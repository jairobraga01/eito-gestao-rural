String dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String dataHoraBr(DateTime d) =>
    '${dataBr(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String numeroBr(double n, {int casas = 1}) {
  final texto = n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(casas);
  return texto.replaceAll('.', ',');
}

String pesoKg(double p) => '${numeroBr(p)} kg';

/// Primeiro número de um texto. Aceita vírgula ou ponto e o formato que as
/// balanças mandam, por exemplo "452,5", "452.5 kg" ou "ST,GS,+0452.5kg".
double? lerNumero(String texto) {
  final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(texto);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

/// Leitura de balança formatada para o visor ("452,5").
String? leituraParaVisor(String leitura) {
  final n = lerNumero(leitura);
  return n == null ? null : numeroBr(n);
}

/// Uma leitura parece peso (balança) e não brinco (RFID tem 15 dígitos)?
bool parecePeso(String leitura) {
  final digitos = leitura.replaceAll(RegExp(r'\D'), '');
  return lerNumero(leitura) != null && digitos.isNotEmpty && digitos.length <= 6;
}

String idade(DateTime nascimento) {
  final hoje = DateTime.now();
  var meses = (hoje.year - nascimento.year) * 12 + hoje.month - nascimento.month;
  if (hoje.day < nascimento.day) meses--;
  if (meses < 1) return '${hoje.difference(nascimento).inDays} dias';
  if (meses < 24) return '$meses ${meses == 1 ? 'mês' : 'meses'}';
  final anos = meses ~/ 12, resto = meses % 12;
  return resto == 0 ? '$anos anos' : '$anos anos e $resto m';
}
