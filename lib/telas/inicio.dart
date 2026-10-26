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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'BUSCAR ANIMAL',
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
          padding: const EdgeInsets.only(bottom: 88),
          children: [
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
            const SizedBox(height: 12),
            if (podeLancar) const _BotaoModoCurral(),
            if (Db.podeGravar('reproducoes') && planoAtual().completo) const _BotaoModoInseminacao(),
            if (podeLancar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
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
              ]),
            ),
            if (podeLancar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                Expanded(
                    child: _Modo('Lançar do WhatsApp', Icons.chat_outlined, const Color(0xFF2E7D32),
                        () => _abrir(const LancarWhatsAppPage()))),
                const SizedBox(width: 8),
                Expanded(
                    child: _Modo('Lançar por foto ou PDF', Icons.document_scanner_outlined, const Color(0xFF5D4037),
                        () => _abrir(const LancarDocumentoPage()))),
              ]),
            ),
            SizedBox(
              height: 128,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _Indicador('${p.lotes}', 'Lotes', Icons.workspaces_outline, _ir(secLotes)),
                  _Indicador('${p.ativos}', 'Animais', Icons.pets, _ir(secRebanho)),
                  _Indicador('${p.femeas} / ${p.machos}', 'Fêmeas / machos', Icons.wc, _ir(secRebanho)),
                  _Indicador('${p.prenhes}', 'Prenhes', Icons.favorite, _ir(secReproducao)),
                  _Indicador('${p.carencia.length}', 'Em carência', Icons.block, _ir(secRelatorios)),
                  _Indicador('${p.avisosEstoque}', 'Avisos de estoque', Icons.inventory_2_outlined, _ir(secEstoque)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: largo ? 4 : 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: largo ? 2.0 : 1.05,
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
          ],
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador(this.valor, this.rotulo, this.icone, this.onTap);
  final String valor, rotulo;
  final IconData icone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 132,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: cs.primary),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                ),
                Text(rotulo.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.outline, letterSpacing: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Atalho colorido da tela inicial (fundo na cor do assunto, ícone e texto brancos).
class _Botao extends StatelessWidget {
  const _Botao(this.texto, this.icone, this.cor, this.onTap);
  final String texto;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor,
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 36, color: Colors.white),
              const SizedBox(height: 6),
              Text(texto.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modo de trabalho em série (botão médio, abaixo do Modo Curral e do Modo Inseminação).
class _Modo extends StatelessWidget {
  const _Modo(this.texto, this.icone, this.cor, this.onTap);
  final String texto;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(children: [
            Icon(icone, size: 32, color: Cores.laranja),
            const SizedBox(height: 4),
            Text(texto.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
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
          child: Material(
            color: Cores.azul,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Nav.ir(secClima),
              child: Padding(padding: const EdgeInsets.all(14), child: filho),
            ),
          ),
        );
    const branco = TextStyle(color: Colors.white);
    if (f == null) {
      return cartao(const Row(children: [
        Icon(Icons.location_off_outlined, color: Cores.laranja),
        SizedBox(width: 12),
        Expanded(child: Text('Previsão do tempo: toque para marcar a localização da fazenda.', style: branco)),
      ]));
    }
    return FutureBuilder<Clima>(
      future: f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return cartao(const SizedBox(
              height: 48, child: Center(child: CircularProgressIndicator(color: Colors.white))));
        }
        if (s.hasError || s.data == null) {
          return cartao(const Row(children: [
            Icon(Icons.cloud_off_outlined, color: Cores.laranja),
            SizedBox(width: 12),
            Expanded(child: Text('Sem previsão agora. Confira a internet.', style: branco)),
          ]));
        }
        final c = s.data!;
        return cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(iconeTempo(c.codigo), size: 40, color: Cores.laranja),
            const SizedBox(width: 12),
            Text(c.temperatura == null ? '—' : '${c.temperatura!.round()}°C',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${descricaoTempo(c.codigo)}\nChuva em 7 dias: ${num1(c.chuva7Dias)} mm',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, d) in c.dias.take(7).indexed)
              Expanded(
                child: Column(children: [
                  Text(_dia(d.data, i), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Icon(iconeTempo(d.codigo), size: 20, color: Colors.white),
                  Text('${d.max?.round() ?? '—'}°', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text('${num1(d.chuvaMm ?? 0)}mm', style: const TextStyle(color: Cores.laranja, fontSize: 11)),
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
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Material(
          elevation: 3,
          shadowColor: const Color(0xFF1B5E20),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: InkWell(
              onTap: () => mostrarCotacaoArroba(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.trending_up, color: Color(0xFF2E7D32), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Cotação da arroba',
                          style: TextStyle(fontSize: 19, color: Colors.white, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Boi gordo na B3 e nos sites de cotação',
                          style: TextStyle(fontSize: 13, color: Color(0xFFE8F5E9))),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white, size: 30),
                ]),
              ),
            ),
          ),
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
