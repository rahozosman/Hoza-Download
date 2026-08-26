package com.hoza.download

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The one Flutter engine the app ever runs.
 *
 * Both windows — the full app and the floating share sheet — attach to this
 * engine instead of creating their own. That keeps a single Dart isolate, so a
 * download started from the share sheet is the same download the Downloads tab
 * lists, and it keeps running when the sheet's window goes away.
 *
 * Platform channels are registered here, once, because they outlive every
 * activity. Anything that needs an [Activity] reads [host], which always points
 * at the window currently on screen.
 */
object HozaEngine {

    const val ID = "hoza"

    /** Route the engine starts on for a normal launch. */
    const val ROUTE_APP = "/"

    /** Route the engine starts on when a share opens the floating sheet. */
    const val ROUTE_SHARE = "/share"

    /** The window currently hosting the engine, or null while none is. */
    var host: Activity? = null
        private set

    private var share: ShareChannel? = null

    fun ensure(context: Context, initialRoute: String): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }

        val app = context.applicationContext
        val engine = FlutterEngine(app)

        // Must be set before Dart runs: it decides whether the app boots into
        // the shell or straight into the floating sheet, with no splash.
        engine.navigationChannel.setInitialRoute(initialRoute)

        val messenger = engine.dartExecutor.binaryMessenger
        share = ShareChannel(messenger)
        MediaStoreChannel(app) { host }.register(messenger)
        NotificationsChannel(app).register(messenger)
        NetworkChannel(app).register(messenger)
        HozaPermissions.register(messenger)
        SurfaceChannel.register(app, messenger)
        MuxerChannel().register(messenger)
        registerServiceChannel(app, messenger)

        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }

    fun bind(activity: Activity) {
        host = activity
        SurfaceChannel.notifyHost(
            if (activity is ShareSheetActivity) SurfaceChannel.HOST_SHARE
            else SurfaceChannel.HOST_APP,
        )
    }

    fun unbind(activity: Activity) {
        if (host === activity) host = null
    }

    /** Called for a launching intent and for every later share. */
    fun handleIntent(intent: Intent?) {
        share?.handleIntent(intent)
    }

    private fun registerServiceChannel(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "update" -> {
                        DownloadForegroundService.update(
                            context,
                            call.argument<String>("title")
                                ?: DownloadForegroundService.DEFAULT_TITLE,
                            call.argument<String>("text").orEmpty(),
                            call.argument<Int>("progress") ?: -1,
                            details = call.argument<String>("details"),
                            subText = call.argument<String>("subText"),
                            actions = call.argument<List<String>>("actions").orEmpty(),
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        DownloadForegroundService.stop(context)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // A refused service start must never take the app down; Dart
                // keeps downloading, just without the ongoing notification.
                result.error("service_error", error.message, null)
            }
        }
    }

    private const val SERVICE_CHANNEL = "com.hoza.download/service"
}
