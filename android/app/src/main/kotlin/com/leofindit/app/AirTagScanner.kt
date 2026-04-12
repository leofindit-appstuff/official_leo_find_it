package com.leofindit.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.security.MessageDigest
import kotlin.math.pow

class AirTagScanner(
    private val context: Context,
    private val onTrackerUpdate: (DetectedTracker) -> Unit
) {

    companion object {
        private const val TAG = "AirTagScanner"

        private const val APPLE_MFG_ID = 0x004C
        private val FIND_MY_UUID =
            ParcelUuid.fromString("0000FD44-0000-1000-8000-00805F9B34FB")
        private const val STABLE_PREFIX_LEN = 4
        private const val TRACKER_TTL_MS = 20_000L
    }

    enum class TrackerKind {
        AIRTAG,
        FIND_MY,
        TILE,
        SAMSUNG,
        APPLE_DEVICE,
        UNKNOWN
    }

    data class DetectedTracker(
        val id: String,
        val logicalId: String,
        val kind: TrackerKind,
        val address: String?,
        val rssi: Int,
        val distanceMeters: Double,
        val lastSeenMs: Long,
        val signature: String,
        val rawFrame: String,
        val rotatingMacCount: Int
    )

    private data class TrackerState(
        val signature: String,
        var kind: TrackerKind,
        var lastRssi: Int,
        var lastSeenMs: Long,
        var rawFrame: String,
        var lastMac: String?,
        var rotatingMacCount: Int
    )

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        mgr.adapter
    }

    private val scanner get() = bluetoothAdapter?.bluetoothLeScanner
    private val trackers = mutableMapOf<String, TrackerState>()

    private var scanning = false

    fun start() {
        if (scanning || bluetoothAdapter?.isEnabled != true) return
        try {
            scanning = true
            scanner?.startScan(null, buildSettings(), callback)
            Log.i(TAG, "Apple Find My scan started")
        } catch (e: SecurityException) {
            scanning = false
            Log.w(TAG, "BLE scan blocked", e)
        }
    }

    fun stop() {
        if (!scanning) return
        try {
            scanner?.stopScan(callback)
        } catch (_: SecurityException) {
        }
        scanning = false
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(type: Int, result: ScanResult) = handle(result)

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { handle(it) }
        }
    }

    private fun handle(result: ScanResult) {
        val record = result.scanRecord ?: return
        val bytes = record.bytes ?: return
        val now = System.currentTimeMillis()

        val fd44 = record.serviceData[FIND_MY_UUID]
        val appleMfg = record.manufacturerSpecificData.get(APPLE_MFG_ID)
        val rawHex = bytes.toHex()

        Log.d(
            TAG,
            "Apple scan candidate fd44=${fd44?.joinToString("") { "%02x".format(it) }} " +
                    "appleMfg=${appleMfg?.joinToString("") { "%02x".format(it) }} " +
                    "raw=$rawHex mac=${result.device?.address} rssi=${result.rssi} connectable=${result.isConnectable}"
        )

        val trackerKind = classifyAppleTracker(fd44, appleMfg, result) ?: return

        trackers.entries.removeIf {
            now - it.value.lastSeenMs > TRACKER_TTL_MS
        }

        val stableSource = when {
            fd44 != null && fd44.size >= STABLE_PREFIX_LEN ->
                fd44.copyOfRange(0, STABLE_PREFIX_LEN)

            appleMfg != null && appleMfg.size >= STABLE_PREFIX_LEN ->
                appleMfg.copyOfRange(0, STABLE_PREFIX_LEN)

            else -> return
        }

        val signature = sha1(stableSource)
        val mac = result.device?.address
        val rssi = result.rssi

        val state = trackers.getOrPut(signature) {
            TrackerState(
                signature = signature,
                kind = trackerKind,
                lastRssi = rssi,
                lastSeenMs = now,
                rawFrame = rawHex,
                lastMac = mac,
                rotatingMacCount = if (mac.isNullOrBlank()) 0 else 1
            )
        }

        if (!mac.isNullOrBlank() && mac != state.lastMac) {
            state.lastMac = mac
            state.rotatingMacCount += 1
        }

        state.lastSeenMs = now
        state.lastRssi = rssi
        state.rawFrame = rawHex

        if (state.kind != TrackerKind.AIRTAG && trackerKind == TrackerKind.FIND_MY) {
            state.kind = TrackerKind.FIND_MY
        }

        if (
            state.kind == TrackerKind.FIND_MY &&
            state.rotatingMacCount >= 4 &&
            !state.lastMac.isNullOrBlank() &&
            looksLikeAirTagFrame(state.rawFrame)
        ) {
            state.kind = TrackerKind.AIRTAG
        }

        Log.d(
            TAG,
            "classified kind=${state.kind} sig=$signature mac=$mac rotations=${state.rotatingMacCount} raw=$rawHex"
        )

        val kindPrefix = when (state.kind) {
            TrackerKind.AIRTAG -> "AIRTAG"
            TrackerKind.FIND_MY -> "FINDMY"
            else -> "APPLE"
        }

        onTrackerUpdate(
            DetectedTracker(
                id = "${kindPrefix}_$signature",
                logicalId = "${kindPrefix}_$signature",
                kind = state.kind,
                address = mac,
                rssi = rssi,
                distanceMeters = estimateDistance(rssi),
                lastSeenMs = now,
                signature = signature,
                rawFrame = rawHex,
                rotatingMacCount = state.rotatingMacCount
            )
        )
    }

    private fun classifyAppleTracker(
        fd44: ByteArray?,
        appleMfg: ByteArray?,
        result: ScanResult
    ): TrackerKind? {
        val hasFindMy = fd44 != null
        val mfg = appleMfg

        val deviceName = result.scanRecord?.deviceName ?: ""
        val isConnectable = result.isConnectable

        if (deviceName.isNotBlank()) {
            return null
        }

        if (mfg != null && mfg.size >= 3) {
            val b0 = mfg[0].toInt() and 0xFF
            val b1 = mfg[1].toInt() and 0xFF
            val b2 = mfg[2].toInt() and 0xFF
            val b3 = if (mfg.size > 3) mfg[3].toInt() and 0xFF else -1

            if (b0 == 0x12 && b1 == 0x19 && b2 == 0x10) {
                return TrackerKind.FIND_MY
            }

            if (b0 == 0x12 && b1 == 0x02 && b2 == 0x00 && (b3 == 0x00 || b3 == 0x01)) {
                return if (hasFindMy || !isConnectable) TrackerKind.FIND_MY else null
            }

            if (b0 == 0x12 && b1 == 0x19 && b2 == 0x20) {
                return TrackerKind.FIND_MY
            }

            if (mfg.size in 18..32 && !isConnectable) {
                return TrackerKind.FIND_MY
            }
        }

        if (hasFindMy) {
            return TrackerKind.FIND_MY
        }

        return null
    }

    private fun looksLikeAirTagFrame(rawHex: String): Boolean {
        val lower = rawHex.lowercase()
        return lower.contains("4c00121920")
    }

    private fun buildSettings(): ScanSettings =
        ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setReportDelay(0L)
            .build()

    private fun estimateDistance(rssi: Int, txPower: Int = -59): Double {
        val ratio = (txPower - rssi) / (10.0 * 2.0)
        return 10.0.pow(ratio)
    }

    private fun sha1(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-1")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }
}