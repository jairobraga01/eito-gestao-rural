/// Fora do navegador o app já está instalado.
bool get instalacaoDisponivel => false;

bool get instalacaoIos => false;

void aoMudarInstalacao(void Function() f) {}

Future<String> instalarApp() async => 'indisponivel';
