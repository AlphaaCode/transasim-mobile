package com.transasim.transasim_mobile

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.euicc.DownloadableSubscription
import android.telephony.euicc.EuiccManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android's eSIM install hand-off.
 *
 * `EuiccManager.downloadSubscription()` needs no carrier entitlement — the OS
 * shows its own consent dialog and does the work. That is the whole reason
 * Android gets a one-tap path while iOS goes through a Universal Link: Apple's
 * equivalent, CTCellularPlanProvisioning.addPlan(), is gated behind an
 * entitlement only real mobile network operators receive.
 *
 * This is BEST EFFORT. Every failure path returns rather than throws, because
 * the QR code is still on screen behind it and remains the reliable route.
 */
class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val CHANNEL = "transasim/esim"
        const val ACTION_RESULT = "com.transasim.transasim_mobile.ESIM_DOWNLOAD"
    }

    private var receiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> result.success(install(call.argument<String>("activationCode")))
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * @return true when the OS took over, false when this device cannot.
     *
     * "Cannot" is the ordinary case on a device with no eUICC — including every
     * emulator — and it is not an error: the caller falls back to the QR code,
     * which was never hidden.
     */
    private fun install(activationCode: String?): Boolean {
        if (activationCode.isNullOrBlank()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false

        val euicc = getSystemService(Context.EUICC_SERVICE) as? EuiccManager ?: return false
        if (!euicc.isEnabled) return false

        registerResultReceiver()

        val intent = Intent(ACTION_RESULT).setPackage(packageName)
        val pending = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            // MUTABLE is required: the platform writes its detailed result code
            // back into this intent's extras.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        return try {
            euicc.downloadSubscription(
                DownloadableSubscription.forActivationCode(activationCode),
                // false: never switch the user's active line for them. The
                // system dialog handles consent for the download itself.
                false,
                pending,
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * The platform answers asynchronously through a broadcast. Nothing in the
     * app depends on the outcome — the user sees the system's own UI — but the
     * receiver has to exist or the PendingIntent has nowhere to land.
     */
    private fun registerResultReceiver() {
        if (receiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) = Unit
        }
        receiver = r
        ContextCompat.registerReceiver(
            this,
            r,
            IntentFilter(ACTION_RESULT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onDestroy() {
        receiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already gone; nothing to undo.
            }
        }
        receiver = null
        super.onDestroy()
    }
}
