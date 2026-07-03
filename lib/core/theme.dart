import 'package:flutter/material.dart';

final priorTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1A5276), // deep water blue
    primary: const Color(0xFF0D3B66),
    secondary: const Color(0xFF2B6CB0),

    brightness: Brightness.dark,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
  ),
);
