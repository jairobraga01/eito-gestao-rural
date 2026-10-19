// Mapa da fazenda: piquetes desenhados com lotação e rodízio, pontos
// (aguadas, cochos, cercas...) e ocorrências com foto e GPS.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../dados/db.dart';
import '../dados/mapa.dart';
import '../dispositivos/gps.dart';
import '../util/util.dart';
import 'base.dart';
import 'importar_kml.dart';
import 'piquetes.dart' show PiqueteDetalhePage;

LatLng _ll(Ponto p) => LatLng(p.lat, p.lng);
Ponto _pt(LatLng p) => (lat: p.latitude, lng: p.longitude);

Color corRodizio(SituacaoPasto? s) => switch (s) {
      SituacaoPasto.trocar => Colors.red,
      SituacaoPasto.ocupado => Colors.orange,
      SituacaoPasto.descansando => Colors.blueGrey,
      SituacaoPasto.pronto => Colors.green,
      _ => Colors.grey,
    };

IconData iconePonto(Object? tipo) => switch (tipo) {
      'Aguada' => Icons.water_drop,
      'Cocho' => Icons.inventory_2,
      'Saleiro' => Icons.grain,
      'Cerca / porteira' => Icons.fence,
      'Curral' => Icons.crop_square,
      'Sede' => Icons.home,
      _ => Icons.place,
    };

/// Pega a posição do GPS avisando o motivo quando não der.
Future<Ponto?> posicaoComAviso(BuildContext context) async {
  avisar(context, 'Buscando a posição pelo GPS…');
  final p = await minhaPosicao(erro: (e) {
    if (context.mounted) avisar(context, e);
  });
  return p;
}

enum _Modo { ver, desenhar, ponto, ocorrencia }

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  final _mapa = MapController();
  bool satelite = true;
  _Modo modo = _Modo.ver;
  Reg? desenhando;
  final contornoNovo = <Ponto>[];
  Ponto? eu;

  static const _centroPadrao = LatLng(-15.3, -49.1); // Goiás

  void _sair() => setState(() {
        modo = _Modo.ver;
        desenhando = null;
        contornoNovo.clear();
      });

  Future<void> _escolherPiqueteParaDesenhar() async {
    final ps = await Db.piquetes();
    if (!mounted) return;
    if (ps.isEmpty) {
      avisar(context, 'Cadastre os piquetes primeiro (menu Piquete/Pasto).');
      return;
    }
    final p = await showModalBottomSheet<Reg>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Qual piquete desenhar?', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final q in ps)
            ListTile(
              leading: Icon(contorno(q).length >= 3 ? Icons.check_circle : Icons.crop_free),
              title: Text(txt(q['nome'])),
              subtitle: Text(contorno(q).length >= 3 ? 'Já desenhado: refazer' : 'Sem contorno'),
              onTap: () => Navigator.pop(c, q),
            ),
        ]),
      ),
    );
    if (p == null) return;
    setState(() {
      modo = _Modo.desenhar;
      desenhando = p;
      contornoNovo.clear();
    });
  }

  Future<void> _salvarContorno() async {
    final p = desenhando;
    if (p == null) return;
    if (contornoNovo.length < 3) {
      avisar(context, 'Marque pelo menos 3 cantos.');
      return;
    }
    final area = areaHa(contornoNovo);
    var v = <String, Object?>{'contorno': contornoParaSalvar(contornoNovo)};
    final atual = p['area'];
    if (atual is! num || atual <= 0) {
      v['area'] = double.parse(area.toStringAsFixed(2));
    } else if ((atual - area).abs() / atual > 0.05) {
      final usar = await confirmar(context, 'Atualizar a área?',
          'A área cadastrada é ${num1(atual)} ha e o desenho dá ${num1(area)} ha. Usar a do desenho?',
          ok: 'Usar ${num1(area)} ha');
      if (usar) v = {...v, 'area': double.parse(area.toStringAsFixed(2))};
    }
    await Db.atualizar('piquetes', p['id'] as int, v);
    if (!mounted) return;
    avisar(context, 'Contorno de ${p['nome']} salvo (${num1(area)} ha).');
    _sair();
  }

  Future<void> _gps() async {
    final p = await posicaoComAviso(context);
    if (p == null || !mounted) return;
    setState(() => eu = p);
    if (modo == _Modo.desenhar) {
      setState(() => contornoNovo.add(p));
    } else {
      _mapa.move(_ll(p), 17);
    }
  }

  void _toque(LatLng ll) async {
    final p = _pt(ll);
    switch (modo) {
      case _Modo.desenhar:
        setState(() => contornoNovo.add(p));
      case _Modo.ponto:
        _sair();
        await Navigator.push(context, MaterialPageRoute(builder: (_) => PontoFormPage(local: p)));
      case _Modo.ocorrencia:
        _sair();
        await Navigator.push(context, MaterialPageRoute(builder: (_) => OcorrenciaFormPage(local: p)));
      case _Modo.ver:
        final q = piqueteNoPonto(p);
        if (q != null) _resumoPiquete(q);
    }
  }

  void _resumoPiquete(Reg q) {
    final id = q['id'] as int;
    final l = lotacaoPiquetes()[id];
    final r = rodizio(hojeIso()).where((x) => x.piquete['id'] == id).firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(txt(q['nome']).toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (l != null) ...[
              Info('Animais', '${l.cabecas}'),
              Info('Área', l.area == null ? '' : '${num1(l.area!)} ha'),
              Info('Lotação', l.uaHa == null ? '' : '${num1(l.uaHa!)} UA/ha${l.acima ? ' (acima da capacidade)' : ''}'),
            ],
            if (r != null) Info('Rodízio', r.texto),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir piquete'),
              onPressed: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PiqueteDetalhePage(id)));
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Mapa da fazenda',
      acoes: [
        IconButton(
          tooltip: 'Importar pastos do Google Earth (KML)',
          icon: const Icon(Icons.upload_file),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarKmlPage())),
        ),
        IconButton(
          tooltip: 'Ocorrências',
          icon: const Icon(Icons.report_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OcorrenciasPage())),
        ),
        IconButton(
          tooltip: 'Rodízio de pastejo',
          icon: const Icon(Icons.autorenew),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RodizioPage())),
        ),
        IconButton(
          tooltip: 'Contagem de campo',
          icon: const Icon(Icons.format_list_numbered),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContagemPage())),
        ),
        IconButton(
          tooltip: 'Pontos (aguadas, cochos, cercas)',
          icon: const Icon(Icons.place_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PontosPage())),
        ),
      ],
      corpo: AoMudar<(List<Reg>, Map<int, Lotacao>, List<Rodizio>, List<Reg>, List<Reg>)>(
        carregar: () async =>
            (await Db.piquetes(), lotacaoPiquetes(), rodizio(hojeIso()), pontos(), ocorrencias(soAbertas: true)),
        builder: (context, d) {
          final (piquetes, lot, rod, pts, ocs) = d;
          final situacao = {for (final r in rod) r.piquete['id']: r.situacao};
          final todos = <LatLng>[
            for (final q in piquetes) ...contorno(q).map(_ll),
            for (final p in pts)
              if (p['lat'] is num) LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          ];
          final opcoes = MapOptions(
            initialCenter: todos.isEmpty ? _centroPadrao : todos.first,
            initialZoom: todos.isEmpty ? 6 : 15,
            initialCameraFit: todos.length >= 2
                ? CameraFit.coordinates(coordinates: todos, padding: const EdgeInsets.all(40), maxZoom: 17)
                : null,
            onTap: (_, ll) => _toque(ll),
          );
          return Stack(children: [
            FlutterMap(
              mapController: _mapa,
              options: opcoes,
              children: [
                TileLayer(
                  urlTemplate: satelite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'br.com.eitogestao',
                  maxNativeZoom: 19,
                ),
                PolygonLayer(polygons: [
                  for (final q in piquetes)
                    if (contorno(q).length >= 3 && q['id'] != desenhando?['id'])
                      Polygon(
                        points: contorno(q).map(_ll).toList(),
                        color: corRodizio(situacao[q['id']]).withValues(alpha: 0.25),
                        borderColor: corRodizio(situacao[q['id']]),
                        borderStrokeWidth: 2,
                      ),
                ]),
                if (contornoNovo.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [...contornoNovo.map(_ll), if (contornoNovo.length >= 3) _ll(contornoNovo.first)],
                      color: Colors.yellow,
                      strokeWidth: 3,
                    ),
                  ]),
                MarkerLayer(markers: [
                  for (final q in piquetes)
                    if (centro(contorno(q)) case final c? when q['id'] != desenhando?['id'])
                      Marker(
                        point: _ll(c),
                        width: 140,
                        height: 44,
                        child: IgnorePointer(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(txt(q['nome']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 3)])),
                            Text(
                              '${lot[q['id']]?.cabecas ?? 0} cab.'
                              '${lot[q['id']]?.uaHa == null ? '' : ' · ${num1(lot[q['id']]!.uaHa!)} UA/ha'}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 3)]),
                            ),
                          ]),
                        ),
                      ),
                  for (final p in contornoNovo)
                    Marker(
                      point: _ll(p),
                      width: 14,
                      height: 14,
                      child: Container(
                          decoration: BoxDecoration(
                              color: Colors.yellow, shape: BoxShape.circle, border: Border.all(color: Colors.black))),
                    ),
                  for (final p in pts)
                    if (p['lat'] is num)
                      Marker(
                        point: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => PontoFormPage(ponto: p))),
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(iconePonto(p['tipo']), color: Colors.blue.shade800, size: 20),
                          ),
                        ),
                      ),
                  for (final o in ocs)
                    if (o['lat'] is num)
                      Marker(
                        point: LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble()),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => OcorrenciaFormPage(ocorrencia: o))),
                          child: const CircleAvatar(
                            backgroundColor: Colors.red,
                            child: Icon(Icons.priority_high, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                  if (eu != null)
                    Marker(
                      point: _ll(eu!),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                ]),
                RichAttributionWidget(attributions: [
                  TextSourceAttribution(satelite ? 'Esri, Maxar, Earthstar Geographics' : 'OpenStreetMap'),
                ]),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Column(children: [
                FloatingActionButton.small(
                  heroTag: null,
                  tooltip: satelite ? 'Ver ruas' : 'Ver satélite',
                  onPressed: () => setState(() => satelite = !satelite),
                  child: Icon(satelite ? Icons.map_outlined : Icons.satellite_alt_outlined),
                ),
                FloatingActionButton.small(
                  heroTag: null,
                  tooltip: modo == _Modo.desenhar ? 'Marcar canto onde estou' : 'Onde estou',
                  onPressed: _gps,
                  child: const Icon(Icons.my_location),
                ),
              ]),
            ),
            if (piquetes.isNotEmpty && piquetes.every((q) => contorno(q).length < 3) && modo == _Modo.ver)
              const Positioned(
                top: 8,
                left: 8,
                right: 64,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('Desenhe os piquetes: toque em "Desenhar" e marque os cantos no mapa, '
                        'ou ande pela cerca tocando no botão de posição em cada canto.'),
                  ),
                ),
              ),
            Positioned(left: 8, right: 8, bottom: 8, child: _barra()),
          ]);
        },
      ),
    );
  }

  Widget _barra() {
    if (modo == _Modo.ver) {
      return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: _escolherPiqueteParaDesenhar, icon: const Icon(Icons.draw_outlined), label: const Text('Desenhar')),
        FilledButton.icon(
            onPressed: () => setState(() => modo = _Modo.ponto),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Ponto')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => setState(() => modo = _Modo.ocorrencia),
          icon: const Icon(Icons.report_outlined),
          label: const Text('Ocorrência'),
        ),
      ]);
    }
    final texto = switch (modo) {
      _Modo.desenhar => '${desenhando?['nome']}: toque nos cantos (${contornoNovo.length} marcados'
          '${contornoNovo.length >= 3 ? ', ${num1(areaHa(contornoNovo))} ha' : ''})',
      _Modo.ponto => 'Toque no mapa onde fica o ponto',
      _ => 'Toque no mapa onde está a ocorrência',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _sair, child: const Text('Cancelar')),
            if (modo == _Modo.desenhar) ...[
              OutlinedButton(
                onPressed: contornoNovo.isEmpty ? null : () => setState(() => contornoNovo.removeLast()),
                child: const Text('Desfazer'),
              ),
              FilledButton(onPressed: _salvarContorno, child: const Text('Salvar contorno')),
            ],
            if (modo != _Modo.desenhar)
              FilledButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Usar onde estou'),
                onPressed: () async {
                  final p = await posicaoComAviso(context);
                  if (p == null || !mounted) return;
                  final ocorrencia = modo == _Modo.ocorrencia;
                  _sair();
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ocorrencia ? OcorrenciaFormPage(local: p) : PontoFormPage(local: p)));
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

// ======================= Ocorrências =======================

class OcorrenciasPage extends StatefulWidget {
  const OcorrenciasPage({super.key});

  @override
  State<OcorrenciasPage> createState() => _OcorrenciasPageState();
}

class _OcorrenciasPageState extends State<OcorrenciasPage> {
  bool soAbertas = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ocorrências')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OcorrenciaFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: () async => ocorrencias(soAbertas: soAbertas),
        builder: (context, lista) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Abertas')),
                ButtonSegment(value: false, label: Text('Todas')),
              ],
              selected: {soAbertas},
              onSelectionChanged: (s) => setState(() => soAbertas = s.first),
            ),
          ),
          if (lista.isEmpty) const Vazio('Nenhuma ocorrência.', icone: Icons.report_outlined),
          for (final o in lista)
            ListTile(
              leading: Icon(o['resolvida'] == true ? Icons.check_circle : Icons.report,
                  color: o['resolvida'] == true ? Colors.green : Colors.red),
              title: Text(txt(o['tipo'])),
              subtitle: Text([
                br(o['data']),
                if (Db.registro('piquetes', o['piquete_id']) != null) txt(Db.registro('piquetes', o['piquete_id'])!['nome']),
                if (Db.registro('pontos', o['ponto_id']) != null) txt(Db.registro('pontos', o['ponto_id'])!['nome']),
                if (txt(o['descricao']).isNotEmpty) txt(o['descricao']),
              ].join(' · ')),
              onTap: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => OcorrenciaFormPage(ocorrencia: o))),
            ),
        ]),
      ),
    );
  }
}

/// Tira (ou escolhe) uma foto pequena para guardar no banco. Null se cancelar.
Future<String?> tirarFoto(BuildContext context) async {
  final op = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (op == null) return null;
  final img = await ImagePicker().pickImage(source: op, maxWidth: 800, maxHeight: 800, imageQuality: 70);
  if (img == null) return null;
  final bytes = await img.readAsBytes();
  if (bytes.length > 700 * 1024) {
    if (context.mounted) avisar(context, 'Foto grande demais. Tente de novo.');
    return null;
  }
  return base64Encode(bytes);
}

class OcorrenciaFormPage extends StatefulWidget {
  const OcorrenciaFormPage({super.key, this.ocorrencia, this.local, this.pontoId});
  final Reg? ocorrencia;
  final Ponto? local;
  final int? pontoId;

  @override
  State<OcorrenciaFormPage> createState() => _OcorrenciaFormPageState();
}

class _OcorrenciaFormPageState extends State<OcorrenciaFormPage> {
  late final o = widget.ocorrencia;
  late String? tipo = (o?['tipo'] as String?) ?? (widget.pontoId != null ? 'Manutenção feita' : tiposOcorrencia.first);
  late String data = (o?['data'] as String?) ?? hojeIso();
  late final descricao = TextEditingController(text: txt(o?['descricao']));
  late Ponto? local = o?['lat'] is num
      ? (lat: (o!['lat'] as num).toDouble(), lng: (o!['lng'] as num).toDouble())
      : widget.local ?? _localDoPonto(widget.pontoId);
  late int? piqueteId = o?['piquete_id'] as int? ?? (local == null ? null : piqueteNoPonto(local!)?['id'] as int?);
  late int? pontoId = o?['ponto_id'] as int? ?? widget.pontoId;
  late bool resolvida = o?['resolvida'] == true;
  String? foto;
  bool fotoMudou = false;
  List<Reg> piquetes = [];

  static Ponto? _localDoPonto(int? id) {
    final p = Db.registro('pontos', id);
    return p?['lat'] is num ? (lat: (p!['lat'] as num).toDouble(), lng: (p['lng'] as num).toDouble()) : null;
  }

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
    if (o != null) {
      Db.foto(o!['id'] as int).then((f) {
        if (mounted && !fotoMudou) setState(() => foto = f);
      });
    }
  }

  @override
  void dispose() {
    descricao.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    final v = <String, Object?>{
      'tipo': tipo,
      'data': data,
      'descricao': nulo(descricao.text),
      'lat': local?.lat,
      'lng': local?.lng,
      'piquete_id': piqueteId,
      'ponto_id': pontoId,
      'resolvida': resolvida,
      if (resolvida && o?['resolvida'] != true) 'resolvida_em': hojeIso(),
      if (!resolvida) 'resolvida_em': null,
    };
    final id = await salvarOcorrencia(v, id: o?['id'] as int?);
    if (fotoMudou) await Db.salvarFoto(id, foto);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ps = pontos();
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? 'Nova ocorrência' : 'Ocorrência'), actions: [
        if (o != null)
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmar(context, 'Excluir ocorrência?', 'A foto também será apagada.', ok: 'Excluir')) {
                return;
              }
              await Db.excluir('ocorrencias', o!['id'] as int);
              if (context.mounted) Navigator.pop(context);
            },
          ),
      ]),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        escolha('Tipo', tipo, tiposOcorrencia, (v) => setState(() => tipo = v)),
        gap,
        DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (x) => setState(() => data = x!)),
        gap,
        campoTexto(descricao, 'O que aconteceu', linhas: 3),
        gap,
        Row(children: [
          Expanded(
            child: Text(local == null
                ? 'Sem local'
                : 'Local: ${local!.lat.toStringAsFixed(5)}, ${local!.lng.toStringAsFixed(5)}'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.my_location),
            label: const Text('Onde estou'),
            onPressed: () async {
              final p = await posicaoComAviso(context);
              if (p == null || !mounted) return;
              setState(() {
                local = p;
                piqueteId = piqueteNoPonto(p)?['id'] as int? ?? piqueteId;
              });
            },
          ),
        ]),
        gap,
        escolhaId('Piquete/Pasto', piqueteId, piquetes, (v) => setState(() => piqueteId = v), vazio: 'Nenhum'),
        gap,
        escolhaId('Ponto (aguada, cocho, cerca…)', pontoId, ps, (v) => setState(() => pontoId = v), vazio: 'Nenhum'),
        gap,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Resolvida'),
          value: resolvida,
          onChanged: (v) => setState(() => resolvida = v),
        ),
        gap,
        if (foto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(base64Decode(foto!), height: 220, fit: BoxFit.cover),
          ),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(foto == null ? 'Pôr foto' : 'Trocar foto'),
            onPressed: () async {
              final f = await tirarFoto(context);
              if (f != null) {
                setState(() {
                  foto = f;
                  fotoMudou = true;
                });
              }
            },
          ),
          if (foto != null)
            TextButton(
              onPressed: () => setState(() {
                foto = null;
                fotoMudou = true;
              }),
              child: const Text('Remover foto'),
            ),
        ]),
      ]),
    );
  }
}

// ======================= Pontos =======================

class PontosPage extends StatelessWidget {
  const PontosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aguadas, cochos e cercas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Novo ponto'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PontoFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: () async => pontos(),
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum ponto cadastrado.\nMarque no mapa as aguadas, cochos, saleiros e porteiras.',
                icone: Icons.place_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final p in lista)
              ListTile(
                leading: Icon(iconePonto(p['tipo'])),
                title: Text(txt(p['nome'])),
                subtitle: Text([
                  txt(p['tipo']),
                  '${ocorrencias(soAbertas: true, pontoId: p['id'] as int).length} aberta(s)',
                ].join(' · ')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PontoFormPage(ponto: p))),
              ),
          ]);
        },
      ),
    );
  }
}

class PontoFormPage extends StatefulWidget {
  const PontoFormPage({super.key, this.ponto, this.local});
  final Reg? ponto;
  final Ponto? local;

  @override
  State<PontoFormPage> createState() => _PontoFormPageState();
}

class _PontoFormPageState extends State<PontoFormPage> {
  late final p = widget.ponto;
  late String? tipo = (p?['tipo'] as String?) ?? tiposPonto.first;
  late final nome = TextEditingController(text: txt(p?['nome']));
  late final obs = TextEditingController(text: txt(p?['obs']));
  late Ponto? local =
      p?['lat'] is num ? (lat: (p!['lat'] as num).toDouble(), lng: (p!['lng'] as num).toDouble()) : widget.local;

  @override
  void dispose() {
    nome.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    if (nome.text.trim().isEmpty) {
      avisar(context, 'Dê um nome ao ponto (ex.: Aguada do córrego).');
      return;
    }
    await salvarPonto({
      'tipo': tipo,
      'nome': nome.text.trim(),
      'obs': nulo(obs.text),
      'lat': local?.lat,
      'lng': local?.lng,
    }, id: p?['id'] as int?);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final id = p?['id'] as int?;
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Novo ponto' : txt(p!['nome'])), actions: [
        if (id != null)
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmar(context, 'Excluir ponto?', 'As ocorrências dele continuam salvas.', ok: 'Excluir')) {
                return;
              }
              await Db.excluir('pontos', id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
      ]),
      bottomNavigationBar: BotaoSalvar(onPressed: salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        escolha('Tipo', tipo, tiposPonto, (v) => setState(() => tipo = v)),
        gap,
        campoTexto(nome, 'Nome *'),
        gap,
        Row(children: [
          Expanded(
            child: Text(local == null
                ? 'Sem local (marque pelo mapa ou pelo GPS)'
                : 'Local: ${local!.lat.toStringAsFixed(5)}, ${local!.lng.toStringAsFixed(5)}'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.my_location),
            label: const Text('Onde estou'),
            onPressed: () async {
              final g = await posicaoComAviso(context);
              if (g != null && mounted) setState(() => local = g);
            },
          ),
        ]),
        gap,
        campoTexto(obs, 'Anotações', linhas: 3),
        if (id != null) ...[
          const Secao('Histórico de manutenção e problemas'),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.build_outlined),
            label: const Text('Registrar manutenção ou problema'),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => OcorrenciaFormPage(pontoId: id))),
          ),
          AoMudar<List<Reg>>(
            carregar: () async => ocorrencias(pontoId: id),
            builder: (context, lista) => Column(children: [
              if (lista.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nada registrado ainda.')),
              for (final o in lista)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(o['resolvida'] == true ? Icons.check_circle : Icons.report,
                      color: o['resolvida'] == true ? Colors.green : Colors.red),
                  title: Text(txt(o['tipo'])),
                  subtitle: Text([br(o['data']), if (txt(o['descricao']).isNotEmpty) txt(o['descricao'])].join(' · ')),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => OcorrenciaFormPage(ocorrencia: o))),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ======================= Rodízio =======================

class RodizioPage extends StatelessWidget {
  const RodizioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rodízio de pastejo')),
      body: AoMudar<(List<Rodizio>, Map<int, Lotacao>)>(
        carregar: () async => (rodizio(hojeIso()), lotacaoPiquetes()),
        builder: (context, d) {
          final (lista, lot) = d;
          if (lista.isEmpty) return const Vazio('Nenhum piquete cadastrado.', icone: Icons.fence);
          int ordem(Rodizio r) => switch (r.situacao) {
                SituacaoPasto.trocar => 0,
                SituacaoPasto.pronto => 1,
                SituacaoPasto.ocupado => 2,
                SituacaoPasto.descansando => 3,
                SituacaoPasto.semHistorico => 4,
              };
          final ordenada = [...lista]..sort((a, b) => ordem(a).compareTo(ordem(b)));
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Conta pelas entradas e saídas de animais de cada piquete. Os dias de ocupação e de descanso '
                  'ficam no cadastro do piquete (padrão: $ocupacaoPadrao e $descansoPadrao dias).'),
            ),
            for (final r in ordenada)
              ListTile(
                leading: Icon(Icons.circle, color: corRodizio(r.situacao)),
                title: Text(txt(r.piquete['nome'])),
                subtitle: Text([
                  r.texto,
                  if (lot[r.piquete['id']]?.uaHa != null) '${num1(lot[r.piquete['id']]!.uaHa!)} UA/ha',
                ].join(' · ')),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => PiqueteDetalhePage(r.piquete['id'] as int))),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================= Contagem de campo =======================

class ContagemPage extends StatefulWidget {
  const ContagemPage({super.key, this.piqueteId});
  final int? piqueteId;

  @override
  State<ContagemPage> createState() => _ContagemPageState();
}

class _ContagemPageState extends State<ContagemPage> {
  late int? piqueteId = widget.piqueteId;
  final contado = TextEditingController();
  final obs = TextEditingController();
  List<Reg> piquetes = [];

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  @override
  void dispose() {
    contado.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    final n = lerNumero(contado.text)?.round();
    if (piqueteId == null || n == null) {
      avisar(context, 'Escolha o piquete e informe quantos animais contou.');
      return;
    }
    final esperado = animaisNoPiquete(piqueteId!).length;
    await registrarContagem(piqueteId!, hojeIso(), n, obs: nulo(obs.text));
    if (!mounted) return;
    final dif = n - esperado;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(dif == 0 ? 'Bateu!' : 'Diferença de ${dif > 0 ? '+$dif' : '$dif'}'),
        content: Text(dif == 0
            ? 'Contou $n, o mesmo que o Eito tem no piquete.'
            : 'Contou $n e o Eito tem $esperado no piquete. '
                '${dif < 0 ? 'Procure os que faltam ou registre as saídas e mortes.' : 'Há animais de outro piquete aqui, ou animais sem cadastro.'}'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    contado.clear();
    obs.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contagem de campo')),
      body: AoMudar<(List<Reg>, List<Reg>)>(
        carregar: () async =>
            (piqueteId == null ? <Reg>[] : animaisNoPiquete(piqueteId!), contagens(piqueteId: piqueteId)),
        builder: (context, d) {
          final (esperados, historico) = d;
          return ListView(padding: const EdgeInsets.all(16), children: [
            escolhaId('Piquete/Pasto', piqueteId, piquetes, (v) => setState(() => piqueteId = v), vazio: 'Escolha'),
            if (piqueteId != null) ...[
              gap,
              Text('O Eito tem ${esperados.length} animal(is) neste piquete.', style: const TextStyle(fontSize: 18)),
              gap,
              campoTexto(contado, 'Quantos você contou', numero: true),
              gap,
              campoTexto(obs, 'Observação (opcional)'),
              gap,
              FilledButton.icon(onPressed: salvar, icon: const Icon(Icons.check), label: const Text('Registrar contagem')),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Animais que deveriam estar aqui'),
                children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in esperados) Chip(label: Text('${a['brinco']}${txt(a['categoria']).isEmpty ? '' : ' · ${a['categoria']}'}')),
                  ]),
                ],
              ),
            ],
            const Secao('Contagens anteriores'),
            if (historico.isEmpty) const Text('Nenhuma ainda.'),
            for (final c in historico)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c['contado'] == c['esperado'] ? Icons.check_circle : Icons.warning_amber,
                    color: c['contado'] == c['esperado'] ? Colors.green : Colors.orange),
                title: Text('${txt(Db.registro('piquetes', c['piquete_id'])?['nome'])}: contou ${c['contado']} de ${c['esperado']}'),
                subtitle: Text([br(c['data']), if (txt(c['obs']).isNotEmpty) txt(c['obs'])].join(' · ')),
              ),
          ]);
        },
      ),
    );
  }
}
