import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history.dart';
import '../services/api_service.dart';
import '../services/refund_service.dart';
import '../utils/constants.dart';
import '../widgets/refund_dialog.dart';
import '../widgets/invoice_share_widget.dart';

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
  bool _isOffline = false;
  int _currentPage = 1;
  int _lastPage = 1;

  // ── TAMBAH: kasirId dari user yang login ──────────────────
  int _kasirId = 0;
  String _tokoNama = '';
  String _tokoAlamat = '';

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<int, RefundModel?> _refundCache = {};

  DateTime? _tanggalDari;
  DateTime? _tanggalSampai;
  int? _jenisOrderFilter;
  int? _metodePembayaranFilter;

  @override
  void initState() {
    super.initState();
    _loadKasirId(); // ← TAMBAH
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── TAMBAH: baca kasirId & toko dari SharedPreferences ───────────
  Future<void> _loadKasirId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(Constants.userKey);
      if (userJson != null) {
        final user = jsonDecode(userJson);
        final id = user['id'];
        final toko = user['toko'];
        if (mounted) {
          setState(() {
            _kasirId = id is int ? id : int.tryParse(id.toString()) ?? 0;
            if (toko is Map) {
              _tokoNama = toko['nama_toko']?.toString() ?? '';
              _tokoAlamat = toko['alamat']?.toString() ?? '';
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ _loadKasirId error: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _lastPage) {
        _loadMoreData();
      }
    }
  }

  String? _formatDateParam(DateTime? date) =>
      date != null ? DateFormat('yyyy-MM-dd').format(date) : null;

  // ── Sudah ada — tidak diubah ──────────────────────────────
  Future<void> _loadRefundForOrder(int orderId) async {
    if (_refundCache.containsKey(orderId)) return;
    final refund = await RefundService.getRefundByOrder(orderId);
    if (mounted) setState(() => _refundCache[orderId] = refund);
  }

  // ── UBAH: kasirId sekarang pakai _kasirId ─────────────────
  Future<void> _bukaRefundDialog({
    required int orderId,
    required double totalOrder,
    required String nomorOrder,
  }) async {
    final result = await showDialog<RefundModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundDialog(
        orderId: orderId,
        userId: _kasirId,
        totalOrder: totalOrder.toDouble(),
        nomorOrder: nomorOrder,
      ),
    );

    if (result != null) {
      setState(() => _refundCache[orderId] = result);
      _showSnackBar('Permintaan refund berhasil diajukan.');
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _orders = [];
    });

    if (_tanggalDari != null &&
        _tanggalSampai != null &&
        _tanggalDari!.isAfter(_tanggalSampai!)) {
      _showSnackBar('Tanggal awal tidak boleh melebihi tanggal akhir',
          isError: true);
      setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.getRiwayatSummary(
          tanggalDari: _formatDateParam(_tanggalDari),
          tanggalSampai: _formatDateParam(_tanggalSampai),
        ).catchError((_) => <String, dynamic>{'success': false}),
        ApiService.getRiwayat(
          page: _currentPage,
          tanggalDari: _formatDateParam(_tanggalDari),
          tanggalSampai: _formatDateParam(_tanggalSampai),
          jenisOrder: _jenisOrderFilter,
          metodePembayaran: _metodePembayaranFilter,
          search: _searchController.text.trim().isNotEmpty
              ? _searchController.text.trim()
              : null,
        ),
      ]);

      if (!mounted) return;

      final summaryRes = results[0];
      final riwayatRes = results[1];

      if (summaryRes['success'] == true && summaryRes['data'] != null) {
        setState(() => _summary = RiwayatSummary.fromJson(summaryRes['data']));
      }

      if (riwayatRes['success'] == true) {
        final List<dynamic> data = riwayatRes['data'] ?? [];
        final meta = riwayatRes['meta'] ?? {};
        setState(() {
          _orders = data.map((json) => History.fromJson(json)).toList();
          _lastPage = meta['last_page'] ?? 1;
          _isOffline = riwayatRes['offline'] == true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isOffline = riwayatRes['offline'] == true;
          _isLoading = false;
        });
        if (riwayatRes['offline'] != true) {
          _showSnackBar(riwayatRes['message'] ?? 'Gagal memuat data',
              isError: true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Gagal terhubung ke server', isError: true);
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore || _currentPage >= _lastPage) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    try {
      final response = await ApiService.getRiwayat(
        page: _currentPage,
        tanggalDari: _formatDateParam(_tanggalDari),
        tanggalSampai: _formatDateParam(_tanggalSampai),
        jenisOrder: _jenisOrderFilter,
        metodePembayaran: _metodePembayaranFilter,
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        setState(() {
          _orders.addAll(data.map((json) => History.fromJson(json)).toList());
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoadingMore = false;
          _currentPage--;
        });
        _showSnackBar('Gagal memuat halaman berikutnya', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _currentPage--;
      });
      _showSnackBar('Gagal terhubung ke server', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB71C1C) : const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
    return 'Rp${amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        backgroundColor: const Color(0xFF1a315b),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 15),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline — Menampilkan data terakhir yang tersimpan',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (_summary != null) _buildSummaryCard(),
                        _buildSearchBar(),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a315b), Color(0xFF0f2040)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1a315b).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildSummaryItem('Total Transaksi',
                  _summary!.totalTransaksi.toString(), Icons.receipt_long),
              _buildSummaryItem('Total Pendapatan',
                  _formatRupiah(_summary!.totalPendapatan), Icons.attach_money),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryItem(
                  'Cash', _formatRupiah(_summary!.totalCash), Icons.payments),
              _buildSummaryItem('Transfer',
                  _formatRupiah(_summary!.totalTransfer), Icons.credit_card),
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
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadData(),
              maxLength: 100,
              decoration: InputDecoration(
                hintText: 'Cari kode order atau catatan...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a315b),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cari',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── UBAH: tambah _buildRefundRow di bawah card ────────────
  Widget _buildOrderCard(History order) {
    // Panggil load refund tiap kali card dirender
    _loadRefundForOrder(order.id);

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
              // ── Baris atas: kode order + badge metode bayar ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.kodeOrder,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(order.tanggalDisplay,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
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

              // ── Baris bawah: info order + total ─────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.namaCustomer,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
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
                          Text(order.jenisOrderText,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12)),
                          if (order.meja != null) ...[
                            const SizedBox(width: 8),
                            Text('• Meja ${order.meja!.nomorMeja}',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ],
                      ),
                    ],
                  ),
                  Text(
                    _formatRupiah(order.totalHarga),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1a315b)),
                  ),
                ],
              ),

              // ── TAMBAH: baris refund di bawah ───────────────
              const SizedBox(height: 8),
              _buildRefundRow(order),
            ],
          ),
        ),
      ),
    );
  }

  // ── TAMBAH: widget refund row ─────────────────────────────
  Widget _buildRefundRow(History order) {
    final refund = _refundCache[order.id];

    // Sedang loading (key belum ada di cache) → kosong
    if (!_refundCache.containsKey(order.id)) {
      return const SizedBox.shrink();
    }

    // Sudah ada refund → tampilkan badge
    if (refund != null) {
      return _RefundBadge(status: refund.status);
    }

    // Belum ada refund → tombol Refund
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => _bukaRefundDialog(
          orderId: order.id,
          totalOrder: order.totalHarga,
          nomorOrder: order.kodeOrder,
        ),
        icon: const Icon(Icons.assignment_return_rounded, size: 16),
        label: const Text('Refund'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.orange.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          textStyle: const TextStyle(fontSize: 13),
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
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Coba ubah filter tanggal',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  void _showInvoiceDialog(History order) {
    showDialog(
      context: context,
      builder: (_) => InvoiceShareDialog(
        order: order,
        tokoNama: _tokoNama,
        tokoAlamat: _tokoAlamat,
      ),
    );
  }

  // ── UBAH: tambah tombol/badge refund di detail bottom sheet ─
  void _showOrderDetail(History order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 24),
              Text(order.kodeOrder,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(order.tanggalDisplay,
                  style: TextStyle(color: Colors.grey.shade600)),
              const Divider(height: 32),
              _buildDetailRow('Customer', order.namaCustomer),
              _buildDetailRow('Jenis Order', order.jenisOrderText),
              if (order.meja != null)
                _buildDetailRow('Meja', order.meja!.nomorMeja),
              _buildDetailRow('Pembayaran', order.metodePembayaranText),
              if (order.kasir != null) _buildDetailRow('Kasir', order.kasir!),
              const SizedBox(height: 24),
              const Text('Item Pesanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                              Text(item.menuNama,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              Text('${item.qty}x ${_formatRupiah(item.harga)}',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(_formatRupiah(item.subtotal),
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    _formatRupiah(order.totalHarga),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1a315b)),
                  ),
                ],
              ),

              // ── TAMBAH: refund section di detail ────────────
              const SizedBox(height: 20),
              _buildRefundSection(order),

              // ── Tombol bagikan invoice ───────────────────────
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showInvoiceDialog(order),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Bagikan Invoice',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a315b),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── TAMBAH: section refund di dalam detail bottom sheet ───
  Widget _buildRefundSection(History order) {
    final refund = _refundCache[order.id];

    if (refund != null) {
      // Ada refund — tampilkan info detail
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: refund.isApproved
              ? Colors.green.shade50
              : refund.isRejected
                  ? Colors.red.shade50
                  : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: refund.isApproved
                ? Colors.green.shade200
                : refund.isRejected
                    ? Colors.red.shade200
                    : Colors.orange.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_return_rounded,
                    size: 16,
                    color: refund.isApproved
                        ? Colors.green.shade700
                        : refund.isRejected
                            ? Colors.red.shade700
                            : Colors.orange.shade700),
                const SizedBox(width: 6),
                Text(
                  'Info Refund',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: refund.isApproved
                        ? Colors.green.shade700
                        : refund.isRejected
                            ? Colors.red.shade700
                            : Colors.orange.shade700,
                  ),
                ),
                const Spacer(),
                _RefundBadge(status: refund.status),
              ],
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
                'Jumlah', _formatRupiah(refund.jumlahRefund.toDouble())),
            _buildDetailRow('Metode', refund.metodeRefund),
            _buildDetailRow('Alasan', refund.alasan),
            if (refund.catatan != null && refund.catatan!.isNotEmpty)
              _buildDetailRow('Catatan', refund.catatan!),
          ],
        ),
      );
    }

    // Belum ada refund → tombol ajukan
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.pop(context); // tutup bottom sheet dulu
          _bukaRefundDialog(
            orderId: order.id,
            totalOrder: order.totalHarga,
            nomorOrder: order.kodeOrder,
          );
        },
        icon: Icon(Icons.assignment_return_rounded,
            size: 18, color: Colors.orange.shade700),
        label: Text('Ajukan Refund',
            style: TextStyle(color: Colors.orange.shade700)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.orange.shade300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget _RefundBadge
// ─────────────────────────────────────────────────────────────────────────────

class _RefundBadge extends StatelessWidget {
  final String status; // pending | approved | rejected

  const _RefundBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _config();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 13, color: config.fgColor),
          const SizedBox(width: 4),
          Text(
            config.label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: config.fgColor),
          ),
        ],
      ),
    );
  }

  _BadgeConfig _config() {
    switch (status) {
      case 'approved':
        return _BadgeConfig(
          label: 'Sudah Direfund',
          icon: Icons.check_circle_outline,
          bgColor: Colors.green.shade50,
          fgColor: Colors.green.shade700,
        );
      case 'rejected':
        return _BadgeConfig(
          label: 'Refund Ditolak',
          icon: Icons.cancel_outlined,
          bgColor: Colors.red.shade50,
          fgColor: Colors.red.shade700,
        );
      default:
        return _BadgeConfig(
          label: 'Refund Diproses',
          icon: Icons.hourglass_empty_rounded,
          bgColor: Colors.orange.shade50,
          fgColor: Colors.orange.shade700,
        );
    }
  }
}

class _BadgeConfig {
  final String label;
  final IconData icon;
  final Color bgColor;
  final Color fgColor;
  const _BadgeConfig({
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.fgColor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Bottom Sheet — tidak ada perubahan dari versi kamu
// ─────────────────────────────────────────────────────────────────────────────

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
  String? _tanggalError;

  @override
  void initState() {
    super.initState();
    _tanggalDari = widget.tanggalDari;
    _tanggalSampai = widget.tanggalSampai;
    _jenisOrder = widget.jenisOrder;
    _metodePembayaran = widget.metodePembayaran;
  }

  Future<void> _selectDate(bool isDari) async {
    final initial = isDari
        ? (_tanggalDari ?? DateTime.now())
        : (_tanggalSampai ?? _tanggalDari ?? DateTime.now());

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date == null) return;

    setState(() {
      if (isDari) {
        _tanggalDari = date;
        if (_tanggalSampai != null && _tanggalSampai!.isBefore(date)) {
          _tanggalSampai = date;
        }
      } else {
        _tanggalSampai = date;
      }
      _tanggalError = null;
    });
  }

  void _onApply() {
    if (_tanggalDari != null &&
        _tanggalSampai != null &&
        _tanggalDari!.isAfter(_tanggalSampai!)) {
      setState(() =>
          _tanggalError = 'Tanggal awal tidak boleh melebihi tanggal akhir');
      return;
    }
    widget.onApply(
        _tanggalDari, _tanggalSampai, _jenisOrder, _metodePembayaran);
    Navigator.pop(context);
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
              const Text('Filter',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                  label: Text(_tanggalDari != null
                      ? DateFormat('dd/MM/yyyy').format(_tanggalDari!)
                      : 'Dari'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _selectDate(false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_tanggalSampai != null
                      ? DateFormat('dd/MM/yyyy').format(_tanggalSampai!)
                      : 'Sampai'),
                ),
              ),
            ],
          ),
          if (_tanggalError != null) ...[
            const SizedBox(height: 6),
            Text(_tanggalError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
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
                onSelected: (_) => setState(() => _jenisOrder = null),
              ),
              FilterChip(
                label: const Text('Dine In'),
                selected: _jenisOrder == 1,
                onSelected: (_) => setState(() => _jenisOrder = 1),
              ),
              FilterChip(
                label: const Text('Take Away'),
                selected: _jenisOrder == 2,
                onSelected: (_) => setState(() => _jenisOrder = 2),
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
                onSelected: (_) => setState(() => _metodePembayaran = null),
              ),
              FilterChip(
                label: const Text('Cash'),
                selected: _metodePembayaran == 1,
                onSelected: (_) => setState(() => _metodePembayaran = 1),
              ),
              FilterChip(
                label: const Text('Transfer'),
                selected: _metodePembayaran == 2,
                onSelected: (_) => setState(() => _metodePembayaran = 2),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a315b),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
