import 'dart:async';
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

/// Abre a janela de escolher arquivo e devolve o texto dele (null se cancelar).
Future<String?> escolherArquivoTexto({String aceitar = '.json'}) {
  final c = Completer<String?>();
  try {
    final doc = globalContext['document'] as JSObject;
    final input = doc.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
    input['type'] = 'file'.toJS;
    input['accept'] = aceitar.toJS;
    Future<void> ler() async {
      try {
        final files = input['files'] as JSObject?;
        final f = files?.callMethod<JSObject?>('item'.toJS, 0.toJS);
        if (f == null) {
          if (!c.isCompleted) c.complete(null);
          return;
        }
        final t = await f.callMethod<JSPromise<JSString>>('text'.toJS).toDart;
        if (!c.isCompleted) c.complete(t.toDart);
      } catch (_) {
        if (!c.isCompleted) c.complete(null);
      }
    }

    input.callMethod<JSAny?>('addEventListener'.toJS, 'change'.toJS, ((JSAny _) {
      ler();
    }).toJS);
    input.callMethod<JSAny?>('addEventListener'.toJS, 'cancel'.toJS, ((JSAny _) {
      if (!c.isCompleted) c.complete(null);
    }).toJS);
    input.callMethod<JSAny?>('click'.toJS);
  } catch (_) {
    if (!c.isCompleted) c.complete(null);
  }
  return c.future;
}

/// Abre a impressão do navegador com [html] (onde dá para "Salvar como PDF").
bool imprimirHtml(String html) {
  try {
    final doc = globalContext['document'] as JSObject;
    final f = doc.callMethod<JSObject>('createElement'.toJS, 'iframe'.toJS);
    final estilo = f['style'] as JSObject;
    estilo['position'] = 'fixed'.toJS;
    estilo['right'] = '0'.toJS;
    estilo['bottom'] = '0'.toJS;
    estilo['width'] = '0'.toJS;
    estilo['height'] = '0'.toJS;
    estilo['border'] = '0'.toJS;
    f.callMethod<JSAny?>('addEventListener'.toJS, 'load'.toJS, ((JSAny _) {
      final w = f['contentWindow'] as JSObject;
      w.callMethod<JSAny?>('focus'.toJS);
      w.callMethod<JSAny?>('print'.toJS);
      // Tira o quadro um tempo depois (o Safari imprime de forma assíncrona).
      Timer(const Duration(minutes: 1), () => f.callMethod<JSAny?>('remove'.toJS));
    }).toJS);
    f['srcdoc'] = html.toJS;
    (doc['body'] as JSObject).callMethod<JSAny?>('appendChild'.toJS, f);
    return true;
  } catch (_) {
    return false;
  }
}
