import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orderkuy_kasir/screens/pengeluaran_form_screen.dart';
import '../services/api_service.dart';
import '../models/pengeluaran.dart';

class PengeluaranScreen extends StatefulWidget {
  const PengeluaranScreen({super.key});

  @override
  State<PengeluaranScreen> createState() => _PengeluaranScreenState();
}

class _PengeluaranScreenState extends State<PengeluaranScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  final List<Pengeluaran> _pengeluaranList = [];
  bool _isLoading = true;
  String? _searchQuery;
  DateTime? _tanggalAwal;
  DateTime? _tanggalAkhir;
  double _totalPengeluaran = 0;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadPengeluaran();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final value = _searchController.text.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _searchQuery = value.isEmpty ? null : value;
      });
      _loadPengeluaran();
    });
  }

  Future<void> _loadPengeluaran() async {
    setState(() {
      _isLoading = true;
    });

    debugPrint('🔄 Loading Pengeluaran...');

    final result = await ApiService.getPengeluaran(
      search: _searchQuery,
      tanggalAwal: _tanggalAwal != null
          ? DateFormat('yyyy-MM-dd').format(_tanggalAwal!)
          : null,
      tanggalAkhir: _tanggalAkhir != null
          ? DateFormat('yyyy-MM-dd').format(_tanggalAkhir!)
          : null,
    );

    debugPrint('📦 Result: ${result.toString()}');
    debugPrint('✅ Success: ${result['success']}');

    if (!mounted) return;

    if (result is! Map<String, dynamic>) {
      debugPrint('❌ Result bukan Map');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respon server tidak valid')),
      );
      return;
    }

    if (result['success'] == true) {
      final rawData = result['data'];
      debugPrint('🔍 Raw Data Type: ${rawData.runtimeType}');
      debugPrint('🔍 Raw Data is List: ${rawData is List}');
      debugPrint('🔍 Raw Data length: ${rawData is List ? rawData.length : 0}');

      List<Pengeluaran> pengeluaranList = [];

      if (rawData is List<Pengeluaran>) {
        pengeluaranList = rawData;
        debugPrint('✅ Data already parsed as List<Pengeluaran>');
      } else if (rawData is List) {
        debugPrint('⚠️ Data is List but not List<Pengeluaran>, parsing now...');
        for (var item in rawData) {
          try {
            if (item is Pengeluaran) {
              pengeluaranList.add(item);
            } else if (item is Map<String, dynamic>) {
              pengeluaranList.add(Pengeluaran.fromJson(item));
            }
          } catch (e) {
            debugPrint('❌ Error parsing item: $e');
          }
        }
      }

      debugPrint('✅ Parsed List Length: ${pengeluaranList.length}');

      setState(() {
        _pengeluaranList.clear();
        _pengeluaranList.addAll(pengeluaranList);

        debugPrint(
            '✅ _pengeluaranList Length after setState: ${_pengeluaranList.length}');

        final rawTotal = result['total_pengeluaran'];
        if (rawTotal == null) {
          _totalPengeluaran = 0;
        } else if (rawTotal is num) {
          _totalPengeluaran = rawTotal.toDouble();
        } else if (rawTotal is String) {
          _totalPengeluaran = double.tryParse(rawTotal) ?? 0;
        } else {
          _totalPengeluaran = 0;
        }

        debugPrint('💵 Total Pengeluaran: $_totalPengeluaran');

        _isLoading = false;
      });
    } else {
      debugPrint('❌ API returned success: false');
      debugPrint('❌ Message: ${result['message']}');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal memuat data pengeluaran'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deletePengeluaran(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Konfirmasi Hapus'),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin menghapus pengeluaran ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService.deletePengeluaran(id);

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pengeluaran berhasil dihapus'),
            backgroundColor: Colors.green.shade600,
          ),
        );
        _loadPengeluaran();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal menghapus pengeluaran'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showPengeluaranForm({Pengeluaran? pengeluaran}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PengeluaranForm(
        pengeluaran: pengeluaran,
        onSave: (data) async {
          Navigator.pop(context);
          await _handleSavePengeluaran(data, pengeluaran?.id);
        },
      ),
    );
  }

  Future<void> _handleSavePengeluaran(
      Map<String, dynamic> data, int? id) async {
    final result = id != null
        ? await ApiService.updatePengeluaran(id, data)
        : await ApiService.createPengeluaran(data);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Pengeluaran berhasil disimpan'),
          backgroundColor: Colors.green.shade600,
        ),
      );
      _loadPengeluaran();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Gagal menyimpan pengeluaran'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _clearFilters() {
    setState(() {
      _tanggalAwal = null;
      _tanggalAkhir = null;
      _searchController.clear();
      _searchQuery = null;
    });
    _loadPengeluaran();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    debugPrint(
        '🎨 Building UI - isLoading: $_isLoading, listLength: ${_pengeluaranList.length}');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Kembali ke Dashboard',
        ),
        title: const Text('Pengeluaran'),
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey.shade200,
          ),
        ),
      ),
      body: Column(
        children: [
          // Header dengan Total Pengeluaran
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade400, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.shade200.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Pengeluaran',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currencyFormat.format(_totalPengeluaran),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_pengeluaranList.length} transaksi',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Filter Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nama pengeluaran...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = null);
                              _loadPengeluaran();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.red.shade400, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                ),

                const SizedBox(height: 12),

                // Filter Tanggal Row
                Row(
                  children: [
                    // Tanggal Awal
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _tanggalAwal ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: Colors.red.shade400,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (date != null) {
                            setState(() => _tanggalAwal = date);
                            _loadPengeluaran();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _tanggalAwal != null
                                ? Colors.red.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _tanggalAwal != null
                                  ? Colors.red.shade400
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _tanggalAwal != null
                                    ? Colors.red.shade700
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tanggalAwal != null
                                      ? DateFormat('dd/MM/yyyy')
                                          .format(_tanggalAwal!)
                                      : 'Dari Tanggal',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _tanggalAwal != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _tanggalAwal != null
                                        ? Colors.red.shade700
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),

                    // Tanggal Akhir
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _tanggalAkhir ?? DateTime.now(),
                            firstDate: _tanggalAwal ?? DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: Colors.red.shade400,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (date != null) {
                            setState(() => _tanggalAkhir = date);
                            _loadPengeluaran();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _tanggalAkhir != null
                                ? Colors.red.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _tanggalAkhir != null
                                  ? Colors.red.shade400
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _tanggalAkhir != null
                                    ? Colors.red.shade700
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tanggalAkhir != null
                                      ? DateFormat('dd/MM/yyyy')
                                          .format(_tanggalAkhir!)
                                      : 'Sampai Tanggal',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _tanggalAkhir != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _tanggalAkhir != null
                                        ? Colors.red.shade700
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Reset Button
                    if (_tanggalAwal != null ||
                        _tanggalAkhir != null ||
                        _searchQuery != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Reset Filter',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Builder(
              builder: (context) {
                debugPrint(
                    '🎨 ListView Builder - isLoading: $_isLoading, isEmpty: ${_pengeluaranList.isEmpty}, length: ${_pengeluaranList.length}');

                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_pengeluaranList.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: _loadPengeluaran,
                  color: Colors.red.shade400,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          MediaQuery.of(context).size.width > 600 ? 3 : 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _pengeluaranList.length,
                    itemBuilder: (context, index) {
                      final pengeluaran = _pengeluaranList[index];
                      debugPrint(
                          '🎨 Building card $index: ${pengeluaran.namaPengeluaran}');
                      return _buildPengeluaranCard(pengeluaran);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPengeluaranForm(),
        backgroundColor: Colors.red.shade400,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
        elevation: 4,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.shade100,
                    Colors.red.shade50,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.shade100.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 60,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Belum Ada Pengeluaran',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pengeluaran yang ditambahkan akan muncul di sini',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPengeluaranCard(Pengeluaran pengeluaran) {
    final date = DateTime.tryParse(pengeluaran.tanggal);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showPengeluaranForm(pengeluaran: pengeluaran),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header dengan Menu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      date != null ? DateFormat('dd/MM').format(date) : '-',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert,
                        size: 18, color: Colors.grey.shade600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showPengeluaranForm(pengeluaran: pengeluaran);
                      } else if (value == 'delete') {
                        if (pengeluaran.id != null) {
                          _deletePengeluaran(pengeluaran.id!);
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Hapus', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Icon & Nama Pengeluaran
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      size: 20,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pengeluaran.namaPengeluaran,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Deskripsi (jika ada)
              if (pengeluaran.deskripsi != null &&
                  pengeluaran.deskripsi!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  pengeluaran.deskripsi!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Divider
              Container(
                height: 1,
                color: Colors.grey.shade200,
              ),

              const SizedBox(height: 12),

              // Jumlah
              Text(
                _currencyFormat.format(pengeluaran.jumlah),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
