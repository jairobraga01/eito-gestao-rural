// Numeração automática para o gado que entra sem brinco (rebanho que já
// estava na fazenda, compra de bezerros sem identificação...).
// Ex.: vaca_fazenda_001, novilha_fazenda_002, bezerra_compra25OUT2026_001.
import 'db.dart';

const _meses = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

/// Texto em minúsculas, sem acento e só com letras e números.
String _limpo(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ', para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = de.indexOf(c);
    final x = i >= 0 ? para[i] : c;
    if (RegExp('[a-z0-9]').hasMatch(x)) b.write(x);
  }
  return b.toString();
}

/// Data ISO no formato 25OUT2026.
String dataCurta(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}${_meses[d.month - 1]}${d.year}';
}

/// Prefixo sugerido: categoria + de onde veio (+ data, quando não é rebanho da fazenda).
String prefixoSugerido({String? categoria, required String sexo, required String tipo, required String data}) {
  final cat = _limpo(categoria ?? (sexo == 'F' ? 'femea' : 'macho'));
  final origem = switch (tipo) {
    'Rebanho existente' => 'fazenda',
    'Compra' => 'compra${dataCurta(data)}',
    'Transferência' => 'transf${dataCurta(data)}',
    'Doação' => 'doacao${dataCurta(data)}',
    _ => 'entrada${dataCurta(data)}',
  };
  return '${cat}_$origem';
}

/// Próximo número livre para o prefixo nesta propriedade (continua a contagem).
int proximoNumero(String prefixo) {
  final p = '${prefixo.trim().toLowerCase()}_';
  var maior = 0;
  for (final a in Db.registros('animais')) {
    if (a['propriedade_id'] != Db.pid) continue;
    final b = '${a['brinco'] ?? ''}'.toLowerCase();
    if (!b.startsWith(p)) continue;
    final n = int.tryParse(b.substring(p.length));
    if (n != null && n > maior) maior = n;
  }
  return maior + 1;
}

/// Brincos gerados: prefixo_001, prefixo_002... (no mínimo 3 dígitos).
List<String> gerarBrincos(String prefixo, int inicio, int quantidade) {
  final p = prefixo.trim();
  final digitos = '${inicio + quantidade - 1}'.length.clamp(3, 9);
  return [for (var i = 0; i < quantidade; i++) '${p}_${'${inicio + i}'.padLeft(digitos, '0')}'];
}
