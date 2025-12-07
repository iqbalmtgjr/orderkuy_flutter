import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Request Bluetooth permissions
  static Future<bool> requestBluetoothPermissions(BuildContext context) async {
    try {
      // Build list of permissions to request
      final permissions = <Permission>[];

      // Check each permission status
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
      final locationStatus = await Permission.locationWhenInUse.status;

      // Add permissions that are not granted
      if (!bluetoothScanStatus.isGranted) {
        permissions.add(Permission.bluetoothScan);
      }
      if (!bluetoothConnectStatus.isGranted) {
        permissions.add(Permission.bluetoothConnect);
      }
      if (!locationStatus.isGranted) {
        permissions.add(Permission.locationWhenInUse);
      }

      if (permissions.isEmpty) {
        // All permissions already granted
        return true;
      }

      // Request permissions
      await permissions.request();

      // Check if all required permissions are granted
      final bluetoothScanGranted = await Permission.bluetoothScan.status;
      final bluetoothConnectGranted = await Permission.bluetoothConnect.status;
      final locationGranted = await Permission.locationWhenInUse.status;

      final allGranted = bluetoothScanGranted.isGranted &&
          bluetoothConnectGranted.isGranted &&
          locationGranted.isGranted;

      if (!allGranted) {
        // Check if permanently denied
        final permanentlyDenied = bluetoothScanGranted.isPermanentlyDenied ||
            bluetoothConnectGranted.isPermanentlyDenied ||
            locationGranted.isPermanentlyDenied;

        // Show dialog to guide user to settings
        if (context.mounted) {
          await _showPermissionDialog(context, permanentlyDenied);
        }
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error requesting Bluetooth permissions: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error meminta izin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  // Show dialog when permissions are denied
  static Future<void> _showPermissionDialog(
    BuildContext context,
    bool permanentlyDenied,
  ) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Izin Diperlukan'),
          content: Text(
            permanentlyDenied
                ? 'Izin Bluetooth dan Lokasi telah ditolak secara permanen. '
                    'Silakan buka pengaturan aplikasi dan berikan izin yang diperlukan secara manual.'
                : 'Untuk dapat scan printer Bluetooth, aplikasi memerlukan izin akses lokasi dan Bluetooth. '
                    'Silakan izinkan akses yang diperlukan.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            if (permanentlyDenied)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Buka Pengaturan'),
              )
            else
              TextButton(
                child: const Text('Coba Lagi'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        );
      },
    );
  }

  // Check if Bluetooth permissions are granted
  static Future<bool> checkBluetoothPermissions() async {
    try {
      final bluetoothScan = await Permission.bluetoothScan.status;
      final bluetoothConnect = await Permission.bluetoothConnect.status;
      final location = await Permission.locationWhenInUse.status;

      return bluetoothScan.isGranted &&
          bluetoothConnect.isGranted &&
          location.isGranted;
    } catch (e) {
      debugPrint('Error checking Bluetooth permissions: $e');
      return false;
    }
  }

  // Check if any permission is permanently denied
  static Future<bool> isAnyPermissionPermanentlyDenied() async {
    try {
      final bluetoothScan = await Permission.bluetoothScan.status;
      final bluetoothConnect = await Permission.bluetoothConnect.status;
      final location = await Permission.locationWhenInUse.status;

      return bluetoothScan.isPermanentlyDenied ||
          bluetoothConnect.isPermanentlyDenied ||
          location.isPermanentlyDenied;
    } catch (e) {
      debugPrint('Error checking permanently denied permissions: $e');
      return false;
    }
  }
}
