// Ficha rápida do Modo Curral: botões grandes para o que se faz no tronco.
// Tudo é gravado nos mesmos módulos do app (Pesagens, Sanidade, Reprodução,
// Rebanho, Vendas e saídas).
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/teclado_grande.dart';
import 'animais.dart';
import 'mover.dart';
import 'reproducao.dart';
import 'sanidade.dart' show itensSanidade, Segmentos;
import 'vendas.dart';

/// Abre a ficha rápida do animal com esse brinco (visual ou eletrônico).
/// Se não existir, oferece o cadastro já com o número preenchido.
Future<void> abrirPorCodigo(BuildContext context, String codigo) async {
  final animal = await Db.buscarPorCodigo(codigo);
  if (!context.mounted) return;
  if (animal != null) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FichaCurral(animalId: animal['id'] as int)));
    return;
  }
  final cadastrar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Brinco não cadastrado'),
      content: Text('Nenhum animal com o brinco $codigo.', style: const TextStyle(fontSize: 18)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('IGNORAR')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CADASTRAR')),
      ],
    ),
  );
  if (cadastrar == true && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalFormPage(codigoLido: codigo)));
  }
}

class _DadosFicha {
  _DadosFicha(this.a, this.pesagens, this.sanidade, this.servicoAberto);
  final Reg a;
  final List<Reg> pesagens, sanidade;
  final Reg? servicoAberto;
}

class FichaCurral extends StatefulWidget {
  const FichaCurral({super.key, required this.animalId});
  final int animalId;

  @override
  State<FichaCurral> createState() => _FichaCurralState();
}

class _FichaCurralState extends State<FichaCurral> {
  VoidCallback? _cancelarLeitor;

  int get id => widget.animalId;

  @override
  void initState() {
    super.initState();
    // Leu outro brinco com a ficha aberta: troca para o outro animal.
    _cancelarLeitor = LeitorTeclado.instancia.assinar((codigo) async {
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (parecePeso(codigo)) return;
      final outro = await Db.buscarPorCodigo(codigo);
      if (!mounted) return;
      if (outro == null) {
        _aviso('Brinco $codigo não cadastrado.', cor: Cores.alerta);
        return;
      }
      if (outro['id'] == id) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => FichaCurral(animalId: outro['id'] as int)));
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  Future<_DadosFicha?> _carregar() async {
    final a = await Db.animal(id);
    if (a == null) return null;
    return _DadosFicha(
      a,
      await Db.pesagens(animalId: id),
      await Db.sanidadeDoAnimal(id),
      a['sexo'] == 'F' ? await Db.reproducaoAberta(id) : null,
    );
  }

  void _aviso(String texto, {Color cor = Cores.sucesso}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: cor, content: Text(texto)));
  }

  void _ir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  Future<void> _pesar(Reg a) async {
    final peso = await pedirPeso(context, titulo: 'Peso do brinco ${a['brinco']}');
    if (peso == null || peso <= 0) return;
    final g = await Db.registrarPesagem(id, peso);
    if (!mounted) return;
    _aviso(g == null ? 'Peso ${pesoKg(peso)} salvo.' : 'Peso ${pesoKg(peso)} salvo. Ganho de ${gmd(g)}.');
  }

  Future<void> _medicar(Reg a) async {
    final item = await pedirItemSanidade(context);
    if (item == null) return;
    await Db.lancarSanidade([id], item.valores());
    if (!mounted) return;
    _aviso('${item.produto} registrado no brinco ${a['brinco']}.');
  }

  Future<void> _vincular(Reg a) async {
    final rfid = await showDialog<String>(context: context, builder: (_) => const _DialogoLerRfid());
    if (rfid == null || rfid.trim().isEmpty) return;
    try {
      await Db.atualizar('animais', id, {'rfid': rfid.trim()});
      if (mounted) _aviso('Brinco eletrônico vinculado.');
    } on RegistroDuplicado catch (e) {
      if (mounted) _aviso(e.mensagem, cor: Cores.alerta);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AoMudar<_DadosFicha?>(
      carregar: _carregar,
      builder: (context, f) {
        if (f == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Animal')),
            body: const Center(child: Text('Animal não encontrado.', style: TextStyle(fontSize: 20))),
          );
        }
        final a = f.a;
        final ativo = a['status'] == 'Ativo';
        final femea = a['sexo'] == 'F';
        final largura = MediaQuery.sizeOf(context).width;
        Widget botao(IconData icone, String texto, VoidCallback onTap, {Color cor = Cores.oliva}) => Material(
              color: cor,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icone, size: 34, color: Colors.white),
                    const SizedBox(height: 6),
                    Text(texto,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            );
        final botoes = <Widget>[
          botao(Icons.monitor_weight_outlined, 'PESAR', () => _pesar(a), cor: Cores.azul),
          botao(Icons.vaccines_outlined, 'VACINAR / MEDICAR', () => _medicar(a)),
          if (femea) ...[
            botao(Icons.child_friendly_outlined, 'NASCIMENTO',
                () => _ir(NascimentoFormPage(mae: a, reproducao: f.servicoAberto)),
                cor: Cores.olivaClaro),
            botao(
              Icons.favorite_border,
              f.servicoAberto != null && f.servicoAberto!['diagnostico'] == 'Pendente' ? 'DIAGNÓSTICO' : 'REPRODUÇÃO',
              () => _ir(f.servicoAberto != null && f.servicoAberto!['diagnostico'] == 'Pendente'
                  ? ReproducaoFormPage(registro: f.servicoAberto, femea: a)
                  : ReproducaoFormPage(femea: a)),
              cor: Cores.olivaClaro,
            ),
          ],
          botao(Icons.swap_horiz, 'MOVER', () => _ir(MoverAnimaisPage(animais: [a])), cor: Cores.olivaEscuro),
          botao(Icons.sell_outlined, 'VENDA / SAÍDA', () => _ir(SaidaFormPage(animais: [a])), cor: Cores.alerta),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text('Brinco ${a['brinco']}'),
            actions: [
              IconButton(
                tooltip: 'Ficha completa',
                icon: const Icon(Icons.badge_outlined),
                onPressed: () => _ir(FichaAnimalPage(id)),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _Cabecalho(animal: a, ultimaPesagem: f.pesagens.isEmpty ? null : f.pesagens.first),
            const SizedBox(height: 16),
            if (!ativo)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Este animal saiu do rebanho (${a['status']}).',
                    style: const TextStyle(color: Cores.alerta, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            if (ativo) ...[
              GridView.count(
                crossAxisCount: largura >= 720 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: largura >= 720 ? 2.6 : 1.6,
                children: botoes,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _vincular(a),
                icon: const Icon(Icons.contactless_outlined),
                label: Text(txt(a['rfid']).isEmpty ? 'VINCULAR BRINCO ELETRÔNICO' : 'TROCAR BRINCO ELETRÔNICO'),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Últimos lançamentos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ..._historico(f),
          ]),
        );
      },
    );
  }

  List<Widget> _historico(_DadosFicha f) {
    final itens = <(String, IconData, String, String)>[]; // data, ícone, título, detalhe
    final ps = f.pesagens; // mais recente primeiro
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i];
      var detalhe = txt(p['evento']);
      if (i + 1 < ps.length) {
        final dias = diasEntre(txt(ps[i + 1]['data']), txt(p['data']));
        if (dias > 0) {
          detalhe += ' · GMD ${gmd(((p['peso'] as num) - (ps[i + 1]['peso'] as num)) / dias)}';
        }
      }
      itens.add((txt(p['data']), Icons.monitor_weight_outlined, 'Pesagem: ${kg(p['peso'] as num)}', detalhe));
    }
    for (final s in f.sanidade) {
      itens.add((
        txt(s['data']),
        Icons.vaccines_outlined,
        '${s['produto']}',
        [txt(s['tipo']), if (txt(s['dose']).isNotEmpty) 'dose ${s['dose']}'].where((x) => x.isNotEmpty).join(' · '),
      ));
    }
    if (itens.isEmpty) return const [Text('Nenhum lançamento ainda.', style: TextStyle(fontSize: 17))];
    itens.sort((x, y) => y.$1.compareTo(x.$1));
    return [
      for (final (data, icone, titulo, detalhe) in itens.take(20))
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(icone, color: Cores.oliva, size: 30),
            title: Text(titulo, style: const TextStyle(fontSize: 18)),
            subtitle: Text([br(data), if (detalhe.isNotEmpty) detalhe].join(' · '), style: const TextStyle(fontSize: 15)),
          ),
        ),
    ];
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.animal, this.ultimaPesagem});
  final Reg animal;
  final Reg? ultimaPesagem;

  @override
  Widget build(BuildContext context) {
    final a = animal;
    Widget dado(String rotulo, String valor) => valor.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              SizedBox(width: 120, child: Text(rotulo, style: const TextStyle(color: Colors.white70, fontSize: 16))),
              Expanded(
                  child: Text(valor,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
            ]),
          );
    final peso = ultimaPesagem?['peso'] as num?;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(txt(a['nome']).isEmpty ? 'Brinco ${a['brinco']}' : '${a['brinco']} · ${a['nome']}',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(10)),
            child: Text(a['sexo'] == 'F' ? 'FÊMEA' : 'MACHO',
                style: const TextStyle(color: Cores.azul, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(peso == null ? 'Sem pesagem' : kg(peso),
            style: const TextStyle(color: Cores.laranja, fontSize: 40, fontWeight: FontWeight.w900)),
        if (ultimaPesagem != null)
          Text('pesado em ${br(ultimaPesagem!['data'])}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 6),
        dado('Categoria', txt(a['categoria'])),
        dado('Eletrônico', txt(a['rfid'])),
        dado('Raça', txt(a['raca'])),
        dado('Lote', txt(a['lote_nome'])),
        dado('Piquete', txt(a['piquete_nome'])),
        dado('Idade', a['nascimento'] == null ? '' : '${idade(a['nascimento'])} (${br(a['nascimento'])})'),
        dado('Mãe', txt(a['mae_brinco'])),
      ]),
    );
  }
}

/// Espera o bastão ler o brinco eletrônico.
class _DialogoLerRfid extends StatefulWidget {
  const _DialogoLerRfid();

  @override
  State<_DialogoLerRfid> createState() => _DialogoLerRfidState();
}

class _DialogoLerRfidState extends State<_DialogoLerRfid> {
  VoidCallback? _cancelar;

  @override
  void initState() {
    super.initState();
    _cancelar = LeitorTeclado.instancia.assinar((codigo) {
      if (mounted) Navigator.pop(context, codigo);
    });
  }

  @override
  void dispose() {
    _cancelar?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Brinco eletrônico'),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contactless_outlined, size: 72, color: Cores.laranja),
        SizedBox(height: 12),
        Text('Encoste o bastão no brinco eletrônico.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
      ]),
      actions: [
        TextButton(
          onPressed: () async {
            final digitado = await pedirNumero(context, titulo: 'Número do brinco eletrônico');
            if (digitado != null && context.mounted) Navigator.pop(context, digitado);
          },
          child: const Text('DIGITAR'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
      ],
    );
  }
}

// ======================= Escolha do produto sanitário =======================

/// Produto escolhido no curral, com os mesmos tipos e itens do módulo Sanidade.
class ItemSanidade {
  const ItemSanidade({required this.tipo, required this.produto, this.dose, this.carencia, this.proxima});
  final String tipo; // Vacinação, Antiparasitário ou Tratamento
  final String produto;
  final String? dose;
  final int? carencia;
  final String? proxima;

  Reg valores() => {
        'data': hojeIso(),
        'tipo': tipo,
        'produto': produto,
        'dose': dose,
        'carencia': carencia,
        'proxima': proxima,
        'obs': 'Lançado no Modo Curral',
      };

  String get resumo => [
        produto,
        if (dose != null) 'dose $dose',
        if (carencia != null) 'carência $carencia dias',
        if (proxima != null) 'próxima ${br(proxima)}',
      ].join(' · ');
}

Future<ItemSanidade?> pedirItemSanidade(BuildContext context, {ItemSanidade? atual}) {
  return Navigator.push<ItemSanidade>(
    context,
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _TelaItemSanidade(atual: atual)),
  );
}

class _TelaItemSanidade extends StatefulWidget {
  const _TelaItemSanidade({this.atual});
  final ItemSanidade? atual;

  @override
  State<_TelaItemSanidade> createState() => _TelaItemSanidadeState();
}

class _TelaItemSanidadeState extends State<_TelaItemSanidade> {
  late String tipo = widget.atual?.tipo ?? 'Vacinação';
  late final dose = TextEditingController(text: widget.atual?.dose ?? '');
  late final carencia = TextEditingController(text: widget.atual?.carencia?.toString() ?? '');
  late String? proxima = widget.atual?.proxima;

  @override
  void dispose() {
    dose.dispose();
    carencia.dispose();
    super.dispose();
  }

  Future<void> _escolher(String item) async {
    var produto = item;
    if (item == 'Outros') {
      final ctrl = TextEditingController();
      final nome = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Qual produto?'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Nome do produto'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCELAR')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('OK')),
          ],
        ),
      );
      ctrl.dispose();
      if (nome == null || nome.trim().isEmpty) return;
      produto = nome.trim();
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      ItemSanidade(
        tipo: tipo,
        produto: produto,
        dose: nulo(dose.text),
        carencia: lerNumero(carencia.text)?.round(),
        proxima: proxima,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tipos = itensSanidade.keys.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Produto aplicado')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Segmentos(
          opcoes: [for (final t in tipos) t.toUpperCase()],
          selecionado: tipos.indexOf(tipo),
          altura: 48,
          onChanged: (i) => setState(() => tipo = tipos[i]),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Dose, carência e próxima aplicação (opcional)',
              style: TextStyle(color: Cores.oliva, fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded: widget.atual?.dose != null || widget.atual?.carencia != null,
          children: [
            campoTexto(dose, 'Dose (ex.: 5 ml)'),
            gap,
            campoTexto(carencia, 'Carência', numero: true, sufixo: 'dias'),
            gap,
            DateField(label: 'Próxima aplicação', value: proxima, onChanged: (v) => setState(() => proxima = v)),
            Wrap(spacing: 8, children: [
              for (final e in const {'30 dias': 30, '3 meses': 90, '6 meses': 182, '1 ano': 365}.entries)
                ActionChip(
                  label: Text('+${e.key}'),
                  onPressed: () => setState(() => proxima = somaDias(hojeIso(), e.value)),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        for (final item in itensSanidade[tipo]!)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              minVerticalPadding: 14,
              leading: Icon(item == 'Outros' ? Icons.edit_outlined : Icons.vaccines_outlined,
                  color: Cores.oliva, size: 30),
              title: Text(item, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _escolher(item),
            ),
          ),
      ]),
    );
  }
}
