import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'eito360_local_store.dart';
Future<Eito360LocalStore> openEito360LocalStore() async => _WebStore(await SharedPreferences.getInstance());
class _WebStore implements Eito360LocalStore {
  _WebStore(this.prefs); final SharedPreferences prefs;
  static const cacheKey='eito360.local.cache.v1';
  @override Future<String?> getString(String key) async => prefs.getString(key);
  @override Future<int?> getInt(String key) async => prefs.getInt(key);
  @override Future<void> setString(String key,String value) async { await prefs.setString(key,value); }
  @override Future<void> setInt(String key,int value) async { await prefs.setInt(key,value); }
  @override Future<void> applyChangesAndCursor(List<Map<String,dynamic>> changes,int cursor) async {
    final cache=Map<String,dynamic>.from(jsonDecode(prefs.getString(cacheKey)??'{}') as Map);
    for(final c in changes){ final type=c['entity_type']?.toString(), id=c['entity_id']?.toString(); if(!['farm','animal'].contains(type)||id==null||id.isEmpty)continue;
      final key='$type:$id'; if(c['change_type']=='delete'){cache.remove(key);}else{cache[key]={'id':id,'version':c['version'],'payload':c['payload']};}}
    await prefs.setString(cacheKey,jsonEncode(cache));
    await prefs.setInt('eito360.sync.cursor',cursor);
  }
  @override Future<List<Map<String,dynamic>>> cachedEntities(String type) async { final cache=Map<String,dynamic>.from(jsonDecode(prefs.getString(cacheKey)??'{}') as Map); return cache.entries.where((e)=>e.key.startsWith('$type:')).map((e)=>Map<String,dynamic>.from(e.value as Map)).toList(); }
  @override Future<void> saveIdMapping(String type,String localId,String serverId) async { await prefs.setString('eito360.idmap.$type.$localId',serverId); }
  @override Future<String?> getIdMapping(String type,String localId) async => prefs.getString('eito360.idmap.$type.$localId');
  @override Future<void> close() async {}
}
