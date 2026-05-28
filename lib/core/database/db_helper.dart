import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;

    _db = await openDatabase(
      join(await getDatabasesPath(), 'orderkuy.db'),
      // ← naikan ke 7 agar onUpgrade dijalankan di device existing
      version: 7,
      onCreate: (db, v) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
          CREATE TABLE IF NOT EXISTS products_cache(
            id INTEGER PRIMARY KEY,
            nama_produk TEXT,
            harga REAL,
            qty INTEGER,
            foto TEXT,
            kategori TEXT,
            kategori_id INTEGER,
            toko_id INTEGER,
            last_updated TEXT
          )
          ''');
        }

        if (oldVersion < 3) {
          for (final col in [
            'client_uuid TEXT',
            'sync_error TEXT',
            'server_id INTEGER'
          ]) {
            try {
              await db.execute('ALTER TABLE orders_offline ADD COLUMN $col');
            } catch (_) {}
          }
        }

        if (oldVersion < 4) {
          await db.execute('''
          CREATE TABLE IF NOT EXISTS pengeluaran_offline(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_uuid TEXT UNIQUE NOT NULL,
            payload TEXT,
            created_at TEXT,
            is_synced INTEGER DEFAULT 0,
            sync_error TEXT,
            server_id INTEGER
          )
          ''');
          await db.execute('''
          CREATE TABLE IF NOT EXISTS pengeluaran_cache(
            id INTEGER PRIMARY KEY,
            nama_pengeluaran TEXT,
            jumlah REAL,
            tanggal TEXT,
            deskripsi TEXT,
            toko_id INTEGER,
            user_id INTEGER,
            last_updated TEXT
          )
          ''');
        }

        if (oldVersion < 5) {
          await db.execute('''
          CREATE TABLE IF NOT EXISTS kategoris_cache(
            id INTEGER PRIMARY KEY,
            nama_kategori TEXT,
            icon TEXT,
            toko_id INTEGER,
            last_updated TEXT
          )
          ''');
        }

        if (oldVersion < 6) {
          try {
            await db.execute(
                'ALTER TABLE products_cache ADD COLUMN kategori_id INTEGER');
          } catch (_) {}
        }

        // ← BARU: simpan option_groups sebagai JSON di cache
        if (oldVersion < 7) {
          try {
            await db.execute(
                'ALTER TABLE products_cache ADD COLUMN option_groups_json TEXT');
          } catch (_) {
            debugPrint('option_groups_json column may already exist');
          }
          try {
            await db.execute(
                'ALTER TABLE products_cache ADD COLUMN has_options INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE products_cache ADD COLUMN use_stock INTEGER DEFAULT 0');
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────
  // TABLE CREATION
  // ─────────────────────────────────────────────────────────────

  static Future<void> _createTables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS orders_offline(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_uuid TEXT UNIQUE NOT NULL,
      payload TEXT,
      created_at TEXT,
      is_synced INTEGER DEFAULT 0,
      sync_error TEXT,
      server_id INTEGER
    )
    ''');

    // products_cache dengan semua kolom termasuk option_groups_json
    await db.execute('''
    CREATE TABLE IF NOT EXISTS products_cache(
      id INTEGER PRIMARY KEY,
      nama_produk TEXT,
      harga REAL,
      qty INTEGER,
      foto TEXT,
      kategori TEXT,
      kategori_id INTEGER,
      toko_id INTEGER,
      has_options INTEGER DEFAULT 0,
      use_stock INTEGER DEFAULT 0,
      option_groups_json TEXT,
      last_updated TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS pengeluaran_offline(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_uuid TEXT UNIQUE NOT NULL,
      payload TEXT,
      created_at TEXT,
      is_synced INTEGER DEFAULT 0,
      sync_error TEXT,
      server_id INTEGER
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS pengeluaran_cache(
      id INTEGER PRIMARY KEY,
      nama_pengeluaran TEXT,
      jumlah REAL,
      tanggal TEXT,
      deskripsi TEXT,
      toko_id INTEGER,
      user_id INTEGER,
      last_updated TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS kategoris_cache(
      id INTEGER PRIMARY KEY,
      nama_kategori TEXT,
      icon TEXT,
      toko_id INTEGER,
      last_updated TEXT
    )
    ''');
  }

  // ─────────────────────────────────────────────────────────────
  // SAFETY HELPERS
  // ─────────────────────────────────────────────────────────────

  static Future<void> _ensureTableExists(String tableName) async {
    final database = await db;
    try {
      await database.rawQuery('SELECT 1 FROM $tableName LIMIT 1');
    } catch (_) {
      if (tableName == 'kategoris_cache') {
        await database.execute('''
        CREATE TABLE IF NOT EXISTS kategoris_cache(
          id INTEGER PRIMARY KEY, nama_kategori TEXT, icon TEXT,
          toko_id INTEGER, last_updated TEXT)
        ''');
      } else if (tableName == 'pengeluaran_cache') {
        await database.execute('''
        CREATE TABLE IF NOT EXISTS pengeluaran_cache(
          id INTEGER PRIMARY KEY, nama_pengeluaran TEXT, jumlah REAL,
          tanggal TEXT, deskripsi TEXT, toko_id INTEGER,
          user_id INTEGER, last_updated TEXT)
        ''');
      } else if (tableName == 'pengeluaran_offline') {
        await database.execute('''
        CREATE TABLE IF NOT EXISTS pengeluaran_offline(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_uuid TEXT UNIQUE NOT NULL, payload TEXT,
          created_at TEXT, is_synced INTEGER DEFAULT 0,
          sync_error TEXT, server_id INTEGER)
        ''');
      }
    }
  }

  /// Pastikan kolom-kolom baru ada (untuk device yang belum ter-upgrade)
  static Future<void> _ensureProductsCacheColumns() async {
    final database = await db;

    // kategori_id
    try {
      await database.rawQuery('SELECT kategori_id FROM products_cache LIMIT 1');
    } catch (_) {
      await database
          .execute('ALTER TABLE products_cache ADD COLUMN kategori_id INTEGER');
    }

    // option_groups_json  ← BARU
    try {
      await database
          .rawQuery('SELECT option_groups_json FROM products_cache LIMIT 1');
    } catch (_) {
      await database.execute(
          'ALTER TABLE products_cache ADD COLUMN option_groups_json TEXT');
    }

    // has_options
    try {
      await database.rawQuery('SELECT has_options FROM products_cache LIMIT 1');
    } catch (_) {
      await database.execute(
          'ALTER TABLE products_cache ADD COLUMN has_options INTEGER DEFAULT 0');
    }

    // use_stock
    try {
      await database.rawQuery('SELECT use_stock FROM products_cache LIMIT 1');
    } catch (_) {
      await database.execute(
          'ALTER TABLE products_cache ADD COLUMN use_stock INTEGER DEFAULT 0');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PRODUCTS CACHE
  // ─────────────────────────────────────────────────────────────

  /// Simpan produk ke cache, termasuk option_groups sebagai JSON string.
  /// Parameter `products` adalah raw JSON dari API.
  static Future<void> saveProductsToCache(
    List<Map<String, dynamic>> products,
  ) async {
    final database = await db;
    await _ensureProductsCacheColumns();

    final batch = database.batch();
    batch.delete('products_cache');

    for (final p in products) {
      // Encode option_groups ke JSON string agar bisa disimpan di SQLite TEXT
      final optionGroupsJson = jsonEncode(p['option_groups'] ?? []);

      batch.insert('products_cache', {
        'id': p['id'],
        'nama_produk': p['nama_produk'],
        'harga': p['harga'],
        'qty': p['qty'],
        'foto': p['foto'],
        'kategori': p['kategori'],
        'kategori_id': p['kategori_id'],
        'toko_id': p['toko_id'],
        'has_options':
            (p['has_options'] == true || p['has_options'] == 1) ? 1 : 0,
        'use_stock': (p['use_stock'] == true || p['use_stock'] == 1) ? 1 : 0,
        'option_groups_json': optionGroupsJson,
        'last_updated': DateTime.now().toIso8601String(),
      });
    }

    await batch.commit(noResult: true);
    debugPrint('✅ Cached ${products.length} products (with option_groups)');
  }

  /// Baca produk dari cache.
  /// Mengembalikan List<Map> yang sudah menyertakan 'option_groups' sebagai List.
  static Future<List<Map<String, dynamic>>> getProductsFromCache() async {
    final database = await db;
    await _ensureProductsCacheColumns();

    final rows = await database.query('products_cache');

    // Decode option_groups_json kembali ke List agar Product.fromJson bisa parse
    return rows.map((row) {
      final mutable = Map<String, dynamic>.from(row);

      // Decode JSON string → List
      try {
        final raw = mutable['option_groups_json'];
        if (raw != null && raw.toString().isNotEmpty) {
          mutable['option_groups'] = jsonDecode(raw as String) as List;
        } else {
          mutable['option_groups'] = <dynamic>[];
        }
      } catch (_) {
        mutable['option_groups'] = <dynamic>[];
      }

      // SQLite menyimpan bool sebagai INTEGER; konversi balik ke bool
      mutable['has_options'] = mutable['has_options'] == 1;
      mutable['use_stock'] = mutable['use_stock'] == 1;

      return mutable;
    }).toList();
  }

  static Future<bool> hasProductsCache() async {
    final database = await db;
    await _ensureProductsCacheColumns();
    final result =
        await database.rawQuery('SELECT COUNT(*) as count FROM products_cache');
    return (result.first['count'] as int) > 0;
  }

  static Future<DateTime?> getProductsCacheTimestamp() async {
    final database = await db;
    final result = await database.query(
      'products_cache',
      columns: ['last_updated'],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return DateTime.parse(result.first['last_updated'] as String);
  }

  static Future<void> updateProductStock(int productId, int newQty) async {
    final database = await db;
    await database.update(
      'products_cache',
      {'qty': newQty},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // OFFLINE ORDERS
  // ─────────────────────────────────────────────────────────────

  static Future<void> saveOfflineOrder(
    Map<String, dynamic> order,
    String clientUuid,
  ) async {
    final database = await db;
    final existing = await database.query(
      'orders_offline',
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
    if (existing.isNotEmpty) return;

    await database.insert('orders_offline', {
      'client_uuid': clientUuid,
      'payload': jsonEncode(order),
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getOfflineOrders() async {
    final database = await db;
    return database.query('orders_offline',
        where: 'is_synced = 0', orderBy: 'created_at ASC');
  }

  static Future<int> getOfflineOrdersCount() async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM orders_offline WHERE is_synced = 0');
    return result.first['count'] as int;
  }

  static Future<void> markSynced(int id, int serverId) async {
    final database = await db;
    await database.update(
      'orders_offline',
      {'is_synced': 1, 'server_id': serverId, 'sync_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markSyncError(int id, String error) async {
    final database = await db;
    await database.update(
      'orders_offline',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearSyncedOrders() async {
    final database = await db;
    await database.delete('orders_offline', where: 'is_synced = 1');
  }

  // ─────────────────────────────────────────────────────────────
  // OFFLINE PENGELUARAN
  // ─────────────────────────────────────────────────────────────

  static Future<void> saveOfflinePengeluaran(
    Map<String, dynamic> pengeluaran,
    String clientUuid,
  ) async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');
    final existing = await database.query('pengeluaran_offline',
        where: 'client_uuid = ?', whereArgs: [clientUuid]);
    if (existing.isNotEmpty) return;

    await database.insert('pengeluaran_offline', {
      'client_uuid': clientUuid,
      'payload': jsonEncode(pengeluaran),
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getOfflinePengeluaran() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');
    return database.query('pengeluaran_offline',
        where: 'is_synced = 0', orderBy: 'created_at ASC');
  }

  static Future<int> getOfflinePengeluaranCount() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');
    final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM pengeluaran_offline WHERE is_synced = 0');
    return result.first['count'] as int;
  }

  static Future<void> markPengeluaranSynced(int id, int serverId) async {
    final database = await db;
    await database.update(
      'pengeluaran_offline',
      {'is_synced': 1, 'server_id': serverId, 'sync_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markPengeluaranSyncError(int id, String error) async {
    final database = await db;
    await database.update(
      'pengeluaran_offline',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearSyncedPengeluaran() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');
    await database.delete('pengeluaran_offline', where: 'is_synced = 1');
  }

  // ─────────────────────────────────────────────────────────────
  // PENGELUARAN CACHE
  // ─────────────────────────────────────────────────────────────

  static Future<void> savePengeluaranToCache(
      List<Map<String, dynamic>> list) async {
    final database = await db;
    await _ensureTableExists('pengeluaran_cache');
    final batch = database.batch();
    batch.delete('pengeluaran_cache');
    for (final item in list) {
      batch.insert('pengeluaran_cache', {
        'id': item['id'],
        'nama_pengeluaran': item['nama_pengeluaran'],
        'jumlah': item['jumlah'],
        'tanggal': item['tanggal'],
        'deskripsi': item['deskripsi'],
        'toko_id': item['toko_id'],
        'user_id': item['user_id'],
        'last_updated': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getPengeluaranFromCache() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_cache');
    return database.query('pengeluaran_cache');
  }

  static Future<bool> hasPengeluaranCache() async {
    try {
      final database = await db;
      await _ensureTableExists('pengeluaran_cache');
      final result = await database
          .rawQuery('SELECT COUNT(*) as count FROM pengeluaran_cache');
      return (result.first['count'] as int) > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> addPengeluaranToCache(
      Map<String, dynamic> pengeluaran) async {
    final database = await db;
    await _ensureTableExists('pengeluaran_cache');
    await database.insert('pengeluaran_cache', {
      'id': pengeluaran['id'] ?? DateTime.now().millisecondsSinceEpoch,
      'nama_pengeluaran': pengeluaran['nama_pengeluaran'],
      'jumlah': pengeluaran['jumlah'],
      'tanggal': pengeluaran['tanggal'],
      'deskripsi': pengeluaran['deskripsi'],
      'toko_id': pengeluaran['toko_id'] ?? 0,
      'user_id': pengeluaran['user_id'] ?? 0,
      'last_updated': DateTime.now().toIso8601String(),
    });
  }

  // ─────────────────────────────────────────────────────────────
  // KATEGORIS CACHE
  // ─────────────────────────────────────────────────────────────

  static Future<void> saveKategorisToCache(
      List<Map<String, dynamic>> kategoris) async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');
      final batch = database.batch();
      batch.delete('kategoris_cache');
      for (final item in kategoris) {
        batch.insert('kategoris_cache', {
          'id': item['id'],
          'nama_kategori': item['nama_kategori'] ?? item['name'] ?? '',
          'icon': item['icon'] ?? '',
          'toko_id': item['toko_id'] ?? 0,
          'last_updated': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('❌ saveKategorisToCache: $e');
    }
  }

  static Future<bool> hasKategorisCache() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');
      final result = await database
          .rawQuery('SELECT COUNT(*) as count FROM kategoris_cache');
      return (result.first['count'] as int) > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getKategorisFromCache() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');
      return database.query('kategoris_cache');
    } catch (_) {
      return [];
    }
  }

  static Future<DateTime?> getKategorisCacheTimestamp() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');
      final result = await database.query('kategoris_cache',
          columns: ['last_updated'], limit: 1);
      if (result.isEmpty) return null;
      return DateTime.parse(result.first['last_updated'] as String);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────────────────────

  static Future<void> clearAllCache() async {
    final database = await db;
    await database.delete('products_cache');
    await database.delete('orders_offline');
    await database.delete('pengeluaran_offline');
    await database.delete('pengeluaran_cache');
    await database.delete('kategoris_cache');
    debugPrint('🧹 All cache cleared');
  }

  /// Hapus hanya cache produk/kategori/pengeluaran.
  /// TIDAK menghapus orders_offline dan pengeluaran_offline agar pesanan
  /// yang belum tersinkron tidak hilang.
  static Future<void> clearProductCache() async {
    final database = await db;
    await database.delete('products_cache');
    await database.delete('pengeluaran_cache');
    await database.delete('kategoris_cache');
    debugPrint('🧹 Product cache cleared (offline queues preserved)');
  }

  static Future<void> resetDatabase() async {
    try {
      final dbPath = join(await getDatabasesPath(), 'orderkuy.db');
      await deleteDatabase(dbPath);
      _db = null;
      await db;
      debugPrint('🔄 Database reset');
    } catch (e) {
      debugPrint('❌ resetDatabase: $e');
    }
  }
}
