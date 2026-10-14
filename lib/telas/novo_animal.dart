import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/formato.dart';

class NovoAnimal extends StatefulWidget {
  const NovoAnimal({super.key, required this.repo, this.codigoLido});
  final Repositorio repo;

  /// Código que veio do bastão (ou digitado) e não foi encontrado.
  final String? codigoLido;

  @override
  State<NovoAnimal> createState() => _NovoAnimalState();
}

class _NovoAnimalState extends State<NovoAnimal> {
  final _brinco = TextEditingController();
  final _rfid = TextEditingController();
  final _nome = TextEditingController();
  final _raca = TextEditingController();
  final _lote = TextEditingController();
  final _peso = TextEditingController();
  String _sexo = 'F';
  DateTime? _nascimento;
  String? _erro;
  bool _salvando = false;
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    final c = widget.codigoLido;
    if (c != null) {
      // RFID tem 15 dígitos; brinco visual é curto.
      (c.length >= 8 ? _rfid : _brinco).text = c;
    }
    // Encostou o bastão com esta tela aberta: preenche o brinco eletrônico.
    _cancelarLeitor = LeitorTeclado.instancia.assinar((leitura) {
      if (!parecePeso(leitura)) setState(() => _rfid.text = leitura);
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    for (final c in [_brinco, _rfid, _nome, _raca, _lote, _peso]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherNascimento() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _nascimento ?? hoje,
      firstDate: DateTime(hoje.year - 25),
      lastDate: hoje,
      helpText: 'Data de nascimento',
    );
    if (d != null) setState(() => _nascimento = d);
  }

  Future<void> _salvar() async {
    final brinco = _brinco.text.trim();
    if (brinco.isEmpty) {
      setState(() => _erro = 'Informe o número do brinco.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final repetidoBrinco = await widget.repo.buscarPorCodigo(brinco);
    final rfid = _rfid.text.trim();
    final repetidoRfid = rfid.isEmpty ? null : await widget.repo.buscarPorCodigo(rfid);
    if (!mounted) return;
    if (repetidoBrinco != null || repetidoRfid != null) {
      setState(() {
        _salvando = false;
        _erro = 'Já existe um animal com esse brinco${repetidoRfid != null ? ' eletrônico' : ''}.';
      });
      return;
    }
    widget.repo.novoAnimal(
      brinco: brinco,
      sexo: _sexo,
      rfid: rfid,
      nome: _nome.text,
      raca: _raca.text,
      lote: _lote.text,
      nascimento: _nascimento,
      peso: lerNumero(_peso.text),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Cores.sucesso, content: Text('Brinco $brinco cadastrado.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const campo = TextStyle(fontSize: 20);
    return Scaffold(
      appBar: AppBar(title: const Text('Novo animal')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _brinco,
            style: campo,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nº do brinco *', prefixIcon: Icon(Icons.tag)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rfid,
            style: campo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Brinco eletrônico (RFID)',
              helperText: 'Encoste o bastão no brinco para preencher',
              prefixIcon: Icon(Icons.contactless_outlined),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Sexo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            for (final (valor, texto) in const [('F', 'FÊMEA'), ('M', 'MACHO')]) ...[
              Expanded(
                child: _sexo == valor
                    ? FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Cores.laranja),
                        onPressed: () {},
                        child: Text(texto))
                    : OutlinedButton(onPressed: () => setState(() => _sexo = valor), child: Text(texto)),
              ),
              if (valor == 'F') const SizedBox(width: 12),
            ],
          ]),
          const SizedBox(height: 16),
          TextField(controller: _nome, style: campo, decoration: const InputDecoration(labelText: 'Nome (opcional)')),
          const SizedBox(height: 12),
          TextField(controller: _raca, style: campo, decoration: const InputDecoration(labelText: 'Raça')),
          const SizedBox(height: 12),
          TextField(controller: _lote, style: campo, decoration: const InputDecoration(labelText: 'Lote / pasto')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _escolherNascimento,
            icon: const Icon(Icons.cake_outlined),
            label: Text(_nascimento == null ? 'DATA DE NASCIMENTO' : 'Nasceu em ${dataBr(_nascimento!)}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _peso,
            style: campo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Peso de entrada (kg)', suffixText: 'kg'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Cores.alerta, fontSize: 17, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.laranja, minimumSize: const Size.fromHeight(72)),
            onPressed: _salvando ? null : _salvar,
            icon: const Icon(Icons.check, size: 32),
            label: const Text('SALVAR ANIMAL'),
          ),
        ]),
      ),
    );
  }
}
