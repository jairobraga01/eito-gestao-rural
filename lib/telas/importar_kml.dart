// Importar os pastos desenhados no Google Earth (arquivo .kml).
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/kml.dart';
import '../dados/mapa.dart' show contornoParaSalvar;
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../util/util.dart';

const _ignorar = -1, _novo = 0;

class ImportarKmlPage extends StatefulWidget {
  const ImportarKmlPage({super.key});

  @override
  State<ImportarKmlPage> createState() => _ImportarKmlPageState();
}

class _ImportarKmlPageState extends State<ImportarKmlPage> {
  List<PoligonoKml>? poligonos;
  List<int> destinos = [];
  List<Reg> piquetes = [];
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    Db.piquetes().then((v) {
      if (mounted) setState(() => piquetes = v);
    });
  }

  Future<void> _escolher() async {
    final texto = await escolherArquivoTexto(aceitar: '.kml');
    if (texto == null || !mounted) return;
    final p = lerKml(texto);
    if (p.isEmpty) {
      avisar(context, 'Nenhum pasto (polígono) encontrado no arquivo. No Google Earth, salve como .kml, não .kmz.');
      return;
    }
    setState(() {
      poligonos = p;
      destinos = [
        for (final x in p)
          (piquetes.where((q) => txt(q['nome']).toLowerCase() == x.nome.toLowerCase()).firstOrNull?['id'] as int?) ??
              _novo,
      ];
    });
  }

  Future<void> salvar() async {
    final p = poligonos!;
    var novos = 0, atualizados = 0;
    setState(() => salvando = true);
    for (final (i, x) in p.indexed) {
      final area = double.parse(x.area.toStringAsFixed(2));
      final v = {'contorno': contornoParaSalvar(x.pontos), 'area': area};
      if (destinos[i] == _novo) {
        await Db.inserir('piquetes', {...v, 'nome': x.nome, 'propriedade_id': Db.pid});
        novos++;
      } else if (destinos[i] != _ignorar) {
        await Db.atualizar('piquetes', destinos[i], v);
        atualizados++;
      }
    }
    if (!mounted) return;
    avisar(context, '$novos piquete(s) novo(s) e $atualizados atualizado(s).');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = poligonos;
    return Scaffold(
      appBar: AppBar(title: const Text('IMPORTAR PASTOS (KML)')),
      bottomNavigationBar:
          p == null ? null : BotaoSalvar(onPressed: salvando ? null : salvar, texto: 'Importar'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('No Google Earth, clique com o botão direito na pasta dos pastos, escolha '
              '"Salvar lugar como" e o tipo .kml. Cada polígono vira um piquete com a área calculada.'),
          gap,
          OutlinedButton.icon(
            onPressed: _escolher,
            icon: const Icon(Icons.upload_file),
            label: Text(p == null ? 'Escolher arquivo .kml' : 'Escolher outro arquivo'),
          ),
          if (p != null) ...[
            Secao('${p.length} pasto(s) no arquivo'),
            for (final (i, x) in p.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<int>(
                  key: ValueKey('kml_$i'),
                  initialValue: destinos[i],
                  decoration: InputDecoration(labelText: '${x.nome} · ${num1(x.area)} ha'),
                  items: [
                    const DropdownMenuItem(value: _novo, child: Text('Criar piquete novo')),
                    for (final q in piquetes)
                      DropdownMenuItem(value: q['id'] as int, child: Text('Atualizar ${txt(q['nome'])}')),
                    const DropdownMenuItem(value: _ignorar, child: Text('Não importar')),
                  ],
                  onChanged: (v) => setState(() => destinos[i] = v ?? _novo),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
