package com.hoza.download

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards links shared to Hoza Download into Dart.
 *
 * Android delivers a share two different ways: as the intent that started the
 * process (cold start) and as a new intent on an activity that is already
 * running (warm start). Both end up on one stream so Dart sees a single source
 * of links.
 */
class ShareChannel(messenger: BinaryMessenger) : EventChannel.StreamHandler {

    /**
     * A link that arrived before Dart was listening. Held until it is claimed
     * exactly once, so a share is never delivered twice or lost.
     */
    private var pendingLink: String? = null

    private var eventSink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_CONSUME_INITIAL_LINK -> {
                    result.success(pendingLink)
                    pendingLink = null
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Flush anything that arrived while Dart was starting up.
        pendingLink?.let { link ->
            pendingLink = null
            events?.success(link)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** Called for the launching intent and for every later share. */
    fun handleIntent(intent: Intent?) {
        val link = extractLink(intent) ?: return
        val sink = eventSink
        if (sink != null) sink.success(link) else pendingLink = link
    }

    fun dispose() {
        eventSink = null
    }

    /**
     * Pulls the shared text out of an intent.
     *
     * The payload is passed through untouched: parsing, extraction and
     * validation all happen in Dart, where the same rules apply to pasted and
     * shared links alike.
     */
    private fun extractLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null

        return intent.getStringExtra(Intent.EXTRA_TEXT)
            ?.trim()
            ?.takeIf { it.isNotEmpty() && it.length <= MAX_SHARED_TEXT_LENGTH }
    }

    private companion object {
        const val METHOD_CHANNEL = "com.hoza.download/share"
        const val EVENT_CHANNEL = "com.hoza.download/share_events"
        const val METHOD_CONSUME_INITIAL_LINK = "consumeInitialLink"

        /** Guards against a pathological share payload. */
        const val MAX_SHARED_TEXT_LENGTH = 8192
    }
}
