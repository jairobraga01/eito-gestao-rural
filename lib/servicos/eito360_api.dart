import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP para a nova API do Eito 360.
/// Não habilitar até existir um tenant_id obtido por um fluxo seguro de adesão.
class Eito360Api {
  Eito360Api({required this.baseUrl, required this.tenantId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String tenantId;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, String>> _authOnlyHeaders({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Entre na sua conta antes de acessar o Eito 360.');
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) throw StateError('Não foi possível validar sua sessão.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  /// Cria uma conta rural, associa o usuário autenticado como proprietário e
  /// cadastra a primeira fazenda numa única transação no servidor.
  Future<Map<String, dynamic>> criarContaRural({required String nomeConta,
      required String nomeFazenda, String? municipio, String? estado}) async {
    final response = await _client.post(_uri('/api/onboarding'),
      headers: await _authOnlyHeaders(forceRefresh: true), body: jsonEncode({
        'tenant_name': nomeConta, 'farm_name': nomeFazenda,
        'municipality': municipio, 'state': estado,
      }));
    return _decode(response)['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listarMinhasContas() async {
    final response = await _client.get(_uri('/api/onboarding/my-tenants'), headers: await _authOnlyHeaders());
    return (_decode(response)['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Entre na sua conta antes de acessar o Eito 360.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('Não foi possível validar sua sessão.');
    if (tenantId.trim().isEmpty) throw StateError('O cliente da fazenda ainda não foi selecionado.');
    return {'Authorization': 'Bearer $token', 'X-Tenant-Id': tenantId,
      'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  Future<List<Map<String, dynamic>>> listarFazendas() async {
    final response = await _client.get(_uri('/api/farms'), headers: await _headers());
    return (_decode(response)['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> criarFazenda({required String nome, String? municipio,
      String? estado, double? areaHectares}) async {
    final response = await _client.post(_uri('/api/farms'), headers: await _headers(),
      body: jsonEncode({'name': nome, 'municipality': municipio, 'state': estado,
        'area_hectares': areaHectares}));
    return _decode(response)['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listarAnimais({String? fazendaId}) async {
    final response = await _client.get(_uri('/api/animals',
      fazendaId == null ? null : {'farm_id': fazendaId}), headers: await _headers());
    return (_decode(response)['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> criarAnimal({required String fazendaId,
      required String identificacao, String? nome, String? sexo, String? raca,
      String? nascimento, String status = 'active'}) async {
    final response = await _client.post(_uri('/api/animals'), headers: await _headers(),
      body: jsonEncode({'farm_id': fazendaId, 'tag': identificacao, 'name': nome,
        'sex': sexo, 'breed': raca, 'birth_date': nascimento, 'status': status}));
    return _decode(response)['data'] as Map<String, dynamic>;
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic parsed;
    try { parsed = jsonDecode(response.body); }
    catch (_) { throw StateError('A API retornou resposta inválida (HTTP ${response.statusCode}).'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = parsed is Map ? parsed['message'] : null;
      throw StateError(message?.toString() ?? 'Falha na API (HTTP ${response.statusCode}).');
    }
    if (parsed is! Map<String, dynamic>) throw StateError('Formato de resposta inesperado.');
    return parsed;
  }

  void close() => _client.close();
}
