import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import 'edge_glow.dart';
import 'sheen_text.dart';

/// Chrome for every Hoza modal sheet: a lit top rim, drag handle, optional
/// title row, rounded top corners, and safe-area aware padding.
///
/// This is the surface the app shows over other apps when a link is shared, so
/// it has to stand on its own: the same accent wash the pages carry, a brand
/// hairline travelling along the one edge that is actually on screen, and a
/// title that breathes. Sheets size themselves to their content and stay
/// scrollable when the keyboard or a long body would otherwise overflow.
class HozaSheet extends StatelessWidget {
  const HozaSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
    this.maxHeightFraction = 0.9,
    this.frosted = true,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  /// An action bar held against the bottom of the sheet, outside the scroll.
  ///
  /// Whatever the body does — a long list, a keyboard pushing it up — what is
  /// in here stays on screen. A sheet whose one action can be scrolled out of
  /// sight is a sheet the user can get stuck in.
  final Widget? footer;

  final EdgeInsets padding;

  /// The most of the screen the sheet may take; its body scrolls past that.
  final double maxHeightFraction;

  /// Whether the sheet is glass: the page behind it shows through, blurred,
  /// and the fill is a little translucent. Off where there is nothing of the
  /// app behind it to show — the floating share window sits over another
  /// app, whose pixels are outside what a blur can reach — so the sheet is
  /// solid there and its text stays crisp over a playing video.
  final bool frosted;

  /// How much of the page behind shows through a glass sheet.
  static const double _blurSigma = 18;
  static const double _glassAlpha = 0.88;

  /// How far the accent wash reaches down from the top rim.
  static const double _washHeight = 200;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final media = MediaQuery.of(context);
    // Inside a draggable sheet the height is the sheet's to decide, and the
    // body has to scroll with the controller the drag is listening to.
    final scrollController = SheetScrollScope.maybeOf(context);
    final expandable = scrollController != null;

    final glass = frosted && !context.reduceMotion;
    final fill = glass
        ? palette.surface.withValues(alpha: _glassAlpha)
        : palette.surface;

    Widget sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: Radii.sheetRadius,
        // A rounded box needs a uniform border; per-side colours assert at
        // paint time.
        border: Border.all(color: palette.borderStrong),
      ),
      // Transparent Material above the sheet's own fill so ripples inside the
      // sheet render on top of it.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _washHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.backgroundTint.withValues(alpha: 0.5),
                        palette.surface.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // The only unpositioned child, so the sheet takes its height.
            SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: expandable
                      ? double.infinity
                      : media.size.height * maxHeightFraction,
                ),
                child: Column(
                  mainAxisSize: expandable
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  children: [
                    _DragHandle(pulse: expandable),
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.lg,
                          0,
                          Gap.xs,
                          Gap.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SheenText(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.title.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            ?trailing,
                          ],
                        ),
                      ),
                    Flexible(
                      fit: expandable ? FlexFit.tight : FlexFit.loose,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: padding.copyWith(
                          // With an action bar below, the body only needs
                          // breathing room; the bar carries the safe area
                          // and the keyboard inset instead.
                          bottom: footer != null
                              ? Gap.sm
                              : padding.bottom + media.viewInsets.bottom,
                        ),
                        child: child,
                      ),
                    ),

                    if (footer != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: fill,
                          // A hairline is what tells the eye the list above
                          // ran out rather than simply stopping.
                          border: Border(
                            top: BorderSide(color: palette.border),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            Gap.sm,
                            padding.right,
                            padding.bottom + media.viewInsets.bottom,
                          ),
                          child: footer,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // The caught light just under the rim: one pixel of white,
            // which is what makes a glass edge read as an edge.
            Positioned(
              top: 2,
              left: 0,
              right: 0,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.22
                          : 0.8,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(child: RimLight()),
            ),
          ],
        ),
      ),
    );

    if (glass) {
      sheet = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: sheet,
      );
    }

    return ClipRRect(
      borderRadius: Radii.sheetRadius,
      clipBehavior: Clip.antiAlias,
      child: sheet,
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({this.pulse = false});

  /// Whether the sheet can be pulled taller. The handle then widens once on
  /// arrival — a hint that it does something — and settles.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final handle = Container(
      margin: const EdgeInsets.symmetric(vertical: Gap.sm),
      width: 44,
      height: 4,
      decoration: BoxDecoration(
        color: context.colors.borderStrong,
        borderRadius: Radii.pillRadius,
      ),
    );

    return Semantics(
      label: pulse ? 'Drag handle. Pull up for more' : 'Drag handle',
      child: !pulse || context.reduceMotion
          ? handle
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (context, t, child) {
                // Out and back: 1 → 1.35 → 1 over the sheet's first second.
                final swell = 1 + 0.35 * (1 - (2 * t - 1).abs());
                return Transform.scale(scaleX: swell, child: child);
              },
              child: handle,
            ),
    );
  }
}

/// Hands a draggable sheet's scroll controller down to the [HozaSheet] inside
/// it, so the body scrolls with the drag and the sheet fills the height the
/// drag gives it.
class SheetScrollScope extends InheritedWidget {
  const SheetScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SheetScrollScope>()
      ?.controller;

  @override
  bool updateShouldNotify(SheetScrollScope old) => old.controller != controller;
}

/// Presents [builder] as a Hoza-styled modal sheet.
///
/// Centralised so entrance motion, barrier colour and radius are identical
/// everywhere a sheet is used.
///
/// [expandable] opens the sheet at [initialFraction] of the screen and lets
/// the user pull it to [maxFraction], snapping between the two — for a sheet
/// whose list can be long, like twenty photos of one post. Left off, the
/// sheet sizes itself to its content.
Future<T?> showHozaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool expandable = false,
  double initialFraction = 0.65,
  double maxFraction = 0.94,
}) {
  final duration = context.motion(Motion.slow);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.scrim,
    elevation: 0,
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      curve: Motion.emphasized,
      reverseDuration: context.motion(Motion.base),
      reverseCurve: Motion.exit,
    ),
    builder: expandable
        ? (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: initialFraction,
            minChildSize: initialFraction * 0.7,
            maxChildSize: maxFraction,
            snap: true,
            snapSizes: [initialFraction],
            builder: (context, controller) => SheetScrollScope(
              controller: controller,
              child: Builder(builder: builder),
            ),
          )
        : builder,
  );
}
