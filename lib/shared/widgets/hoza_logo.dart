import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The Hoza mark: the app's own icon artwork, presented as its tile.
///
/// The same file the launcher icons are cut from, so the tile the user tapped
/// on their home screen is the tile they see on the launch screen, on Home and
/// in About — one mark, not a drawn stand-in that drifts away from it.
///
/// The artwork is a shape on transparency, and its outlines are navy. On the
/// app's midnight canvas those outlines would simply disappear, so the mark is
/// always given the light ground it was drawn for — the same ground the
/// adaptive icon uses. That is why this is a plate and not a bare image: it is
/// the icon as the user already knows it, not a picture floating on a page.
class HozaLogo extends StatelessWidget {
  const HozaLogo({super.key, this.size = 44});

  /// The icon asset. Shared with `flutter_launcher_icons` in pubspec.yaml.
  static const String asset = 'assets/icon/hoza_mark.png';

  /// Corner rounding as a share of the tile's width — close enough to
  /// Android's squircle that the plate reads as a launcher tile.
  static const double _cornerRatio = 0.22;

  /// How far the artwork sits inside the plate. The drawing carries a margin
  /// of its own, so this only needs to keep it clear of the rounding.
  static const double _inset = 0.07;

  /// The ground the artwork was drawn against. Cooled a little off pure white,
  /// which glares against a midnight background.
  static const Color _plate = Color(0xFFF4F7FD);

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Semantics(
      label: 'Hoza Download',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _plate,
          borderRadius: BorderRadius.circular(size * _cornerRatio),
          boxShadow: [
            // A soft drop so the tile sits on the page in the light theme,
            // where plate and surface are otherwise the same brightness.
            BoxShadow(
              color: palette.shadow,
              blurRadius: size * 0.22,
              offset: Offset(0, size * 0.07),
            ),
            // And the brand halo underneath it, which is what keeps a white
            // tile from reading as a hole punched in a dark screen.
            BoxShadow(
              color: palette.glow,
              blurRadius: size * 0.46,
              spreadRadius: -size * 0.10,
              offset: Offset(0, size * 0.10),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * _inset),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            // Decoding at display size keeps a 44px mark from parking a full
            // resolution bitmap in the image cache.
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
