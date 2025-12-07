// FILE INI DIGUNAKAN - Handle String dari API Laravel

class Product {
  final int id;
  final String namaProduk;
  final double harga;
  final int qty;
  final String? foto;
  final String? kategori;
  final int tokoId;

  Product({
    required this.id,
    required this.namaProduk,
    required this.harga,
    required this.qty,
    this.foto,
    this.kategori,
    required this.tokoId,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      namaProduk: json['nama_produk'],
      // ← FIX: Handle String dari Laravel
      harga: _parseDouble(json['harga']),
      qty: _parseInt(json['qty']),
      foto: json['foto'],
      kategori: json['kategori'],
      tokoId: json['toko_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nama_produk': namaProduk,
      'harga': harga,
      'qty': qty,
      'foto': foto,
      'kategori': kategori,
      'toko_id': tokoId,
    };
  }

  // Helper function untuk parse String ke double
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  // Helper function untuk parse String ke int
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    if (value is double) return value.toInt();
    return 0;
  }
}
