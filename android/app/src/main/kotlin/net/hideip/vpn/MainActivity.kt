package net.hideip.vpn

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

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
                                "error" to HideipVpnService.lastError,
                                "alwaysOn" to isSystemAlwaysOn(),
                                "lockdown" to isLockdownEnabled()
                            )
                        )
                    }
                    "setAlwaysOn" -> {
                        // The app-settings opt-in for Always-on support; the
                        // service reads it when the system starts it directly.
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        getSharedPreferences(HideipVpnService.NATIVE_PREFS, MODE_PRIVATE)
                            .edit()
                            .putBoolean(HideipVpnService.KEY_ALWAYS_ON, enabled)
                            .apply()
                        result.success(true)
                    }
                    "setKillSwitch" -> {
                        // The service reads this when the core dies unexpectedly
                        // and decides to reconnect (keeping the TUN up) instead
                        // of tearing the tunnel down.
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        getSharedPreferences(HideipVpnService.NATIVE_PREFS, MODE_PRIVATE)
                            .edit()
                            .putBoolean(HideipVpnService.KEY_KILL_SWITCH, enabled)
                            .apply()
                        result.success(true)
                    }
                    "setSensitiveClipboard" -> setSensitiveClipboard(call, result)
                    "openVpnSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
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

    private fun setSensitiveClipboard(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val text = call.argument<String>("text")
        if (text.isNullOrEmpty()) {
            result.error("no_clipboard_text", "text is required", null)
            return
        }
        val ttlMs = (call.argument<Number>("ttlMs")?.toLong() ?: 60_000L)
            .coerceIn(5_000L, 300_000L)
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val marker = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("hideip.net sensitive value", text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
            putString(CLIP_MARKER, marker)
        }
        clipboard.setPrimaryClip(clip)
        Handler(Looper.getMainLooper()).postDelayed({
            if (clipboard.primaryClipDescription?.extras?.getString(CLIP_MARKER) == marker) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    clipboard.clearPrimaryClip()
                } else {
                    clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                }
            }
        }, ttlMs)
        result.success(true)
    }

    /** Whether Android's system Always-on VPN points at this app. Normal apps
     *  cannot WRITE this (device-owner API only), but the secure setting is
     *  readable, which lets the UI mirror the true system state live. Falls
     *  back to the service's last snapshot if the read is ever restricted. */
    private fun isSystemAlwaysOn(): Boolean = try {
        Settings.Secure.getString(contentResolver, "always_on_vpn_app") == packageName
    } catch (e: Exception) {
        HideipVpnService.alwaysOnActive
    }

    /** Whether "Block connections without VPN" accompanies Always-on. */
    private fun isLockdownEnabled(): Boolean = try {
        Settings.Secure.getInt(contentResolver, "always_on_vpn_lockdown", 0) == 1
    } catch (e: Exception) {
        false
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

    companion object {
        private const val CLIP_MARKER = "net.hideip.vpn.CLIP_MARKER"
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
