// ============================================================
// widgets/option_picker_dialog.dart
// Dialog pilih opsi/varian saat user tap menu
// ============================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';

class OptionPickerDialog extends StatefulWidget {
  final Product product;
  final int initialQty;

  const OptionPickerDialog({
    super.key,
    required this.product,
    this.initialQty = 1,
  });

  /// Tampilkan dialog dan kembalikan hasil pilihan.
  /// Return null jika user batal.
  /// Return Map berisi qty, selectedOptions, totalHarga jika konfirmasi.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Product product,
    int initialQty = 1,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OptionPickerDialog(
        product: product,
        initialQty: initialQty,
      ),
    );
  }

  @override
  State<OptionPickerDialog> createState() => _OptionPickerDialogState();
}

class _OptionPickerDialogState extends State<OptionPickerDialog> {
  static const Color _primary = Color(0xFF1a315b);
  static const Color _primaryLight = Color(0xFF2a4a7f);

  static final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  int _qty = 1;

  // Untuk tipe 'single': groupId → optionItemId yang dipilih
  final Map<int, int?> _singleSelections = {};

  // Untuk tipe 'multiple': groupId → Set of optionItemId yang dipilih
  final Map<int, Set<int>> _multipleSelections = {};

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty;

    for (final group in widget.product.optionGroups) {
      if (group.isSingle) {
        // Pilih item pertama secara default jika required
        _singleSelections[group.id] = group.isRequired && group.items.isNotEmpty
            ? group.items.first.id
            : null;
      } else {
        _multipleSelections[group.id] = {};
      }
    }
  }

  // Hitung total harga tambahan dari semua opsi yang dipilih
  int get _totalHargaOpsi {
    int total = 0;

    for (final group in widget.product.optionGroups) {
      if (group.isSingle) {
        final selectedId = _singleSelections[group.id];
        if (selectedId != null) {
          final item = group.items.firstWhere(
            (i) => i.id == selectedId,
            orElse: () => const OptionItem(id: 0, nama: '', hargaTambahan: 0),
          );
          total += item.hargaTambahan;
        }
      } else {
        final selectedIds = _multipleSelections[group.id] ?? {};
        for (final itemId in selectedIds) {
          final item = group.items.firstWhere(
            (i) => i.id == itemId,
            orElse: () => const OptionItem(id: 0, nama: '', hargaTambahan: 0),
          );
          total += item.hargaTambahan;
        }
      }
    }

    return total;
  }

  double get _hargaPerItem => widget.product.harga + _totalHargaOpsi;
  double get _totalHarga => _hargaPerItem * _qty;

  // Validasi: semua required group sudah dipilih?
  bool get _isValid {
    for (final group in widget.product.optionGroups) {
      if (!group.isRequired) continue;

      if (group.isSingle) {
        if (_singleSelections[group.id] == null) return false;
      } else {
        final selected = _multipleSelections[group.id] ?? {};
        if (selected.length < group.minPilih) return false;
      }
    }
    return true;
  }

  // Kumpulkan semua option_item_ids yang dipilih
  List<int> get _selectedOptionItemIds {
    final ids = <int>[];

    for (final group in widget.product.optionGroups) {
      if (group.isSingle) {
        final selectedId = _singleSelections[group.id];
        if (selectedId != null) ids.add(selectedId);
      } else {
        ids.addAll(_multipleSelections[group.id] ?? {});
      }
    }

    return ids;
  }

  void _confirm() {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap lengkapi pilihan yang wajib dipilih'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'qty': _qty,
      'option_item_ids': _selectedOptionItemIds,
      'harga_per_item': _hargaPerItem,
      'total_harga': _totalHarga,
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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

            // Header
            _buildHeader(),

            // Body — daftar option groups
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  ...widget.product.optionGroups.map(_buildOptionGroup),
                  const SizedBox(height: 16),
                  _buildQtySelector(),
                ],
              ),
            ),

            // Footer — total + tombol tambahkan
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0f2040), _primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.namaProduk,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currency.format(widget.product.harga),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Pilih Opsi',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionGroup(OptionGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                group.nama,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (group.isRequired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'Wajib',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Opsional',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
        if (group.isMultiple && group.maxPilih > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Pilih hingga ${group.maxPilih} item',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        const SizedBox(height: 8),
        ...group.items.map((item) => group.isSingle
            ? _buildSingleItem(group, item)
            : _buildMultipleItem(group, item)),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildSingleItem(OptionGroup group, OptionItem item) {
    final isSelected = _singleSelections[group.id] == item.id;

    return InkWell(
      onTap: () => setState(() => _singleSelections[group.id] = item.id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFe8eef5) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _primary : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _primary : Colors.grey.shade400,
                  width: 2,
                ),
                color: isSelected ? _primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.nama,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? _primary : Colors.black87,
                ),
              ),
            ),
            if (item.hargaTambahan > 0)
              Text(
                '+${_currency.format(item.hargaTambahan)}',
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? _primary : Colors.grey.shade600,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              )
            else
              Text(
                'Gratis',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleItem(OptionGroup group, OptionItem item) {
    final selected = _multipleSelections[group.id] ?? {};
    final isSelected = selected.contains(item.id);
    final reachedMax = !isSelected && selected.length >= group.maxPilih;

    return InkWell(
      onTap: reachedMax
          ? null
          : () {
              setState(() {
                final set = _multipleSelections[group.id] ??= {};
                if (isSelected) {
                  set.remove(item.id);
                } else {
                  set.add(item.id);
                }
              });
            },
      borderRadius: BorderRadius.circular(10),
      child: Opacity(
        opacity: reachedMax ? 0.45 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFe8eef5) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _primary : Colors.grey.shade200,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isSelected ? _primary : Colors.grey.shade400,
                    width: 2,
                  ),
                  color: isSelected ? _primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.nama,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? _primary : Colors.black87,
                  ),
                ),
              ),
              if (item.hargaTambahan > 0)
                Text(
                  '+${_currency.format(item.hargaTambahan)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? _primary : Colors.grey.shade600,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                )
              else
                Text(
                  'Gratis',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQtySelector() {
    return Row(
      children: [
        const Text(
          'Jumlah',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        _qtyBtn(Icons.remove, () {
          if (_qty > 1) setState(() => _qty--);
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '$_qty',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        _qtyBtn(Icons.add, () => setState(() => _qty++)),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 18, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              Text(
                _currency.format(_totalHarga),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
              if (_totalHargaOpsi > 0)
                Text(
                  '+${_currency.format(_totalHargaOpsi)} opsi',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isValid ? _confirm : null,
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text(
                'Tambahkan ke Pesanan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
