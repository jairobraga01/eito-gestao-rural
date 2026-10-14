import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/formato.dart';
import '../widgets/teclado_grande.dart';
import 'ficha_animal.dart' show pedirProduto;
import 'novo_animal.dart';

enum ModoSerie { pesagem, sanidade }

/// Manejo no tronco/brete, um animal atrás do outro:
/// lê o brinco → (pesa) → confirma → próximo. Sem voltar para menu nenhum.
class ManejoEmSerie extends StatefulWidget {
  const ManejoEmSerie({super.key, required this.repo, required this.modo});
  final Repositorio repo;
  final ModoSerie modo;

  @override
  State<ManejoEmSerie> createState() => _ManejoEmSerieState();
}

class _ManejoEmSerieState extends State<ManejoEmSerie> {
  final ValueNotifier<String> _peso = ValueNotifier('');
  final Set<String> _feitos = {};
  VoidCallback? _cancelarLeitor;
  Animal? _atual; // animal no tronco aguardando peso
  String? _produto;
  String? _mensagem;
  Color _corMensagem = Cores.sucesso;
  bool _buscando = false;

  bool get _pesagem => widget.modo == ModoSerie.pesagem;

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar(_aoLer);
    if (!_pesagem) WidgetsBinding.instance.addPostFrameCallback((_) => _escolherProduto());
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    _peso.dispose();
    super.dispose();
  }

  Future<void> _escolherProduto() async {
    final p = await pedirProduto(context, inicial: _produto ?? '');
    if (!mounted) return;
    if (p == null && _produto == null) {
      Navigator.pop(context); // sem produto não há o que registrar
      return;
    }
    if (p != null) setState(() => _produto = p);
  }

  void _avisar(String texto, {Color cor = Cores.sucesso}) => setState(() {
        _mensagem = texto;
        _corMensagem = cor;
      });

  void _aoLer(String leitura) {
    // Com animal no tronco, número curto é o peso vindo da balança.
    if (_pesagem && _atual != null && parecePeso(leitura)) {
      _peso.value = leituraParaVisor(leitura) ?? _peso.value;
      return;
    }
    // Balança mandou peso sem animal no tronco: avisa em vez de buscar brinco.
    if (_pesagem && _atual == null && parecePeso(leitura)) {
      _avisar('Chegou o peso ${leituraParaVisor(leitura)} kg, mas falta ler o brinco primeiro.',
          cor: Cores.alerta);
      return;
    }
    _receberBrinco(leitura);
  }

  Future<void> _digitarBrinco() async {
    final c = await pedirNumero(context, titulo: 'Número do brinco');
    if (c != null && c.trim().isNotEmpty) _receberBrinco(c.trim());
  }

  Future<void> _receberBrinco(String codigo) async {
    if (_buscando) return;
    setState(() => _buscando = true);
    final a = await widget.repo.buscarPorCodigo(codigo);
    if (!mounted) return;
    setState(() => _buscando = false);

    if (a == null) {
      _avisar('Brinco $codigo não cadastrado.', cor: Cores.alerta);
      final cadastrar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Brinco $codigo não cadastrado'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PULAR')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CADASTRAR')),
          ],
        ),
      );
      if (cadastrar == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NovoAnimal(repo: widget.repo, codigoLido: codigo)));
      }
      return;
    }
    if (a.status != 'ativo') {
      _avisar('Brinco ${a.brinco} já saiu do rebanho (${a.status}).', cor: Cores.alerta);
      return;
    }

    if (_pesagem) {
      _peso.value = '';
      setState(() {
        _atual = a;
        _mensagem = null;
      });
      return;
    }

    // Vacinação: registra na hora, sem tocar em nada.
    if (_feitos.contains(a.id)) {
      _avisar('Brinco ${a.brinco} JÁ recebeu $_produto agora. Não registrei de novo.', cor: Cores.alerta);
      return;
    }
    widget.repo.registrarSanidade(a, _produto!);
    _feitos.add(a.id);
    _avisar('✔ Brinco ${a.brinco}: $_produto');
  }

  void _confirmarPeso() {
    final a = _atual;
    final peso = lerNumero(_peso.value);
    if (a == null || peso == null || peso <= 0) return;
    final gmd = widget.repo.registrarPeso(a, peso);
    _feitos.add(a.id);
    _peso.value = '';
    setState(() => _atual = null);
    _avisar('✔ Brinco ${a.brinco}: ${pesoKg(peso)}'
        '${gmd == null ? '' : '  ·  ${numeroBr(gmd, casas: 2)} kg/dia'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pesagem ? 'Pesagem em série' : 'Vacinação em série'),
        actions: [
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
          if (!_pesagem)
            Card(
              child: ListTile(
                leading: const Icon(Icons.vaccines_outlined, size: 34, color: Cores.oliva),
                title: Text(_produto ?? 'Escolha o produto',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                subtitle: const Text('Aplicando em todos os brincos lidos'),
                trailing: TextButton(onPressed: _escolherProduto, child: const Text('TROCAR')),
              ),
            ),
          if (_mensagem != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _corMensagem, borderRadius: BorderRadius.circular(14)),
              child: Text(_mensagem!,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 8),
          if (_pesagem && _atual != null) ..._painelPeso(_atual!) else _painelEspera(),
        ]),
      ),
    );
  }

  Widget _painelEspera() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          _buscando
              ? const SizedBox(height: 72, width: 72, child: CircularProgressIndicator(color: Cores.laranja))
              : const Icon(Icons.contactless_outlined, size: 84, color: Cores.laranja),
          const SizedBox(height: 12),
          const Text('Próximo animal:\nencoste o bastão no brinco',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.laranja, minimumSize: const Size.fromHeight(68)),
            onPressed: _digitarBrinco,
            icon: const Icon(Icons.dialpad, size: 30),
            label: const Text('DIGITAR Nº DO BRINCO'),
          ),
        ]),
      );

  List<Widget> _painelPeso(Animal a) => [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Cores.olivaEscuro, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Brinco ${a.brinco}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                Text(
                  [
                    a.femea ? 'Fêmea' : 'Macho',
                    if (a.lote != null) 'Lote ${a.lote}',
                    if (a.pesoAtual != null) 'último ${pesoKg(a.pesoAtual!)}',
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
        const SizedBox(height: 12),
        VisorNumero(valor: _peso, sufixo: 'kg'),
        const SizedBox(height: 4),
        const Text('A balança preenche sozinha, ou digite abaixo.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: TecladoGrande(valor: _peso, decimal: true, maxDigitos: 5),
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: _peso,
          builder: (context, v, _) => FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.laranja, minimumSize: const Size.fromHeight(80)),
            onPressed: v.isEmpty ? null : _confirmarPeso,
            icon: const Icon(Icons.check, size: 36),
            label: const Text('CONFIRMAR PESO'),
          ),
        ),
      ];
}
