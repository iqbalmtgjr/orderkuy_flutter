import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineQueueDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;

    // sqflite_common_ffi sudah di-set di main.dart

    _db = await openDatabase(
      join(await getDatabasesPath(), 'queue.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_queue(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          endpoint TEXT,
          method TEXT,
          payload TEXT,
          created_at TEXT,
          is_synced INTEGER DEFAULT 0
        )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> push({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final database = await db;
    await database.insert('offline_queue', {
      'endpoint': endpoint,
      'method': method,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getQueue() async {
    final database = await db;
    return await database.query('offline_queue', where: 'is_synced = 0');
  }

  static Future<void> markSynced(int id) async {
    final database = await db;
    await database.update(
      'offline_queue',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
