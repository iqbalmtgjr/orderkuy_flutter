import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../models/product.dart';
import '../models/kategori.dart';
import '../models/meja.dart';
import '../models/order.dart';
import '../utils/constants.dart';
import 'printer_setup_screen.dart';
import '../widgets/sync_status_widget.dart';
import '../core/database/db_helper.dart';

class _RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final number = int.tryParse(digitsOnly) ?? 0;
    final formatted = number.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    final fullText = 'Rp $formatted';
    return TextEditingValue(
      text: fullText,
      selection: TextSelection.collapsed(offset: fullText.length),
    );
  }
}

// Helper class untuk segment option
class _SegmentOption {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
}

class KasirScreen extends StatefulWidget {
  final Order? orderToEdit;
  const KasirScreen({super.key, this.orderToEdit});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen>
    with TickerProviderStateMixin {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Kategori> _kategoris = [];
  List<Meja> _mejas = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  bool _isLoading = true;
  bool _isOnline = true;
  bool _isBackgroundLoading = false;

  // Form fields
  int _jenisOrder = Constants.jenisOrderDineIn;
  int _metodeBayar = Constants.metodeBayarCash;
  int? _selectedMejaId;
  String _catatan = '';

  // Filter
  int? _selectedKategoriFilter;
  String _searchQuery = '';

  // Cart
  double _totalHarga = 0;
  int _totalItem = 0;

  // Payment
  final TextEditingController _nominalBayarController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _catatanController = TextEditingController();
  double _kembalian = 0;

  // ✨ Bottom panel expand/collapse
  bool _isBottomPanelExpanded = false;
  AnimationController? _panelController;
  Animation<double>? _panelAnimation;

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static double _parseNominalBayar(String text) {
    final digitsOnly = text.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(digitsOnly) ?? 0;
  }

  void _addDigitToNominal(String digit, StateSetter setDialogState) {
    final currentText = _nominalBayarController.text;
    final digitsOnly = currentText.replaceAll(RegExp(r'[^\d]'), '');
    final newDigits = digitsOnly + digit;
    final newValue = int.tryParse(newDigits) ?? 0;
    final formatted = newValue.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    _nominalBayarController.text = 'Rp $formatted';
    final nominal = _parseNominalBayar(_nominalBayarController.text);
    setDialogState(() => _kembalian = nominal - _totalHarga);
  }

  void _removeDigitFromNominal(StateSetter setDialogState) {
    final currentText = _nominalBayarController.text;
    final digitsOnly = currentText.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return;
    final newDigits = digitsOnly.substring(0, digitsOnly.length - 1);
    if (newDigits.isEmpty) {
      _nominalBayarController.text = '';
      setDialogState(() => _kembalian = -_totalHarga);
      return;
    }
    final newValue = int.tryParse(newDigits) ?? 0;
    final formatted = newValue.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    _nominalBayarController.text = 'Rp $formatted';
    final nominal = _parseNominalBayar(_nominalBayarController.text);
    setDialogState(() => _kembalian = nominal - _totalHarga);
  }

  void _clearNominal(StateSetter setDialogState) {
    _nominalBayarController.text = '';
    setDialogState(() => _kembalian = -_totalHarga);
  }

  @override
  void initState() {
    super.initState();

    // ✅ Inisialisasi controller PERTAMA sebelum apapun
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController!,
      curve: Curves.easeInOutCubic,
    );

    _loadData();
    _checkConnectivity();
    _listenToConnectivity();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _applyFilters();
      });
    });

    if (widget.orderToEdit != null) {
      final order = widget.orderToEdit!;
      _jenisOrder = order.jenisOrder;
      _metodeBayar = order.metodeBayar;
      _selectedMejaId = order.mejaId;
      _catatan = order.catatan ?? '';
      _catatanController.text = _catatan;
      _selectedItems.clear();
      for (var item in order.items) {
        _selectedItems.add({
          'menu_id': item.menuId,
          'nama_produk': item.menuNama,
          'harga': item.harga,
          'qty': item.qty,
        });
      }
      _calculateTotals();
    }
  }

  @override
  void dispose() {
    _panelController?.dispose();
    _nominalBayarController.dispose();
    _searchController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  void _togglePanel() {
    setState(() => _isBottomPanelExpanded = !_isBottomPanelExpanded);
    if (_isBottomPanelExpanded) {
      _panelController?.forward();
    } else {
      _panelController?.reverse();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CONNECTIVITY
  // ═══════════════════════════════════════════════════════════

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOnline = result != ConnectivityResult.none);
  }

  void _listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _isOnline = result != ConnectivityResult.none);
      if (_isOnline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📡 Koneksi kembali, data akan tersinkron'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // Update method dengan indicator
  Future<void> _loadDataWithIndicator() async {
    setState(() => _isLoading = true);

    try {
      final products = await ApiService.getMenusOfflineFirst(
        onDataUpdated: (freshProducts) {
          if (mounted) {
            setState(() {
              _products = freshProducts;
              _applyFilters();
              _isBackgroundLoading = false; // ← Hide indicator
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Menu diperbarui dari server'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      );

      final kategoris = await ApiService.getKategoris();
      final mejas = widget.orderToEdit != null
          ? await ApiService.getAllTables()
          : await ApiService.getFreeTables();

      setState(() {
        _products = products;
        _kategoris = kategoris;
        _filteredProducts = products;
        _mejas = mejas;
        _isLoading = false;
        _isBackgroundLoading = true; // ← Show indicator saat fetch background
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    debugPrint('🔄 Loading data (Offline-First Strategy)...');

    try {
      // Load products with offline-first strategy
      final products = await ApiService.getMenusOfflineFirst(
        onDataUpdated: (freshProducts) {
          // Callback: dipanggil saat data baru dari server ready
          if (mounted) {
            setState(() {
              _products = freshProducts;
              _applyFilters();
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Data menu diperbarui dari server'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      );

      // ← CRITICAL FIX: Gunakan getKategorisOfflineFirst()
      final kategoris = await ApiService.getKategorisOfflineFirst(
        onDataUpdated: (freshKategoris) {
          // Callback: update kategoris saat data baru ready
          if (mounted) {
            setState(() {
              _kategoris = freshKategoris;
            });
            debugPrint('✅ Kategoris updated from background fetch');
          }
        },
      );

      // Load mejas (online only, no cache needed)
      final mejas = widget.orderToEdit != null
          ? await ApiService.getAllTables()
          : await ApiService.getFreeTables();

      setState(() {
        _products = products;
        _kategoris = kategoris;
        _filteredProducts = products;
        _mejas = mejas;
        _isLoading = false;
      });

      debugPrint(
          '✅ Initial data loaded: ${products.length} products, ${kategoris.length} kategoris');
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error memuat data: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Coba Lagi',
              textColor: Colors.white,
              onPressed: _loadData,
            ),
          ),
        );
      }
    }
  }

  Future<void> _forceRefreshData() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa refresh saat offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Clear cache first
    await DBHelper.clearAllCache();

    // Reload data
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Data berhasil di-refresh'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredProducts = _products.where((product) {
        final matchKategori = _selectedKategoriFilter == null ||
            product.kategoriId == _selectedKategoriFilter;
        final matchSearch = _searchQuery.isEmpty ||
            product.namaProduk
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());
        return matchKategori && matchSearch;
      }).toList();
    });
  }

  void _addToCart(Product product, int qty) {
    if (product.qty < qty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Stok ${product.namaProduk} tidak mencukupi!')),
        );
      }
      return;
    }
    setState(() {
      final existingIndex = _selectedItems.indexWhere(
        (item) => item['menu_id'] == product.id,
      );
      if (existingIndex != -1) {
        _selectedItems[existingIndex]['qty'] += qty;
      } else {
        _selectedItems.add({
          'menu_id': product.id,
          'nama_produk': product.namaProduk,
          'harga': product.harga,
          'qty': qty,
        });
      }
      _calculateTotals();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${product.namaProduk} ditambahkan'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _removeFromCart(int index) {
    setState(() {
      _selectedItems.removeAt(index);
      _calculateTotals();
    });
  }

  void _updateQuantity(int index, int change) {
    setState(() {
      _selectedItems[index]['qty'] += change;
      if (_selectedItems[index]['qty'] <= 0) {
        _selectedItems.removeAt(index);
      }
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    _totalItem = 0;
    _totalHarga = 0;
    for (var item in _selectedItems) {
      _totalItem += item['qty'] as int;
      _totalHarga += (item['qty'] as int) * (item['harga'] as double);
    }
  }

  Future<void> _showPaymentDialog() async {
    if (_selectedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keranjang masih kosong')),
        );
      }
      return;
    }
    if (_jenisOrder == Constants.jenisOrderDineIn && _selectedMejaId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih meja terlebih dahulu')),
        );
      }
      return;
    }
    await showDialog(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth > 500 ? 480.0 : screenWidth * 0.92;
        return AlertDialog(
          title: const Text('Konfirmasi Pesanan',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isOnline)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off,
                                  size: 20, color: Colors.orange.shade900),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Mode Offline: Pesanan akan tersimpan lokal',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.orange.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Text('Item Pesanan:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._selectedItems.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: false,
                          title: Text(item['nama_produk'],
                              style: const TextStyle(fontSize: 15)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${item['qty']} x ${_currencyFormat.format(item['harga'])}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          trailing: Text(
                            _currencyFormat.format((item['qty'] as int) *
                                (item['harga'] as double)),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Total: ${_currencyFormat.format(_totalHarga)}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _nominalBayarController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: 'Nominal Bayar',
                          hintText: 'Rp 0',
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide:
                                BorderSide(color: Color(0xFFD32F2F), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _nominalBayarController.clear();
                              setDialogState(() => _kembalian = -_totalHarga);
                            },
                          ),
                        ),
                        inputFormatters: [_RupiahInputFormatter()],
                        onChanged: (value) {
                          setDialogState(() {
                            final nominal = _parseNominalBayar(value);
                            _kembalian = nominal - _totalHarga;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildNumericKeypad(setDialogState),
                      const SizedBox(height: 20),
                      Text(
                        'Kembalian: ${_currencyFormat.format(_kembalian)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _kembalian < 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () {
                if (_kembalian < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nominal bayar kurang')),
                  );
                  return;
                }
                Navigator.pop(context);
                _savePesanan();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child:
                  const Text('Bayar & Simpan', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SAVE PESANAN
  // ═══════════════════════════════════════════════════════════

  Future<void> _savePesanan() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Menyimpan pesanan...',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );

    final orderData = {
      'jenis_order': _jenisOrder,
      'metode_bayar': _metodeBayar,
      'meja_id':
          _jenisOrder == Constants.jenisOrderDineIn ? _selectedMejaId : null,
      'catatan': _catatan,
      'items': _selectedItems
          .map((item) => {
                'menu_id': item['menu_id'],
                'qty': item['qty'],
                'harga': item['harga'],
              })
          .toList(),
      'total_harga': _totalHarga,
    };

    final isEditing = widget.orderToEdit != null;
    final result = isEditing
        ? await ApiService.updateOrder(widget.orderToEdit!.id, orderData)
        : await ApiService.createOrder(orderData);

    if (!mounted) return;
    Navigator.pop(context);

    if (result['success']) {
      final isOffline = result['offline'] == true;
      if (!isOffline && result['data'] != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Mencetak struk & nota dapur...',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        );
        final printResults = await _printAll(result['data']);
        final kasirOk = printResults[0];
        final dapurOk = printResults[1];
        if (!mounted) return;
        Navigator.pop(context);

        String msg;
        Color bgColor;
        if (kasirOk && dapurOk) {
          msg = isEditing
              ? 'Pesanan diperbarui. Struk kasir & nota dapur tercetak.'
              : 'Pesanan disimpan. Struk kasir & nota dapur tercetak.';
          bgColor = Colors.green;
        } else if (kasirOk && !dapurOk) {
          msg = 'Pesanan disimpan. Struk kasir OK, printer dapur gagal.';
          bgColor = Colors.orange;
        } else if (!kasirOk && dapurOk) {
          msg = 'Pesanan disimpan. Nota dapur OK, printer kasir gagal.';
          bgColor = Colors.orange;
        } else {
          msg = isEditing
              ? 'Pesanan diperbarui, tapi kedua printer gagal mencetak.'
              : 'Pesanan disimpan, tapi kedua printer gagal mencetak.';
          bgColor = Colors.orange;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg),
                backgroundColor: bgColor,
                duration: const Duration(seconds: 3)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '📵 Pesanan disimpan offline, akan tersinkron saat online'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      if (!isEditing) {
        setState(() {
          _selectedItems.clear();
          _totalHarga = 0;
          _totalItem = 0;
          _selectedMejaId = null;
          _catatan = '';
          _nominalBayarController.clear();
          _catatanController.clear();
        });
      }
      if (mounted) Navigator.pop(context);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ??
                (isEditing
                    ? 'Gagal memperbarui pesanan'
                    : 'Gagal menyimpan pesanan')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<bool>> _printAll(Map<String, dynamic> orderData) async {
    try {
      final kasirNama = orderData['user']?['name']?.toString();
      final tokoNama =
          orderData['toko']?['nama_toko']?.toString() ?? 'OrderKuy';
      final tokoAlamat = orderData['toko']?['alamat']?.toString() ?? '';
      String? mejaNo;
      if (_jenisOrder == Constants.jenisOrderDineIn &&
          _selectedMejaId != null) {
        final found = _mejas.where((m) => m.id == _selectedMejaId);
        if (found.isNotEmpty) mejaNo = found.first.noMeja;
      }
      return await ThermalPrintService.printAll(
        orderId: orderData['id']?.toString() ?? '',
        tokoNama: tokoNama,
        tokoAlamat: tokoAlamat,
        items: _selectedItems,
        totalHarga: _totalHarga,
        jenisOrder: _jenisOrder,
        mejaNo: mejaNo,
        catatan: _catatan,
        metodeBayar: _metodeBayar,
        kasirNama: kasirNama,
      );
    } catch (e) {
      debugPrint('❌ _printAll error: $e');
      return [false, false];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  static const double _breakpointTablet = 600;

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.orderToEdit != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _breakpointTablet;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (_selectedItems.isNotEmpty) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Konfirmasi'),
              content: const Text(
                  'Ada item di keranjang. Yakin ingin keluar?\nData akan hilang.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white),
                  child: const Text('Ya, Keluar'),
                ),
              ],
            ),
          );
          if (shouldPop == true && context.mounted) Navigator.pop(context);
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              if (_selectedItems.isNotEmpty) {
                final shouldPop = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Konfirmasi'),
                    content: const Text(
                        'Ada item di keranjang. Yakin ingin keluar?\nData akan hilang.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white),
                        child: const Text('Ya, Keluar'),
                      ),
                    ],
                  ),
                );
                if (shouldPop == true && mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Row(
            children: [
              Text(
                isEditing ? 'Edit Pesanan' : 'Kasir',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isBackgroundLoading) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ],
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          elevation: 10,
          shadowColor: Colors.red.withValues(alpha: 0.5),
          actions: [
            if (_isOnline)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _forceRefreshData,
                tooltip: 'Refresh Data',
              ),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.white),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const PrinterSetupScreen())),
              tooltip: 'Setup Printer',
            ),
          ],
        ),
        body: Column(
          children: [
            const SyncStatusWidget(),
            Expanded(
              child: isMobile
                  ? _buildMobileLayout(isEditing)
                  : _buildTabletLayout(isEditing),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MOBILE LAYOUT — Stack dengan floating bottom panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobileLayout(bool isEditing) {
    return Stack(
      children: [
        // ── Produk List (background) ──
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Cari Produk',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFD32F2F), width: 2),
                  ),
                  prefixIcon: Icon(Icons.search, color: Colors.red[700]),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),
            _buildKategoriFilter(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProducts.isEmpty
                      ? Center(
                          child: Text(
                            !_isOnline && _products.isEmpty
                                ? 'Menu tidak tersedia offline.'
                                : 'Tidak ada menu',
                          ),
                        )
                      : GridView.builder(
                          // Padding bawah agar tidak tertutup panel collapsed (~72px)
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) => _buildProductCard(
                              _filteredProducts[index],
                              isMobile: true),
                        ),
            ),
          ],
        ),

        // ── Floating Bottom Panel ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomPanel(isEditing),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Bottom Panel
  // Collapsed : hanya bar kecil (icon keranjang + jumlah + tombol bayar)
  // Expanded  : seluruh form order + cart + tombol bayar besar
  // ─────────────────────────────────────────────
  Widget _buildBottomPanel(bool isEditing) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Collapsed Bar (selalu tampil, tap untuk toggle) ──
          InkWell(
            onTap: _togglePanel,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // Cart icon + badge jumlah item
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_rounded,
                          color: Color(0xFFD32F2F),
                          size: 24,
                        ),
                      ),
                      if (_totalItem > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              '$_totalItem',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Ringkasan teks
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _totalItem > 0
                              ? '$_totalItem item · ${_currencyFormat.format(_totalHarga)}'
                              : 'Keranjang kosong',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _totalItem > 0
                                ? Colors.grey.shade800
                                : Colors.grey.shade400,
                          ),
                        ),
                        Text(
                          _getOrderSummaryLine(),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Tombol bayar ringkas (hanya saat ada item)
                  if (_totalItem > 0) ...[
                    ElevatedButton(
                      onPressed: _showPaymentDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Bayar',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Chevron panah atas/bawah
                  AnimatedRotation(
                    turns: _isBottomPanelExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    child: Icon(Icons.keyboard_arrow_up,
                        color: Colors.grey.shade500, size: 26),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Content ──
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _isBottomPanelExpanded
                ? _buildExpandedContent(isEditing)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Konten yang muncul saat panel di-expand
  // ─────────────────────────────────────────────
  Widget _buildExpandedContent(bool isEditing) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── Jenis Order + Metode Bayar (2 kolom) ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _buildCompactSegment(
                  label: 'Jenis Order',
                  options: [
                    _SegmentOption(
                      label: 'Dine In',
                      icon: Icons.restaurant,
                      isSelected: _jenisOrder == Constants.jenisOrderDineIn,
                      onTap: () => setState(
                          () => _jenisOrder = Constants.jenisOrderDineIn),
                    ),
                    _SegmentOption(
                      label: 'Take Away',
                      icon: Icons.takeout_dining,
                      isSelected: _jenisOrder == Constants.jenisOrderTakeAway,
                      onTap: () => setState(() {
                        _jenisOrder = Constants.jenisOrderTakeAway;
                        _selectedMejaId = null;
                      }),
                    ),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildCompactSegment(
                  label: 'Metode Bayar',
                  options: [
                    _SegmentOption(
                      label: 'Cash',
                      icon: Icons.payments_outlined,
                      isSelected: _metodeBayar == Constants.metodeBayarCash,
                      onTap: () => setState(
                          () => _metodeBayar = Constants.metodeBayarCash),
                    ),
                    _SegmentOption(
                      label: 'Transfer',
                      icon: Icons.account_balance_outlined,
                      isSelected: _metodeBayar == Constants.metodeBayarTransfer,
                      onTap: () => setState(
                          () => _metodeBayar = Constants.metodeBayarTransfer),
                    ),
                  ],
                )),
              ],
            ),

            // ── Pilih Meja ──
            if (_jenisOrder == Constants.jenisOrderDineIn) ...[
              const SizedBox(height: 12),
              _buildTableSelector(),
            ],

            // ── Catatan ──
            const SizedBox(height: 12),
            _buildNotesField(),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Header Keranjang ──
            Row(
              children: [
                const Text('Keranjang',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_totalItem > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$_totalItem',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCartItems(),
            const SizedBox(height: 10),

            // ── Total Card ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade50, Colors.red.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Item',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      Text('$_totalItem item',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total Harga',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      Text(
                        _currencyFormat.format(_totalHarga),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Tombol Bayar Besar ──
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _showPaymentDialog,
                icon: Icon(isEditing ? Icons.update : Icons.payment,
                    color: Colors.white),
                label: Text(
                  isEditing
                      ? 'Update & Simpan'
                      : 'Bayar  •  ${_currencyFormat.format(_totalHarga)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: Colors.red.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Compact Segment Control (untuk panel mobile)
  // ─────────────────────────────────────────────
  Widget _buildCompactSegment({
    required String label,
    required List<_SegmentOption> options,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.grey.shade600)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: options.map((opt) {
              return Expanded(
                child: GestureDetector(
                  onTap: opt.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: opt.isSelected
                          ? const Color(0xFFD32F2F)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: opt.isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFD32F2F)
                                    .withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(opt.icon,
                            size: 16,
                            color: opt.isSelected
                                ? Colors.white
                                : Colors.grey.shade500),
                        const SizedBox(height: 2),
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: opt.isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: opt.isSelected
                                ? Colors.white
                                : Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // Summary satu baris untuk collapsed bar
  String _getOrderSummaryLine() {
    final jenis =
        _jenisOrder == Constants.jenisOrderDineIn ? 'Dine In' : 'Take Away';
    final bayar =
        _metodeBayar == Constants.metodeBayarCash ? 'Cash' : 'Transfer';
    String mejaText = '';
    if (_jenisOrder == Constants.jenisOrderDineIn && _selectedMejaId != null) {
      final found = _mejas.where((m) => m.id == _selectedMejaId);
      if (found.isNotEmpty) mejaText = ' · Meja ${found.first.noMeja}';
    }
    return '$jenis · $bayar$mejaText';
  }

  // ═══════════════════════════════════════════════════════════
  // TABLET LAYOUT (tidak berubah)
  // ═══════════════════════════════════════════════════════════

  Widget _buildTabletLayout(bool isEditing) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Cari Produk',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search, color: Colors.red[700]),
                  ),
                ),
              ),
              _buildKategoriFilter(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredProducts.isEmpty
                        ? Center(
                            child: Text(!_isOnline && _products.isEmpty
                                ? 'Menu tidak tersedia offline.'
                                : 'Tidak ada menu'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) => _buildProductCard(
                                _filteredProducts[index],
                                isMobile: false),
                          ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red[50]!, Colors.red[100]!],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.1),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(-2, 0),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderTypeSelector(),
                  const SizedBox(height: 16),
                  _buildPaymentMethodSelector(),
                  const SizedBox(height: 16),
                  if (_jenisOrder == Constants.jenisOrderDineIn)
                    _buildTableSelector(),
                  const SizedBox(height: 16),
                  _buildNotesField(),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('Item Dipilih',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildCartItems(),
                  const SizedBox(height: 16),
                  _buildTotals(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _showPaymentDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        elevation: 5,
                        shadowColor: Colors.red.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ).copyWith(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.hovered)
                              ? const Color(0xFFB71C1C)
                              : const Color(0xFFD32F2F),
                        ),
                      ),
                      child: Text(
                        isEditing ? 'Update & Simpan' : 'Bayar & Simpan',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SHARED WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════

  Widget _buildKategoriFilter() {
    final isMobile = MediaQuery.of(context).size.width < _breakpointTablet;
    return Container(
      height: isMobile ? 48 : 60,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Semua'),
              selected: _selectedKategoriFilter == null,
              onSelected: (_) {
                setState(() {
                  _selectedKategoriFilter = null;
                  _applyFilters();
                });
              },
              selectedColor: const Color(0xFFD32F2F),
              backgroundColor: Colors.grey[200],
              labelStyle: TextStyle(
                color: _selectedKategoriFilter == null
                    ? Colors.white
                    : Colors.black87,
                fontWeight: _selectedKategoriFilter == null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          ..._kategoris.map((kategori) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(kategori.namaKategori),
                selected: _selectedKategoriFilter == kategori.id,
                onSelected: (selected) {
                  setState(() {
                    _selectedKategoriFilter = selected ? kategori.id : null;
                    _applyFilters();
                  });
                },
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: Colors.grey[200],
                labelStyle: TextStyle(
                  color: _selectedKategoriFilter == kategori.id
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: _selectedKategoriFilter == kategori.id
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, {bool isMobile = false}) {
    const String baseUrl =
        'https://orderkuy.indotechconsulting.com/assets/img/menu/';
    final padding = isMobile ? 4.0 : 8.0;
    final iconSize = isMobile ? 32.0 : 48.0;
    final titleStyle =
        TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 14);
    final priceStyle = TextStyle(
        color: Colors.green,
        fontWeight: FontWeight.bold,
        fontSize: isMobile ? 11 : 14);

    return Card(
      elevation: isMobile ? 4 : 8,
      margin: isMobile ? const EdgeInsets.symmetric(horizontal: 2) : null,
      shadowColor: Colors.red.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
        side: const BorderSide(color: Color(0xFFD32F2F), width: 1),
      ),
      child: InkWell(
        onTap: () => _addToCart(product, 1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: EdgeInsets.all(padding),
                child: product.foto != null && product.foto!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
                        child: Image.network(
                          '$baseUrl${product.foto}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.restaurant_menu,
                            size: iconSize,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      )
                    : Icon(Icons.restaurant_menu,
                        size: iconSize, color: Theme.of(context).primaryColor),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(product.namaProduk,
                        style: titleStyle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text(_currencyFormat.format(product.harga),
                        style: priceStyle),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text('Stok: ${product.qty}',
                        style: TextStyle(
                            fontSize: isMobile ? 10 : 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Jenis Order',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Dine In',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                selected: _jenisOrder == Constants.jenisOrderDineIn,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (_) =>
                    setState(() => _jenisOrder = Constants.jenisOrderDineIn),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Take Away',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                selected: _jenisOrder == Constants.jenisOrderTakeAway,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (_) => setState(() {
                  _jenisOrder = Constants.jenisOrderTakeAway;
                  _selectedMejaId = null;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Metode Bayar',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Cash',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                selected: _metodeBayar == Constants.metodeBayarCash,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (_) =>
                    setState(() => _metodeBayar = Constants.metodeBayarCash),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Transfer',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                selected: _metodeBayar == Constants.metodeBayarTransfer,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (_) => setState(
                    () => _metodeBayar = Constants.metodeBayarTransfer),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTableSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pilih Meja', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _selectedMejaId,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: _mejas.map((meja) {
            return DropdownMenuItem<int>(
              value: meja.id,
              child: Text('Meja ${meja.noMeja}'),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedMejaId = value),
          hint: const Text('Pilih meja'),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Catatan', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _catatanController,
          maxLines: 2,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: 'Tambahkan catatan jika ada',
          ),
          onChanged: (value) => setState(() => _catatan = value),
        ),
      ],
    );
  }

  Widget _buildCartItems() {
    if (_selectedItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.shopping_cart_outlined,
                  color: Colors.grey.shade300, size: 36),
              const SizedBox(height: 6),
              Text('Belum ada item',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return Column(
      children: _selectedItems.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['nama_produk'],
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(_currencyFormat.format(item['harga']),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildQtyButton(
                        icon: Icons.remove,
                        onTap: () => _updateQuantity(index, -1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('${item['qty']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    _buildQtyButton(
                        icon: Icons.add,
                        onTap: () => _updateQuantity(index, 1)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _removeFromCart(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQtyButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 16, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildTotals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Item: $_totalItem'),
        Text(
          'Total Harga: ${_currencyFormat.format(_totalHarga)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // NUMERIC KEYPAD
  // ═══════════════════════════════════════════════════════════

  Widget _buildNumericKeypad(StateSetter setDialogState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade50, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: _buildKeypadButton('1', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('2', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('3', setDialogState)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _buildKeypadButton('4', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('5', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('6', setDialogState)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _buildKeypadButton('7', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('8', setDialogState)),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypadButton('9', setDialogState)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _buildKeypadActionButton(
                'Clear',
                Icons.clear_all,
                Colors.orange.shade700,
                () => _clearNominal(setDialogState),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _buildKeypadButton('0', setDialogState)),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKeypadActionButton(
                'Del',
                Icons.backspace,
                const Color(0xFFD32F2F),
                () => _removeDigitFromNominal(setDialogState),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String digit, StateSetter setDialogState) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      shadowColor: Colors.grey.shade400,
      child: InkWell(
        onTap: () => _addDigitToNominal(digit, setDialogState),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 1),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(digit,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD32F2F),
                    letterSpacing: 1)),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadActionButton(
      String label, IconData icon, Color color, VoidCallback onPressed) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      shadowColor: color.withOpacity(0.5),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
