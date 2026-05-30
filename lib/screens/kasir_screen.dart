import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/payment_method_service.dart'; // ← TAMBAH INI
import '../models/product.dart';
import '../models/kategori.dart';
import '../models/meja.dart';
import '../models/order.dart';
import '../utils/constants.dart';
import 'printer_setup_screen.dart';
import '../widgets/sync_status_widget.dart';
import '../core/database/db_helper.dart';
import '../widgets/option_picker_dialog.dart';
import 'payment_confirmation_screen.dart';

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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  int _jenisOrder = Constants.jenisOrderDineIn;

  // ── PERUBAHAN: ganti int _metodeBayar → Map _selectedPaymentMethod ──
  List<Map<String, dynamic>> _paymentMethods = [];
  Map<String, dynamic>? _selectedPaymentMethod;
  bool _paymentMethodsLoading = false;
  // ────────────────────────────────────────────────────────────────────

  int? _selectedMejaId;
  String _mejaNoInput = ''; // dipakai saat offline & cache meja kosong
  String _catatan = '';

  int? _selectedKategoriFilter;
  String _searchQuery = '';

  double _totalHarga = 0;
  int _totalItem = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _catatanController = TextEditingController();

  bool _isBottomPanelExpanded = false;
  AnimationController? _panelController;

  static const Color _primaryColor = Color(0xFF1a315b);
  static const Color _primaryLight = Color(0xFF2a4a7f);
  static const Color _primaryDark = Color(0xFF0f2040);
  static const Color _primarySurface = Color(0xFFe8eef5);
  static const Color _primarySurfaceDeep = Color(0xFFc8d5e8);

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  // ── Helper: apakah metode bayar yang dipilih adalah tunai? ──
  bool get _isCash {
    if (_selectedPaymentMethod == null) return true;
    final kode =
        (_selectedPaymentMethod!['kode'] as String?)?.toUpperCase() ?? '';
    final nama =
        (_selectedPaymentMethod!['nama'] as String?)?.toUpperCase() ?? '';
    return kode == 'CASH' ||
        kode == 'TUNAI' ||
        nama == 'TUNAI' ||
        nama == 'CASH';
  }

  // ── Helper: icon per kode metode bayar ──────────────────────
  IconData _getPaymentIcon(String kode) {
    switch (kode.toUpperCase()) {
      case 'CASH':
      case 'TUNAI':
        return Icons.payments_outlined;
      case 'QRIS':
        return Icons.qr_code_rounded;
      case 'TF':
      case 'TRANSFER':
        return Icons.account_balance_outlined;
      case 'EDC':
      case 'DEBIT':
      case 'KREDIT':
        return Icons.credit_card_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _loadData();
    _loadPaymentMethods(); // ← TAMBAH INI
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
      _selectedMejaId = order.mejaId;
      _catatan = order.catatan ?? '';
      _catatanController.text = _catatan;
      _selectedItems.clear();
      for (var item in order.items) {
        _selectedItems.add({
          'menu_id': item.menuId,
          'nama_produk': item.menuNama,
          'harga': item.harga + item.totalHargaOpsi.toDouble(),
          'harga_dasar': item.harga,
          'qty': item.qty,
          'option_item_ids': item.opsiDipilih.map((o) => o.id).toList(),
          'has_options': item.opsiDipilih.isNotEmpty,
        });
      }
      _calculateTotals();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _panelController?.dispose();
    _searchController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  // ── BARU: Load payment methods dari API ─────────────────────
  Future<void> _loadPaymentMethods() async {
    setState(() => _paymentMethodsLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(Constants.userKey);
      if (userJson == null) return;

      final user = jsonDecode(userJson);
      final tokoId = user['toko_id'] as int? ?? 0;
      if (tokoId == 0) return;

      final methods = await PaymentMethodService.getPaymentMethods(tokoId);

      setState(() {
        _paymentMethods = methods;
        // Default: pilih metode pertama (biasanya Tunai)
        if (methods.isNotEmpty && _selectedPaymentMethod == null) {
          _selectedPaymentMethod = methods.first;
        }
        _paymentMethodsLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadPaymentMethods error: $e');
      setState(() {
        _paymentMethods = [
          {'id': null, 'nama': 'Tunai', 'kode': 'CASH'},
          {'id': null, 'nama': 'Transfer', 'kode': 'TF'},
          {'id': null, 'nama': 'QRIS', 'kode': 'QRIS'},
        ];
        _selectedPaymentMethod = _paymentMethods.first;
        _paymentMethodsLoading = false;
      });
    }
  }
  // ────────────────────────────────────────────────────────────

  void _togglePanel() {
    setState(() => _isBottomPanelExpanded = !_isBottomPanelExpanded);
    if (_isBottomPanelExpanded) {
      _panelController?.forward();
    } else {
      _panelController?.reverse();
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _isOnline =
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none));
  }

  void _listenToConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (!mounted) return;
      final isConnected = results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);
      setState(() => _isOnline = isConnected);
      if (isConnected) {
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final products = await ApiService.getMenusOfflineFirst(
        onDataUpdated: (freshProducts) {
          if (mounted) {
            setState(() {
              _products = freshProducts;
              _applyFilters();
            });
          }
        },
      );
      final kategoris = await ApiService.getKategorisOfflineFirst(
        onDataUpdated: (freshKategoris) {
          if (mounted) setState(() => _kategoris = freshKategoris);
        },
      );
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
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _forceRefreshData() async {
    if (!_isOnline) return;
    setState(() => _isLoading = true);
    await DBHelper.clearProductCache();
    await _loadData();
    await _loadPaymentMethods();
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

  void _addToCart(Product product, int qty) async {
    if (product.useStock && product.qty < qty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Stok ${product.namaProduk} tidak mencukupi!')),
        );
      }
      return;
    }

    if (product.hasOptions && product.optionGroups.isNotEmpty) {
      final result = await OptionPickerDialog.show(
        context,
        product: product,
        initialQty: qty,
      );
      if (result == null || !mounted) return;

      setState(() {
        _selectedItems.add({
          'menu_id': product.id,
          'nama_produk': product.namaProduk,
          'harga': result['harga_per_item'] as double,
          'harga_dasar': product.harga,
          'qty': result['qty'] as int,
          'option_item_ids': result['option_item_ids'] as List<int>,
          'has_options': true,
        });
        _calculateTotals();
      });
      return;
    }

    setState(() {
      final existingIndex = _selectedItems.indexWhere(
        (item) => item['menu_id'] == product.id && item['has_options'] != true,
      );
      if (existingIndex != -1) {
        _selectedItems[existingIndex]['qty'] += qty;
      } else {
        _selectedItems.add({
          'menu_id': product.id,
          'nama_produk': product.namaProduk,
          'harga': product.harga,
          'qty': qty,
          'option_item_ids': <int>[],
          'has_options': false,
        });
      }
      _calculateTotals();
    });
  }

  Future<void> _editCartItemOptions(
      int index, Map<String, dynamic> item) async {
    final menuId = item['menu_id'] as int;
    Product? product;
    try {
      product = _products.firstWhere((p) => p.id == menuId);
    } catch (_) {
      return;
    }
    if (product.optionGroups.isEmpty) return;

    final result = await OptionPickerDialog.show(
      context,
      product: product,
      initialQty: item['qty'] as int,
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedItems[index]['qty'] = result['qty'] as int;
      _selectedItems[index]['option_item_ids'] =
          result['option_item_ids'] as List<int>;
      _selectedItems[index]['harga'] = result['harga_per_item'] as double;
      _calculateTotals();
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keranjang masih kosong')),
      );
      return;
    }
    if (_jenisOrder == Constants.jenisOrderDineIn) {
      final belumPilihMeja = _selectedMejaId == null ||
          (_selectedMejaId == 0 && _mejaNoInput.isEmpty);
      if (belumPilihMeja) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih atau ketik nomor meja terlebih dahulu')),
        );
        return;
      }
    }

    // Attach resolved option labels so the confirmation screen can display them
    final itemsWithOpsi = _selectedItems.map((item) {
      if (item['has_options'] != true) return item;
      final optionItemIds =
          (item['option_item_ids'] as List?)?.cast<int>() ?? [];
      if (optionItemIds.isEmpty) return item;
      try {
        final product = _products.firstWhere((p) => p.id == item['menu_id']);
        final names = <String>[];
        for (final group in product.optionGroups) {
          for (final opt in group.items) {
            if (optionItemIds.contains(opt.id)) names.add(opt.nama);
          }
        }
        if (names.isNotEmpty) return {...item, 'opsi': names.join(', ')};
      } catch (_) {}
      return item;
    }).toList();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentConfirmationScreen(
          selectedItems: itemsWithOpsi,
          totalHarga: _totalHarga,
          paymentMethods: _paymentMethods,
          initialPaymentMethod: _selectedPaymentMethod,
          isOnline: _isOnline,
        ),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() => _selectedPaymentMethod = result['payment_method']);
      _savePesanan();
    }
  }

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

    // ── PERUBAHAN: kirim metode_bayar_id juga ────────────────
    final orderData = {
      'jenis_order': _jenisOrder,
      'metode_bayar': _isCash ? 1 : 2, // backward compat field lama
      'metode_bayar_id': _selectedPaymentMethod?['id'], // field baru (nullable)
      'meja_id': _jenisOrder == Constants.jenisOrderDineIn
          ? (_selectedMejaId == 0 ? null : _selectedMejaId)
          : null,
      if (_jenisOrder == Constants.jenisOrderDineIn && _selectedMejaId == 0 && _mejaNoInput.isNotEmpty)
        'meja_no': _mejaNoInput,
      'catatan': _catatan,
      'items': _selectedItems
          .map((item) => {
                'menu_id': item['menu_id'],
                'qty': item['qty'],
                'harga': item['harga_dasar'] ?? item['harga'],
                'option_item_ids':
                    (item['option_item_ids'] as List?)?.cast<int>() ?? [],
              })
          .toList(),
      'total_harga': _totalHarga,
    };
    // ────────────────────────────────────────────────────────

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
                Text('Mencetak struk...',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        );
        final printResults = await _printAll(result['data']);
        if (!mounted) return;
        Navigator.pop(context);

        final kasirOk = printResults[0];
        final dapurOk = printResults[1];
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
        } else {
          msg = isEditing
              ? 'Pesanan diperbarui, tapi printer gagal.'
              : 'Pesanan disimpan, tapi printer gagal.';
          bgColor = Colors.orange;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: bgColor,
              duration: const Duration(seconds: 3)));
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
            backgroundColor: _primaryColor,
          ),
        );
      }
    }
  }

  Future<List<bool>> _printAll(Map<String, dynamic> orderData) async {
    try {
      final kasirNama = orderData['user']?['name']?.toString();
      final tokoNama = orderData['toko']?['nama_toko']?.toString() ?? 'Kasvo';
      final tokoAlamat = orderData['toko']?['alamat']?.toString() ?? '';
      String? mejaNo;
      if (_jenisOrder == Constants.jenisOrderDineIn &&
          _selectedMejaId != null) {
        final found = _mejas.where((m) => m.id == _selectedMejaId);
        if (found.isNotEmpty) mejaNo = found.first.noMeja;
      }

      final itemsForPrint = _selectedItems.map((item) {
        final hasOptions = item['has_options'] == true;
        String opsiLabel = '';
        if (hasOptions) {
          final menuId = item['menu_id'] as int;
          final optionItemIds =
              (item['option_item_ids'] as List?)?.cast<int>() ?? [];
          if (optionItemIds.isNotEmpty) {
            try {
              final product = _products.firstWhere((p) => p.id == menuId);
              final selectedNames = <String>[];
              for (var group in product.optionGroups) {
                for (var optItem in group.items) {
                  if (optionItemIds.contains(optItem.id)) {
                    selectedNames.add(optItem.nama);
                  }
                }
              }
              opsiLabel = selectedNames.join(', ');
            } catch (_) {}
          }
        }
        return {
          ...item,
          if (opsiLabel.isNotEmpty) 'opsi': opsiLabel,
        };
      }).toList();

      // ── PERUBAHAN: kirim nama metode bayar ke printer ──────
      final metodeBayarInt = _isCash ? 1 : 2;

      return await ThermalPrintService.printAll(
        orderId: orderData['id']?.toString() ?? '',
        tokoNama: tokoNama,
        tokoAlamat: tokoAlamat,
        items: itemsForPrint,
        totalHarga: _totalHarga,
        jenisOrder: _jenisOrder,
        mejaNo: mejaNo,
        catatan: _catatan,
        metodeBayar: metodeBayarInt,
        kasirNama: kasirNama,
      );
    } catch (e) {
      debugPrint('❌ _printAll error: $e');
      return [false, false];
    }
  }

  // ── _getOrderSummaryLine — PERUBAHAN: pakai nama dari object ─
  String _getOrderSummaryLine() {
    final jenis =
        _jenisOrder == Constants.jenisOrderDineIn ? 'Dine In' : 'Take Away';
    final bayar = _selectedPaymentMethod?['nama'] ?? 'Tunai'; // ← PERUBAHAN
    String mejaText = '';
    if (_jenisOrder == Constants.jenisOrderDineIn && _selectedMejaId != null) {
      final found = _mejas.where((m) => m.id == _selectedMejaId);
      if (found.isNotEmpty) mejaText = ' · Meja ${found.first.noMeja}';
    }
    return '$jenis · $bayar$mejaText';
  }

  // ── _buildPaymentMethodSelector (TABLET) — PERUBAHAN ────────
  Widget _buildPaymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Metode Bayar',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_paymentMethodsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _paymentMethods.map((method) {
              final isSelected =
                  _selectedPaymentMethod?['id'] == method['id'] &&
                      _selectedPaymentMethod?['kode'] == method['kode'];
              return GestureDetector(
                onTap: () => setState(() => _selectedPaymentMethod = method),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryColor : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? _primaryColor : _primarySurfaceDeep,
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _primaryColor.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            )
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getPaymentIcon(method['kode'] ?? ''),
                        size: 16,
                        color: isSelected ? Colors.white : _primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        method['nama'] ?? '-',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── Widget metode bayar untuk mobile bottom panel ─────────
  Widget _buildPaymentMethodSegmentMobile() {
    if (_paymentMethodsLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Metode Bayar',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _paymentMethods.map((method) {
            final isSelected = _selectedPaymentMethod?['id'] == method['id'] &&
                _selectedPaymentMethod?['kode'] == method['kode'];
            return GestureDetector(
              onTap: () => setState(() => _selectedPaymentMethod = method),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? _primaryColor : Colors.grey.shade300,
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPaymentIcon(method['kode'] ?? ''),
                      size: 14,
                      color: isSelected ? Colors.white : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      method['nama'] ?? '-',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

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
                      backgroundColor: _primaryColor,
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
                final navigator = Navigator.of(context);
                final shouldPop = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Konfirmasi'),
                    content: const Text(
                        'Ada item di keranjang. Yakin ingin keluar?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white),
                        child: const Text('Ya, Keluar'),
                      ),
                    ],
                  ),
                );
                if (shouldPop == true && mounted) {
                  navigator.pop();
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            isEditing ? 'Edit Pesanan' : 'Kasir',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryColor, _primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          elevation: 10,
          shadowColor: _primaryColor.withValues(alpha: 0.5),
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

  Widget _buildMobileLayout(bool isEditing) {
    return Stack(
      children: [
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
                        const BorderSide(color: _primaryLight, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.search, color: _primaryColor),
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
                          child: Text(!_isOnline && _products.isEmpty
                              ? 'Menu tidak tersedia offline.'
                              : 'Tidak ada menu'))
                      : GridView.builder(
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomPanel(isEditing),
        ),
      ],
    );
  }

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
          InkWell(
            onTap: _togglePanel,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shopping_cart_rounded,
                            color: _primaryColor, size: 24),
                      ),
                      if (_totalItem > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            child: Text('$_totalItem',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
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
                        Text(_getOrderSummaryLine(),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  if (_totalItem > 0) ...[
                    ElevatedButton(
                      onPressed: isEditing ? _savePesanan : _showPaymentDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(
                        isEditing ? 'Update' : 'Bayar',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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

  Widget _buildExpandedContent(bool isEditing) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 14),
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
                // ── PERUBAHAN: ganti segment hardcode → dinamis ──
                Expanded(child: _buildPaymentMethodSegmentMobile()),
              ],
            ),
            if (_jenisOrder == Constants.jenisOrderDineIn) ...[
              const SizedBox(height: 12),
              _buildTableSelector(),
            ],
            const SizedBox(height: 12),
            _buildNotesField(),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
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
                      color: _primaryColor,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primarySurface, _primarySurfaceDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.15), width: 1),
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
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isEditing ? _savePesanan : _showPaymentDialog,
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
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: _primaryColor.withValues(alpha: 0.35),
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

  Widget _buildCompactSegment({
    required String label,
    required List<_SegmentOption> options,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            return GestureDetector(
              onTap: opt.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: opt.isSelected ? _primaryColor : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        opt.isSelected ? _primaryColor : Colors.grey.shade300,
                    width: 1,
                  ),
                  boxShadow: opt.isSelected
                      ? [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt.icon,
                      size: 14,
                      color:
                          opt.isSelected ? Colors.white : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: opt.isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: opt.isSelected
                            ? Colors.white
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

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
                  decoration: const InputDecoration(
                    labelText: 'Cari Produk',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search, color: _primaryColor),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primarySurface, Color(0xFFdce6f2)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderTypeSelector(),
                  const SizedBox(height: 16),
                  _buildPaymentMethodSelector(), // ← sudah dinamis
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
                      onPressed: isEditing ? _savePesanan : _showPaymentDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
              selectedColor: _primaryColor,
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
                selectedColor: _primaryColor,
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
      elevation: isMobile ? 2 : 4,
      shadowColor: _primaryColor.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
        side: BorderSide(color: _primaryColor.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        onTap: () => _addToCart(product, 1),
        borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
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
                              color: _primaryLight),
                        ),
                      )
                    : Icon(Icons.restaurant_menu,
                        size: iconSize, color: _primaryLight),
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
                    product.useStock
                        ? Text('Stok: ${product.qty}',
                            style: TextStyle(
                                fontSize: isMobile ? 10 : 12,
                                color: product.qty <= 5
                                    ? Colors.orange
                                    : Colors.grey))
                        : Text('Tersedia',
                            style: TextStyle(
                                fontSize: isMobile ? 10 : 12,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w500)),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _jenisOrder = Constants.jenisOrderDineIn),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _jenisOrder == Constants.jenisOrderDineIn
                      ? _primaryColor
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _jenisOrder == Constants.jenisOrderDineIn
                        ? _primaryColor
                        : _primarySurfaceDeep,
                    width: 1.5,
                  ),
                  boxShadow: _jenisOrder == Constants.jenisOrderDineIn
                      ? [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restaurant,
                      size: 16,
                      color: _jenisOrder == Constants.jenisOrderDineIn
                          ? Colors.white
                          : _primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dine In',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _jenisOrder == Constants.jenisOrderDineIn
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _jenisOrder == Constants.jenisOrderDineIn
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _jenisOrder = Constants.jenisOrderTakeAway;
                _selectedMejaId = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _jenisOrder == Constants.jenisOrderTakeAway
                      ? _primaryColor
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _jenisOrder == Constants.jenisOrderTakeAway
                        ? _primaryColor
                        : _primarySurfaceDeep,
                    width: 1.5,
                  ),
                  boxShadow: _jenisOrder == Constants.jenisOrderTakeAway
                      ? [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.takeout_dining,
                      size: 16,
                      color: _jenisOrder == Constants.jenisOrderTakeAway
                          ? Colors.white
                          : _primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Take Away',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _jenisOrder == Constants.jenisOrderTakeAway
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _jenisOrder == Constants.jenisOrderTakeAway
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTableSelector() {
    // Offline dan cache kosong → input manual
    if (!_isOnline && _mejas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nomor Meja',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off, size: 13, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Offline: ketik nomor meja secara manual',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.orange.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: 'Contoh: 1, 2, VIP',
              labelText: 'Nomor Meja',
            ),
            onChanged: (value) {
              setState(() {
                _mejaNoInput = value.trim();
                _selectedMejaId = _mejaNoInput.isNotEmpty ? 0 : null;
              });
            },
          ),
        ],
      );
    }

    // Online atau cache tersedia → dropdown normal
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pilih Meja', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _mejas.any((m) => m.id == _selectedMejaId)
              ? _selectedMejaId
              : null,
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
        final hasOptions = item['has_options'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: hasOptions
                ? BorderSide(
                    color: _primaryColor.withValues(alpha: 0.35), width: 1.2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: hasOptions ? () => _editCartItemOptions(index, item) : null,
            borderRadius: BorderRadius.circular(10),
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
                            color: _primarySurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: _primaryColor, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
}
