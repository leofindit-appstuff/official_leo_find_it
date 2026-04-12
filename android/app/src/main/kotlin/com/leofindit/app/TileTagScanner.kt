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

// Non-Apple tracker scanner (Tile)
// Goals:
// - Stable logical identity
// - Fewer phantom Samsung devices
// - TTL eviction
// - Better duplicate suppression
// - MAC rotation tolerance

class TileTagScanner(
    context: Context,
    private val onTrackerUpdate: (AirTagScanner.DetectedTracker) -> Unit
) {

    companion object {
        private const val TAG = "TileTagScanner"

        private const val TILE_MFG_ID = 0x0131

        private val TILE_UUIDS = setOf(
            ParcelUuid.fromString("0000FEED-0000-1000-8000-00805F9B34FB"),
            ParcelUuid.fromString("0000FEE7-0000-1000-8000-00805F9B34FB")
        )

        private const val TILE_STABLE_PREFIX_LEN = 4
        private const val TRACKER_TTL_MS = 30_000L
    }

    private data class TrackerState(
        val signature: String,
        var lastMac: String?,
        var rotatingMacCount: Int,
        var lastSeenMs: Long,
        var lastRssi: Int,
        var rawFrame: String
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
            Log.i(TAG, "Tile scan started")
        } catch (e: SecurityException) {
            scanning = false
            Log.w(TAG, "Tile scan blocked", e)
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

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed errorCode=$errorCode")
        }
    }

    private fun handle(result: ScanResult) {
        val record = result.scanRecord ?: return
        val bytes = record.bytes ?: return
        val now = System.currentTimeMillis()

        val tileMfg = record.manufacturerSpecificData.get(TILE_MFG_ID)
        if (!isTileFrame(record, tileMfg)) return

        trackers.entries.removeIf { now - it.value.lastSeenMs > TRACKER_TTL_MS }

        val identitySource = getTileIdentitySource(record, tileMfg) ?: return
        val stablePart = identitySource.copyOfRange(
            0,
            minOf(TILE_STABLE_PREFIX_LEN, identitySource.size)
        )

        val signature = sha1(stablePart)
        val mac = result.device?.address
        val rssi = result.rssi
        val rawFrameHex = bytes.toHex()

        val state = trackers.getOrPut(signature) {
            TrackerState(
                signature = signature,
                lastMac = mac,
                rotatingMacCount = if (mac.isNullOrBlank()) 0 else 1,
                lastSeenMs = now,
                lastRssi = rssi,
                rawFrame = rawFrameHex
            )
        }

        if (!mac.isNullOrBlank() && mac != state.lastMac) {
            state.lastMac = mac
            state.rotatingMacCount += 1
        }

        state.lastSeenMs = now
        state.lastRssi = rssi
        state.rawFrame = rawFrameHex

        Log.d(
            TAG,
            "TILE_ACCEPTED sig=$signature mac=$mac rssi=$rssi rotMacs=${state.rotatingMacCount}"
        )

        onTrackerUpdate(
            AirTagScanner.DetectedTracker(
                id = "TILE_$signature",
                logicalId = "TILE_$signature",
                kind = AirTagScanner.TrackerKind.TILE,
                address = mac,
                rssi = rssi,
                distanceMeters = estimateDistance(rssi),
                lastSeenMs = now,
                signature = signature,
                rawFrame = rawFrameHex,
                rotatingMacCount = state.rotatingMacCount
            )
        )
    }

    private fun isTileFrame(
        record: android.bluetooth.le.ScanRecord,
        tileMfg: ByteArray?
    ): Boolean {
        return tileMfg != null || record.serviceUuids?.any { it in TILE_UUIDS } == true
    }

    private fun getTileIdentitySource(
        record: android.bluetooth.le.ScanRecord,
        tileMfg: ByteArray?
    ): ByteArray? {
        return when {
            tileMfg != null -> tileMfg
            record.serviceData.isNotEmpty() -> record.serviceData.values.first()
            else -> null
        }
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