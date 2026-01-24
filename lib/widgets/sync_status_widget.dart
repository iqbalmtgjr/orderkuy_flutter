import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/sync_service.dart';
import '../core/database/db_helper.dart';

class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({super.key});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  bool _isOnline = true;
  int _offlineCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();

    // Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      _loadStatus();
    });
  }

  Future<void> _loadStatus() async {
    final count = await DBHelper.getOfflineOrdersCount();
    setState(() {
      _offlineCount = count;
    });
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);

    final result = await SyncService.syncOrders();

    setState(() => _isSyncing = false);
    await _loadStatus();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? 'Sync selesai'),
        backgroundColor: result['success'] ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline && _offlineCount == 0) {
      // No indicator when online and no pending data
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isOnline ? Colors.orange.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isOnline ? Colors.orange : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isOnline ? Icons.cloud_upload : Icons.cloud_off,
            color: _isOnline ? Colors.orange : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOnline
                  ? '$_offlineCount pesanan offline'
                  : 'Mode Offline - $_offlineCount pesanan belum tersinkron',
              style: TextStyle(
                color: _isOnline ? Colors.orange.shade900 : Colors.red.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_isOnline && _offlineCount > 0)
            _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _manualSync,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Sync',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
        ],
      ),
    );
  }
}
