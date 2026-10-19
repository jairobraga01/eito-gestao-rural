import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _ponte => globalContext['eitoInstalar'] as JSObject?;

/// Verdadeiro quando o navegador deixa instalar (ou é iPhone, que se instala à mão).
bool get instalacaoDisponivel {
  try {
    return _ponte?.callMethod<JSBoolean>('pode'.toJS).toDart ?? false;
  } catch (_) {
    return false;
  }
}

bool get instalacaoIos {
  try {
    return (_ponte?['ios'] as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Avisa quando o navegador libera a instalação ou o app termina de instalar.
void aoMudarInstalacao(void Function() f) {
  try {
    (globalContext['window'] as JSObject).callMethod<JSAny?>('addEventListener'.toJS, 'eito-instalar'.toJS, (() => f()).toJS);
  } catch (_) {}
}

/// Abre o convite de instalação do navegador. Devolve 'accepted', 'dismissed' ou 'manual'.
Future<String> instalarApp() async {
  try {
    final r = await _ponte!.callMethod<JSPromise<JSString>>('instalar'.toJS).toDart;
    return r.toDart;
  } catch (_) {
    return 'manual';
  }
}
