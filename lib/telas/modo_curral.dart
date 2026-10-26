import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dispositivos/leitor_teclado.dart';
import '../tema.dart';
import '../util/util.dart';
import '../widgets/bandeira.dart';
import '../widgets/barra_sincronia.dart';
import '../widgets/botao_curral.dart';
import '../widgets/teclado_grande.dart';
import 'animais.dart';
import 'dispositivos.dart';
import 'ficha_animal.dart';
import 'lancamento_voz.dart';
import 'manejo_em_serie.dart';
import 'modo_inseminacao.dart';
import 'mover.dart';
import 'fila_do_dia.dart';
import '../dados/manejo.dart' show filaDoDia;
import 'vendas.dart';

/// Atalho para lançar rápido o serviço feito no curral. Encostou o bastão no
/// brinco, abre a ficha rápida do animal. Tudo grava nos módulos do app.
class ModoCurral extends StatefulWidget {
  const ModoCurral({super.key});

  @override
  State<ModoCurral> createState() => _ModoCurralState();
}

class _ModoCurralState extends State<ModoCurral> {
  VoidCallback? _cancelarLeitor;

  @override
  void initState() {
    super.initState();
    _cancelarLeitor = LeitorTeclado.instancia.assinar((codigo) {
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (parecePeso(codigo)) return; // leitura da balança fora da pesagem
      abrirPorCodigo(context, codigo);
    });
  }

  @override
  void dispose() {
    _cancelarLeitor?.call();
    super.dispose();
  }

  void _ir(Widget tela) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => tela));

  Future<void> _digitarBrinco() async {
    final codigo = await pedirNumero(context, titulo: 'Número do brinco');
    if (codigo != null && codigo.trim().isNotEmpty && mounted) abrirPorCodigo(context, codigo.trim());
  }

  Future<void> _escolherEIr(String titulo, Widget Function(List<Reg>) tela) async {
    final r = await pickAnimais(context, titulo: titulo);
    if (r == null || r.isEmpty || !mounted) return;
    _ir(tela(r));
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          BandeiraBrasil(),
          SizedBox(width: 10),
          Text('Modo Curral'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Bastão e balança',
            icon: const Icon(Icons.bluetooth),
            onPressed: () => _ir(const TelaDispositivos()),
          ),
        ],
      ),
      body: Column(children: [
        const BarraSincronia(sempre: true),
        ValueListenableBuilder<Reg?>(
          valueListenable: Db.prop,
          builder: (context, p, _) => Container(
            width: double.infinity,
            color: Cores.azul,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(txt(p?['nome']).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _PainelLeitura(aoDigitar: _digitarBrinco),
            const SizedBox(height: 16),
            AoMudar<int>(
              carregar: () async => (await Db.animais(soAtivos: true)).length,
              builder: (context, total) {
                final feitos = Db.filaFeitos();
                final fila = filaDoDia(hojeIso()).where((i) => !feitos.contains(i.chave)).length;
                return GridView.count(
                crossAxisCount: largura >= 720 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: largura >= 720 ? 1.6 : 1.05,
                children: [
                  BotaoCurral(
                    icone: Icons.checklist,
                    rotulo: 'Fila\ndo dia',
                    detalhe: fila == 0 ? 'nada pendente' : '$fila para fazer',
                    cor: fila == 0 ? Cores.olivaClaro : Cores.alerta,
                    aoTocar: () => _ir(const FilaDoDiaPage()),
                  ),
                  BotaoCurral(
                    icone: Icons.mic,
                    rotulo: 'Lançar\npor voz',
                    detalhe: 'peso, vacina, diagnóstico',
                    cor: Cores.oliva,
                    aoTocar: () => _ir(const LancamentoVozPage()),
                  ),
                  BotaoCurral(
                    icone: Icons.monitor_weight_outlined,
                    rotulo: 'Pesagem\nem série',
                    cor: Cores.azul,
                    aoTocar: () => _ir(const ManejoEmSerie(modo: ModoSerie.pesagem)),
                  ),
                  BotaoCurral(
                    icone: Icons.vaccines_outlined,
                    rotulo: 'Vacina e\nremédio em série',
                    cor: Cores.oliva,
                    aoTocar: () => _ir(const ManejoEmSerie(modo: ModoSerie.sanidade)),
                  ),
                  BotaoCurral(
                    icone: Icons.favorite_border,
                    rotulo: 'Modo\nInseminação',
                    detalhe: 'IA, IATF e diagnóstico',
                    cor: Cores.azul,
                    aoTocar: () => _ir(const ModoInseminacao()),
                  ),
                  BotaoCurral(
                    icone: Icons.child_friendly_outlined,
                    rotulo: 'Nascimento',
                    cor: Cores.olivaClaro,
                    aoTocar: () => _ir(const NascimentoFormPage()),
                  ),
                  BotaoCurral(
                    icone: Icons.add_circle_outline,
                    rotulo: 'Novo\nanimal',
                    detalhe: '$total ${total == 1 ? 'cabeça' : 'cabeças'} ativas',
                    cor: Cores.olivaClaro,
                    aoTocar: () => _ir(const AnimalFormPage()),
                  ),
                  BotaoCurral(
                    icone: Icons.swap_horiz,
                    rotulo: 'Mover\nanimais',
                    detalhe: 'lote, piquete, fazenda',
                    cor: Cores.olivaEscuro,
                    aoTocar: () => _escolherEIr('Animais para mover', (r) => MoverAnimaisPage(animais: r)),
                  ),
                  if (Db.podeGravar('saidas'))
                  BotaoCurral(
                    icone: Icons.sell_outlined,
                    rotulo: 'Venda\nou saída',
                    cor: Cores.alerta,
                    aoTocar: () => _escolherEIr('Animais que saem', (r) => SaidaFormPage(animais: r)),
                  ),
                ],
              );
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('VOLTAR AO PAINEL'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PainelLeitura extends StatelessWidget {
  const _PainelLeitura({required this.aoDigitar});
  final VoidCallback aoDigitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Cores.olivaEscuro,
        borderRadius: BorderRadius.circular(20),
        // Foto do gado bem escurecida: dá identidade sem atrapalhar a leitura no sol.
        image: DecorationImage(
          image: const AssetImage('assets/imagens/fundo_gado.jpg'),
          fit: BoxFit.cover,
          alignment: const Alignment(0.35, -0.2),
          colorFilter: ColorFilter.mode(Cores.olivaEscuro.withValues(alpha: 0.72), BlendMode.srcATop),
          onError: (_, __) {},
        ),
      ),
      child: Column(children: [
        const Icon(Icons.contactless_outlined, size: 72, color: Cores.laranja),
        const SizedBox(height: 8),
        const Text('Encoste o bastão no brinco',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('A ficha do animal abre sozinha: pesar, vacinar, parto, diagnóstico, saída.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 17)),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Cores.laranja, foregroundColor: Cores.azul, minimumSize: const Size.fromHeight(68)),
          onPressed: aoDigitar,
          icon: const Icon(Icons.dialpad, size: 30),
          label: const Text('DIGITAR Nº DO BRINCO'),
        ),
      ]),
    );
  }
}
