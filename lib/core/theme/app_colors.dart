import 'package:flutter/material.dart';

/// Warm "spice market at night" palette. Saffron & tomato accents on a deep
/// aubergine base for dark mode, cream & paprika for light mode.
class AppColors {
  AppColors._();

  static const saffron = Color(0xFFFF8A3D);
  static const tomato = Color(0xFFFF4D6D);
  static const turmeric = Color(0xFFFFC145);
  static const herb = Color(0xFF34D399);
  static const mint = Color(0xFF2DD4BF);
  static const berry = Color(0xFFA78BFA);
  static const sky = Color(0xFF60A5FA);
  static const chili = Color(0xFFF87171);

  static const fresh = Color(0xFF22C55E);
  static const expiring = Color(0xFFF59E0B);
  static const expired = Color(0xFFEF4444);

  // Dark
  static const darkBg = Color(0xFF0E0B13);
  static const darkSurface = Color(0xFF17131E);
  static const darkCard = Color(0xFF1C1724);
  static const darkBorder = Color(0xFF2C2537);
  static const darkText = Color(0xFFF7F2EE);
  static const darkMuted = Color(0xFF9C93A8);

  // Light
  static const lightBg = Color(0xFFFFF8F1);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFF0E3D6);
  static const lightText = Color(0xFF2A1E17);
  static const lightMuted = Color(0xFF8A7568);

  static const primaryGradient = LinearGradient(
    colors: [saffron, tomato],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const aiGradient = LinearGradient(
    colors: [Color(0xFFFF8A3D), Color(0xFFE0457B), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Deterministic pleasant gradient for a string (recipe art, avatars).
  static LinearGradient gradientFor(String seed) {
    const pairs = [
      [Color(0xFFFF9A5A), Color(0xFFFF5E62)],
      [Color(0xFFF6D365), Color(0xFFFDA085)],
      [Color(0xFF84FAB0), Color(0xFF26A69A)],
      [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
      [Color(0xFFFCCB90), Color(0xFFD57EEB)],
      [Color(0xFF43E97B), Color(0xFF38F9D7)],
      [Color(0xFFFA709A), Color(0xFFFEE140)],
      [Color(0xFF667EEA), Color(0xFF764BA2)],
      [Color(0xFFFF8008), Color(0xFFFFC837)],
    ];
    final i = seed.codeUnits.fold<int>(0, (a, b) => a + b) % pairs.length;
    return LinearGradient(
      colors: pairs[i],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

/// Theme-aware colors not covered by ColorScheme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.card,
    required this.border,
    required this.muted,
    required this.glow,
  });

  final Color card;
  final Color border;
  final Color muted;
  final Color glow;

  static const dark = AppPalette(
    card: AppColors.darkCard,
    border: AppColors.darkBorder,
    muted: AppColors.darkMuted,
    glow: Color(0x40FF8A3D),
  );

  static const light = AppPalette(
    card: AppColors.lightCard,
    border: AppColors.lightBorder,
    muted: AppColors.lightMuted,
    glow: Color(0x26FF8A3D),
  );

  @override
  AppPalette copyWith({Color? card, Color? border, Color? muted, Color? glow}) =>
      AppPalette(
        card: card ?? this.card,
        border: border ?? this.border,
        muted: muted ?? this.muted,
        glow: glow ?? this.glow,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

extension AppThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
