import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../shared/widgets/flight_overlay.dart';
import '../shell_controller.dart';

class NavDestination {
  const NavDestination({
    required this.tab,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final ShellTab tab;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Bottom navigation for the shell.
///
/// One indicator pill slides between destinations rather than three fading in
/// and out, so the movement itself tells you where you went. The bar sits on a
/// short gradient scrim instead of a live backdrop blur: it reads the same, and
/// it does not re-blur the whole page on every repaint.
class HozaNavBar extends StatelessWidget {
  const HozaNavBar({
    super.key,
    required this.current,
    required this.onSelected,
    this.badges = const {},
    this.bumpToken = 0,
  });

  final ShellTab current;
  final ValueChanged<ShellTab> onSelected;

  /// A count worn by a destination — live downloads on the Downloads tab.
  /// Zero or absent means no badge.
  final Map<ShellTab, int> badges;

  /// Changes whenever something new lands in a badged tab; the badge bumps
  /// on every change, count or no count.
  final int bumpToken;

  static const List<NavDestination> destinations = [
    NavDestination(
      tab: ShellTab.home,
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    NavDestination(
      tab: ShellTab.downloads,
      label: 'Downloads',
      icon: Icons.download_outlined,
      activeIcon: Icons.download_rounded,
    ),
    NavDestination(
      tab: ShellTab.settings,
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
  ];

  /// Height of the fade above the bar that content dissolves into.
  static const double scrimHeight = 24;

  /// Share of the bar's width the indicator occupies.
  double get _indicatorWidth => 0.52 / destinations.length;

  /// Alignment that puts the indicator's centre under the current icon.
  ///
  /// [Align] places a narrow child across the *free* space, not across the
  /// whole box, so mapping the three slots straight onto -1..1 pins the outer
  /// two against the ends of the bar — the indicator sat off to the left of
  /// Home and off to the right of Settings, and only Downloads, at the centre,
  /// ever lined up. Solving for the child's own centre fixes all three.
  double get _indicatorX {
    final centre = (current.index + 0.5) / destinations.length;
    final free = 1 - _indicatorWidth;
    if (free <= 0) return 0;
    return 2 * (centre - _indicatorWidth / 2) / free - 1;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final barColor = palette.surface.withValues(alpha: 0.94);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Content scrolling under the bar dissolves instead of colliding with
        // its edge.
        SizedBox(
          height: scrimHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [barColor.withValues(alpha: 0), barColor],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: barColor,
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            // A transparent Material above the bar's own fill, so destination
            // ripples are visible instead of painting behind it.
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                height: Layout.navBarHeight,
                child: Stack(
                  children: [
                    AnimatedAlign(
                      // Sits behind the icon row, not the labels. Directional,
                      // so the slot maths still points at the right
                      // destination when the layout is mirrored.
                      alignment: AlignmentDirectional(_indicatorX, -0.47),
                      duration: context.motion(Motion.base),
                      curve: Motion.emphasized,
                      child: FractionallySizedBox(
                        widthFactor: _indicatorWidth,
                        child: Container(
                          height: 30,
                          decoration: BoxDecoration(
                            // The pill carries the same blue-to-violet ramp as
                            // the primary action, so the tab you are on and
                            // the button you would press are lit alike.
                            gradient: LinearGradient(
                              colors: [
                                palette.accent.withValues(alpha: 0.22),
                                palette.accentAlt.withValues(alpha: 0.22),
                              ],
                            ),
                            borderRadius: Radii.pillRadius,
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final destination in destinations)
                          Expanded(
                            child: _NavItem(
                              destination: destination,
                              selected: destination.tab == current,
                              badge: badges[destination.tab] ?? 0,
                              bumpToken: bumpToken,
                              // The Downloads icon is where a starting
                              // download flies to.
                              iconKey: destination.tab == ShellTab.downloads
                                  ? FlightTargets.downloadsTab
                                  : null,
                              onTap: () => onSelected(destination.tab),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    this.bumpToken = 0,
    this.iconKey,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final int bumpToken;
  final GlobalKey? iconKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final color = selected ? palette.accent : palette.textTertiary;
    final duration = context.motion(Motion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0
          ? '${destination.label}, $badge active'
          : destination.label,
      child: InkWell(
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: Radii.cardRadius,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.08 : 1,
                      duration: duration,
                      curve: Motion.springy,
                      // The glyph swaps outline-to-filled; cross-fading the
                      // two reads as one icon thickening rather than two
                      // icons.
                      child: AnimatedSwitcher(
                        duration: context.motion(Motion.fast),
                        switchInCurve: Motion.standard,
                        switchOutCurve: Motion.exit,
                        child: Icon(
                          selected ? destination.activeIcon : destination.icon,
                          key: ValueKey<bool>(selected),
                          size: 22,
                          color: color,
                        ),
                      ),
                    ),
                    // Sized and keyed apart from the icon, so a flight lands
                    // on the glyph and not on the badge beside it.
                    if (iconKey != null)
                      Positioned.fill(child: SizedBox(key: iconKey)),
                    PositionedDirectional(
                      top: -6,
                      end: -12,
                      child: _Badge(count: badge, token: bumpToken),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: context.motion(Motion.fast),
              curve: Motion.standard,
              style: AppTypography.label.copyWith(
                color: color,
                letterSpacing: 0.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(destination.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The count of live downloads on the Downloads icon.
///
/// Appears with a spring when the first one starts, bumps — 1 → 1.35 → 1 —
/// every time another lands, and leaves when the last one finishes. The bump
/// is what closes the loop on "where did my download go?": the poster flew
/// here, and here is the number going up.
class _Badge extends StatefulWidget {
  const _Badge({required this.count, required this.token});

  final int count;
  final int token;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(covariant _Badge old) {
    super.didUpdateWidget(old);
    final grew = widget.count > old.count;
    if ((grew || widget.token != old.token) && widget.count > 0) {
      if (!context.reduceMotion) _bump.forward(from: 0);
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visible = widget.count > 0;

    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: context.motion(Motion.base),
      curve: visible ? Motion.springy : Motion.exit,
      child: AnimatedBuilder(
        animation: _bump,
        builder: (context, child) {
          // Out and back on a single curve, so the number pops once.
          final t = _bump.value;
          final scale = 1 + 0.35 * (1 - (2 * t - 1).abs());
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.accent, palette.accentAlt],
            ),
            borderRadius: Radii.pillRadius,
            border: Border.all(color: palette.surface, width: 1.5),
          ),
          child: Text(
            '${widget.count}',
            style: AppTypography.label.copyWith(
              color: palette.onAccent,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
