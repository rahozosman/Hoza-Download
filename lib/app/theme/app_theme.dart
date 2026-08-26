import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_motion.dart';
import 'app_typography.dart';

/// Builds the two Hoza [ThemeData] variants from a single [HozaPalette].
///
/// Every component style lives here so screens stay declarative and no widget
/// has to reach for a raw colour value.
abstract final class AppTheme {
  static ThemeData get dark => _build(HozaPalette.dark, Brightness.dark);
  static ThemeData get light => _build(HozaPalette.light, Brightness.light);

  /// The link sheet's theme: always light, whatever the app is set to. See
  /// [HozaPalette.sheet].
  static ThemeData get sheet => _build(HozaPalette.sheet, Brightness.light);

  /// System bars matched to the app background, per brightness.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  static ThemeData _build(HozaPalette p, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accent,
      secondary: p.success,
      onSecondary: p.onAccent,
      secondaryContainer: p.successSoft,
      onSecondaryContainer: p.success,
      error: p.danger,
      onError: p.onAccent,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceMuted,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.borderStrong,
      shadow: p.shadow,
      scrim: p.scrim,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.background,
      inversePrimary: p.accentPressed,
    );

    final text = AppTypography.textTheme(
      primary: p.textPrimary,
      secondary: p.textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      // InkSparkle compiles a runtime fragment shader on first touch, which
      // stalls (and on some Impeller builds kills) the raster thread the moment
      // the whole tree repaints — exactly what a theme change does. InkRipple
      // is pure geometry and behaves identically to the eye.
      splashFactory: InkRipple.splashFactory,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[p],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.pageTitle.copyWith(color: p.textPrimary),
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
        systemOverlayStyle: overlayStyle(brightness),
      ),
      iconTheme: IconThemeData(color: p.textSecondary, size: 22),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardRadius,
          side: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return p.accent.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) return p.accentPressed;
            return p.accent;
          }),
          foregroundColor: WidgetStateProperty.all(p.onAccent),
          overlayColor: WidgetStateProperty.all(
            p.onAccent.withValues(alpha: 0.08),
          ),
          textStyle: WidgetStateProperty.all(AppTypography.button),
          minimumSize: WidgetStateProperty.all(
            const Size.fromHeight(Layout.minTouchTarget + 4),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
          ),
          elevation: WidgetStateProperty.all(0),
          animationDuration: Motion.fast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(p.textPrimary),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return p.surfaceMuted;
            return Colors.transparent;
          }),
          side: WidgetStateProperty.all(BorderSide(color: p.borderStrong)),
          textStyle: WidgetStateProperty.all(AppTypography.button),
          minimumSize: WidgetStateProperty.all(
            const Size.fromHeight(Layout.minTouchTarget + 4),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
          ),
          animationDuration: Motion.fast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(p.accent),
          textStyle: WidgetStateProperty.all(AppTypography.button),
          overlayColor: WidgetStateProperty.all(p.accentSoft),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: Radii.tileRadius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(p.textSecondary),
          overlayColor: WidgetStateProperty.all(
            p.textPrimary.withValues(alpha: 0.06),
          ),
          minimumSize: WidgetStateProperty.all(
            const Size.square(Layout.minTouchTarget),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: AppTypography.body.copyWith(color: p.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.md,
        ),
        border: OutlineInputBorder(
          borderRadius: Radii.cardRadius,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.cardRadius,
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.cardRadius,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.cardRadius,
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.cardRadius,
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceMuted,
        selectedColor: p.accentSoft,
        disabledColor: p.surfaceMuted,
        side: BorderSide(color: p.border),
        labelStyle: AppTypography.caption.copyWith(color: p.textSecondary),
        secondaryLabelStyle: AppTypography.caption.copyWith(color: p.accent),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.xs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.pillRadius),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        modalBarrierColor: p.scrim,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.largeRadius,
          side: BorderSide(color: p.border),
        ),
        titleTextStyle: AppTypography.title.copyWith(color: p.textPrimary),
        contentTextStyle: AppTypography.body.copyWith(color: p.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceMuted,
        contentTextStyle: AppTypography.body.copyWith(color: p.textPrimary),
        actionTextColor: p.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.all(Gap.md),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardRadius,
          side: BorderSide(color: p.border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceMuted,
        circularTrackColor: p.surfaceMuted,
        linearMinHeight: 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onAccent;
          return p.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.borderStrong;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.textTertiary;
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: AppTypography.body.copyWith(color: p.textPrimary),
        subtitleTextStyle: AppTypography.bodySmall.copyWith(
          color: p.textSecondary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.tileRadius),
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
        minVerticalPadding: Gap.sm,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.shadow,
        textStyle: AppTypography.body.copyWith(color: p.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardRadius,
          side: BorderSide(color: p.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: Radii.tileRadius,
          border: Border.all(color: p.border),
        ),
        textStyle: AppTypography.caption.copyWith(color: p.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        elevation: 0,
        height: Layout.navBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(p.borderStrong),
        radius: const Radius.circular(Radii.pill),
        thickness: WidgetStateProperty.all(3),
      ),
      splashColor: p.accentSoft,
      highlightColor: Colors.transparent,
    );
  }
}
