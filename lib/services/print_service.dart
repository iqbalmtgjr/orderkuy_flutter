import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThermalPrintService {
  static final FlutterThermalPrinter _printer = FlutterThermalPrinter.instance;
  static Printer? _selectedPrinter;
  static bool _isConnected = false;
  static DateTime? _lastConnectionAttempt;

  // Singleton pattern untuk maintain connection state
  static final ThermalPrintService _instance = ThermalPrintService._internal();
  factory ThermalPrintService() => _instance;
  ThermalPrintService._internal();

  // Get list of available printers
  static Future<List<Printer>> getAvailablePrinters() async {
    try {
      await _printer.getPrinters();
      // Wait for printers to be discovered
      final printers = <Printer>[];
      await for (final printerList in _printer.devicesStream.take(1)) {
        printers.addAll(printerList);
        break;
      }
      return printers;
    } catch (e) {
      debugPrint('Error getting printers: $e');
      return [];
    }
  }

  // Save selected printer
  static Future<void> saveSelectedPrinter(Printer printer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_address', printer.address ?? '');
      await prefs.setString('printer_name', printer.name ?? '');

      // Keep the same printer object to maintain connection
      if (_selectedPrinter?.address != printer.address) {
        _selectedPrinter = printer;
        _isConnected = false; // Reset connection for new printer
      }

      debugPrint('Printer saved: ${printer.name}');
    } catch (e) {
      debugPrint('Error saving printer: $e');
    }
  }

  // Get saved printer - return existing instance if available
  static Future<Printer?> getSavedPrinter() async {
    try {
      // If we already have a printer instance, return it
      if (_selectedPrinter != null) {
        debugPrint(
            'Returning existing printer instance: ${_selectedPrinter!.name}');
        return _selectedPrinter;
      }

      // Otherwise load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('printer_address');
      final name = prefs.getString('printer_name');

      if (address != null && name != null) {
        _selectedPrinter = Printer(
          address: address,
          name: name,
        );
        debugPrint('Loaded printer from storage: $name');
        return _selectedPrinter;
      }
    } catch (e) {
      debugPrint('Error getting saved printer: $e');
    }
    return null;
  }

  // Set selected printer
  static void setSelectedPrinter(Printer? printer) {
    _selectedPrinter = printer;
    _isConnected = false;
  }

  // Connect to printer with improved logic
  static Future<bool> connectPrinter(Printer printer) async {
    try {
      // Check if already connected to this printer
      if (_isConnected &&
          _selectedPrinter?.address == printer.address &&
          _lastConnectionAttempt != null &&
          DateTime.now().difference(_lastConnectionAttempt!) <
              const Duration(seconds: 30)) {
        debugPrint('Already connected to printer: ${printer.name}');
        return true;
      }

      // Disconnect first before reconnecting
      try {
        await _printer.disconnect(printer);
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('Disconnect before connect (expected): $e');
      }

      debugPrint('Connecting to printer: ${printer.name}');
      await _printer.connect(printer);

      _selectedPrinter = printer;
      _isConnected = true;
      _lastConnectionAttempt = DateTime.now();

      debugPrint('Successfully connected to printer');
      return true;
    } catch (e) {
      debugPrint('Error connecting printer: $e');
      _isConnected = false;
      _lastConnectionAttempt = null;
      return false;
    }
  }

  // Disconnect printer
  static Future<void> disconnectPrinter() async {
    try {
      if (_selectedPrinter != null) {
        await _printer.disconnect(_selectedPrinter!);
        _isConnected = false;
        _lastConnectionAttempt = null;
        debugPrint('Printer disconnected');
      }
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
      _isConnected = false;
      _lastConnectionAttempt = null;
    }
  }

  // Ensure printer is connected with smart reconnection
  static Future<bool> ensureConnected() async {
    if (_selectedPrinter == null) {
      // Try to load saved printer
      _selectedPrinter = await getSavedPrinter();
      if (_selectedPrinter == null) {
        debugPrint('No printer selected');
        return false;
      }
    }

    // Check if recently connected (within 30 seconds)
    if (_isConnected &&
        _lastConnectionAttempt != null &&
        DateTime.now().difference(_lastConnectionAttempt!) <
            const Duration(seconds: 30)) {
      debugPrint(
          'Using existing connection (${DateTime.now().difference(_lastConnectionAttempt!).inSeconds}s ago)');
      return true;
    }

    // Try to connect
    debugPrint('Attempting to connect to printer...');
    final connected = await connectPrinter(_selectedPrinter!);

    if (!connected) {
      debugPrint('Failed to connect, waiting 1 second and retrying...');
      await Future.delayed(const Duration(seconds: 1));
      return await connectPrinter(_selectedPrinter!);
    }

    return true;
  }

  // Print test page
  static Future<bool> printTest() async {
    try {
      debugPrint('=== Starting Test Print ===');
      if (!await ensureConnected()) {
        debugPrint('Failed to connect to printer');
        return false;
      }

      debugPrint('Creating print data...');
      // Create ESC/POS commands
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Print test content
      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('TEST PRINT',
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ));
      bytes += generator.text('ORDERKUY!',
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ));
      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Printer berhasil terhubung',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(DateTime.now().toString().substring(0, 19),
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(3);

      // Send to printer
      debugPrint('Sending to printer...');
      await _printer.printData(_selectedPrinter!, bytes);

      debugPrint('Test print successful');
      return true;
    } catch (e) {
      debugPrint('Error printing test: $e');
      _isConnected = false;
      _lastConnectionAttempt = null;
      return false;
    }
  }

  // Print receipt/struk
  static Future<bool> printReceipt({
    required String orderId,
    required String tokoNama,
    required List<Map<String, dynamic>> items,
    required double totalHarga,
    int jenisOrder = 1,
    String? mejaNo,
    String? catatan,
    int? metodeBayar,
    String? kasirNama,
  }) async {
    try {
      debugPrint('=== Starting Receipt Print ===');
      if (!await ensureConnected()) {
        debugPrint('Failed to connect to printer');
        return false;
      }

      debugPrint('Creating receipt data...');
      // Create ESC/POS commands
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Header
      bytes += generator.text('================================');
      bytes += generator.text(tokoNama,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ));
      bytes += generator.text('STRUK PEMBELIAN',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('================================');

      // Info Pesanan
      bytes += generator.text('No Order: $orderId');
      bytes += generator
          .text('Tanggal: ${DateTime.now().toString().substring(0, 19)}');

      if (jenisOrder == 1 && mejaNo != null) {
        bytes += generator.text('Meja: $mejaNo');
        bytes += generator.text('Jenis: Dine In');
      } else {
        bytes += generator.text('Jenis: Take Away');
      }

      if (metodeBayar != null) {
        bytes +=
            generator.text('Bayar: ${metodeBayar == 1 ? "Cash" : "Transfer"}');
      }

      bytes += generator.text('================================');

      // Items
      bytes += generator.text('PESANAN',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('--------------------------------');

      for (var item in items) {
        final nama = item['nama_produk'] ?? '';
        final qty = item['qty'] ?? 0;
        final harga = (item['harga'] is double)
            ? item['harga'] as double
            : double.parse(item['harga'].toString());
        final subtotal = qty * harga;

        // Nama produk
        bytes += generator.text(nama);

        // Qty x Harga = Subtotal
        final line =
            '  $qty x ${_formatRupiah(harga)} = ${_formatRupiah(subtotal)}';
        bytes += generator.text(line);
      }

      bytes += generator.text('================================');

      // Total
      bytes += generator.text('TOTAL: ${_formatRupiah(totalHarga)}',
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ));

      bytes += generator.text('================================');

      // Catatan
      if (catatan != null && catatan.isNotEmpty) {
        bytes += generator.text('Catatan:');
        bytes += generator.text(catatan);
        bytes += generator.text('================================');
      }

      // Footer
      bytes += generator.text('TERIMA KASIH',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Selamat Menikmati',
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.feed(3);

      // Send to printer
      debugPrint('Sending receipt to printer...');
      await _printer.printData(_selectedPrinter!, bytes);

      debugPrint('Receipt printed successfully');
      return true;
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      _isConnected = false;
      _lastConnectionAttempt = null;
      return false;
    }
  }

  // Format rupiah
  static String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    )}';
  }

  // Check connection status
  static bool isConnected() {
    return _isConnected && _selectedPrinter != null;
  }

  // Get current printer info
  static Printer? getCurrentPrinter() {
    return _selectedPrinter;
  }

  // Clear connection state (untuk force reconnect)
  static void clearConnectionState() {
    _isConnected = false;
    _lastConnectionAttempt = null;
    debugPrint('Connection state cleared');
  }
}
