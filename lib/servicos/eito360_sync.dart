import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'eito360_local_store.dart';

/// Fila persistente e sincronização incremental para fazendas/animais.
/// A fila é armazenada no dispositivo; use um armazenamento protegido para dados
/// sensíveis e não a trate como substituta de backups ou migração dos módulos legados.
class Eito360Sync {
  Eito360Sync({required this.baseUrl, required this.tenantId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String tenantId;
  final http.Client _client;
  static const _queueKeyPrefix = 'eito360.sync.queue.v1.';
  static const _cursorKeyPrefix = 'eito360.sync.cursor.v1.';
  static const _deviceKeyPrefix = 'eito360.sync.device_key.v1.';
  static const _deviceIdKeyPrefix = 'eito360.sync.device_id.v1.';

  String get _scope => '${FirebaseAuth.instance.currentUser?.uid ?? 'anonymous'}.$tenantId';
  String get _queueKey => '$_queueKeyPrefix$_scope';
  String get _cursorKey => '$_cursorKeyPrefix$_scope';
  String get _deviceKeyKey => '$_deviceKeyPrefix$_scope';
  String get _deviceIdKey => '$_deviceIdKeyPrefix$_scope';

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Entre na sua conta antes de sincronizar.');
    if (tenantId.trim().isEmpty) throw StateError('Selecione uma conta rural.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('Não foi possível validar a sessão.');
    return {'Authorization': 'Bearer $token', 'X-Tenant-Id': tenantId,
      'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic body;
    try { body = jsonDecode(response.body); } catch (_) { throw StateError('Resposta inválida da API (HTTP ${response.statusCode}).'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body is Map ? (body['message']?.toString() ?? 'Erro HTTP ${response.statusCode}') : 'Erro HTTP ${response.statusCode}');
    }
    if (body is! Map<String, dynamic>) throw StateError('Formato de resposta inesperado.');
    return body;
  }

  String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<List<Map<String, dynamic>>> _readQueue(Eito360LocalStore prefs) async {
    final raw = await prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw StateError('Fila local corrompida; não foi apagada para preservar os dados.');
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _saveQueue(Eito360LocalStore prefs, List<Map<String, dynamic>> queue) async {
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  /// Registra operação local. Requer UUID local estável; em criação, entity_local_id
  /// pode ser um identificador local não-UUID, que será mapeado ao id retornado pelo servidor.
  Future<String> enfileirar({required String entityType, required String operation,
      required String localId, required Map<String, dynamic> payload}) async {
    if (!['farm', 'animal'].contains(entityType)) throw ArgumentError('Tipo de registro não suportado pela sincronização atual.');
    if (!['create', 'update', 'delete'].contains(operation)) throw ArgumentError('Operação inválida.');
    if (localId.trim().isEmpty) throw ArgumentError('Informe o identificador local.');
    final prefs = await Eito360LocalStore.open();
    final queue = await _readQueue(prefs);
    final id = _uuid();
    queue.add({'id': id, 'entity_type': entityType, 'operation': operation,
      'entity_local_id': localId, 'payload': payload, 'status': 'pending',
      'queued_at': DateTime.now().toUtc().toIso8601String()});
    await _saveQueue(prefs, queue);
    return id;
  }

  Future<Map<String, dynamic>> _ensureDevice(Eito360LocalStore prefs) async {
    var deviceKey = await prefs.getString(_deviceKeyKey);
    if (deviceKey == null || deviceKey.length < 8) {
      deviceKey = _uuid() + _uuid().replaceAll('-', '');
      await prefs.setString(_deviceKeyKey, deviceKey);
    }
    final response = await _client.post(_uri('/api/sync/device'), headers: await _headers(),
      body: jsonEncode({'device_key': deviceKey, 'label': 'Dispositivo Eito 360'}));
    final data = _decode(response)['data'] as Map<String, dynamic>;
    await prefs.setString(_deviceIdKey, data['id'].toString());
    return data;
  }

  /// Envia até 100 operações pendentes por chamada. Operações conflitantes/rejeitadas
  /// permanecem na fila com status explícito para revisão, não são descartadas.
  Future<Map<String, dynamic>> enviarPendentes() async {
    final prefs = await Eito360LocalStore.open();
    final device = await _ensureDevice(prefs);
    final queue = await _readQueue(prefs);
    final pending = queue.where((op) => op['status'] == 'pending').toList()
      ..sort((a, b) => (a['entity_type'] == 'farm' ? 0 : 1).compareTo(b['entity_type'] == 'farm' ? 0 : 1));
    final batch = pending.take(100).toList();
    if (batch.isEmpty) return {'sent': 0, 'applied': 0, 'blocked': 0};
    final wireOps = <Map<String, dynamic>>[];
    final skippedDependencies = <String>{};
    for (final op in batch) {
      final payload = Map<String, dynamic>.from(op['payload'] as Map);
      if (op['entity_type'] == 'animal' && op['operation'] == 'create') {
        final farmId = payload['farm_id']?.toString() ?? '';
        final mappedFarm = await prefs.getIdMapping('farm', farmId);
        if (mappedFarm != null) payload['farm_id'] = mappedFarm;
        else if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$').hasMatch(farmId)) {
          skippedDependencies.add(op['id'].toString());
          continue;
        }
      }
      wireOps.add({'id': op['id'], 'entity_type': op['entity_type'], 'operation': op['operation'],
        'entity_local_id': op['entity_local_id'], 'payload': payload});
    }
    if (wireOps.isEmpty) return {'sent': 0, 'applied': 0, 'blocked': 0, 'waiting_dependencies': skippedDependencies.length};
    final response = await _client.post(_uri('/api/sync/push'), headers: await _headers(),
      body: jsonEncode({'device_id': device['id'], 'operations': wireOps}));
    final results = (_decode(response)['data'] as List).cast<Map<String, dynamic>>();
    final byId = {for (final r in results) r['id'].toString(): r};
    final updated = <Map<String, dynamic>>[];
    var applied = 0, blocked = 0;
    for (final item in queue) {
      final result = byId[item['id']];
      if (result == null) { updated.add(item); continue; }
      final status = result['status']?.toString() ?? 'rejected';
      if (status == 'applied') {
        applied++;
        final serverResult = result['result'];
        if (serverResult is Map && serverResult['id'] != null && item['operation'] == 'create') {
          await prefs.saveIdMapping(item['entity_type'].toString(), item['entity_local_id'].toString(), serverResult['id'].toString());
        }
        continue;
      }
      blocked++;
      updated.add({...item, 'status': status, 'server_result': result['result'], 'error_code': result['error_code']});
    }
    await _saveQueue(prefs, updated);

    return {'sent': wireOps.length, 'applied': applied, 'blocked': blocked, 'waiting_dependencies': skippedDependencies.length, 'results': results};
  }

  /// Baixa mudanças, persiste no cache local e só então avança o cursor.
  /// A integração do cache com os repositórios das telas legadas ainda é separada.
  Future<Map<String, dynamic>> baixarAlteracoes({int limit = 200}) async {
    final prefs = await Eito360LocalStore.open();
    final device = await _ensureDevice(prefs);
    final cursor = await prefs.getInt(_cursorKey) ?? 0;
    final response = await _client.get(_uri('/api/sync/pull', {
      'cursor': '$cursor', 'limit': '${limit.clamp(1, 500)}', 'device_key': (await prefs.getString(_deviceKeyKey)) ?? '',
    }), headers: await _headers());
    final body = _decode(response);
    final changes = (body['data'] as List).cast<Map<String, dynamic>>();
    final nextCursor = (body['next_cursor'] as num?)?.toInt() ?? cursor;
    // Apply server changes and cursor in one SQLite transaction on mobile/desktop.
    // On web the cache is persisted before the cursor so a failure causes safe replay.
    await prefs.applyChangesAndCursor(changes, nextCursor);
    await prefs.setInt(_cursorKey, nextCursor);
    return {'changes': changes, 'next_cursor': nextCursor, 'has_more': body['has_more'], 'previous_cursor': cursor, 'applied_locally': true};
  }

  Future<void> confirmarCursor(int cursor) async {
    if (cursor < 0) throw ArgumentError('Cursor inválido.');
    final prefs = await Eito360LocalStore.open();
    await prefs.setInt(_cursorKey, cursor);
  }

  Future<List<Map<String, dynamic>>> dadosLocais(String entityType) async {
    if (!['farm', 'animal'].contains(entityType)) throw ArgumentError('Tipo local inválido.');
    return (await Eito360LocalStore.open()).cachedEntities(entityType);
  }

  Future<List<Map<String, dynamic>>> pendencias() async {
    final prefs = await Eito360LocalStore.open();
    return _readQueue(prefs);
  }

  void close() => _client.close();
}
