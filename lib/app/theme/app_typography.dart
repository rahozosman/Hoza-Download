import 'package:flutter/material.dart';

/// Typography roles used across Hoza Download.
///
/// The app deliberately ships without a bundled font: Android's system face
/// (Roboto) renders crisply at these weights, keeps the APK small, and avoids a
/// runtime font download. Only sizes, weights and tracking are opinionated.
abstract final class AppTypography {
  /// Splash wordmark and hero numbers.
  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  /// Screen titles.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// Card headlines and dialog titles.
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Section headers above lists.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Primary reading size.
  static const TextStyle body = TextStyle(
    fontSize: 14.5,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// Supporting copy under a title.
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// Metadata rows: quality, size, timestamp.
  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Status pills and overline labels.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// Button text.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Tabular figures for progress, speed and ETA so digits do not jitter as
  /// they tick.
  static const TextStyle metric = TextStyle(
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displaySmall: display.copyWith(color: primary),
      headlineMedium: pageTitle.copyWith(color: primary),
      headlineSmall: title.copyWith(color: primary),
      titleMedium: sectionTitle.copyWith(color: primary),
      titleSmall: caption.copyWith(color: secondary),
      bodyLarge: body.copyWith(color: primary),
      bodyMedium: body.copyWith(color: secondary),
      bodySmall: bodySmall.copyWith(color: secondary),
      labelLarge: button.copyWith(color: primary),
      labelMedium: caption.copyWith(color: secondary),
      labelSmall: label.copyWith(color: secondary),
    );
  }
}
