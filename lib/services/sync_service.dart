import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/database/db_helper.dart';
import 'api_service.dart';

class SyncService {
  static bool _isSyncing = false;

  // ═══════════════════════════════════════════════════════════
  // SYNC OFFLINE ORDERS TO SERVER (existing - no changes)
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> syncOrders() async {
    if (_isSyncing) {
      debugPrint('⏳ Sync already in progress, skipping');
      return {
        'success': false,
        'message': 'Sync sedang berjalan',
      };
    }

    _isSyncing = true;

    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) {
        debugPrint('📵 Offline: Cannot sync orders');
        _isSyncing = false;
        return {
          'success': false,
          'message': 'Tidak ada koneksi internet',
        };
      }

      final offlineOrders = await DBHelper.getOfflineOrders();

      if (offlineOrders.isEmpty) {
        debugPrint('✅ No offline orders to sync');
        _isSyncing = false;
        return {
          'success': true,
          'message': 'Tidak ada pesanan offline',
          'synced': 0,
        };
      }

      debugPrint('🔄 Syncing ${offlineOrders.length} offline orders...');

      int successCount = 0;
      int failedCount = 0;
      List<String> errors = [];

      for (final row in offlineOrders) {
        try {
          final payload = jsonDecode(row['payload'] as String);
          final clientUuid = row['client_uuid'] as String;

          debugPrint('⬆️ Uploading order: $clientUuid');

          payload['client_uuid'] = clientUuid;

          final res = await ApiService.createOrder(payload);

          if (res['success']) {
            final serverId = res['data']?['id'];
            await DBHelper.markSynced(row['id'] as int, serverId ?? 0);
            successCount++;
            debugPrint('✅ Order $clientUuid synced successfully');
          } else {
            final errorMsg = res['message'] ?? 'Unknown error';
            await DBHelper.markSyncError(row['id'] as int, errorMsg);
            failedCount++;
            errors.add(errorMsg);
            debugPrint('❌ Failed to sync order $clientUuid: $errorMsg');
          }
        } catch (e) {
          await DBHelper.markSyncError(
            row['id'] as int,
            e.toString(),
          );
          failedCount++;
          errors.add(e.toString());
          debugPrint('❌ Exception syncing order: $e');
        }
      }

      _isSyncing = false;

      if (successCount > 0) {
        await DBHelper.clearSyncedOrders();
      }

      return {
        'success': failedCount == 0,
        'message': '$successCount berhasil, $failedCount gagal',
        'synced': successCount,
        'failed': failedCount,
        'errors': errors,
      };
    } catch (e) {
      _isSyncing = false;
      debugPrint('❌ Sync service error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SYNC OFFLINE PENGELUARAN TO SERVER - NEW!
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> syncPengeluaran() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) {
        debugPrint('📵 Offline: Cannot sync pengeluaran');
        return {
          'success': false,
          'message': 'Tidak ada koneksi internet',
        };
      }

      final offlinePengeluaran = await DBHelper.getOfflinePengeluaran();

      if (offlinePengeluaran.isEmpty) {
        debugPrint('✅ No offline pengeluaran to sync');
        return {
          'success': true,
          'message': 'Tidak ada pengeluaran offline',
          'synced': 0,
        };
      }

      debugPrint(
          '🔄 Syncing ${offlinePengeluaran.length} offline pengeluaran...');

      int successCount = 0;
      int failedCount = 0;
      List<String> errors = [];

      for (final row in offlinePengeluaran) {
        try {
          final payload = jsonDecode(row['payload'] as String);
          final clientUuid = row['client_uuid'] as String;

          debugPrint('⬆️ Uploading pengeluaran: $clientUuid');

          payload['client_uuid'] = clientUuid;

          final res = await ApiService.createPengeluaran(payload);

          if (res['success']) {
            final serverId = res['data']?['id'];
            await DBHelper.markPengeluaranSynced(
                row['id'] as int, serverId ?? 0);
            successCount++;
            debugPrint('✅ Pengeluaran $clientUuid synced successfully');
          } else {
            final errorMsg = res['message'] ?? 'Unknown error';
            await DBHelper.markPengeluaranSyncError(row['id'] as int, errorMsg);
            failedCount++;
            errors.add(errorMsg);
            debugPrint('❌ Failed to sync pengeluaran $clientUuid: $errorMsg');
          }
        } catch (e) {
          await DBHelper.markPengeluaranSyncError(
            row['id'] as int,
            e.toString(),
          );
          failedCount++;
          errors.add(e.toString());
          debugPrint('❌ Exception syncing pengeluaran: $e');
        }
      }

      if (successCount > 0) {
        await DBHelper.clearSyncedPengeluaran();
      }

      return {
        'success': failedCount == 0,
        'message': 'Pengeluaran: $successCount berhasil, $failedCount gagal',
        'synced': successCount,
        'failed': failedCount,
        'errors': errors,
      };
    } catch (e) {
      debugPrint('❌ Sync pengeluaran error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SYNC PRODUCTS FROM SERVER (existing - no changes)
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> syncProducts() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) {
        debugPrint('📵 Offline: Skipping product sync');

        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          final timestamp = await DBHelper.getProductsCacheTimestamp();
          return {
            'success': true,
            'message': 'Menggunakan cache',
            'cached': true,
            'timestamp': timestamp,
          };
        }

        return {
          'success': false,
          'message': 'Offline dan tidak ada cache',
        };
      }

      debugPrint('🔄 Syncing products from server...');
      final products = await ApiService.getMenus();

      if (products.isNotEmpty) {
        debugPrint('✅ Products synced: ${products.length} items');
        return {
          'success': true,
          'message': '${products.length} produk berhasil disinkronkan',
          'count': products.length,
        };
      } else {
        return {
          'success': false,
          'message': 'Tidak ada produk dari server',
        };
      }
    } catch (e) {
      debugPrint('❌ Error syncing products: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // AUTO SYNC ON CONNECTIVITY CHANGE - UPDATED!
  // ═══════════════════════════════════════════════════════════

  static void startAutoSync() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        debugPrint('📡 Connection restored, auto-syncing...');
        syncOrders();
        syncPengeluaran(); // ← NEW: Also sync pengeluaran
        syncProducts();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // GET SYNC STATUS - UPDATED!
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getSyncStatus() async {
    final offlineOrdersCount = await DBHelper.getOfflineOrdersCount();
    final offlinePengeluaranCount = await DBHelper.getOfflinePengeluaranCount();
    final hasProductCache = await DBHelper.hasProductsCache();
    final hasPengeluaranCache = await DBHelper.hasPengeluaranCache();
    final cacheTimestamp = await DBHelper.getProductsCacheTimestamp();
    final isOnline =
        await Connectivity().checkConnectivity() != ConnectivityResult.none;

    return {
      'is_online': isOnline,
      'is_syncing': _isSyncing,
      'offline_orders': offlineOrdersCount,
      'offline_pengeluaran': offlinePengeluaranCount, // ← NEW
      'has_products_cache': hasProductCache,
      'has_pengeluaran_cache': hasPengeluaranCache, // ← NEW
      'cache_timestamp': cacheTimestamp?.toIso8601String(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // SYNC ALL - NEW HELPER METHOD
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> syncAll() async {
    final results = {
      'orders': await syncOrders(),
      'pengeluaran': await syncPengeluaran(),
      'products': await syncProducts(),
    };

    final totalSynced = (results['orders']?['synced'] ?? 0) +
        (results['pengeluaran']?['synced'] ?? 0);

    return {
      'success': true,
      'message': 'Sync selesai: $totalSynced item berhasil',
      'details': results,
    };
  }
}
