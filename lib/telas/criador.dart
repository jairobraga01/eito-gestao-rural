import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/plataforma.dart';
import '../tema.dart';
import '../util/util.dart';
import 'ajuda.dart' show ItemChamado;

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

String _data(Object? v) {
  final d = dataDe(v);
  return d == null ? '—' : br(d.toIso8601String());
}

/// Painel do criador do Eito: clientes, chamados e comunicados.
class CriadorPage extends StatelessWidget {
  const CriadorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel do criador'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Visão geral'), Tab(text: 'Clientes'), Tab(text: 'Chamados'), Tab(text: 'Comunicados')],
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
            return TabBarView(children: [
              _VisaoGeral(contas: contas),
              _Clientes(contas: contas),
              const _Chamados(),
              const _Comunicados(),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------- Visão geral ----------

class _VisaoGeral extends StatelessWidget {
  const _VisaoGeral({required this.contas});
  final _Docs contas;

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
    final pagantes = donos.where((c) => ['Essencial', 'Profissional', 'Completa'].contains(c.data()['plano'])).length;
    final suspensas = contas.where((c) => c.data()['status'] == 'suspensa').length;
    final animais = donos.fold<int>(0, (s, c) => s + ((c.data()['animais'] as num?)?.toInt() ?? 0));

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
      const Secao('Testes terminando em até 3 dias'),
      if (terminando.isEmpty) const ListTile(title: Text('Nenhum.')),
      for (final c in terminando) _ItemCliente(d: c),
    ]);
  }
}

// ---------- Clientes ----------

class _Clientes extends StatefulWidget {
  const _Clientes({required this.contas});
  final _Docs contas;

  @override
  State<_Clientes> createState() => _ClientesState();
}

class _ClientesState extends State<_Clientes> {
  String _busca = '';
  String _filtro = 'Todos';

  @override
  Widget build(BuildContext context) {
    final b = _busca.trim().toLowerCase();
    final lista = widget.contas.where((c) {
      final d = c.data();
      if (b.isNotEmpty && !'${d['email']} ${d['nome']}'.toLowerCase().contains(b)) return false;
      return switch (_filtro) {
        'Produtores' => (d['papel'] ?? 'dono') == 'dono',
        'Em teste' => (d['plano'] ?? 'Teste') == 'Teste',
        'Pagantes' => ['Essencial', 'Profissional', 'Completa'].contains(d['plano']),
        'Suspensas' => d['status'] == 'suspensa',
        _ => true,
      };
    }).toList()
      ..sort((a, b) => (dataDe(b.data()['criado_em']) ?? DateTime(2100)).compareTo(dataDe(a.data()['criado_em']) ?? DateTime(2100)));
    return Column(children: [
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
          for (final f in ['Todos', 'Produtores', 'Em teste', 'Pagantes', 'Suspensas'])
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
          for (final c in lista) _ItemCliente(d: c),
        ]),
      ),
    ]);
  }
}

class _ItemCliente extends StatelessWidget {
  const _ItemCliente({required this.d});
  final QueryDocumentSnapshot<Map<String, dynamic>> d;

  @override
  Widget build(BuildContext context) {
    final c = d.data();
    final suspensa = c['status'] == 'suspensa';
    final equipe = (c['papel'] ?? 'dono') != 'dono';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: suspensa ? Cores.alerta : (equipe ? Cores.azul : Cores.oliva),
        child: Icon(equipe ? Icons.badge_outlined : Icons.agriculture_outlined, color: Colors.white),
      ),
      title: Text('${c['email'] ?? d.id}'),
      subtitle: Text([
        if (equipe) 'Equipe (${c['papel']})' else situacaoConta(c),
        '${c['animais'] ?? 0} animais · último acesso ${_data(c['ultimo_acesso'])}',
      ].join('\n')),
      isThreeLine: true,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FichaCliente(uid: d.id))),
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

  Future<void> _salvar(Map<String, dynamic> v, String msg) async {
    try {
      await _ref.update(v);
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
    }, 'Teste estendido por $dias dias.');
  }

  Future<void> _concederPlano(Map<String, dynamic> c) async {
    var plano = planos.contains(c['plano']) && c['plano'] != 'Teste' ? '${c['plano']}' : 'Essencial';
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
    }, 'Plano $plano concedido.');
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
                      Info('Tipo', (c['papel'] ?? 'dono') == 'dono' ? 'Produtor (dono)' : 'Equipe · ${c['papel']}'),
                      Info('Situação', situacaoConta(c)),
                      Info('Cadastro', _data(c['criado_em'])),
                      Info('Último acesso', _data(c['ultimo_acesso'])),
                      Info('Animais ativos', '${c['animais'] ?? 0}'),
                      Info('Propriedades', '${c['propriedades'] ?? 0}'),
                    ]),
                  ),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: Plataforma.contas.firestore.collection('usuarios').doc(widget.uid).get(),
                    builder: (context, u) {
                      final i = u.data?.data();
                      if (i == null || '${i['indicacao'] ?? ''}'.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        leading: const Icon(Icons.card_giftcard_outlined, color: Cores.oliva),
                        title: Text('Indicação: ${i['indicacao']}'),
                        subtitle: Text('${i['indicacao_tipo'] ?? ''} · desconto de ${i['desconto'] ?? 0}%'),
                      );
                    },
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
                        onTap: () => _salvar({'plano': 'Teste', 'plano_ate': null}, 'Plano retirado.'),
                      ),
                  ],
                  ListTile(
                    leading: Icon(c['status'] == 'suspensa' ? Icons.lock_open : Icons.block,
                        color: c['status'] == 'suspensa' ? Cores.sucesso : Cores.alerta),
                    title: Text(c['status'] == 'suspensa' ? 'Reativar a conta' : 'Suspender a conta'),
                    subtitle: const Text('Suspensa, a pessoa não consegue abrir os dados'),
                    onTap: () async {
                      final suspender = c['status'] != 'suspensa';
                      final ok = await confirmar(
                          context, suspender ? 'Suspender a conta?' : 'Reativar a conta?', '${c['email']}',
                          ok: suspender ? 'Suspender' : 'Reativar');
                      if (ok) {
                        await _salvar({'status': suspender ? 'suspensa' : 'ativa'},
                            suspender ? 'Conta suspensa.' : 'Conta reativada.');
                      }
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

  static const publicos = {'todos': 'Todos', 'teste': 'Só quem está em teste', 'pagantes': 'Só pagantes'};

  Future<void> _editar(BuildContext context, [QueryDocumentSnapshot<Map<String, dynamic>>? d]) async {
    final a = d?.data() ?? const <String, dynamic>{};
    final titulo = TextEditingController(text: '${a['titulo'] ?? ''}');
    final texto = TextEditingController(text: '${a['texto'] ?? ''}');
    var publico = '${a['publico'] ?? 'todos'}';
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
                  '${publicos[d.data()['publico']] ?? 'Todos'}'
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
