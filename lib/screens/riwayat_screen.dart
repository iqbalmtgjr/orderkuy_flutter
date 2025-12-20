import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/history.dart';
import '../services/api_service.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<History> _orders = [];
  RiwayatSummary? _summary;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int _lastPage = 1;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Filters
  DateTime? _tanggalDari;
  DateTime? _tanggalSampai;
  int? _jenisOrderFilter;
  int? _metodePembayaranFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _lastPage) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    try {
      // Load summary (tapi jangan crash jika gagal)
      try {
        final summaryResponse = await ApiService.getRiwayatSummary(
          tanggalDari: _tanggalDari?.toIso8601String(),
          tanggalSampai: _tanggalSampai?.toIso8601String(),
        );

        if (summaryResponse['success']) {
          setState(() {
            _summary = RiwayatSummary.fromJson(summaryResponse['data']);
          });
        }
      } catch (summaryError) {
        debugPrint('⚠️ Summary error (non-critical): $summaryError');
        // Lanjutkan meskipun summary gagal
      }

      // Load orders
      final response = await ApiService.getRiwayat(
        page: _currentPage,
        tanggalDari: _tanggalDari?.toIso8601String().split('T')[0],
        tanggalSampai: _tanggalSampai?.toIso8601String().split('T')[0],
        jenisOrder: _jenisOrderFilter,
        metodePembayaran: _metodePembayaranFilter,
        search:
            _searchController.text.isNotEmpty ? _searchController.text : null,
      );

      if (response['success']) {
        final List<dynamic> data = response['data'];
        final meta = response['meta'];

        setState(() {
          _orders = data.map((json) => History.fromJson(json)).toList();
          _lastPage = meta['last_page'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
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

  Future<void> _loadMoreData() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    try {
      final response = await ApiService.getRiwayat(
        page: _currentPage,
        tanggalDari: _tanggalDari?.toIso8601String().split('T')[0],
        tanggalSampai: _tanggalSampai?.toIso8601String().split('T')[0],
        jenisOrder: _jenisOrderFilter,
        metodePembayaran: _metodePembayaranFilter,
        search:
            _searchController.text.isNotEmpty ? _searchController.text : null,
      );

      if (response['success']) {
        final List<dynamic> data = response['data'];
        setState(() {
          _orders.addAll(data.map((json) => History.fromJson(json)).toList());
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
        _currentPage--;
      });
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterBottomSheet(
        tanggalDari: _tanggalDari,
        tanggalSampai: _tanggalSampai,
        jenisOrder: _jenisOrderFilter,
        metodePembayaran: _metodePembayaranFilter,
        onApply: (dari, sampai, jenis, metode) {
          setState(() {
            _tanggalDari = dari;
            _tanggalSampai = sampai;
            _jenisOrderFilter = jenis;
            _metodePembayaranFilter = metode;
          });
          _loadData();
        },
        onReset: () {
          setState(() {
            _tanggalDari = null;
            _tanggalSampai = null;
            _jenisOrderFilter = null;
            _metodePembayaranFilter = null;
          });
          _loadData();
        },
      ),
    );
  }

  String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    )}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Summary Card
                  if (_summary != null) _buildSummaryCard(),

                  // Search Bar
                  _buildSearchBar(),

                  // Order List
                  Expanded(
                    child: _orders.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount:
                                _orders.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _orders.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return _buildOrderCard(_orders[index]);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade700, Colors.red.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem(
                'Total Transaksi',
                _summary!.totalTransaksi.toString(),
                Icons.receipt_long,
              ),
              _buildSummaryItem(
                'Total Pendapatan',
                _formatRupiah(_summary!.totalPendapatan),
                Icons.attach_money,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem(
                'Cash',
                _formatRupiah(_summary!.totalCash),
                Icons.payments,
              ),
              _buildSummaryItem(
                'Transfer',
                _formatRupiah(_summary!.totalTransfer),
                Icons.credit_card,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'Cari kode order atau nama customer...',
          border: InputBorder.none,
          icon: Icon(Icons.search),
        ),
        onSubmitted: (_) => _loadData(),
      ),
    );
  }

  Widget _buildOrderCard(History order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showOrderDetail(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.kodeOrder,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.tanggalDisplay,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: order.metodePembayaran == 1
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order.metodePembayaranText,
                      style: TextStyle(
                        color: order.metodePembayaran == 1
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.namaCustomer,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            order.jenisOrder == 1
                                ? Icons.restaurant
                                : Icons.shopping_bag,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            order.jenisOrderText,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          if (order.meja != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• Meja ${order.meja!.nomorMeja}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  Text(
                    _formatRupiah(order.totalHarga),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Belum ada riwayat transaksi',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetail(History order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                order.kodeOrder,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                order.tanggalDisplay,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const Divider(height: 32),
              _buildDetailRow('Customer', order.namaCustomer),
              _buildDetailRow('Jenis Order', order.jenisOrderText),
              if (order.meja != null)
                _buildDetailRow('Meja', order.meja!.nomorMeja),
              _buildDetailRow('Pembayaran', order.metodePembayaranText),
              if (order.kasir != null) _buildDetailRow('Kasir', order.kasir!),
              const SizedBox(height: 24),
              const Text(
                'Item Pesanan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.menuNama,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${item.qty}x ${_formatRupiah(item.harga)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatRupiah(item.subtotal),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatRupiah(order.totalHarga),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final DateTime? tanggalDari;
  final DateTime? tanggalSampai;
  final int? jenisOrder;
  final int? metodePembayaran;
  final Function(DateTime?, DateTime?, int?, int?) onApply;
  final VoidCallback onReset;

  const _FilterBottomSheet({
    this.tanggalDari,
    this.tanggalSampai,
    this.jenisOrder,
    this.metodePembayaran,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  DateTime? _tanggalDari;
  DateTime? _tanggalSampai;
  int? _jenisOrder;
  int? _metodePembayaran;

  @override
  void initState() {
    super.initState();
    _tanggalDari = widget.tanggalDari;
    _tanggalSampai = widget.tanggalSampai;
    _jenisOrder = widget.jenisOrder;
    _metodePembayaran = widget.metodePembayaran;
  }

  Future<void> _selectDate(bool isDari) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        if (isDari) {
          _tanggalDari = date;
        } else {
          _tanggalSampai = date;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filter',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  widget.onReset();
                  Navigator.pop(context);
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Tanggal', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _selectDate(true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _tanggalDari != null
                        ? DateFormat('dd/MM/yyyy').format(_tanggalDari!)
                        : 'Dari',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _selectDate(false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _tanggalSampai != null
                        ? DateFormat('dd/MM/yyyy').format(_tanggalSampai!)
                        : 'Sampai',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Jenis Order',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Semua'),
                selected: _jenisOrder == null,
                onSelected: (selected) => setState(() => _jenisOrder = null),
              ),
              FilterChip(
                label: const Text('Dine In'),
                selected: _jenisOrder == 1,
                onSelected: (selected) => setState(() => _jenisOrder = 1),
              ),
              FilterChip(
                label: const Text('Take Away'),
                selected: _jenisOrder == 2,
                onSelected: (selected) => setState(() => _jenisOrder = 2),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Metode Pembayaran',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Semua'),
                selected: _metodePembayaran == null,
                onSelected: (selected) =>
                    setState(() => _metodePembayaran = null),
              ),
              FilterChip(
                label: const Text('Cash'),
                selected: _metodePembayaran == 1,
                onSelected: (selected) => setState(() => _metodePembayaran = 1),
              ),
              FilterChip(
                label: const Text('Transfer'),
                selected: _metodePembayaran == 2,
                onSelected: (selected) => setState(() => _metodePembayaran = 2),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(
                  _tanggalDari,
                  _tanggalSampai,
                  _jenisOrder,
                  _metodePembayaran,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Terapkan Filter'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
