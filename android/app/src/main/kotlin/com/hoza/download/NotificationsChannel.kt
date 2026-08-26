package com.hoza.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * One-off notifications for downloads that finished or failed.
 *
 * Separate from the foreground service's ongoing progress notification: this
 * channel can make a sound, and its notifications are dismissible. Dart decides
 * whether to post at all, based on the user's notification preferences.
 */
class NotificationsChannel(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "showCompleted" -> {
                        showCompleted(call)
                        result.success(true)
                    }
                    "showFailed" -> {
                        showFailed(call)
                        result.success(true)
                    }
                    "showInfo" -> {
                        showInfo(call)
                        result.success(true)
                    }
                    "cancel" -> {
                        manager()?.cancel(notificationId(call.argument<String>("id")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("notification_error", error.message, null)
            }
        }
    }

    private fun manager(): NotificationManager? =
        context.getSystemService(NotificationManager::class.java)

    /** Stable per download, so a repeat notification replaces the old one. */
    private fun notificationId(downloadId: String?): Int =
        BASE_NOTIFICATION_ID + (downloadId?.hashCode() ?: 0).and(0xFFFF)

    private fun showCompleted(call: MethodCall) {
        val title = call.argument<String>("title").orEmpty()
        val text = call.argument<String>("text").orEmpty()
        val location = call.argument<String>("location")
        val mimeType = call.argument<String>("mimeType") ?: "*/*"

        post(
            id = notificationId(call.argument<String>("id")),
            title = title,
            text = text,
            icon = android.R.drawable.stat_sys_download_done,
            intent = openFileIntent(location, mimeType) ?: openAppIntent(),
            // The icon takes the hue of what was saved — the same blue, green
            // and amber the app uses for video, audio and images — so the
            // shade tells the kind of file before the text is read.
            color = mediaColor(call.argument<String>("mediaType")),
        )
    }

    private fun showFailed(call: MethodCall) {
        post(
            id = notificationId(call.argument<String>("id")),
            title = call.argument<String>("title").orEmpty(),
            text = call.argument<String>("text").orEmpty(),
            icon = android.R.drawable.stat_notify_error,
            // A failure needs the app, not a file that was never written.
            intent = openAppIntent(),
        )
    }

    private fun showInfo(call: MethodCall) {
        post(
            id = notificationId(call.argument<String>("id")),
            title = call.argument<String>("title").orEmpty(),
            text = call.argument<String>("text").orEmpty(),
            icon = android.R.drawable.ic_media_pause,
            intent = openAppIntent(),
        )
    }

    /** Colour of the notification icon per kind of media, mirroring MediaVisuals. */
    private fun mediaColor(mediaType: String?): Int = when (mediaType) {
        "audio" -> 0xFF37C08A.toInt()
        "image" -> 0xFFE3A94A.toInt()
        else -> 0xFF4C7DFF.toInt()
    }

    private fun post(
        id: Int,
        title: String,
        text: String,
        icon: Int,
        intent: PendingIntent,
        color: Int = 0xFF4C7DFF.toInt(),
    ) {
        val notifications = manager() ?: return
        ensureChannel(notifications)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        notifications.notify(
            id,
            builder
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setSmallIcon(icon)
                .setColor(color)
                .setContentIntent(intent)
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Tapping a finished download plays it, which is what the user wants. */
    private fun openFileIntent(location: String?, mimeType: String): PendingIntent? {
        if (location.isNullOrEmpty()) return null

        // A file:// URI handed to another app throws FileUriExposedException,
        // so a legacy path is resolved to its scanned content URI instead.
        val uri = if (location.startsWith("content://")) {
            Uri.parse(location)
        } else {
            if (!File(location).exists()) return null
            MediaStoreChannel.contentUriForPath(context, location) ?: return null
        }

        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (view.resolveActivity(context.packageManager) == null) return null

        return PendingIntent.getActivity(
            context,
            uri.hashCode(),
            view,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(notifications: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (notifications.getNotificationChannel(CHANNEL_ID) != null) return

        notifications.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Download results",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Tells you when a download finishes or fails."
            },
        )
    }

    private companion object {
        const val CHANNEL = "com.hoza.download/notifications"
        const val CHANNEL_ID = "hoza_downloads_status"
        const val BASE_NOTIFICATION_ID = 2000
    }
}
