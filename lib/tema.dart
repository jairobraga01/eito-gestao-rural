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
  // O textTheme padrão só traz cores; os tamanhos vêm do Typography.
  // Sem juntar os dois, o aumento de letra abaixo não teria efeito.
  final texto = Typography.englishLike2021.merge(base.textTheme);
  return base.copyWith(
    scaffoldBackgroundColor: Cores.palha,
    // Letras um pouco maiores que o padrão: o app é usado no curral, de pé, no sol.
    textTheme: texto.apply(
      fontSizeFactor: 1.08,
      bodyColor: Cores.tinta,
      displayColor: Cores.tinta,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.olivaEscuro,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white),
      iconTheme: IconThemeData(size: 28, color: Colors.white),
      actionsIconTheme: IconThemeData(size: 26, color: Colors.white),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Cores.oliva,
      indicatorColor: Cores.laranja,
      labelStyle: TextStyle(fontWeight: FontWeight.w800),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Cores.laranja,
      foregroundColor: Colors.white,
    ),
    // Altura grande, mas largura mínima finita: com Size.fromHeight o botão
    // tenta ocupar largura infinita e quebra dentro de diálogos e linhas.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(88, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(88, 52),
        foregroundColor: Cores.oliva,
        side: const BorderSide(color: Cores.oliva, width: 2),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: const CardThemeData(color: Colors.white, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontSize: 17),
    ),
  );
}
