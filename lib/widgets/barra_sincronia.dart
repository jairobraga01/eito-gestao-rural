import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../tema.dart';

/// Faixa no topo que mostra, sem precisar pensar, se está tudo na nuvem
/// ou guardado no aparelho esperando sinal.
class BarraSincronia extends StatefulWidget {
  const BarraSincronia({super.key, required this.repo});
  final Repositorio repo;

  @override
  State<BarraSincronia> createState() => _BarraSincroniaState();
}

class _BarraSincroniaState extends State<BarraSincronia> {
  late final Stream<int> _pendentes = widget.repo.pendentes();
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
    return StreamBuilder<int>(
      stream: _pendentes,
      builder: (context, snap) {
        final n = snap.data ?? 0;
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icone, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(texto,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
