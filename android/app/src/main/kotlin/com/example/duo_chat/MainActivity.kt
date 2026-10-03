package com.example.duo_chat

import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VIBRATOR_CHANNEL = "duochat/vibrator"
    private val SCANNER_CHANNEL = "duo_chat/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Vibrator channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager =
                        getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vibratorManager?.defaultVibrator
                        ?: (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }

                when (call.method) {
                    "vibrate" -> {
                        val duration = (call.argument<Number>("duration") ?: 100).toLong()
                        if (vibrator != null && vibrator.hasVibrator()) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(
                                    VibrationEffect.createOneShot(
                                        duration, VibrationEffect.DEFAULT_AMPLITUDE
                                    )
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(duration)
                            }
                        }
                        result.success(true)
                    }
                    "vibratePattern" -> {
                        val patternList = call.argument<List<Number>>("pattern")
                        if (vibrator != null && vibrator.hasVibrator() && patternList != null) {
                            val pattern = patternList.map { it.toLong() }.toLongArray()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(pattern, -1)
                            }
                        }
                        result.success(true)
                    }
                    "cancel" -> {
                        vibrator?.cancel()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── MediaScanner channel ──────────────────────────────────────────────
        // Called exclusively from _saveImageToGallery() when the user taps the
        // explicit "Save to Gallery" button.  Triggers MediaScannerConnection
        // so the saved file appears in the system Gallery immediately.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                null  // let the scanner infer MIME type
                            ) { _, _ ->
                                // Callback fires on a background thread; result
                                // must be called on the platform thread.
                                runOnUiThread { result.success(null) }
                            }
                        } else {
                            result.error("INVALID_ARG", "'path' argument is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
