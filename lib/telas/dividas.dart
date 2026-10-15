import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/dividas.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';

/// Dívidas da propriedade, parcelas a vencer e ônus reais (hipoteca, penhor, alienação).
class DividasPage extends StatelessWidget {
  const DividasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hoje = hojeIso();
    return Pagina(
      titulo: 'Dívidas e ônus reais',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('Nova dívida'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DividaFormPage())),
      ),
      corpo: AoMudar<(List<Reg>, List<ParcelaAberta>)>(
        carregar: () async => (dividas(), parcelasAVencer(hoje)),
        builder: (context, d) {
          final (ds, aVencer) = d;
          if (ds.isEmpty) {
            return const Vazio('Nenhuma dívida lançada. Lance financiamentos, empréstimos e as garantias dadas.',
                icone: Icons.account_balance_outlined);
          }
          final saldo = ds.fold<double>(0, (s, x) => s + saldoDevedor(x));
          final onus = ds.where(onusAtivo).toList();
          final vencidas = aVencer.where((p) => p.vencimento.compareTo(hoje) < 0).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 100,
                child: Row(children: [
                  Expanded(child: Kpi('Saldo devedor', moeda(saldo), icone: Icons.account_balance_outlined)),
                  Expanded(
                    child: Kpi('Vence em 90 dias', moeda(aVencer.fold<double>(0, (s, p) => s + p.valor)),
                        icone: Icons.event_outlined, cor: vencidas.isEmpty ? null : Cores.alerta),
                  ),
                  Expanded(child: Kpi('Ônus ativos', '${onus.length}', icone: Icons.gavel_outlined)),
                ]),
              ),
            ),
            if (aVencer.isNotEmpty) ...[
              Secao('A pagar até 90 dias (${aVencer.length})'),
              for (final p in aVencer)
                CheckboxListTile(
                  dense: true,
                  value: false,
                  onChanged: (_) => pagarParcela(p.divida, p.indice, true, data: hoje),
                  title: Text('${moeda(p.valor)} · ${p.divida['credor'] ?? p.divida['tipo']}'),
                  subtitle: Text(p.vencimento.compareTo(hoje) < 0 ? 'Vencida em ${br(p.vencimento)}' : 'Vence em ${br(p.vencimento)}',
                      style: TextStyle(color: p.vencimento.compareTo(hoje) < 0 ? Cores.alerta : null)),
                ),
            ],
            Secao('Dívidas (${ds.length})'),
            for (final x in ds) _DividaTile(x),
            Secao('Ônus reais ativos (${onus.length})'),
            if (onus.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nenhum bem com garantia ativa.')),
            for (final x in onus)
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: Text('${x['onus']}${txt(x['bem']).isEmpty ? '' : ' · ${x['bem']}'}'),
                subtitle: Text([
                  if (txt(x['registro']).isNotEmpty) txt(x['registro']),
                  'em favor de ${txt(x['credor']).isEmpty ? '-' : x['credor']}',
                  'saldo ${moeda(saldoDevedor(x))}',
                ].join(' · ')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DividaFormPage(divida: x))),
              ),
          ]);
        },
      ),
    );
  }
}

class _DividaTile extends StatelessWidget {
  const _DividaTile(this.d);
  final Reg d;

  @override
  Widget build(BuildContext context) {
    final ps = parcelas(d);
    final pagas = ps.where((p) => p['pago'] == true).length;
    final prox = proximaParcela(d);
    return ListTile(
      leading: Icon(quitada(d) ? Icons.check_circle : Icons.account_balance_outlined,
          color: quitada(d) ? Cores.sucesso : null),
      title: Text('${txt(d['credor']).isEmpty ? d['tipo'] : d['credor']} · ${moeda(d['valor_total'] as num?)}'),
      subtitle: Text([
        txt(d['tipo']),
        if (ps.isNotEmpty) '$pagas/${ps.length} parcelas pagas',
        if (prox != null) 'próxima ${br(prox['vencimento'])}',
        if (onusAtivo(d)) txt(d['onus']),
      ].join(' · ')),
      trailing: Text(quitada(d) ? 'Quitada' : moeda(saldoDevedor(d))),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DividaFormPage(divida: d))),
    );
  }
}

class DividaFormPage extends StatefulWidget {
  const DividaFormPage({super.key, this.divida});
  final Reg? divida;

  @override
  State<DividaFormPage> createState() => _DividaFormPageState();
}

class _DividaFormPageState extends State<DividaFormPage> {
  Reg? get d => widget.divida;
  static String _n(Object? v) => v is num ? numeroBr(v.toDouble(), casas: 2) : '';

  late final credor = TextEditingController(text: txt(d?['credor']));
  late String tipo = txt(d?['tipo']).isEmpty ? tiposDivida.first : txt(d!['tipo']);
  late final contrato = TextEditingController(text: txt(d?['contrato']));
  late String? data = txt(d?['data']).isEmpty ? hojeIso() : txt(d!['data']);
  late final valor = TextEditingController(text: _n(d?['valor_total']));
  late final taxa = TextEditingController(text: _n(d?['taxa']));
  late final qtd = TextEditingController(text: '${parcelas(d ?? const {}).isEmpty ? 1 : parcelas(d!).length}');
  late String? primeiro = parcelas(d ?? const {}).firstOrNull?['vencimento'] as String?;
  int intervalo = 12;
  late List<Map<String, Object?>> ps = parcelas(d ?? const {});
  late String onus = txt(d?['onus']).isEmpty ? 'Nenhum' : txt(d!['onus']);
  late final bem = TextEditingController(text: txt(d?['bem']));
  late final registro = TextEditingController(text: txt(d?['registro']));
  late bool baixado = d?['onus_baixado'] == true;
  late final obs = TextEditingController(text: txt(d?['obs']));

  @override
  void dispose() {
    for (final c in [credor, contrato, valor, taxa, qtd, bem, registro, obs]) {
      c.dispose();
    }
    super.dispose();
  }

  void _gerar() {
    final total = lerNumero(valor.text);
    final n = (lerNumero(qtd.text) ?? 0).round();
    if (total == null || total <= 0 || n <= 0 || primeiro == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o valor, o número de parcelas e o 1º vencimento.')));
      return;
    }
    setState(() => ps = gerarParcelas(total, n, primeiro!, intervaloMeses: intervalo));
  }

  Future<void> _salvar() async {
    final total = lerNumero(valor.text);
    if (total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o valor da dívida.')));
      return;
    }
    final dados = <String, Object?>{
      'credor': nulo(credor.text),
      'tipo': tipo,
      'contrato': nulo(contrato.text),
      'data': data,
      'valor_total': total,
      'taxa': lerNumero(taxa.text),
      'parcelas': ps.isEmpty && primeiro != null ? gerarParcelas(total, 1, primeiro!) : ps,
      'onus': onus,
      'bem': onus == 'Nenhum' ? null : nulo(bem.text),
      'registro': onus == 'Nenhum' ? null : nulo(registro.text),
      'onus_baixado': onus != 'Nenhum' && baixado,
      'obs': nulo(obs.text),
    };
    if (d == null) {
      await Db.inserir('dividas', {...dados, 'propriedade_id': Db.pid});
    } else {
      await Db.atualizar('dividas', d!['id'] as int, dados);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir a dívida?', 'As parcelas e o ônus somem junto.', ok: 'Excluir')) return;
    await Db.excluir('dividas', d!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hoje = hojeIso();
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Nova dívida' : 'Dívida'),
        actions: [if (d != null) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        campoTexto(credor, 'Credor (banco, cooperativa, fornecedor)'),
        gap,
        Row(children: [
          Expanded(child: escolha('Tipo', tipo, tiposDivida, (v) => setState(() => tipo = v ?? tipo))),
          const SizedBox(width: 12),
          Expanded(child: campoTexto(contrato, 'Contrato / cédula')),
        ]),
        gap,
        Row(children: [
          Expanded(child: DateField(label: 'Contratada em', value: data, onChanged: (v) => setState(() => data = v))),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor total', prefixText: r'R$ '),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 90, child: campoTexto(taxa, 'Juros', numero: true, sufixo: '% a.a.')),
        ]),
        const Secao('Parcelas'),
        Row(children: [
          SizedBox(width: 70, child: campoTexto(qtd, 'Nº', numero: true)),
          const SizedBox(width: 8),
          Expanded(child: DateField(label: '1º vencimento', value: primeiro, onChanged: (v) => setState(() => primeiro = v))),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: escolha('A cada', {1: 'Mês', 6: 'Semestre', 12: 'Ano'}[intervalo], const ['Mês', 'Semestre', 'Ano'],
                (v) => setState(() => intervalo = {'Mês': 1, 'Semestre': 6, 'Ano': 12}[v] ?? 12)),
          ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(icon: const Icon(Icons.refresh), label: const Text('Gerar parcelas iguais'), onPressed: _gerar),
        ),
        for (var i = 0; i < ps.length; i++)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: ps[i]['pago'] == true,
            onChanged: (v) => setState(() => ps[i] = {...ps[i], 'pago': v == true, 'pago_em': v == true ? hoje : null}),
            title: Text('${i + 1}ª · ${moeda(ps[i]['valor'] as num?)} · vence ${br(ps[i]['vencimento'])}'),
            subtitle: ps[i]['pago'] == true && ps[i]['pago_em'] != null ? Text('Paga em ${br(ps[i]['pago_em'])}') : null,
          ),
        const Secao('Ônus real (garantia)'),
        escolha('Garantia', onus, tiposOnus, (v) => setState(() => onus = v ?? 'Nenhum')),
        if (onus != 'Nenhum') ...[
          gap,
          campoTexto(bem, 'Bem dado em garantia (imóvel, gado, safra, máquina)'),
          gap,
          campoTexto(registro, 'Matrícula / registro no cartório'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ônus já baixado no cartório'),
            value: baixado,
            onChanged: (v) => setState(() => baixado = v),
          ),
        ],
        gap,
        campoTexto(obs, 'Observações', linhas: 3),
        const SizedBox(height: 16),
        BotaoSalvar(onPressed: _salvar),
      ]),
    );
  }
}
