import 'package:flutter/material.dart';

import '../dados/clima.dart';
import '../dados/db.dart';
import '../dados/mapa.dart' show Ponto;
import '../dispositivos/gps.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

const _semanas = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

IconData iconeTempo(int? c) {
  if (c == null) return Icons.cloud_outlined;
  if (c == 0) return Icons.wb_sunny_outlined;
  if (c <= 2) return Icons.wb_cloudy_outlined;
  if (c == 3 || c == 45 || c == 48) return Icons.cloud_outlined;
  if (c >= 95) return Icons.thunderstorm_outlined;
  if (c >= 51) return Icons.water_drop_outlined;
  return Icons.cloud_outlined;
}

/// Clima da fazenda: agora e próximos 7 dias.
class ClimaPage extends StatefulWidget {
  const ClimaPage({super.key});

  @override
  State<ClimaPage> createState() => _ClimaPageState();
}

class _ClimaPageState extends State<ClimaPage> {
  Future<Clima>? _f;
  Ponto? _local;
  int _pid = -1;

  void _carregar() {
    _pid = Db.pid;
    _local = localDaFazenda(_pid);
    _f = _local == null ? null : buscarClima(_local!);
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _usarGps() async {
    String? erro;
    final p = await minhaPosicao(erro: (e) => erro = e);
    if (!mounted) return;
    if (p == null) {
      avisar(context, erro ?? 'Não foi possível pegar a posição.');
      return;
    }
    await salvarLocal(Db.pid, p);
    setState(_carregar);
  }

  Future<void> _digitar() async {
    final lat = TextEditingController(text: _local?.lat.toStringAsFixed(5) ?? '');
    final lng = TextEditingController(text: _local?.lng.toStringAsFixed(5) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Localização da fazenda'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Use o formato do Google Maps, ex.: -8.8458 e -48.5105'),
          gap,
          TextField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude')),
          gap,
          TextField(
              controller: lng,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitude')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    final a = double.tryParse(lat.text.trim().replaceAll(',', '.'));
    final b = double.tryParse(lng.text.trim().replaceAll(',', '.'));
    lat.dispose();
    lng.dispose();
    if (ok != true || !mounted) return;
    if (a == null || b == null || a.abs() > 90 || b.abs() > 180) {
      avisar(context, 'Latitude ou longitude inválida.');
      return;
    }
    await salvarLocal(Db.pid, (lat: a, lng: b));
    setState(_carregar);
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Previsão 07 Dias',
      acoes: [
        IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: () => setState(_carregar)),
      ],
      corpo: ValueListenableBuilder<Reg?>(
        valueListenable: Db.prop,
        builder: (context, _, __) {
          if (Db.pid != _pid) _carregar();
          final f = _f;
          if (f == null) return _semLocal();
          return FutureBuilder<Clima>(
            future: f,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) {
                return Vazio('Sem previsão agora (${s.error}). Confira a internet e toque em atualizar.',
                    icone: Icons.cloud_off_outlined);
              }
              return _previsao(s.data!);
            },
          );
        },
      ),
    );
  }

  Widget _semLocal() => ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.location_off_outlined, size: 48, color: Cores.oliva),
        gap,
        const Text(
          'Falta a localização desta propriedade. Marque agora (estando na fazenda) ou digite as coordenadas. '
          'Se você desenhar os piquetes no Mapa, o Eito usa o centro deles.',
          textAlign: TextAlign.center,
        ),
        gap,
        FilledButton.icon(onPressed: _usarGps, icon: const Icon(Icons.my_location), label: const Text('Usar minha posição')),
        gap,
        OutlinedButton.icon(onPressed: _digitar, icon: const Icon(Icons.edit_location_alt_outlined), label: const Text('Digitar coordenadas')),
      ]);

  Widget _previsao(Clima c) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Card(
        margin: const EdgeInsets.all(12),
        color: Cores.azul,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(iconeTempo(c.codigo), size: 56, color: Cores.laranja),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.temperatura == null ? '—' : '${c.temperatura!.round()}°C',
                    style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                Text(descricaoTempo(c.codigo), style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text(
                  [
                    if (c.umidade != null) 'Umidade ${c.umidade!.round()}%',
                    if (c.vento != null) 'Vento ${c.vento!.round()} km/h',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70),
                ),
              ]),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Chuva prevista nos 7 dias: ${num1(c.chuva7Dias)} mm', style: t.titleMedium),
      ),
      const Secao('Próximos dias'),
      for (final d in c.dias)
        ListTile(
          leading: Icon(iconeTempo(d.codigo), color: Cores.oliva),
          title: Text('${_diaSemana(d.data)} · ${br(d.data).length >= 5 ? br(d.data).substring(0, 5) : d.data}'),
          subtitle: Text(descricaoTempo(d.codigo)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${d.max?.round() ?? '—'}° / ${d.min?.round() ?? '—'}°', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              '${num1(d.chuvaMm ?? 0)} mm${d.chanceChuva == null ? '' : ' · ${d.chanceChuva}%'}',
              style: const TextStyle(color: Colors.blue),
            ),
          ]),
        ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.place_outlined),
        title: const Text('Localização usada'),
        subtitle: Text(_local == null ? '—' : '${_local!.lat.toStringAsFixed(4)}, ${_local!.lng.toStringAsFixed(4)}'),
        trailing: TextButton(onPressed: _digitar, child: const Text('Mudar')),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Previsão: Open-Meteo.com', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    ]);
  }

  String _diaSemana(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final hoje = DateTime.now();
    if (d.year == hoje.year && d.month == hoje.month && d.day == hoje.day) return 'Hoje';
    return _semanas[d.weekday - 1];
  }
}
