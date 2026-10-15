import 'package:flutter/material.dart';

/// Identidade visual do Eito: cores da bandeira do Brasil.
/// Os nomes antigos foram mantidos para não mexer no app inteiro:
/// [oliva] = verde da bandeira, [laranja] = amarelo (destaque),
/// [azul] = azul da bandeira. Texto sobre o amarelo vai em azul.
class Cores {
  static const oliva = Color(0xFF009C3B); // verde da bandeira
  static const olivaEscuro = Color(0xFF00602A); // verde escuro (barras do topo)
  static const olivaClaro = Color(0xFF1E8449);
  static const laranja = Color(0xFFFFDF00); // amarelo da bandeira
  static const azul = Color(0xFF002776); // azul da bandeira
  static const palha = Color(0xFFF5F8F3); // fundo claro, legível no sol
  static const tinta = Color(0xFF0B1F14);
  static const alerta = Color(0xFFB3261E);
  static const sucesso = Color(0xFF2E7D32);
}

ThemeData temaEito() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.oliva,
    primary: Cores.oliva,
    secondary: Cores.laranja,
    onSecondary: Cores.azul,
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
      indicatorColor: Cores.oliva,
      labelStyle: TextStyle(fontWeight: FontWeight.w800),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Cores.laranja,
      foregroundColor: Cores.azul,
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
