import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/print_service.dart';
import '../services/permission_service.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Printer> _printers = [];
  bool _isScanning = false;

  // Saved printers
  Printer? _savedKasir;
  Printer? _savedDapur;

  // Currently selected during scan session
  Printer? _pendingKasir;
  Printer? _pendingDapur;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedPrinters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPrinters() async {
    final kasir =
        await ThermalPrintService.getSavedPrinter(role: PrinterRole.kasir);
    final dapur =
        await ThermalPrintService.getSavedPrinter(role: PrinterRole.dapur);
    if (mounted) {
      setState(() {
        _savedKasir = kasir;
        _savedDapur = dapur;
        _pendingKasir = kasir;
        _pendingDapur = dapur;
      });
    }
  }

  Future<void> _scanPrinters() async {
    setState(() {
      _isScanning = true;
      _printers = [];
    });

    try {
      final granted =
          await PermissionService.requestBluetoothPermissions(context);
      if (!granted) {
        if (mounted) {
          setState(() => _isScanning = false);
          _showSnack(
              'Izin Bluetooth diperlukan untuk scan printer', Colors.red);
        }
        return;
      }

      final printers = await ThermalPrintService.getAvailablePrinters();
      if (mounted) {
        setState(() {
          _printers = printers;
          _isScanning = false;
        });
        if (printers.isEmpty) {
          _showSnack(
              'Tidak ada printer ditemukan. Pastikan printer Bluetooth aktif.',
              Colors.orange);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showSnack('Error scanning: $e', Colors.red);
      }
    }
  }

  Future<void> _selectPrinter(Printer printer, PrinterRole role) async {
    _showLoadingDialog('Menghubungkan ke printer...');

    try {
      await ThermalPrintService.savePrinter(printer, role);
      final connected =
          await ThermalPrintService.connectPrinter(printer, role: role)
              .timeout(const Duration(seconds: 15), onTimeout: () => false);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      setState(() {
        if (role == PrinterRole.kasir) {
          _savedKasir = printer;
          _pendingKasir = printer;
        } else {
          _savedDapur = printer;
          _pendingDapur = printer;
        }
      });

      final label = role == PrinterRole.kasir ? 'Kasir' : 'Dapur';
      if (connected) {
        _showSnack('Printer $label (${printer.name}) berhasil terhubung!',
            Colors.green);
      } else {
        _showSnack(
            'Printer $label tersimpan. Coba Test Print untuk koneksi ulang.',
            Colors.orange);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', Colors.red);
    }
  }

  Future<void> _testPrint(PrinterRole role) async {
    final saved = role == PrinterRole.kasir ? _savedKasir : _savedDapur;
    if (saved == null) {
      _showSnack(
          'Pilih printer ${role == PrinterRole.kasir ? "Kasir" : "Dapur"} terlebih dahulu',
          Colors.orange);
      return;
    }

    _showLoadingDialog('Testing printer...');
    try {
      final success = await ThermalPrintService.printTest(role: role)
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (!mounted) return;
      Navigator.pop(context);

      _showSnack(
        success
            ? 'Test print berhasil!'
            : 'Test print gagal. Pastikan printer aktif dan ada kertas.',
        success ? Colors.green : Colors.red,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', Colors.red);
    }
  }

  Future<void> _removePrinter(PrinterRole role) async {
    final label = role == PrinterRole.kasir ? 'Kasir' : 'Dapur';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text('Yakin ingin menghapus Printer $label?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ThermalPrintService.removePrinter(role);
      if (mounted) {
        setState(() {
          if (role == PrinterRole.kasir) {
            _savedKasir = null;
            _pendingKasir = null;
          } else {
            _savedDapur = null;
            _pendingDapur = null;
          }
        });
        _showSnack('Printer $label berhasil dihapus', Colors.green);
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 3)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Printer'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              icon: Icon(
                ThermalPrintService.isConnected(role: PrinterRole.kasir)
                    ? Icons.bluetooth_connected
                    : Icons.receipt_long,
                size: 20,
              ),
              text: 'Printer Kasir',
            ),
            Tab(
              icon: Icon(
                ThermalPrintService.isConnected(role: PrinterRole.dapur)
                    ? Icons.bluetooth_connected
                    : Icons.restaurant,
                size: 20,
              ),
              text: 'Printer Dapur',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Scan Button — shared untuk kedua tab
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanPrinters,
                icon: _isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
                label: Text(
                    _isScanning
                        ? 'Mencari Printer...'
                        : 'Scan Printer Bluetooth',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Pilih tab printer yang ingin dikonfigurasi, lalu ketuk printer dari daftar.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPrinterTab(PrinterRole.kasir, _savedKasir, _pendingKasir),
                _buildPrinterTab(PrinterRole.dapur, _savedDapur, _pendingDapur),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterTab(PrinterRole role, Printer? saved, Printer? pending) {
    final isKasir = role == PrinterRole.kasir;
    final label = isKasir ? 'Kasir' : 'Dapur';
    final icon = isKasir ? Icons.receipt_long : Icons.restaurant;
    final color = isKasir ? Colors.blue.shade700 : Colors.orange.shade700;

    return Column(
      children: [
        // ── Saved printer card ──────────────────────────────────────────────
        if (saved != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThermalPrintService.isConnected(role: role)
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ThermalPrintService.isConnected(role: role)
                    ? Colors.green.shade200
                    : Colors.blue.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Printer $label',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(width: 8),
                          _statusBadge(role),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(saved.name ?? 'Unknown',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(saved.address ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.grey.shade400, size: 32),
                const SizedBox(width: 12),
                Text('Printer $label belum dikonfigurasi',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),

        // ── Printer list ────────────────────────────────────────────────────
        Expanded(
          child: _printers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.print_disabled,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Tekan "Scan Printer" untuk mencari',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _printers.length,
                  itemBuilder: (ctx, i) {
                    final p = _printers[i];
                    final isSelected = (role == PrinterRole.kasir
                            ? _pendingKasir?.address
                            : _pendingDapur?.address) ==
                        p.address;

                    return Card(
                      elevation: isSelected ? 6 : 1,
                      margin: const EdgeInsets.only(bottom: 6),
                      color: isSelected ? color.withOpacity(0.1) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isSelected
                            ? BorderSide(color: color, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: Icon(Icons.print,
                            color: isSelected ? color : Colors.grey.shade500),
                        title: Text(p.name ?? 'Unknown Printer',
                            style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        subtitle: Text(p.address ?? ''),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: color)
                            : const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () => _selectPrinter(p, role),
                      ),
                    );
                  },
                ),
        ),

        // ── Action buttons ──────────────────────────────────────────────────
        if (saved != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _testPrint(role),
                    icon: const Icon(Icons.print),
                    label: Text('Test Print Printer $label',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: color, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => _removePrinter(role),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text('Hapus Printer $label'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusBadge(PrinterRole role) {
    final online = ThermalPrintService.isConnected(role: role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        online ? 'ONLINE' : 'OFFLINE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: online ? Colors.green.shade700 : Colors.grey.shade700,
        ),
      ),
    );
  }
}
