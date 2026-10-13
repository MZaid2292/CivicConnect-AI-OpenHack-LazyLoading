import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Brand and semantic hues. Widgets should NOT use these directly for
/// surfaces or text — read `Theme.of(context).colorScheme` / `context.civic`
/// instead so light and dark mode both work. Semantic hues used for status
/// indicators go through [CivicPalette.tone] to stay readable in dark mode.
class AppColors {
  const AppColors._();
  // Brand
  static const civicBlue = Color(0xFF1D4ED8);
  static const navy = Color(0xFF0B1F4B);
  static const royal = civicBlue;
  static const teal = Color(0xFF0D9488);
  static const emerald = Color(0xFF059669);
  static const cyan = Color(0xFF0891B2);
  // Semantic hues
  static const amber = Color(0xFFB45309);
  static const orange = Color(0xFFC2410C);
  static const red = Color(0xFFB91C1C);
  static const purple = Color(0xFF6D28D9);
  static const indigo = Color(0xFF4338CA);
  static const green = Color(0xFF15803D);
  static const slate = Color(0xFF64748B);
}

/// Extra design tokens not covered by [ColorScheme].
@immutable
class CivicPalette extends ThemeExtension<CivicPalette> {
  const CivicPalette({
    required this.isDark,
    required this.muted,
    required this.subtle,
    required this.border,
    required this.raised,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.heroStart,
    required this.heroEnd,
    required this.shadow,
  });

  final bool isDark;

  /// Secondary text.
  final Color muted;

  /// Tertiary text / disabled icons.
  final Color subtle;

  /// Hairline borders around cards and inputs.
  final Color border;

  /// Slightly raised surface (chips, input fills, nested panels).
  final Color raised;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Brand gradient for hero headers.
  final Color heroStart;
  final Color heroEnd;
  final Color shadow;

  static const light = CivicPalette(
    isDark: false,
    muted: Color(0xFF5B6B82),
    subtle: Color(0xFF94A3B8),
    border: Color(0xFFE3E8F0),
    raised: Color(0xFFF1F4F9),
    success: Color(0xFF047857),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    info: Color(0xFF1D4ED8),
    heroStart: Color(0xFF0B1F4B),
    heroEnd: Color(0xFF1D4ED8),
    shadow: Color(0x140F172A),
  );

  static const dark = CivicPalette(
    isDark: true,
    muted: Color(0xFFA3B1C6),
    subtle: Color(0xFF6B7A93),
    border: Color(0xFF26324A),
    raised: Color(0xFF1A2438),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF93B4FF),
    heroStart: Color(0xFF0E1A3A),
    heroEnd: Color(0xFF1E3A8A),
    shadow: Color(0x00000000),
  );

  /// Adapts a semantic hue for the current brightness: unchanged in light
  /// mode, lightened in dark mode so text/icons keep contrast.
  Color tone(Color c) => isDark ? Color.lerp(c, Colors.white, 0.45)! : c;

  /// Soft tinted background for badges/banners of hue [c].
  Color tint(Color c) => c.withValues(alpha: isDark ? 0.18 : 0.10);

  List<BoxShadow> get cardShadow => isDark
      ? const []
      : [BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8))];

  @override
  CivicPalette copyWith() => this;

  @override
  CivicPalette lerp(CivicPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CivicPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      muted: l(muted, other.muted),
      subtle: l(subtle, other.subtle),
      border: l(border, other.border),
      raised: l(raised, other.raised),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
      shadow: l(shadow, other.shadow),
    );
  }
}

extension CivicThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;
  CivicPalette get civic =>
      Theme.of(this).extension<CivicPalette>() ?? CivicPalette.light;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  /// Back-compat alias.
  static ThemeData get light => lightTheme;

  static ColorScheme _scheme(Brightness b) {
    final dark = b == Brightness.dark;
    return ColorScheme.fromSeed(seedColor: AppColors.civicBlue, brightness: b)
        .copyWith(
      primary: dark ? const Color(0xFF93B4FF) : AppColors.civicBlue,
      onPrimary: dark ? const Color(0xFF0A1A44) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF1E3A8A) : const Color(0xFFDCE6FF),
      onPrimaryContainer:
          dark ? const Color(0xFFDCE6FF) : const Color(0xFF0B1F4B),
      secondary: dark ? const Color(0xFF5EEAD4) : AppColors.teal,
      onSecondary: dark ? const Color(0xFF042F2E) : Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
      onSecondaryContainer:
          dark ? const Color(0xFFCCFBF1) : const Color(0xFF134E4A),
      tertiary: dark ? const Color(0xFF6EE7B7) : AppColors.emerald,
      onTertiary: dark ? const Color(0xFF022C22) : Colors.white,
      error: dark ? const Color(0xFFF87171) : AppColors.red,
      surface: dark ? const Color(0xFF111A2C) : Colors.white,
      onSurface: dark ? const Color(0xFFE6ECF5) : const Color(0xFF0F172A),
      onSurfaceVariant:
          dark ? const Color(0xFFA3B1C6) : const Color(0xFF5B6B82),
      surfaceContainerLowest:
          dark ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          dark ? const Color(0xFF0F1727) : const Color(0xFFF8FAFD),
      surfaceContainer:
          dark ? const Color(0xFF151F33) : const Color(0xFFF1F4F9),
      surfaceContainerHigh:
          dark ? const Color(0xFF1A2438) : const Color(0xFFEAEFF6),
      surfaceContainerHighest:
          dark ? const Color(0xFF212C42) : const Color(0xFFE3E8F0),
      outline: dark ? const Color(0xFF3A4864) : const Color(0xFFC7D0DD),
      outlineVariant: dark ? const Color(0xFF26324A) : const Color(0xFFE3E8F0),
    );
  }

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = _scheme(b);
    final palette = dark ? CivicPalette.dark : CivicPalette.light;
    final background = dark ? const Color(0xFF0B1220) : const Color(0xFFF4F6FB);
    final base =
        ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    final t = base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final text = t.copyWith(
      displaySmall: t.displaySmall?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1),
      headlineMedium: t.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: t.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: t.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: t.labelSmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
    );
    final overlay =
        (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent);
    final inputBorder = OutlineInputBorder(
        borderRadius: Radii.brMd,
        borderSide: BorderSide(color: palette.border));

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: text,
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        shadowColor: palette.border,
        centerTitle: false,
        elevation: 0,
        systemOverlayStyle: overlay,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: Radii.brLg, side: BorderSide(color: palette.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? palette.raised : Colors.white,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder:
            inputBorder.copyWith(borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: scheme.error, width: 1.6)),
        hintStyle: TextStyle(color: palette.subtle),
        helperStyle: TextStyle(color: palette.muted),
        helperMaxLines: 3,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md + 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: Radii.brLg),
        extendedTextStyle: text.labelLarge,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: palette.border),
        labelStyle: text.labelLarge?.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.pill)),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium
            ?.copyWith(
                fontWeight:
                    s.contains(WidgetState.selected) ? FontWeight.w700 : null)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        selectedLabelTextStyle:
            text.labelLarge?.copyWith(color: scheme.primary),
        unselectedLabelTextStyle:
            text.labelLarge?.copyWith(color: palette.muted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.brXl),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: Radii.brLg)),
          side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
        backgroundColor:
            dark ? const Color(0xFFE6ECF5) : const Color(0xFF0F172A),
        contentTextStyle: text.bodyMedium
            ?.copyWith(color: dark ? const Color(0xFF0F172A) : Colors.white),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
            color: dark ? const Color(0xFFE6ECF5) : const Color(0xFF0F172A),
            borderRadius: Radii.brSm),
        textStyle: text.bodySmall
            ?.copyWith(color: dark ? const Color(0xFF0F172A) : Colors.white),
      ),
      dividerTheme: DividerThemeData(color: palette.border, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: palette.muted,
        shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(0, 44),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: palette.muted,
        indicatorColor: scheme.primary,
        dividerColor: palette.border,
        labelStyle: text.labelLarge,
      ),
      badgeTheme: BadgeThemeData(
          backgroundColor: scheme.error, textColor: scheme.onError),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
