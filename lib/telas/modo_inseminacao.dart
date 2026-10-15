import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/gestao.dart' show alertaConsanguinidade;
import '../dados/iatf.dart';
import '../dados/indicadores.dart' show notasEcc;
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';
import 'protocolos.dart';
import 'semens.dart';

const tiposInseminacao = ['IATF', 'IA', 'TE (embrião)'];

enum EtapaIa { inseminar, diagnostico }

/// Inseminação no tronco, uma vaca atrás da outra: lê o brinco, preenche a
/// ficha da vaca (ECC, cio, implante, bezerro...) e registra IA/IATF com o
/// sêmen escolhido (dá baixa da dose). Na etapa de diagnóstico, lê o brinco e
/// marca prenhe ou vazia; prenhe já mostra o parto previsto. Prenhe com 2º
/// diagnóstico pendente abre a confirmação (perdeu = perda embrionária).
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
  final _tecnico = TextEditingController();
  String _data = hojeIso();
  String _hora = _agora();
  bool _fichaPorVaca = true;
  Reg _ficha = {};
  final _obs = TextEditingController();
  final _peso = TextEditingController();
  final _temperatura = TextEditingController();
  final _folD = TextEditingController();
  final _folE = TextEditingController();
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
    for (final c in [_inseminador, _protocolo, _tecnico, _obs, _peso, _temperatura, _folD, _folE]) {
      c.dispose();
    }
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
      // 2º diagnóstico só a partir de 45 dias da IA (e não na mesma passada do 1º).
      final confirmar = aberto?['diagnostico'] == 'Prenhe' &&
          aberto?['data_confirmacao'] == null &&
          !_feitos.contains(id) &&
          txt(aberto?['data']).isNotEmpty &&
          diasEntre(txt(aberto!['data']), _data) >= 45;
      if (aberto == null || (aberto['diagnostico'] != 'Pendente' && !confirmar)) {
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
    if (_fichaPorVaca) {
      _abrirFicha(a);
      return;
    }
    await _registrar(a);
  }

  /// Vaca no tronco: abre a ficha já com o que o app sabe (categoria, dias de parida, ECC recente).
  void _abrirFicha(Reg a) {
    final auto = fichaAutomatica(a['id'] as int, _data);
    for (final c in [_obs, _peso, _temperatura, _folD, _folE]) {
      c.clear();
    }
    setState(() {
      _atual = a;
      _mensagem = null;
      _ficha = {
        'ecc': auto['ecc'],
        'implante': 'Retirado normal',
        'tratamentos': <String>[],
        if (auto['categoria_ia'] == 'Novilha') 'bezerro': false,
      };
    });
  }

  Reg _fichaPreenchida() => {
        ..._ficha,
        'hora': _hora,
        'tecnico': nulo(_tecnico.text),
        'peso': lerNumero(_peso.text),
        'temperatura': lerNumero(_temperatura.text),
        'foliculo_d': lerNumero(_folD.text),
        'foliculo_e': lerNumero(_folE.text),
        'obs': nulo(_obs.text),
      };

  Future<void> _registrar(Reg a, {Reg ficha = const {}}) async {
    final id = a['id'] as int;
    final brinco = a['brinco'];
    final semen = Db.registro('semens', _semenId);
    final parentesco = alertaConsanguinidade(id, semen?['touro']);
    if (parentesco != null) {
      if (!mounted || !await _perguntar('Atenção: consanguinidade', parentesco, 'INSEMINAR ASSIM')) return;
    }
    final doses = (semen?['doses'] as num?)?.toInt() ?? 0;
    if (semen != null && doses <= 0 && !_avisouSemEstoque) {
      if (!mounted) return;
      if (!await _perguntar('Sem doses no estoque',
          'O sêmen de ${semen['touro']} está sem doses cadastradas. Registrar mesmo assim?', 'REGISTRAR')) {
        return;
      }
      _avisouSemEstoque = true;
    }
    final int servico;
    try {
      servico = await inseminarComFicha(
        femeaId: id,
        data: _data,
        tipo: _tipo,
        semenId: semen == null ? null : _semenId,
        inseminador: nulo(_inseminador.text),
        protocolo: nulo(_protocolo.text),
        ficha: {'hora': _hora, 'tecnico': nulo(_tecnico.text), ...ficha},
      );
    } on RegistroDuplicado catch (e) {
      return _avisar(e.mensagem, cor: Cores.alerta);
    }
    _feitos.add(id);
    if (!mounted) return;
    final lote = Db.registro('protocolos', Db.registro('reproducoes', servico)?['protocolo_id']);
    final dg = (lote?['dg_dias'] as num?)?.toInt() ?? 30;
    setState(() => _atual = null);
    _avisar([
      '✔ Brinco $brinco: $_tipo',
      if (semen != null) '${semen['touro']} (restam ${doses - 1})',
      'DG a partir de ${br(somaDias(_data, dg))}',
    ].join(' · '));
  }

  Future<void> _descartar(Reg a) async {
    final lote = Db.protocoloDaFemea(a['id'] as int, _data);
    if (!await _perguntar('Descarte / refugo', 'Brinco ${a['brinco']} fica marcada para descarte'
        '${lote == null ? '' : ' e sai do protocolo ${lote['nome']}'}. Não registra a inseminação.', 'DESCARTAR')) {
      return;
    }
    if (lote != null) {
      await descartarDoProtocolo(lote['id'] as int, a['id'] as int);
    } else {
      await Db.atualizar('animais', a['id'] as int, {'descarte': true});
    }
    _feitos.add(a['id'] as int);
    if (!mounted) return;
    setState(() => _atual = null);
    _avisar('Brinco ${a['brinco']} marcada para DESCARTE.', cor: Cores.alerta);
  }

  Future<void> _confirmar(bool prenhe) async {
    final a = _atual, s = _servico;
    if (a == null || s == null) return;
    await Db.lancarConfirmacao(s['id'] as int, prenhe, _data);
    _feitos.add(a['id'] as int);
    if (!mounted) return;
    setState(() {
      _atual = null;
      _servico = null;
    });
    _avisar(prenhe ? '✔ Brinco ${a['brinco']}: PRENHEZ CONFIRMADA' : '✔ Brinco ${a['brinco']}: PERDA · fica vazia',
        cor: prenhe ? Cores.sucesso : Cores.alerta);
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
          if (!_inseminar && _atual != null)
            _servico!['diagnostico'] == 'Prenhe' ? _painelConfirmacao(_atual!, _servico!) : _painelDiagnostico(_atual!, _servico!)
          else if (_inseminar && _atual != null)
            _painelFicha(_atual!)
          else
            _painelEspera(),
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
              Expanded(child: campoTexto(_tecnico, 'Técnico / veterinário')),
            ]),
            gap,
            campoTexto(_protocolo, 'Protocolo (vazio = o do lote)'),
            gap,
            Row(children: [
              Expanded(
                child: DateField(
                    label: 'Data da inseminação', value: _data, obrigatorio: true, onChanged: (v) => setState(() => _data = v!)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(onPressed: _escolherHora, icon: const Icon(Icons.schedule), label: Text(_hora)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ficha de cada vaca'),
              subtitle: const Text('ECC, cio, implante, bezerro ao pé... Desligado: registra direto ao ler o brinco.'),
              value: _fichaPorVaca,
              onChanged: (v) => setState(() => _fichaPorVaca = v),
            ),
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

  Future<void> _escolherHora() async {
    final p = _hora.split(':');
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p.last) ?? 0));
    if (t != null) setState(() => _hora = _hhmm(t.hour, t.minute));
  }

  Widget _cabecalhoVaca(Reg a, String linha) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Brinco ${a['brinco']}',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              Text(linha, style: const TextStyle(color: Colors.white70, fontSize: 17)),
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
      );

  Widget _opcoes(String titulo, String campo, List<String> opcoes, {String Function(String)? rotulo}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in opcoes)
              ChoiceChip(
                label: Text(rotulo == null ? o : rotulo(o), style: const TextStyle(fontSize: 16)),
                selected: _ficha[campo] == o,
                onSelected: (sel) => setState(() => _ficha[campo] = sel ? o : null),
              ),
          ]),
        ]),
      );

  Widget _painelFicha(Reg a) {
    final auto = fichaAutomatica(a['id'] as int, _data);
    final dias = auto['dias_parida'];
    final tratamentos = (_ficha['tratamentos'] as List<String>?) ?? <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cabecalhoVaca(a, [
        auto['categoria_ia'],
        if (dias != null) '$dias dias de parida',
        '${auto['ordem']}º serviço',
        if (txt(a['raca']).isNotEmpty) txt(a['raca']),
      ].join(' · ')),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ECC', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final n in notasEcc)
                    ChoiceChip(
                      label: Text(num1(n), style: const TextStyle(fontSize: 16)),
                      selected: _ficha['ecc'] == n,
                      onSelected: (sel) => setState(() => _ficha['ecc'] = sel ? n : null),
                    ),
                ]),
              ]),
            ),
            _opcoes('Escore de cio', 'escore_cio', escoresCio),
            _opcoes('Implante', 'implante', statusImplante),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bezerro ao pé', style: TextStyle(fontWeight: FontWeight.w700)),
              value: _ficha['bezerro'] == true,
              onChanged: (v) => setState(() => _ficha['bezerro'] = v),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Mais detalhes', style: TextStyle(fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                _opcoes('Ciclicidade', 'ciclicidade', opcoesCiclicidade),
                _opcoes('Saída do brete', 'saida_brete', saidasBrete),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in tratamentosIa)
                      FilterChip(
                        label: Text(t),
                        selected: tratamentos.contains(t),
                        onSelected: (sel) => setState(() => _ficha['tratamentos'] = [
                              for (final x in tratamentosIa)
                                if (x == t ? sel : tratamentos.contains(x)) x,
                            ]),
                      ),
                  ]),
                ),
                gap,
                Row(children: [
                  Expanded(child: campoTexto(_peso, 'Peso', numero: true, sufixo: 'kg')),
                  const SizedBox(width: 8),
                  Expanded(child: campoTexto(_temperatura, 'Temp. retal', numero: true, sufixo: '°C')),
                ]),
                gap,
                Row(children: [
                  Expanded(child: campoTexto(_folD, 'Folículo direito', numero: true, sufixo: 'mm')),
                  const SizedBox(width: 8),
                  Expanded(child: campoTexto(_folE, 'Folículo esquerdo', numero: true, sufixo: 'mm')),
                ]),
              ],
            ),
            campoTexto(_obs, 'Observação clínica'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Cores.sucesso, minimumSize: const Size.fromHeight(80)),
        onPressed: () => _registrar(a, ficha: _fichaPreenchida()),
        icon: const Icon(Icons.favorite, size: 34),
        label: Text('INSEMINAR · $_tipo'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Cores.alerta, minimumSize: const Size.fromHeight(56)),
        onPressed: () => _descartar(a),
        icon: const Icon(Icons.block),
        label: const Text('DESCARTE / REFUGO'),
      ),
    ]);
  }

  Widget _painelConfirmacao(Reg a, Reg s) {
    final dias = diasEntre(txt(s['data']), _data);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cabecalhoVaca(a, [
        '2º diagnóstico · ${s['tipo']} em ${br(s['data'])} ($dias dias)',
        if (txt(s['touro']).isNotEmpty) txt(s['touro']),
      ].join(' · ')),
      const SizedBox(height: 14),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Cores.sucesso, minimumSize: const Size.fromHeight(80)),
        onPressed: () => _confirmar(true),
        icon: const Icon(Icons.verified, size: 34),
        label: Text('CONFIRMA PRENHE · parto ${br(s['parto_previsto'])}'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Cores.alerta, minimumSize: const Size.fromHeight(80)),
        onPressed: () => _confirmar(false),
        icon: const Icon(Icons.close, size: 34),
        label: const Text('PERDEU · VAZIA'),
      ),
    ]);
  }
}

String _hhmm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String _agora() {
  final d = DateTime.now();
  return _hhmm(d.hour, d.minute);
}
