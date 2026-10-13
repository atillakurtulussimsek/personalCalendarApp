import 'package:flutter/material.dart';

const _seed = Color(0xFF3B82F6);

ThemeData lightTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

ThemeData darkTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}
