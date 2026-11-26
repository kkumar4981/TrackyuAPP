package com.fieldforce.fieldforce_hrms

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.security.KeyStoreException

class FakeSharedPreferences : SharedPreferences {
    val store = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = HashMap(store)
    override fun getString(key: String?, defValue: String?): String? = (store[key] as? String) ?: defValue
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = (store[key] as? MutableSet<String>) ?: defValues
    override fun getInt(key: String?, defValue: Int): Int = (store[key] as? Int) ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = (store[key] as? Long) ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = (store[key] as? Float) ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = (store[key] as? Boolean) ?: defValue
    override fun contains(key: String?): Boolean = store.containsKey(key)
    override fun edit(): SharedPreferences.Editor = FakeEditor(this)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

    class FakeEditor(private val prefs: FakeSharedPreferences) : SharedPreferences.Editor {
        private val temp = mutableMapOf<String, Any?>()
        private val toRemove = mutableSetOf<String>()
        private var clearFlag = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor { key?.let { temp[it] = value }; return this }
        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor { key?.let { temp[it] = values }; return this }
        override fun putInt(key: String?, value: Int): SharedPreferences.Editor { key?.let { temp[it] = value }; return this }
        override fun putLong(key: String?, value: Long): SharedPreferences.Editor { key?.let { temp[it] = value }; return this }
        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor { key?.let { temp[it] = value }; return this }
        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor { key?.let { temp[it] = value }; return this }
        override fun remove(key: String?): SharedPreferences.Editor { key?.let { toRemove.add(it) }; return this }
        override fun clear(): SharedPreferences.Editor { clearFlag = true; return this }
        override fun commit(): Boolean { apply(); return true }
        override fun apply() {
            if (clearFlag) prefs.store.clear()
            for (k in toRemove) prefs.store.remove(k)
            for ((k, v) in temp) prefs.store[k] = v
        }
    }
}

class TestCryptoProvider : TrackingStore.CryptoProvider {
    var failDecrypt = false
    override fun encrypt(value: String): String = "TEST_CIPHERTEXT:" + value
    override fun decrypt(value: String): String {
        if (failDecrypt) throw KeyStoreException("Keystore locked or transient hardware error")
        if (value.startsWith("TEST_CIPHERTEXT:")) return value.removePrefix("TEST_CIPHERTEXT:")
        throw IllegalArgumentException("Invalid test ciphertext format")
    }
}

class TrackingStoreCryptoTest {
    private lateinit var fakePrefs: FakeSharedPreferences
    private lateinit var crypto: TestCryptoProvider
    private lateinit var store: TrackingStore

    @Before
    fun setup() {
        val dummyContext = ContextWrapper(null)
        fakePrefs = FakeSharedPreferences()
        crypto = TestCryptoProvider()
        store = TrackingStore(dummyContext, "test_duty.db")
        store.testPrefs = fakePrefs
        store.cryptoProvider = crypto
    }

    @Test
    fun state1_unconfiguredStoreReturnsEmptyConfigAndStatus() {
        val cfg = store.config()
        assertTrue(cfg.length() == 0)
        assertEquals(TrackingStore.ConfigStatus.EMPTY, store.configStatus)
        assertFalse(fakePrefs.contains("config"))
    }

    @Test
    fun state2a_validConfigEncryptedAndDecryptedSuccessfully() {
        val original = JSONObject().apply {
            put("active", true)
            put("userId", "EMP_TEST_001")
            put("attendanceId", 501L)
            put("trackingKey", "secret-key-32chars-sample-123456")
        }
        store.saveConfig(original)

        // Verify stored in prefs as encrypted ciphertext
        assertTrue(fakePrefs.contains("config"))
        val raw = fakePrefs.getString("config", null)!!
        assertTrue(raw.startsWith("TEST_CIPHERTEXT:"))
        assertEquals(TrackingStore.ConfigStatus.VALID, store.configStatus)

        // Verify decrypted on read
        val loaded = store.config()
        assertEquals(TrackingStore.ConfigStatus.VALID, store.configStatus)
        assertTrue(loaded.getBoolean("active"))
        assertEquals("EMP_TEST_001", loaded.getString("userId"))
        assertEquals(501L, loaded.getLong("attendanceId"))
    }

    @Test
    fun state2b_intentionalInactiveConfigHasValidStatusNotError() {
        val offDuty = JSONObject().apply {
            put("active", false)
            put("userId", "EMP_TEST_001")
            put("attendanceId", 501L)
        }
        store.saveConfig(offDuty)
        store.clearMemoryCache()

        val loaded = store.config()
        assertEquals(TrackingStore.ConfigStatus.VALID, store.configStatus)
        assertFalse(loaded.getBoolean("active"))
        // Explicitly verifies intentional off-duty is NOT DECRYPT_ERROR
        assertNotEquals(TrackingStore.ConfigStatus.DECRYPT_ERROR, store.configStatus)
    }

    @Test
    fun state3_transientKeystoreFailurePreservesCiphertextAndEntersErrorState() {
        // 1. Save valid active configuration
        val original = JSONObject().apply {
            put("active", true)
            put("userId", "EMP_TEST_001")
            put("trackingKey", "active-key-12345")
        }
        store.saveConfig(original)
        val rawBefore = fakePrefs.getString("config", null)!!

        // 2. Simulate process restart / memory eviction with Keystore locked
        store.clearMemoryCache()
        crypto.failDecrypt = true

        // 3. Attempt config() read while Keystore is unavailable
        val fallback = store.config()

        // 4. VERIFY:
        // A) Ciphertext on disk MUST NOT be deleted!
        assertTrue("Ciphertext must be preserved in SharedPreferences on transient decrypt failure", fakePrefs.contains("config"))
        assertEquals("Ciphertext content must remain completely intact", rawBefore, fakePrefs.getString("config", null))

        // B) Config status must be DECRYPT_ERROR (not EMPTY or VALID)
        assertEquals(TrackingStore.ConfigStatus.DECRYPT_ERROR, store.configStatus)

        // C) Fallback returned is empty JSON without crashing
        assertFalse(fallback.optBoolean("active"))
    }

    @Test
    fun state3_recoveryAfterKeystoreBecomesAvailableRestoresConfiguration() {
        // 1. Active config exists on disk
        val original = JSONObject().apply {
            put("active", true)
            put("userId", "EMP_RECOVERY_002")
            put("attendanceId", 999L)
        }
        store.saveConfig(original)

        // 2. Transient lock happens
        store.clearMemoryCache()
        crypto.failDecrypt = true
        val lockedCfg = store.config()
        assertEquals(TrackingStore.ConfigStatus.DECRYPT_ERROR, store.configStatus)
        assertEquals(0, lockedCfg.length())

        // 3. Keystore unlocks (e.g. user unlocks phone, direct boot completes)
        crypto.failDecrypt = false

        // 4. Next read succeeds transparently without any manual intervention
        val recovered = store.config()
        assertEquals(TrackingStore.ConfigStatus.VALID, store.configStatus)
        assertTrue(recovered.getBoolean("active"))
        assertEquals("EMP_RECOVERY_002", recovered.getString("userId"))
        assertEquals(999L, recovered.getLong("attendanceId"))
    }
}
