import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/db.dart';
import '../dados/iatf.dart';
import '../dados/manejo.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';
import 'concepcao.dart';
import 'financeiro.dart' show entregarArquivo;

String _pct(double? v) => v == null ? '-' : '${(v * 100).round()}%';

/// Resumo do resultado: "8 P+ · 2 V− · 80% · 3 aguardando DG".
String resumoResultado(ResultadoIatf r) => [
      if (r.diagnosticadas > 0) '${r.prenhes} P+ · ${r.vazias + r.perdas} V− · ${_pct(r.taxaPrenhez)}',
      if (r.perdas > 0) '${r.perdas} perda${r.perdas == 1 ? '' : 's'}',
      if (r.aguardando > 0) '${r.aguardando} aguardando DG',
      if (r.semIa > 0) '${r.semIa} sem IA',
    ].join(' · ');

/// Lotes de vacas em protocolo de IATF, com a data de cada etapa e o resultado.
class ProtocolosPage extends StatelessWidget {
  const ProtocolosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocolos de IATF'),
        actions: [
          IconButton(
            tooltip: 'Concepção por fator',
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConcepcaoPage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Novo protocolo'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProtocoloFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: Db.protocolos,
        builder: (context, lista) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum protocolo.\nToque em "Novo protocolo", escolha o D0 e leia os brincos das vacas.',
                icone: Icons.event_note);
          }
          final hoje = hojeIso();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final p = lista[i];
              final r = resultadoProtocolo(p);
              final res = resumoResultado(r);
              return ListTile(
                leading: const Icon(Icons.event_note),
                title: Text('${p['nome']} · D0 ${br(p['inicio'])} · ${r.vacas.length} '
                    '${r.vacas.length == 1 ? 'vaca' : 'vacas'}'),
                subtitle: Text([
                  for (final e in etapasDe(p))
                    '${Db.dataEtapa(p['inicio'], e['dia']).compareTo(hoje) < 0 ? '✔' : '•'} '
                        'D${e['dia']} ${br(Db.dataEtapa(p['inicio'], e['dia']))}'
                        '${txt(e['hora']).isEmpty ? '' : ' ${e['hora']}'}: ${e['nome']}',
                  if (res.isNotEmpty) res,
                ].join('\n')),
                isThreeLine: true,
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => ProtocoloResultadoPage(p['id'] as int))),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- Resultado do protocolo ----------------

class ProtocoloResultadoPage extends StatelessWidget {
  const ProtocoloResultadoPage(this.id, {super.key});
  final int id;

  Future<void> _relatorio(BuildContext context, Reg p) async {
    final completo = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.medical_services_outlined),
            title: const Text('Relatório do veterinário'),
            subtitle: const Text('Completo: etapas, ficha de cada vaca e concepção por touro e inseminador'),
            onTap: () => Navigator.pop(c, true),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Relatório do produtor'),
            subtitle: const Text('Enxuto: vaca, touro e resultado'),
            onTap: () => Navigator.pop(c, false),
          ),
        ]),
      ),
    );
    if (completo == null || !context.mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => _TextoPage('Relatório da IATF', relatorioProtocolo(p, completo: completo))));
  }

  Future<void> _ressinc(BuildContext context, Reg p) async {
    final vazias = vaziasParaRessinc(p);
    if (vazias.isEmpty) {
      avisar(context, 'Nenhuma vaca vazia neste protocolo.');
      return;
    }
    final inicio = await showDatePicker(
      context: context,
      helpText: 'D0 da ressincronização (${vazias.length} vazias)',
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (inicio == null || !context.mounted) return;
    final novo = await ressincronizar(p, isoDe(inicio));
    if (novo == null || !context.mounted) return;
    avisar(context, 'Ressincronização criada com ${vazias.length} vacas.');
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProtocoloResultadoPage(novo)));
  }

  Future<void> _vaca(BuildContext context, Reg p, VacaIatf v) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Brinco ${v.animal['brinco']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (v.situacao != SituacaoIatf.descartada)
            ListTile(
              leading: const Icon(Icons.block, color: Cores.alerta),
              title: const Text('Descarte / refugo'),
              subtitle: const Text('Tira a vaca do protocolo e marca o animal para descarte'),
              onTap: () => Navigator.pop(c, 'descarte'),
            ),
        ]),
      ),
    );
    if (op == 'descarte' && context.mounted) {
      if (await confirmar(context, 'Descartar brinco ${v.animal['brinco']}?',
          'A vaca sai das etapas do protocolo e fica marcada para descarte na ficha.', ok: 'Descartar')) {
        await descartarDoProtocolo(id, v.animal['id'] as int);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AoMudar<Reg?>(
      carregar: () async => Db.registro('protocolos', id),
      builder: (context, p) {
        if (p == null) return Scaffold(appBar: AppBar(), body: const Vazio('Protocolo excluído.'));
        final r = resultadoProtocolo(p);
        return Scaffold(
          appBar: AppBar(
            title: Text(txt(p['nome'])),
            actions: [
              IconButton(
                tooltip: 'Relatório (WhatsApp e Excel)',
                icon: const Icon(Icons.share),
                onPressed: () => _relatorio(context, p),
              ),
              IconButton(
                tooltip: 'Editar protocolo',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProtocoloFormPage(protocolo: p))),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _Numero('Vacas', '${r.vacas.length}'),
                _Numero('Prenhes', '${r.prenhes}', cor: Colors.green),
                _Numero('Vazias', '${r.vazias}', cor: Cores.alerta),
                if (r.perdas > 0) _Numero('Perdas', '${r.perdas}', cor: Colors.deepOrange),
                _Numero('Aguardando DG', '${r.aguardando}', cor: Colors.orange),
                _Numero('Taxa de prenhez', _pct(r.taxaPrenhez), cor: Cores.oliva),
                if (r.perdas > 0) _Numero('Perda embrionária', _pct(r.taxaPerda), cor: Colors.deepOrange),
              ]),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  [
                    for (final e in etapasDe(p))
                      'D${e['dia']} ${br(Db.dataEtapa(p['inicio'], e['dia']))}'
                          '${txt(e['hora']).isEmpty ? '' : ' às ${e['hora']}'}: ${e['nome']}',
                    'DG (${nomeTipoDg(r.dgDias)}): ${br(r.dgPrevisto)}',
                    'Confirmação da prenhez: ${br(r.confirmacaoPrevista)}',
                    'Partos previstos a partir de ${br(r.partoPrevisto)}',
                    if (txt(p['veterinario']).isNotEmpty) 'Veterinário: ${p['veterinario']}',
                  ].join('\n'),
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => _ressinc(context, p),
                  icon: const Icon(Icons.replay),
                  label: Text('Ressincronizar vazias (${vaziasParaRessinc(p).length})'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ConcepcaoPage(protocoloId: id))),
                  icon: const Icon(Icons.insights),
                  label: const Text('Concepção por fator'),
                ),
                OutlinedButton.icon(
                  onPressed: () => entregarArquivo(
                      context, 'iatf-${txt(p['nome']).replaceAll(RegExp(r'[^\w-]+'), '-')}.csv', planilhaProtocolo(p)),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Planilha (Excel)'),
                ),
              ]),
            ),
            const Divider(height: 24),
            for (final v in r.vacas)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: corSituacaoIatf(v.situacao),
                  foregroundColor: Colors.white,
                  child: Text(rotuloSituacao[v.situacao]!.length <= 2 ? rotuloSituacao[v.situacao]! : '•',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: Text('Brinco ${v.animal['brinco']}${txt(v.animal['nome']).isEmpty ? '' : ' – ${v.animal['nome']}'}'),
                subtitle: Text([
                  rotuloSituacao[v.situacao]! + (v.confirmada ? ' (confirmada)' : ''),
                  if (txt(v.servico?['touro']).isNotEmpty) txt(v.servico!['touro']),
                  if (txt(v.servico?['categoria_ia']).isNotEmpty) txt(v.servico!['categoria_ia']),
                  if (v.servico?['ecc'] is num) 'ECC ${num1(v.servico!['ecc'] as num)}',
                  if (txt(v.servico?['inseminador']).isNotEmpty) txt(v.servico!['inseminador']),
                ].join(' · ')),
                onTap: () => _vaca(context, p, v),
              ),
          ]),
        );
      },
    );
  }
}

String nomeTipoDg(int dias) =>
    tiposDg.entries.firstWhere((e) => e.value == dias, orElse: () => MapEntry('$dias dias', dias)).key;

Color corSituacaoIatf(SituacaoIatf s) => switch (s) {
      SituacaoIatf.prenhe => Colors.green,
      SituacaoIatf.vazia => Cores.alerta,
      SituacaoIatf.perda => Colors.deepOrange,
      SituacaoIatf.aguardando => Colors.orange,
      _ => Colors.grey,
    };

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor, {this.cor});
  final String titulo, valor;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (cor ?? Cores.tinta).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor)),
          Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );
}

/// Texto pronto para mandar pelo WhatsApp ou copiar.
class _TextoPage extends StatelessWidget {
  const _TextoPage(this.titulo, this.texto);
  final String titulo, texto;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(texto, style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size.fromHeight(56)),
            onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.send),
            label: const Text('ENVIAR PELO WHATSAPP'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (context.mounted) avisar(context, 'Texto copiado.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar texto'),
          ),
        ]),
      );
}

// ---------------- Cadastro do protocolo ----------------

class ProtocoloFormPage extends StatefulWidget {
  const ProtocoloFormPage({super.key, this.protocolo});
  final Reg? protocolo;

  @override
  State<ProtocoloFormPage> createState() => _ProtocoloFormPageState();
}

/// Etapa em edição: dia (a partir do D0), o que fazer e o horário.
class _Etapa {
  _Etapa(int dia, String nome, this.hora)
      : dia = TextEditingController(text: '$dia'),
        nome = TextEditingController(text: nome);
  final TextEditingController dia, nome;
  String? hora;
  int get d => int.tryParse(dia.text.trim()) ?? 0;
}

class _ProtocoloFormPageState extends State<ProtocoloFormPage> {
  late final p = widget.protocolo;
  late final nome = TextEditingController(text: txt(p?['nome']).isEmpty ? protocolosIatf.keys.first : txt(p!['nome']));
  late final veterinario = TextEditingController(text: txt(p?['veterinario']));
  late String inicio = (p?['inicio'] as String?) ?? hojeIso();
  late int dgDias = (p?['dg_dias'] as num?)?.toInt() ?? 30;
  late final List<_Etapa> etapas = p == null
      ? _doModelo(protocolosIatf.keys.first)
      : [for (final e in etapasDe(p!)) _Etapa((e['dia'] as num?)?.toInt() ?? 0, txt(e['nome']), e['hora'] as String?)];
  late final List<Reg> vacas = [
    for (final id in (p?['femeas'] as List?) ?? const [])
      if (Db.registro('animais', id) case final a?) a,
  ];
  VoidCallback? _cancelarLeitor;

  static List<_Etapa> _doModelo(String m) => [for (final (dia, n) in protocolosIatf[m]!) _Etapa(dia, n, null)];

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar((c) {
      if (!(ModalRoute.of(context)?.isCurrent ?? false) || parecePeso(c)) return;
      _adicionar(c);
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    nome.dispose();
    veterinario.dispose();
    for (final e in etapas) {
      e.dia.dispose();
      e.nome.dispose();
    }
    super.dispose();
  }

  void _usarModelo(String m) => setState(() {
        nome.text = m;
        etapas
          ..clear()
          ..addAll(_doModelo(m));
      });

  Future<void> _hora(_Etapa e) async {
    final partes = (e.hora ?? '08:00').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(partes[0]) ?? 8, minute: int.tryParse(partes.last) ?? 0),
    );
    if (t != null) {
      setState(() => e.hora = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _adicionar(String codigo) async {
    final a = await Db.buscarPorCodigo(codigo);
    if (!mounted) return;
    if (a == null || a['status'] != 'Ativo' || a['sexo'] != 'F') {
      avisar(context, a == null ? 'Brinco $codigo não cadastrado.' : 'Brinco ${a['brinco']} não é fêmea ativa.');
      return;
    }
    if (vacas.any((v) => v['id'] == a['id'])) {
      avisar(context, 'Brinco ${a['brinco']} já está no protocolo.');
      return;
    }
    setState(() => vacas.add(a));
  }

  Future<void> _digitar() async {
    final c = await pedirNumero(context, titulo: 'Número do brinco');
    if (c != null && c.trim().isNotEmpty) _adicionar(c.trim());
  }

  Future<void> _escolher() async {
    final r = await pickAnimais(context, titulo: 'Vacas do protocolo', iniciais: [for (final v in vacas) v['id'] as int]);
    if (r == null) return;
    setState(() => vacas
      ..clear()
      ..addAll(r.where((a) => a['sexo'] == 'F')));
  }

  Future<void> _salvar() async {
    if (vacas.isEmpty) {
      avisar(context, 'Leia ou escolha as vacas.');
      return;
    }
    final lista = [for (final e in etapas) if (e.nome.text.trim().isNotEmpty) e]..sort((a, b) => a.d.compareTo(b.d));
    if (lista.isEmpty) {
      avisar(context, 'Informe as etapas do protocolo.');
      return;
    }
    await Db.salvarProtocolo(
      id: p?['id'] as int?,
      nome: nome.text.trim().isEmpty ? 'IATF' : nome.text.trim(),
      inicio: inicio,
      etapas: [
        for (final e in lista) {'dia': e.d, 'nome': e.nome.text.trim(), if (e.hora != null) 'hora': e.hora},
      ],
      femeas: [for (final v in vacas) v['id'] as int],
      extras: {'dg_dias': dgDias, 'veterinario': nulo(veterinario.text)},
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (await confirmar(context, 'Excluir protocolo?', 'As inseminações já lançadas continuam.', ok: 'Excluir')) {
      await Db.excluir('protocolos', p!['id'] as int);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Novo protocolo' : 'Editar protocolo'),
        actions: [
          if (p != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Modelo:')),
          for (final m in protocolosIatf.keys) ActionChip(label: Text(m), onPressed: () => _usarModelo(m)),
        ]),
        gap,
        campoTexto(nome, 'Nome do protocolo'),
        gap,
        DateField(label: 'D0 (início)', value: inicio, obrigatorio: true, onChanged: (v) => setState(() => inicio = v!)),
        gap,
        Text('Etapas (a última é a inseminação)', style: Theme.of(context).textTheme.titleSmall),
        for (final e in etapas)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: e.dia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dia', prefixText: 'D'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: campoTexto(e.nome, 'Manejo e produtos')),
              TextButton(
                onPressed: () => _hora(e),
                child: Text(e.hora ?? 'Hora'),
              ),
              IconButton(
                tooltip: 'Tirar etapa',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => etapas.remove(e)),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => etapas.add(_Etapa(etapas.isEmpty ? 0 : etapas.last.d + 1, '', null))),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar etapa'),
          ),
        ),
        for (final e in [...etapas]..sort((a, b) => a.d.compareTo(b.d)))
          Text('D${e.d}: ${br(Db.dataEtapa(inicio, e.d))}${e.hora == null ? '' : ' às ${e.hora}'}',
              style: const TextStyle(color: Colors.black54)),
        gap,
        Text('Diagnóstico de gestação', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: [
            for (final t in tiposDg.entries) ButtonSegment(value: t.value, label: Text('${t.key} (${t.value} dias)')),
          ],
          selected: {dgDias},
          onSelectionChanged: (s) => setState(() => dgDias = s.first),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('A confirmação da prenhez entra na fila do dia aos $diasConfirmacao dias da IA.'),
        ),
        gap,
        campoTexto(veterinario, 'Veterinário / técnico'),
        const Divider(height: 32),
        Text('${vacas.length} ${vacas.length == 1 ? 'vaca' : 'vacas'} · encoste o bastão no brinco para incluir',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in vacas)
            InputChip(label: Text(txt(v['brinco'])), onDeleted: () => setState(() => vacas.remove(v))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _digitar, icon: const Icon(Icons.dialpad), label: const Text('Digitar brinco')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(onPressed: _escolher, icon: const Icon(Icons.checklist), label: const Text('Escolher')),
          ),
        ]),
      ]),
    );
  }
}
