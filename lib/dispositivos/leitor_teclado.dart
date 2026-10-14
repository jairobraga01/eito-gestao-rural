import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Leitor de bastão RFID e de balança eletrônica via Bluetooth, no
/// "modo teclado" (HID).
///
/// Bastões e indicadores de balança com Bluetooth costumam ter um modo em que
/// são pareados como um teclado: a cada leitura eles "digitam" o número e
/// apertam Enter. Esse caminho funciona no iPhone, no Android e no computador,
/// sem instalar nada. É o único que funciona no iPhone pelo navegador,
/// porque o Safari não tem Web Bluetooth.
///
/// O que vem do aparelho é separado da digitação de uma pessoa pela
/// velocidade: máquina digita tudo em poucos milissegundos.
///
/// Uso: cada tela chama [assinar] ao abrir e o cancelamento devolvido ao
/// fechar. Só a tela mais recente (a do topo) recebe a leitura, para que um
/// peso lido na tela de pesagem não seja tratado como brinco na tela inicial.
class LeitorTeclado {
  LeitorTeclado._();
  static final LeitorTeclado instancia = LeitorTeclado._();

  final List<ValueChanged<String>> _ouvintes = [];
  final StringBuffer _buffer = StringBuffer();
  final List<int> _intervalos = [];
  DateTime? _ultimaTecla;
  bool _ativo = false;

  /// Intervalo médio máximo entre teclas para considerar que veio do aparelho.
  static const int msMaquina = 60;

  /// Última leitura recebida (para a tela de teste de dispositivos).
  final ValueNotifier<String?> ultimaLeitura = ValueNotifier(null);

  void iniciar() {
    if (_ativo) return;
    _ativo = true;
    HardwareKeyboard.instance.addHandler(_aoTeclar);
  }

  void parar() {
    if (!_ativo) return;
    _ativo = false;
    HardwareKeyboard.instance.removeHandler(_aoTeclar);
  }

  VoidCallback assinar(ValueChanged<String> aoLer) {
    _ouvintes.add(aoLer);
    return () => _ouvintes.remove(aoLer);
  }

  bool _aoTeclar(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final agora = DateTime.now();
    if (_ultimaTecla != null) {
      final ms = agora.difference(_ultimaTecla!).inMilliseconds;
      if (ms > 300) {
        _limpar(); // pausa longa: começa uma leitura nova
      } else {
        _intervalos.add(ms);
      }
    }
    _ultimaTecla = agora;

    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.tab) {
      final texto = _buffer.toString().trim();
      final media = _intervalos.isEmpty
          ? 9999.0
          : _intervalos.reduce((a, b) => a + b) / _intervalos.length;
      _limpar();
      if (texto.length >= 2 && media <= msMaquina) _entregar(texto);
      return false;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) _buffer.write(ch);
    return false; // não "come" a tecla: campos de texto continuam funcionando
  }

  void _entregar(String texto) {
    ultimaLeitura.value = texto;
    if (_ouvintes.isNotEmpty) _ouvintes.last(texto);
  }

  /// Para testes e para quem digita o número na mão.
  void simular(String texto) => _entregar(texto);

  void _limpar() {
    _buffer.clear();
    _intervalos.clear();
  }
}
