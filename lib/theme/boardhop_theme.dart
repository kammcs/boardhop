import 'package:flutter/material.dart';

import 'boardhop_colors.dart';
import 'tokens.dart';

/// The master theme. `main` builds both variants once and hands them to
/// `MaterialApp`; every screen inherits from here and reads values through
/// `Theme.of(context)`, never from literals.
///
/// To retune the whole app, change [seed] (brand hue), the component blocks
/// in [_build], or the domain palette in `BoardhopColors`.
abstract final class BoardhopTheme {
  /// Neutral slate seed. Material 3 derives the full light and dark schemes
  /// from it with the `neutral` variant, so the chrome stays quiet and the
  /// colors that carry meaning (team lane colors, work item types, states,
  /// PR and pipeline status) are the only saturated things on screen.
  static const Color seed = Color(0xFF64748B);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// Largest a floating snackbar gets. Material's own guidance is that a
  /// snackbar stays near one end of a wide window rather than spanning it;
  /// 560 pt is about 70 characters of `bodyMedium`, past which the eye has
  /// to travel back for the action.
  static const double snackBarMaxWidth = 560;

  /// [base] adjusted for a window this wide. The snackbar is the only
  /// component whose look depends on the window rather than the widget:
  /// `SnackBarThemeData.width` is read when the bar is shown, and there is
  /// no per-snackbar call site to fix, so the app wraps its routes in this
  /// (see `lib/app.dart`).
  ///
  /// A phone keeps the full-width bar; from [Breakpoint.medium] up the bar
  /// is capped and floats centred, so one line of text no longer runs the
  /// whole iPad (iPad walkthrough, finding h).
  static ThemeData forWindow(ThemeData base, double width) {
    if (width <= snackBarMaxWidth + 2 * Spacing.lg) return base;
    return base.copyWith(
      snackBarTheme: base.snackBarTheme.copyWith(width: snackBarMaxWidth),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    final isDark = brightness == Brightness.dark;
    final domain = isDark ? BoardhopColors.dark : BoardhopColors.light;

    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      // Page transitions stay at the Material 3 defaults, which are already
      // platform-adaptive (Cupertino on iOS). Widgets with `.adaptive`
      // constructors (Switch, Slider, AlertDialog, CircularProgressIndicator)
      // should use them.
    );

    final textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[domain],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.xs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        minVerticalPadding: Spacing.sm,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Never Size.fromHeight here: an infinite minimum width forces
          // infinite constraints on a FilledButton inside a Row. Full-width
          // CTAs get their width from a stretched Column or a ListView.
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.chip),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
        ),
      ),
      // A floating snackbar still stretches the whole window, so on an
      // iPad one line of text ran the full 1032 pt (iPad walkthrough,
      // finding h). `BoardhopTheme.forWindow` caps it; see there.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        dividerColor: scheme.outlineVariant,
      ),
    );
  }

  /// System font on each platform (Roboto / SF). Weights are nudged so
  /// titles read as headings without a display face. Monospace comes from
  /// [codeStyle].
  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  /// Monospace style for code, diffs, IDs and diagnostics.
  static TextStyle codeStyle(BuildContext context) {
    final t = Theme.of(context);
    return t.textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono'],
      color: t.colorScheme.onSurface,
      height: 1.4,
    );
  }
}
