import 'package:flutter/material.dart';

/// Central color tokens. Values are taken directly from the web app's CSS
/// so both apps look identical.
class MarleyColors {
  static const accent = Color(0xFF5856D6);

  static const greenLight = Color(0xFF2CA24B);
  static const greenDark = Color(0xFF4ADE80);
  static const redLight = Color(0xFFD43D51);
  static const redDark = Color(0xFFF87171);

  static const bgAppLight = Color(0xFFF6F5F1);
  static const bgCardLight = Color(0xFFFFFFFF);
  static const bgAppDark = Color(0xFF141427);
  static const bgCardDark = Color(0xFF1E1E3A);

  static const incomeGreen = Color(0xFF34C759);
  static const spendingPurple = Color(0xFF5856D6);
  static const netWorthLine = Color(0xFF111111);

  static Color green(Brightness b) =>
      b == Brightness.dark ? greenDark : greenLight;
  static Color red(Brightness b) => b == Brightness.dark ? redDark : redLight;
  static Color bgApp(Brightness b) =>
      b == Brightness.dark ? bgAppDark : bgAppLight;
  static Color bgCard(Brightness b) =>
      b == Brightness.dark ? bgCardDark : bgCardLight;
}

/// Row background tints keyed by `Txn.style`.
Color? rowColorForStyle(String style, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  switch (style) {
    case 'opening':
      return dark ? const Color(0xFF23324A) : const Color(0xFFE7EEF5);
    case 'salary':
      return dark ? const Color(0xFF1E3A2A) : const Color(0xFFE6F6EA);
    case 'critical':
      return dark ? const Color(0xFF3A1F24) : const Color(0xFFFBE7E9);
    case 'warning':
      return dark ? const Color(0xFF3A331A) : const Color(0xFFFDF3D8);
    case 'fixed':
      return dark ? const Color(0xFF25253F) : const Color(0xFFF1F0EC);
    case 'adjustment':
      return dark ? const Color(0xFF2A2440) : const Color(0xFFEFEAF7);
    case 'normal':
    default:
      return null;
  }
}

ThemeData buildMarleyTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MarleyColors.accent,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: MarleyColors.bgApp(brightness),
    cardColor: MarleyColors.bgCard(brightness),
    fontFamily: 'SF Pro Text',
    appBarTheme: AppBarTheme(
      backgroundColor: MarleyColors.bgApp(brightness),
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black,
      ),
    ),
    cardTheme: CardThemeData(
      color: MarleyColors.bgCard(brightness),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarleyColors.bgCard(brightness),
      indicatorColor: MarleyColors.accent.withValues(alpha: 0.18),
    ),
    textTheme: const TextTheme(
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(fontWeight: FontWeight.w500),
    ),
  );
}

/// Determines whether it should be dark by default given the current time
/// of day: dark between 18:00 and 06:00.
bool isNightHour(DateTime now) => now.hour >= 18 || now.hour < 6;
