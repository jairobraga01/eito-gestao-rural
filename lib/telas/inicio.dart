// Painel: busca, indicadores, atalhos grandes e alertas da propriedade.
import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/estoque.dart' show alertasEstoque;
import '../tema.dart';
import '../util/util.dart';
import 'animais.dart';
import 'base.dart';
import 'relatorios.dart' show partosPrevistos, diagnosticosAtrasados, aplicacoesProximas, animaisEmCarencia;
import 'reproducao.dart';
import 'sanidade.dart';

class _Painel {
  int ativos = 0, femeas = 0, machos = 0, prenhes = 0, lotes = 0, avisosEstoque = 0;
  List<Reg> partos = [], diagnosticos = [], aplicacoes = [], carencia = [];
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
  return p;
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  String busca = '';

  void _abrir(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

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
          for (final r in p.partos)
            ListTile(
              leading: Icon(Icons.child_friendly_outlined,
                  color: txt(r['parto_previsto']).compareTo(hoje) < 0 ? Colors.red : Colors.blue),
              title: Text('Parto previsto: ${rotulo(r)}'),
              subtitle: Text(br(r['parto_previsto'])),
              onTap: () => _abrir(NascimentoFormPage(
                  mae: {'id': r['femea_id'], 'brinco': r['brinco'], 'nome': r['nome']}, reproducao: r)),
            ),
          for (final r in p.diagnosticos)
            ListTile(
              leading: const Icon(Icons.hourglass_empty, color: Colors.orange),
              title: Text('Fazer diagnóstico: ${rotulo(r)}'),
              subtitle: Text('${txt(r['tipo'])} em ${br(r['data'])}'),
              onTap: () => _abrir(ReproducaoFormPage(registro: r)),
            ),
          for (final s in p.aplicacoes)
            ListTile(
              leading: Icon(Icons.vaccines_outlined,
                  color: txt(s['proxima']).compareTo(hoje) < 0 ? Colors.red : Colors.teal),
              title: Text('${s['produto']} – ${s['qtd']} animal(is)'),
              subtitle: Text(
                  '${txt(s['proxima']).compareTo(hoje) < 0 ? 'Atrasada desde' : 'Prevista para'} ${br(s['proxima'])}'),
              onTap: () => _abrir(const SanidadeFormPage()),
            ),
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const _BotaoModoCurral(),
            const _BotaoModoInseminacao(),
            SizedBox(
              height: 128,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _Indicador('${p.lotes}', 'Lotes', Icons.workspaces_outline, () => Nav.ir(secLotes)),
                  _Indicador('${p.ativos}', 'Animais', Icons.pets, () => Nav.ir(secRebanho)),
                  _Indicador('${p.femeas} / ${p.machos}', 'Fêmeas / machos', Icons.wc, () => Nav.ir(secRebanho)),
                  _Indicador('${p.prenhes}', 'Prenhes', Icons.favorite, () => Nav.ir(secReproducao)),
                  _Indicador('${p.carencia.length}', 'Em carência', Icons.block, () => Nav.ir(secRelatorios)),
                  _Indicador('${p.avisosEstoque}', 'Avisos de estoque', Icons.inventory_2_outlined, () => Nav.ir(secEstoque)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 2.4 : 1.6,
                children: [
                  _Botao('Animal', Icons.pets, () => Nav.ir(secRebanho)),
                  _Botao('Lote', Icons.workspaces_outline, () => Nav.ir(secLotes)),
                  _Botao('Reprodução', Icons.favorite_border, () => Nav.ir(secReproducao)),
                  _Botao('Sanidade', Icons.vaccines_outlined, () => Nav.ir(secSanidade)),
                  _Botao('Piquete/Pasto', Icons.fence, () => Nav.ir(secPiquetes)),
                  _Botao('Pastagem', Icons.grass, () => Nav.ir(secPastagem)),
                ],
              ),
            ),
            Secao('Alertas (${alertas.length})'),
            if (alertas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Nada pendente. Partos dos próximos 30 dias, diagnósticos atrasados e '
                    'aplicações dos próximos 15 dias aparecem aqui.'),
              ),
            ...alertas,
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
  final VoidCallback onTap;

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

class _Botao extends StatelessWidget {
  const _Botao(this.texto, this.icone, this.onTap);
  final String texto;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 44, color: cs.primary),
            const SizedBox(height: 10),
            Text(texto.toUpperCase(),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
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
