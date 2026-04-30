class SelectedOptionSnapshot {
  final int id;
  final String namaGroup;
  final String namaItem;
  final int hargaTambahan;

  const SelectedOptionSnapshot({
    required this.id,
    required this.namaGroup,
    required this.namaItem,
    required this.hargaTambahan,
  });

  factory SelectedOptionSnapshot.fromJson(Map<String, dynamic> json) {
    return SelectedOptionSnapshot(
      id: _parseInt(json['option_item_id'] ?? json['id']),
      namaGroup: json['nama_group']?.toString() ?? '',
      namaItem: json['nama_item']?.toString() ?? '',
      hargaTambahan: _parseInt(json['harga_tambahan']),
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

// ── OrderItem ────────────────────────────────────────────────
class OrderItem {
  final int id;
  final int orderId;
  final int menuId;
  final String menuNama;
  final int qty;
  final double harga;
  final List<SelectedOptionSnapshot> opsiDipilih;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.menuId,
    required this.menuNama,
    required this.qty,
    required this.harga,
    this.opsiDipilih = const [],
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    // Parse opsi — field dari formatOrder() Laravel adalah 'opsi_dipilih'
    final opsiList = (json['opsi_dipilih'] as List? ?? [])
        .map((o) => SelectedOptionSnapshot.fromJson(o as Map<String, dynamic>))
        .toList();

    return OrderItem(
      id: _parseInt(json['id']),
      orderId: _parseInt(json['order_id'] ?? 0),
      menuId: _parseInt(json['menu_id']),
      menuNama: json['menu']
              ?.toString() ?? // dari formatOrder: field 'menu' berisi string nama
          json['menu_nama']?.toString() ??
          '',
      qty: _parseInt(json['qty']),
      // PERBAIKAN: parse harga dengan robust — bisa string "25000" atau int 25000
      harga: _parseDouble(json['harga']),
      opsiDipilih: opsiList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_id': orderId,
        'menu_id': menuId,
        'qty': qty,
        'harga': harga,
      };

  int get totalHargaOpsi =>
      opsiDipilih.fold(0, (sum, o) => sum + o.hargaTambahan);

  // PERBAIKAN: subtotal = qty × (harga dasar + total opsi)
  double get subtotal => qty * (harga + totalHargaOpsi);

  String get opsiLabel => opsiDipilih.map((o) => o.namaItem).join(', ');

  // ── Helpers ─────────────────────────────────────────────────
  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── Order ────────────────────────────────────────────────────
class Order {
  final int id;
  final int tokoId;
  final int userId;
  final int? mejaId;
  final String? mejaNo;
  final int jenisOrder;
  final int metodeBayar;
  final String? catatan;
  final double totalHarga;
  final String status;
  final List<OrderItem> items;
  final DateTime createdAt;
  final String? kasirNama;
  final String? tokoNama;
  final String? tokoAlamat;

  Order({
    required this.id,
    required this.tokoId,
    required this.userId,
    this.mejaId,
    this.mejaNo,
    required this.jenisOrder,
    required this.metodeBayar,
    this.catatan,
    required this.totalHarga,
    required this.status,
    required this.items,
    required this.createdAt,
    this.kasirNama,
    this.tokoNama,
    this.tokoAlamat,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    var itemsList = <OrderItem>[];

    if (json['detailorder'] != null) {
      itemsList = (json['detailorder'] as List)
          .map((item) => OrderItem.fromJson(item))
          .toList();
    } else if (json['items'] != null) {
      // Format dari endpoint baru (formatOrder helper)
      itemsList = (json['items'] as List)
          .map((item) => OrderItem.fromJson(item))
          .toList();
    }

    return Order(
      id: json['id'],
      tokoId: json['toko_id'],
      userId: json['user_id'],
      mejaId: json['meja_id'],
      mejaNo: json['meja']?['no_meja']?.toString(),
      jenisOrder: json['jenis_order'] ?? 1,
      metodeBayar: json['metode_bayar'] ?? 1,
      catatan: json['catatan']?.toString(),
      totalHarga: double.parse(json['total_harga'].toString()),
      status: json['status']?.toString() ?? 'pending',
      items: itemsList,
      createdAt: json['created_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000)
          : DateTime.parse(json['created_at'].toString()),
      kasirNama: json['user']?['name']?.toString(),
      tokoNama: json['toko']?['nama_toko']?.toString(),
      tokoAlamat: json['toko']?['alamat']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'toko_id': tokoId,
      'user_id': userId,
      'meja_id': mejaId,
      'jenis_order': jenisOrder,
      'metode_bayar': metodeBayar,
      'catatan': catatan,
      'total_harga': totalHarga,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'kasir_nama': kasirNama,
      'toko_nama': tokoNama,
      'toko_alamat': tokoAlamat,
    };
  }

  String get jenisOrderText => jenisOrder == 1 ? 'Dine In' : 'Take Away';
  String get metodeBayarText => metodeBayar == 1 ? 'Cash' : 'Transfer';
}
