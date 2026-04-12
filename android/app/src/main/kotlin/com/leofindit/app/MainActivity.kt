package com.leofindit.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_REQUEST = 6001
        private const val SCAN_CHANNEL = "leo_find_it/scanner"
        private const val STORAGE_CHANNEL = "leo_find_it/storage"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var scanActive = false

    private var airTagScanner: AirTagScanner? = null
    private var tileTagScanner: TileTagScanner? = null
    private var samsungTagScanner: SamsungTagScanner? = null
    private var scanChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        scanChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN_CHANNEL)
        scanChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> {
                    if (!hasBlePermissions()) {
                        requestBlePermissions()
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    if (!isLocationEnabled()) {
                        result.error(
                            "LOCATION_DISABLED",
                            "Location services must be enabled to scan for trackers",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    initScannersIfNeeded()
                    startScanners()
                    result.success(true)
                }

                "stopScan" -> {
                    stopScanners()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName") ?: "leo_report.json"
                        val mime = call.argument<String>("mimeType") ?: "application/json"
                        val content = call.argument<String>("content") ?: ""

                        try {
                            val uriString = saveTextToDownloads(fileName, mime, content)
                            result.success(uriString)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "deleteFromDownloads" -> {
                        val uriString = call.argument<String>("uri") ?: ""
                        try {
                            val ok = deleteFromDownloads(uriString)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopScanners()
        super.onDestroy()
    }

    private val scanRefreshRunnable = object : Runnable {
        override fun run() {
            if (!scanActive) return
            restartScanners()
            mainHandler.postDelayed(this, 120_000L)
        }
    }

    private fun initScannersIfNeeded() {
        if (airTagScanner != null && tileTagScanner != null && samsungTagScanner != null) return

        airTagScanner = AirTagScanner(this) { tracker ->
            sendToFlutter(tracker)
        }

        tileTagScanner = TileTagScanner(this) { tracker ->
            sendToFlutter(tracker)
        }

        samsungTagScanner = SamsungTagScanner(this) { tracker ->
            sendToFlutter(tracker)
        }
    }

    private fun startScanners() {
        scanActive = true
        mainHandler.removeCallbacks(scanRefreshRunnable)
        airTagScanner?.start()
        tileTagScanner?.start()
        samsungTagScanner?.start()
        mainHandler.postDelayed(scanRefreshRunnable, 120_000L)
    }

    private fun restartScanners() {
        airTagScanner?.stop()
        tileTagScanner?.stop()
        samsungTagScanner?.stop()
        airTagScanner?.start()
        tileTagScanner?.start()
        samsungTagScanner?.start()
    }

    private fun stopScanners() {
        scanActive = false
        mainHandler.removeCallbacks(scanRefreshRunnable)
        airTagScanner?.stop()
        tileTagScanner?.stop()
        samsungTagScanner?.stop()
    }

    private fun hasBlePermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) ==
                    PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                    PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBlePermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT
                ),
                PERMISSION_REQUEST
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                PERMISSION_REQUEST
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != PERMISSION_REQUEST) return

        val granted = grantResults.isNotEmpty() && grantResults.all {
            it == PackageManager.PERMISSION_GRANTED
        }

        if (!granted) return
        if (!isLocationEnabled()) return

        initScannersIfNeeded()
    }

    private fun isLocationEnabled(): Boolean {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun sendToFlutter(tracker: AirTagScanner.DetectedTracker) {
        val payload = mapOf(
            "id" to tracker.id,
            "logicalId" to tracker.logicalId,
            "address" to tracker.address,
            "mac" to (tracker.address ?: ""),
            "kind" to tracker.kind.name,
            "rssi" to tracker.rssi,
            "distanceMeters" to tracker.distanceMeters,
            "lastSeenMs" to tracker.lastSeenMs,
            "signature" to tracker.signature,
            "rawFrame" to tracker.rawFrame,
            "rotatingMacCount" to tracker.rotatingMacCount
        )

        mainHandler.post {
            scanChannel?.invokeMethod("onDevice", payload)
        }
    }

    private fun saveTextToDownloads(
        fileName: String,
        mimeType: String,
        content: String
    ): String {
        val resolver = applicationContext.contentResolver

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/LEOFindIt")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        }

        val collection: Uri = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val itemUri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Failed to create downloads entry")

        var out: OutputStream? = null
        try {
            out = resolver.openOutputStream(itemUri)
                ?: throw IllegalStateException("Failed to open output stream")
            out.write(content.toByteArray(Charsets.UTF_8))
            out.flush()
        } finally {
            try {
                out?.close()
            } catch (_: Exception) {
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }
            resolver.update(itemUri, done, null, null)
        }

        return itemUri.toString()
    }

    private fun deleteFromDownloads(uriString: String): Boolean {
        if (uriString.isBlank()) return false
        val resolver = applicationContext.contentResolver
        val uri = Uri.parse(uriString)
        return resolver.delete(uri, null, null) > 0
    }
}