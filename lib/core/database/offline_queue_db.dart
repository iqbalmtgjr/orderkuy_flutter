import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineQueueDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;

    _db = await openDatabase(
      join(await getDatabasesPath(), 'queue.db'),
      version: 2, // ← naik dari 1 ke 2
      onCreate: (db, v) async {
        await _createTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Tambah kolom baru ke tabel yang sudah ada
          try {
            await db.execute(
                'ALTER TABLE offline_queue ADD COLUMN retry_count INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_queue ADD COLUMN last_error TEXT');
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  static Future<void> _createTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS offline_queue(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      endpoint TEXT NOT NULL,
      method TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT,
      is_synced INTEGER DEFAULT 0,
      retry_count INTEGER DEFAULT 0,
      last_error TEXT
    )
    ''');
  }

  // ── Public API ─────────────────────────────────────────────

  /// Tambahkan request ke antrian offline.
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
      'retry_count': 0,
    });
  }

  /// Ambil semua item yang belum di-sync dan belum terlalu banyak gagal.
  static Future<List<Map<String, dynamic>>> getQueue() async {
    final database = await db;
    return database.query(
      'offline_queue',
      where: 'is_synced = 0 AND retry_count < 3',
      orderBy: 'created_at ASC',
    );
  }

  /// Tandai item berhasil di-sync.
  static Future<void> markSynced(int id) async {
    final database = await db;
    await database.update(
      'offline_queue',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Naikkan counter gagal dan simpan pesan error.
  static Future<void> incrementRetry(int id, String error) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE offline_queue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  /// Hapus semua item yang sudah berhasil di-sync.
  static Future<void> clearSynced() async {
    final database = await db;
    await database.delete('offline_queue', where: 'is_synced = 1');
  }

  /// Hapus semua item (termasuk yang belum sync) — gunakan hati-hati.
  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('offline_queue');
  }

  /// Jumlah item yang masih menunggu sync.
  static Future<int> getPendingCount() async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM offline_queue WHERE is_synced = 0');
    return result.first['count'] as int;
  }
}
