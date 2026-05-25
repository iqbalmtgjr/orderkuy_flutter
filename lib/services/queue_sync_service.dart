import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/database/offline_queue_db.dart';
import 'api_service.dart';

class QueueSyncService {
  static bool _isSyncing = false;

  static Future<Map<String, dynamic>> sync() async {
    // Guard: jangan sync paralel
    if (_isSyncing) {
      debugPrint('⏳ QueueSync already running, skipping');
      return {'success': false, 'message': 'Sync sedang berjalan'};
    }

    // Cek koneksi dulu
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      debugPrint('📵 QueueSync: offline, skip');
      return {'success': false, 'message': 'Tidak ada koneksi'};
    }

    _isSyncing = true;

    int successCount = 0;
    int failCount = 0;
    int skippedCount = 0;
    final List<String> errors = [];

    try {
      final queue = await OfflineQueueDB.getQueue();

      if (queue.isEmpty) {
        debugPrint('✅ QueueSync: antrian kosong');
        _isSyncing = false;
        return {
          'success': true,
          'message': 'Tidak ada item di antrian',
          'synced': 0,
        };
      }

      debugPrint('🔄 QueueSync: ${queue.length} item akan di-sync');

      for (final q in queue) {
        final id = q['id'] as int;
        final retryCount = (q['retry_count'] as int?) ?? 0;

        // Lewati item yang sudah gagal >3 kali
        if (retryCount >= 3) {
          debugPrint('⏭️ QueueSync: item $id dilewati (retry=$retryCount)');
          skippedCount++;
          continue;
        }

        try {
          final payload =
              jsonDecode(q['payload'] as String) as Map<String, dynamic>;

          final res = await ApiService.raw(
            endpoint: q['endpoint'] as String,
            method: q['method'] as String,
            payload: payload,
          );

          if (res['success'] == true) {
            await OfflineQueueDB.markSynced(id);
            successCount++;
            debugPrint('✅ QueueSync: item $id berhasil');
          } else {
            final errMsg = res['message']?.toString() ?? 'Unknown error';
            await OfflineQueueDB.incrementRetry(id, errMsg);
            failCount++;
            errors.add('Item $id: $errMsg');
            debugPrint('❌ QueueSync: item $id gagal — $errMsg');
          }
        } catch (e) {
          // Network error atau parse error
          await OfflineQueueDB.incrementRetry(id, e.toString());
          failCount++;
          errors.add('Item $id: $e');
          debugPrint('❌ QueueSync: item $id exception — $e');
        }
      }

      // Bersihkan item yang sudah synced
      if (successCount > 0) {
        await OfflineQueueDB.clearSynced();
      }

      debugPrint(
          '🏁 QueueSync selesai: $successCount ok, $failCount gagal, $skippedCount dilewati');

      return {
        'success': failCount == 0,
        'message':
            '$successCount berhasil, $failCount gagal, $skippedCount dilewati',
        'synced': successCount,
        'failed': failCount,
        'skipped': skippedCount,
        'errors': errors,
      };
    } catch (e) {
      debugPrint('❌ QueueSyncService fatal error: $e');
      return {'success': false, 'message': 'Error: $e'};
    } finally {
      _isSyncing = false;
    }
  }

  /// Daftarkan listener: auto-sync saat koneksi kembali.
  static void startAutoSync() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        debugPrint('📡 Koneksi pulih — memulai QueueSync otomatis');
        sync();
      }
    });
  }
}
