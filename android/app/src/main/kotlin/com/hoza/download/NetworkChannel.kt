package com.hoza.download

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Reports whether the device is online and whether the connection is metered.
 *
 * Used for the offline state and for the Wi-Fi-only preference. Nothing here
 * blocks a download on its own — it only tells Dart what the network is, and
 * the queue decides.
 *
 * The default network is tracked from the callbacks themselves rather than
 * read back from the system on every event: when the phone moves from Wi-Fi
 * to mobile data, `onLost` for the old network can arrive *after* the new one
 * is up, and at that instant `activeNetwork` is briefly null. Reporting that
 * as offline — with nothing to correct it until the next change — is how a
 * connected phone ends up "waiting for a connection".
 */
class NetworkChannel(private val context: Context) : EventChannel.StreamHandler {

    private val connectivity: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)

    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    /** The default network the callbacks last announced, and what it can do. */
    private var defaultNetwork: Network? = null
    private var defaultCapabilities: NetworkCapabilities? = null

    /** A second look, a moment after a loss, in case the loss was a hand-over. */
    private val recheck = Runnable { emit() }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val manager = connectivity ?: return

        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                defaultNetwork = network
                defaultCapabilities = manager.getNetworkCapabilities(network)
                emit()
            }

            override fun onLost(network: Network) {
                if (network == defaultNetwork) {
                    defaultNetwork = null
                    defaultCapabilities = null
                }
                emit()
                // A loss during a hand-over is followed by the new network's
                // arrival; if it was not, this confirms the offline state.
                mainHandler.removeCallbacks(recheck)
                mainHandler.postDelayed(recheck, RECHECK_DELAY_MS)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                if (network == defaultNetwork || defaultNetwork == null) {
                    defaultNetwork = network
                    defaultCapabilities = networkCapabilities
                }
                emit()
            }
        }
        callback = networkCallback

        try {
            manager.registerDefaultNetworkCallback(networkCallback)
        } catch (_: SecurityException) {
            // Some restricted profiles refuse this; the app falls back to
            // polling the status on demand.
            callback = null
        }
        emit()
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        sink = null
    }

    fun dispose() {
        unregister()
        sink = null
    }

    private fun unregister() {
        mainHandler.removeCallbacks(recheck)
        val manager = connectivity ?: return
        callback?.let {
            try {
                manager.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered.
            }
        }
        callback = null
        defaultNetwork = null
        defaultCapabilities = null
    }

    /** Callbacks arrive off the main thread; Flutter requires it. */
    private fun emit() {
        mainHandler.post { sink?.success(status()) }
    }

    private fun status(): Map<String, Any> {
        val manager = connectivity
            // Without connectivity info, assume online rather than blocking
            // downloads on a check we cannot make.
            ?: return mapOf("connected" to true, "metered" to false)

        val capabilities = try {
            manager.activeNetwork?.let { manager.getNetworkCapabilities(it) }
                ?: defaultCapabilities
                ?: anyInternetCapabilities(manager)
        } catch (_: SecurityException) {
            null
        }

        val connected = capabilities != null &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)

        val metered = if (capabilities == null) {
            manager.isActiveNetworkMetered
        } else {
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        }

        return mapOf("connected" to connected, "metered" to metered)
    }

    /**
     * Last resort while the system has no default network to name: any
     * network that can reach the internet. Deprecated in favour of the
     * callbacks, which is exactly what this backs up.
     */
    private fun anyInternetCapabilities(manager: ConnectivityManager): NetworkCapabilities? {
        @Suppress("DEPRECATION")
        val networks = manager.allNetworks
        for (network in networks) {
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                return capabilities
            }
        }
        return null
    }

    private companion object {
        const val METHOD_CHANNEL = "com.hoza.download/network"
        const val EVENT_CHANNEL = "com.hoza.download/network_events"
        const val RECHECK_DELAY_MS = 1_500L
    }
}
