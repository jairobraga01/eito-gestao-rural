import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';
import 'animais.dart' show AnimalFormPage;
import 'ficha_animal.dart' show ItemSanidade, pedirItemSanidade;
import 'sanidade.dart' show eventosPesagem;

enum ModoSerie { pesagem, sanidade }

/// Manejo no tronco/brete, um animal atrás do outro:
/// lê o brinco → (pesa) → confirma → próximo. Sem voltar para menu nenhum.
/// Grava em Pesagens e em Sanidade, os mesmos módulos do app.
class ManejoEmSerie extends StatefulWidget {
  const ManejoEmSerie({super.key, required this.modo});
  final ModoSerie modo;

  @override
  State<ManejoEmSerie> createState() => _ManejoEmSerieState();
}

class _ManejoEmSerieState extends State<ManejoEmSerie> {
  final ValueNotifier<String> _peso = ValueNotifier('');
  final Set<int> _feitos = {};
  VoidCallback? _cancelarLeitor;
  Reg? _atual; // animal no tronco aguardando peso
  ItemSanidade? _item;
  String? _grupo; // junta a vacinação da série num só lançamento em Sanidade
  String _evento = 'Rotina';
  String? _mensagem;
  Color _corMensagem = Cores.sucesso;
  bool _buscando = false;

  bool get _pesagem => widget.modo == ModoSerie.pesagem;

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar(_aoLer);
    if (!_pesagem) WidgetsBinding.instance.addPostFrameCallback((_) => _escolherProduto());
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    _peso.dispose();
    super.dispose();
  }

  Future<void> _escolherProduto() async {
    final p = await pedirItemSanidade(context, atual: _item);
    if (!mounted) return;
    if (p == null && _item == null) {
      Navigator.pop(context); // sem produto não há o que registrar
      return;
    }
    if (p != null) {
      setState(() {
        _item = p;
        _grupo = null; // produto novo, lançamento novo
        _feitos.clear();
      });
    }
  }

  void _avisar(String texto, {Color cor = Cores.sucesso}) => setState(() {
        _mensagem = texto;
        _corMensagem = cor;
      });

  void _aoLer(String leitura) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // Com animal no tronco, número curto é o peso vindo da balança.
    if (_pesagem && _atual != null && parecePeso(leitura)) {
      _peso.value = leituraParaVisor(leitura) ?? _peso.value;
      return;
    }
    // Balança mandou peso sem animal no tronco: avisa em vez de buscar brinco.
    if (_pesagem && _atual == null && parecePeso(leitura)) {
      _avisar('Chegou o peso ${leituraParaVisor(leitura)} kg, mas falta ler o brinco primeiro.', cor: Cores.alerta);
      return;
    }
    _receberBrinco(leitura);
  }

  Future<void> _digitarBrinco() async {
    final c = await pedirNumero(context, titulo: 'Número do brinco');
    if (c != null && c.trim().isNotEmpty) _receberBrinco(c.trim());
  }

  Future<void> _receberBrinco(String codigo) async {
    if (_buscando) return;
    setState(() => _buscando = true);
    final a = await Db.buscarPorCodigo(codigo, soDestaFazenda: true);
    if (!mounted) return;
    setState(() => _buscando = false);

    if (a == null) {
      _avisar('Brinco $codigo não cadastrado.', cor: Cores.alerta);
      final cadastrar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Brinco $codigo não cadastrado'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PULAR')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CADASTRAR')),
          ],
        ),
      );
      if (cadastrar == true && mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => AnimalFormPage(codigoLido: codigo)));
      }
      return;
    }
    if (a['status'] != 'Ativo') {
      _avisar('Brinco ${a['brinco']} já saiu do rebanho (${a['status']}).', cor: Cores.alerta);
      return;
    }
    final id = a['id'] as int;

    if (_pesagem) {
      final noTronco = _atual;
      if (noTronco != null && noTronco['id'] == id) return; // releitura do mesmo brinco: mantém o peso
      if (noTronco != null && _peso.value.isNotEmpty) {
        _avisar('Confirme o peso do brinco ${noTronco['brinco']} antes de ler outro.', cor: Cores.alerta);
        return;
      }
      if (_feitos.contains(id) &&
          !await confirmar(context, 'Brinco ${a['brinco']} já foi pesado agora', 'Pesar de novo?', ok: 'Pesar de novo')) {
        return;
      }
      if (!mounted) return;
      _peso.value = '';
      setState(() {
        _atual = a;
        _mensagem = null;
      });
      return;
    }

    // Sanidade: registra na hora, sem tocar em nada.
    final item = _item;
    if (item == null) return;
    if (_feitos.contains(id)) {
      _avisar('Brinco ${a['brinco']} JÁ recebeu ${item.produto} agora. Não registrei de novo.', cor: Cores.alerta);
      return;
    }
    _grupo = await Db.lancarSanidade([id], item.valores(), grupo: _grupo);
    _feitos.add(id);
    if (mounted) _avisar('✔ Brinco ${a['brinco']}: ${item.produto}');
  }

  Future<void> _confirmarPeso() async {
    final a = _atual;
    final peso = lerNumero(_peso.value);
    if (a == null || peso == null || peso <= 0) return;
    if (peso > 2000) {
      _avisar('Peso ${pesoKg(peso)} fora do normal. Confira e digite de novo.', cor: Cores.alerta);
      return;
    }
    final g = await Db.registrarPesagem(a['id'] as int, peso, evento: _evento);
    _feitos.add(a['id'] as int);
    _peso.value = '';
    if (!mounted) return;
    setState(() => _atual = null);
    _avisar('✔ Brinco ${a['brinco']}: ${pesoKg(peso)}${g == null ? '' : '  ·  ${gmd(g)}'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pesagem ? 'Pesagem em série' : 'Sanidade em série'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${_feitos.length} feitos',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Cores.laranja)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!_pesagem)
            Card(
              child: ListTile(
                leading: const Icon(Icons.vaccines_outlined, size: 34, color: Cores.oliva),
                title: Text(_item?.produto ?? 'Escolha o produto',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                subtitle: Text(_item == null ? 'Aplicando em todos os brincos lidos' : '${_item!.tipo} · ${_item!.resumo}'),
                trailing: TextButton(onPressed: _escolherProduto, child: const Text('TROCAR')),
              ),
            ),
          if (_pesagem)
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Evento:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              for (final e in eventosPesagem.where((e) => e != 'Nascimento'))
                ChoiceChip(
                  label: Text(e, style: const TextStyle(fontSize: 16)),
                  selected: _evento == e,
                  onSelected: (_) => setState(() => _evento = e),
                ),
            ]),
          if (_mensagem != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _corMensagem, borderRadius: BorderRadius.circular(14)),
              child: Text(_mensagem!,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 8),
          if (_pesagem && _atual != null) ..._painelPeso(_atual!) else _painelEspera(),
        ]),
      ),
    );
  }

  Widget _painelEspera() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          _buscando
              ? const SizedBox(height: 72, width: 72, child: CircularProgressIndicator(color: Cores.laranja))
              : const Icon(Icons.contactless_outlined, size: 84, color: Cores.laranja),
          const SizedBox(height: 12),
          const Text('Próximo animal:\nencoste o bastão no brinco',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.laranja, foregroundColor: Cores.azul, minimumSize: const Size.fromHeight(68)),
            onPressed: _digitarBrinco,
            icon: const Icon(Icons.dialpad, size: 30),
            label: const Text('DIGITAR Nº DO BRINCO'),
          ),
        ]),
      );

  List<Widget> _painelPeso(Reg a) => [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Brinco ${a['brinco']}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                Text(
                  [
                    a['sexo'] == 'F' ? 'Fêmea' : 'Macho',
                    if (txt(a['categoria']).isNotEmpty) txt(a['categoria']),
                    if (txt(a['lote_nome']).isNotEmpty) 'Lote ${a['lote_nome']}',
                    if (a['ultimo_peso'] != null) 'último ${kg(a['ultimo_peso'] as num)}',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 17),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Trocar animal',
              iconSize: 32,
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _atual = null),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        VisorNumero(valor: _peso, sufixo: 'kg'),
        const SizedBox(height: 4),
        const Text('A balança preenche sozinha, ou digite abaixo.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: TecladoGrande(valor: _peso, decimal: true, maxDigitos: 5),
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: _peso,
          builder: (context, v, _) => FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.laranja, foregroundColor: Cores.azul, minimumSize: const Size.fromHeight(80)),
            onPressed: v.isEmpty ? null : _confirmarPeso,
            icon: const Icon(Icons.check, size: 36),
            label: const Text('CONFIRMAR PESO'),
          ),
        ),
      ];
}
