// Partes do Painel do criador (criador.dart): saúde e uso das contas,
// cancelamentos, WhatsApp em lote, fazenda do cliente só leitura,
// pagamentos e histórico da conta.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/cotacao_compra.dart' show telefoneWhats;
import '../dados/db.dart';
import '../dados/painel_criador.dart';
import '../dados/planos.dart';
import '../dados/plataforma.dart';
import '../tema.dart';
import '../util/util.dart';

typedef DocConta = QueryDocumentSnapshot<Map<String, dynamic>>;

String _reais(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _quando(Object? v) {
  final d = dataDe(v);
  return d == null ? '—' : br(d.toIso8601String());
}

/// Barra horizontal com rótulo e número (para rankings simples).
class _Barra extends StatelessWidget {
  const _Barra(this.rotulo, this.valor, this.maximo, {this.extra = ''});
  final String rotulo, extra;
  final int valor, maximo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          SizedBox(width: 130, child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 14,
                  width: maximo == 0 ? 0 : c.maxWidth * valor / maximo,
                  decoration: BoxDecoration(color: Cores.oliva, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$valor$extra', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

// ---------- Saúde e uso ----------

class SaudeEUso extends StatelessWidget {
  const SaudeEUso({super.key, required this.contas, required this.itemCliente, required this.telasDoMenu});
  final List<DocConta> contas;
  final Widget Function(DocConta) itemCliente;
  final List<String> telasDoMenu;

  @override
  Widget build(BuildContext context) {
    final donos = contas.where((c) => (c.data()['papel'] ?? 'dono') == 'dono' && c.data()['status'] != 'suspensa').toList();
    final risco = donos.where((c) => emRisco(c.data())).toList()
      ..sort((a, b) => saudeConta(a.data()).compareTo(saudeConta(b.data())));

    // Telas do menu: quantas vezes foram abertas e por quantas contas.
    final usos = <String, int>{}, contasPorTela = <String, int>{};
    for (final c in contas) {
      final uso = c.data()['uso'];
      if (uso is! Map) continue;
      for (final e in uso.entries) {
        usos['${e.key}'] = (usos['${e.key}'] ?? 0) + ((e.value as num?)?.toInt() ?? 0);
        contasPorTela['${e.key}'] = (contasPorTela['${e.key}'] ?? 0) + 1;
      }
    }
    final ranking = usos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final nunca = telasDoMenu.where((t) => !usos.containsKey(t)).toList();

    final porUf = <String, int>{};
    for (final c in donos) {
      final uf = ufDaConta(c.data()) ?? 'Sem estado';
      porUf[uf] = (porUf[uf] ?? 0) + 1;
    }
    final ufs = porUf.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Alertas de abuso.
    final equipePorDono = <String, int>{};
    for (final c in contas) {
      final dono = c.data()['dono'];
      if ((c.data()['papel'] ?? 'dono') != 'dono' && dono is String) equipePorDono[dono] = (equipePorDono[dono] ?? 0) + 1;
    }
    final alertas = <(DocConta, String)>[];
    for (final c in donos) {
      final d = c.data();
      final plano = PlanoEito.de(d['plano']);
      if (planosPagos.contains(d['plano']) && plano.situacao((d['animais'] as num?)?.toInt() ?? 0) == 'acima') {
        alertas.add((c, '${d['animais']} animais no plano ${plano.nome} (limite ${plano.maxAnimais})'));
      }
      final aparelhos = (d['aparelhos'] as List?)?.length ?? 0;
      if (aparelhos >= limiteAparelhos) alertas.add((c, 'Login usado em $aparelhos aparelhos'));
      final equipe = equipePorDono[c.id] ?? 0;
      final cabe = plano.maxPorPapel.values.fold<int>(0, (s, v) => s + v);
      if (planosPagos.contains(d['plano']) && equipe > cabe) {
        alertas.add((c, '$equipe pessoas na equipe; o plano ${plano.nome} permite $cabe'));
      }
    }

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Secao('Em risco de desistir (${risco.length})'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Nota de 0 a 100 juntando acesso recente, animais, fazenda cadastrada e telas usadas. Abaixo de 40 = risco.',
            style: TextStyle(color: Colors.black54)),
      ),
      if (risco.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final c in risco.take(30)) itemCliente(c),
      const Secao('Alertas'),
      if (alertas.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final (c, motivo) in alertas)
        ListTile(
          leading: const Icon(Icons.warning_amber, color: Cores.alerta),
          title: Text('${c.data()['email'] ?? c.id}'),
          subtitle: Text(motivo),
        ),
      const Secao('Telas mais usadas'),
      if (ranking.isEmpty)
        const ListTile(title: Text('Ainda sem dados. A contagem começa a partir desta versão do app.')),
      for (final e in ranking.take(12))
        _Barra(e.key, e.value, ranking.first.value, extra: ' · ${contasPorTela[e.key]} conta(s)'),
      if (ranking.isNotEmpty && nunca.isNotEmpty)
        ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: const Text('Ninguém abriu ainda'),
          subtitle: Text(nunca.join(', ')),
        ),
      const Secao('Clientes por estado'),
      if (ufs.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final e in ufs) _Barra(e.key, e.value, ufs.first.value),
      const Secao('Satisfação (NPS)'),
      const _Nps(),
    ]);
  }
}

class _Nps extends StatelessWidget {
  const _Nps();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PainelCriador.nps.snapshots(),
      builder: (context, s) {
        final docs = [...?s.data?.docs]..sort((a, b) => '${b.data()['em']}'.compareTo('${a.data()['em']}'));
        final notas = [for (final d in docs) (d.data()['nota'] as num?)?.toInt() ?? 0];
        final nps = calcularNps(notas);
        if (nps == null) {
          return const ListTile(
              title: Text('Nenhuma nota ainda. O app pergunta a quem tem conta há 21 dias ou mais.'));
        }
        return Column(children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: nps >= 50 ? Cores.sucesso : (nps >= 0 ? Cores.laranja : Cores.alerta),
              child: Text('$nps', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            title: Text('NPS $nps · ${notas.length} resposta(s)'),
            subtitle: Text('Promotores (9-10): ${notas.where((n) => n >= 9).length} · '
                'neutros (7-8): ${notas.where((n) => n == 7 || n == 8).length} · '
                'detratores (0-6): ${notas.where((n) => n <= 6).length}'),
          ),
          for (final d in docs.where((d) => '${d.data()['comentario'] ?? ''}'.isNotEmpty).take(15))
            ListTile(
              dense: true,
              leading: Text('${d.data()['nota']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              title: Text('${d.data()['comentario']}'),
              subtitle: Text('${d.data()['email'] ?? ''} · ${d.data()['plano'] ?? ''}'),
            ),
        ]);
      },
    );
  }
}

// ---------- Cancelamentos ----------

class CancelamentosDoMes extends StatelessWidget {
  const CancelamentosDoMes({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PainelCriador.historico.where('acao', isEqualTo: 'Cancelamento').snapshots(),
      builder: (context, s) {
        final agora = DateTime.now();
        final mes = [
          for (final d in s.data?.docs ?? const <DocConta>[])
            if (dataDe(d.data()['em']) case final em? when em.year == agora.year && em.month == agora.month) d.data(),
        ];
        final motivos = <String, int>{};
        for (final m in mes) {
          final chave = '${m['motivo'] ?? 'Sem motivo'}'.split(':').first;
          motivos[chave] = (motivos[chave] ?? 0) + 1;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Secao('Cancelamentos neste mês (${mes.length})'),
          if (mes.isEmpty) const ListTile(title: Text('Nenhum.')),
          for (final e in motivos.entries) _Barra(e.key, e.value, mes.length),
        ]);
      },
    );
  }
}

// ---------- WhatsApp em lote ----------

class WhatsEmLote extends StatefulWidget {
  const WhatsEmLote({super.key, required this.contas});
  final List<Map<String, dynamic>> contas;

  @override
  State<WhatsEmLote> createState() => _WhatsEmLoteState();
}

class _WhatsEmLoteState extends State<WhatsEmLote> {
  String _modelo = 'Conforme a situação';
  final _enviados = <int>{};

  String _texto(Map<String, dynamic> c) {
    final nome = '${c['nome'] ?? ''}';
    final teste = (c['plano'] ?? 'Teste') == 'Teste';
    return switch (_modelo) {
      'Cobrança do teste' => textoCobrancaTeste(nome, dataDe(c['teste_ate'])),
      'Chamar de volta' => textoSumido(nome),
      'Boas-vindas' => textoBoasVindas(nome),
      _ => teste ? textoCobrancaTeste(nome, dataDe(c['teste_ate'])) : textoSumido(nome),
    };
  }

  @override
  Widget build(BuildContext context) {
    final semFone = widget.contas.where((c) => telefoneWhats('${c['telefone'] ?? ''}') == null).length;
    return Scaffold(
      appBar: AppBar(title: Text('WhatsApp para ${widget.contas.length} conta(s)')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: escolha('Mensagem', _modelo, const ['Conforme a situação', 'Cobrança do teste', 'Chamar de volta', 'Boas-vindas'],
              (v) => setState(() => _modelo = v ?? _modelo)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('O WhatsApp só deixa abrir uma conversa por vez: toque em cada um e volte para o próximo.',
              style: TextStyle(color: Colors.black54)),
        ),
        if (semFone > 0)
          ListTile(leading: const Icon(Icons.phone_disabled), title: Text('$semFone conta(s) sem telefone ficam de fora.')),
        for (final (i, c) in widget.contas.indexed)
          if (telefoneWhats('${c['telefone'] ?? ''}') case final fone?)
            ListTile(
              leading: Icon(_enviados.contains(i) ? Icons.check_circle : Icons.chat,
                  color: _enviados.contains(i) ? Cores.sucesso : const Color(0xFF25D366)),
              title: Text('${c['nome'] ?? ''}'.isEmpty ? '${c['email']}' : '${c['nome']}'),
              subtitle: Text('${c['telefone']} · ${situacaoConta(c)}'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                await launchUrl(Uri.parse('https://wa.me/$fone?text=${Uri.encodeComponent(_texto(c))}'),
                    mode: LaunchMode.externalApplication);
                setState(() => _enviados.add(i));
              },
            ),
      ]),
    );
  }
}

// ---------- Fazenda do cliente (só leitura) ----------

/// Nome das tabelas para a tela (as que não estão aqui aparecem como estão).
const _nomesTabelas = {
  'propriedades': 'Propriedades',
  'lotes': 'Lotes',
  'piquetes': 'Piquetes',
  'animais': 'Animais',
  'reproducoes': 'Reprodução',
  'sanidade': 'Sanidade',
  'pesagens': 'Pesagens',
  'saidas': 'Saídas (vendas e mortes)',
  'entradas': 'Entradas (compras)',
  'contas': 'Contas a pagar/receber',
  'custos': 'Custos',
  'estoque': 'Estoque',
  'tarefas': 'Tarefas',
  'chuvas': 'Chuvas',
  'config': 'Configurações',
};

class FazendaDoCliente extends StatelessWidget {
  const FazendaDoCliente({super.key, required this.uid, required this.email});
  final String uid, email;

  CollectionReference<Map<String, dynamic>> _tabela(String t) => Db.banco.collection('usuarios').doc(uid).collection(t);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fazenda de $email')),
      body: ListView(children: [
        Container(
          color: Cores.azul.withValues(alpha: 0.10),
          padding: const EdgeInsets.all(12),
          child: const Text('Só leitura: você vê o que o cliente lançou, sem poder alterar nada.'),
        ),
        for (final t in Db.tabelas)
          FutureBuilder<AggregateQuerySnapshot>(
            future: _tabela(t).count().get(),
            builder: (context, s) {
              final n = s.data?.count;
              if (s.hasError) {
                return ListTile(title: Text(_nomesTabelas[t] ?? t), subtitle: const Text('Sem permissão (publique as regras novas)'));
              }
              if (n == 0) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.table_rows_outlined),
                title: Text(_nomesTabelas[t] ?? t),
                trailing: Text(n == null ? '…' : '$n'),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => _TabelaDoCliente(titulo: _nomesTabelas[t] ?? t, ref: _tabela(t)))),
              );
            },
          ),
      ]),
    );
  }
}

class _TabelaDoCliente extends StatelessWidget {
  const _TabelaDoCliente({required this.titulo, required this.ref});
  final String titulo;
  final CollectionReference<Map<String, dynamic>> ref;

  static String _resumo(Map<String, dynamic> d) {
    for (final campo in ['brinco', 'nome', 'descricao', 'titulo', 'data']) {
      final v = '${d[campo] ?? ''}';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: ref.limit(300).get(),
        builder: (context, s) {
          if (s.hasError) return Vazio('Não foi possível ler (${s.error}).', icone: Icons.lock_outline);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.where((d) => d.data()['excluido'] != true).toList();
          if (docs.isEmpty) return const Vazio('Nada aqui.');
          return ListView(children: [
            if (docs.length >= 300) const ListTile(title: Text('Mostrando os 300 primeiros.')),
            for (final d in docs)
              ExpansionTile(
                title: Text(_resumo(d.data()).isEmpty ? d.id : _resumo(d.data())),
                subtitle: Text('${d.data()['status'] ?? ''}'),
                children: [
                  for (final e in (d.data().entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                    if (e.value != null && '${e.value}'.isNotEmpty) Info(e.key, '${e.value}'),
                ],
              ),
          ]);
        },
      ),
    );
  }
}

// ---------- Pagamentos e histórico da conta ----------

class PagamentosDaConta extends StatelessWidget {
  const PagamentosDaConta({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PainelCriador.pagamentos.where('uid', isEqualTo: uid).snapshots(),
      builder: (context, s) {
        final docs = [...?s.data?.docs]
          ..sort((a, b) => (dataDe(b.data()['data']) ?? DateTime(1900)).compareTo(dataDe(a.data()['data']) ?? DateTime(1900)));
        final total = docs.fold<double>(0, (t, d) => t + ((d.data()['valor'] as num?)?.toDouble() ?? 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Secao('Pagamentos · total ${_reais(total)}'),
          if (docs.isEmpty) const ListTile(title: Text('Nenhum registrado.')),
          for (final d in docs)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: Cores.sucesso),
              title: Text('${_reais((d.data()['valor'] as num?) ?? 0)} · ${d.data()['plano']} ${d.data()['periodo']}'),
              subtitle: Text('${_quando(d.data()['data'])} · ${d.data()['forma'] ?? ''} · vale até ${_quando(d.data()['vale_ate'])}'),
              onLongPress: () async {
                if (await confirmar(context, 'Apagar este pagamento?', 'O vencimento do plano não muda sozinho.', ok: 'Apagar')) {
                  await d.reference.delete();
                  await PainelCriador.anotar(uid, 'Pagamento apagado', detalhe: _reais((d.data()['valor'] as num?) ?? 0));
                }
              },
            ),
        ]);
      },
    );
  }
}

class HistoricoDaConta extends StatelessWidget {
  const HistoricoDaConta({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PainelCriador.historico.where('uid', isEqualTo: uid).snapshots(),
      builder: (context, s) {
        final docs = [...?s.data?.docs]
          ..sort((a, b) => (dataDe(b.data()['em']) ?? DateTime(2100)).compareTo(dataDe(a.data()['em']) ?? DateTime(2100)));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Secao('Histórico de mudanças'),
          if (docs.isEmpty) const ListTile(title: Text('Nenhuma mudança registrada ainda.')),
          for (final d in docs.take(50))
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text([d.data()['acao'], d.data()['detalhe']].where((v) => '${v ?? ''}'.isNotEmpty).join(' · ')),
              subtitle: Text([
                _quando(d.data()['em']),
                if ('${d.data()['motivo'] ?? ''}'.isNotEmpty) 'motivo: ${d.data()['motivo']}',
                if ('${d.data()['por'] ?? ''}'.isNotEmpty) 'por ${d.data()['por']}',
              ].join(' · ')),
            ),
        ]);
      },
    );
  }
}
