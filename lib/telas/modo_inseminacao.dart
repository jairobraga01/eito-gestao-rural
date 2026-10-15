import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';
import 'protocolos.dart';
import 'semens.dart';

const tiposInseminacao = ['IATF', 'IA', 'TE (embrião)'];

enum EtapaIa { inseminar, diagnostico }

/// Inseminação no tronco, uma vaca atrás da outra: lê o brinco e registra
/// IA/IATF com o sêmen escolhido (dá baixa da dose). Na etapa de diagnóstico,
/// lê o brinco e marca prenhe ou vazia; prenhe já mostra o parto previsto.
class ModoInseminacao extends StatefulWidget {
  const ModoInseminacao({super.key, this.etapa = EtapaIa.inseminar});
  final EtapaIa etapa;

  @override
  State<ModoInseminacao> createState() => _ModoInseminacaoState();
}

class _ModoInseminacaoState extends State<ModoInseminacao> {
  late EtapaIa _etapa = widget.etapa;
  final Set<int> _feitos = {};
  VoidCallback? _cancelarLeitor;
  String _tipo = 'IATF';
  int? _semenId;
  final _inseminador = TextEditingController();
  final _protocolo = TextEditingController();
  String _data = hojeIso();
  bool _avisouSemEstoque = false;
  Reg? _atual; // vaca no tronco aguardando o diagnóstico
  Reg? _servico;
  String? _mensagem;
  Color _corMensagem = Cores.sucesso;
  bool _buscando = false;

  bool get _inseminar => _etapa == EtapaIa.inseminar;

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar(_aoLer);
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    _inseminador.dispose();
    _protocolo.dispose();
    super.dispose();
  }

  void _avisar(String texto, {Color cor = Cores.sucesso}) => setState(() {
        _mensagem = texto;
        _corMensagem = cor;
      });

  void _aoLer(String leitura) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (parecePeso(leitura)) return; // leitura da balança
    _receberBrinco(leitura);
  }

  Future<void> _digitarBrinco() async {
    final c = await pedirNumero(context, titulo: 'Número do brinco');
    if (c != null && c.trim().isNotEmpty) _receberBrinco(c.trim());
  }

  Future<bool> _perguntar(String titulo, String texto, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto, style: const TextStyle(fontSize: 18)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PULAR')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _receberBrinco(String codigo) async {
    if (_buscando) return;
    setState(() => _buscando = true);
    final a = await Db.buscarPorCodigo(codigo);
    if (!mounted) return;
    setState(() => _buscando = false);

    if (a == null) return _avisar('Brinco $codigo não cadastrado.', cor: Cores.alerta);
    final brinco = a['brinco'];
    if (a['status'] != 'Ativo') return _avisar('Brinco $brinco já saiu do rebanho (${a['status']}).', cor: Cores.alerta);
    if (a['sexo'] != 'F') return _avisar('Brinco $brinco é macho.', cor: Cores.alerta);
    final id = a['id'] as int;
    final aberto = await Db.reproducaoAberta(id);
    if (!mounted) return;

    if (!_inseminar) {
      if (aberto == null || aberto['diagnostico'] != 'Pendente') {
        return _avisar(
            aberto == null
                ? 'Brinco $brinco não tem serviço aguardando diagnóstico.'
                : 'Brinco $brinco já está PRENHE · parto previsto ${br(aberto['parto_previsto'])}.',
            cor: Cores.alerta);
      }
      setState(() {
        _atual = a;
        _servico = aberto;
        _mensagem = null;
      });
      return;
    }

    if (_feitos.contains(id)) {
      return _avisar('Brinco $brinco JÁ foi inseminada agora. Não registrei de novo.', cor: Cores.alerta);
    }
    if (aberto?['diagnostico'] == 'Prenhe') {
      return _avisar('Brinco $brinco já está PRENHE · parto previsto ${br(aberto!['parto_previsto'])}. Não registrei.',
          cor: Cores.alerta);
    }
    if (aberto != null &&
        !await _perguntar('Brinco $brinco aguarda diagnóstico',
            '${aberto['tipo']} de ${br(aberto['data'])} ainda sem diagnóstico. Registrar nova inseminação? A anterior fica como vazia.',
            'INSEMINAR')) {
      return;
    }
    final semen = Db.registro('semens', _semenId);
    final doses = (semen?['doses'] as num?)?.toInt() ?? 0;
    if (semen != null && doses <= 0 && !_avisouSemEstoque) {
      if (!mounted) return;
      if (!await _perguntar('Sem doses no estoque',
          'O sêmen de ${semen['touro']} está sem doses cadastradas. Registrar mesmo assim?', 'REGISTRAR')) {
        return;
      }
      _avisouSemEstoque = true;
    }
    try {
      await Db.registrarInseminacao(
        femeaId: id,
        data: _data,
        tipo: _tipo,
        semenId: semen == null ? null : _semenId,
        inseminador: nulo(_inseminador.text),
        protocolo: nulo(_protocolo.text),
      );
    } on RegistroDuplicado catch (e) {
      return _avisar(e.mensagem, cor: Cores.alerta);
    }
    _feitos.add(id);
    if (!mounted) return;
    _avisar([
      '✔ Brinco $brinco: $_tipo',
      if (semen != null) '${semen['touro']} (restam ${doses - 1})',
      'diagnóstico a partir de ${br(somaDias(_data, 30))}',
    ].join(' · '));
  }

  Future<void> _diagnosticar(String diagnostico) async {
    final a = _atual, s = _servico;
    if (a == null || s == null) return;
    await Db.lancarDiagnostico(s['id'] as int, diagnostico, _data);
    _feitos.add(a['id'] as int);
    if (!mounted) return;
    setState(() {
      _atual = null;
      _servico = null;
    });
    _avisar(
        diagnostico == 'Prenhe'
            ? '✔ Brinco ${a['brinco']}: PRENHE · parto previsto ${br(Db.partoPrevisto(s['data']))}'
            : '✔ Brinco ${a['brinco']}: VAZIA',
        cor: diagnostico == 'Prenhe' ? Cores.sucesso : Cores.alerta);
  }

  void _trocarEtapa(EtapaIa e) => setState(() {
        _etapa = e;
        _feitos.clear();
        _atual = null;
        _servico = null;
        _mensagem = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo Inseminação'),
        actions: [
          IconButton(
            tooltip: 'Protocolos de IATF',
            icon: const Icon(Icons.event_note),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProtocolosPage())),
          ),
          IconButton(
            tooltip: 'Sêmen e touros',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SemensPage())),
          ),
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
          SegmentedButton<EtapaIa>(
            segments: const [
              ButtonSegment(value: EtapaIa.inseminar, label: Text('INSEMINAR'), icon: Icon(Icons.favorite_border)),
              ButtonSegment(value: EtapaIa.diagnostico, label: Text('DIAGNÓSTICO'), icon: Icon(Icons.search)),
            ],
            selected: {_etapa},
            onSelectionChanged: (s) => _trocarEtapa(s.first),
          ),
          const SizedBox(height: 12),
          if (_inseminar) _ajustesInseminacao() else _ajustesDiagnostico(),
          if (_mensagem != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _corMensagem, borderRadius: BorderRadius.circular(14)),
              child: Text(_mensagem!,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 8),
          if (!_inseminar && _atual != null) _painelDiagnostico(_atual!, _servico!) else _painelEspera(),
        ]),
      ),
    );
  }

  Widget _ajustesInseminacao() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              for (final t in tiposInseminacao)
                ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 16)),
                  selected: _tipo == t,
                  onSelected: (_) => setState(() => _tipo = t),
                ),
            ]),
            gap,
            AoMudar<List<Reg>>(
              carregar: Db.semens,
              builder: (context, semens) => Row(children: [
                Expanded(
                  child: escolhaId('Sêmen / touro', _semenId, [
                    for (final s in semens)
                      {
                        ...s,
                        'rotulo': '${s['touro']} · ${(s['doses'] as num?)?.toInt() ?? 0} doses'
                            '${s['preco_dose'] is num ? ' · ${moeda(s['preco_dose'] as num)}' : ''}',
                      },
                  ], (v) => setState(() {
                    _semenId = v;
                    _avisouSemEstoque = false;
                  }), vazio: semens.isEmpty ? 'Nenhum cadastrado' : 'Não informado', campo: 'rotulo'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SemenFormPage())),
                  child: const Text('NOVO'),
                ),
              ]),
            ),
            gap,
            Row(children: [
              Expanded(child: campoTexto(_inseminador, 'Inseminador')),
              const SizedBox(width: 12),
              Expanded(child: campoTexto(_protocolo, 'Protocolo (vazio = o do lote)')),
            ]),
            gap,
            DateField(label: 'Data da inseminação', value: _data, obrigatorio: true, onChanged: (v) => setState(() => _data = v!)),
          ]),
        ),
      );

  Widget _ajustesDiagnostico() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DateField(
              label: 'Data do diagnóstico', value: _data, obrigatorio: true, onChanged: (v) => setState(() => _data = v!)),
        ),
      );

  Widget _painelEspera() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          _buscando
              ? const SizedBox(height: 72, width: 72, child: CircularProgressIndicator(color: Cores.laranja))
              : const Icon(Icons.contactless_outlined, size: 84, color: Cores.laranja),
          const SizedBox(height: 12),
          Text(_inseminar ? 'Próxima vaca:\nencoste o bastão no brinco' : 'Diagnóstico:\nencoste o bastão no brinco',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Cores.laranja, foregroundColor: Cores.azul, minimumSize: const Size.fromHeight(68)),
            onPressed: _digitarBrinco,
            icon: const Icon(Icons.dialpad, size: 30),
            label: const Text('DIGITAR Nº DO BRINCO'),
          ),
        ]),
      );

  Widget _painelDiagnostico(Reg a, Reg s) {
    final dias = diasEntre(txt(s['data']), _data);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  '${s['tipo']} em ${br(s['data'])} ($dias dias)',
                  if (txt(s['touro']).isNotEmpty) txt(s['touro']),
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
      const SizedBox(height: 14),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Cores.sucesso, minimumSize: const Size.fromHeight(80)),
        onPressed: () => _diagnosticar('Prenhe'),
        icon: const Icon(Icons.favorite, size: 34),
        label: Text('PRENHE · parto ${br(Db.partoPrevisto(s['data']))}'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Cores.alerta, minimumSize: const Size.fromHeight(80)),
        onPressed: () => _diagnosticar('Vazia'),
        icon: const Icon(Icons.close, size: 34),
        label: const Text('VAZIA'),
      ),
    ]);
  }
}
