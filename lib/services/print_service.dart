import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipe printer yang tersedia
enum PrinterRole { kasir, dapur }

class ThermalPrintService {
  static final FlutterThermalPrinter _printer = FlutterThermalPrinter.instance;

  // ── Dual Printer State ──────────────────────────────────────────────────────
  static Printer? _kasirPrinter;
  static Printer? _dapurPrinter;

  static bool _kasirConnected = false;
  static bool _dapurConnected = false;

  static DateTime? _kasirLastPrint;
  static DateTime? _dapurLastPrint;

  static int _kasirErrors = 0;
  static int _dapurErrors = 0;

  // ── Cache Generator (load sekali, pakai terus) ──────────────────────────────
  static CapabilityProfile? _cachedProfile;
  static Generator? _cachedGenerator;

  // ── Settings ────────────────────────────────────────────────────────────────
  // Koneksi dianggap masih segar selama 30 detik sejak print terakhir
  static const Duration _connectionFreshDuration = Duration(seconds: 30);
  static const int _maxErrors = 3;

  // ── SEPARATE queue per printer ─────────────────────────────────────────────
  // Ini kunci utama agar kedua printer tidak saling block
  static bool _kasirPrinting = false;
  static bool _dapurPrinting = false;

  // ── SharedPrefs Keys ────────────────────────────────────────────────────────
  static const _kKasirAddress = 'printer_kasir_address';
  static const _kKasirName = 'printer_kasir_name';
  static const _kDapurAddress = 'printer_dapur_address';
  static const _kDapurName = 'printer_dapur_name';

  // Singleton
  static final ThermalPrintService _instance = ThermalPrintService._internal();
  factory ThermalPrintService() => _instance;
  ThermalPrintService._internal();

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERATOR (load sekali, cache selamanya)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Generator> _getGenerator() async {
    if (_cachedGenerator != null) return _cachedGenerator!;
    _cachedProfile = await CapabilityProfile.load();
    _cachedGenerator = Generator(PaperSize.mm58, _cachedProfile!);
    debugPrint('✅ Generator cached');
    return _cachedGenerator!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCAN PRINTERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<Printer>> getAvailablePrinters() async {
    try {
      await _printer.getPrinters();
      final printers = <Printer>[];
      await for (final list in _printer.devicesStream.take(1)) {
        printers.addAll(list);
        break;
      }
      return printers;
    } catch (e) {
      debugPrint('❌ Error getting printers: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE & LOAD
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> savePrinter(Printer printer, PrinterRole role) async {
    final prefs = await SharedPreferences.getInstance();
    if (role == PrinterRole.kasir) {
      await prefs.setString(_kKasirAddress, printer.address ?? '');
      await prefs.setString(_kKasirName, printer.name ?? '');
      if (_kasirPrinter?.address != printer.address) {
        _kasirPrinter = printer;
        _kasirConnected = false;
        _kasirLastPrint = null;
        _kasirErrors = 0;
      }
    } else {
      await prefs.setString(_kDapurAddress, printer.address ?? '');
      await prefs.setString(_kDapurName, printer.name ?? '');
      if (_dapurPrinter?.address != printer.address) {
        _dapurPrinter = printer;
        _dapurConnected = false;
        _dapurLastPrint = null;
        _dapurErrors = 0;
      }
    }
    debugPrint('✅ ${role.name} printer saved: ${printer.name}');
  }

  static Future<Printer?> getSavedPrinter(
      {PrinterRole role = PrinterRole.kasir}) async {
    try {
      if (role == PrinterRole.kasir) {
        if (_kasirPrinter != null) return _kasirPrinter;
        final prefs = await SharedPreferences.getInstance();
        final address = prefs.getString(_kKasirAddress);
        final name = prefs.getString(_kKasirName);
        if (address != null && address.isNotEmpty) {
          _kasirPrinter = Printer(address: address, name: name ?? '');
          return _kasirPrinter;
        }
      } else {
        if (_dapurPrinter != null) return _dapurPrinter;
        final prefs = await SharedPreferences.getInstance();
        final address = prefs.getString(_kDapurAddress);
        final name = prefs.getString(_kDapurName);
        if (address != null && address.isNotEmpty) {
          _dapurPrinter = Printer(address: address, name: name ?? '');
          return _dapurPrinter;
        }
      }
    } catch (e) {
      debugPrint('❌ getSavedPrinter error: $e');
    }
    return null;
  }

  static Future<void> removePrinter(PrinterRole role) async {
    final prefs = await SharedPreferences.getInstance();
    if (role == PrinterRole.kasir) {
      await prefs.remove(_kKasirAddress);
      await prefs.remove(_kKasirName);
      _kasirPrinter = null;
      _kasirConnected = false;
      _kasirLastPrint = null;
      _kasirErrors = 0;
    } else {
      await prefs.remove(_kDapurAddress);
      await prefs.remove(_kDapurName);
      _dapurPrinter = null;
      _dapurConnected = false;
      _dapurLastPrint = null;
      _dapurErrors = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SMART CONNECT — CEPAT
  // Kunci optimasi: skip disconnect jika koneksi masih segar
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> _smartConnect(PrinterRole role,
      {bool force = false}) async {
    final isKasir = role == PrinterRole.kasir;
    Printer? target = isKasir ? _kasirPrinter : _dapurPrinter;

    // Load dari prefs jika belum ada di memory
    if (target == null) {
      target = await getSavedPrinter(role: role);
      if (target == null) {
        debugPrint('⚠️ Tidak ada ${role.name} printer yang dikonfigurasi');
        return false;
      }
    }

    final errors = isKasir ? _kasirErrors : _dapurErrors;
    final connected = isKasir ? _kasirConnected : _dapurConnected;
    final lastPrint = isKasir ? _kasirLastPrint : _dapurLastPrint;

    // Terlalu banyak error → paksa reconnect, reset counter
    if (errors >= _maxErrors) {
      force = true;
      if (isKasir)
        _kasirErrors = 0;
      else
        _dapurErrors = 0;
    }

    // ─── FAST PATH: koneksi masih segar, skip reconnect ───────────────────
    if (!force &&
        connected &&
        lastPrint != null &&
        DateTime.now().difference(lastPrint) < _connectionFreshDuration) {
      debugPrint('⚡ ${role.name} fast path (koneksi masih segar)');
      return true;
    }

    // ─── CONNECT ──────────────────────────────────────────────────────────
    try {
      debugPrint('🔗 Connecting ${role.name} printer: ${target.name}');

      // Hanya disconnect jika benar-benar perlu (force/error recovery)
      // Tidak disconnect jika ini koneksi pertama — hemat waktu ~1-2 detik
      if (force && connected) {
        try {
          await _printer.disconnect(target);
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (_) {}
      }

      await _printer.connect(target).timeout(
            const Duration(seconds: 8), // ← Turun dari 20s ke 8s
            onTimeout: () => throw TimeoutException('Connection timeout 8s'),
          );

      final now = DateTime.now();
      if (isKasir) {
        _kasirConnected = true;
        _kasirLastPrint = now;
        _kasirErrors = 0;
      } else {
        _dapurConnected = true;
        _dapurLastPrint = now;
        _dapurErrors = 0;
      }

      debugPrint('✅ ${role.name} connected!');
      return true;
    } catch (e) {
      debugPrint('❌ ${role.name} connect failed: $e');
      if (isKasir) {
        _kasirConnected = false;
        _kasirErrors++;
      } else {
        _dapurConnected = false;
        _dapurErrors++;
      }
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUEUE PER PRINTER (bukan queue global)
  // Ini yang fix masalah dapur tidak print
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> _runKasirJob(Future<bool> Function() job) async {
    // Tunggu jika kasir sedang printing
    while (_kasirPrinting) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _kasirPrinting = true;
    try {
      return await job();
    } finally {
      _kasirPrinting = false;
    }
  }

  static Future<bool> _runDapurJob(Future<bool> Function() job) async {
    // Tunggu jika dapur sedang printing
    while (_dapurPrinting) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _dapurPrinting = true;
    try {
      return await job();
    } finally {
      _dapurPrinting = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST PRINT
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> printTest({PrinterRole role = PrinterRole.kasir}) async {
    final runJob = role == PrinterRole.kasir ? _runKasirJob : _runDapurJob;
    return runJob(() async {
      try {
        if (!await _smartConnect(role, force: true)) return false;

        final generator = await _getGenerator();
        final target =
            role == PrinterRole.kasir ? _kasirPrinter! : _dapurPrinter!;
        final label =
            role == PrinterRole.kasir ? '[PRINTER KASIR]' : '[PRINTER DAPUR]';

        List<int> bytes = [];
        bytes += generator.text('================================',
            styles: const PosStyles(align: PosAlign.center));
        bytes += generator.text('TEST PRINT',
            styles: const PosStyles(
                align: PosAlign.center,
                height: PosTextSize.size2,
                width: PosTextSize.size2,
                bold: true));
        bytes += generator.text('ORDERKUY!',
            styles: const PosStyles(
                align: PosAlign.center,
                height: PosTextSize.size2,
                width: PosTextSize.size2,
                bold: true));
        bytes += generator.text(label,
            styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.text('================================',
            styles: const PosStyles(align: PosAlign.center));
        bytes += generator.text('Printer berhasil terhubung',
            styles: const PosStyles(align: PosAlign.center));
        bytes += generator.text(DateTime.now().toString().substring(0, 19),
            styles: const PosStyles(align: PosAlign.center));
        bytes += generator.feed(3);
        bytes += generator.cut();

        await _printer.printData(target, bytes);

        _updateLastPrint(role);
        debugPrint('✅ Test print ${role.name} OK');
        return true;
      } catch (e) {
        debugPrint('❌ Test print ${role.name} error: $e');
        _markError(role);
        return false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRINT RECEIPT (Struk Kasir)
  // ═══════════════════════════════════════════════════════════════════════════

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
    return _runKasirJob(() async {
      try {
        // Cek apakah printer kasir dikonfigurasi
        final p = await getSavedPrinter(role: PrinterRole.kasir);
        if (p == null) {
          debugPrint('⚠️ Printer kasir belum dikonfigurasi, skip');
          return false;
        }

        if (!await _smartConnect(PrinterRole.kasir)) {
          debugPrint('❌ Kasir connect failed');
          return false;
        }

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

        await _printer.printData(_kasirPrinter!, bytes).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw TimeoutException('Kasir print timeout'),
            );

        _updateLastPrint(PrinterRole.kasir);
        debugPrint('✅ Kasir receipt printed');
        return true;
      } catch (e) {
        debugPrint('❌ printReceipt error: $e');
        _markError(PrinterRole.kasir);
        return false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRINT KITCHEN ORDER (Nota Dapur)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> printKitchenOrder({
    required String orderId,
    required List<Map<String, dynamic>> items,
    int jenisOrder = 1,
    String? mejaNo,
    String? catatan,
    String? kasirNama,
  }) async {
    return _runDapurJob(() async {
      try {
        // Cek apakah printer dapur dikonfigurasi
        final p = await getSavedPrinter(role: PrinterRole.dapur);
        if (p == null) {
          debugPrint('⚠️ Printer dapur belum dikonfigurasi, skip');
          return false;
        }

        if (!await _smartConnect(PrinterRole.dapur)) {
          debugPrint('❌ Dapur connect failed');
          return false;
        }

        final generator = await _getGenerator();
        final bytes = _buildKitchenBytes(
          generator: generator,
          orderId: orderId,
          items: items,
          jenisOrder: jenisOrder,
          mejaNo: mejaNo,
          catatan: catatan,
          kasirNama: kasirNama,
        );

        await _printer.printData(_dapurPrinter!, bytes).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw TimeoutException('Dapur print timeout'),
            );

        _updateLastPrint(PrinterRole.dapur);
        debugPrint('✅ Kitchen order printed');
        return true;
      } catch (e) {
        debugPrint('❌ printKitchenOrder error: $e');
        _markError(PrinterRole.dapur);
        return false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRINT ALL — Sequential tapi non-blocking satu sama lain
  //
  // Kenapa sequential bukan parallel?
  // Bluetooth pada Android tidak bisa handle 2 koneksi aktif secara bersamaan
  // dengan baik. Sequential jauh lebih reliable.
  // Kasir dicetak dulu (user butuh struk), lalu dapur di background.
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<bool>> printAll({
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
    // Step 1: Kasir dulu (user nunggu struk ini)
    final kasirOk = await printReceipt(
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

    // Step 2: Dapur setelah kasir selesai
    // Delay singkat agar Bluetooth adapter bisa switch koneksi
    await Future.delayed(const Duration(milliseconds: 300));

    final dapurOk = await printKitchenOrder(
      orderId: orderId,
      items: items,
      jenisOrder: jenisOrder,
      mejaNo: mejaNo,
      catatan: catatan,
      kasirNama: kasirNama,
    );

    debugPrint('📊 Print results → Kasir: $kasirOk, Dapur: $dapurOk');
    return [kasirOk, dapurOk];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD RECEIPT BYTES
  // ═══════════════════════════════════════════════════════════════════════════

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
    final now = DateTime.now();
    final dateStr =
        '${_pad(now.day)}/${_pad(now.month)}/${now.year} ${_pad(now.hour)}:${_pad(now.minute)}';

    bytes += generator.text('OrderKuy!',
        styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true));
    bytes += generator.emptyLines(1);
    bytes += generator.text(tokoNama,
        styles: const PosStyles(align: PosAlign.center, bold: true));
    if (tokoAlamat != null && tokoAlamat.isNotEmpty)
      bytes += generator.text(tokoAlamat,
          styles: const PosStyles(align: PosAlign.center));
    if (tokoTelepon != null && tokoTelepon.isNotEmpty)
      bytes += generator.text('Telp: $tokoTelepon',
          styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

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
    if (kasirNama != null && kasirNama.isNotEmpty)
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
    if (jenisOrder == 1 && mejaNo != null)
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

    bytes += generator.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    double subtotal = 0;
    for (var item in items) {
      final nama = item['nama_produk'] ?? '';
      final qty = item['qty'] ?? 0;
      final harga = (item['harga'] is double)
          ? item['harga'] as double
          : double.parse(item['harga'].toString());
      final total = qty * harga;
      subtotal += total;
      bytes += generator.text(nama,
          styles: const PosStyles(bold: true, align: PosAlign.left));
      bytes += generator.row([
        PosColumn(
            text: '$qty x ${_formatRupiah(harga)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: _formatRupiah(total),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));
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

    if ((totalHarga - subtotal).abs() > 0.01) {
      final diff = totalHarga - subtotal;
      bytes += generator.row([
        PosColumn(
            text: diff > 0 ? 'Pajak/Biaya:' : 'Diskon:',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: diff > 0
                ? _formatRupiah(diff)
                : '-${_formatRupiah(diff.abs())}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));
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

    if (catatan != null && catatan.isNotEmpty) {
      bytes += generator.text('Catatan:',
          styles: const PosStyles(align: PosAlign.left, bold: true));
      bytes += generator.text(catatan,
          styles: const PosStyles(align: PosAlign.left));
      bytes += generator.emptyLines(1);
    }

    bytes += generator.text('Terima Kasih',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Selamat Menikmati',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Powered by OrderKuy!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(3);
    bytes += generator.cut();
    return bytes;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD KITCHEN BYTES
  // ═══════════════════════════════════════════════════════════════════════════

  static List<int> _buildKitchenBytes({
    required Generator generator,
    required String orderId,
    required List<Map<String, dynamic>> items,
    int jenisOrder = 1,
    String? mejaNo,
    String? catatan,
    String? kasirNama,
  }) {
    List<int> bytes = [];
    final now = DateTime.now();
    final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';

    bytes += generator.text('*** NOTA DAPUR ***',
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));
    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.row([
      PosColumn(
          text: 'Order #:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(
          text: orderId.padLeft(6, '0'),
          width: 6,
          styles: const PosStyles(
              align: PosAlign.right,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);
    bytes += generator.row([
      PosColumn(
          text: 'Waktu:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: timeStr,
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(
          text: 'Jenis:',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
          text: jenisOrder == 1 ? 'DINE IN' : 'TAKE AWAY',
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    if (jenisOrder == 1 && mejaNo != null)
      bytes += generator.row([
        PosColumn(
            text: 'MEJA:',
            width: 6,
            styles: const PosStyles(align: PosAlign.left, bold: true)),
        PosColumn(
            text: mejaNo,
            width: 6,
            styles: const PosStyles(
                align: PosAlign.right,
                bold: true,
                height: PosTextSize.size2,
                width: PosTextSize.size2)),
      ]);
    if (kasirNama != null && kasirNama.isNotEmpty)
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

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('ITEM PESANAN:',
        styles: const PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    for (var item in items) {
      final nama = item['nama_produk'] ?? '';
      final qty = item['qty'] ?? 0;
      bytes += generator.row([
        PosColumn(
            text: '${qty}x',
            width: 2,
            styles: const PosStyles(
                align: PosAlign.left,
                bold: true,
                height: PosTextSize.size2,
                width: PosTextSize.size2)),
        PosColumn(
            text: nama,
            width: 10,
            styles: const PosStyles(
                align: PosAlign.left, height: PosTextSize.size2)),
      ]);
    }

    bytes += generator.text('================================',
        styles: const PosStyles(align: PosAlign.center));

    if (catatan != null && catatan.isNotEmpty) {
      bytes += generator.text('!! CATATAN:',
          styles: const PosStyles(align: PosAlign.left, bold: true));
      bytes += generator.text(catatan,
          styles:
              const PosStyles(align: PosAlign.left, height: PosTextSize.size2));
      bytes += generator.text('================================',
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += generator.feed(3);
    bytes += generator.cut();
    return bytes;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _formatRupiah(double amount) {
    final f = amount.toStringAsFixed(0);
    return 'Rp${f.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    )}';
  }

  static void _updateLastPrint(PrinterRole role) {
    final now = DateTime.now();
    if (role == PrinterRole.kasir) {
      _kasirLastPrint = now;
      _kasirErrors = 0;
    } else {
      _dapurLastPrint = now;
      _dapurErrors = 0;
    }
  }

  static void _markError(PrinterRole role) {
    if (role == PrinterRole.kasir) {
      _kasirConnected = false;
      _kasirErrors++;
    } else {
      _dapurConnected = false;
      _dapurErrors++;
    }
  }

  // ─── Status ────────────────────────────────────────────────────────────────

  static bool isConnected({PrinterRole role = PrinterRole.kasir}) =>
      role == PrinterRole.kasir
          ? _kasirConnected && _kasirPrinter != null
          : _dapurConnected && _dapurPrinter != null;

  static Printer? getPrinter(PrinterRole role) =>
      role == PrinterRole.kasir ? _kasirPrinter : _dapurPrinter;

  static void clearConnectionState({PrinterRole? role}) {
    if (role == null || role == PrinterRole.kasir) {
      _kasirConnected = false;
      _kasirLastPrint = null;
      _kasirErrors = 0;
    }
    if (role == null || role == PrinterRole.dapur) {
      _dapurConnected = false;
      _dapurLastPrint = null;
      _dapurErrors = 0;
    }
  }

  static Future<bool> connectPrinter(Printer printer,
      {PrinterRole role = PrinterRole.kasir}) async {
    if (role == PrinterRole.kasir)
      _kasirPrinter = printer;
    else
      _dapurPrinter = printer;
    return _smartConnect(role, force: true);
  }

  // ─── Backward compatibility (dipakai pesanan_screen.dart) ─────────────────

  static void setSelectedPrinter(Printer? printer) {
    _kasirPrinter = printer;
    _kasirConnected = false;
    _kasirLastPrint = null;
    _kasirErrors = 0;
  }

  static Future<bool> ensureConnected() async =>
      _smartConnect(PrinterRole.kasir);

  static int getConsecutiveErrors() => _kasirErrors;
  static int getConnectionAge() => _kasirLastPrint == null
      ? -1
      : DateTime.now().difference(_kasirLastPrint!).inSeconds;

  static Future<bool> forceReconnect() async {
    clearConnectionState();
    return _smartConnect(PrinterRole.kasir, force: true);
  }
}
