// lib/utils/platform_helper.dart
import 'dart:io';

class PlatformHelper {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isWindows => Platform.isWindows;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Check if feature is supported
  static bool get supportsThermalPrinter => isMobile;
  static bool get supportsGeolocator => isMobile || isWindows;
  static bool get supportsPermissionHandler => isMobile;

  /// Request storage permission (only for mobile)
  static Future<bool> requestStoragePermission() async {
    if (!supportsPermissionHandler) {
      // Windows tidak perlu permission
      return true;
    }

    // Uncomment jika permission_handler sudah di-enable
    /*
    final status = await Permission.storage.request();
    return status.isGranted;
    */

    return true; // Default granted untuk testing
  }

  /// Print receipt (platform-specific)
  static Future<void> printReceipt(String content) async {
    if (supportsThermalPrinter) {
      // Gunakan flutter_thermal_printer
      // await ThermalPrinter.print(content);
      print('📄 Printing via thermal printer: $content');
    } else if (isWindows) {
      // Alternatif untuk Windows:
      // 1. Generate PDF dan print
      // 2. Kirim ke network printer
      // 3. Export ke file
      print('📄 [Windows] Saving receipt to file: $content');
      // TODO: Implement Windows printing
    }
  }

  /// Get location (platform-specific)
  static Future<Map<String, double>?> getCurrentLocation() async {
    if (!supportsGeolocator) {
      print('⚠️ Geolocation not supported on this platform');
      return null;
    }

    // Uncomment jika geolocator sudah di-enable
    /*
    try {
      final position = await Geolocator.getCurrentPosition();
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
    */

    return null; // Default untuk testing
  }

  /// Show platform info in debug
  static void printPlatformInfo() {
    print('========== PLATFORM INFO ==========');
    print('OS: ${Platform.operatingSystem}');
    print('Version: ${Platform.operatingSystemVersion}');
    print('Is Mobile: $isMobile');
    print('Is Desktop: $isDesktop');
    print('Thermal Printer: $supportsThermalPrinter');
    print('Geolocator: $supportsGeolocator');
    print('===================================');
  }
}
