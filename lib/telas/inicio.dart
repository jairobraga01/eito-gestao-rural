// Painel: busca, previsão do tempo, alertas, modos, indicadores e atalhos da propriedade.
import 'package:flutter/material.dart';

import '../dados/clima.dart';
import '../dados/db.dart';
import '../dados/estoque.dart' show alertasEstoque;
import '../dados/mapa.dart' show Rodizio, SituacaoPasto, rodizio;
import '../dados/planos.dart';
import '../dados/plataforma.dart' show Plataforma;
import '../tema.dart';
import '../util/util.dart';
import 'animais.dart';
import 'base.dart';
import 'clima.dart' show iconeTempo;
import 'cotacao_compra.dart' show CartaoCotacoesRespondidas;
import 'fila_do_dia.dart';
import 'lancamento_voz.dart';
import 'lancar_documento.dart';
import 'lancar_whatsapp.dart';
import 'manejo_em_serie.dart';
import 'popup_arroba.dart';
import 'mover.dart' show MudarPastoPage;
import 'relatorios.dart' show partosPrevistos, diagnosticosAtrasados, aplicacoesProximas, animaisEmCarencia;
import 'reproducao.dart';
import 'sanidade.dart';
import 'nps.dart';

class _Painel {
  int ativos = 0, femeas = 0, machos = 0, prenhes = 0, lotes = 0, avisosEstoque = 0;
  List<Reg> partos = [], diagnosticos = [], aplicacoes = [], carencia = [];
  List<Rodizio> trocar = [];

  /// Piquete vazio que descansou mais (sugestão para receber o gado).
  int? descansado;
}

Future<_Painel> _carregar() async {
  final p = _Painel();
  final ativos = await Db.animais(soAtivos: true);
  p.ativos = ativos.length;
  p.femeas = ativos.where((a) => a['sexo'] == 'F').length;
  p.machos = p.ativos - p.femeas;
  p.prenhes = (await Db.reproducoes(filtro: 'Prenhe')).where((r) => r['femea_status'] == 'Ativo').length;
  p.lotes = (await Db.lotes(soAtivos: true)).length;
  p.partos = await partosPrevistos(30);
  p.diagnosticos = await diagnosticosAtrasados();
  p.aplicacoes = await aplicacoesProximas(15);
  p.carencia = await animaisEmCarencia();
  p.avisosEstoque = alertasEstoque(hojeIso()).length;
  final rod = rodizio(hojeIso());
  p.trocar = rod.where((r) => r.situacao == SituacaoPasto.trocar).toList();
  final prontos = rod.where((r) => r.situacao == SituacaoPasto.pronto).toList()
    ..sort((a, b) => (b.dias ?? 0).compareTo(a.dias ?? 0));
  p.descansado = prontos.firstOrNull?.piquete['id'] as int?;
  return p;
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  String busca = '';

  @override
  void initState() {
    super.initState();
    // Dono e gerente marcam o dia em que o rebanho passou do limite do plano.
    if (!Db.ehCampo && podeLancar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => conferirLimiteAnimais(hojeIso()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Plataforma.contaNova.value) {
        Plataforma.contaNova.value = false;
        await _boasVindas();
      } else if (!Db.ehCampo && mounted) {
        await popupArrobaDoDia(context);
        if (Db.ehDono && mounted) await pedirNps(context);
      }
    });
  }

  Future<void> _boasVindas() => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.celebration_outlined, color: Cores.oliva, size: 40),
          title: const Text('Sua conta está pronta'),
          content: const Text('Você tem 30 dias com tudo liberado para testar.\n\n'
              'Comece cadastrando a fazenda e os pastos no mapa; depois monte os lotes do rebanho. '
              'Se precisar, fale com a gente pela Ajuda dentro do app.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Começar'))],
        ),
      );

  void _abrir(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// Vai para a seção só se o papel a vê; senão o toque não faz nada.
  VoidCallback? _ir(int secao) => podeVer(secao) ? () => Nav.ir(secao) : null;

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Painel',
      fab: const AcoesFab(),
      corpo: Column(
        children: [
          // Busca no topo verde, que continua no cabeçalho do painel.
          Container(
            color: Cores.olivaEscuro,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar animal',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => busca = v),
            ),
          ),
          Expanded(child: busca.trim().isEmpty ? _painel() : _resultados()),
        ],
      ),
    );
  }

  Widget _resultados() {
    return AoMudar<List<Reg>>(
      carregar: () => Db.animais(busca: busca),
      builder: (context, lista) => lista.isEmpty
          ? const Vazio('Nenhum animal encontrado.', icone: Icons.search_off)
          : ListView.separated(
              itemCount: lista.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) => AnimalTile(lista[i]),
            ),
    );
  }

  Widget _painel() {
    final hoje = hojeIso();
    return AoMudar<_Painel>(
      carregar: _carregar,
      builder: (context, p) {
        final alertas = <Widget>[
          for (final r in p.trocar)
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.brown),
              title: Text('Mudar de pasto: ${txt(r.piquete['nome'])}'),
              subtitle: Text('Ocupado há ${r.dias} dias (limite ${r.limite}). Toque para mudar o lote.'),
              onTap: Db.podeGravar('pastagens')
                  ? () => _abrir(MudarPastoPage(origem: r.piquete['id'] as int, destino: p.descansado))
                  : null,
            ),
          for (final r in p.partos)
            ListTile(
              leading: Icon(Icons.child_friendly_outlined,
                  color: txt(r['parto_previsto']).compareTo(hoje) < 0 ? Colors.red : Colors.blue),
              title: Text('Parto previsto: ${rotulo(r)}'),
              subtitle: Text(br(r['parto_previsto'])),
              onTap: Db.podeGravar('animais') && Db.podeGravar('reproducoes')
                  ? () => _abrir(NascimentoFormPage(
                      mae: {'id': r['femea_id'], 'brinco': r['brinco'], 'nome': r['nome']}, reproducao: r))
                  : null,
            ),
          for (final r in p.diagnosticos)
            ListTile(
              leading: const Icon(Icons.hourglass_empty, color: Colors.orange),
              title: Text('Fazer diagnóstico: ${rotulo(r)}'),
              subtitle: Text('${txt(r['tipo'])} em ${br(r['data'])}'),
              onTap: Db.podeGravar('reproducoes') ? () => _abrir(ReproducaoFormPage(registro: r)) : null,
            ),
          for (final s in p.aplicacoes)
            ListTile(
              leading: Icon(Icons.vaccines_outlined,
                  color: txt(s['proxima']).compareTo(hoje) < 0 ? Colors.red : Colors.teal),
              title: Text('${s['produto']} – ${s['qtd']} animal(is)'),
              subtitle: Text(
                  '${txt(s['proxima']).compareTo(hoje) < 0 ? 'Atrasada desde' : 'Prevista para'} ${br(s['proxima'])}'),
              onTap: Db.podeGravar('sanidade') ? () => _abrir(const SanidadeFormPage()) : null,
            ),
          for (final c in p.carencia)
            ListTile(
              leading: const Icon(Icons.block, color: Colors.deepOrange),
              title: Text('Em carência: ${rotulo(c)}'),
              subtitle: Text('${txt(c['produto'])} · liberado para venda em ${br(c['libera'])}'),
              onTap: podeLancar ? () => _abrir(FichaAnimalPage(c['id'] as int)) : null,
            ),
        ];
        final largo = MediaQuery.sizeOf(context).width >= 700;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _Cabecalho(p, _ir),
            // Folha clara com cantos de cima arredondados, por cima do verde.
            ColoredBox(
              color: Cores.olivaEscuro,
              child: Container(
                padding: const EdgeInsets.only(top: 14, bottom: 88),
                decoration: const BoxDecoration(
                  color: Cores.palha,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _PrevisaoTopo(),
            const _AtalhoArroba(),
            const CartaoCotacoesRespondidas(),
            const _AvisoPlano(),
            Secao('Alertas (${alertas.length})'),
            if (alertas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Nada pendente. Partos dos próximos 30 dias, diagnósticos atrasados, '
                    'aplicações dos próximos 15 dias, pastos para trocar e animais em carência aparecem aqui.'),
              ),
            ...alertas,
            const SizedBox(height: 4),
            if (podeLancar) const _RotuloSecao('Modos de lançar'),
            if (podeLancar) const _BotaoModoCurral(),
            if (Db.podeGravar('reproducoes') && planoAtual().completo) const _BotaoModoInseminacao(),
            if (podeLancar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                    child: _Modo('Pesagem em série', Icons.monitor_weight_outlined, const Color(0xFF1565C0),
                        () => _abrir(const ManejoEmSerie(modo: ModoSerie.pesagem)))),
                const SizedBox(width: 8),
                if (Db.podeGravar('sanidade')) ...[
                  Expanded(
                      child: _Modo('Vacinação em série', Icons.vaccines_outlined, const Color(0xFF00796B),
                          () => _abrir(const ManejoEmSerie(modo: ModoSerie.sanidade)))),
                  const SizedBox(width: 8),
                ],
                Expanded(
                    child: _Modo('Lançar por voz', Icons.mic_none, const Color(0xFF6A1B9A),
                        () => _abrir(const LancamentoVozPage()))),
              ])),
            ),
            if (podeLancar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                    child: _Modo('Lançar do WhatsApp', Icons.chat_outlined, const Color(0xFF2E7D32),
                        () => _abrir(const LancarWhatsAppPage()))),
                const SizedBox(width: 8),
                Expanded(
                    child: _Modo('Lançar por foto ou PDF', Icons.document_scanner_outlined, const Color(0xFF5D4037),
                        () => _abrir(const LancarDocumentoPage()))),
              ])),
            ),
            const _RotuloSecao('Acesso rápido'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GridView.count(
                crossAxisCount: largo ? 4 : 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: largo ? 2.0 : 0.95,
                children: [
                  for (final (texto, icone, cor, secao, ir) in <(String, IconData, Color, int, VoidCallback)>[
                    ('Animais', Icons.pets, const Color(0xFF2E7D32), secRebanho, () => Nav.ir(secRebanho)),
                    ('Lotes', Icons.workspaces_outline, Cores.olivaEscuro, secLotes, () => Nav.ir(secLotes)),
                    ('Reprodução', Icons.favorite_border, const Color(0xFFAD1457), secReproducao,
                        () => Nav.ir(secReproducao)),
                    ('Sanidade', Icons.vaccines_outlined, const Color(0xFF00796B), secSanidade,
                        () => Nav.ir(secSanidade)),
                    ('Pesagem', Icons.monitor_weight_outlined, const Color(0xFF1565C0), secPesagem,
                        () => Nav.ir(secPesagem)),
                    ('Nascimentos', Icons.child_friendly_outlined, const Color(0xFF6A1B9A), secNascimentos,
                        () => Nav.ir(secNascimentos)),
                    ('Piquete/Pasto', Icons.fence, const Color(0xFF558B2F), secPiquetes, () => Nav.ir(secPiquetes)),
                    ('Mudar de pasto', Icons.swap_horiz, const Color(0xFF6D4C41),
                        Db.podeGravar('pastagens') ? secPiquetes : -1, () => _abrir(const MudarPastoPage())),
                    ('Pastagem', Icons.grass, const Color(0xFF33691E), secPastagem, () => Nav.ir(secPastagem)),
                    ('Compras', Icons.arrow_circle_down_outlined, const Color(0xFF00695C), secEntradas,
                        () => Nav.ir(secEntradas)),
                    ('Vendas', Icons.arrow_circle_up_outlined, Cores.alerta, secVendas, () => Nav.ir(secVendas)),
                    ('Chuva', Icons.water_drop_outlined, Cores.azul, secChuva, () => Nav.ir(secChuva)),
                    ('Fila do dia', Icons.format_list_bulleted, const Color(0xFFE65100), secTarefas,
                        () => _abrir(const FilaDoDiaPage())),
                    ('Tarefas', Icons.task_alt, const Color(0xFFEF6C00), secTarefas, () => Nav.ir(secTarefas)),
                    ('Relatórios', Icons.bar_chart, const Color(0xFF37474F), secRelatorios,
                        () => Nav.ir(secRelatorios)),
                  ])
                    if (podeVer(secao)) _Botao(texto, icone, cor, ir),
                ],
              ),
            ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cabeçalho verde do painel: total de cabeças e seis indicadores em vidro fosco.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.p, this.ir);
  final _Painel p;
  final VoidCallback? Function(int secao) ir;

  @override
  Widget build(BuildContext context) {
    final itens = <(String, String, Color, int)>[
      ('${p.lotes}', 'Lotes ativos', Cores.laranja, secLotes),
      ('${p.femeas} / ${p.machos}', 'Fêmeas / machos', const Color(0xFF8FD3FF), secRebanho),
      ('${p.prenhes}', 'Prenhes', const Color(0xFFFF9FB2), secReproducao),
      ('${p.partos.length}', 'Partos em 30 dias', const Color(0xFF8FD3FF), secReproducao),
      ('${p.carencia.length}', 'Em carência', const Color(0xFFFFB38A), secRelatorios),
      ('${p.avisosEstoque}', 'Avisos de estoque', Cores.laranja, secEstoque),
    ];
    return Container(
      color: Cores.olivaEscuro,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: ir(secRebanho),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('${p.ativos}',
                style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 10),
            Text(p.ativos == 1 ? 'cabeça' : 'cabeças',
                style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final colunas = c.maxWidth >= 700 ? 6 : 3;
          final largura = (c.maxWidth - 10 * (colunas - 1)) / colunas;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (valor, rotulo, cor, secao) in itens)
              SizedBox(width: largura, child: _Indicador(valor, rotulo, cor, ir(secao))),
          ]);
        }),
      ]),
    );
  }
}

/// Indicador do cabeçalho: fundo branco translúcido e filete colorido à esquerda.
class _Indicador extends StatelessWidget {
  const _Indicador(this.valor, this.rotulo, this.cor, this.onTap);
  final String valor, rotulo;
  final Color cor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: cor, width: 3))),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
            ),
            const SizedBox(height: 2),
            Text(rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// Rótulo de seção do painel, em letras pequenas e espaçadas.
class _RotuloSecao extends StatelessWidget {
  const _RotuloSecao(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Text(texto.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF55645B), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
      );
}

/// Cartão branco e suave, com sombra leve (base dos atalhos do painel).
class _CartaoSuave extends StatelessWidget {
  const _CartaoSuave({required this.onTap, required this.child, this.padding = const EdgeInsets.all(10)});
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x0F0B1F14), blurRadius: 12, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE6ECE8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Quadradinho claro com o ícone na cor do assunto.
class _IconeSuave extends StatelessWidget {
  const _IconeSuave(this.icone, this.cor, {this.tamanho = 56});
  final IconData icone;
  final Color cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(16)),
        child: Icon(icone, color: cor, size: tamanho * 0.5),
      );
}

/// Atalho da tela inicial: cartão branco, ícone colorido num quadrado claro e texto escuro.
class _Botao extends StatelessWidget {
  const _Botao(this.texto, this.icone, this.cor, this.onTap);
  final String texto;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CartaoSuave(
      onTap: onTap,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _IconeSuave(icone, cor),
          const SizedBox(height: 10),
          Text(texto,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF2A3530))),
        ],
      ),
    );
  }
}

/// Modo de trabalho em série (cartão médio, abaixo do Modo Curral e do Modo Inseminação).
class _Modo extends StatelessWidget {
  const _Modo(this.texto, this.icone, this.cor, this.onTap);
  final String texto;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CartaoSuave(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _IconeSuave(icone, cor, tamanho: 44),
        const SizedBox(height: 6),
        Text(texto,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(color: Color(0xFF2A3530), fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Previsão do tempo da fazenda no topo do painel: agora e os próximos 7 dias.
class _PrevisaoTopo extends StatefulWidget {
  const _PrevisaoTopo();

  @override
  State<_PrevisaoTopo> createState() => _PrevisaoTopoState();
}

class _PrevisaoTopoState extends State<_PrevisaoTopo> {
  static const _semanas = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  int _pid = -1;
  Future<Clima>? _f;

  void _carregar() {
    _pid = Db.pid;
    final local = localDaFazenda(_pid);
    _f = local == null ? null : buscarClima(local);
  }

  String _dia(String iso, int i) {
    if (i == 0) return 'Hoje';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : _semanas[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (Db.pid != _pid) _carregar();
    final f = _f;
    Widget cartao(Widget filho) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: _CartaoSuave(
            onTap: () => Nav.ir(secClima),
            padding: const EdgeInsets.all(14),
            child: filho,
          ),
        );
    const branco = TextStyle(color: Cores.tinta);
    if (f == null) {
      return cartao(const Row(children: [
        Icon(Icons.location_off_outlined, color: Cores.azul),
        SizedBox(width: 12),
        Expanded(child: Text('Previsão do tempo: toque para marcar a localização da fazenda.', style: branco)),
      ]));
    }
    return FutureBuilder<Clima>(
      future: f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return cartao(const SizedBox(
              height: 48, child: Center(child: CircularProgressIndicator())));
        }
        if (s.hasError || s.data == null) {
          return cartao(const Row(children: [
            Icon(Icons.cloud_off_outlined, color: Cores.azul),
            SizedBox(width: 12),
            Expanded(child: Text('Sem previsão agora. Confira a internet.', style: branco)),
          ]));
        }
        final c = s.data!;
        return cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(iconeTempo(c.codigo), size: 40, color: const Color(0xFFF2A900)),
            const SizedBox(width: 12),
            Text(c.temperatura == null ? '—' : '${c.temperatura!.round()}°C',
                style: const TextStyle(color: Cores.azul, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${descricaoTempo(c.codigo)}\nChuva em 7 dias: ${num1(c.chuva7Dias)} mm',
                  style: const TextStyle(color: Color(0xFF4D5A53), fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, d) in c.dias.take(7).indexed)
              Expanded(
                child: Column(children: [
                  Text(_dia(d.data, i), style: const TextStyle(color: Color(0xFF7A867F), fontSize: 12)),
                  Icon(iconeTempo(d.codigo), size: 20, color: Cores.azul),
                  Text('${d.max?.round() ?? '—'}°', style: const TextStyle(color: Cores.tinta, fontSize: 12)),
                  Text('${num1(d.chuvaMm ?? 0)}mm', style: const TextStyle(color: Color(0xFF1565C0), fontSize: 11)),
                ]),
              ),
          ]),
        ]));
      },
    );
  }
}

/// Atalho "Cotação da arroba", logo abaixo da previsão do tempo: abre o
/// quadro da B3 e os sites do Notícias Agrícolas e da Scot Consultoria.
class _AtalhoArroba extends StatelessWidget {
  const _AtalhoArroba();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: _CartaoSuave(
          onTap: () => mostrarCotacaoArroba(context),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: const Row(children: [
            _IconeSuave(Icons.trending_up, Cores.sucesso, tamanho: 46),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cotação da arroba',
                    style: TextStyle(fontSize: 17, color: Cores.tinta, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Boi gordo na B3 e nos sites de cotação',
                    style: TextStyle(fontSize: 13, color: Color(0xFF66736B))),
              ]),
            ),
            Icon(Icons.chevron_right, color: Color(0xFFB0B8B3), size: 28),
          ]),
        ),
      );
}

/// Atalho grande para o Modo Curral (lançar o serviço feito no curral).
class _BotaoModoCurral extends StatelessWidget {
  const _BotaoModoCurral();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: Cores.olivaEscuro,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: const AssetImage('assets/imagens/fundo_gado.jpg'),
              fit: BoxFit.cover,
              alignment: const Alignment(0.35, -0.2),
              colorFilter: ColorFilter.mode(Cores.olivaEscuro.withValues(alpha: 0.72), BlendMode.srcATop),
              onError: (_, __) {},
            ),
          ),
          child: InkWell(
            onTap: () => abrirModoCurral(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(children: [
                Icon(Icons.contactless_outlined, size: 52, color: Cores.laranja),
                SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MODO CURRAL',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('Pesagem, vacina, nascimento e saída com botões grandes e bastão.',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ]),
                ),
                Icon(Icons.chevron_right, color: Colors.white, size: 32),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Atalho para o Modo Inseminação, logo abaixo do Modo Curral.
class _BotaoModoInseminacao extends StatelessWidget {
  const _BotaoModoInseminacao();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Cores.azul,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => abrirModoInseminacao(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Icon(Icons.favorite_border, size: 44, color: Cores.laranja),
              SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('MODO INSEMINAÇÃO',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  SizedBox(height: 2),
                  Text('IA e IATF com baixa do sêmen, e diagnóstico em série.',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                ]),
              ),
              Icon(Icons.chevron_right, color: Colors.white, size: 32),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Aviso do limite de animais do plano (a partir de 90% do limite).
class _AvisoPlano extends StatelessWidget {
  const _AvisoPlano();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Db.changes,
      builder: (context, _, __) => ValueListenableBuilder<String?>(
        valueListenable: Db.planoDaFazenda,
        builder: (context, _, __) {
          final p = planoAtual();
          final n = animaisAtivos();
          final situacao = p.situacao(n);
          final conta = Plataforma.conta.value;
          final venceu = Db.ehDono && conta?['plano'] == 'Teste' && testeVencido(conta!, DateTime.now());
          if ((situacao == 'ok' && !venceu) || Db.ehCampo) return const SizedBox.shrink();
          final dias = diasParaTravar(hojeIso());
          final texto = situacao == 'ok'
              ? 'Seu teste de $diasDeTeste dias acabou. A fazenda segue no plano Simples (até '
                  '${PlanoEito.simples.maxAnimais} animais). Para liberar tudo, escolha um plano com o suporte.'
              : situacao == 'perto'
              ? 'Plano ${p.nome}: $n de ${p.maxAnimais} animais. Falta pouco para o limite.'
              : 'Plano ${p.nome}: $n animais, acima do limite de ${p.maxAnimais}. '
                  '${dias != null && dias > 0 ? 'Você ainda pode cadastrar por $dias dia(s); depois, só com um plano maior.' : 'Novos cadastros estão travados até mudar de plano.'}';
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Material(
              color: situacao == 'acima' ? Cores.alerta : Colors.orange.shade800,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text(texto, style: const TextStyle(color: Colors.white))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
