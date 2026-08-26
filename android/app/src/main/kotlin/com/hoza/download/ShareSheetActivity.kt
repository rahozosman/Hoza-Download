package com.hoza.download

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * The window a share lands on.
 *
 * It is translucent and lives in its own task, so choosing "Hoza Download" in
 * another app's share sheet does not bring the app forward: the user keeps
 * looking at the video they were watching, with Hoza's download sheet slid up
 * over it.
 *
 * The Flutter view is hidden until Dart says the sheet is ready. The engine
 * may well be painting the app's own screens when this window attaches to it
 * — it keeps whatever route the last window left — and revealing those here
 * would look exactly like the whole app opening over the share.
 *
 * While Dart gets the sheet up, the window is never blank: a small native
 * "Opening Hoza Download" card shows at once, so the user always sees that
 * their tap did something. Left invisible, this window would still swallow
 * every touch, and the app behind it would look frozen. If the sheet has not
 * appeared after [READY_TIMEOUT_MS] the share is handed to the full app
 * instead, which always has a screen to show for it.
 */
class ShareSheetActivity : HozaFlutterActivity() {

    override val startRoute: String get() = HozaEngine.ROUTE_SHARE

    /** Draw over whatever the link was shared from. */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    private var revealed = false

    /** The native card shown until the sheet is up. */
    private var placeholder: View? = null

    /** Runs the fallback if Dart never presents the sheet. */
    private val giveUp = Runnable { if (!revealed) openAppWithShare() }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Registered before the engine hears about the link, so Dart's
        // "ready" can never arrive at a window that does not know it exists.
        current = this
        super.onCreate(savedInstanceState)
        // The sheet plays its own entrance; a window animation on top of it
        // reads as two separate movements.
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)

        flutterContent()?.alpha = 0f
        showPlaceholder()
        window.decorView.postDelayed(giveUp, READY_TIMEOUT_MS)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A second share reused this window. If the first never got its
        // sheet, the clock starts again for this one.
        if (!revealed) {
            window.decorView.removeCallbacks(giveUp)
            window.decorView.postDelayed(giveUp, READY_TIMEOUT_MS)
        }
    }

    /** The FlutterView this activity hosts, once it has been set as content. */
    private fun flutterContent(): View? =
        findViewById<ViewGroup>(android.R.id.content)?.getChildAt(0)

    /** Fade the sheet in and the placeholder out; called by Dart the moment the sheet is presented. */
    fun reveal() {
        if (revealed) return
        revealed = true
        window.decorView.removeCallbacks(giveUp)

        flutterContent()?.let { view ->
            view.animate().alpha(1f).setDuration(REVEAL_FADE_MS).start()
        }
        placeholder?.let { card ->
            card.animate()
                .alpha(0f)
                .setDuration(REVEAL_FADE_MS)
                .withEndAction { removePlaceholder() }
                .start()
        }
    }

    fun dismiss() {
        if (isFinishing) return
        window.decorView.removeCallbacks(giveUp)
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    /**
     * The sheet never came. Rather than vanish — which reads as the app doing
     * nothing — the share is passed to the full app, whose window is always
     * able to show something for it.
     */
    private fun openAppWithShare() {
        if (isFinishing) return
        val source = intent
        val forward = Intent(this, MainActivity::class.java).apply {
            action = source?.action
            type = source?.type
            source?.extras?.let { putExtras(it) }
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        try {
            startActivity(forward)
        } catch (_: Exception) {
            // Nothing else to try; at least the window stops covering the app.
        }
        dismiss()
    }

    /**
     * A small card above the app the link came from: a spinner and the app's
     * name. Tapping anywhere outside it cancels the share, so the user is never
     * stuck waiting.
     */
    private fun showPlaceholder() {
        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density + 0.5f).toInt()

        val spinner = ProgressBar(this).apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(Color.WHITE)
        }
        val label = TextView(this).apply {
            text = getString(R.string.share_sheet_opening)
            setTextColor(Color.WHITE)
            textSize = 15f
            setPadding(dp(14), 0, 0, 0)
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(16), dp(24), dp(16))
            elevation = dp(8).toFloat()
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(getColor(R.color.hozaMidnight))
            }
            isClickable = true
            addView(spinner, LinearLayout.LayoutParams(dp(22), dp(22)))
            addView(label)
        }

        val holder = FrameLayout(this).apply {
            setOnClickListener { dismiss() }
            addView(
                card,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
                ).apply { bottomMargin = dp(56) },
            )
        }

        addContentView(
            holder,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        placeholder = holder
    }

    private fun removePlaceholder() {
        val view = placeholder ?: return
        placeholder = null
        (view.parent as? ViewGroup)?.removeView(view)
    }

    /**
     * The full app took the engine while this window was up. The sheet is
     * over; coming back to this window later would only show the app's own
     * screens through a transparent frame, so it goes.
     */
    override fun onEvicted() {
        dismiss()
    }

    override fun onDestroy() {
        window.decorView.removeCallbacks(giveUp)
        // Back gesture, swipe-away or a system finish: Dart still thinks it is
        // painting a sheet, so tell it the window is gone.
        if (current === this) current = null
        if (isFinishing) SurfaceChannel.notifyOverlayDismissed()
        super.onDestroy()
    }

    companion object {
        /**
         * The live share window, if there is one.
         *
         * Tracked separately from the engine host because opening the full app
         * takes the engine away from this window while it is still on screen,
         * and it still has to be closed afterwards.
         */
        var current: ShareSheetActivity? = null

        /**
         * How long Dart gets to present the sheet before the share is handed to
         * the full app. Covers a cold start of the engine on a slow phone; an
         * unusable share is closed by Dart itself long before this.
         */
        private const val READY_TIMEOUT_MS = 6_000L
        private const val REVEAL_FADE_MS = 120L
    }
}
