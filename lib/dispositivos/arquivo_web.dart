import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Baixa um arquivo de texto pelo navegador. Retorna false se não der.
bool baixarArquivo(String nome, String conteudo, {String tipo = 'text/plain'}) {
  try {
    final bytes = Uint8List.fromList(utf8.encode(conteudo));
    final opcoes = JSObject()..['type'] = '$tipo;charset=utf-8'.toJS;
    final blob = (globalContext['Blob'] as JSFunction).callAsConstructor<JSObject>([bytes.toJS].toJS, opcoes);
    final url = globalContext['URL'] as JSObject;
    final endereco = url.callMethod<JSString>('createObjectURL'.toJS, blob);
    final doc = globalContext['document'] as JSObject;
    final a = doc.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
    a['href'] = endereco;
    a['download'] = nome.toJS;
    (doc['body'] as JSObject).callMethod<JSAny?>('appendChild'.toJS, a);
    a.callMethod<JSAny?>('click'.toJS);
    a.callMethod<JSAny?>('remove'.toJS);
    url.callMethod<JSAny?>('revokeObjectURL'.toJS, endereco);
    return true;
  } catch (_) {
    return false;
  }
}
