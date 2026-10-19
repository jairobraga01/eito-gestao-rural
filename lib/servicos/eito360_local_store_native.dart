import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'eito360_local_store.dart';

Future<Eito360LocalStore> openEito360LocalStore() async {
  final root = await getDatabasesPath();
  final db = await openDatabase(p.join(root, 'eito360_local_v1.db'), version: 2,
    onUpgrade: (db, oldVersion, newVersion) async { if (oldVersion < 2) await db.execute('CREATE TABLE IF NOT EXISTS id_map (entity_type TEXT NOT NULL, local_id TEXT NOT NULL, server_id TEXT NOT NULL, PRIMARY KEY(entity_type, local_id))'); },
    onCreate: (db, version) async {
      await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute('CREATE TABLE entity_cache (entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(entity_type, entity_id))');
      await db.execute('CREATE TABLE id_map (entity_type TEXT NOT NULL, local_id TEXT NOT NULL, server_id TEXT NOT NULL, PRIMARY KEY(entity_type, local_id))');
    });
  return _NativeStore(db);
}
class _NativeStore implements Eito360LocalStore {
  _NativeStore(this.db); final Database db;
  @override Future<String?> getString(String key) async => (await db.query('kv', columns:['value'], where:'key=?', whereArgs:[key], limit:1)).firstOrNull?['value'] as String?;
  @override Future<int?> getInt(String key) async { final s=await getString(key); return s==null?null:int.tryParse(s); }
  @override Future<void> setString(String key,String value) async { await db.insert('kv', {'key':key,'value':value}, conflictAlgorithm:ConflictAlgorithm.replace); }
  @override Future<void> setInt(String key,int value) => setString(key,'$value');
  @override Future<void> applyChangesAndCursor(List<Map<String,dynamic>> changes,int cursor) async {
    await db.transaction((txn) async {
      for(final c in changes) {
        final type=c['entity_type']?.toString(); final id=c['entity_id']?.toString();
        if(!['farm','animal'].contains(type)||id==null||id.isEmpty) continue;
        if(c['change_type']=='delete') { await txn.delete('entity_cache',where:'entity_type=? AND entity_id=?',whereArgs:[type,id]); }
        else { final payload=c['payload'] is Map ? Map<String,dynamic>.from(c['payload'] as Map) : <String,dynamic>{};
          await txn.insert('entity_cache', {'entity_type':type,'entity_id':id,'payload':jsonEncode(payload),'version':(c['version'] as num?)?.toInt()??1}, conflictAlgorithm:ConflictAlgorithm.replace); }
      }
      await txn.insert('kv',{'key':'eito360.sync.cursor','value':'$cursor'},conflictAlgorithm:ConflictAlgorithm.replace);
    });
  }
  @override Future<List<Map<String,dynamic>>> cachedEntities(String type) async => (await db.query('entity_cache',where:'entity_type=?',whereArgs:[type])).map((r)=>{'id':r['entity_id'],'version':r['version'],'payload':jsonDecode(r['payload'] as String)}).toList();
  @override Future<void> saveIdMapping(String type,String localId,String serverId) async { await db.insert('id_map',{'entity_type':type,'local_id':localId,'server_id':serverId},conflictAlgorithm:ConflictAlgorithm.replace); }
  @override Future<String?> getIdMapping(String type,String localId) async => (await db.query('id_map',columns:['server_id'],where:'entity_type=? AND local_id=?',whereArgs:[type,localId],limit:1)).firstOrNull?['server_id'] as String?;
  @override Future<void> close()=>db.close();
}
extension _FirstOrNull<T> on List<T> { T? get firstOrNull => isEmpty?null:first; }
