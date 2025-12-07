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
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload printer state when returning to this screen
    _refreshPrinterState();
  }

  Future<void> _refreshPrinterState() async {
    // Get saved printer (ini akan return existing instance jika ada)
    final saved = await ThermalPrintService.getSavedPrinter();
    if (mounted) {
      setState(() {
        _savedPrinter = saved;
        _selectedPrinter ??= saved;
      });

      // Try to reconnect silently jika ada saved printer
      if (saved != null && !ThermalPrintService.isConnected()) {
        _silentReconnect();
      }
    }
  }

  Future<void> _silentReconnect() async {
    if (_isReconnecting) return;

    setState(() => _isReconnecting = true);

    debugPrint('Attempting silent reconnection...');
    final success = await ThermalPrintService.ensureConnected();

    if (mounted) {
      setState(() => _isReconnecting = false);

      if (success) {
        debugPrint('Silent reconnection successful');
      } else {
        debugPrint('Silent reconnection failed');
      }
    }
  }

  Future<void> _loadSavedPrinter() async {
    final saved = await ThermalPrintService.getSavedPrinter();
    if (mounted) {
      setState(() {
        _savedPrinter = saved;
        _selectedPrinter = saved;
      });
    }
  }

  Future<void> _scanPrinters() async {
    setState(() {
      _isScanning = true;
      _printers = [];
    });

    try {
      // Request Bluetooth permissions first
      final permissionsGranted =
          await PermissionService.requestBluetoothPermissions(context);
      if (!permissionsGranted) {
        if (mounted) {
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Izin Bluetooth dan lokasi diperlukan untuk scan printer'),
              backgroundColor: Colors.red,
            ),
          );
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
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ada printer ditemukan'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectPrinter(Printer printer) async {
    // Show connecting dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Menyimpan dan menghubungkan printer...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Save printer
      await ThermalPrintService.saveSelectedPrinter(printer);

      // Try to connect immediately
      final connected = await ThermalPrintService.connectPrinter(printer);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      setState(() {
        _selectedPrinter = printer;
        _savedPrinter = printer;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            connected
                ? 'Printer ${printer.name} berhasil disimpan dan terhubung'
                : 'Printer ${printer.name} berhasil disimpan (koneksi gagal)',
          ),
          backgroundColor: connected ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
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

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Menghubungkan ke printer...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    final success = await ThermalPrintService.printTest();

    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test print berhasil! Printer terhubung.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test print gagal. Cek koneksi printer.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _disconnectPrinter() async {
    if (_selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada printer yang terhubung'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      await ThermalPrintService.disconnectPrinter();

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer berhasil di-disconnect'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error disconnect: $e'),
          backgroundColor: Colors.red,
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Disconnect first
        await ThermalPrintService.disconnectPrinter();

        // Clear saved data
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('printer_address');
        await prefs.remove('printer_name');

        // Clear service state
        ThermalPrintService.setSelectedPrinter(null);

        if (mounted) {
          setState(() {
            _savedPrinter = null;
            _selectedPrinter = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Printer tersimpan berhasil dihapus'),
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
          // Connection status indicator
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
                    const SizedBox(width: 4),
                    if (_isReconnecting)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
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
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
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
                                    ? 'Terhubung'
                                    : 'Terputus',
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
                        Text(_savedPrinter!.name ?? 'Unknown'),
                        Text(
                          _savedPrinter!.address ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ThermalPrintService.isConnected()
                              ? 'Siap untuk print'
                              : 'Tekan "Test Print" untuk menghubungkan',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontStyle: FontStyle.italic,
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
                  _isScanning ? 'Mencari Printer...' : 'Scan Printer',
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
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          leading: Icon(
                            Icons.print,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
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
                              : null,
                          onTap: () => _selectPrinter(printer),
                        ),
                      );
                    },
                  ),
          ),

          // Action Buttons
          if (_selectedPrinter != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _testPrint,
                      icon: const Icon(Icons.print),
                      label: const Text('Test Print & Koneksi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _disconnectPrinter,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect Printer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _clearSavedPrinter,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Hapus Printer Tersimpan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade700,
                        side: BorderSide(color: Colors.orange.shade700),
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
