import 'package:flutter/services.dart';

/// Número de celular brasileiro sem o DDD: 9 dígitos, com o traço depois do quinto (99928-5293).
class FormatoNumeroTelefone extends TextInputFormatter {
  const FormatoNumeroTelefone();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    var d = novo.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 9) d = d.substring(0, 9);
    final t = d.length > 5 ? '${d.substring(0, 5)}-${d.substring(5)}' : d;
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Telefone completo "(62) 99928-5293" a partir do DDD e do número; null se incompleto.
String? telefoneBr(String ddd, String numero) {
  final dd = ddd.replaceAll(RegExp(r'\D'), ''), n = numero.replaceAll(RegExp(r'\D'), '');
  if (dd.length != 2 || n.length < 8 || n.length > 9) return null;
  return '($dd) ${n.length == 9 ? '${n.substring(0, 5)}-${n.substring(5)}' : '${n.substring(0, 4)}-${n.substring(4)}'}';
}
