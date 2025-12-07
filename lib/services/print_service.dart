import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class ThermalPrintService {
  static final FlutterThermalPrinter _printer = FlutterThermalPrinter.instance;
  static Printer? _selectedPrinter;
  static bool _isConnected = false;
  static DateTime? _lastConnectionAttempt;

  // Singleton pattern
  static final ThermalPrintService _instance = ThermalPrintService._internal();
  factory ThermalPrintService() => _instance;
  ThermalPrintService._internal();

  // Load logo image from assets
  static Future<img.Image?> _loadLogoImage() async {
    try {
      final ByteData data = await rootBundle.load('assets/icon/orderkuy.png');
      final Uint8List bytes = data.buffer.asUint8List();
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Failed to decode image');
        return null;
      }
      return image;
    } catch (e) {
      debugPrint('Error loading logo image: $e');
      return null;
    }
  }

  // Get list of available printers
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

      if (_selectedPrinter?.address != printer.address) {
        _selectedPrinter = printer;
        _isConnected = false;
      }

      debugPrint('Printer saved: ${printer.name}');
    } catch (e) {
      debugPrint('Error saving printer: $e');
    }
  }

  // Get saved printer
  static Future<Printer?> getSavedPrinter() async {
    try {
      if (_selectedPrinter != null) {
        debugPrint(
            'Returning existing printer instance: ${_selectedPrinter!.name}');
        return _selectedPrinter;
      }

      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('printer_address');
      final name = prefs.getString('printer_name');

      if (address != null && name != null) {
        _selectedPrinter = Printer(address: address, name: name);
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

  // Connect to printer
  static Future<bool> connectPrinter(Printer printer) async {
    try {
      if (_isConnected &&
          _selectedPrinter?.address == printer.address &&
          _lastConnectionAttempt != null &&
          DateTime.now().difference(_lastConnectionAttempt!) <
              const Duration(seconds: 30)) {
        debugPrint('Already connected to printer: ${printer.name}');
        return true;
      }

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

  // Ensure connected
  static Future<bool> ensureConnected() async {
    if (_selectedPrinter == null) {
      _selectedPrinter = await getSavedPrinter();
      if (_selectedPrinter == null) {
        debugPrint('No printer selected');
        return false;
      }
    }

    if (_isConnected &&
        _lastConnectionAttempt != null &&
        DateTime.now().difference(_lastConnectionAttempt!) <
            const Duration(seconds: 30)) {
      debugPrint(
          'Using existing connection (${DateTime.now().difference(_lastConnectionAttempt!).inSeconds}s ago)');
      return true;
    }

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
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
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

      // Load and print logo image
      final logoImage = await _loadLogoImage();
      if (logoImage != null) {
        bytes += generator.imageRaster(logoImage, align: PosAlign.center);
      }

      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Printer berhasil terhubung',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(DateTime.now().toString().substring(0, 19),
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(3);
      bytes += generator.cut();

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
    String? tokoAlamat,
    String? tokoTelepon,
  }) async {
    try {
      debugPrint('=== Starting Receipt Print ===');
      debugPrint('Toko: $tokoNama');
      debugPrint('Kasir: ${kasirNama ?? "NULL"}');
      debugPrint('Alamat: ${tokoAlamat ?? "NULL"}');

      if (!await ensureConnected()) {
        debugPrint('Failed to connect to printer');
        return false;
      }

      debugPrint('Creating receipt data...');
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // Logo/Brand
      final logoImage = await _loadLogoImage();
      if (logoImage != null) {
        bytes += generator.imageRaster(logoImage, align: PosAlign.center);
      }

      bytes += generator.emptyLines(1);

      // Header - Nama Toko
      bytes += generator.text(tokoNama,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size3,
            width: PosTextSize.size3,
          ));

      // Alamat Toko
      if (tokoAlamat != null && tokoAlamat.isNotEmpty) {
        bytes += generator.text(tokoAlamat,
            styles: const PosStyles(align: PosAlign.center));
      }

      // Telepon Toko
      if (tokoTelepon != null && tokoTelepon.isNotEmpty) {
        bytes += generator.text('Telp: $tokoTelepon',
            styles: const PosStyles(align: PosAlign.center));
      }

      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));

      // Info Pesanan
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // No. Nota
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

      // Tanggal
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

      // Kasir
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

      // Jenis Order
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

      // Meja
      if (jenisOrder == 1 && mejaNo != null && mejaNo.isNotEmpty) {
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

      // Items Section
      bytes += generator.text('--------------------------------',
          styles: const PosStyles(align: PosAlign.center));

      double subtotal = 0;
      for (var item in items) {
        final nama = item['nama_produk'] ?? '';
        final qty = item['qty'] ?? 0;
        final harga = (item['harga'] is double)
            ? item['harga'] as double
            : double.tryParse(item['harga'].toString()) ?? 0.0;
        final itemTotal = qty * harga;
        subtotal += itemTotal;

        // Nama produk - BOLD
        bytes += generator.text(nama,
            styles: const PosStyles(bold: true, align: PosAlign.left));

        // Qty x Harga = Total
        bytes += generator.row([
          PosColumn(
            text: '$qty x ${_formatRupiah(harga)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: _formatRupiah(itemTotal),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
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

      // Pajak/Diskon
      if ((totalHarga - subtotal).abs() > 0.01) {
        final difference = totalHarga - subtotal;
        if (difference > 0) {
          bytes += generator.row([
            PosColumn(
                text: 'Pajak/Biaya:',
                width: 6,
                styles: const PosStyles(align: PosAlign.left)),
            PosColumn(
                text: _formatRupiah(difference),
                width: 6,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        } else if (difference < 0) {
          bytes += generator.row([
            PosColumn(
                text: 'Diskon:',
                width: 6,
                styles: const PosStyles(align: PosAlign.left)),
            PosColumn(
                text: '-${_formatRupiah(difference.abs())}',
                width: 6,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        }
      }

      // Separator
      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));

      // TOTAL
      bytes += generator.row([
        PosColumn(
          text: 'TOTAL:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left, bold: true),
        ),
        PosColumn(
          text: _formatRupiah(totalHarga),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);

      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));

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

      bytes += generator.feed(3);
      bytes += generator.cut();

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

  // Clear connection state
  static void clearConnectionState() {
    _isConnected = false;
    _lastConnectionAttempt = null;
    debugPrint('Connection state cleared');
  }
}
