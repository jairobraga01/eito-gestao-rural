import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/formato.dart';
import '../widgets/teclado_grande.dart';

class FichaAnimal extends StatefulWidget {
  const FichaAnimal({super.key, required this.repo, required this.animalId});
  final Repositorio repo;
  final String animalId;

  @override
  State<FichaAnimal> createState() => _FichaAnimalState();
}

class _FichaAnimalState extends State<FichaAnimal> {
  late final Stream<Animal?> _animal = widget.repo.animal(widget.animalId);
  late final Stream<List<Evento>> _historico = widget.repo.historico(widget.animalId);
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    // Leu outro brinco com a ficha aberta: troca para o outro animal.
    _cancelarLeitor = LeitorTeclado.instancia.assinar((codigo) async {
      final outro = await widget.repo.buscarPorCodigo(codigo);
      if (!mounted || outro == null || outro.id == widget.animalId) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => FichaAnimal(repo: widget.repo, animalId: outro.id)));
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  void _aviso(String texto, {Color cor = Cores.sucesso}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: cor, content: Text(texto)));
  }

  Future<void> _pesar(Animal a) async {
    final peso = await pedirPeso(context, titulo: 'Peso do brinco ${a.brinco}');
    if (peso == null || peso <= 0) return;
    final gmd = widget.repo.registrarPeso(a, peso);
    _aviso(gmd == null
        ? 'Peso ${pesoKg(peso)} salvo.'
        : 'Peso ${pesoKg(peso)} salvo. Ganho de ${numeroBr(gmd, casas: 2)} kg/dia.');
  }

  Future<void> _medicar(Animal a) async {
    final produto = await pedirProduto(context);
    if (produto == null) return;
    widget.repo.registrarSanidade(a, produto);
    _aviso('$produto registrado no brinco ${a.brinco}.');
  }

  Future<void> _vincular(Animal a) async {
    final rfid = await showDialog<String>(context: context, builder: (_) => const _DialogoLerRfid());
    if (rfid == null || rfid.isEmpty) return;
    final dono = await widget.repo.buscarPorCodigo(rfid);
    if (dono != null && dono.id != a.id) {
      _aviso('Esse brinco eletrônico já é do animal ${dono.brinco}.', cor: Cores.alerta);
      return;
    }
    widget.repo.vincularRfid(a, rfid);
    _aviso('Brinco eletrônico vinculado.');
  }

  Future<void> _saida(Animal a) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Saída do brinco ${a.brinco}'),
        children: [
          for (final (valor, texto) in const [('vendido', 'Venda'), ('morto', 'Morte'), ('descartado', 'Descarte')])
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              onPressed: () => Navigator.pop(ctx, valor),
              child: Text(texto, style: const TextStyle(fontSize: 20)),
            ),
        ],
      ),
    );
    if (motivo == null || !mounted) return;
    widget.repo.registrarSaida(a, motivo);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Animal?>(
      stream: _animal,
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Animal')),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : const Text('Animal não encontrado.', style: TextStyle(fontSize: 20)),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text('Brinco ${a.brinco}')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _Cabecalho(animal: a),
            const SizedBox(height: 16),
            if (a.status != 'ativo')
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Este animal saiu do rebanho (${a.status}).',
                    style: const TextStyle(color: Cores.alerta, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            if (a.status == 'ativo') ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Cores.laranja, minimumSize: const Size.fromHeight(76)),
                onPressed: () => _pesar(a),
                icon: const Icon(Icons.monitor_weight_outlined, size: 34),
                label: const Text('PESAR'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(76)),
                onPressed: () => _medicar(a),
                icon: const Icon(Icons.vaccines_outlined, size: 34),
                label: const Text('VACINAR / MEDICAR'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _vincular(a),
                    icon: const Icon(Icons.contactless_outlined),
                    label: Text(a.rfid == null ? 'BRINCO ELETR.' : 'TROCAR RFID'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Cores.alerta, side: const BorderSide(color: Cores.alerta, width: 2)),
                    onPressed: () => _saida(a),
                    icon: const Icon(Icons.logout),
                    label: const Text('SAÍDA'),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 24),
            const Text('Histórico', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            StreamBuilder<List<Evento>>(
              stream: _historico,
              builder: (context, s) {
                final eventos = s.data ?? const <Evento>[];
                if (eventos.isEmpty) {
                  return const Text('Nenhum lançamento ainda.', style: TextStyle(fontSize: 17));
                }
                return Column(children: [for (final e in eventos.take(30)) _LinhaEvento(evento: e)]);
              },
            ),
          ]),
        );
      },
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.animal});
  final Animal animal;

  @override
  Widget build(BuildContext context) {
    final a = animal;
    Widget dado(String rotulo, String valor) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 120, child: Text(rotulo, style: const TextStyle(color: Colors.white70, fontSize: 16))),
            Expanded(
                child: Text(valor,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(a.nome ?? 'Brinco ${a.brinco}',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(10)),
            child: Text(a.femea ? 'FÊMEA' : 'MACHO',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(a.pesoAtual == null ? 'Sem pesagem' : pesoKg(a.pesoAtual!),
            style: const TextStyle(color: Cores.laranja, fontSize: 40, fontWeight: FontWeight.w900)),
        if (a.dataUltimoPeso != null)
          Text('pesado em ${dataBr(a.dataUltimoPeso!)}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 6),
        dado('Brinco', a.brinco),
        if (a.rfid != null) dado('Eletrônico', a.rfid!),
        if (a.raca != null) dado('Raça', a.raca!),
        if (a.lote != null) dado('Lote', a.lote!),
        if (a.nascimento != null) dado('Idade', '${idade(a.nascimento!)} (${dataBr(a.nascimento!)})'),
      ]),
    );
  }
}

class _LinhaEvento extends StatelessWidget {
  const _LinhaEvento({required this.evento});
  final Evento evento;

  @override
  Widget build(BuildContext context) {
    final d = evento.dados;
    final (IconData icone, String texto) = switch (evento.tipo) {
      'pesagem' => (
          Icons.monitor_weight_outlined,
          'Pesagem: ${pesoKg((d['peso'] as num).toDouble())}'
              '${d['gmd'] == null ? '' : ' · GMD ${numeroBr((d['gmd'] as num).toDouble(), casas: 2)} kg/dia'}'
        ),
      'sanidade' => (Icons.vaccines_outlined, '${d['produto']}${d['dose'] == null ? '' : ' · ${d['dose']}'}'),
      'cadastro' => (Icons.add_circle_outline, 'Cadastro${d['peso'] == null ? '' : ' com ${pesoKg((d['peso'] as num).toDouble())}'}'),
      'rfid' => (Icons.contactless_outlined, 'Brinco eletrônico ${d['rfid']}'),
      'saida' => (Icons.logout, 'Saída: ${d['motivo']}'),
      _ => (Icons.notes, evento.tipo),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icone, color: Cores.oliva, size: 30),
        title: Text(texto, style: const TextStyle(fontSize: 18)),
        subtitle: Text(dataHoraBr(evento.data), style: const TextStyle(fontSize: 15)),
      ),
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
    _cancelar = LeitorTeclado.instancia.assinar((codigo) => Navigator.pop(context, codigo));
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

/// Pergunta o produto aplicado (vacina, vermífugo, medicamento).
Future<String?> pedirProduto(BuildContext context, {String inicial = ''}) {
  final ctrl = TextEditingController(text: inicial);
  const sugestoes = ['Brucelose (B19)', 'Raiva', 'Clostridiose', 'Ivermectina', 'Vermífugo', 'Carrapaticida'];
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Produto aplicado'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Vacina ou medicamento'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in sugestoes)
              ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 16)),
                onPressed: () => Navigator.pop(ctx, s),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
