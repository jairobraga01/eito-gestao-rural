import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/cotacao_compra.dart' show telefoneWhats;
import '../dados/financeiro.dart' show csv;
import '../dados/indicacoes.dart';
import '../dados/painel_criador.dart';
import '../dados/planos.dart';
import '../dados/plataforma.dart';
import '../tema.dart';
import '../util/util.dart';
import 'ajuda.dart' show ItemChamado;
import 'base.dart' show itensMenu;
import 'criador_mais.dart';
import 'financeiro.dart' show entregarArquivo;

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

String _data(Object? v) {
  final d = dataDe(v);
  return d == null ? '—' : br(d.toIso8601String());
}

String _reais(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

bool _dono(Map<String, dynamic> c) => (c['papel'] ?? 'dono') == 'dono';

/// Sem abrir o app há 15 dias ou mais.
bool _sumido(Map<String, dynamic> c) {
  final u = dataDe(c['ultimo_acesso']);
  return u != null && DateTime.now().difference(u).inDays >= 15;
}

/// Com 90% ou mais do limite de animais do plano.
bool _pertoDoLimite(Map<String, dynamic> c) =>
    _dono(c) && planosPagos.contains(c['plano']) && PlanoEito.de(c['plano']).situacao((c['animais'] as num?)?.toInt() ?? 0) != 'ok';

/// Teste que termina em até 3 dias ou já venceu.
bool _testeNoFim(Map<String, dynamic> c) {
  if ((c['plano'] ?? 'Teste') != 'Teste' || c['status'] == 'suspensa') return false;
  final ate = dataDe(c['teste_ate']);
  return ate != null && ate.difference(DateTime.now()).inDays <= 3;
}

/// Plano pago com vencimento que já passou (pagamento atrasado).
bool _atrasado(Map<String, dynamic> c) {
  final ate = dataDe(c['plano_ate']);
  return planosPagos.contains(c['plano']) && c['status'] != 'suspensa' && ate != null && ate.isBefore(DateTime.now());
}

/// Total pago por conta (uid → R\$).
Map<String, double> _pagoPorConta(_Docs pagamentos) {
  final m = <String, double>{};
  for (final p in pagamentos) {
    final uid = '${p.data()['uid']}';
    m[uid] = (m[uid] ?? 0) + ((p.data()['valor'] as num?)?.toDouble() ?? 0);
  }
  return m;
}

Future<void> _abrir(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Abre o WhatsApp com a mensagem que combina com a situação da conta.
Future<void> _whatsCobranca(Map<String, dynamic> c) async {
  final fone = telefoneWhats('${c['telefone'] ?? ''}');
  if (fone == null) return;
  final nome = '${c['nome'] ?? ''}';
  final texto = _testeNoFim(c) ? textoCobrancaTeste(nome, dataDe(c['teste_ate'])) : textoSumido(nome);
  await _abrir('https://wa.me/$fone?text=${Uri.encodeComponent(texto)}');
}

/// Painel do criador do Eito: clientes, chamados e comunicados.
class CriadorPage extends StatelessWidget {
  const CriadorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Só o criador e os administradores (admins/{uid}) entram; as regras do Firestore também barram.
    return FutureBuilder<bool>(
      future: Indicacoes.souAdmin(),
      builder: (context, s) => switch (s.data) {
        true => _painel(context),
        false => Scaffold(
            appBar: AppBar(title: const Text('Painel do criador')),
            body: const Vazio('Área só do criador e dos administradores do Eito.', icone: Icons.lock_outline),
          ),
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    );
  }

  Widget _painel(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel do criador'),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Guia: ativar, suspender e excluir usuário',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _GuiaUsuarios())),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.local_fire_department_outlined),
              tooltip: 'Abrir no Firebase',
              onSelected: _abrir,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'https://console.firebase.google.com/project/caderneta-rebanho/firestore/databases/-default-/data/~2Fcontas',
                    child: Text('Cadastros das contas (Firestore)')),
                PopupMenuItem(value: linkFirebaseLogins, child: Text('Logins (Authentication)')),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Visão geral'),
              Tab(text: 'Clientes'),
              Tab(text: 'Saúde e uso'),
              Tab(text: 'Indicações'),
              Tab(text: 'Chamados'),
              Tab(text: 'Comunicados'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Plataforma.contas.snapshots(),
          builder: (context, s) {
            if (s.hasError) {
              return Vazio(
                  'Sem acesso às contas (${s.error}).\nConfira se as regras novas do Firestore foram publicadas '
                  'e se o seu e-mail está confirmado.',
                  icone: Icons.lock_outline);
            }
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final contas = s.data!.docs;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: PainelCriador.pagamentos.snapshots(),
              builder: (context, p) {
                final pagamentos = p.data?.docs ?? const [];
                return TabBarView(children: [
                  _VisaoGeral(contas: contas, pagamentos: pagamentos),
                  _Clientes(contas: contas, pagamentos: pagamentos),
                  SaudeEUso(contas: contas, itemCliente: (d) => _ItemCliente(d: d), telasDoMenu: [for (final i in itensMenu) i.$1]),
                  _RankingIndicacoes(contas: contas),
                  const _Chamados(),
                  const _Comunicados(),
                ]);
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------- Visão geral ----------

class _VisaoGeral extends StatelessWidget {
  const _VisaoGeral({required this.contas, required this.pagamentos});
  final _Docs contas;
  final _Docs pagamentos;

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    bool desde(Object? v, int dias) {
      final d = dataDe(v);
      return d != null && agora.difference(d).inDays < dias;
    }

    final donos = contas.where((c) => (c.data()['papel'] ?? 'dono') == 'dono').toList();
    final emTeste = donos.where((c) => (c.data()['plano'] ?? 'Teste') == 'Teste' && c.data()['status'] != 'suspensa');
    final terminando = emTeste.where((c) {
      final ate = dataDe(c.data()['teste_ate']);
      return ate != null && ate.isAfter(agora) && ate.difference(agora).inDays <= 3;
    }).toList();
    final vencidos = emTeste.where((c) {
      final ate = dataDe(c.data()['teste_ate']);
      return ate != null && ate.isBefore(agora);
    }).length;
    final pagantes = donos.where((c) => planosPagos.contains(c.data()['plano'])).length;
    final suspensas = contas.where((c) => c.data()['status'] == 'suspensa').length;
    final animais = donos.fold<int>(0, (s, c) => s + ((c.data()['animais'] as num?)?.toInt() ?? 0));

    // Receita: preço mensal de tabela de cada conta paga e ativa.
    final pagas = donos.where((c) => planosPagos.contains(c.data()['plano']) && c.data()['status'] != 'suspensa');
    final receita = pagas.fold<double>(0, (s, c) => s + precoMensal(c.data()['plano']));
    final porPlano = <String, int>{
      for (final p in ['Simples', 'Média', 'Plus', 'Cortesia'])
        p: donos.where((c) => nomePlano(c.data()['plano']) == p).length,
    };
    final vencendo = donos.where((c) {
      final ate = dataDe(c.data()['plano_ate']);
      return (c.data()['plano'] ?? 'Teste') != 'Teste' && ate != null && ate.difference(agora).inDays <= 7;
    }).toList()
      ..sort((a, b) => dataDe(a.data()['plano_ate'])!.compareTo(dataDe(b.data()['plano_ate'])!));
    final noMes = pagamentos.where((p) {
      final d = dataDe(p.data()['data']);
      return d != null && d.year == agora.year && d.month == agora.month;
    });
    final recebidoMes = noMes.fold<double>(0, (s, p) => s + ((p.data()['valor'] as num?)?.toDouble() ?? 0));
    final atrasados = donos.where((c) => _atrasado(c.data())).toList();
    // Conversão: dos produtores cujo teste já acabou, quantos pagam.
    final conversao = pagantes + vencidos == 0 ? null : pagantes * 100 / (pagantes + vencidos);

    // Cadastros por mês (últimos 6 meses).
    final meses = [for (var i = 5; i >= 0; i--) DateTime(agora.year, agora.month - i)];
    final porMes = [
      for (final m in meses)
        donos.where((c) {
          final d = dataDe(c.data()['criado_em']);
          return d != null && d.year == m.year && d.month == m.month;
        }).length,
    ];
    final maxMes = porMes.fold<int>(1, (a, b) => b > a ? b : a);
    const nomesMes = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

    Widget card(String t, Object v, IconData i, {Color? cor}) => SizedBox(
          width: 170,
          height: 104,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i, color: cor ?? Cores.oliva),
                const Spacer(),
                Text('$v', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );

    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        card('Contas de produtor', donos.length, Icons.agriculture_outlined),
        card('Logins de equipe', contas.length - donos.length, Icons.group_outlined),
        card('Novos em 7 dias', donos.where((c) => desde(c.data()['criado_em'], 7)).length, Icons.person_add_alt),
        card('Novos em 30 dias', donos.where((c) => desde(c.data()['criado_em'], 30)).length, Icons.calendar_month),
        card('Ativos em 7 dias', contas.where((c) => desde(c.data()['ultimo_acesso'], 7)).length, Icons.bolt),
        card('Em teste', emTeste.length, Icons.hourglass_bottom),
        card('Teste vencido', vencidos, Icons.timer_off_outlined, cor: Cores.alerta),
        card('Com plano pago', pagantes, Icons.workspace_premium_outlined, cor: Cores.sucesso),
        card('Suspensas', suspensas, Icons.block, cor: Cores.alerta),
        card('Animais cadastrados', animais, Icons.pets_outlined),
      ]),
      const Secao('Receita'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        card('Recebido neste mês', _reais(recebidoMes), Icons.price_check, cor: Cores.sucesso),
        card('Por mês (preço de tabela)', _reais(receita), Icons.payments_outlined, cor: Cores.sucesso),
        card('Por ano (12 meses)', _reais(receita * 12), Icons.savings_outlined, cor: Cores.sucesso),
        for (final e in porPlano.entries) card('Plano ${e.key}', e.value, Icons.workspace_premium_outlined),
        card('Teste que virou pago', conversao == null ? '—' : '${conversao.round()}%', Icons.trending_up),
        card('Pagamento atrasado', atrasados.length, Icons.money_off, cor: Cores.alerta),
      ]),
      const CancelamentosDoMes(),
      const Secao('Cadastros de produtores por mês'),
      SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < meses.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${porMes[i]}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Container(
                    height: 4 + 96 * porMes[i] / maxMes,
                    decoration: BoxDecoration(color: Cores.oliva, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Text(nomesMes[meses[i].month - 1]),
                ]),
              ),
            ),
        ]),
      ),
      if (atrasados.isNotEmpty) ...[
        const Secao('Pagamento atrasado'),
        for (final c in atrasados) _ItemCliente(d: c),
      ],
      const Secao('Planos vencendo em até 7 dias (ou vencidos)'),
      if (vencendo.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final c in vencendo) _ItemCliente(d: c),
      const Secao('Testes terminando em até 3 dias'),
      if (terminando.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final c in terminando) _ItemCliente(d: c),
    ]);
  }
}

// ---------- Clientes ----------

class _Clientes extends StatefulWidget {
  const _Clientes({required this.contas, required this.pagamentos});
  final _Docs contas;
  final _Docs pagamentos;

  @override
  State<_Clientes> createState() => _ClientesState();
}

class _ClientesState extends State<_Clientes> {
  String _busca = '';
  String _filtro = 'Todos';
  String _ordem = 'Mais recentes';
  final _marcados = <String>{};

  void _marcar(String uid) => setState(() => _marcados.contains(uid) ? _marcados.remove(uid) : _marcados.add(uid));

  Future<void> _estenderLote(List<QueryDocumentSnapshot<Map<String, dynamic>>> sel) async {
    final dias = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text('Estender o teste de ${sel.length} conta(s)'), children: [
        for (final d in [7, 14, 30])
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Text('+ $d dias')),
      ]),
    );
    if (dias == null) return;
    final lote = Plataforma.contas.firestore.batch();
    for (final c in sel) {
      final atual = dataDe(c.data()['teste_ate']);
      final base = atual == null || atual.isBefore(DateTime.now()) ? DateTime.now() : atual;
      lote.update(c.reference, {
        'plano': 'Teste',
        'plano_ate': null,
        'teste_ate': Timestamp.fromDate(base.add(Duration(days: dias))),
      });
      lote.set(PainelCriador.historico.doc(), {
        'uid': c.id,
        'acao': 'Teste estendido',
        'detalhe': '+$dias dias (em lote)',
        'por': FirebaseAuth.instance.currentUser?.email ?? '',
        'em': FieldValue.serverTimestamp(),
      });
    }
    try {
      await lote.commit();
      if (mounted) {
        avisar(context, 'Teste estendido em ${sel.length} conta(s).');
        setState(_marcados.clear);
      }
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _busca.trim().toLowerCase();
    final lista = widget.contas.where((c) {
      final d = c.data();
      if (b.isNotEmpty && !'${d['email']} ${d['nome']}'.toLowerCase().contains(b)) return false;
      return switch (_filtro) {
        'Produtores' => (d['papel'] ?? 'dono') == 'dono',
        'Em teste' => (d['plano'] ?? 'Teste') == 'Teste',
        'Pagantes' => planosPagos.contains(d['plano']),
        'Suspensas' => d['status'] == 'suspensa',
        'Teste no fim' => _testeNoFim(d),
        'Atrasados' => _atrasado(d),
        'Em risco' => _dono(d) && d['status'] != 'suspensa' && emRisco(d),
        'Sumidos há 15 dias' => _sumido(d),
        'Perto do limite' => _pertoDoLimite(d),
        'Boas-vindas' => d['boas_vindas_whats'] == 'pendente',
        _ => true,
      };
    }).toList();
    int porData(String campo, QueryDocumentSnapshot<Map<String, dynamic>> a, QueryDocumentSnapshot<Map<String, dynamic>> b) =>
        (dataDe(b.data()[campo]) ?? DateTime(1900)).compareTo(dataDe(a.data()[campo]) ?? DateTime(1900));
    lista.sort(switch (_ordem) {
      'Último acesso' => (a, b) => porData('ultimo_acesso', a, b),
      'Mais animais' => (a, b) => ((b.data()['animais'] as num?) ?? 0).compareTo((a.data()['animais'] as num?) ?? 0),
      _ => (a, b) => porData('criado_em', a, b),
    });
    final pago = _pagoPorConta(widget.pagamentos);
    final sel = widget.contas.where((c) => _marcados.contains(c.id)).toList();
    return Column(children: [
      if (sel.isNotEmpty)
        Material(
          color: Cores.oliva.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
              IconButton(icon: const Icon(Icons.close), tooltip: 'Limpar seleção', onPressed: () => setState(_marcados.clear)),
              Text('${sel.length} marcada(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextButton.icon(
                icon: const Icon(Icons.more_time, size: 18),
                label: const Text('Estender teste'),
                onPressed: () => _estenderLote(sel),
              ),
              TextButton.icon(
                icon: const Icon(Icons.chat, size: 18, color: Color(0xFF25D366)),
                label: const Text('WhatsApp'),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => WhatsEmLote(contas: [for (final c in sel) c.data()]))),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('E-mails'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sel.map((c) => '${c.data()['email']}').join('; ')));
                  avisar(context, 'E-mails copiados.');
                },
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por e-mail ou nome'),
          onChanged: (v) => setState(() => _busca = v),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          for (final f in [
            'Todos',
            'Produtores',
            'Em teste',
            'Teste no fim',
            'Pagantes',
            'Atrasados',
            'Em risco',
            'Perto do limite',
            'Sumidos há 15 dias',
            'Suspensas',
            'Boas-vindas',
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(f), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('${lista.length} conta(s)'),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Ordenar',
            initialValue: _ordem,
            onSelected: (v) => setState(() => _ordem = v),
            itemBuilder: (_) => [
              for (final o in ['Mais recentes', 'Último acesso', 'Mais animais']) PopupMenuItem(value: o, child: Text(o)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.sort, size: 18), Text(' $_ordem')]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Exportar planilha',
            onPressed: () => entregarArquivo(
              context,
              'clientes-eito.csv',
              csv(
                ['E-mail', 'Nome', 'Telefone', 'Estado', 'Tipo', 'Plano', 'Situação', 'Animais', 'Propriedades', 'Saúde (0-100)',
                  'Total pago (R\$)', 'Cadastro', 'Último acesso'],
                [
                  for (final c in lista)
                    [
                      c.data()['email'],
                      c.data()['nome'],
                      c.data()['telefone'],
                      ufDaConta(c.data()),
                      _dono(c.data()) ? 'Produtor' : 'Equipe (${c.data()['papel']})',
                      nomePlano(c.data()['plano']),
                      situacaoConta(c.data()),
                      c.data()['animais'] ?? 0,
                      c.data()['propriedades'] ?? 0,
                      saudeConta(c.data()),
                      pago[c.id] ?? 0,
                      _data(c.data()['criado_em']),
                      _data(c.data()['ultimo_acesso']),
                    ],
                ],
              ),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar e-mails'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lista.map((c) => '${c.data()['email']}').join('; ')));
              avisar(context, 'E-mails copiados.');
            },
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          for (final c in lista)
            _ItemCliente(
              d: c,
              marcado: _marcados.contains(c.id),
              aoMarcar: () => _marcar(c.id),
              selecionando: _marcados.isNotEmpty,
            ),
        ]),
      ),
    ]);
  }
}

class _ItemCliente extends StatelessWidget {
  const _ItemCliente({required this.d, this.marcado = false, this.aoMarcar, this.selecionando = false});
  final QueryDocumentSnapshot<Map<String, dynamic>> d;

  /// Seleção para as ações em lote (segurar marca; com algo marcado, tocar marca).
  final bool marcado, selecionando;
  final VoidCallback? aoMarcar;

  @override
  Widget build(BuildContext context) {
    final c = d.data();
    final suspensa = c['status'] == 'suspensa';
    final equipe = (c['papel'] ?? 'dono') != 'dono';
    return ListTile(
      selected: marcado,
      leading: CircleAvatar(
        backgroundColor: marcado ? Cores.laranja : (suspensa ? Cores.alerta : (equipe ? Cores.azul : Cores.oliva)),
        child: Icon(marcado ? Icons.check : (equipe ? Icons.badge_outlined : Icons.agriculture_outlined), color: Colors.white),
      ),
      title: Text('${c['email'] ?? d.id}'),
      subtitle: Text([
        if (equipe) 'Equipe (${c['papel']})' else situacaoConta(c),
        '${c['animais'] ?? 0} animais · último acesso ${_data(c['ultimo_acesso'])}'
            '${equipe ? '' : ' · saúde ${saudeConta(c)}'}'
            '${c['boas_vindas_whats'] == 'pendente' ? ' · boas-vindas no WhatsApp pendente' : ''}',
      ].join('\n')),
      isThreeLine: true,
      trailing: !equipe && (_testeNoFim(c) || _sumido(c)) && telefoneWhats('${c['telefone'] ?? ''}') != null
          ? IconButton(
              icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
              tooltip: _testeNoFim(c) ? 'Cobrar pelo WhatsApp' : 'Chamar de volta pelo WhatsApp',
              onPressed: () => _whatsCobranca(c),
            )
          : null,
      onLongPress: aoMarcar,
      onTap: selecionando && aoMarcar != null
          ? aoMarcar
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FichaCliente(uid: d.id))),
    );
  }
}

class _FichaCliente extends StatefulWidget {
  const _FichaCliente({required this.uid});
  final String uid;

  @override
  State<_FichaCliente> createState() => _FichaClienteState();
}

class _FichaClienteState extends State<_FichaCliente> {
  DocumentReference<Map<String, dynamic>> get _ref => Plataforma.contas.doc(widget.uid);
  late final _indicacao = Plataforma.contas.firestore.collection('usuarios').doc(widget.uid).get();

  Future<void> _salvar(Map<String, dynamic> v, String msg, {String? acao, String detalhe = '', String? motivo}) async {
    try {
      await _ref.update(v);
      if (acao != null) await PainelCriador.anotar(widget.uid, acao, detalhe: detalhe, motivo: motivo);
      if (mounted) avisar(context, msg);
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  Future<void> _estenderTeste(Map<String, dynamic> c) async {
    final dias = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Estender o teste'), children: [
        for (final d in [7, 14, 30])
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Text('+ $d dias')),
      ]),
    );
    if (dias == null) return;
    final atual = dataDe(c['teste_ate']);
    final base = atual == null || atual.isBefore(DateTime.now()) ? DateTime.now() : atual;
    await _salvar({
      'plano': 'Teste',
      'plano_ate': null,
      'teste_ate': Timestamp.fromDate(base.add(Duration(days: dias))),
    }, 'Teste estendido por $dias dias.', acao: 'Teste estendido', detalhe: '+$dias dias');
  }

  Future<void> _concederPlano(Map<String, dynamic> c) async {
    var plano = planos.contains(c['plano']) && c['plano'] != 'Teste' ? '${c['plano']}' : 'Simples';
    String? fim = dataDe(c['plano_ate'])?.toIso8601String().substring(0, 10);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Conceder plano'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            escolha('Plano', plano, planos.where((p) => p != 'Teste').toList(), (v) => set(() => plano = v ?? plano)),
            gap,
            DateField(label: 'Vale até (vazio = sem fim)', value: fim, onChanged: (v) => set(() => fim = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Conceder')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final f = fim == null ? null : DateTime.tryParse(fim!);
    await _salvar({
      'plano': plano,
      'plano_ate': f == null ? null : Timestamp.fromDate(f),
      'plano_concedido_em': FieldValue.serverTimestamp(),
    }, 'Plano $plano concedido.', acao: 'Plano concedido', detalhe: '$plano${f == null ? ', sem fim' : ' até ${br(fim)}'}');
  }

  Future<void> _excluir(Map<String, dynamic> c) async {
    final ok = await confirmar(
        context,
        'Excluir o cadastro?',
        'Apaga ${c['email']} da lista de clientes e as anotações internas. '
            'O login e os dados da fazenda ficam no Firebase; veja o guia para apagar tudo. '
            'Se a pessoa entrar de novo, a conta volta como teste novo.',
        ok: 'Excluir');
    if (!ok) return;
    try {
      await PainelCriador.anotar(widget.uid, 'Cadastro excluído', detalhe: '${c['email'] ?? ''}');
      await Plataforma.notas.doc(widget.uid).delete();
      await _ref.delete();
      if (mounted) {
        avisar(context, 'Cadastro excluído.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível excluir: $e');
    }
  }

  /// Pergunta o motivo (cancelamento, suspensão). null = desistiu.
  Future<String?> _pedirMotivo(String titulo) async {
    const motivos = ['Preço', 'Não usou o app', 'Faltou alguma função', 'Foi para outro app', 'Parou a atividade', 'Falta de pagamento', 'Outro'];
    var motivo = motivos.first;
    final obs = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(titulo),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            escolha('Motivo', motivo, motivos, (v) => set(() => motivo = v ?? motivo)),
            gap,
            campoTexto(obs, 'Detalhe (opcional)', linhas: 2),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    final t = obs.text.trim();
    obs.dispose();
    if (ok != true) return null;
    return t.isEmpty ? motivo : '$motivo: $t';
  }

  Future<void> _registrarPagamento(Map<String, dynamic> c, int desconto) async {
    var plano = planosPagos.contains(c['plano']) ? nomePlano(c['plano']) : 'Simples';
    var periodo = 'mensal';
    var forma = 'Pix';
    String? data = hojeIso();
    final valor = TextEditingController(text: valorSugerido(plano, periodo, desconto: desconto).toStringAsFixed(2).replaceAll('.', ','));
    void sugerir() => valor.text = valorSugerido(plano, periodo, desconto: desconto).toStringAsFixed(2).replaceAll('.', ',');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Registrar pagamento'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              escolha('Plano', plano, const ['Simples', 'Média', 'Plus'], (v) => set(() {
                    plano = v ?? plano;
                    sugerir();
                  })),
              gap,
              escolha('Período', periodo, const ['mensal', 'anual'], (v) => set(() {
                    periodo = v ?? periodo;
                    sugerir();
                  })),
              gap,
              campoTexto(valor, desconto > 0 ? 'Valor (R\$, já com $desconto% da indicação)' : 'Valor (R\$)', numero: true),
              gap,
              escolha('Forma', forma, const ['Pix', 'Boleto', 'Cartão', 'Dinheiro', 'Outra'], (v) => set(() => forma = v ?? forma)),
              gap,
              DateField(label: 'Pago em', value: data, onChanged: (v) => set(() => data = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    final v = lerNumero(valor.text)?.toDouble() ?? 0;
    valor.dispose();
    if (ok != true) return;
    final pagoEm = DateTime.tryParse(data ?? '') ?? DateTime.now();
    final vence = vencimentoAposPagamento(dataDe(c['plano_ate']), DateTime.now(), periodo);
    try {
      await PainelCriador.pagamentos.add({
        'uid': widget.uid,
        'email': c['email'],
        'plano': plano,
        'periodo': periodo,
        'valor': v,
        'forma': forma,
        'data': Timestamp.fromDate(pagoEm),
        'vale_ate': Timestamp.fromDate(vence),
        'criado_em': FieldValue.serverTimestamp(),
      });
      await _salvar({'plano': plano, 'plano_ate': Timestamp.fromDate(vence), 'status': 'ativa'},
          'Pagamento registrado. Plano vale até ${br(vence.toIso8601String())}.',
          acao: 'Pagamento', detalhe: '${_reais(v)} · $plano $periodo · $forma');
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível registrar: $e');
    }
  }

  Future<void> _redefinirSenha(String email) async {
    if (email.isEmpty) return avisar(context, 'Conta sem e-mail.');
    if (!await confirmar(context, 'Redefinir a senha?', 'Enviar o e-mail de redefinição para $email.', ok: 'Enviar')) {
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) avisar(context, 'E-mail de redefinição enviado.');
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível enviar: $e');
    }
  }

  Future<void> _corrigirNome(String atual) async {
    final t = TextEditingController(text: atual);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome do cadastro'),
        content: campoTexto(t, 'Nome', foco: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    final nome = t.text.trim();
    t.dispose();
    if (ok == true) await _salvar({'nome': nome}, 'Nome atualizado.', acao: 'Nome corrigido', detalhe: nome);
  }

  Future<void> _notas(String atual) async {
    final t = TextEditingController(text: atual);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anotações internas'),
        content: SizedBox(width: 480, child: campoTexto(t, 'Só você vê', linhas: 6, foco: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    final texto = t.text;
    t.dispose();
    if (ok != true) return;
    try {
      await Plataforma.notas.doc(widget.uid).set({'texto': texto, 'em': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, s) {
        final c = s.data?.data();
        return Scaffold(
          appBar: AppBar(title: Text('${c?['email'] ?? 'Cliente'}')),
          body: c == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Column(children: [
                      Info('E-mail', '${c['email'] ?? ''}'),
                      if ('${c['nome'] ?? ''}'.isNotEmpty) Info('Nome', '${c['nome']}'),
                      if ('${c['telefone'] ?? ''}'.isNotEmpty) Info('Telefone', '${c['telefone']}'),
                      Info('Tipo', (c['papel'] ?? 'dono') == 'dono' ? 'Produtor (dono)' : 'Equipe · ${c['papel']}'),
                      Info('Situação', situacaoConta(c)),
                      Info('Cadastro', _data(c['criado_em'])),
                      Info('Último acesso', _data(c['ultimo_acesso'])),
                      Info('Animais ativos', '${c['animais'] ?? 0}'),
                      Info('Propriedades', '${c['propriedades'] ?? 0}'),
                      if (ufDaConta(c) case final uf?) Info('Estado', uf),
                      Info('Saúde da conta', '${saudeConta(c)} de 100${emRisco(c) ? ' · em risco' : ''}'),
                      if ((c['aparelhos'] as List?)?.length case final n? when n > 0)
                        Info('Aparelhos usados', '$n${n >= limiteAparelhos ? ' · atenção' : ''}'),
                      if (dataDe(c['criado_em']) case final desde?)
                        Info('Cliente há', '${(DateTime.now().difference(desde).inDays / 30).floor()} mês(es)'),
                    ]),
                  ),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _indicacao,
                    builder: (context, u) {
                      final i = u.data?.data();
                      final desconto = (i?['desconto'] as num?)?.toInt() ?? 0;
                      return Column(children: [
                        if (i != null && '${i['indicacao'] ?? ''}'.isNotEmpty)
                          ListTile(
                            leading: const Icon(Icons.card_giftcard_outlined, color: Cores.oliva),
                            title: Text('Indicação: ${i['indicacao']}'),
                            subtitle: Text('${i['indicacao_tipo'] ?? ''} · desconto de $desconto%'),
                          ),
                        if ((c['papel'] ?? 'dono') == 'dono')
                          ListTile(
                            leading: const Icon(Icons.price_check, color: Cores.sucesso),
                            title: const Text('Registrar pagamento'),
                            subtitle: const Text('Renova o plano por 1 mês ou 1 ano'),
                            onTap: () => _registrarPagamento(c, desconto),
                          ),
                      ]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined, color: Cores.azul),
                    title: const Text('Ver a fazenda como o cliente (só leitura)'),
                    subtitle: const Text('Rebanho, lotes, pesagens e o resto, sem poder alterar'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => FazendaDoCliente(uid: '${c['dono'] ?? widget.uid}', email: '${c['email'] ?? ''}'))),
                  ),
                  if ((c['papel'] ?? 'dono') == 'dono') ...[
                    ListTile(
                      leading: const Icon(Icons.more_time),
                      title: const Text('Estender o teste'),
                      onTap: () => _estenderTeste(c),
                    ),
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Conceder plano (cortesia ou contrato)'),
                      onTap: () => _concederPlano(c),
                    ),
                    if ((c['plano'] ?? 'Teste') != 'Teste')
                      ListTile(
                        leading: const Icon(Icons.undo),
                        title: const Text('Tirar o plano (volta para teste)'),
                        onTap: () async {
                          final motivo = await _pedirMotivo('Por que o plano vai sair?');
                          if (motivo == null) return;
                          await _salvar({'plano': 'Teste', 'plano_ate': null}, 'Plano retirado.',
                              acao: 'Cancelamento', detalhe: nomePlano(c['plano']), motivo: motivo);
                        },
                      ),
                  ],
                  ListTile(
                    leading: Icon(c['status'] == 'suspensa' ? Icons.lock_open : Icons.block,
                        color: c['status'] == 'suspensa' ? Cores.sucesso : Cores.alerta),
                    title: Text(c['status'] == 'suspensa' ? 'Reativar a conta' : 'Suspender a conta'),
                    subtitle: const Text('Suspensa, a pessoa não consegue abrir os dados'),
                    onTap: () async {
                      final suspender = c['status'] != 'suspensa';
                      if (suspender) {
                        final motivo = await _pedirMotivo('Suspender ${c['email']}?');
                        if (motivo == null) return;
                        await _salvar({'status': 'suspensa'}, 'Conta suspensa.',
                            acao: planosPagos.contains(c['plano']) ? 'Cancelamento' : 'Conta suspensa',
                            detalhe: 'suspensa', motivo: motivo);
                      } else if (await confirmar(context, 'Reativar a conta?', '${c['email']}', ok: 'Reativar')) {
                        await _salvar({'status': 'ativa'}, 'Conta reativada.', acao: 'Conta reativada');
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Corrigir nome do cadastro'),
                    subtitle: Text('${c['nome'] ?? ''}'.isEmpty ? 'Sem nome' : '${c['nome']}'),
                    onTap: () => _corrigirNome('${c['nome'] ?? ''}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_reset),
                    title: const Text('Enviar e-mail para redefinir a senha'),
                    subtitle: const Text('A pessoa cria a nova senha pelo link recebido'),
                    onTap: () => _redefinirSenha('${c['email'] ?? ''}'),
                  ),
                  if (telefoneWhats('${c['telefone'] ?? ''}') case final fone?)
                    ListTile(
                      leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
                      title: const Text('Enviar boas-vindas pelo WhatsApp'),
                      subtitle: Text(c['boas_vindas_whats'] == 'pendente'
                          ? 'Ainda não enviada'
                          : c['boas_vindas_whats'] == 'enviada'
                              ? 'Já enviada'
                              : 'Mensagem de abertura da conta'),
                      onTap: () async {
                        final texto = Uri.encodeComponent(textoBoasVindas('${c['nome'] ?? ''}'));
                        await launchUrl(Uri.parse('https://wa.me/$fone?text=$texto'), mode: LaunchMode.externalApplication);
                        await _salvar({'boas_vindas_whats': 'enviada'}, 'Marcada como enviada.');
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.local_fire_department_outlined, color: Colors.orange),
                    title: const Text('Abrir o cadastro no Firebase'),
                    subtitle: const Text('Edita os campos da conta direto no console'),
                    onTap: () => _abrir(linkFirebaseConta(widget.uid)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Ver o login no Firebase'),
                    subtitle: const Text('Copia o e-mail e abre a lista de logins para buscar'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '${c['email'] ?? ''}'));
                      _abrir(linkFirebaseLogins);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copiar e-mail'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '${c['email'] ?? ''}'));
                      avisar(context, 'E-mail copiado.');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Guia: ativar, suspender e excluir'),
                    subtitle: const Text('Passo a passo, com os links desta conta no Firebase'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _GuiaUsuarios(uid: widget.uid))),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Cores.alerta),
                    title: const Text('Excluir o usuário'),
                    subtitle: const Text('Tira o cadastro da lista (o login apaga no Firebase, veja o guia)'),
                    onTap: () => _excluir(c),
                  ),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: Plataforma.notas.doc(widget.uid).snapshots(),
                    builder: (context, n) {
                      final texto = '${n.data?.data()?['texto'] ?? ''}';
                      return ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: const Text('Anotações internas'),
                        subtitle: Text(texto.isEmpty ? 'Nenhuma' : texto),
                        onTap: () => _notas(texto),
                      );
                    },
                  ),
                  PagamentosDaConta(uid: widget.uid),
                  HistoricoDaConta(uid: widget.uid),
                  const Secao('Chamados deste cliente'),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: Plataforma.chamados.where('uid', isEqualTo: widget.uid).snapshots(),
                    builder: (context, q) {
                      final docs = q.data?.docs ?? const [];
                      if (docs.isEmpty) return const ListTile(title: Text('Nenhum.'));
                      return Column(children: [for (final d in docs) ItemChamado(d: d, equipe: true)]);
                    },
                  ),
                ]),
        );
      },
    );
  }
}

// ---------- Guia de usuários ----------

/// Passo a passo para ativar, suspender (desativar) e excluir um usuário.
class _GuiaUsuarios extends StatelessWidget {
  const _GuiaUsuarios({this.uid});

  /// Conta aberta na ficha (mostra os links direto para ela).
  final String? uid;

  @override
  Widget build(BuildContext context) {
    Widget passo(String n, String t) => ListTile(
          dense: true,
          leading: CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 12))),
          title: Text(t),
        );
    Widget link(String t, String url) => ListTile(
          leading: const Icon(Icons.open_in_new, color: Colors.orange),
          title: Text(t),
          onTap: () => _abrir(url),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Guia de usuários')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const Secao('Ativar (liberar o uso)'),
        passo('1', 'A conta nasce sozinha quando a pessoa se cadastra no app, já em teste de 14 dias.'),
        passo('2', 'Em Clientes, abra a ficha. Para dar mais tempo, use "Estender o teste".'),
        passo('3', 'Para liberar de vez, use "Conceder plano" e escolha Simples, Média, Plus ou Cortesia, com ou sem data de fim.'),
        passo('4', 'Se a conta estava suspensa, toque em "Reativar a conta". Vale na hora, no próximo acesso.'),
        const Secao('Desativar (suspender)'),
        passo('1', 'Abra a ficha e toque em "Suspender a conta". A pessoa não abre mais os dados; nada é apagado.'),
        passo('2', 'Suspender o dono trava também a equipe dele (gerente, peão, veterinário...).'),
        passo('3', 'Para tirar só uma pessoa da equipe, peça ao dono para removê-la em Equipe, ou suspenda o login dela.'),
        passo('4', 'Para voltar, toque em "Reativar a conta".'),
        const Secao('Excluir (apagar de vez)'),
        passo('1', 'Suspenda a conta primeiro, para ninguém lançar nada enquanto você apaga.'),
        passo('2', 'Se quiser, exporte a lista de clientes ou peça à pessoa um backup da fazenda antes.'),
        passo('3', 'No Firebase, em Authentication, busque o e-mail e apague o login (menu ⋮ > Excluir conta).'),
        passo('4', 'No Firebase, em Firestore, apague o documento usuarios/{uid} com as subcoleções (os dados da fazenda).'),
        passo('5', 'Por último, na ficha, toque em "Excluir o usuário" para tirar o cadastro da lista.'),
        passo('!', 'Excluir não tem volta. Se a pessoa se cadastrar de novo, começa do zero, em teste.'),
        const Secao('Atalhos no Firebase'),
        link('Logins (Authentication)', linkFirebaseLogins),
        if (uid != null) ...[
          link('Cadastro desta conta (contas)', linkFirebaseConta(uid!)),
          link('Dados da fazenda desta conta (usuarios)', linkFirebaseDados(uid!)),
        ] else
          link('Cadastros das contas (Firestore)',
              'https://console.firebase.google.com/project/caderneta-rebanho/firestore/databases/-default-/data/~2Fcontas'),
      ]),
    );
  }
}

// ---------- Indicações ----------

class _RankingIndicacoes extends StatefulWidget {
  const _RankingIndicacoes({required this.contas});
  final _Docs contas;

  @override
  State<_RankingIndicacoes> createState() => _RankingIndicacoesState();
}

class _RankingIndicacoesState extends State<_RankingIndicacoes> {
  late Future<(List<Indicacao>, Map<String, String>)> _dados = _carregar();

  Future<(List<Indicacao>, Map<String, String>)> _carregar() async =>
      (await Indicacoes.todas(), await Indicacoes.codigoPorConta());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Indicacao>, Map<String, String>)>(
      future: _dados,
      builder: (context, s) {
        if (s.hasError) return Vazio('Não foi possível ler as indicações (${s.error}).', icone: Icons.error_outline);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final (codigos, usados) = s.data!;
        final contaPorUid = {for (final c in widget.contas) c.id: c.data()};
        final linhas = <String, ({String nome, int cadastros, int pagantes})>{
          for (final i in codigos) i.codigo: (nome: '${i.nome} · ${i.tipoNome}', cadastros: 0, pagantes: 0),
        };
        for (final e in usados.entries) {
          final l = linhas[e.value] ?? (nome: 'Código apagado', cadastros: 0, pagantes: 0);
          final paga = planosPagos.contains(contaPorUid[e.key]?['plano']);
          linhas[e.value] = (nome: l.nome, cadastros: l.cadastros + 1, pagantes: l.pagantes + (paga ? 1 : 0));
        }
        final ranking = linhas.entries.toList()
          ..sort((a, b) {
            final p = b.value.pagantes.compareTo(a.value.pagantes);
            return p != 0 ? p : b.value.cadastros.compareTo(a.value.cadastros);
          });
        if (ranking.isEmpty) return const Vazio('Nenhum código de indicação criado.', icone: Icons.card_giftcard_outlined);
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _dados = _carregar());
            await _dados;
          },
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            for (final (n, e) in ranking.indexed)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: n < 3 && e.value.cadastros > 0 ? Cores.oliva : Colors.grey,
                  child: Text('${n + 1}', style: const TextStyle(color: Colors.white)),
                ),
                title: Text(e.key),
                subtitle: Text(e.value.nome),
                trailing: Text('${e.value.cadastros} cadastro(s)\n${e.value.pagantes} pagante(s)', textAlign: TextAlign.end),
              ),
          ]),
        );
      },
    );
  }
}

// ---------- Chamados ----------

class _Chamados extends StatefulWidget {
  const _Chamados();

  @override
  State<_Chamados> createState() => _ChamadosState();
}

class _ChamadosState extends State<_Chamados> {
  String _filtro = 'Abertos';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Plataforma.chamados.snapshots(),
      builder: (context, s) {
        if (s.hasError) return Vazio('Erro: ${s.error}', icone: Icons.error_outline);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final medio = tempoMedioResposta(s.data!.docs.map((d) => d.data()));
        final docs = s.data!.docs.where((d) {
          final st = d.data()['status'];
          return switch (_filtro) {
            'Abertos' => st != 'fechado',
            'Fechados' => st == 'fechado',
            _ => true,
          };
        }).toList()
          ..sort((a, b) {
            final pa = a.data()['prioridade'] == 'alta' ? 0 : 1, pb = b.data()['prioridade'] == 'alta' ? 0 : 1;
            if (pa != pb) return pa.compareTo(pb);
            final la = a.data()['lido_equipe'] == false ? 0 : 1, lb = b.data()['lido_equipe'] == false ? 0 : 1;
            if (la != lb) return la.compareTo(lb);
            return (dataDe(b.data()['atualizado_em']) ?? DateTime(2100))
                .compareTo(dataDe(a.data()['atualizado_em']) ?? DateTime(2100));
          });
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              for (final f in ['Abertos', 'Fechados', 'Todos'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
                ),
              const Spacer(),
              if (medio != null)
                Tooltip(
                  message: 'Tempo médio até a primeira resposta',
                  child: Chip(avatar: const Icon(Icons.timer_outlined, size: 18), label: Text(textoDuracao(medio))),
                ),
            ]),
          ),
          Expanded(
            child: docs.isEmpty
                ? const Vazio('Nenhum chamado aqui.', icone: Icons.support_agent)
                : ListView(children: [for (final d in docs) ItemChamado(d: d, equipe: true)]),
          ),
        ]);
      },
    );
  }
}

// ---------- Comunicados ----------

class _Comunicados extends StatelessWidget {
  const _Comunicados();

  static const publicos = {
    'todos': 'Todos',
    'teste': 'Só quem está em teste',
    'pagantes': 'Só pagantes',
    'Simples': 'Só plano Simples',
    'Média': 'Só plano Média',
    'Plus': 'Só plano Plus',
    'uf': 'Só de um estado',
  };

  Future<void> _editar(BuildContext context, [QueryDocumentSnapshot<Map<String, dynamic>>? d]) async {
    final a = d?.data() ?? const <String, dynamic>{};
    final titulo = TextEditingController(text: '${a['titulo'] ?? ''}');
    final texto = TextEditingController(text: '${a['texto'] ?? ''}');
    var publico = '${a['publico'] ?? 'todos'}';
    var uf = '${a['uf'] ?? 'GO'}';
    var ativo = a['ativo'] != false;
    String? inicio = a['inicio'] as String?, fim = a['fim'] as String?;
    final op = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(d == null ? 'Novo comunicado' : 'Editar comunicado'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              campoTexto(titulo, 'Título', foco: true),
              gap,
              campoTexto(texto, 'Mensagem', linhas: 3),
              gap,
              escolha('Para quem', publicos[publico], publicos.values.toList(),
                  (v) => set(() => publico = publicos.entries.firstWhere((e) => e.value == v).key)),
              if (publico == 'uf') ...[
                gap,
                escolha('Estado', uf, ufs, (v) => set(() => uf = v ?? uf)),
              ],
              gap,
              DateField(label: 'Começa em (vazio = já)', value: inicio, onChanged: (v) => set(() => inicio = v)),
              gap,
              DateField(label: 'Termina em (vazio = sem fim)', value: fim, onChanged: (v) => set(() => fim = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar no app'),
                value: ativo,
                onChanged: (v) => set(() => ativo = v),
              ),
            ]),
          ),
          actions: [
            if (d != null) TextButton(onPressed: () => Navigator.pop(ctx, 'excluir'), child: const Text('Excluir')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'salvar'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = {
      'titulo': titulo.text.trim(),
      'texto': texto.text.trim(),
      'publico': publico,
      'uf': publico == 'uf' ? uf : null,
      'ativo': ativo,
      'inicio': inicio,
      'fim': fim,
      'atualizado_em': FieldValue.serverTimestamp(),
    };
    titulo.dispose();
    texto.dispose();
    try {
      if (op == 'excluir') {
        await d!.reference.delete();
      } else if (op == 'salvar') {
        if ('${v['titulo']}'.isEmpty && '${v['texto']}'.isEmpty) return;
        if (d == null) {
          await Plataforma.comunicados.add({...v, 'criado_em': FieldValue.serverTimestamp()});
        } else {
          await d.reference.update(v);
        }
      }
    } catch (e) {
      if (context.mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Novo comunicado'),
        onPressed: () => _editar(context),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Plataforma.comunicados.snapshots(),
        builder: (context, s) {
          if (s.hasError) return Vazio('Erro: ${s.error}', icone: Icons.error_outline);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = [...s.data!.docs]..sort((a, b) =>
              (dataDe(b.data()['criado_em']) ?? DateTime(2100)).compareTo(dataDe(a.data()['criado_em']) ?? DateTime(2100)));
          if (docs.isEmpty) {
            return const Vazio('Nenhum comunicado. Eles aparecem numa faixa no topo do app.', icone: Icons.campaign_outlined);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final d in docs)
              ListTile(
                leading: Icon(Icons.campaign_outlined, color: d.data()['ativo'] == true ? Cores.oliva : Colors.grey),
                title: Text('${d.data()['titulo'] ?? ''}'),
                subtitle: Text([
                  '${d.data()['texto'] ?? ''}',
                  '${publicos[d.data()['publico']] ?? 'Todos'}${d.data()['publico'] == 'uf' ? ' (${d.data()['uf']})' : ''}'
                      '${d.data()['ativo'] == true ? '' : ' · desligado'}'
                      '${d.data()['fim'] == null ? '' : ' · até ${br(d.data()['fim'])}'}',
                ].join('\n')),
                isThreeLine: true,
                onTap: () => _editar(context, d),
              ),
          ]);
        },
      ),
    );
  }
}
