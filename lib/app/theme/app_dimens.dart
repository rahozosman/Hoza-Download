import 'package:flutter/widgets.dart';

/// Spacing scale. Every gap in the app comes from this ladder so rhythm stays
/// consistent across screens.
abstract final class Gap {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 44;
}

/// Corner radii. Hoza uses generous rounding on containers and pill shapes on
/// interactive chips.
abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double sheet = 30;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius tileRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius largeRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Layout constants shared by the shell and content pages.
abstract final class Layout {
  /// Horizontal page padding on a phone.
  static const double pagePadding = Gap.lg;

  /// Content never stretches past this on tablets/foldables.
  static const double maxContentWidth = 560;

  /// Minimum tappable square, matching Android accessibility guidance.
  static const double minTouchTarget = 48;

  static const double navBarHeight = 64;
}
