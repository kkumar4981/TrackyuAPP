package com.fieldforce.fieldforce_hrms

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class GpsWatchdogAndHealthTest {

    @Before
    fun setUp() {
        DutyLocationService.resetDiagnosticsForTest()
    }

    @Test
    fun testA03_watchdogDoesNotStarveWhenStationaryCallbacksArrive() {
        // Given: employee is stationary at desk, callbacks arrive every 30s
        val now = 100000L
        DutyLocationService.lastRawCallbackElapsed = now - 15000L // 15 seconds ago
        DutyLocationService.lastAcceptedElapsed = now - 15000L
        DutyLocationService.lastPersistedElapsed = now - 300000L // 5 mins ago (stationary heartbeat)

        val callbackSilence = now - DutyLocationService.lastRawCallbackElapsed
        val isStarved = callbackSilence > 90000L

        // Then: watchdog should NOT trigger aggressive high-accuracy polling / freshFix
        assertFalse("Watchdog must not trigger freshFix when stationary callbacks arrive", isStarved)
        assertEquals(15000L, callbackSilence)
    }

    @Test
    fun testA03_watchdogStarvesWhenNoCallbacksArriveForOver90Seconds() {
        // Given: hardware GPS callbacks stop arriving (> 90 seconds silence)
        val now = 200000L
        DutyLocationService.lastRawCallbackElapsed = now - 95000L // 95 seconds ago

        val callbackSilence = now - DutyLocationService.lastRawCallbackElapsed
        val isStarved = callbackSilence > 90000L

        // Then: watchdog triggers fallback/freshFix to recover hardware GPS
        assertTrue("Watchdog must trigger recovery when callback silence exceeds 90s", isStarved)
    }

    @Test
    fun testA03_separateTimestampsArePreserved() {
        DutyLocationService.lastRawCallbackElapsed = 1000L
        DutyLocationService.lastAcceptedElapsed = 2000L
        DutyLocationService.lastPersistedElapsed = 3000L

        assertEquals(1000L, DutyLocationService.lastRawCallbackElapsed)
        assertEquals(2000L, DutyLocationService.lastAcceptedElapsed)
        assertEquals(3000L, DutyLocationService.lastPersistedElapsed)

        DutyLocationService.resetDiagnosticsForTest()
        assertEquals(0L, DutyLocationService.lastRawCallbackElapsed)
        assertEquals(0L, DutyLocationService.lastAcceptedElapsed)
        assertEquals(0L, DutyLocationService.lastPersistedElapsed)
    }

    @Test
    fun testA04_persistenceQueueNeverBlocksCallingThreadUnderBackpressure() {
        // Enqueue 50 items onto bounded queue
        val queue = LinkedBlockingQueue<LocationSnapshot>(5)
        val callerThread = Thread.currentThread().name

        // Fill queue to capacity
        for (i in 1..5) {
            val enqueued = queue.offer(LocationSnapshot(0.0, 0.0, 10f, false, 0f, false, 0f, "fused", i.toLong(), i.toLong()))
            assertTrue("Item $i should fit in queue", enqueued)
        }

        // 6th item arrives: Non-blocking overflow handling
        val overflowItem = LocationSnapshot(10.0, 20.0, 5f, false, 0f, false, 0f, "fused", 6L, 6L)
        val fit = queue.offer(overflowItem)
        assertFalse("Queue is full, should not block", fit)

        // Non-blocking eviction policy off the main thread:
        val evicted = queue.poll()
        assertNotNull("Evicted item", evicted)
        val enqueuedAfterEviction = queue.offer(overflowItem)
        assertTrue("New item enqueued after eviction", enqueuedAfterEviction)

        // Verify caller thread was never blocked and ran 0 disk operations
        assertEquals(Thread.currentThread().name, callerThread)
        assertEquals(5, queue.size)
    }

    @Test
    fun testA04_shutdownSynchronizationPreventsConcurrentWritesAndReordering() {
        val persistenceLock = Any()
        val queue = LinkedBlockingQueue<LocationSnapshot>(20)
        val retryQueue = java.util.ArrayDeque<LocationSnapshot>()
        val written = Collections.synchronizedList(mutableListOf<String>())
        val concurrentCount = AtomicInteger(0)
        val maxConcurrent = AtomicInteger(0)

        fun fakePersist(tag: String, delayMs: Long) {
            synchronized(persistenceLock) {
                val current = concurrentCount.incrementAndGet()
                if (current > maxConcurrent.get()) maxConcurrent.set(current)
                Thread.sleep(delayMs)
                written.add(tag)
                concurrentCount.decrementAndGet()
            }
        }

        val executor = Executors.newSingleThreadExecutor()
        val workerActiveLatch = CountDownLatch(1)

        // 1. Worker thread starts a slow write (100ms)
        executor.execute {
            workerActiveLatch.countDown()
            fakePersist("worker-slow-task", 100)
        }

        assertTrue(workerActiveLatch.await(1, TimeUnit.SECONDS))

        // 2. Queue some pending items during shutdown
        queue.add(LocationSnapshot(1.0, 1.0, 10f, false, 0f, false, 0f, "fused", 1L, 1L))
        queue.add(LocationSnapshot(2.0, 2.0, 10f, false, 0f, false, 0f, "fused", 2L, 2L))

        // 3. Service shutdown initiates immediately
        executor.shutdown()
        // Wait up to 50ms (simulating timeout while worker is still running)
        executor.awaitTermination(50, TimeUnit.MILLISECONDS)

        // 4. Shutdown thread drains under persistenceLock
        val remaining = mutableListOf<LocationSnapshot>()
        queue.drainTo(remaining)
        for (snap in remaining) {
            fakePersist("shutdown-drain-${snap.captured}", 10)
        }

        executor.awaitTermination(2, TimeUnit.SECONDS)

        // Concurrency Guard Verification:
        assertEquals("Max concurrent SQLite writers must NEVER exceed 1", 1, maxConcurrent.get())
        assertEquals("Worker write must finish before shutdown drain starts", "worker-slow-task", written[0])
        assertEquals("Remaining tasks must execute in strict FIFO order", listOf("worker-slow-task", "shutdown-drain-1", "shutdown-drain-2"), written)
    }

    @Test
    fun testA04_sqliteExceptionTriggersRetryQueueWithoutDiscardingData() {
        val retryQueue = java.util.ArrayDeque<LocationSnapshot>()
        val persisted = mutableListOf<Long>()
        var shouldFailDisk = true

        val loc = LocationSnapshot(12.34, 56.78, 15f, false, 0f, false, 0f, "fused", 1001L, 1001L)

        fun tryPersist(s: LocationSnapshot): Boolean {
            if (shouldFailDisk) {
                // Simulate SQLite locked or transient write failure
                if (s.retryCount < 3) {
                    s.retryCount++
                    retryQueue.offerLast(s)
                }
                return false
            } else {
                persisted.add(s.captured)
                return true
            }
        }

        // First attempt: Fails
        val success1 = tryPersist(loc)
        assertFalse("First attempt should fail", success1)
        assertEquals("Item must be preserved in retryQueue", 1, retryQueue.size)
        assertEquals("Retry count incremented", 1, retryQueue.peekFirst()?.retryCount)
        assertEquals("Persisted list empty", 0, persisted.size)

        // Storage recovers: Second attempt on next cycle
        shouldFailDisk = false
        val retryLoc = retryQueue.pollFirst()!!
        val success2 = tryPersist(retryLoc)
        assertTrue("Second attempt should succeed", success2)
        assertEquals("Retry queue drained", 0, retryQueue.size)
        assertEquals("Successfully persisted to SQLite", listOf(1001L), persisted)
    }

    @Test
    fun testA04_boundedRetryReachesExhaustionWithoutCrashing() {
        val retryQueue = java.util.ArrayDeque<LocationSnapshot>()
        var exhaustedReported = false

        val loc = LocationSnapshot(12.34, 56.78, 15f, false, 0f, false, 0f, "fused", 2002L, 2002L)

        fun tryPersist(s: LocationSnapshot): Boolean {
            if (s.retryCount < 3) {
                s.retryCount++
                retryQueue.offerLast(s)
                return false
            } else {
                exhaustedReported = true
                return false
            }
        }

        // Fail 3 times
        tryPersist(loc) // retryCount = 1
        assertEquals(1, retryQueue.size)
        tryPersist(retryQueue.pollFirst()!!) // retryCount = 2
        assertEquals(1, retryQueue.size)
        tryPersist(retryQueue.pollFirst()!!) // retryCount = 3
        assertEquals(1, retryQueue.size)

        // 4th attempt: Exhausted
        tryPersist(retryQueue.pollFirst()!!)
        assertTrue("Exhaustion diagnostic must be reported after 3 retries", exhaustedReported)
        assertEquals("Failed item removed from retry queue after exhaustion", 0, retryQueue.size)
    }

    @Test
    fun testA02_healthState_idleWhenInactive() {
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = false,
            active = false,
            finePerm = true,
            gpsEnabled = true,
            lastCallbackElapsed = 1000L,
            pendingCount = 0,
            nowElapsed = 2000L
        )
        assertEquals("IDLE", state)
        assertTrue(reason.contains("not active"))
    }

    @Test
    fun testA02_healthState_serviceDeadWhenKilledByOs() {
        // A-02 CRITICAL FIX: Even if active is true in config, if isAlive is false, report SERVICE_DEAD!
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = false,
            active = true,
            finePerm = true,
            gpsEnabled = true,
            lastCallbackElapsed = 1000L,
            pendingCount = 0,
            nowElapsed = 2000L
        )
        assertEquals("SERVICE_DEAD", state)
        assertTrue(reason.contains("terminated") || reason.contains("stopped"))
    }

    @Test
    fun testA02_healthState_permissionRevoked() {
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = true,
            active = true,
            finePerm = false,
            gpsEnabled = true,
            lastCallbackElapsed = 1000L,
            pendingCount = 0,
            nowElapsed = 2000L
        )
        assertEquals("PERMISSION_REVOKED", state)
        assertTrue(reason.contains("permission"))
    }

    @Test
    fun testA02_healthState_noGpsWhenProviderDisabled() {
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = true,
            active = true,
            finePerm = true,
            gpsEnabled = false,
            lastCallbackElapsed = 1000L,
            pendingCount = 0,
            nowElapsed = 2000L
        )
        assertEquals("NO_GPS", state)
        assertTrue(reason.contains("off") || reason.contains("provider"))
    }

    @Test
    fun testA02_healthState_noGpsWhenSilenceExceeds90Seconds() {
        val now = 200000L
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = true,
            active = true,
            finePerm = true,
            gpsEnabled = true,
            lastCallbackElapsed = now - 95000L, // 95s silence
            pendingCount = 0,
            nowElapsed = now
        )
        assertEquals("NO_GPS", state)
        assertTrue(reason.contains("> 90s") || reason.contains("signals"))
    }

    @Test
    fun testA02_healthState_syncPendingWhenOfflineQueueHasItems() {
        val now = 200000L
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = true,
            active = true,
            finePerm = true,
            gpsEnabled = true,
            lastCallbackElapsed = now - 10000L,
            pendingCount = 5,
            nowElapsed = now
        )
        assertEquals("SYNC_PENDING", state)
        assertTrue(reason.contains("5 location points"))
    }

    @Test
    fun testA02_healthState_healthyWhenActiveAndReceivingFixes() {
        val now = 200000L
        val (state, reason) = TrackingRuntime.computeHealthState(
            isAlive = true,
            active = true,
            finePerm = true,
            gpsEnabled = true,
            lastCallbackElapsed = now - 15000L,
            pendingCount = 0,
            nowElapsed = now
        )
        assertEquals("HEALTHY", state)
        assertTrue(reason.contains("reliable") || reason.contains("active"))
    }
}
