import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const _font = 'Outfit';
  static const radius = 22.0;

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: AppColors.darkBg,
        surface: AppColors.darkSurface,
        text: AppColors.darkText,
        muted: AppColors.darkMuted,
        border: AppColors.darkBorder,
        palette: AppPalette.dark,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: AppColors.lightBg,
        surface: AppColors.lightSurface,
        text: AppColors.lightText,
        muted: AppColors.lightMuted,
        border: AppColors.lightBorder,
        palette: AppPalette.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color text,
    required Color muted,
    required Color border,
    required AppPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.saffron,
      onPrimary: Colors.white,
      secondary: AppColors.tomato,
      onSecondary: Colors.white,
      tertiary: AppColors.herb,
      onTertiary: Colors.white,
      error: AppColors.expired,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: palette.card,
      outline: border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _font,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: [palette],
    );

    final tt = base.textTheme.apply(bodyColor: text, displayColor: text);
    final textTheme = tt.copyWith(
      displaySmall: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 17),
      bodyLarge: tt.bodyLarge?.copyWith(fontSize: 17, height: 1.45),
      bodyMedium: tt.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
      bodySmall: tt.bodySmall?.copyWith(color: muted, fontSize: 13),
      labelLarge: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
    );

    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: text,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontFamily: _font),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF221C2B) : const Color(0xFFFFF3E8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: ob(border),
        enabledBorder: ob(border),
        focusedBorder: ob(AppColors.saffron, 1.6),
        errorBorder: ob(AppColors.expired),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        prefixIconColor: muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          backgroundColor: AppColors.saffron,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          foregroundColor: text,
          side: BorderSide(color: border, width: 1.2),
          textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.saffron,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.card,
        selectedColor: AppColors.saffron.withValues(alpha: 0.18),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: TextStyle(fontFamily: _font, color: text, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2333) : const Color(0xFF2A1E17),
        contentTextStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.saffron : border,
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.saffron,
        thumbColor: AppColors.saffron,
        inactiveTrackColor: border,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.saffron),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
