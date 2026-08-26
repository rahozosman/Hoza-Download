package com.hoza.download

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Lets Dart drive the floating share window it is being drawn into: reveal it
 * once the sheet is ready, close it when the sheet is dismissed, and open the
 * full app when the user asks for their downloads.
 *
 * Also reports back when the window disappears without Dart asking, and which
 * kind of window currently holds the engine, so Dart can keep the sheet and
 * the app's own screens from ever showing in the wrong window.
 */
object SurfaceChannel {

    private var channel: MethodChannel? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val method = MethodChannel(messenger, CHANNEL)
        channel = method
        method.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    overlay()?.reveal()
                    result.success(true)
                }
                "close" -> {
                    overlay()?.dismiss()
                    result.success(true)
                }
                "openApp" -> {
                    openApp(context)
                    result.success(true)
                }
                // Which window holds the engine right now. Asked rather than
                // only pushed, because the push sent while Dart was still
                // booting was never heard.
                "host" -> result.success(
                    when (HozaEngine.host) {
                        null -> null
                        is ShareSheetActivity -> HOST_SHARE
                        else -> HOST_APP
                    },
                )
                else -> result.notImplemented()
            }
        }
    }

    /** The live share window, if one is on screen. */
    private fun overlay(): ShareSheetActivity? = ShareSheetActivity.current

    private fun openApp(context: Context) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(intent)
    }

    /** The share window went away — swiped off, or finished by the system. */
    fun notifyOverlayDismissed() {
        channel?.invokeMethod(METHOD_DISMISSED, null)
    }

    /** A window took the engine: [HOST_SHARE] for the floating sheet, [HOST_APP] otherwise. */
    fun notifyHost(host: String) {
        channel?.invokeMethod(METHOD_HOST_CHANGED, host)
    }

    const val HOST_APP = "app"
    const val HOST_SHARE = "share"

    private const val CHANNEL = "com.hoza.download/surface"
    private const val METHOD_DISMISSED = "overlayDismissed"
    private const val METHOD_HOST_CHANGED = "hostChanged"
}
