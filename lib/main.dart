import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'marca.dart';
import 'tema.dart';
import 'telas/login.dart';
import 'telas/modo_curral.dart';
import 'widgets/logo_eito.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Modo offline obrigatório: tudo é gravado primeiro no aparelho e a
  // nuvem recebe sozinha quando o celular pega sinal.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // E-mails de verificação e recuperação de senha em português.
  await FirebaseAuth.instance.setLanguageCode('pt');

  runApp(const EitoApp());
}

class EitoApp extends StatelessWidget {
  const EitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Marca.nome,
      debugShowCheckedModeBanner: false,
      theme: temaEito(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const TelaCarregando();
          }
          final usuario = snap.data;
          if (usuario == null) return const TelaLogin();
          // A key garante um Modo Curral novo se outra pessoa entrar.
          return ModoCurral(key: ValueKey(usuario.uid), usuario: usuario);
        },
      ),
    );
  }
}
