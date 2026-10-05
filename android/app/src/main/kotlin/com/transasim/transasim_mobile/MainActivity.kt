package com.transasim.transasim_mobile

import android.content.Context
import android.os.Build
import android.telephony.euicc.EuiccManager
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * What this app can and cannot do about installing an eSIM, on Android.
 *
 * ⚠️ `EuiccManager.downloadSubscription()` USED TO BE CALLED HERE. It no longer
 * is, and the reason is in two device logs rather than in documentation:
 *
 *  - Galaxy A25, Android 16: `isEnabled` came back FALSE, so the call was never
 *    reachable at all.
 *  - Galaxy S23 Ultra, Android 15: `hasSystemFeature(telephony.euicc)=true` and
 *    `isEnabled=true`, so the call WAS made. The platform answered
 *    `RESOLVABLE_ERROR` / `RESOLVABLE_ERROR_NO_PRIVILEGED`, the user was shown
 *    the consent dialog and accepted it, the SM-DP+ was contacted and the
 *    profile metadata downloaded — and then `EuiccController` refused with
 *    **"Caller does not have carrier privilege in metadata."** The profile's own
 *    GSMA access rules name the certificates allowed to install it, and this
 *    app's is not among them.
 *
 * So the API cannot work for this app without its signing certificate being
 * registered in the profile's access rules at the SM-DP+ — a provisioning
 * change on the operator's side, which no amount of client code reaches.
 * Installing goes through the esimsetup.android.com link instead, which hands
 * the activation string to the OS with NO app in the call chain: on the same
 * S23 Ultra that path ran GMS → Samsung's `QrTransferActivity` →
 * `finishAndLaunchEsimAddPlan`, with no Knox restriction and no refusal.
 *
 * What is left here is [hint]: two read-only facts about the device, for
 * telling a user whether their phone has an eUICC at all. It installs nothing.
 */
class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val TAG = "EsimInstall"
        const val CHANNEL = "transasim/esim"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hint" -> result.success(hint())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Whether this device has an eUICC, and whether this app may drive it.
     *
     * The two answer different questions and both are worth having: the feature
     * flag is about the HARDWARE, `isEnabled` about this app's access. Seeing
     * `euiccFeature=true isEnabled=false` is what distinguishes "no eSIM
     * hardware" from "hardware present, this app not allowed" — the A25 and the
     * S23 Ultra differ on exactly that line.
     *
     * Read-only, and nothing is wired to it yet.
     */
    private fun hint(): Map<String, Any> {
        val feature = packageManager.hasSystemFeature("android.hardware.telephony.euicc")
        val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) euiccEnabled() else false
        Log.w(TAG, "hint: sdk=${Build.VERSION.SDK_INT} euiccFeature=$feature isEnabled=$enabled")
        return mapOf("euiccFeature" to feature, "isEnabled" to enabled)
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun euiccEnabled(): Boolean = try {
        val euicc = getSystemService(Context.EUICC_SERVICE) as? EuiccManager
        if (euicc == null) {
            Log.w(TAG, "EuiccManager=null")
            false
        } else {
            euicc.isEnabled
        }
    } catch (e: Exception) {
        Log.w(TAG, "isEnabled threw ${e.javaClass.simpleName}: ${e.message}")
        false
    }
}
