package net.hideip.vpn

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter <-> the native VpnService.
 *
 * Channel: net.hideip.vpn/control
 *   prepare() -> asks the OS for VPN consent if needed; returns true when ready
 *   start(config) -> launches HideipVpnService with the sing-box config JSON
 *   stop() -> stops the tunnel
 *   status() -> {running, error}
 */
class MainActivity : FlutterActivity() {

    private val channelName = "net.hideip.vpn/control"
    private val reqVpnConsent = 7001
    private val reqPostNotifications = 7002
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> handlePrepare(result)
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("no_config", "config is required", null)
                        } else {
                            val intent = Intent(this, HideipVpnService::class.java).apply {
                                action = HideipVpnService.ACTION_START
                                putExtra(HideipVpnService.EXTRA_CONFIG, config)
                                putExtra(
                                    HideipVpnService.EXTRA_LABEL,
                                    call.argument<String>("label"),
                                )
                            }
                            startForegroundService(intent)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        val intent = Intent(this, HideipVpnService::class.java).apply {
                            action = HideipVpnService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "status" -> {
                        result.success(
                            mapOf(
                                "running" to HideipVpnService.running,
                                "error" to HideipVpnService.lastError
                            )
                        )
                    }
                    "stats" -> {
                        result.success(
                            mapOf(
                                "uplink" to HideipVpnService.uplink,
                                "downlink" to HideipVpnService.downlink,
                                "uplinkTotal" to HideipVpnService.uplinkTotal,
                                "downlinkTotal" to HideipVpnService.downlinkTotal
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handlePrepare(result: MethodChannel.Result) {
        // Android 13+ requires a runtime grant for the ongoing VPN notification.
        // It is a soft dependency: if the user declines, the tunnel still runs,
        // only the persistent "Connected" notification is suppressed by the OS.
        // So we ask fire-and-forget and never block the connection on its outcome.
        ensureNotificationPermission()

        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Need user consent; remember the result to resolve after the dialog.
            pendingResult = result
            startActivityForResult(intent, reqVpnConsent)
        } else {
            result.success(true)
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                reqPostNotifications,
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqVpnConsent) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        }
    }
}
