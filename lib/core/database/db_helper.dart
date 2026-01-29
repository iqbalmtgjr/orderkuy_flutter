import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;

    _db = await openDatabase(
      join(await getDatabasesPath(), 'orderkuy.db'),
      version: 5, // ← INCREMENT version untuk kategoris cache
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
            toko_id INTEGER,
            last_updated TEXT
          )
          ''');
        }

        if (oldVersion < 3) {
          try {
            await db.execute('''
            ALTER TABLE orders_offline 
            ADD COLUMN client_uuid TEXT
            ''');
          } catch (e) {
            print('Column client_uuid already exists or error: $e');
          }

          try {
            await db.execute('''
            ALTER TABLE orders_offline 
            ADD COLUMN sync_error TEXT
            ''');
          } catch (e) {
            print('Column sync_error already exists or error: $e');
          }

          try {
            await db.execute('''
            ALTER TABLE orders_offline 
            ADD COLUMN server_id INTEGER
            ''');
          } catch (e) {
            print('Column server_id already exists or error: $e');
          }
        }

        // Pengeluaran offline table
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

        // ← NEW: Kategoris cache table
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
      },
    );
    return _db!;
  }

  static Future<void> _createTables(Database db) async {
    // Orders offline table
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

    // Products cache
    await db.execute('''
    CREATE TABLE IF NOT EXISTS products_cache(
      id INTEGER PRIMARY KEY,
      nama_produk TEXT,
      harga REAL,
      qty INTEGER,
      foto TEXT,
      kategori TEXT,
      toko_id INTEGER,
      last_updated TEXT
    )
    ''');

    // Pengeluaran offline table
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

    // Pengeluaran cache table
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

    // Kategoris cache table
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

  // ═══════════════════════════════════════════════════════════
  // HELPER: Ensure table exists (safety check)
  // ═══════════════════════════════════════════════════════════

  static Future<void> _ensureTableExists(String tableName) async {
    final database = await db;
    try {
      // Test if table exists by querying it
      await database.rawQuery('SELECT 1 FROM $tableName LIMIT 1');
    } catch (e) {
      print('⚠️ Table $tableName does not exist, creating...');

      // Create the missing table based on table name
      if (tableName == 'kategoris_cache') {
        await database.execute('''
        CREATE TABLE IF NOT EXISTS kategoris_cache(
          id INTEGER PRIMARY KEY,
          nama_kategori TEXT,
          icon TEXT,
          toko_id INTEGER,
          last_updated TEXT
        )
        ''');
        print('✅ Table kategoris_cache created successfully');
      } else if (tableName == 'pengeluaran_cache') {
        await database.execute('''
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
        print('✅ Table pengeluaran_cache created successfully');
      } else if (tableName == 'pengeluaran_offline') {
        await database.execute('''
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
        print('✅ Table pengeluaran_offline created successfully');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // OFFLINE ORDERS (existing code - no changes)
  // ═══════════════════════════════════════════════════════════

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

    if (existing.isNotEmpty) {
      print('⚠️ Order with UUID $clientUuid already exists, skipping');
      return;
    }

    await database.insert('orders_offline', {
      'client_uuid': clientUuid,
      'payload': jsonEncode(order),
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });

    print('✅ Offline order saved with UUID: $clientUuid');
  }

  static Future<List<Map<String, dynamic>>> getOfflineOrders() async {
    final database = await db;
    return await database.query(
      'orders_offline',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
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
      {
        'is_synced': 1,
        'server_id': serverId,
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    print('✅ Order $id marked as synced (server ID: $serverId)');
  }

  static Future<void> markSyncError(int id, String error) async {
    final database = await db;
    await database.update(
      'orders_offline',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    print('❌ Sync error saved for order $id: $error');
  }

  static Future<void> deleteOfflineOrder(int id) async {
    final database = await db;
    await database.delete(
      'orders_offline',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearSyncedOrders() async {
    final database = await db;
    await database.delete(
      'orders_offline',
      where: 'is_synced = 1',
    );
    print('🧹 Cleared synced orders');
  }

  // ═══════════════════════════════════════════════════════════
  // OFFLINE PENGELUARAN
  // ═══════════════════════════════════════════════════════════

  static Future<void> saveOfflinePengeluaran(
    Map<String, dynamic> pengeluaran,
    String clientUuid,
  ) async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');

    // Check duplicate
    final existing = await database.query(
      'pengeluaran_offline',
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );

    if (existing.isNotEmpty) {
      print('⚠️ Pengeluaran with UUID $clientUuid already exists, skipping');
      return;
    }

    await database.insert('pengeluaran_offline', {
      'client_uuid': clientUuid,
      'payload': jsonEncode(pengeluaran),
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });

    print('✅ Offline pengeluaran saved with UUID: $clientUuid');
  }

  static Future<List<Map<String, dynamic>>> getOfflinePengeluaran() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');

    return await database.query(
      'pengeluaran_offline',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
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
      {
        'is_synced': 1,
        'server_id': serverId,
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    print('✅ Pengeluaran $id marked as synced (server ID: $serverId)');
  }

  static Future<void> markPengeluaranSyncError(int id, String error) async {
    final database = await db;
    await database.update(
      'pengeluaran_offline',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    print('❌ Pengeluaran sync error saved for $id: $error');
  }

  static Future<void> clearSyncedPengeluaran() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_offline');

    await database.delete(
      'pengeluaran_offline',
      where: 'is_synced = 1',
    );
    print('🧹 Cleared synced pengeluaran');
  }

  // ═══════════════════════════════════════════════════════════
  // PENGELUARAN CACHE
  // ═══════════════════════════════════════════════════════════

  static Future<void> savePengeluaranToCache(
    List<Map<String, dynamic>> pengeluaranList,
  ) async {
    final database = await db;
    await _ensureTableExists('pengeluaran_cache');

    final batch = database.batch();

    // Clear existing cache
    batch.delete('pengeluaran_cache');

    // Insert new data
    for (final item in pengeluaranList) {
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
    print('✅ Cached ${pengeluaranList.length} pengeluaran');
  }

  static Future<List<Map<String, dynamic>>> getPengeluaranFromCache() async {
    final database = await db;
    await _ensureTableExists('pengeluaran_cache');

    return await database.query('pengeluaran_cache');
  }

  static Future<bool> hasPengeluaranCache() async {
    try {
      final database = await db;
      await _ensureTableExists('pengeluaran_cache');

      final result = await database
          .rawQuery('SELECT COUNT(*) as count FROM pengeluaran_cache');
      return (result.first['count'] as int) > 0;
    } catch (e) {
      print('❌ Error checking pengeluaran cache: $e');
      return false;
    }
  }

  // Add single pengeluaran to cache (for offline created items)
  static Future<void> addPengeluaranToCache(
    Map<String, dynamic> pengeluaran,
  ) async {
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

  // ═══════════════════════════════════════════════════════════
  // PRODUCT CACHE
  // ═══════════════════════════════════════════════════════════

  static Future<void> saveProductsToCache(
    List<Map<String, dynamic>> products,
  ) async {
    final database = await db;
    final batch = database.batch();

    batch.delete('products_cache');

    for (final product in products) {
      batch.insert('products_cache', {
        'id': product['id'],
        'nama_produk': product['nama_produk'],
        'harga': product['harga'],
        'qty': product['qty'],
        'foto': product['foto'],
        'kategori': product['kategori'],
        'toko_id': product['toko_id'],
        'last_updated': DateTime.now().toIso8601String(),
      });
    }

    await batch.commit(noResult: true);
    print('✅ Cached ${products.length} products');
  }

  static Future<List<Map<String, dynamic>>> getProductsFromCache() async {
    final database = await db;
    return await database.query('products_cache');
  }

  static Future<bool> hasProductsCache() async {
    final database = await db;
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

  // ═══════════════════════════════════════════════════════════
  // KATEGORIS CACHE - FIXED with robust error handling
  // ═══════════════════════════════════════════════════════════

  static Future<void> saveKategorisToCache(
    List<Map<String, dynamic>> kategoris,
  ) async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');

      final batch = database.batch();

      // Clear existing cache
      batch.delete('kategoris_cache');

      // Insert new data
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
      print('✅ Cached ${kategoris.length} kategoris');
    } catch (e) {
      print('❌ Error saving kategoris to cache: $e');
    }
  }

  static Future<bool> hasKategorisCache() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');

      final result = await database
          .rawQuery('SELECT COUNT(*) as count FROM kategoris_cache');
      return (result.first['count'] as int) > 0;
    } catch (e) {
      print('❌ Error checking kategoris cache: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getKategorisFromCache() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');

      return await database.query('kategoris_cache');
    } catch (e) {
      print('❌ Error getting kategoris from cache: $e');
      return [];
    }
  }

  static Future<DateTime?> getKategorisCacheTimestamp() async {
    try {
      final database = await db;
      await _ensureTableExists('kategoris_cache');

      final result = await database.query(
        'kategoris_cache',
        columns: ['last_updated'],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return DateTime.parse(result.first['last_updated'] as String);
    } catch (e) {
      print('❌ Error getting kategoris cache timestamp: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DATABASE UTILITIES
  // ═══════════════════════════════════════════════════════════

  static Future<void> clearAllCache() async {
    final database = await db;
    await database.delete('products_cache');
    await database.delete('orders_offline');
    await database.delete('pengeluaran_offline');
    await database.delete('pengeluaran_cache');
    await database.delete('kategoris_cache');
    print('🧹 All cache cleared');
  }

  // Force recreate all tables (use only for debugging)
  static Future<void> resetDatabase() async {
    try {
      final dbPath = join(await getDatabasesPath(), 'orderkuy.db');
      await deleteDatabase(dbPath);
      _db = null;
      print('🔄 Database reset successfully');
      await db; // Reinitialize
    } catch (e) {
      print('❌ Error resetting database: $e');
    }
  }
}
