import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/sync_service.dart';
import '../models/order.dart';
import '../utils/constants.dart';
import 'kasir_screen.dart';
import '../widgets/sync_status_widget.dart';

class PesananScreen extends StatefulWidget {
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _filterJenisOrder;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final orders = await ApiService.getOrders(
      filterJenisOrder: _filterJenisOrder,
    );
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _isLoading = false;
    });
  }

  Future<void> _refreshOrders() async {
    await SyncService.syncOrders();
    await _loadOrders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil diperbarui'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _selesaikanPesanan(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Yakin pesanan ini selesai?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Batal', style: TextStyle(color: Color(0xFFD32F2F))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ya, Selesai'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await ApiService.completeOrder(orderId);

      if (!mounted) return;
      Navigator.pop(context);

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesanan berhasil diselesaikan'),
            backgroundColor: Colors.green,
          ),
        );
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal menyelesaikan pesanan'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printReceipt(Order order) async {
    try {
      final kasirPrinter = await ThermalPrintService.getSavedPrinter(
        role: PrinterRole.kasir,
      );

      if (kasirPrinter == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Printer belum dipilih. Silakan pilih printer di menu Setup Printer.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final items = order.items
          .map((item) => {
                'menu_id': item.menuId,
                'nama_produk': item.menuNama,
                'harga': item.harga,
                'qty': item.qty,
              })
          .toList();

      if (!mounted) return;

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
                'Mencetak struk & nota dapur...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );

      final results = await ThermalPrintService.printAll(
        orderId: order.id.toString(),
        tokoNama: order.tokoNama ?? 'OrderKuy',
        tokoAlamat: order.tokoAlamat ?? '',
        items: items,
        totalHarga: order.totalHarga,
        jenisOrder: order.jenisOrder,
        mejaNo: order.jenisOrder == Constants.jenisOrderDineIn
            ? order.mejaNo
            : null,
        catatan: order.catatan,
        metodeBayar: order.metodeBayar,
        kasirNama: order.kasirNama,
      );

      if (!mounted) return;
      Navigator.pop(context);

      final kasirOk = results[0];
      final dapurOk = results[1];

      String msg;
      Color bgColor;

      if (kasirOk && dapurOk) {
        msg = 'Struk kasir & nota dapur berhasil dicetak';
        bgColor = Colors.green;
      } else if (kasirOk && !dapurOk) {
        msg = 'Struk kasir OK, printer dapur gagal';
        bgColor = Colors.orange;
      } else if (!kasirOk && dapurOk) {
        msg = 'Nota dapur OK, printer kasir gagal';
        bgColor = Colors.orange;
      } else {
        msg = 'Gagal mencetak. Pastikan printer aktif dan coba lagi.';
        bgColor = Colors.red;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route is! DialogRoute);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error print: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Filter Jenis Pesanan',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterTile('Semua', null),
            _filterTile('Dine In', '1'),
            _filterTile('Take Away', '2'),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(String label, String? value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      leading: Radio<String?>(
        value: value,
        groupValue: _filterJenisOrder,
        activeColor: const Color(0xFFD32F2F),
        onChanged: (v) {
          setState(() => _filterJenisOrder = v);
          Navigator.pop(context);
          _loadOrders();
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    // Tablet: 2 kolom, mobile: 1 kolom (list)
    final isTablet = sw > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          const SyncStatusWidget(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFD32F2F)))
                : _orders.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: const Color(0xFFD32F2F),
                        onRefresh: _refreshOrders,
                        child:
                            isTablet ? _buildTabletGrid() : _buildMobileList(),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const KasirScreen()),
          ).then((_) => _loadOrders());
        },
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Pesanan',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Kembali ke Dashboard',
      ),
      title: const Text(
        'Data Pesanan',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      elevation: 4,
      actions: [
        IconButton(
          icon: const Icon(Icons.sync, color: Colors.white),
          onPressed: _refreshOrders,
          tooltip: 'Refresh & Sync',
        ),
        IconButton(
          icon: const Icon(Icons.filter_list, color: Colors.white),
          onPressed: _showFilterDialog,
          tooltip: 'Filter',
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // MOBILE: ListView — tidak ada overflow
  // ─────────────────────────────────────────────
  Widget _buildMobileList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
    );
  }

  // ─────────────────────────────────────────────
  // TABLET: 2-kolom grid, pakai crossAxisExtent
  // ─────────────────────────────────────────────
  Widget _buildTabletGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        // Tidak pakai childAspectRatio — gunakan mainAxisExtent tetap
        mainAxisExtent: 220,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _orders.length,
      itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
    );
  }

  // ─────────────────────────────────────────────
  // ORDER CARD — tinggi mengikuti konten (tidak pakai Expanded)
  // ─────────────────────────────────────────────
  Widget _buildOrderCard(Order order) {
    final isDineIn = order.jenisOrder == 1;
    final hasCatatan = order.catatan != null && order.catatan!.isNotEmpty;

    return GestureDetector(
      onTap: () => _showOrderDetails(order),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ← ikuti konten
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header merah ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isDineIn ? Icons.restaurant : Icons.shopping_bag,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDineIn ? 'Meja ${order.mejaNo ?? "-"}' : 'Take Away',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Badge PENDING
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item count + Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 15, color: Colors.red.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${order.items.length} item${order.items.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatRupiah(order.totalHarga),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),

                  // Catatan (opsional)
                  if (hasCatatan) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: 14, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.catatan!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Tombol aksi
                  Row(
                    children: [
                      // Edit
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: order.id == 0
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          KasirScreen(orderToEdit: order),
                                    ),
                                  ).then((_) => _loadOrders());
                                },
                          icon: Icon(Icons.edit_outlined,
                              size: 16, color: Colors.orange.shade700),
                          label: Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            side: BorderSide(color: Colors.orange.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Selesai
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              order.id == 0 // ← order offline, disable tombol
                                  ? null
                                  : () => _selesaikanPesanan(order.id),
                          icon:
                              const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text(
                            'Selesai',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_outlined,
                  size: 52, color: Colors.red.shade300),
            ),
            const SizedBox(height: 24),
            Text(
              'Belum Ada Pesanan',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pesanan yang dibuat hari ini\nakan muncul di sini',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DETAIL BOTTOM SHEET
  // ─────────────────────────────────────────────
  void _showOrderDetails(Order order) {
    final isDineIn = order.jenisOrder == 1;
    final hasCatatan = order.catatan != null && order.catatan!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDineIn ? Icons.restaurant : Icons.shopping_bag,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isDineIn ? 'Meja ${order.mejaNo ?? "-"}' : 'Take Away',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Detail Pesanan',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // Items
                    ...order.items.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.red.shade100,
                              child: Text(
                                '${item.qty}x',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.menuNama,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  Text(
                                    _formatRupiah(item.harga),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatRupiah(item.subtotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(height: 28),

                    // Catatan
                    if (hasCatatan) ...[
                      Row(
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: 18, color: Colors.orange.shade600),
                          const SizedBox(width: 8),
                          const Text('Catatan:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Text(order.catatan!,
                            style: const TextStyle(
                                fontStyle: FontStyle.italic, fontSize: 14)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            _formatRupiah(order.totalHarga),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Tombol aksi
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                order.id == 0 // ← order offline, disable tombol
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                KasirScreen(orderToEdit: order),
                                          ),
                                        ).then((_) => _loadOrders());
                                      },
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade700,
                              side: BorderSide(color: Colors.orange.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                order.id == 0 // ← order offline, disable tombol
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _printReceipt(order);
                                      },
                            icon: const Icon(Icons.print_outlined, size: 16),
                            label: const Text('Print'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                              side: BorderSide(color: Colors.blue.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                order.id == 0 // ← order offline, disable tombol
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _selesaikanPesanan(order.id);
                                      },
                            icon: const Icon(Icons.check_circle_outline,
                                size: 16),
                            label: const Text('Selesai'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp ${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    )}';
  }
}
