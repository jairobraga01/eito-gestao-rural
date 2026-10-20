// Cotação do boi gordo na B3 (pregão regular), gravada todo dia pelo GitHub
// Actions em mercado/boi_gordo_b3 (ver .github/workflows/cotacao-b3.yml).
import 'db.dart';

const siteScotBoi = 'https://www.scotconsultoria.com.br/cotacoes/boi-gordo/';
const siteNoticiasBoi = 'https://www.noticiasagricolas.com.br/cotacoes/boi-gordo';
const siteNoticiasB3 = 'https://www.noticiasagricolas.com.br/cotacoes/boi-gordo/boi-gordo-b3-prego-regular';

class LinhaB3 {
  LinhaB3(this.contrato, this.fechamento, this.variacao);
  final String contrato;
  final double fechamento;
  final double? variacao;
}

class CotacaoB3 {
  CotacaoB3(this.linhas, this.atualizado, this.fonte);
  final List<LinhaB3> linhas;

  /// Data do fechamento (dd/mm/aaaa), como vem do site.
  final String atualizado;
  final String fonte;

  static CotacaoB3? deMapa(Map<String, dynamic>? m) {
    final l = m?['linhas'];
    if (l is! List || l.isEmpty) return null;
    final linhas = <LinhaB3>[
      for (final x in l)
        if (x is Map && x['fechamento'] is num)
          LinhaB3('${x['contrato'] ?? ''}', (x['fechamento'] as num).toDouble(),
              x['variacao'] is num ? (x['variacao'] as num).toDouble() : null),
    ];
    if (linhas.isEmpty) return null;
    return CotacaoB3(linhas, '${m!['atualizado'] ?? ''}', '${m['fonte'] ?? 'B3'}');
  }
}

/// Última cotação da B3 (null sem internet ou se ainda não foi gravada).
Future<CotacaoB3?> buscarCotacaoB3() async {
  try {
    final s = await Db.banco.collection('mercado').doc('boi_gordo_b3').get();
    return CotacaoB3.deMapa(s.data());
  } catch (_) {
    return null;
  }
}
