package com.fieldforce.fieldforce_hrms

import android.content.Context
import android.content.ContextWrapper
import androidx.work.Configuration
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

class MockTrackingContext : ContextWrapper(null), Configuration.Provider {
    private val stubResources: android.content.res.Resources = try {
        val ctor = android.content.res.Resources::class.java.declaredConstructors.first()
        ctor.isAccessible = true
        val args = arrayOfNulls<Any>(ctor.parameterCount)
        ctor.newInstance(*args) as android.content.res.Resources
    } catch (_: Throwable) {
        android.content.res.Resources(null, null, null)
    }

    override fun getApplicationContext(): Context = this
    override fun getPackageName(): String = "com.fieldforce.fieldforce_hrms"
    override fun getSystemService(name: String): Any? = null
    override fun getResources(): android.content.res.Resources = stubResources
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.DEBUG)
            .build()
}

class TrackingRuntimeCutoffTest {
    private lateinit var fakePrefs: FakeSharedPreferences
    private lateinit var crypto: TestCryptoProvider
    private lateinit var store: TrackingStore
    private lateinit var dummyContext: Context

    @Before
    fun setUp() {
        val testCtx = MockTrackingContext()
        dummyContext = testCtx
        try {
            WorkManagerTestInitHelper.initializeTestWorkManager(testCtx)
        } catch (_: Throwable) {
            try {
                WorkManager.initialize(testCtx, testCtx.workManagerConfiguration)
            } catch (_: Throwable) {}
        }
        fakePrefs = FakeSharedPreferences()
        crypto = TestCryptoProvider()
        store = TrackingStore(dummyContext, "test_duty.db")
        store.testPrefs = fakePrefs
        store.cryptoProvider = crypto
        TrackingRuntime.instance = store
    }

    @Test
    fun testCutoffAnchor_anchorsToPunchInUtcOnInitialConfigure() {
        val punchInTime = "2026-11-17T04:30:00Z"
        val serverTime = "2026-11-17T05:00:00Z"
        val expectedPunchInMs = Instant.parse(punchInTime).toEpochMilli()

        val config = JSONObject().apply {
            put("baseUrl", "https://example.com/api")
            put("offlineLocal", true)
            put("active", true)
            put("userId", "SM488")
            put("attendanceId", 77L)
            put("mode", "Field")
            put("serverTimeUtc", serverTime)
            put("punchInUtc", punchInTime)
        }

        TrackingRuntime.configure(dummyContext, config)

        val saved = store.config()
        assertEquals("dutyStartUtc must be anchored to punchInUtc", expectedPunchInMs, saved.getLong("dutyStartUtc"))
    }

    @Test
    fun testCutoffAnchor_remainsImmutableAcrossLeaseRenewals() {
        val punchInTime = "2026-11-17T04:30:00Z"
        val initialServerTime = "2026-11-17T04:30:00Z"
        val expectedPunchInMs = Instant.parse(punchInTime).toEpochMilli()

        val initialConfig = JSONObject().apply {
            put("baseUrl", "https://example.com/api")
            put("offlineLocal", true)
            put("active", true)
            put("userId", "SM488")
            put("attendanceId", 77L)
            put("mode", "Field")
            put("serverTimeUtc", initialServerTime)
            put("punchInUtc", punchInTime)
        }
        TrackingRuntime.configure(dummyContext, initialConfig)
        assertEquals(expectedPunchInMs, store.config().getLong("dutyStartUtc"))

        // Simulate subsequent lease renewal hours later with new server clock
        val renewalServerTime = "2026-11-17T16:00:00Z"
        val renewalConfig = JSONObject().apply {
            put("baseUrl", "https://example.com/api")
            put("offlineLocal", true)
            put("active", true)
            put("userId", "SM488")
            put("attendanceId", 77L)
            put("mode", "Field")
            put("serverTimeUtc", renewalServerTime)
            put("punchInUtc", punchInTime)
        }
        TrackingRuntime.configure(dummyContext, renewalConfig)

        val renewed = store.config()
        assertEquals("dutyStartUtc must NOT drift to renewed serverTimeUtc", expectedPunchInMs, renewed.getLong("dutyStartUtc"))
    }

    @Test
    fun testCutoffAnchor_retainedAcrossProcessRecreation() {
        val punchInTime = "2026-11-17T04:30:00Z"
        val expectedPunchInMs = Instant.parse(punchInTime).toEpochMilli()

        val initialConfig = JSONObject().apply {
            put("baseUrl", "https://example.com/api")
            put("offlineLocal", true)
            put("active", true)
            put("userId", "SM488")
            put("attendanceId", 77L)
            put("mode", "Field")
            put("serverTimeUtc", "2026-11-17T04:30:00Z")
            put("punchInUtc", punchInTime)
        }
        TrackingRuntime.configure(dummyContext, initialConfig)

        // Simulate process termination and recreation: clear memory caches & runtime instance
        store.clearMemoryCache()
        TrackingRuntime.instance = null

        // New store instance backed by same preferences
        val recreatedStore = TrackingStore(dummyContext, "test_duty.db")
        recreatedStore.testPrefs = fakePrefs
        recreatedStore.cryptoProvider = crypto
        TrackingRuntime.instance = recreatedStore

        val reloaded = recreatedStore.config()
        assertEquals("dutyStartUtc must survive process recreation", expectedPunchInMs, reloaded.getLong("dutyStartUtc"))
    }

    @Test
    fun testReceiptGuard_rejectsInvalidAttendanceReceiptBeforeTransaction() {
        val op = JSONObject().apply {
            put("id", "op-att-001")
            put("route", "FieldAttendance/punch-in")
            put("body", JSONObject().put("lat", 19.0).toString())
        }

        // Receipt with missing / invalid ID
        val invalidReceipt = JSONObject().apply {
            put("id", 0L)
            put("success", true)
        }

        try {
            store.localAck("test-scope", op, invalidReceipt)
            fail("localAck must throw IllegalStateException on attendance receipt with id <= 0")
        } catch (e: IllegalStateException) {
            assertTrue("Exception message must detail invalid receipt", e.message!!.contains("missing valid server id"))
        }
    }

    @Test
    fun testReceiptGuard_rejectsInvalidVisitReceiptBeforeTransaction() {
        val op = JSONObject().apply {
            put("id", "op-visit-002")
            put("route", "MobileVisits/checkout")
            put("body", JSONObject().put("visitId", 123).toString())
        }

        val invalidReceipt = JSONObject().apply {
            put("id", -1L)
        }

        try {
            store.localAck("test-scope", op, invalidReceipt)
            fail("localAck must throw IllegalStateException on visit receipt with id <= 0")
        } catch (e: IllegalStateException) {
            assertTrue(e.message!!.contains("missing valid server id"))
        }
    }
}
