import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estacao.dart';
import '../tema.dart';
import '../util/util.dart';

String _pct(double? v) => v == null ? '-' : '${(v * 100).round()}%';

const _nomesMes = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
String _mes(String ym) => '${_nomesMes[int.parse(ym.substring(5, 7)) - 1]}/${ym.substring(0, 4)}';

/// Estações de monta da propriedade, cada uma com o resultado acumulado.
class EstacoesPage extends StatelessWidget {
  const EstacoesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estação de monta')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova estação'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstacaoFormPage())),
      ),
      body: AoMudar<List<Reg>>(
        carregar: () async => estacoes(),
        builder: (context, lista) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma estação cadastrada.\nToque em "Nova estação" e informe o início e o fim.',
                  textAlign: TextAlign.center),
            ),
          for (final e in lista)
            Builder(builder: (context) {
              final r = resultadoEstacao(e);
              return ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(txt(e['nome'])),
                subtitle: Text('${br(e['inicio'])} a ${br(e['fim'])}\n'
                    '${r.aptas.length} aptas · ${r.prenhes.length} prenhes · prenhez ${_pct(r.taxaPrenhez)}'),
                isThreeLine: true,
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => EstacaoResultadoPage(e['id'] as int))),
              );
            }),
          const Divider(),
          const _PrevisaoPartos(),
        ]),
      ),
    );
  }
}

/// Partos previstos por mês, com bezerras e bezerros quando houve sexagem.
class _PrevisaoPartos extends StatelessWidget {
  const _PrevisaoPartos();

  @override
  Widget build(BuildContext context) {
    final meses = previsaoPartos();
    if (meses.isEmpty) return const SizedBox.shrink();
    final femeas = meses.fold(0, (s, m) => s + m.femeas);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Secao('Partos previstos'),
      for (final m in meses)
        ListTile(
          dense: true,
          title: Text(_mes(m.mes)),
          subtitle: m.femeas + m.machos == 0
              ? null
              : Text([
                  if (m.femeas > 0) '${m.femeas} bezerra${m.femeas == 1 ? '' : 's'}',
                  if (m.machos > 0) '${m.machos} bezerro${m.machos == 1 ? '' : 's'}',
                  if (m.semSexagem > 0) '${m.semSexagem} sem sexagem',
                ].join(' · ')),
          trailing: Text('${m.total}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      if (femeas > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text('Previsão pela sexagem fetal: $femeas bezerra${femeas == 1 ? '' : 's'} a nascer.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

class EstacaoResultadoPage extends StatelessWidget {
  const EstacaoResultadoPage(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context) {
    return AoMudar<Reg?>(
      carregar: () async => Db.registro('estacoes', id),
      builder: (context, e) {
        if (e == null) return Scaffold(appBar: AppBar(), body: const Vazio('Estação excluída.'));
        final r = resultadoEstacao(e);
        Widget linha(String t, String v, {String? sub}) =>
            ListTile(dense: true, title: Text(t), subtitle: sub == null ? null : Text(sub), trailing: Text(v,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));
        return Scaffold(
          appBar: AppBar(
            title: Text(txt(e['nome'])),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EstacaoFormPage(estacao: e))),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('${br(e['inicio'])} a ${br(e['fim'])}', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Secao('Resultado'),
            linha('Fêmeas aptas', '${r.aptas.length}', sub: '12 meses ou mais e não prenhes no início'),
            linha('Servidas', '${r.servidas.length}', sub: 'Taxa de serviço ${_pct(r.taxaServico)}'),
            linha('Prenhes', '${r.prenhes.length}',
                sub: 'Taxa de prenhez ${_pct(r.taxaPrenhez)} · IATF/IA ${r.prenhesIatf} · repasse ${r.prenhesRepasse}'),
            linha('Vazias', '${r.vazias.length}'),
            linha('Aguardando diagnóstico', '${r.aguardando.length}'),
            if (r.ciclos.isNotEmpty) ...[
              const Secao('Prenhez acumulada (ciclos de 21 dias)'),
              for (final c in r.ciclos)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('Ciclo ${c.numero} · ${br(c.de)} a ${br(c.ate)}')),
                      Text('+${c.prenhes} · ${_pct(r.aptas.isEmpty ? null : c.acumulado / r.aptas.length)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: r.aptas.isEmpty ? 0 : c.acumulado / r.aptas.length,
                      minHeight: 8,
                      color: Cores.oliva,
                      backgroundColor: Cores.oliva.withValues(alpha: 0.12),
                    ),
                  ]),
                ),
            ],
            const Secao('Custos da estação'),
            linha('Sêmen', moeda(r.custoSemen)),
            linha('Hormônios dos protocolos', moeda(r.custoHormonios)),
            linha('Outros (veterinário, mão de obra...)', moeda(r.outrosCustos)),
            linha('Total', moeda(r.custoTotal)),
            linha('Custo por prenhez', moeda(r.custoPorPrenhez)),
            linha('Custo por bezerro desmamado', moeda(r.custoPorDesmamado),
                sub: '${r.bezerrosNascidos} nascidos · ${r.bezerrosDesmamados} com pesagem de desmama'),
            if (r.naoServidas.isNotEmpty) ...[
              Secao('Não servidas (${r.naoServidas.length})'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final a in r.naoServidas) Chip(label: Text(txt(a['brinco']))),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class EstacaoFormPage extends StatefulWidget {
  const EstacaoFormPage({super.key, this.estacao});
  final Reg? estacao;

  @override
  State<EstacaoFormPage> createState() => _EstacaoFormPageState();
}

class _EstacaoFormPageState extends State<EstacaoFormPage> {
  late final e = widget.estacao;
  late final nome = TextEditingController(text: txt(e?['nome']).isEmpty ? 'Estação ${DateTime.now().year}' : txt(e!['nome']));
  late final outros = TextEditingController(
      text: e?['outros_custos'] is num ? numeroBr((e!['outros_custos'] as num).toDouble(), casas: 2) : '');
  late String inicio = (e?['inicio'] as String?) ?? hojeIso();
  late String? fim = (e?['fim'] as String?) ?? somaDias(hojeIso(), 90);

  @override
  void dispose() {
    nome.dispose();
    outros.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (fim != null && fim!.compareTo(inicio) < 0) {
      avisar(context, 'O fim precisa ser depois do início.');
      return;
    }
    await salvarEstacao({
      'nome': nome.text.trim().isEmpty ? 'Estação de monta' : nome.text.trim(),
      'inicio': inicio,
      'fim': fim,
      'outros_custos': lerNumero(outros.text),
    }, id: e?['id'] as int?);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (await confirmar(context, 'Excluir estação?', 'Os serviços e diagnósticos continuam.', ok: 'Excluir')) {
      await Db.excluir('estacoes', e!['id'] as int);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'Nova estação' : 'Editar estação'),
        actions: [
          if (e != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      bottomNavigationBar: BotaoSalvar(onPressed: _salvar),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        campoTexto(nome, 'Nome'),
        gap,
        DateField(label: 'Início', value: inicio, obrigatorio: true, onChanged: (v) => setState(() => inicio = v!)),
        gap,
        DateField(label: 'Fim', value: fim, onChanged: (v) => setState(() => fim = v)),
        gap,
        campoTexto(outros, 'Outros custos da estação', numero: true, sufixo: 'R\$'),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Veterinário, mão de obra, frete... O sêmen e os hormônios dos protocolos entram sozinhos.'),
        ),
      ]),
    );
  }
}
