// Formatos usados no Modo Curral e na leitura de bastão/balança.

String dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String dataHoraBr(DateTime d) =>
    '${dataBr(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String numeroBr(double n, {int casas = 1}) {
  final texto = n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(casas);
  return texto.replaceAll('.', ',');
}

String pesoKg(double p) => '${numeroBr(p)} kg';

/// Lê um número digitado ou vindo da balança.
/// Aceita "450", "450,5", "1.250,5", "452.5 kg" e "ST,GS,+0452.5kg".
double? lerNumero(String texto) {
  var t = texto.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  final direto = double.tryParse(t);
  if (direto != null) return direto;
  // Texto com letras (balança): pega o primeiro número.
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
