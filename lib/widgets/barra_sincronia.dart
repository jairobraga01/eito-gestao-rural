import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../tema.dart';

/// Faixa que mostra, sem precisar pensar, se está tudo na nuvem ou
/// guardado no aparelho esperando sinal.
///
/// Com [sempre] = false (telas do app), só aparece quando há algo pendente
/// ou falta sinal. No Modo Curral fica sempre visível.
class BarraSincronia extends StatefulWidget {
  const BarraSincronia({super.key, this.sempre = false});
  final bool sempre;

  @override
  State<BarraSincronia> createState() => _BarraSincroniaState();
}

class _BarraSincroniaState extends State<BarraSincronia> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_atualizar);
    _sub = Connectivity().onConnectivityChanged.listen(_atualizar);
  }

  void _atualizar(List<ConnectivityResult> r) {
    if (!mounted) return;
    setState(() => _online = r.isNotEmpty && !r.contains(ConnectivityResult.none));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Db.pendentes,
      builder: (context, n, _) {
        if (!widget.sempre && _online && n == 0) return const SizedBox.shrink();
        final (Color cor, IconData icone, String texto) = !_online
            ? (
                Cores.tinta,
                Icons.cloud_off,
                n == 0
                    ? 'Sem sinal. Pode trabalhar: tudo fica salvo no aparelho.'
                    : 'Sem sinal. $n ${n == 1 ? 'lançamento guardado' : 'lançamentos guardados'} no aparelho.'
              )
            : n > 0
                ? (Cores.laranja, Icons.cloud_upload, 'Enviando $n ${n == 1 ? 'lançamento' : 'lançamentos'} para a nuvem…')
                : (Cores.olivaClaro, Icons.cloud_done, 'Tudo salvo na nuvem.');
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: cor,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.sempre ? 10 : 6),
            child: Row(children: [
              Icon(icone, color: Colors.white, size: widget.sempre ? 26 : 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(texto,
                    style: TextStyle(
                        color: Colors.white, fontSize: widget.sempre ? 16 : 14, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
