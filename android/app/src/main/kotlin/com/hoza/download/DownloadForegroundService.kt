package com.hoza.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process alive while downloads are running.
 *
 * Transfers run in the Flutter isolate, which Android is free to kill once the
 * app leaves the screen. A foreground service with an ongoing notification is
 * the supported way to say "this work is still happening" — it is started when
 * the first transfer begins and stopped the moment the last one ends, so it is
 * never running without something to show for it.
 */
class DownloadForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
                val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
                val details = intent?.getStringExtra(EXTRA_DETAILS)
                val subText = intent?.getStringExtra(EXTRA_SUB_TEXT)
                val actions = intent?.getStringArrayListExtra(EXTRA_ACTIONS).orEmpty()
                startForegroundCompat(
                    buildNotification(title, text, progress, details, subText, actions),
                )
            }
        }
        // Do not resurrect the service on its own: without the Flutter isolate
        // there is nothing for it to keep alive.
        return START_NOT_STICKY
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        // STOP_FOREGROUND_REMOVE exists from API 24, which is the app minimum.
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /**
     * [text] is the one line shown collapsed; [details] is what the expanded
     * card shows instead — percent, size, speed and time left on their own
     * lines — and [subText] the small label next to the app name.
     */
    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
        details: String?,
        subText: String?,
        actions: List<String>,
    ): Notification {
        ensureChannel()

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(details ?: text))
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            // The bar is the clock here; a timestamp beside it only clutters.
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            // A negative value means the total size is unknown, which the bar
            // shows as indeterminate rather than as a fabricated percentage.
            .setProgress(100, progress.coerceAtLeast(0), progress < 0)
        if (!subText.isNullOrEmpty()) builder.setSubText(subText)
        for (key in actions) {
            val broadcast = DownloadActionReceiver.actionFor(key) ?: continue
            val pending = PendingIntent.getBroadcast(
                this,
                broadcast.hashCode(),
                Intent(this, DownloadActionReceiver::class.java).apply { action = broadcast },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            @Suppress("DEPRECATION")
            builder.addAction(0, DownloadActionReceiver.labelFor(key), pending)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ may collapse a foreground service notification for
            // its first seconds; a download's bar should be visible at once.
            builder.setForegroundServiceBehavior(
                Notification.FOREGROUND_SERVICE_IMMEDIATE,
            )
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Active downloads",
                // Silent: an ongoing progress bar should not buzz the device.
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows downloads that are currently running."
                setShowBadge(false)
            },
        )
    }

    companion object {
        const val CHANNEL_ID = "hoza_downloads_progress"
        const val NOTIFICATION_ID = 1001

        const val ACTION_UPDATE = "com.hoza.download.action.UPDATE"
        const val ACTION_STOP = "com.hoza.download.action.STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_DETAILS = "details"
        const val EXTRA_SUB_TEXT = "subText"
        const val EXTRA_ACTIONS = "actions"

        const val DEFAULT_TITLE = "Downloading"

        /** Starts or refreshes the ongoing notification. */
        fun update(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            details: String? = null,
            subText: String? = null,
            actions: List<String> = emptyList(),
        ) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_DETAILS, details)
                putExtra(EXTRA_SUB_TEXT, subText)
                putStringArrayListExtra(EXTRA_ACTIONS, ArrayList(actions))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, DownloadForegroundService::class.java).apply {
                    action = ACTION_STOP
                },
            )
        }
    }
}
