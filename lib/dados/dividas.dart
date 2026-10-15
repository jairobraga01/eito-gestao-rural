// Dívidas da propriedade (parcelas) e ônus reais (garantias sobre os bens).
import 'db.dart';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _n(Object? v) => v is num ? v.toDouble() : 0;
String _t(Object? v) => v == null ? '' : '$v';

const tiposDivida = ['Custeio', 'Investimento', 'Comercialização', 'Empréstimo', 'Fornecedor', 'Arrendamento', 'Outra'];
const tiposOnus = ['Nenhum', 'Hipoteca', 'Alienação fiduciária', 'Penhor rural', 'Penhor pecuário', 'Penhor de safra', 'Aval/fiança', 'Outro'];

List<Reg> dividas() => [
      for (final d in Db.registros('dividas'))
        if (_int(d['propriedade_id']) == Db.pid) d,
    ]..sort((a, b) {
        final q = (quitada(a) ? 1 : 0).compareTo(quitada(b) ? 1 : 0);
        return q != 0 ? q : _t(proximaParcela(a)?['vencimento']).compareTo(_t(proximaParcela(b)?['vencimento']));
      });

List<Map<String, Object?>> parcelas(Reg d) => [
      for (final p in (d['parcelas'] as List?) ?? const []) Map<String, Object?>.from(p as Map),
    ];

/// Parcelas iguais a cada [intervaloMeses], a partir do primeiro vencimento.
List<Map<String, Object?>> gerarParcelas(double total, int quantidade, String primeiro, {int intervaloMeses = 12}) {
  if (quantidade <= 0) return [];
  final base = DateTime.parse(primeiro);
  final valor = (total / quantidade * 100).floorToDouble() / 100;
  return [
    for (var i = 0; i < quantidade; i++)
      {
        'vencimento': _iso(_somaMeses(base, i * intervaloMeses)),
        // A última leva os centavos que sobram.
        'valor': i == quantidade - 1 ? double.parse((total - valor * (quantidade - 1)).toStringAsFixed(2)) : valor,
        'pago': false,
      },
  ];
}

DateTime _somaMeses(DateTime d, int meses) {
  final m = d.month - 1 + meses;
  final ano = d.year + m ~/ 12, mes = m % 12 + 1;
  final ultimo = DateTime(ano, mes + 1, 0).day;
  return DateTime(ano, mes, d.day > ultimo ? ultimo : d.day);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double saldoDevedor(Reg d) => parcelas(d).where((p) => p['pago'] != true).fold(0, (s, p) => s + _n(p['valor']));
double totalPago(Reg d) => parcelas(d).where((p) => p['pago'] == true).fold(0, (s, p) => s + _n(p['valor']));
bool quitada(Reg d) => parcelas(d).isNotEmpty && parcelas(d).every((p) => p['pago'] == true);
Map<String, Object?>? proximaParcela(Reg d) {
  final abertas = parcelas(d).where((p) => p['pago'] != true).toList()
    ..sort((a, b) => _t(a['vencimento']).compareTo(_t(b['vencimento'])));
  return abertas.firstOrNull;
}

/// Ônus ainda valendo: dívida com garantia que não foi quitada nem baixada.
bool onusAtivo(Reg d) {
  final tipo = _t(d['onus']);
  return tipo.isNotEmpty && tipo != 'Nenhum' && !quitada(d) && d['onus_baixado'] != true;
}

class ParcelaAberta {
  ParcelaAberta(this.divida, this.indice, this.vencimento, this.valor);
  final Reg divida;
  final int indice;
  final String vencimento;
  final double valor;
}

/// Parcelas em aberto vencidas ou vencendo até [dias] dias depois de [hoje].
List<ParcelaAberta> parcelasAVencer(String hoje, {int dias = 90}) {
  final limite = _iso(DateTime.parse(hoje).add(Duration(days: dias)));
  final r = <ParcelaAberta>[];
  for (final d in dividas()) {
    final ps = parcelas(d);
    for (var i = 0; i < ps.length; i++) {
      final v = _t(ps[i]['vencimento']);
      if (ps[i]['pago'] != true && v.isNotEmpty && v.compareTo(limite) <= 0) r.add(ParcelaAberta(d, i, v, _n(ps[i]['valor'])));
    }
  }
  return r..sort((a, b) => a.vencimento.compareTo(b.vencimento));
}

/// Marca ou desmarca o pagamento de uma parcela.
Future<void> pagarParcela(Reg divida, int indice, bool pago, {String? data}) async {
  final ps = parcelas(divida);
  if (indice < 0 || indice >= ps.length) return;
  ps[indice] = {...ps[indice], 'pago': pago, 'pago_em': pago ? data : null};
  await Db.atualizar('dividas', _int(divida['id'])!, {'parcelas': ps});
}
