class Order {
  final int id;
  final int tokoId;
  final int userId;
  final int? mejaId;
  final String? mejaNo;
  final int jenisOrder; // 1: dine-in, 2: take away
  final int metodeBayar; // 1: cash, 2: transfer
  final String? catatan;
  final double totalHarga;
  final String status;
  final List<OrderItem> items;
  final DateTime createdAt;

  // New fields for kasir and toko info
  final String? kasirNama;
  final String? tokoNama;

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
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    var itemsList = <OrderItem>[];

    if (json['detailorder'] != null) {
      itemsList = (json['detailorder'] as List)
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
      // Parse kasir and toko info
      // Kasir name from users.name column
      kasirNama: json['user']?['name']?.toString(),
      // Toko name from toko.nama_toko column
      tokoNama: json['toko']?['nama_toko']?.toString(),
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
    };
  }

  String get jenisOrderText => jenisOrder == 1 ? 'Dine In' : 'Take Away';
  String get metodeBayarText => metodeBayar == 1 ? 'Cash' : 'Transfer';
}

class OrderItem {
  final int id;
  final int orderId;
  final int menuId;
  final String menuNama;
  final int qty;
  final double harga;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.menuId,
    required this.menuNama,
    required this.qty,
    required this.harga,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'],
      orderId: json['order_id'],
      menuId: json['menu_id'],
      menuNama: json['menu']?['nama_produk']?.toString() ?? '',
      qty: int.parse(json['qty'].toString()),
      harga: double.parse(json['harga'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'menu_id': menuId,
      'qty': qty,
      'harga': harga,
    };
  }

  double get subtotal => qty * harga;
}
