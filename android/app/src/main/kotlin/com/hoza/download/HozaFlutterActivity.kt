package com.hoza.download

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Shared behaviour for the two windows that host Hoza's Flutter engine.
 *
 * Both attach to the single cached engine in [HozaEngine] rather than starting
 * one of their own, so downloads, history and settings are the same objects
 * whichever window the user is looking at — and they survive that window
 * closing.
 */
abstract class HozaFlutterActivity : FlutterActivity() {

    /** Route the engine boots on when this window is what started the process. */
    protected abstract val startRoute: String

    /** Set when another window took the engine away from this one. */
    private var evicted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine has to exist before FlutterActivity looks it up in the
        // cache, and the launching share has to be handed over before Dart can
        // ask for it.
        HozaEngine.ensure(this, startRoute)
        HozaEngine.bind(this)
        // Only a fresh launch carries a new share. A window Android rebuilt —
        // recreate() after an eviction, or a restore after the process was
        // killed — still holds the old intent, and delivering it again would
        // open the same link a second time.
        if (savedInstanceState == null) HozaEngine.handleIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun getCachedEngineId(): String = HozaEngine.ID

    /** The engine outlives its windows; downloads keep running without one. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /** Plugins are registered once, when the engine is built. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) = Unit

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        HozaEngine.handleIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        // The embedding hands the engine to whichever window attaches last and
        // does not give it back: a window that was evicted has nothing left to
        // draw, so it is never shown blank.
        if (evicted && !isFinishing) {
            evicted = false
            onEvicted()
        }
    }

    override fun onResume() {
        super.onResume()
        // A translucent window on top leaves this one visible and merely paused,
        // so onStart never runs on the way back; check here too.
        if (evicted && !isFinishing) {
            evicted = false
            onEvicted()
            return
        }
        HozaEngine.bind(this)
    }

    /**
     * Called when this window comes back after another one took the engine.
     * The full app rebuilds itself and takes the engine back; a window that
     * should not outlive its moment overrides this to close instead.
     */
    protected open fun onEvicted() {
        recreate()
    }

    override fun detachFromFlutterEngine() {
        super.detachFromFlutterEngine()
        evicted = true
    }

    override fun onDestroy() {
        HozaEngine.unbind(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        HozaPermissions.onResult(requestCode, grantResults)
    }
}
