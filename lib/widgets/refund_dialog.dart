import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/refund_service.dart';

class RefundDialog extends StatefulWidget {
  final int orderId;
  final double totalOrder;
  final String nomorOrder;
  final int userId;

  const RefundDialog({
    super.key,
    required this.orderId,
    required this.totalOrder,
    required this.nomorOrder,
    required this.userId,
  });

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _jumlahCtrl = TextEditingController();
  final _alasanCtrl = TextEditingController();
  bool _isLoading = false;
  bool _refundPenuh = true; // toggle refund penuh vs custom

  @override
  void initState() {
    super.initState();
    _jumlahCtrl.text = widget.totalOrder.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _jumlahCtrl.dispose();
    _alasanCtrl.dispose();
    super.dispose();
  }

  String _metodeRefund = 'tunai';

  // ── Format angka ke Rupiah ──────────────────────────────────────────────────
  String _formatRupiah(double amount) {
    final parts = amount.toStringAsFixed(0).split('');
    final result = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) result.write('.');
      result.write(parts[i]);
    }
    return 'Rp ${result.toString()}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final jumlahRefund = int.tryParse(
          _jumlahCtrl.text.replaceAll(RegExp(r'[^\d]'), ''),
        ) ??
        0;

    setState(() => _isLoading = true);

    final result = await RefundService.createRefund(
      orderId: widget.orderId,
      userId: widget.userId,
      jumlahRefund: jumlahRefund,
      alasan: _alasanCtrl.text.trim(),
      metodeRefund: _metodeRefund,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pop(result['refund'] as RefundModel);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Gagal membuat refund.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.assignment_return_rounded,
                      color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Refund Order ${widget.nomorOrder}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Total order: ${_formatRupiah(widget.totalOrder)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const Divider(height: 24),

              // ── Toggle refund penuh / sebagian ─────────────
              Row(
                children: [
                  Expanded(
                    child: _ToggleChip(
                      label: 'Refund Penuh',
                      selected: _refundPenuh,
                      onTap: () {
                        setState(() {
                          _refundPenuh = true;
                          _jumlahCtrl.text =
                              widget.totalOrder.toStringAsFixed(0);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ToggleChip(
                      label: 'Sebagian',
                      selected: !_refundPenuh,
                      onTap: () {
                        setState(() {
                          _refundPenuh = false;
                          _jumlahCtrl.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Input jumlah ────────────────────────────────
              TextFormField(
                controller: _jumlahCtrl,
                enabled: !_refundPenuh,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Jumlah Refund (Rp)',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: _refundPenuh,
                  fillColor: _refundPenuh ? Colors.grey.shade100 : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  final val = double.tryParse(
                      v?.replaceAll(RegExp(r'[^\d]'), '') ?? '');
                  if (val == null || val <= 0) {
                    return 'Masukkan jumlah yang valid';
                  }
                  if (val > widget.totalOrder) {
                    return 'Melebihi total order';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _metodeRefund,
                decoration: InputDecoration(
                  labelText: 'Metode Refund',
                  prefixIcon: const Icon(Icons.swap_horiz_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'tunai', child: Text('Tunai')),
                  DropdownMenuItem(value: 'kredit', child: Text('Kredit')),
                  DropdownMenuItem(value: 'lainnya', child: Text('Lainnya')),
                ],
                onChanged: (v) => setState(() => _metodeRefund = v ?? 'tunai'),
              ),
              const SizedBox(height: 12),

              // ── Input alasan ────────────────────────────────
              TextFormField(
                controller: _alasanCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Alasan Refund',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.notes_rounded),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Alasan tidak boleh kosong';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),

              // ── Info status ─────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Refund akan menunggu persetujuan owner/admin.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Tombol aksi ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Ajukan Refund'),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget helper: toggle chip kecil
// ─────────────────────────────────────────────────────────────────────────────
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.orange.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
