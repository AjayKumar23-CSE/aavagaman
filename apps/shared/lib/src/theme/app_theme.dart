import 'package:flutter/material.dart';

/// Which app the theme is for: the rider app is blue, the driver app green,
/// so a driver testing both never confuses them. Everything else is shared.
enum AppBrand { rider, driver }

/// Colours beyond Material's scheme, read with `AppColors.of(context)`.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.ink,
    required this.gradientStart,
    required this.gradientEnd,
    required this.shadow,
  });

  /// Positive states: approved, paid, online.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Saffron highlight: fares, the trip OTP, earnings.
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;

  /// Deep navy used for immersive screens (offer popup, hero headers).
  final Color ink;

  /// Brand gradient (hero headers, the brand mark).
  final Color gradientStart;
  final Color gradientEnd;

  /// Soft card shadow.
  final Color shadow;

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientStart, gradientEnd],
      );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? ink,
    Color? gradientStart,
    Color? gradientEnd,
    Color? shadow,
  }) =>
      AppColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentContainer: accentContainer ?? this.accentContainer,
        onAccentContainer: onAccentContainer ?? this.onAccentContainer,
        ink: ink ?? this.ink,
        gradientStart: gradientStart ?? this.gradientStart,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        shadow: shadow ?? this.shadow,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentContainer: c(accentContainer, other.accentContainer),
      onAccentContainer: c(onAccentContainer, other.onAccentContainer),
      ink: c(ink, other.ink),
      gradientStart: c(gradientStart, other.gradientStart),
      gradientEnd: c(gradientEnd, other.gradientEnd),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Rounded, airy Material 3 theme shared by both apps: Plus Jakarta Sans,
/// 16–20 px radii, filled inputs, soft bordered cards.
class AppTheme {
  const AppTheme._();

  static const fontFamily = 'PlusJakartaSans';
  static const fontPackage = 'ride_shared';

  static const radiusSmall = 12.0;
  static const radius = 16.0;
  static const radiusLarge = 20.0;
  static const radiusSheet = 28.0;

  static ThemeData light({AppBrand brand = AppBrand.rider}) => _build(brand, Brightness.light);

  static ThemeData dark({AppBrand brand = AppBrand.rider}) => _build(brand, Brightness.dark);

  static ThemeData _build(AppBrand brand, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final (seed, primaryLight, primaryDark) = switch (brand) {
      // Aavagaman (D-057): deep green for riders, leaf green for drivers; mint on dark.
      AppBrand.rider => (const Color(0xFF0F3D2E), const Color(0xFF0F3D2E), const Color(0xFF4ADE80)),
      AppBrand.driver => (const Color(0xFF15803D), const Color(0xFF15803D), const Color(0xFF4ADE80)),
    };
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final scheme = dark
        ? base.copyWith(
            primary: primaryDark,
            onPrimary: const Color(0xFF052E16),
            primaryContainer: const Color(0xFF14532D),
            onPrimaryContainer: const Color(0xFFBBF7D0),
            tertiary: const Color(0xFFFBBF24),
            onTertiary: const Color(0xFF3B2600),
            tertiaryContainer: const Color(0xFF4A3300),
            onTertiaryContainer: const Color(0xFFFFE2A8),
            error: const Color(0xFFFF7B80),
            onError: const Color(0xFF3B0A0C),
            errorContainer: const Color(0xFF5A1E22),
            onErrorContainer: const Color(0xFFFFDADC),
            surface: const Color(0xFF080F14),
            onSurface: const Color(0xFFE6EAF2),
            onSurfaceVariant: const Color(0xFFA3ADC2),
            surfaceContainerLowest: const Color(0xFF05090C),
            surfaceContainerLow: const Color(0xFF0E1A1F),
            surfaceContainer: const Color(0xFF13222A),
            surfaceContainerHigh: const Color(0xFF1A2C34),
            surfaceContainerHighest: const Color(0xFF22363F),
            outline: const Color(0xFF3A4F55),
            outlineVariant: const Color(0xFF263247),
            inverseSurface: const Color(0xFFE6EAF2),
            onInverseSurface: const Color(0xFF080F14),
          )
        : base.copyWith(
            primary: primaryLight,
            onPrimary: Colors.white,
            primaryContainer: brand == AppBrand.rider ? const Color(0xFFD7F0E3) : const Color(0xFFDCFCE7),
            onPrimaryContainer: brand == AppBrand.rider ? const Color(0xFF0F3D2E) : const Color(0xFF14532D),
            secondary: const Color(0xFF334155),
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFE9EDF5),
            onSecondaryContainer: const Color(0xFF1E293B),
            tertiary: const Color(0xFFF59E0B),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFFFF1D6),
            onTertiaryContainer: const Color(0xFF7A4A00),
            error: const Color(0xFFE5484D),
            onError: Colors.white,
            errorContainer: const Color(0xFFFFE1E3),
            onErrorContainer: const Color(0xFF8C1D21),
            surface: Colors.white,
            onSurface: const Color(0xFF0F172A),
            onSurfaceVariant: const Color(0xFF5B6478),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF6F7FB),
            surfaceContainer: const Color(0xFFF1F4F9),
            surfaceContainerHigh: const Color(0xFFE9EDF5),
            surfaceContainerHighest: const Color(0xFFE2E7F0),
            outline: const Color(0xFFC8D0DD),
            outlineVariant: const Color(0xFFE6EAF2),
            inverseSurface: const Color(0xFF0F172A),
            onInverseSurface: Colors.white,
          );

    final colors = dark
        ? const AppColors(
            success: Color(0xFF4ADE80),
            onSuccess: Color(0xFF052E16),
            successContainer: Color(0xFF14432A),
            onSuccessContainer: Color(0xFFBBF7D0),
            accent: Color(0xFFFBBF24),
            onAccent: Color(0xFF3B2600),
            accentContainer: Color(0xFF4A3300),
            onAccentContainer: Color(0xFFFFE2A8),
            ink: Color(0xFF05090C),
            gradientStart: Color(0xFF0F3D2E),
            gradientEnd: Color(0xFF080F14),
            shadow: Color(0x66000000),
          )
        : AppColors(
            success: const Color(0xFF16A34A),
            onSuccess: Colors.white,
            successContainer: const Color(0xFFDCFCE7),
            onSuccessContainer: const Color(0xFF14532D),
            accent: const Color(0xFFF59E0B),
            onAccent: Colors.white,
            accentContainer: const Color(0xFFFFF1D6),
            onAccentContainer: const Color(0xFF7A4A00),
            ink: const Color(0xFF080F14),
            gradientStart: brand == AppBrand.rider ? const Color(0xFF145C45) : const Color(0xFF15803D),
            gradientEnd: brand == AppBrand.rider ? const Color(0xFF0B2A20) : const Color(0xFF0F3D2E),
            shadow: const Color(0x140F172A),
          );

    final text = _textTheme(scheme.onSurface, scheme.onSurfaceVariant);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      package: fontPackage,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      splashFactory: InkSparkle.splashFactory,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: shape,
          textStyle: text.titleMedium,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: shape,
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
          textStyle: text.titleMedium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.labelLarge?.copyWith(color: scheme.primary),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: text.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusSheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(radiusSheet)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }

  static TextTheme _textTheme(Color on, Color muted) {
    TextStyle s(double size, FontWeight weight, {double? height, double spacing = 0, Color? color}) => TextStyle(
          fontFamily: fontFamily,
          package: fontPackage,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: color ?? on,
        );
    return TextTheme(
      displayLarge: s(56, FontWeight.w800, height: 1.05, spacing: -1.5),
      displayMedium: s(44, FontWeight.w800, height: 1.1, spacing: -1),
      displaySmall: s(36, FontWeight.w800, height: 1.15, spacing: -0.5),
      headlineLarge: s(32, FontWeight.w800, height: 1.2, spacing: -0.5),
      headlineMedium: s(28, FontWeight.w800, height: 1.2, spacing: -0.4),
      headlineSmall: s(24, FontWeight.w700, height: 1.25, spacing: -0.3),
      titleLarge: s(20, FontWeight.w700, height: 1.3, spacing: -0.2),
      titleMedium: s(16, FontWeight.w700, height: 1.4),
      titleSmall: s(14, FontWeight.w700, height: 1.4),
      bodyLarge: s(16, FontWeight.w500, height: 1.5),
      bodyMedium: s(14, FontWeight.w500, height: 1.5, color: muted),
      bodySmall: s(12, FontWeight.w500, height: 1.45, color: muted),
      labelLarge: s(14, FontWeight.w700, height: 1.3),
      labelMedium: s(12, FontWeight.w700, height: 1.3, spacing: 0.2, color: muted),
      labelSmall: s(11, FontWeight.w700, height: 1.3, spacing: 0.6, color: muted),
    );
  }
}
