package com.hoza.download

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Runtime permissions, asked on whichever window is currently on screen.
 *
 * Registered on the engine rather than on an activity, because the floating
 * share sheet needs the same two permissions the app does.
 */
object HozaPermissions {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureNotifications" -> ensureNotifications(result)
                "ensureLegacyStorage" -> ensureLegacyStorage(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Asks for notification access, which Android 13+ requires before the
     * foreground service notification can be shown.
     *
     * A refusal is not fatal: downloads still run, they just have no visible
     * progress notification.
     */
    private fun ensureNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        request(Manifest.permission.POST_NOTIFICATIONS, REQUEST_NOTIFICATIONS, result)
    }

    /**
     * Asks for legacy storage access, needed only on Android 9 and older where
     * MediaStore.Downloads does not exist. Never requests
     * `MANAGE_EXTERNAL_STORAGE`.
     */
    private fun ensureLegacyStorage(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        request(
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            REQUEST_LEGACY_STORAGE,
            result,
        )
    }

    private fun request(permission: String, code: Int, result: MethodChannel.Result) {
        // No window on screen means nothing can host a system dialog; report
        // the refusal rather than leaving Dart waiting.
        val activity = HozaEngine.host ?: run {
            result.success(false)
            return
        }
        if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        // Only one request may be in flight per code; a second caller is
        // answered with the current state rather than being left hanging.
        if (pending.containsKey(code)) {
            result.success(false)
            return
        }
        pending[code] = result
        activity.requestPermissions(arrayOf(permission), code)
    }

    fun onResult(requestCode: Int, grantResults: IntArray) {
        val result = pending.remove(requestCode) ?: return
        result.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    /** Requests awaiting a system callback, keyed by request code. */
    private val pending = mutableMapOf<Int, MethodChannel.Result>()

    private const val CHANNEL = "com.hoza.download/permissions"
    private const val REQUEST_NOTIFICATIONS = 3001
    private const val REQUEST_LEGACY_STORAGE = 3002
}
