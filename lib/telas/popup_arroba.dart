// Pop-up da cotação da arroba no estilo do quadro da B3: contratos por mês,
// fechamento em R$/@ e variação. Abre pelo atalho do Painel e uma vez por dia.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dados/mercado.dart';
import '../dados/proteinado.dart' show cotacoes;
import '../util/util.dart';
import 'cotacao_arroba.dart';

const _cinzaTopo = Color(0xFF3A3D3E);
const _cinzaFaixa = Color(0xFFF1F1F1);
const _cinzaRodape = Color(0xFFE9EAEC);
const _ouro = Color(0xFF94621F);
const _laranja = Color(0xFFF0A24A);

void _abrirSite(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Mostra o pop-up (busca a B3 na hora).
Future<void> mostrarCotacaoArroba(BuildContext context) async {
  final b3 = await buscarCotacaoB3();
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _PopupArroba(b3));
}

/// Abre o pop-up uma vez por dia, quando há cotação da B3 nova.
Future<void> popupArrobaDoDia(BuildContext context) async {
  final b3 = await buscarCotacaoB3();
  if (b3 == null || !context.mounted) return;
  try {
    final p = await SharedPreferences.getInstance();
    final hoje = hojeIso();
    if (p.getString('popup_arroba') == hoje) return;
    await p.setString('popup_arroba', hoje);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _PopupArroba(b3));
}

class _PopupArroba extends StatelessWidget {
  const _PopupArroba(this.b3);
  final CotacaoB3? b3;

  @override
  Widget build(BuildContext context) {
    final propria = cotacoes().firstOrNull;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF222222), fontSize: 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _cinzaTopo, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/imagens/fundo_gado.jpg')),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Boi Gordo - B3 (Pregão Regular)', style: TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('Fonte: ${b3?.fonte ?? 'B3'}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                color: _cinzaFaixa,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                child: const Row(children: [
                  Expanded(flex: 4, child: Text('Contrato - Mês', style: TextStyle(color: _ouro, fontWeight: FontWeight.w600))),
                  Expanded(
                      flex: 4,
                      child: Text('Fechamento (R\$/@)',
                          textAlign: TextAlign.center, style: TextStyle(color: _ouro, fontWeight: FontWeight.w600))),
                  Expanded(
                      flex: 3,
                      child: Text('Variação (%)',
                          textAlign: TextAlign.center, style: TextStyle(color: _ouro, fontWeight: FontWeight.w600))),
                ]),
              ),
              if (b3 == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Sem a cotação da B3 agora. Confira a internet ou veja nos sites abaixo.'),
                )
              else
                for (final (i, l) in b3!.linhas.indexed) ...[
                  if (i > 0) const _Pontilhado(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                    child: Row(children: [
                      Expanded(flex: 4, child: Text(l.contrato)),
                      Expanded(flex: 4, child: Text(numeroBr(l.fechamento, casas: 2), textAlign: TextAlign.center)),
                      Expanded(
                        flex: 3,
                        child: Text(l.variacao == null ? '—' : numeroBr(l.variacao!, casas: 2),
                            textAlign: TextAlign.center),
                      ),
                    ]),
                  ),
                ],
              Container(
                color: _cinzaRodape,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Row(children: [
                  Expanded(child: Text('Atualizado em: ${b3?.atualizado.isNotEmpty == true ? b3!.atualizado : '—'}')),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _laranja,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: () => _abrirSite(siteNoticiasB3),
                    child: const Text('VER HISTÓRICO', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  ),
                ]),
              ),
              if (propria != null)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.edit_note, color: Color(0xFF2E7D32)),
                  title: Text('Sua arroba lançada: ${moeda(propria['valor'] as num)}/@'),
                  subtitle: Text('${br(propria['data'])}${txt(propria['praca']).isEmpty ? '' : ' · ${propria['praca']}'}'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CotacaoArrobaPage()));
                  },
                ),
              const SizedBox(height: 8),
              const Text('Ver a cotação nos sites:', style: TextStyle(fontSize: 14, color: Color(0xFF555555))),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Notícias Agrícolas'),
                  onPressed: () => _abrirSite(siteNoticiasBoi),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Scot Consultoria'),
                  onPressed: () => _abrirSite(siteScotBoi),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Linha pontilhada entre os contratos.
class _Pontilhado extends StatelessWidget {
  const _Pontilhado();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Row(
          children: List.generate(
            (c.maxWidth / 4).floor(),
            (_) => Container(width: 2, height: 1.4, margin: const EdgeInsets.only(right: 2), color: const Color(0xFFBDBDBD)),
          ),
        ),
      );
}
