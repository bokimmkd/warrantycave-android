import 'package:flutter/material.dart';
import 'design_system.dart';

export 'design_system.dart';

const caveNavy = AppColors.navy;
const caveBlue = AppColors.caveBlue;
const caveTeal = AppColors.teal;
const skyBlue = AppColors.sky;
const softBackground = AppColors.background;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: caveBlue,
    primary: caveBlue,
    secondary: caveTeal,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: softBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: softBackground,
      foregroundColor: caveNavy,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE5EEF5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9E6F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9E6F0)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: caveBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: caveTeal.withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? caveBlue
              : Colors.blueGrey.shade600,
        ),
      ),
    ),
  );
}
