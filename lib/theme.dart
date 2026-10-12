import 'package:flutter/material.dart';

/// Jeti's palette: near-black surfaces with a hint of green, and a green
/// accent for what to press (Install, Update) and what's new.
abstract final class AppColors {
  static const background = Color(0xFF090C0A);
  static const surface = Color(0xFF111613);
  static const surfaceHigh = Color(0xFF1A211C);
  static const accent = Color(0xFF4ADE80);

  /// Text and icons on the accent colour.
  static const onAccent = Color(0xFF052E16);

  /// Accent-tinted fill for secondary buttons and the update banner.
  static const accentSoft = Color(0x2E4ADE80);
  static const accentFaint = Color(0x144ADE80);
  static const danger = Color(0xFFF87171);
  static const textSecondary = Color(0xFFA9B3AC);

  /// Still 4.5:1 on [surface], as small text needs.
  static const textTertiary = Color(0xFF85908A);
  static const divider = Color(0x14FFFFFF);
  static const outline = Color(0x26FFFFFF);
}

abstract final class AppRadius {
  static const icon = 16.0;
  static const card = 20.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.accent,
    surface: AppColors.background,
    onSurface: Colors.white,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: AppColors.outline,
    outlineVariant: AppColors.divider,
    error: AppColors.danger,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white);
  const stadium = StadiumBorder();
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  const buttonText = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
      bodySmall: text.bodySmall?.copyWith(color: AppColors.textTertiary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: stadium, padding: buttonPadding, textStyle: buttonText),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: stadium, padding: buttonPadding, textStyle: buttonText),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.accentSoft,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.all(Radius.circular(8))),
      textStyle: TextStyle(color: Colors.white, fontSize: 12),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
  );
}
