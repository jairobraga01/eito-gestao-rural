import 'package:flutter/material.dart';

/// Identidade visual do Eito.
/// Verde oliva = raiz, terra, campo. Laranja = tecnologia, precisão.
/// (Para trocar o laranja por azul elétrico, mude só [Cores.laranja],
/// por exemplo para Color(0xFF1F6BFF), e o ícone em assets/logo.)
class Cores {
  static const oliva = Color(0xFF3F4B1F);
  static const olivaEscuro = Color(0xFF262E12);
  static const olivaClaro = Color(0xFF6B7A3A);
  static const laranja = Color(0xFFFF6A13);
  static const palha = Color(0xFFF4F1E6); // fundo claro, legível no sol
  static const tinta = Color(0xFF1B1F10);
  static const alerta = Color(0xFFB3261E);
  static const sucesso = Color(0xFF2E7D32);
}

ThemeData temaEito() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.oliva,
    primary: Cores.oliva,
    secondary: Cores.laranja,
    surface: Cores.palha,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: esquema);
  return base.copyWith(
    scaffoldBackgroundColor: Cores.palha,
    // Letras maiores que o padrão: o app é usado no curral, de pé, no sol.
    textTheme: base.textTheme.apply(
      fontSizeFactor: 1.12,
      bodyColor: Cores.tinta,
      displayColor: Cores.tinta,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.olivaEscuro,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
      iconTheme: IconThemeData(size: 28, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        foregroundColor: Cores.oliva,
        side: const BorderSide(color: Cores.oliva, width: 2),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      labelStyle: const TextStyle(fontSize: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontSize: 18),
    ),
  );
}
