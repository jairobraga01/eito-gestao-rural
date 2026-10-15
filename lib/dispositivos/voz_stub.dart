/// Fora do navegador não há reconhecimento de voz.
bool get vozDisponivel => false;

Future<(String?, String?)> ouvirFrase() async => (null, 'Reconhecimento de voz indisponível.');
