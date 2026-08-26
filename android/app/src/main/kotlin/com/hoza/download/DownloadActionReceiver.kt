package com.hoza.download

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Receives the buttons on the ongoing download notification and hands them
 * to Dart, which owns the queue and decides what pausing or cancelling means.
 *
 * A press with no engine alive — the process was killed and the stale
 * notification survived — is dropped: there is no queue to act on, and
 * starting the whole app to say so would be worse than nothing.
 */
class DownloadActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            ACTION_PAUSE -> "pause"
            ACTION_RESUME -> "resume"
            ACTION_CANCEL -> "cancel"
            else -> return
        }
        val engine = FlutterEngineCache.getInstance().get(HozaEngine.ID) ?: return
        val messenger = engine.dartExecutor.binaryMessenger
        Handler(Looper.getMainLooper()).post {
            MethodChannel(messenger, CHANNEL).invokeMethod("action", action)
        }
    }

    companion object {
        const val CHANNEL = "com.hoza.download/download_actions"
        const val ACTION_PAUSE = "com.hoza.download.action.PAUSE_ALL"
        const val ACTION_RESUME = "com.hoza.download.action.RESUME_ALL"
        const val ACTION_CANCEL = "com.hoza.download.action.CANCEL_ALL"

        /** The broadcast action for one of Dart's action keys, or null. */
        fun actionFor(key: String): String? = when (key) {
            "pause" -> ACTION_PAUSE
            "resume" -> ACTION_RESUME
            "cancel" -> ACTION_CANCEL
            else -> null
        }

        fun labelFor(key: String): String = when (key) {
            "pause" -> "Pause"
            "resume" -> "Resume"
            "cancel" -> "Cancel"
            else -> key
        }
    }
}
