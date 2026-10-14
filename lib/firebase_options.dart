// Configuração do Firebase do projeto "Eito Gestão Rural"
// (ID interno do projeto: caderneta-rebanho — o Firebase não permite trocar o ID).
//
// A apiKey do Firebase Web é pública por natureza: quem protege os dados
// são as regras do Firestore (cada usuário só acessa usuarios/{uid}/...).
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'Por enquanto o Eito roda como app web (PWA) no iPhone, Android e '
      'computador. Para gerar o app nativo, rode "flutterfire configure".',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCqFQD2TOyqMoRQPNGpr7KpWj5fvU_2iIQ',
    authDomain: 'caderneta-rebanho.firebaseapp.com',
    projectId: 'caderneta-rebanho',
    storageBucket: 'caderneta-rebanho.firebasestorage.app',
    messagingSenderId: '776125088832',
    appId: '1:776125088832:web:692a6d0fa9dec625bc8ba5',
    measurementId: 'G-XY7DMT0SFG',
  );
}
