import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentConfirmationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedItems;
  final double totalHarga;
  final List<Map<String, dynamic>> paymentMethods;
  final Map<String, dynamic>? initialPaymentMethod;
  final bool isOnline;

  const PaymentConfirmationScreen({
    super.key,
    required this.selectedItems,
    required this.totalHarga,
    required this.paymentMethods,
    this.initialPaymentMethod,
    required this.isOnline,
  });

  @override
  State<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> {
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

  late Map<String, dynamic>? _selectedPaymentMethod;
  String _nominalDigits = '';

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

  String get _formattedNominal {
    if (_nominalDigits.isEmpty) return 'Rp 0';
    final value = int.tryParse(_nominalDigits) ?? 0;
    final formatted = value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    return 'Rp $formatted';
  }

  double get _nominalBayar => double.tryParse(_nominalDigits) ?? 0;
  double get _kembalian => _nominalBayar - widget.totalHarga;

  @override
  void initState() {
    super.initState();
    _selectedPaymentMethod = widget.initialPaymentMethod;
  }

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

  void _addDigit(String digit) {
    if (_nominalDigits.length >= 12) return;
    setState(() => _nominalDigits += digit);
  }

  void _removeDigit() {
    if (_nominalDigits.isEmpty) return;
    setState(() => _nominalDigits =
        _nominalDigits.substring(0, _nominalDigits.length - 1));
  }

  void _clearNominal() => setState(() => _nominalDigits = '');

  void _setExactAmount() =>
      setState(() => _nominalDigits = widget.totalHarga.toInt().toString());

  void _confirm() {
    if (_isCash && _kembalian < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nominal bayar kurang dari total'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'payment_method': _selectedPaymentMethod,
      'nominal_bayar': _isCash ? _nominalBayar : widget.totalHarga,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Batal',
        ),
        title: const Text(
          'Konfirmasi Pembayaran',
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
        elevation: 10,
        shadowColor: _primaryColor.withValues(alpha: 0.5),
      ),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  // ── Layout ──────────────────────────────────────────────────────

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                if (!widget.isOnline) _buildOfflineBanner(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildOrderSummary(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primarySurface, Color(0xFFdce6f2)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPaymentMethodSelector(),
                        const SizedBox(height: 20),
                        if (_isCash) ...[
                          _buildNominalDisplay(),
                          const SizedBox(height: 16),
                          _buildKeypad(),
                          const SizedBox(height: 16),
                          _buildKembalianCard(),
                        ] else
                          _buildNonCashCard(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: _buildConfirmButton(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.isOnline) _buildOfflineBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildOrderSummary(),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPaymentMethodSelector(),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isCash
                      ? Column(
                          key: const ValueKey('cash'),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildNominalDisplay(),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildKeypad(),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildKembalianCard(),
                            ),
                          ],
                        )
                      : Padding(
                          key: const ValueKey('noncash'),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildNonCashCard(),
                        ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  // ── Sections ─────────────────────────────────────────────────────

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode Offline — Pesanan akan tersimpan lokal',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: _primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Ringkasan Pesanan',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _primaryDark),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Item list
        ...widget.selectedItems.map((item) {
          final subtotal = (item['qty'] as int) * (item['harga'] as double);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: _primarySurfaceDeep.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${item['qty']}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['nama_produk'],
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item['opsi'] != null &&
                          (item['opsi'] as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: (item['opsi'] as String)
                              .split(', ')
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _primarySurface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: _primarySurfaceDeep,
                                        width: 1),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: _primaryColor,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        '@${_currencyFormat.format(item['harga'])}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Text(
                  _currencyFormat.format(subtotal),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),

        // Total card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primaryColor, _primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Pembayaran',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                _currencyFormat.format(widget.totalHarga),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.payment_rounded,
                  color: _primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Metode Pembayaran',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _primaryDark),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.paymentMethods.map((method) {
            final isSelected = _selectedPaymentMethod?['id'] == method['id'] &&
                _selectedPaymentMethod?['kode'] == method['kode'];
            return GestureDetector(
              onTap: () => setState(() => _selectedPaymentMethod = method),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _primaryColor : _primarySurfaceDeep,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? _primaryColor.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: isSelected ? 10 : 4,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPaymentIcon(method['kode'] ?? ''),
                      size: 20,
                      color: isSelected ? Colors.white : _primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      method['nama'] ?? '-',
                      style: TextStyle(
                        fontSize: 14,
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

  Widget _buildNominalDisplay() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nominal Bayar',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500),
              ),
              GestureDetector(
                onTap: _setExactAmount,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primarySurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _primarySurfaceDeep),
                  ),
                  child: const Text(
                    'Uang Pas',
                    style: TextStyle(
                        fontSize: 12,
                        color: _primaryColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _primarySurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primarySurfaceDeep),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formattedNominal,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (_nominalDigits.isNotEmpty)
                  GestureDetector(
                    onTap: _clearNominal,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.clear,
                          color: Colors.grey.shade600, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _keyRow(['1', '2', '3']),
          const SizedBox(height: 10),
          _keyRow(['4', '5', '6']),
          const SizedBox(height: 10),
          _keyRow(['7', '8', '9']),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionKey('CLR', Icons.clear_all_rounded,
                    Colors.orange.shade600, _clearNominal),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _numKey('0')),
              const SizedBox(width: 10),
              Expanded(
                child: _actionKey('DEL', Icons.backspace_rounded, _primaryColor,
                    _removeDigit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> digits) {
    return Row(
      children: [
        for (int i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _numKey(digits[i])),
        ],
      ],
    );
  }

  Widget _numKey(String digit) {
    return Material(
      color: _primarySurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _addDigit(digit),
        borderRadius: BorderRadius.circular(12),
        splashColor: _primaryColor.withValues(alpha: 0.12),
        child: SizedBox(
          height: 60,
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.2),
        child: SizedBox(
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKembalianCard() {
    final isEnough = _kembalian >= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isEnough ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEnough ? Colors.green.shade300 : Colors.red.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEnough ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isEnough ? Colors.green.shade700 : Colors.red.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kembalian',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        isEnough ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                Text(
                  isEnough
                      ? _currencyFormat.format(_kembalian)
                      : '${_currencyFormat.format(_kembalian.abs())} (kurang)',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color:
                        isEnough ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNonCashCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _getPaymentIcon(_selectedPaymentMethod?['kode'] ?? ''),
                  color: Colors.blue.shade700,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembayaran via',
                      style:
                          TextStyle(fontSize: 12, color: Colors.blue.shade500),
                    ),
                    Text(
                      _selectedPaymentMethod?['nama'] ?? '-',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jumlah yang dibayar',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                ),
                Text(
                  _currencyFormat.format(widget.totalHarga),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    final canConfirm = !_isCash || _kembalian >= 0;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _confirm,
        icon: const Icon(Icons.check_circle_rounded, size: 22),
        label: const Text(
          'Bayar & Simpan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canConfirm ? _primaryColor : Colors.grey.shade300,
          foregroundColor: canConfirm ? Colors.white : Colors.grey.shade500,
          elevation: canConfirm ? 6 : 0,
          shadowColor: _primaryColor.withValues(alpha: 0.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Batal',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: _buildConfirmButton()),
        ],
      ),
    );
  }
}
