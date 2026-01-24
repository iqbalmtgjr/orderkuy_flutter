import 'dart:convert';
import '../core/database/offline_queue_db.dart';
import 'api_service.dart';

class QueueSyncService {
  static Future<void> sync() async {
    final queue = await OfflineQueueDB.getQueue();

    for (final q in queue) {
      final payload = jsonDecode(q['payload']);

      final res = await ApiService.raw(
        endpoint: q['endpoint'],
        method: q['method'],
        payload: payload,
      );

      if (res['success']) {
        await OfflineQueueDB.markSynced(q['id']);
      }
    }
  }
}
