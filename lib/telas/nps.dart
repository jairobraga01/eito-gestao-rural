import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dados/painel_criador.dart';
import '../dados/plataforma.dart';
import '../tema.dart';
import '../util/util.dart';

/// Pergunta "de 0 a 10, quanto você indicaria o Eito?" para quem tem conta há
/// 21 dias ou mais. Uma vez só; quem toca em "Agora não" é perguntado de novo
/// depois de 30 dias. A nota vai para nps/{uid} e aparece no Painel do criador.
Future<void> pedirNps(BuildContext context) async {
  final u = FirebaseAuth.instance.currentUser;
  final criado = dataDe(Plataforma.conta.value?['criado_em']);
  if (u == null || criado == null || DateTime.now().difference(criado).inDays < 21) return;
  SharedPreferences? p;
  try {
    p = await SharedPreferences.getInstance();
    if (p.getBool('nps_respondido') == true) return;
    final adiado = DateTime.tryParse(p.getString('nps_adiado') ?? '');
    if (adiado != null && DateTime.now().difference(adiado).inDays < 30) return;
    if ((await PainelCriador.nps.doc(u.uid).get()).exists) {
      await p.setBool('nps_respondido', true);
      return;
    }
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  int? nota;
  final comentario = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('De 0 a 10, quanto você indicaria o Eito Gestão a um amigo?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var n = 0; n <= 10; n++)
                ChoiceChip(
                  label: Text('$n'),
                  selected: nota == n,
                  selectedColor: n >= 9 ? Cores.sucesso : (n <= 6 ? Cores.alerta : Cores.laranja),
                  onSelected: (_) => set(() => nota = n),
                ),
            ]),
            gap,
            campoTexto(comentario, 'O que podemos melhorar? (opcional)', linhas: 3),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          FilledButton(onPressed: nota == null ? null : () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    ),
  );
  final texto = comentario.text.trim();
  comentario.dispose();
  try {
    if (ok == true && nota != null) {
      await PainelCriador.nps.doc(u.uid).set({
        'nota': nota,
        'comentario': texto,
        'email': u.email ?? '',
        'plano': '${Plataforma.conta.value?['plano'] ?? 'Teste'}',
        'em': DateTime.now().toIso8601String(),
      });
      await p.setBool('nps_respondido', true);
      if (context.mounted) avisar(context, 'Obrigado pela nota!');
    } else {
      await p.setString('nps_adiado', DateTime.now().toIso8601String());
    }
  } catch (_) {}
}
