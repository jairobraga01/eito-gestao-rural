// Equipe e permissões, tarefas para a equipe e registro de quem lançou o quê.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/db.dart';
import '../dados/equipe.dart';
import '../dados/historico.dart';
import '../dados/planos.dart';
import '../dados/tarefas.dart';
import '../firebase_options.dart';
import '../tema.dart';
import '../util/util.dart';
import 'base.dart';
import 'conta.dart' show mensagemConta;

String _uidAtual() => FirebaseAuth.instance.currentUser?.uid ?? '';

/// Data e hora curtas (dd/mm hh:mm) de um texto ISO.
String _quando(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
}

// ---------------- Equipe (só o dono) ----------------

class EquipePage extends StatefulWidget {
  const EquipePage({super.key});

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage> {
  late Future<List<Membro>> _lista;
  bool _ocupado = false;

  String get _dono => _uidAtual();
  String get _donoNome {
    final u = FirebaseAuth.instance.currentUser;
    return u?.displayName ?? u?.email ?? '';
  }

  @override
  void initState() {
    super.initState();
    _lista = Equipe.membros(_dono);
  }

  void _recarregar() => setState(() => _lista = Equipe.membros(_dono));

  Future<void> _executar(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await acao();
    } on FirebaseAuthException catch (e) {
      if (mounted) avisar(context, mensagemConta(e));
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível concluir (precisa de internet): $e');
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        _recarregar();
      }
    }
  }

  /// Nome, e-mail (ou senha, no login de peão) e papel.
  Future<(String, String, String)?> _formulario({required bool peao}) {
    final nome = TextEditingController(), outro = TextEditingController();
    var papel = peao ? 'peao' : 'gerente';
    return showDialog<(String, String, String)>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(peao ? 'Criar login (peão ou outro papel)' : 'Convidar pelo e-mail'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              campoTexto(nome, 'Nome', foco: true),
              gap,
              TextField(
                controller: outro,
                keyboardType: peao ? TextInputType.text : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: peao ? 'Senha (mínimo 6 caracteres)' : 'E-mail da pessoa',
                  helperText: peao ? 'O usuário é criado a partir do nome.' : 'Ela cria a conta com este e-mail.',
                ),
              ),
              gap,
              escolha('Papel', papeis[papel], papeis.values.toList(),
                  (v) => set(() => papel = papeis.entries.firstWhere((e) => e.value == v).key)),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(descricaoPapel[papel]!, style: const TextStyle(color: Colors.black54)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(c, (nome.text.trim(), outro.text.trim(), papel)),
              child: Text(peao ? 'Criar' : 'Convidar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Mensagem quando o plano da fazenda não deixa pôr mais uma pessoa com [papel]; null se cabe.
  Future<String?> _semVaga(String papel, {Membro? trocando}) async {
    final p = planoAtual();
    final nome = papeis[papel] ?? papel;
    if (!p.permite(papel)) return 'O plano ${p.nome} não inclui $nome. Mude para um plano maior.';
    final todos = [for (final m in await _lista) if (m.email != trocando?.email) m];
    if (p.cabe(papel, Equipe.contagemPorPapel(todos))) return null;
    return 'O plano ${p.nome} permite ${p.maxPorPapel[papel]} $nome. Tire alguém ou mude de plano.';
  }

  Future<void> _convidar() async {
    final r = await _formulario(peao: false);
    if (r == null) return;
    final (nome, email, papel) = r;
    if (nome.isEmpty || !email.contains('@')) {
      if (mounted) avisar(context, 'Preencha o nome e um e-mail válido.');
      return;
    }
    final falta = await _semVaga(papel);
    if (falta != null) {
      if (mounted) avisar(context, falta);
      return;
    }
    await _executar(() async {
      await Equipe.convidar(dono: _dono, donoNome: _donoNome, email: email, nome: nome, papel: papel);
      if (mounted) {
        avisar(context, 'Convite feito. $nome cria a conta no Eito com $email, confirma o e-mail e entra.');
      }
    });
  }

  /// Cria o login (usuário e senha) sem deslogar o dono, numa segunda instância
  /// do Firebase. Devolve o usuário e o uid.
  Future<(String, String)> _novoLogin(String nome, String senha) async {
    final app = Firebase.apps.any((a) => a.name == 'cadastro')
        ? Firebase.app('cadastro')
        : await Firebase.initializeApp(name: 'cadastro', options: DefaultFirebaseOptions.currentPlatform);
    final auth = FirebaseAuth.instanceFor(app: app);
    String? usuario;
    UserCredential? cred;
    for (var i = 0; i < 5 && cred == null; i++) {
      usuario = usuarioPeao(nome);
      try {
        cred = await auth.createUserWithEmailAndPassword(email: emailDoLogin(usuario), password: senha);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
      }
    }
    if (cred?.user == null) throw 'não deu para criar o usuário, tente de novo';
    await cred!.user!.updateDisplayName(nome);
    await auth.signOut();
    return (usuario!, cred.user!.uid);
  }

  /// Senha nova para login de peão: o Firebase não deixa o dono trocar a senha
  /// de outra pessoa pelo app, então cria um login novo (mesmo nome e papel),
  /// passa para ele o que o login antigo lançou e desliga o antigo da fazenda.
  Future<void> _novaSenhaPeao(Membro m) async {
    final ctrl = TextEditingController();
    final senha = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nova senha para ${m.nome}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('O Eito cria um usuário novo com esta senha. O usuário antigo para de funcionar, '
              'e tudo o que ele lançou passa para o novo.'),
          gap,
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Senha nova (mínimo 6 caracteres)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Criar')),
        ],
      ),
    );
    if (senha == null || senha.isEmpty) return;
    if (senha.length < 6) {
      if (mounted) avisar(context, 'A senha precisa ter pelo menos 6 caracteres.');
      return;
    }
    String? usuario;
    await _executar(() async {
      final (u, uid) = await _novoLogin(m.nome, senha);
      await Equipe.remover(_dono, m);
      await Equipe.convidar(
        dono: _dono,
        donoNome: _donoNome,
        email: emailDoLogin(u),
        nome: m.nome,
        papel: m.papel,
        uid: uid,
        usuario: u,
      );
      if (m.uid != null) Db.transferirAutoria(m.uid!, uid, m.nome);
      usuario = u;
    });
    if (usuario == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Senha nova criada'),
        content: SelectableText('Passe para ${m.nome}:\n\nUsuário novo: $usuario\nSenha: a que você digitou'),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: 'Eito: usuário $usuario')),
            child: const Text('Copiar usuário'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Cria a conta do peão sem deslogar o dono (usa uma segunda instância do Firebase).
  Future<void> _criarPeao() async {
    final r = await _formulario(peao: true);
    if (r == null) return;
    final (nome, senha, papel) = r;
    if (nome.isEmpty || senha.length < 6) {
      if (mounted) avisar(context, 'Preencha o nome e uma senha com pelo menos 6 caracteres.');
      return;
    }
    final falta = await _semVaga(papel);
    if (falta != null) {
      if (mounted) avisar(context, falta);
      return;
    }
    await _executar(() async {
      final (usuario, uid) = await _novoLogin(nome, senha);
      await Equipe.convidar(
        dono: _dono,
        donoNome: _donoNome,
        email: emailDoLogin(usuario),
        nome: nome,
        papel: papel,
        uid: uid,
        usuario: usuario,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Login criado'),
          content: SelectableText('Passe para $nome:\n\nUsuário: $usuario\nSenha: a que você digitou\n\n'
              'Na tela de entrada do Eito, é só digitar o usuário no lugar do e-mail.'),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: 'Eito: usuário $usuario')),
              child: const Text('Copiar usuário'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
    });
  }

  Future<void> _opcoes(Membro m) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in papeis.entries)
            ListTile(
              leading: Icon(m.papel == p.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: Cores.oliva),
              title: Text(p.value),
              subtitle: Text(descricaoPapel[p.key]!),
              onTap: () => Navigator.pop(c, p.key),
            ),
          const Divider(),
          if (m.usuario != null && m.uid != null)
            ListTile(
              leading: const Icon(Icons.lock_reset, color: Cores.oliva),
              title: const Text('Senha nova (esqueceu a senha)'),
              subtitle: Text('Usuário atual: ${m.usuario}'),
              onTap: () => Navigator.pop(c, 'senha'),
            ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined, color: Cores.alerta),
            title: const Text('Tirar da equipe', style: TextStyle(color: Cores.alerta)),
            onTap: () => Navigator.pop(c, 'remover'),
          ),
        ]),
      ),
    );
    if (op == null || op == m.papel || !mounted) return;
    if (op == 'senha') {
      await _novaSenhaPeao(m);
    } else if (op == 'remover') {
      final ok = await confirmar(context, 'Tirar ${m.nome} da equipe?',
          'A pessoa perde o acesso aos dados desta fazenda na hora. O que ela lançou continua.',
          ok: 'Tirar');
      if (ok) await _executar(() => Equipe.remover(_dono, m));
    } else {
      final falta = await _semVaga(op, trocando: m);
      if (falta != null) {
        if (mounted) avisar(context, falta);
        return;
      }
      await _executar(() => Equipe.mudarPapel(_dono, m, op));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equipe e permissões')),
      body: AbsorbPointer(
        absorbing: _ocupado,
        child: FutureBuilder<List<Membro>>(
          future: _lista,
          builder: (context, s) {
            if (s.hasError) return Vazio('Precisa de internet para ver a equipe.\n${s.error}', icone: Icons.wifi_off);
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final lista = s.data!;
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (_ocupado) const LinearProgressIndicator(),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Cada pessoa entra com a própria conta e trabalha nos dados desta fazenda. '
                  'Tudo o que ela lançar fica marcado com o nome dela.',
                ),
              ),
              _CartaoPlano(lista),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _criarPeao,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Criar login (usuário e senha)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _convidar,
                    icon: const Icon(Icons.forward_to_inbox_outlined),
                    label: const Text('Convidar pelo e-mail'),
                  ),
                ]),
              ),
              Secao('Equipe (${lista.length})'),
              if (lista.isEmpty) const ListTile(title: Text('Ninguém na equipe ainda.')),
              for (final m in lista)
                ListTile(
                  leading: Icon(
                      switch (m.papel) {
                        'peao' => Icons.agriculture_outlined,
                        'veterinario' => Icons.medical_services_outlined,
                        'zootecnista' => Icons.science_outlined,
                        'contador' => Icons.calculate_outlined,
                        _ => Icons.manage_accounts_outlined,
                      },
                      color: Cores.oliva),
                  title: Text(m.nome.isEmpty ? m.email : m.nome),
                  subtitle: Text([
                    papeis[m.papel] ?? m.papel,
                    m.usuario != null ? 'usuário ${m.usuario}' : m.email,
                    if (m.pendente) 'ainda não entrou',
                  ].join(' · ')),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () => _opcoes(m),
                ),
              ListTile(
                leading: const Icon(Icons.history, color: Cores.oliva),
                title: const Text('Quem lançou o quê'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoricoPage())),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------- Tarefas ----------------

class TarefasPage extends StatefulWidget {
  const TarefasPage({super.key});

  @override
  State<TarefasPage> createState() => _TarefasPageState();
}

class _TarefasPageState extends State<TarefasPage> {
  bool _feitas = false;

  @override
  Widget build(BuildContext context) {
    final peao = Db.ehCampo;
    return Pagina(
      titulo: 'Tarefas',
      fab: peao
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              icon: const Icon(Icons.add_task),
              label: const Text('Nova tarefa'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TarefaFormPage())),
            ),
      corpo: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('A fazer'), icon: Icon(Icons.pending_actions)),
              ButtonSegment(value: true, label: Text('Feitas'), icon: Icon(Icons.task_alt)),
            ],
            selected: {_feitas},
            onSelectionChanged: (s) => setState(() => _feitas = s.first),
          ),
        ),
        Expanded(
          child: AoMudar<List<Reg>>(
            carregar: () async => tarefas(feitas: _feitas, paraUid: peao ? _uidAtual() : null),
            builder: (context, lista) {
              if (lista.isEmpty) {
                return Vazio(_feitas ? 'Nenhuma tarefa feita ainda.' : 'Nenhuma tarefa a fazer.',
                    icone: Icons.task_alt);
              }
              return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final t in lista)
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: t['feita'] == true,
                    onChanged: (v) => concluirTarefa(t['id'] as int, v ?? false),
                    title: Text(txt(t['titulo']),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tarefaAtrasada(t) ? Cores.alerta : null,
                        )),
                    subtitle: Text([
                      if (txt(t['obs']).isNotEmpty) txt(t['obs']),
                      txt(t['responsavel_nome']).isEmpty ? 'Qualquer um' : 'Para ${t['responsavel_nome']}',
                      if (t['prazo'] != null) '${tarefaAtrasada(t) ? 'Atrasada · ' : ''}até ${br(t['prazo'])}',
                      if (t['feita'] == true && t['feita_em'] != null)
                        'Feita ${_quando('${t['feita_em']}')}${txt(t['feita_nome']).isEmpty ? '' : ' por ${t['feita_nome']}'}',
                    ].join(' · ')),
                    secondary: peao
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => TarefaFormPage(tarefa: t))),
                          ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class TarefaFormPage extends StatefulWidget {
  const TarefaFormPage({super.key, this.tarefa});
  final Reg? tarefa;

  @override
  State<TarefaFormPage> createState() => _TarefaFormPageState();
}

class _TarefaFormPageState extends State<TarefaFormPage> {
  late final _titulo = TextEditingController(text: txt(widget.tarefa?['titulo']));
  late final _obs = TextEditingController(text: txt(widget.tarefa?['obs']));
  late String? _prazo = widget.tarefa?['prazo'] as String?;
  late String? _responsavel = widget.tarefa?['responsavel'] as String?;
  Map<String, String> _pessoas = {};

  @override
  void initState() {
    super.initState();
    final dono = Equipe.atual?.dono ?? _uidAtual();
    Equipe.nomes(dono).then((n) {
      if (mounted) setState(() => _pessoas = n);
    });
  }

  @override
  void dispose() {
    _titulo.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      avisar(context, 'Diga o que precisa ser feito.');
      return;
    }
    await salvarTarefa({
      'titulo': titulo,
      'obs': nulo(_obs.text),
      'prazo': _prazo,
      'responsavel': _responsavel,
      'responsavel_nome': _responsavel == null ? null : (_pessoas[_responsavel] ?? widget.tarefa?['responsavel_nome']),
    }, id: widget.tarefa?['id'] as int?);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir a tarefa?', txt(widget.tarefa!['titulo']), ok: 'Excluir')) return;
    await Db.excluir('tarefas', widget.tarefa!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pessoas = {..._pessoas};
    if (_responsavel != null && !pessoas.containsKey(_responsavel)) {
      pessoas[_responsavel!] = txt(widget.tarefa?['responsavel_nome']);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tarefa == null ? 'Nova tarefa' : 'Editar tarefa'),
        actions: [
          if (widget.tarefa != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        campoTexto(_titulo, 'O que fazer (ex.: consertar a cerca do piquete 3)', foco: widget.tarefa == null),
        gap,
        campoTexto(_obs, 'Detalhes', linhas: 3),
        gap,
        DropdownButtonFormField<String?>(
          key: ValueKey('resp|$_responsavel|${pessoas.length}'),
          initialValue: _responsavel,
          decoration: const InputDecoration(labelText: 'Quem faz'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Qualquer um da equipe')),
            for (final p in pessoas.entries) DropdownMenuItem<String?>(value: p.key, child: Text(p.value)),
          ],
          onChanged: (v) => setState(() => _responsavel = v),
        ),
        gap,
        DateField(label: 'Prazo', value: _prazo, onChanged: (v) => setState(() => _prazo = v)),
        const SizedBox(height: 24),
        BotaoSalvar(onPressed: _salvar),
      ]),
    );
  }
}

// ---------------- Quem lançou o quê ----------------

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key, this.doMenu = false});

  /// Aberta pelo menu lateral (com o menu e a faixa da propriedade).
  final bool doMenu;

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  String? _uid;

  @override
  Widget build(BuildContext context) {
    final corpo = AoMudar<List<Lancamento>>(
        carregar: () async => lancamentos(),
        builder: (context, todos) {
          final pessoas = <String, String>{for (final l in todos) l.quemUid: l.quem};
          final lista = _uid == null ? todos : todos.where((l) => l.quemUid == _uid).toList();
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String?>(
                key: ValueKey('quem|$_uid|${pessoas.length}'),
                initialValue: pessoas.containsKey(_uid) ? _uid : null,
                decoration: const InputDecoration(labelText: 'Pessoa'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                  for (final p in pessoas.entries)
                    DropdownMenuItem<String?>(value: p.key, child: Text(p.value.isEmpty ? '(sem nome)' : p.value)),
                ],
                onChanged: (v) => setState(() => _uid = v),
              ),
            ),
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nada registrado ainda. Os lançamentos passam a guardar quem lançou a partir desta versão.'),
              ),
            for (final l in lista)
              ListTile(
                dense: true,
                leading: Icon(l.alterou ? Icons.edit_note : Icons.add_circle_outline, color: Cores.oliva),
                title: Text('${l.oQue}${l.detalhe.isEmpty ? '' : ' · ${l.detalhe}'}'),
                subtitle: Text('${l.alterou ? 'Alterado' : 'Lançado'} por ${l.quem.isEmpty ? '?' : l.quem} · ${_quando(l.quando)}'),
              ),
          ]);
        },
      );
    if (widget.doMenu) return Pagina(titulo: 'Quem lançou o quê', corpo: corpo);
    return Scaffold(appBar: AppBar(title: const Text('Quem lançou o quê')), body: corpo);
  }
}


/// Plano da fazenda: preço, animais e pessoas usados em relação ao limite.
class _CartaoPlano extends StatelessWidget {
  const _CartaoPlano(this.equipe);
  final List<Membro> equipe;

  static String _limite(int? v) => v == null || v >= 99 ? 'sem limite' : '$v';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Object?>(
      valueListenable: Db.planoDaFazenda,
      builder: (context, _, __) {
        final p = planoAtual();
        final animais = animaisAtivos();
        final usados = Equipe.contagemPorPapel(equipe);
        final m = p.maxAnimais;
        final preco = p.mes.isEmpty ? 'Teste ou cortesia: tudo liberado' : 'R\$ ${p.mes} por mês ou R\$ ${p.ano} por ano';
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Plano ${p.nome}', style: Theme.of(context).textTheme.titleLarge),
              Text(preco),
              const SizedBox(height: 12),
              Text('Animais: $animais de ${_limite(m)}'),
              if (m != null) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: (animais / m).clamp(0, 1).toDouble()),
              ],
              const SizedBox(height: 12),
              const Text('Pessoas (além do dono)'),
              for (final e in p.maxPorPapel.entries)
                Text('${papeis[e.key] ?? e.key}: ${usados[e.key] ?? 0} de ${_limite(e.value)}'),
              const Divider(height: 24),
              const Text('Planos à venda'),
              for (final q in PlanoEito.todos)
                Text('${q.nome}: R\$ ${q.mes} por mês ou R\$ ${q.ano} por ano; ${q.resumoLimite}; '
                    '${q.maxPorPapel.entries.map((e) => '${e.value} ${papeis[e.key]!.toLowerCase()}').join(', ')}.'),
            ]),
          ),
        );
      },
    );
  }
}
