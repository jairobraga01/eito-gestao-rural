import 'package:geolocator/geolocator.dart';

/// Posição atual do aparelho (lat, lng), ou null sem permissão ou sem sinal de GPS.
/// O texto de [erro] diz o motivo para mostrar na tela.
Future<({double lat, double lng})?> minhaPosicao({void Function(String erro)? erro}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      erro?.call('Ligue a localização (GPS) do aparelho.');
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      erro?.call('Permita o acesso à localização para o Eito nos ajustes do navegador.');
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    return (lat: p.latitude, lng: p.longitude);
  } catch (e) {
    erro?.call('Não foi possível pegar a posição: $e');
    return null;
  }
}
