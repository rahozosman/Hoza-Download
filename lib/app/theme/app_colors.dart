import 'package:flutter/material.dart';

/// Semantic colour tokens for Hoza Download.
///
/// Widgets never hardcode colours; they read tokens from this extension so the
/// dark and light schemes stay in sync and a single edit repaints the app.
@immutable
class HozaPalette extends ThemeExtension<HozaPalette> {
  const HozaPalette({
    required this.background,
    required this.backgroundTint,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.accentAlt,
    required this.glow,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.scrim,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.shadow,
  });

  /// Page background — the deepest surface in the hierarchy.
  final Color background;

  /// Faint accent wash painted behind the top of a page for depth.
  final Color backgroundTint;

  /// Bars and sheets that sit directly on [background].
  final Color surface;

  /// Cards and raised containers.
  final Color surfaceElevated;

  /// Inputs, idle chips and inset wells.
  final Color surfaceMuted;

  /// Hairline separators and card outlines.
  final Color border;

  /// Outline for focused, selected or emphasised containers.
  final Color borderStrong;

  final Color accent;
  final Color accentPressed;

  /// Low-opacity accent used for selected chip fills and icon tiles.
  final Color accentSoft;

  /// Second hue in every accent gradient. Paired with [accent] it gives brand
  /// surfaces depth without adding a third colour to the palette.
  final Color accentAlt;

  /// Coloured halo cast by accent surfaces. Already translucent, so it drops
  /// straight into a [BoxShadow].
  final Color glow;

  /// Foreground on top of [accent].
  final Color onAccent;

  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Barrier painted behind modals and bottom sheets.
  final Color scrim;

  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color shadow;

  static const HozaPalette dark = HozaPalette(
    background: Color(0xFF080E1C),
    backgroundTint: Color(0xFF13224A),
    surface: Color(0xFF0C1424),
    surfaceElevated: Color(0xFF121C30),
    surfaceMuted: Color(0xFF16203A),
    border: Color(0xFF1E2C4C),
    borderStrong: Color(0xFF31446B),
    accent: Color(0xFF4C7DFF),
    accentPressed: Color(0xFF3B67DF),
    accentSoft: Color(0x264C7DFF),
    accentAlt: Color(0xFF8A5CF6),
    glow: Color(0x4D4C7DFF),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF37C08A),
    successSoft: Color(0x2637C08A),
    danger: Color(0xFFE5645C),
    dangerSoft: Color(0x26E5645C),
    warning: Color(0xFFE3A94A),
    warningSoft: Color(0x26E3A94A),
    textPrimary: Color(0xFFF3F6FC),
    textSecondary: Color(0xFF98A4BC),
    textTertiary: Color(0xFF6B7891),
    scrim: Color(0xB301040A),
    skeletonBase: Color(0xFF16203A),
    skeletonHighlight: Color(0xFF22304F),
    shadow: Color(0x66000000),
  );

  static const HozaPalette light = HozaPalette(
    background: Color(0xFFEAF2FD),
    backgroundTint: Color(0xFFD3E4FB),
    surface: Color(0xFFF7FBFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFE1EBFA),
    border: Color(0xFFD2E0F3),
    borderStrong: Color(0xFFB2C9E8),
    accent: Color(0xFF2E5FE8),
    accentPressed: Color(0xFF2450CC),
    accentSoft: Color(0x1F2E5FE8),
    accentAlt: Color(0xFF6D3FE0),
    glow: Color(0x332E5FE8),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF12875A),
    successSoft: Color(0x1F12875A),
    danger: Color(0xFFC93B33),
    dangerSoft: Color(0x1FC93B33),
    warning: Color(0xFFB1751A),
    warningSoft: Color(0x1FB1751A),
    textPrimary: Color(0xFF0B1A33),
    textSecondary: Color(0xFF46587A),
    textTertiary: Color(0xFF55698C),
    scrim: Color(0x800B1A33),
    skeletonBase: Color(0xFFDCE8F8),
    skeletonHighlight: Color(0xFFF1F7FE),
    shadow: Color(0x1A0B1A33),
  );

  /// The link sheet's own scheme: the half sheet a share or a pasted link
  /// opens, whichever theme the app is in.
  ///
  /// Light and low-glare on purpose. It appears over other apps, often at
  /// night, so the surfaces are soft neutral whites rather than pure white,
  /// with no blue cast, and the text is a deep slate rather than black — high
  /// contrast without the harshness. The brand blue stays only where it does
  /// work: the download button, the selected option, the progress ring.
  static const HozaPalette sheet = HozaPalette(
    background: Color(0xFFF4F6F9),
    backgroundTint: Color(0xFFE9EEF6),
    surface: Color(0xFFFBFCFE),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF2F7),
    border: Color(0xFFE1E6EE),
    borderStrong: Color(0xFFC9D2DF),
    accent: Color(0xFF3568E0),
    accentPressed: Color(0xFF2A56C2),
    accentSoft: Color(0x1A3568E0),
    accentAlt: Color(0xFF6A4BDB),
    glow: Color(0x2E3568E0),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF178A5C),
    successSoft: Color(0x1F178A5C),
    danger: Color(0xFFC63F38),
    dangerSoft: Color(0x1FC63F38),
    warning: Color(0xFFA8701A),
    warningSoft: Color(0x1FA8701A),
    textPrimary: Color(0xFF1B2434),
    textSecondary: Color(0xFF4F5B70),
    textTertiary: Color(0xFF6B7789),
    scrim: Color(0x7A0B1A33),
    skeletonBase: Color(0xFFE9EEF5),
    skeletonHighlight: Color(0xFFF7F9FC),
    shadow: Color(0x140B1A33),
  );

  @override
  HozaPalette copyWith({
    Color? background,
    Color? backgroundTint,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentPressed,
    Color? accentSoft,
    Color? accentAlt,
    Color? glow,
    Color? onAccent,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? scrim,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? shadow,
  }) {
    return HozaPalette(
      background: background ?? this.background,
      backgroundTint: backgroundTint ?? this.backgroundTint,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSoft: accentSoft ?? this.accentSoft,
      accentAlt: accentAlt ?? this.accentAlt,
      glow: glow ?? this.glow,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      scrim: scrim ?? this.scrim,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  HozaPalette lerp(ThemeExtension<HozaPalette>? other, double t) {
    if (other is! HozaPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return HozaPalette(
      background: mix(background, other.background),
      backgroundTint: mix(backgroundTint, other.backgroundTint),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      accent: mix(accent, other.accent),
      accentPressed: mix(accentPressed, other.accentPressed),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentAlt: mix(accentAlt, other.accentAlt),
      glow: mix(glow, other.glow),
      onAccent: mix(onAccent, other.onAccent),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      scrim: mix(scrim, other.scrim),
      skeletonBase: mix(skeletonBase, other.skeletonBase),
      skeletonHighlight: mix(skeletonHighlight, other.skeletonHighlight),
      shadow: mix(shadow, other.shadow),
    );
  }

  /// The brand gradient: [accent] into [accentAlt], top-left to bottom-right.
  ///
  /// Declared once so every mark, pill and primary button shares the exact
  /// same ramp, and both themes get the same treatment.
  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentAlt],
  );
}

extension HozaPaletteX on BuildContext {
  /// Shorthand for the active Hoza colour tokens.
  HozaPalette get colors =>
      Theme.of(this).extension<HozaPalette>() ?? HozaPalette.dark;
}
