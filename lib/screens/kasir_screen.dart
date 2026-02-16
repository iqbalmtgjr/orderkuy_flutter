import 'package:flutter/material.dart';
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

class KasirScreen extends StatefulWidget {
  final Order? orderToEdit;
  const KasirScreen({super.key, this.orderToEdit});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Kategori> _kategoris = [];
  List<Meja> _mejas = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  bool _isLoading = true;
  bool _isOnline = true;

  // Form fields
  int _jenisOrder = Constants.jenisOrderDineIn;
  int _metodeBayar = Constants.metodeBayarCash;
  int? _selectedMejaId;
  String _catatan = '';

  // Filter
  int? _selectedKategoriFilter; // null = semua kategori
  String _searchQuery = '';

  // Cart
  double _totalHarga = 0;
  int _totalItem = 0;

  // Payment
  final TextEditingController _nominalBayarController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _catatanController = TextEditingController();
  double _kembalian = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkConnectivity();
    _listenToConnectivity();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _applyFilters();
      });
    });

    // Populate form if editing
    if (widget.orderToEdit != null) {
      final order = widget.orderToEdit!;
      _jenisOrder = order.jenisOrder;
      _metodeBayar = order.metodeBayar;
      _selectedMejaId = order.mejaId;
      _catatan = order.catatan ?? '';
      _catatanController.text = _catatan;

      // Populate cart items
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
    _nominalBayarController.dispose();
    _searchController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // CONNECTIVITY MONITORING
  // ═══════════════════════════════════════════════════════════

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  void _listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });

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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final products = await ApiService.getMenus();
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
    });

    // After loading tables, check if selected meja is still valid
    if (widget.orderToEdit != null && _selectedMejaId != null) {
      final isMejaAvailable = _mejas.any((meja) => meja.id == _selectedMejaId);
      if (!isMejaAvailable) {
        setState(() => _selectedMejaId = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Meja yang dipilih tidak tersedia, silakan pilih meja lain'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredProducts = _products.where((product) {
        // Filter by kategori
        final matchKategori = _selectedKategoriFilter == null ||
            product.kategoriId == _selectedKategoriFilter;

        // Filter by search query
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
          content: Text('${product.namaProduk} ditambahkan'),
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
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Pesanan'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isOnline)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off,
                              size: 16, color: Colors.orange.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mode Offline: Pesanan akan tersimpan lokal',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Total: Rp ${_totalHarga.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nominalBayarController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal Bayar',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        final nominal = double.tryParse(value) ?? 0;
                        _kembalian = nominal - _totalHarga;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Kembalian: Rp ${_kembalian.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kembalian < 0 ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Item Pesanan:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._selectedItems.map(
                    (item) => ListTile(
                      dense: true,
                      title: Text(item['nama_produk']),
                      subtitle: Text(
                        '${item['qty']} x Rp${item['harga'].toStringAsFixed(0)}',
                      ),
                      trailing: Text(
                        'Rp${(item['qty'] * item['harga']).toStringAsFixed(0)}',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_kembalian < 0) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nominal bayar kurang')),
                  );
                }
                return;
              }
              Navigator.pop(context);
              _savePesanan();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 199, 0, 0),
              foregroundColor: Colors.white,
            ),
            child: const Text('Bayar & Simpan'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
// OPTIMIZED VERSION - KASIR_SCREEN.DART
// Replace _savePesanan() dan _printReceipt() methods dengan yang ini
// ═══════════════════════════════════════════════════════════

  Future<void> _savePesanan() async {
    // ← SHOW LOADING: Simpan pesanan
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Menyimpan pesanan...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
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
          .map(
            (item) => {
              'menu_id': item['menu_id'],
              'qty': item['qty'],
              'harga': item['harga'],
            },
          )
          .toList(),
      'total_harga': _totalHarga,
    };

    final isEditing = widget.orderToEdit != null;
    final result = isEditing
        ? await ApiService.updateOrder(widget.orderToEdit!.id, orderData)
        : await ApiService.createOrder(orderData);

    if (!mounted) return;
    Navigator.pop(context); // Close "Menyimpan pesanan..." loading

    if (result['success']) {
      final isOffline = result['offline'] == true;

      // ← OPTIMIZED: Print langsung tanpa dialog tambahan
      if (!isOffline && result['data'] != null) {
        // Show print loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Mencetak struk...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        );

        final printSuccess = await _printReceipt(result['data']);

        if (!mounted) return;
        Navigator.pop(context); // Close print loading

        // Show appropriate message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                printSuccess
                    ? (isEditing
                        ? 'Pesanan berhasil diperbarui dan struk dicetak'
                        : 'Pesanan berhasil disimpan dan struk dicetak')
                    : (isEditing
                        ? 'Pesanan berhasil diperbarui tapi struk gagal dicetak'
                        : 'Pesanan berhasil disimpan tapi struk gagal dicetak'),
              ),
              backgroundColor: printSuccess ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Offline mode
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📵 Pesanan disimpan offline, akan tersinkron saat online',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      // Reset form only if creating new order
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

      if (mounted) {
        Navigator.pop(context);
      }
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

  // ← OPTIMIZED: Return bool untuk indikasi sukses/gagal
  Future<bool> _printReceipt(Map<String, dynamic> orderData) async {
    try {
      // ← REMOVED: Tidak ada dialog tambahan di sini, sudah ada di _savePesanan

      final savedPrinter = await ThermalPrintService.getSavedPrinter();
      if (savedPrinter == null) {
        debugPrint('⚠️ Printer belum dipilih');
        return false;
      }

      ThermalPrintService.setSelectedPrinter(savedPrinter);

      final kasirNama = orderData['user']?['name']?.toString();
      final tokoNama =
          orderData['toko']?['nama_toko']?.toString() ?? 'OrderKuy';

      // ← PRINT: Langsung dengan timeout yang sudah dioptimasi
      final success = await ThermalPrintService.printReceipt(
        orderId: orderData['id']?.toString() ?? '',
        tokoNama: tokoNama,
        tokoAlamat: orderData['toko']?['alamat']?.toString() ?? '-',
        items: _selectedItems,
        totalHarga: _totalHarga,
        jenisOrder: _jenisOrder,
        mejaNo: _jenisOrder == Constants.jenisOrderDineIn
            ? _mejas.firstWhere((m) => m.id == _selectedMejaId).noMeja
            : null,
        catatan: _catatan,
        metodeBayar: _metodeBayar,
        kasirNama: kasirNama,
      );

      return success;
    } catch (e) {
      debugPrint('❌ Error print: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.orderToEdit != null;

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
                'Ada item di keranjang. Yakin ingin keluar?\nData akan hilang.',
              ),
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
                  child: const Text('Ya, Keluar'),
                ),
              ],
            ),
          );

          if (shouldPop == true && context.mounted) {
            Navigator.pop(context);
          }
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
                      'Ada item di keranjang. Yakin ingin keluar?\nData akan hilang.',
                    ),
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
                        child: const Text('Ya, Keluar'),
                      ),
                    ],
                  ),
                );

                if (shouldPop == true && mounted) {
                  Navigator.pop(context);
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(isEditing ? 'Edit Pesanan' : 'Kasir',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
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
            IconButton(
              icon: const Icon(Icons.print, color: Colors.white),
              onPressed: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrinterSetupScreen(),
                  ),
                );
              },
              tooltip: 'Setup Printer',
            ),
          ],
        ),
        body: Column(
          children: [
            const SyncStatusWidget(),
            Expanded(
              child: Row(
                children: [
                  // Left: Product List
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        // Search Bar
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'Cari Produk',
                              border: const OutlineInputBorder(),
                              prefixIcon:
                                  Icon(Icons.search, color: Colors.red[700]),
                            ),
                          ),
                        ),

                        // Kategori Filter
                        _buildKategoriFilter(),

                        // Product Grid
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _filteredProducts.isEmpty
                                  ? Center(
                                      child: Text(
                                        !_isOnline && _products.isEmpty
                                            ? 'Menu tidak tersedia offline. Silakan koneksi internet untuk memuat menu.'
                                            : 'Tidak ada menu',
                                      ),
                                    )
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
                                      itemBuilder: (context, index) {
                                        final product =
                                            _filteredProducts[index];
                                        return _buildProductCard(product);
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),

                  // Right: Order Form
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red[50]!,
                            Colors.red[100]!,
                          ],
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
                            const Text(
                              'Item Dipilih',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                                  shadowColor:
                                      Colors.red.withValues(alpha: 0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ).copyWith(
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith<Color>(
                                    (Set<WidgetState> states) {
                                      if (states
                                          .contains(WidgetState.hovered)) {
                                        return const Color(0xFFB71C1C);
                                      }
                                      return const Color(0xFFD32F2F);
                                    },
                                  ),
                                ),
                                child: Text(
                                  isEditing
                                      ? 'Update & Simpan'
                                      : 'Bayar & Simpan',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // KATEGORI FILTER WIDGET (BARU)
  // ═══════════════════════════════════════════════════════════

  Widget _buildKategoriFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Chip "Semua"
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Semua'),
              selected: _selectedKategoriFilter == null,
              onSelected: (selected) {
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

          // Chips untuk setiap kategori
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

  // ═══════════════════════════════════════════════════════════
  // BUILD METHODS (SAMA SEPERTI SEBELUMNYA)
  // ═══════════════════════════════════════════════════════════

  Widget _buildProductCard(Product product) {
    const String baseUrl =
        'https://orderkuy.indotechconsulting.com/assets/img/menu/';

    return Card(
      elevation: 8,
      shadowColor: Colors.red.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
                padding: const EdgeInsets.all(8),
                child: product.foto != null && product.foto!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '$baseUrl${product.foto}',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.restaurant_menu,
                              size: 48,
                              color: Theme.of(context).primaryColor,
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.restaurant_menu,
                        size: 48,
                        color: Theme.of(context).primaryColor,
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.namaProduk,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rp ${product.harga.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stok: ${product.qty}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
                    style: TextStyle(color: Colors.white)),
                selected: _jenisOrder == Constants.jenisOrderDineIn,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (selected) {
                  setState(() => _jenisOrder = Constants.jenisOrderDineIn);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Take Away',
                    style: TextStyle(color: Colors.white)),
                selected: _jenisOrder == Constants.jenisOrderTakeAway,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (selected) {
                  setState(() {
                    _jenisOrder = Constants.jenisOrderTakeAway;
                    _selectedMejaId = null;
                  });
                },
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
                label:
                    const Text('Cash', style: TextStyle(color: Colors.white)),
                selected: _metodeBayar == Constants.metodeBayarCash,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (selected) {
                  setState(() => _metodeBayar = Constants.metodeBayarCash);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Transfer',
                    style: TextStyle(color: Colors.white)),
                selected: _metodeBayar == Constants.metodeBayarTransfer,
                selectedColor: const Color(0xFFD32F2F),
                backgroundColor: const Color.fromARGB(255, 9, 0, 1),
                onSelected: (selected) {
                  setState(() => _metodeBayar = Constants.metodeBayarTransfer);
                },
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
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: _mejas.map((meja) {
            return DropdownMenuItem<int>(
              value: meja.id,
              child: Text('Meja ${meja.noMeja}'),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedMejaId = value);
          },
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
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Tambahkan catatan jika ada',
          ),
          onChanged: (value) {
            setState(() => _catatan = value);
          },
        ),
      ],
    );
  }

  Widget _buildCartItems() {
    if (_selectedItems.isEmpty) {
      return const Text('Belum ada item dipilih');
    }
    return Column(
      children: _selectedItems.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(item['nama_produk']),
            subtitle:
                Text('${item['qty']} x Rp${item['harga'].toStringAsFixed(0)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => _updateQuantity(index, -1),
                ),
                Text('${item['qty']}'),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _updateQuantity(index, 1),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeFromCart(index),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTotals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Item: $_totalItem'),
        Text('Total Harga: Rp ${_totalHarga.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
