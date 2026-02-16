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

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  List<Printer> _printers = [];
  Printer? _selectedPrinter;
  Printer? _savedPrinter;
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final saved = await ThermalPrintService.getSavedPrinter();
    if (mounted) {
      setState(() {
        _savedPrinter = saved;
        _selectedPrinter = saved;
      });

      // Show connection status
      if (saved != null) {
        _showConnectionStatus();
      }
    }
  }

  void _showConnectionStatus() {
    final isConnected = ThermalPrintService.isConnected();
    final age = ThermalPrintService.getConnectionAge();

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🖨️ PRINTER STATUS:');
    debugPrint('Connected: $isConnected');
    debugPrint('Connection Age: ${age}s');
    debugPrint(
        'Consecutive Errors: ${ThermalPrintService.getConsecutiveErrors()}');
    debugPrint('Printer: ${_savedPrinter?.name}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  Future<void> _scanPrinters() async {
    setState(() {
      _isScanning = true;
      _printers = [];
    });

    try {
      // Request permissions
      final permissionsGranted =
          await PermissionService.requestBluetoothPermissions(context);

      if (!permissionsGranted) {
        if (mounted) {
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin Bluetooth diperlukan untuk scan printer'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      debugPrint('🔍 Scanning for printers...');
      final printers = await ThermalPrintService.getAvailablePrinters();
      debugPrint('📡 Found ${printers.length} printers');

      if (mounted) {
        setState(() {
          _printers = printers;
          _isScanning = false;
        });

        if (printers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Tidak ada printer ditemukan. Pastikan printer Bluetooth aktif.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectPrinter(Printer printer) async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);

    // Show connecting dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Menghubungkan ke printer...',
                      style: TextStyle(fontSize: 14)),
                  SizedBox(height: 8),
                  Text('Mohon tunggu...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🔗 Selecting printer: ${printer.name}');
      debugPrint('Address: ${printer.address}');

      // Step 1: Save printer first
      await ThermalPrintService.saveSelectedPrinter(printer);
      debugPrint('✅ Printer saved');

      // Step 2: Try to connect with longer timeout (RPP02N needs ~10s)
      debugPrint('⏳ Attempting connection...');
      final connected =
          await ThermalPrintService.connectPrinter(printer).timeout(
        const Duration(seconds: 15), // ← INCREASED: 15s for slow BLE printers
        onTimeout: () {
          debugPrint('⏰ Connection timeout after 15s!');
          return false;
        },
      );

      debugPrint('Connection result: $connected');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      setState(() {
        _selectedPrinter = printer;
        _savedPrinter = printer;
        _isConnecting = false;
      });

      if (connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Printer ${printer.name} berhasil terhubung!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Koneksi ke ${printer.name} gagal'),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Printer tersimpan. Tekan "Test Print" untuk coba lagi.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Select printer error: $e');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      setState(() => _isConnecting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _testPrint() async {
    if (_selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih printer terlebih dahulu'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading with better UI
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Testing printer...',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Mengirim data ke printer...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🖨️ Starting test print...');

      final startTime = DateTime.now();
      final success = await ThermalPrintService.printTest().timeout(
        const Duration(seconds: 20), // ← INCREASED: 20s total (connect + print)
        onTimeout: () {
          debugPrint('⏰ Print timeout after 20s!');
          return false;
        },
      );

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('Print completed in ${elapsed}ms');
      debugPrint('Success: $success');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (success) {
        _showConnectionStatus(); // Update status in console

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Test print berhasil!',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Print time: ${elapsed}ms',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Test print gagal'),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Pastikan:\n• Printer Bluetooth aktif\n• Printer tidak digunakan aplikasi lain\n• Printer ada kertas',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Test print error: $e');

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _clearSavedPrinter() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: const Text('Yakin ingin menghapus printer tersimpan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('printer_address');
        await prefs.remove('printer_name');

        ThermalPrintService.clearConnectionState();
        ThermalPrintService.setSelectedPrinter(null);

        if (mounted) {
          setState(() {
            _savedPrinter = null;
            _selectedPrinter = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Printer berhasil dihapus'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Printer'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (_savedPrinter != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    Icon(
                      ThermalPrintService.isConnected()
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      color: ThermalPrintService.isConnected()
                          ? Colors.greenAccent
                          : Colors.white70,
                      size: 20,
                    ),
                    if (_isConnecting) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Info Card
          if (_savedPrinter != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ThermalPrintService.isConnected()
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThermalPrintService.isConnected()
                      ? Colors.green.shade200
                      : Colors.blue.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ThermalPrintService.isConnected()
                        ? Icons.check_circle
                        : Icons.info_outline,
                    color: ThermalPrintService.isConnected()
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Printer Tersimpan',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ThermalPrintService.isConnected()
                                    ? Colors.green.shade100
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                ThermalPrintService.isConnected()
                                    ? 'ONLINE'
                                    : 'OFFLINE',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ThermalPrintService.isConnected()
                                      ? Colors.green.shade700
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _savedPrinter!.name ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _savedPrinter!.address ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ThermalPrintService.isConnected()
                              ? '✓ Siap untuk print'
                              : '⚠ Tekan "Test Print" untuk menghubungkan',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThermalPrintService.isConnected()
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Scan Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanPrinters,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _isScanning ? 'Mencari Printer...' : 'Scan Printer Bluetooth',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),

          // Printer List
          Expanded(
            child: _printers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.print_disabled,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak ada printer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tekan "Scan Printer" untuk mencari',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _printers.length,
                    itemBuilder: (context, index) {
                      final printer = _printers[index];
                      final isSelected =
                          _selectedPrinter?.address == printer.address;

                      return Card(
                        elevation: isSelected ? 8 : 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          leading: Icon(
                            Icons.print,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                            size: 32,
                          ),
                          title: Text(
                            printer.name ?? 'Unknown Printer',
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(printer.address ?? ''),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Colors.blue.shade700,
                                )
                              : const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _selectPrinter(printer),
                        ),
                      );
                    },
                  ),
          ),

          // Action Buttons
          if (_selectedPrinter != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _testPrint,
                      icon: const Icon(Icons.print),
                      label: const Text(
                        'Test Print & Koneksi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: OutlinedButton.icon(
                      onPressed: _clearSavedPrinter,
                      icon: const Icon(Icons.delete_forever, size: 20),
                      label: const Text('Hapus Printer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
