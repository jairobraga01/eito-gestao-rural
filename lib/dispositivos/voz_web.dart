import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Reconhecimento de voz do navegador (Chrome, Edge e Safari), em português.
bool get vozDisponivel => globalContext.has('SpeechRecognition') || globalContext.has('webkitSpeechRecognition');

/// Ouve uma frase. Retorna (texto, erro).
Future<(String?, String?)> ouvirFrase() {
  final c = Completer<(String?, String?)>();
  try {
    final ctor = (globalContext.has('SpeechRecognition')
        ? globalContext['SpeechRecognition']
        : globalContext['webkitSpeechRecognition']) as JSFunction;
    final rec = ctor.callAsConstructor<JSObject>();
    rec['lang'] = 'pt-BR'.toJS;
    rec['interimResults'] = false.toJS;
    rec['maxAlternatives'] = 1.toJS;
    rec['onresult'] = ((JSObject e) {
      final resultados = e['results'] as JSObject;
      final primeiro = resultados.callMethod<JSObject>('item'.toJS, 0.toJS).callMethod<JSObject>('item'.toJS, 0.toJS);
      final texto = (primeiro['transcript'] as JSString).toDart;
      if (!c.isCompleted) c.complete((texto, null));
    }).toJS;
    rec['onerror'] = ((JSObject e) {
      final erro = (e['error'] as JSString?)?.toDart ?? '';
      final msg = switch (erro) {
        'not-allowed' || 'service-not-allowed' => 'O navegador não deixou usar o microfone. Libere o microfone para o site.',
        'no-speech' => 'Não ouvi nada. Toque de novo e fale perto do celular.',
        'network' => 'O reconhecimento de voz precisa de internet.',
        _ => 'Não entendi ($erro).',
      };
      if (!c.isCompleted) c.complete((null, msg));
    }).toJS;
    rec['onend'] = ((JSAny? _) {
      if (!c.isCompleted) c.complete((null, 'Não ouvi nada. Toque de novo e fale perto do celular.'));
    }).toJS;
    rec.callMethod<JSAny?>('start'.toJS);
  } catch (e) {
    if (!c.isCompleted) c.complete((null, 'Reconhecimento de voz indisponível: $e'));
  }
  return c.future;
}
