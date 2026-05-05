import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/sync_service.dart';
import '../models/order.dart';
import '../utils/constants.dart';
import 'kasir_screen.dart';
import '../widgets/sync_status_widget.dart';

// ── Breakpoint helpers ────────────────────────────────────────
// small  : sw < 360  (HP kecil / lama)
// medium : 360 ≤ sw < 600  (HP normal)
// tablet : sw ≥ 600
extension _ScreenSize on double {
  bool get isSmall => this < 360;
  bool get isMedium => this >= 360 && this < 600;
  bool get isTablet => this >= 600;
}

class PesananScreen extends StatefulWidget {
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _filterJenisOrder;

  static const Color _primaryColor = Color(0xFF1a315b);
  static const Color _primaryDark = Color(0xFF0f2442);
  static const Color _primarySurface = Color(0xFFe8eef5);

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
            child: const Text('Batal', style: TextStyle(color: _primaryColor)),
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
            backgroundColor: _primaryColor,
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
                'harga': item.harga + item.totalHargaOpsi.toDouble(),
                'qty': item.qty,
                if (item.opsiDipilih.isNotEmpty) 'opsi': item.opsiLabel,
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
        bgColor = _primaryColor;
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
          backgroundColor: _primaryColor,
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
        activeColor: _primaryColor,
        onChanged: (v) {
          setState(() => _filterJenisOrder = v);
          Navigator.pop(context);
          _loadOrders();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          const SyncStatusWidget(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryColor))
                : _orders.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: _primaryColor,
                        onRefresh: _refreshOrders,
                        child: sw.isTablet
                            ? _buildTabletGrid(sw)
                            : _buildMobileList(sw),
                      ),
          ),
        ],
      ),
      // ── FAB responsif: ikon saja di layar kecil ──────────────
      floatingActionButton: sw.isSmall
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const KasirScreen()),
                ).then((_) => _loadOrders());
              },
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 6,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const KasirScreen()),
                ).then((_) => _loadOrders());
              },
              backgroundColor: _primaryColor,
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
            colors: [_primaryColor, _primaryDark],
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

  // ── Adaptive padding helper ───────────────────────────────────
  EdgeInsets _listPadding(double sw) {
    if (sw.isSmall) return const EdgeInsets.fromLTRB(10, 12, 10, 96);
    if (sw.isTablet) return const EdgeInsets.fromLTRB(20, 16, 20, 100);
    return const EdgeInsets.fromLTRB(14, 16, 14, 100);
  }

  Widget _buildMobileList(double sw) {
    return ListView.separated(
      padding: _listPadding(sw),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => SizedBox(height: sw.isSmall ? 8 : 12),
      itemBuilder: (context, index) => _buildOrderCard(_orders[index], sw),
    );
  }

  // ── Tablet grid: lebar kolom & tinggi dinamis ────────────────
  Widget _buildTabletGrid(double sw) {
    // Lebar maks kolom naik seiring lebar layar
    final maxExtent = sw > 900 ? 420.0 : 380.0;
    return GridView.builder(
      padding: _listPadding(sw),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        // Biarkan Flutter menghitung tinggi dari konten
        // (gunakan childAspectRatio agar tidak clip)
        childAspectRatio: 0.82,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _orders.length,
      itemBuilder: (context, index) => _buildOrderCard(_orders[index], sw),
    );
  }

  // ── Order card utama ─────────────────────────────────────────
  Widget _buildOrderCard(Order order, double sw) {
    final isDineIn = order.jenisOrder == 1;
    final hasCatatan = order.catatan != null && order.catatan!.isNotEmpty;
    final itemPreview = order.items.take(2).toList();
    final moreCount = order.items.length - itemPreview.length;

    // Font scale
    final double titleFs = sw.isSmall ? 12.5 : 14.0;
    final double bodyFs = sw.isSmall ? 11.5 : 13.0;
    final double totalFs = sw.isSmall ? 14.0 : 15.0;
    final double btnFs = sw.isSmall ? 11.5 : 13.0;
    final EdgeInsets hPad = sw.isSmall
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 11);
    final EdgeInsets bPad = sw.isSmall
        ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
        : const EdgeInsets.fromLTRB(14, 10, 14, 12);

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────
            Container(
              padding: hPad,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryDark, _primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isDineIn ? Icons.restaurant : Icons.shopping_bag,
                    color: Colors.white,
                    size: sw.isSmall ? 15 : 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isDineIn ? 'Meja ${order.mejaNo ?? "-"}' : 'Take Away',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFs,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PENDING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: sw.isSmall ? 9 : 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────
            Padding(
              padding: bPad,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...itemPreview
                      .map((item) => _buildItemPreviewRow(item, bodyFs)),
                  if (moreCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+$moreCount item lainnya — tap untuk lihat semua',
                        style: TextStyle(
                          fontSize: sw.isSmall ? 10 : 11,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

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
                              size: 13, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.catatan!,
                              style: TextStyle(
                                fontSize: bodyFs - 1,
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Total + jumlah item
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _formatRupiah(order.totalHarga),
                          style: TextStyle(
                            fontSize: totalFs,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${order.items.length} item',
                        style: TextStyle(
                          fontSize: bodyFs - 1,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Tombol aksi ─────────────────────────────
                  // Gunakan LayoutBuilder agar tombol tidak overflow
                  // di layar sangat sempit
                  LayoutBuilder(builder: (context, constraints) {
                    final tightWidth = constraints.maxWidth < 280;
                    if (tightWidth) {
                      // Layar sangat sempit → tumpuk vertikal
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _editButton(order, btnFs),
                          const SizedBox(height: 6),
                          _selesaiButton(order, btnFs),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _editButton(order, btnFs)),
                        const SizedBox(width: 8),
                        Expanded(child: _selesaiButton(order, btnFs)),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tombol Edit & Selesai sebagai helper ──────────────────────
  Widget _editButton(Order order, double fontSize) {
    return OutlinedButton.icon(
      onPressed: order.id == 0
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => KasirScreen(orderToEdit: order),
                ),
              ).then((_) => _loadOrders());
            },
      icon: Icon(Icons.edit_outlined, size: 15, color: Colors.orange.shade700),
      label: Text(
        'Edit',
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.orange.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 9),
        side: BorderSide(color: Colors.orange.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _selesaiButton(Order order, double fontSize) {
    return ElevatedButton.icon(
      onPressed: order.id == 0 ? null : () => _selesaikanPesanan(order.id),
      icon: const Icon(Icons.check_circle_outline, size: 15),
      label: Text(
        'Selesai',
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Preview item di card ──────────────────────────────────────
  Widget _buildItemPreviewRow(OrderItem item, double bodyFs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _primarySurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${item.qty}x',
              style: TextStyle(
                fontSize: bodyFs - 2,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.menuNama,
                  style:
                      TextStyle(fontSize: bodyFs, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.opsiDipilih.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: item.opsiDipilih
                        .map((opsi) => Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _primarySurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _primaryColor.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                opsi.namaItem,
                                style: TextStyle(
                                  fontSize: bodyFs - 3,
                                  color: _primaryColor,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatRupiah(item.subtotal),
            style: TextStyle(
              fontSize: bodyFs,
              color: _primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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
              decoration: const BoxDecoration(
                color: Color(0xFFe8eef5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_outlined,
                  size: 52, color: _primaryColor),
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

  // ── Bottom sheet detail pesanan ───────────────────────────────
  void _showOrderDetails(Order order) {
    final isDineIn = order.jenisOrder == 1;
    final hasCatatan = order.catatan != null && order.catatan!.isNotEmpty;
    final sh = MediaQuery.of(context).size.height;
    final sw = MediaQuery.of(context).size.width;

    // Bottom sheet lebih tinggi di tablet / layar besar
    final double initSize = sh > 700 ? 0.72 : 0.65;
    final double maxSize = sw.isTablet ? 0.85 : 0.92;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initSize,
        minChildSize: 0.4,
        maxChildSize: maxSize,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Header ──────────────────────────────────────
              Container(
                margin: EdgeInsets.fromLTRB(
                    sw.isSmall ? 10 : 16, 8, sw.isSmall ? 10 : 16, 0),
                padding: EdgeInsets.symmetric(
                  horizontal: sw.isSmall ? 12 : 16,
                  vertical: sw.isSmall ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryDark, _primaryColor],
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
                      size: sw.isSmall ? 17 : 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDineIn
                                ? 'Meja ${order.mejaNo ?? "-"}'
                                : 'Take Away',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: sw.isSmall ? 15 : 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${order.jenisOrderText} · ${order.metodeBayarText}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: sw.isSmall ? 11 : 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'PENDING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: sw.isSmall ? 10 : 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Body scrollable ──────────────────────────────
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(sw.isSmall ? 12 : 16),
                  children: [
                    const Text(
                      'Detail Pesanan',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    ...order.items
                        .map((item) => _buildDetailItemCard(item, sw)),

                    const Divider(height: 28),

                    if (hasCatatan) ...[
                      Row(
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: 17, color: Colors.orange.shade600),
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
                          Flexible(
                            child: Text(
                              _formatRupiah(order.totalHarga),
                              style: TextStyle(
                                fontSize: sw.isSmall ? 18 : 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Tombol aksi bottom sheet ─────────────────
                    // Pada layar sempit, susun 2+1 supaya tidak clipper
                    sw.isSmall
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: _bsEditButton(order, context)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: _bsPrintButton(order, context)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _bsSelesaiButton(order, context),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _bsEditButton(order, context)),
                              const SizedBox(width: 8),
                              Expanded(child: _bsPrintButton(order, context)),
                              const SizedBox(width: 8),
                              Expanded(child: _bsSelesaiButton(order, context)),
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

  // ── Helper tombol bottom sheet ────────────────────────────────
  Widget _bsEditButton(Order order, BuildContext sheetCtx) {
    return OutlinedButton.icon(
      onPressed: order.id == 0
          ? null
          : () {
              Navigator.pop(sheetCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => KasirScreen(orderToEdit: order)),
              ).then((_) => _loadOrders());
            },
      icon: const Icon(Icons.edit_outlined, size: 15),
      label: const Text('Edit'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange.shade700,
        side: BorderSide(color: Colors.orange.shade300),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _bsPrintButton(Order order, BuildContext sheetCtx) {
    return OutlinedButton.icon(
      onPressed: order.id == 0
          ? null
          : () {
              Navigator.pop(sheetCtx);
              _printReceipt(order);
            },
      icon: const Icon(Icons.print_outlined, size: 15),
      label: const Text('Print'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue.shade700,
        side: BorderSide(color: Colors.blue.shade300),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _bsSelesaiButton(Order order, BuildContext sheetCtx) {
    return ElevatedButton.icon(
      onPressed: order.id == 0
          ? null
          : () {
              Navigator.pop(sheetCtx);
              _selesaikanPesanan(order.id);
            },
      icon: const Icon(Icons.check_circle_outline, size: 15),
      label: const Text('Selesai'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Card detail item di bottom sheet ─────────────────────────
  Widget _buildDetailItemCard(OrderItem item, double sw) {
    final hasOpsi = item.opsiDipilih.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                sw.isSmall ? 10 : 12, 10, sw.isSmall ? 10 : 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: sw.isSmall ? 15 : 18,
                  backgroundColor: _primarySurface,
                  child: Text(
                    '${item.qty}x',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: sw.isSmall ? 10 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.menuNama,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: sw.isSmall ? 12.5 : 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatRupiah(item.harga)} × ${item.qty}',
                        style: TextStyle(
                            fontSize: sw.isSmall ? 11 : 12,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatRupiah(item.subtotal),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: sw.isSmall ? 13 : 15),
                    ),
                    if (item.totalHargaOpsi > 0)
                      Text(
                        '+${_formatRupiah(item.totalHargaOpsi.toDouble())} opsi',
                        style: TextStyle(
                          fontSize: sw.isSmall ? 9 : 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (hasOpsi) ...[
            Container(
              margin: EdgeInsets.fromLTRB(
                  sw.isSmall ? 10 : 12, 0, sw.isSmall ? 10 : 12, 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFe8eef5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, size: 13, color: _primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'Pilihan:',
                        style: TextStyle(
                          fontSize: sw.isSmall ? 10 : 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...item.opsiDipilih.map((opsi) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(right: 8, top: 2),
                              decoration: const BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${opsi.namaGroup}: ${opsi.namaItem}',
                                style: TextStyle(
                                    fontSize: sw.isSmall ? 11 : 12,
                                    color: _primaryColor),
                              ),
                            ),
                            if (opsi.hargaTambahan > 0)
                              Text(
                                '+${_formatRupiah(opsi.hargaTambahan.toDouble())}',
                                style: TextStyle(
                                  fontSize: sw.isSmall ? 10 : 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp ${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    )}';
  }
}
