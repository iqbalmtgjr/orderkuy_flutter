import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/history.dart';

class InvoiceShareDialog extends StatefulWidget {
  final History order;
  final String tokoNama;
  final String tokoAlamat;

  const InvoiceShareDialog({
    super.key,
    required this.order,
    required this.tokoNama,
    required this.tokoAlamat,
  });

  @override
  State<InvoiceShareDialog> createState() => _InvoiceShareDialogState();
}

class _InvoiceShareDialogState extends State<InvoiceShareDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _isSharing = false;

  Future<void> _shareAsImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      // Beri waktu frame untuk render penuh sebelum capture
      await Future.delayed(const Duration(milliseconds: 80));

      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget belum siap');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Gagal mengkonversi gambar');

      final tempDir = await getTemporaryDirectory();
      final safeName =
          widget.order.kodeOrder.replaceAll(RegExp(r'[^\w-]'), '_');
      final file = File('${tempDir.path}/invoice_$safeName.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Invoice #${widget.order.kodeOrder}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal berbagi invoice: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Invoice card (scrollable jika layar kecil)
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _repaintKey,
                child: _InvoiceCard(
                  order: widget.order,
                  tokoNama: widget.tokoNama,
                  tokoAlamat: widget.tokoAlamat,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tombol bawah
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Tutup',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isSharing ? null : _shareAsImage,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    _isSharing ? 'Menyiapkan...' : 'Bagikan / Simpan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a315b),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF1a315b).withValues(alpha: 0.6),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice Card — desain sesuai screenshot
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  final History order;
  final String tokoNama;
  final String tokoAlamat;

  const _InvoiceCard({
    required this.order,
    required this.tokoNama,
    required this.tokoAlamat,
  });

  String _fmt(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  int get _totalItem => order.items.fold(0, (s, i) => s + i.qty);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildInfoBar(),
          _buildItemsTable(),
          _buildTotals(),
          if (order.catatan != null && order.catatan!.isNotEmpty)
            _buildCatatan(),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Header biru ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a315b), Color(0xFF2a4b8a)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nama & alamat toko
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tokoNama.isNotEmpty ? tokoNama : 'Kasvo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                if (tokoAlamat.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    tokoAlamat,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Nomor & tanggal invoice
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'INVOICE',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 9,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '#${order.kodeOrder}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                order.tanggalDisplay,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bar info: jenis order, metode, status ─────────────────────────────────

  Widget _buildInfoBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _infoCell('JENIS ORDER', order.jenisOrderText),
            VerticalDivider(
                width: 1, thickness: 1, color: Colors.grey.shade200),
            _infoCell('METODE BAYAR', order.metodePembayaranText),
            VerticalDivider(
                width: 1, thickness: 1, color: Colors.grey.shade200),
            _infoCell('STATUS', order.statusText,
                valueColor: Colors.green.shade600),
          ],
        ),
      ),
    );
  }

  Widget _infoCell(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tabel item ────────────────────────────────────────────────────────────

  Widget _buildItemsTable() {
    return Column(
      children: [
        // Header tabel
        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                  width: 20,
                  child: Text('#', style: _thStyle(), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              Expanded(child: Text('MENU', style: _thStyle())),
              SizedBox(
                  width: 65,
                  child: Text('HARGA', style: _thStyle(), textAlign: TextAlign.right)),
              SizedBox(
                  width: 30,
                  child: Text('QTY', style: _thStyle(), textAlign: TextAlign.center)),
              SizedBox(
                  width: 68,
                  child: Text('SUBTOTAL', style: _thStyle(), textAlign: TextAlign.right)),
            ],
          ),
        ),
        // Baris item
        ...order.items.asMap().entries.map(
              (e) => _buildItemRow(e.key + 1, e.value),
            ),
      ],
    );
  }

  TextStyle _thStyle() => TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 0.4,
      );

  Widget _buildItemRow(int idx, OrderItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$idx',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.menuNama,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1a315b),
                  ),
                ),
                if (item.opsi != null && item.opsi!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: item.opsi!
                        .split(', ')
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 0.5),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey.shade600),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              _fmt(item.harga),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${item.qty}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 68,
            child: Text(
              _fmt(item.subtotal),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Total ─────────────────────────────────────────────────────────────────

  Widget _buildTotals() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('TotalItem',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 18),
              Text('$_totalItem pcs',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Total Bayar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 18),
              Text(
                _fmt(order.totalHarga),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Catatan ───────────────────────────────────────────────────────────────

  Widget _buildCatatan() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATATAN',
            style: TextStyle(
              fontSize: 8,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            order.catatan!,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final printDate =
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final nama = tokoNama.isNotEmpty ? tokoNama : 'kami';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Terima kasih telah berbelanja di $nama.',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Dicetak: $printDate',
            style:
                TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
