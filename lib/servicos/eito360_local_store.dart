import 'eito360_local_store_stub.dart'
    if (dart.library.io) 'eito360_local_store_native.dart'
    if (dart.library.html) 'eito360_local_store_web.dart' as impl;

abstract class Eito360LocalStore {
  static Future<Eito360LocalStore> open() => impl.openEito360LocalStore();
  Future<String?> getString(String key);
  Future<int?> getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> applyChangesAndCursor(List<Map<String, dynamic>> changes, int cursor);
  Future<List<Map<String, dynamic>>> cachedEntities(String entityType);
  Future<void> saveIdMapping(String entityType, String localId, String serverId);
  Future<String?> getIdMapping(String entityType, String localId);
  Future<void> close();
}
