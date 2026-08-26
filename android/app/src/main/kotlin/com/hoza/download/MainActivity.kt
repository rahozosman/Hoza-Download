package com.hoza.download

/**
 * The full app window: the launcher entry point.
 *
 * Everything platform-side lives on the shared engine in [HozaEngine], which
 * this window simply attaches to — see [HozaFlutterActivity].
 */
class MainActivity : HozaFlutterActivity() {

    override val startRoute: String get() = HozaEngine.ROUTE_APP
}
