import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThermalPrintService {
  static final FlutterThermalPrinter _printer = FlutterThermalPrinter.instance;
  static Printer? _selectedPrinter;
  static bool _isConnected = false;
  static DateTime? _lastSuccessfulPrint;
  static int _consecutiveErrors = 0;

  // Cache optimization
  static CapabilityProfile? _cachedProfile;
  static Generator? _cachedGenerator;

  // Connection settings - OPTIMIZED
  static const Duration _connectionTimeout =
      Duration(seconds: 45); // ← REDUCED: 45 seconds
  static const int _maxConsecutiveErrors = 3;

  // Print queue
  static bool _isPrinting = false;
  static final List<Future<bool> Function()> _printQueue = [];

  // Singleton
  static final ThermalPrintService _instance = ThermalPrintService._internal();
  factory ThermalPrintService() => _instance;
  ThermalPrintService._internal();

  // ═══════════════════════════════════════════════════════════
  // LOAD PROFILE ONCE & CACHE
  // ═══════════════════════════════════════════════════════════

  static Future<Generator> _getGenerator() async {
    if (_cachedGenerator != null) {
      debugPrint('✅ Using cached generator (FAST PATH)');
      return _cachedGenerator!;
    }

    debugPrint('⏳ Loading profile first time...');
    _cachedProfile = await CapabilityProfile.load();
    _cachedGenerator = Generator(PaperSize.mm58, _cachedProfile!);
    debugPrint('✅ Profile cached');

    return _cachedGenerator!;
  }

  // ═══════════════════════════════════════════════════════════
  // GET AVAILABLE PRINTERS
  // ═══════════════════════════════════════════════════════════

  static Future<List<Printer>> getAvailablePrinters() async {
    try {
      await _printer.getPrinters();
      final printers = <Printer>[];
      await for (final printerList in _printer.devicesStream.take(1)) {
        printers.addAll(printerList);
        break;
      }
      return printers;
    } catch (e) {
      debugPrint('❌ Error getting printers: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SAVE & LOAD PRINTER
  // ═══════════════════════════════════════════════════════════

  static Future<void> saveSelectedPrinter(Printer printer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_address', printer.address ?? '');
      await prefs.setString('printer_name', printer.name ?? '');

      if (_selectedPrinter?.address != printer.address) {
        _selectedPrinter = printer;
        _isConnected = false;
        _lastSuccessfulPrint = null;
        _consecutiveErrors = 0;
      }

      debugPrint('✅ Printer saved: ${printer.name}');
    } catch (e) {
      debugPrint('❌ Error saving printer: $e');
    }
  }

  static Future<Printer?> getSavedPrinter() async {
    try {
      if (_selectedPrinter != null) {
        return _selectedPrinter;
      }

      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('printer_address');
      final name = prefs.getString('printer_name');

      if (address != null && name != null) {
        _selectedPrinter = Printer(address: address, name: name);
        debugPrint('✅ Loaded printer: $name');
        return _selectedPrinter;
      }
    } catch (e) {
      debugPrint('❌ Error getting saved printer: $e');
    }
    return null;
  }

  static void setSelectedPrinter(Printer? printer) {
    _selectedPrinter = printer;
    _isConnected = false;
    _lastSuccessfulPrint = null;
    _consecutiveErrors = 0;
  }

  // ═══════════════════════════════════════════════════════════
  // SMART CONNECTION - OPTIMIZED
  // ═══════════════════════════════════════════════════════════

  static Future<bool> _smartConnect({bool forceReconnect = false}) async {
    if (_selectedPrinter == null) {
      _selectedPrinter = await getSavedPrinter();
      if (_selectedPrinter == null) {
        debugPrint('❌ No printer selected');
        return false;
      }
    }

    // CHECK 1: Force reconnect if too many errors
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      debugPrint(
          '⚠️ Too many errors ($_consecutiveErrors), forcing reconnect...');
      forceReconnect = true;
      _consecutiveErrors = 0;
    }

    // CHECK 2: Is connection fresh?
    if (!forceReconnect &&
        _isConnected &&
        _lastSuccessfulPrint != null &&
        DateTime.now().difference(_lastSuccessfulPrint!) < _connectionTimeout) {
      final age = DateTime.now().difference(_lastSuccessfulPrint!).inSeconds;
      debugPrint('✅ Using cached connection (${age}s old) - FAST PATH!');
      return true;
    }

    // NEED TO CONNECT/RECONNECT
    try {
      debugPrint(
          '⏳ ${forceReconnect ? "Reconnecting" : "Connecting"} to: ${_selectedPrinter!.name}');

      // Only disconnect if we were previously connected
      if (_isConnected || forceReconnect) {
        try {
          await _printer.disconnect(_selectedPrinter!);
          await Future.delayed(const Duration(milliseconds: 150));
          debugPrint('🔌 Disconnected old connection');
        } catch (e) {
          debugPrint('ℹ️ Disconnect skip: $e');
        }
      }

      // Connect with REDUCED timeout
      await _printer.connect(_selectedPrinter!).timeout(
        const Duration(seconds: 20), // ← REDUCED: 5 seconds
        onTimeout: () {
          throw TimeoutException('Connection timeout (20s)');
        },
      );

      _isConnected = true;
      _lastSuccessfulPrint = DateTime.now();
      _consecutiveErrors = 0;

      debugPrint('✅ Connected successfully!');
      return true;
    } catch (e) {
      debugPrint('❌ Connection failed: $e');
      _isConnected = false;
      _lastSuccessfulPrint = null;
      _consecutiveErrors++;
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // QUEUE-BASED PRINTING (PREVENT CONFLICTS)
  // ═══════════════════════════════════════════════════════════

  static Future<bool> _executePrintJob(Future<bool> Function() job) async {
    _printQueue.add(job);

    if (_isPrinting) {
      debugPrint('⏸️ Print queued, waiting...');
      while (_isPrinting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _isPrinting = true;
    try {
      final result = await job();
      _printQueue.remove(job);
      return result;
    } finally {
      _isPrinting = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PRINT TEST - OPTIMIZED
  // ═══════════════════════════════════════════════════════════

  static Future<bool> printTest() async {
    return await _executePrintJob(() async {
      try {
        debugPrint('🖨️ Test print starting...');

        if (!await _smartConnect()) {
          debugPrint('⚠️ First attempt failed, retrying once...');
          if (!await _smartConnect(forceReconnect: true)) {
            debugPrint('❌ Connection failed after retry');
            return false;
          }
        }

        final generator = await _getGenerator();
        List<int> bytes = [];

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
        bytes += generator.cut();

        await _printer.printData(_selectedPrinter!, bytes);
        _lastSuccessfulPrint = DateTime.now();
        _consecutiveErrors = 0;

        debugPrint('✅ Test print successful!');
        return true;
      } catch (e) {
        debugPrint('❌ Print failed: $e');
        _isConnected = false;
        _consecutiveErrors++;
        return false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // PRINT RECEIPT - OPTIMIZED (NO AUTO-RETRY)
  // ═══════════════════════════════════════════════════════════

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
    String? tokoAlamat,
    String? tokoTelepon,
  }) async {
    return await _executePrintJob(() async {
      try {
        final startTime = DateTime.now();
        debugPrint('🖨️ Receipt print starting...');

        // Try to connect (single attempt for speed)
        if (!await _smartConnect()) {
          debugPrint('❌ Cannot connect to printer');
          return false;
        }

        // Build receipt (cached generator = FAST!)
        final generator = await _getGenerator();
        final bytes = _buildReceiptBytes(
          generator: generator,
          orderId: orderId,
          tokoNama: tokoNama,
          items: items,
          totalHarga: totalHarga,
          jenisOrder: jenisOrder,
          mejaNo: mejaNo,
          catatan: catatan,
          metodeBayar: metodeBayar,
          kasirNama: kasirNama,
          tokoAlamat: tokoAlamat,
          tokoTelepon: tokoTelepon,
        );

        // Send to printer with REDUCED timeout
        await _printer.printData(_selectedPrinter!, bytes).timeout(
          const Duration(seconds: 10), // ← REDUCED: 10 seconds
          onTimeout: () {
            throw TimeoutException('Print timeout (10s)');
          },
        );

        _lastSuccessfulPrint = DateTime.now();
        _consecutiveErrors = 0;

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        debugPrint('✅ Receipt printed in ${elapsed}ms!');
        return true;
      } catch (e) {
        debugPrint('❌ Print error: $e');
        _isConnected = false;
        _consecutiveErrors++;
        return false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD RECEIPT BYTES
  // ═══════════════════════════════════════════════════════════

  static List<int> _buildReceiptBytes({
    required Generator generator,
    required String orderId,
    required String tokoNama,
    required List<Map<String, dynamic>> items,
    required double totalHarga,
    int jenisOrder = 1,
    String? mejaNo,
    String? catatan,
    int? metodeBayar,
    String? kasirNama,
    String? tokoAlamat,
    String? tokoTelepon,
  }) {
    List<int> bytes = [];

    // Logo
    bytes += generator.text('OrderKuy!',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    bytes += generator.emptyLines(1);

    // Toko info
    bytes += generator.text(tokoNama,
        styles: const PosStyles(align: PosAlign.center, bold: true));

    if (tokoAlamat != null && tokoAlamat.isNotEmpty) {
      bytes += generator.text(tokoAlamat,
          styles: const PosStyles(align: PosAlign.center));
    }

    if (tokoTelepon != null && tokoTelepon.isNotEmpty) {
      bytes += generator.text('Telp: $tokoTelepon',
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    // Order info
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    bytes += generator.row([
      PosColumn(
          text: 'No. Nota:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: '#${orderId.padLeft(6, '0')}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Tanggal:',
          width: 4,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: dateStr,
          width: 8,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (kasirNama != null && kasirNama.isNotEmpty) {
      bytes += generator.row([
        PosColumn(
            text: 'Kasir:',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: kasirNama,
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.row([
      PosColumn(
          text: 'Jenis:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: jenisOrder == 1 ? 'Dine In' : 'Take Away',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (jenisOrder == 1 && mejaNo != null) {
      bytes += generator.row([
        PosColumn(
            text: 'Meja:',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: mejaNo,
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    // Items
    bytes += generator.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    double subtotal = 0;
    for (var item in items) {
      final nama = item['nama_produk'] ?? '';
      final qty = item['qty'] ?? 0;
      final harga = (item['harga'] is double)
          ? item['harga'] as double
          : double.parse(item['harga'].toString());
      final itemTotal = qty * harga;
      subtotal += itemTotal;

      bytes += generator.text(nama,
          styles: const PosStyles(bold: true, align: PosAlign.left));
      bytes += generator.row([
        PosColumn(
            text: '$qty x ${_formatRupiah(harga)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: _formatRupiah(itemTotal),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    // Subtotal
    bytes += generator.row([
      PosColumn(
          text: 'Subtotal:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: _formatRupiah(subtotal),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    // Tax/Discount
    if ((totalHarga - subtotal).abs() > 0.01) {
      final difference = totalHarga - subtotal;
      bytes += generator.row([
        PosColumn(
            text: difference > 0 ? 'Pajak/Biaya:' : 'Diskon:',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: difference > 0
                ? _formatRupiah(difference)
                : '-${_formatRupiah(difference.abs())}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    // Total
    bytes += generator.row([
      PosColumn(
          text: 'TOTAL:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(
          text: _formatRupiah(totalHarga),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    // Notes
    if (catatan != null && catatan.isNotEmpty) {
      bytes += generator.text('Catatan:',
          styles: const PosStyles(align: PosAlign.left, bold: true));
      bytes += generator.text(catatan,
          styles: const PosStyles(align: PosAlign.left));
      bytes += generator.emptyLines(1);
    }

    // Footer
    bytes += generator.text('Terima Kasih',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Selamat Menikmati',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Powered by OrderKuy!',
        styles: const PosStyles(align: PosAlign.center));

    final footerDate =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    bytes += generator.text(footerDate,
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.cut();
    return bytes;
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  static String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    )}';
  }

  static bool isConnected() => _isConnected && _selectedPrinter != null;

  static Printer? getCurrentPrinter() => _selectedPrinter;

  static void clearConnectionState() {
    _isConnected = false;
    _lastSuccessfulPrint = null;
    _consecutiveErrors = 0;
    debugPrint('🧹 Connection state cleared');
  }

  static Future<bool> forceReconnect() async {
    clearConnectionState();
    return await _smartConnect(forceReconnect: true);
  }

  static int getConsecutiveErrors() => _consecutiveErrors;

  // ═══════════════════════════════════════════════════════════
  // BACKWARD COMPATIBILITY
  // ═══════════════════════════════════════════════════════════

  static Future<bool> ensureConnected() async {
    debugPrint('ℹ️ ensureConnected() called (using _smartConnect)');
    return await _smartConnect();
  }

  static Future<bool> connectPrinter(Printer printer) async {
    debugPrint('ℹ️ connectPrinter() called (using _smartConnect with force)');
    _selectedPrinter = printer;
    return await _smartConnect(forceReconnect: true);
  }

  static int getConnectionAge() {
    if (_lastSuccessfulPrint == null) return -1;
    return DateTime.now().difference(_lastSuccessfulPrint!).inSeconds;
  }

  static String getDebugInfo() {
    return '''
    Connected: $_isConnected
    Errors: $_consecutiveErrors
    Last Print: ${_lastSuccessfulPrint?.toString() ?? 'Never'}
    Connection Age: ${getConnectionAge()}s
    Printer: ${_selectedPrinter?.name ?? 'None'}
    ''';
  }
}
