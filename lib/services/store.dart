import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as crypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/models.dart';

/// Payloads and queued attachments are AES-GCM encrypted; key lives in OS secure storage.
/// IDs, queue kind, retry metadata and timestamps remain indexable SQLite metadata.
class LocalStore {
  final String namespace;
  late Database db;
  late crypt.Encrypter cipher;
  late Directory root;
  LocalStore(this.namespace);
  Future<void> open() async {
    const secure=FlutterSecureStorage();
    var key=await secure.read(key:'fieldforce.key.$namespace');
    if(key==null) {
      key=crypt.Key.fromSecureRandom(32).base64;
      await secure.write(key:'fieldforce.key.$namespace',value:key);
    }
    cipher=crypt.Encrypter(crypt.AES(crypt.Key.fromBase64(key),mode:crypt.AESMode.gcm,padding:null));
    root=Directory(p.join((await getApplicationSupportDirectory()).path,namespace));
    await root.create(recursive:true);
    db=await openDatabase(p.join(root.path,'operations.db'),version:1,
      onCreate:(d,v) async {
        await d.execute('CREATE TABLE state (id TEXT PRIMARY KEY, body TEXT NOT NULL)');
        await d.execute('CREATE TABLE outbox (id TEXT PRIMARY KEY, kind TEXT NOT NULL, body TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, nextAt INTEGER NOT NULL DEFAULT 0, error TEXT, createdAt INTEGER NOT NULL)');
        await d.execute('CREATE TABLE route (id TEXT PRIMARY KEY, body TEXT NOT NULL, capturedAt INTEGER NOT NULL)');
        await d.execute('CREATE TABLE audit (id TEXT PRIMARY KEY, body TEXT NOT NULL, createdAt INTEGER NOT NULL)');
      });
  }
  String seal(String text) {
    final iv=crypt.IV.fromSecureRandom(12);
    return '${iv.base64}.${cipher.encrypt(text,iv:iv).base64}';
  }
  String unseal(String value) {
    final parts=value.split('.');
    return cipher.decrypt64(parts[1],iv:crypt.IV.fromBase64(parts[0]));
  }
  Future<void> set(String id,dynamic value)=>db.insert('state',{'id':id,'body':seal(jsonEncode(value))},
    conflictAlgorithm:ConflictAlgorithm.replace).then((_){ });
  Future<dynamic> get(String id) async {
    final r=await db.query('state',where:'id=?',whereArgs:[id]);
    return r.isEmpty?null:jsonDecode(unseal(r.first['body'] as String));
  }
  Future<void> enqueue(String id,String kind,Json body,{Transaction? tx}) async {
    await (tx??db).insert('outbox',{'id':id,'kind':kind,'body':seal(jsonEncode(body)),
      'createdAt':DateTime.now().millisecondsSinceEpoch},conflictAlgorithm:ConflictAlgorithm.ignore);
  }
  Future<void> attendance(String id,Json event,Json session) async {
    await db.transaction((tx) async {
      await enqueue(id,'attendance',event,tx:tx);
      await tx.insert('state',{'id':'session','body':seal(jsonEncode(session))},conflictAlgorithm:ConflictAlgorithm.replace);
    });
  }
  Future<List<Json>> pending() async {
    // Ordered FIFO prevents checkout overtaking a retried check-in.
    final rows=await db.query('outbox',orderBy:'createdAt ASC, rowid ASC',limit:50);
    return rows.map((r)=>{...r,'payload':jsonDecode(unseal(r['body'] as String))}).toList();
  }
  Future<int> count() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox'))??0;
  Future<void> ack(String id) async { await db.delete('outbox',where:'id=?',whereArgs:[id]); }
  Future<void> fail(Json row,String error,{bool permanent=false}) async {
    final attempts=(row['attempts'] as int)+1;
    final seconds=permanent?86400:(5*(1<<attempts.clamp(0,9).toInt())).clamp(10,3600).toInt();
    await db.update('outbox',{'attempts':attempts,'nextAt':DateTime.now().add(Duration(seconds:seconds)).millisecondsSinceEpoch,
      'error':error},where:'id=?',whereArgs:[row['id']]);
  }
  Future<void> retry() async { await db.update('outbox',{'nextAt':0}); }
  Future<void> addFix(Fix fix) async {
    await db.insert('route',{'id':fix.id,'body':seal(jsonEncode(fix.toJson())),
      'capturedAt':fix.capturedAt.millisecondsSinceEpoch},conflictAlgorithm:ConflictAlgorithm.ignore);
    // Bounded UI cache; durable native upload queue has its own retention.
    await db.rawDelete('DELETE FROM route WHERE id NOT IN (SELECT id FROM route ORDER BY capturedAt DESC LIMIT 3000)');
  }
  Future<List<Fix>> route() async => (await db.query('route',orderBy:'capturedAt ASC'))
    .map((r)=>Fix.fromJson(Map<String,dynamic>.from(jsonDecode(unseal(r['body'] as String)) as Map))).toList();
  Future<void> audit(String code,String message) async {
    await db.insert('audit',{'id':const Uuid().v4(),'body':seal(jsonEncode({'code':code,'message':message,
      'at':DateTime.now().toUtc().toIso8601String()})),'createdAt':DateTime.now().millisecondsSinceEpoch});
    await db.rawDelete('DELETE FROM audit WHERE id NOT IN (SELECT id FROM audit ORDER BY createdAt DESC LIMIT 300)');
  }
  Future<List<Json>> issues() async => (await db.query('audit',orderBy:'createdAt DESC',limit:30))
    .map((r)=>Map<String,dynamic>.from(jsonDecode(unseal(r['body'] as String)) as Map)).toList();
  Future<String> importAttachment(File file) async {
    final queued=await db.query('outbox',where:'kind=?',whereArgs:['file']);
    if(queued.length>=50) { throw Exception('Upload queue is full (50 files). Sync existing files first.'); }
    final size=await file.length();
    if(size>10*1024*1024) { throw Exception('Maximum attachment size is 10 MB.'); }
    final bytes=await file.readAsBytes();
    final path=p.join(root.path,'${const Uuid().v4()}.enc');
    await File(path).writeAsString(seal(base64Encode(bytes)),flush:true);
    return path;
  }
  Future<List<int>> attachment(String path) async=>base64Decode(unseal(await File(path).readAsString()));
  Future<void> clearAccount() async {
    await db.transaction((tx) async {
      for(final table in ['state','route','audit']) { await tx.delete(table); }
    });
    await for(final entry in root.list()) {
      if(entry is File && entry.path.endsWith('.enc')) { await entry.delete(); }
    }
  }
}
