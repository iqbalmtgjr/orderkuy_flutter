// ============================================================
// models/product.dart
// PERUBAHAN: tambah OptionGroup, OptionItem, field hasOptions
// ============================================================

// ── Model baru: OptionItem ───────────────────────────────────
class OptionItem {
  final int id;
  final String nama;
  final int hargaTambahan;

  const OptionItem({
    required this.id,
    required this.nama,
    required this.hargaTambahan,
  });

  factory OptionItem.fromJson(Map<String, dynamic> json) {
    return OptionItem(
      id: json['id'],
      nama: json['nama']?.toString() ?? '',
      hargaTambahan: _parseInt(json['harga_tambahan']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nama': nama,
        'harga_tambahan': hargaTambahan,
      };

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── Model baru: OptionGroup ──────────────────────────────────
class OptionGroup {
  final int id;
  final String nama;
  final String tipe; // 'single' | 'multiple'
  final bool isRequired;
  final int minPilih;
  final int maxPilih;
  final List<OptionItem> items;

  const OptionGroup({
    required this.id,
    required this.nama,
    required this.tipe,
    required this.isRequired,
    required this.minPilih,
    required this.maxPilih,
    required this.items,
  });

  bool get isSingle => tipe == 'single';
  bool get isMultiple => tipe == 'multiple';

  factory OptionGroup.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List? ?? [])
        .map((i) => OptionItem.fromJson(i as Map<String, dynamic>))
        .toList();

    return OptionGroup(
      id: json['id'],
      nama: json['nama']?.toString() ?? '',
      tipe: json['tipe']?.toString() ?? 'single',
      isRequired: json['is_required'] == true || json['is_required'] == 1,
      minPilih: _parseInt(json['min_pilih']),
      maxPilih: _parseInt(json['max_pilih']),
      items: itemsList,
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── SelectedOption: mewakili pilihan user untuk satu group ───
// Dipakai di kasir_screen saat user memilih opsi sebelum add to cart
class SelectedOption {
  final OptionGroup group;
  final List<OptionItem> selectedItems;

  const SelectedOption({
    required this.group,
    required this.selectedItems,
  });

  int get totalHargaTambahan =>
      selectedItems.fold(0, (sum, item) => sum + item.hargaTambahan);
}

// ── Model utama: Product ─────────────────────────────────────
class Product {
  final int id;
  final String namaProduk;
  final double harga;
  final int qty;
  final String? foto;
  final int kategoriId;
  final String? kategori;
  final int tokoId;
  final bool useStock;

  // BARU
  final bool hasOptions;
  final List<OptionGroup> optionGroups;

  Product({
    required this.id,
    required this.namaProduk,
    required this.harga,
    required this.qty,
    this.foto,
    required this.kategoriId,
    this.kategori,
    required this.tokoId,
    this.hasOptions = false,
    this.optionGroups = const [],
    this.useStock = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final groupsList = (json['option_groups'] as List? ?? [])
        .map((g) => OptionGroup.fromJson(g as Map<String, dynamic>))
        .toList();

    return Product(
      id: json['id'],
      namaProduk: json['nama_produk'],
      harga: _parseDouble(json['harga']),
      qty: _parseInt(json['qty']),
      foto: json['foto'],
      kategoriId: json['kategori_id'],
      kategori: json['kategori'],
      tokoId: json['toko_id'],
      // BARU
      hasOptions: json['has_options'] == true || json['has_options'] == 1,
      optionGroups: groupsList,
      useStock: json['use_stock'] == true || json['use_stock'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nama_produk': namaProduk,
      'harga': harga,
      'qty': qty,
      'foto': foto,
      'kategori_id': kategoriId,
      'kategori': kategori,
      'toko_id': tokoId,
      'has_options': hasOptions,
      'use_stock': useStock,
    };
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
}
