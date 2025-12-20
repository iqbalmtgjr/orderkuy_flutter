class History {
  final int id;
  final String kodeOrder;
  final String tanggal;
  final String tanggalDisplay;
  final int jenisOrder;
  final String jenisOrderText;
  final MejaInfo? meja;
  final String namaCustomer;
  final double totalHarga;
  final int metodePembayaran;
  final String metodePembayaranText;
  final int status;
  final String statusText;
  final String? kasir;
  final List<OrderItem> items;

  History({
    required this.id,
    required this.kodeOrder,
    required this.tanggal,
    required this.tanggalDisplay,
    required this.jenisOrder,
    required this.jenisOrderText,
    this.meja,
    required this.namaCustomer,
    required this.totalHarga,
    required this.metodePembayaran,
    required this.metodePembayaranText,
    required this.status,
    required this.statusText,
    this.kasir,
    required this.items,
  });

  factory History.fromJson(Map<String, dynamic> json) {
    return History(
      id: json['id'],
      kodeOrder: json['kode_order'] ?? '',
      tanggal: json['tanggal'] ?? '',
      tanggalDisplay: json['tanggal_display'] ?? '',
      jenisOrder: json['jenis_order'] ?? 1,
      jenisOrderText: json['jenis_order_text'] ?? '',
      meja: json['meja'] != null ? MejaInfo.fromJson(json['meja']) : null,
      namaCustomer: json['nama_customer'] ?? '',
      totalHarga: _parseDouble(json['total_harga']),
      metodePembayaran: json['metode_pembayaran'] ?? 1,
      metodePembayaranText: json['metode_pembayaran_text'] ?? '',
      status: json['status'] ?? 3,
      statusText: json['status_text'] ?? '',
      kasir: json['kasir'],
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => OrderItem.fromJson(item))
              .toList() ??
          [],
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
}

class MejaInfo {
  final int id;
  final String nomorMeja;

  MejaInfo({
    required this.id,
    required this.nomorMeja,
  });

  factory MejaInfo.fromJson(Map<String, dynamic> json) {
    return MejaInfo(
      id: json['id'],
      nomorMeja: json['nomor_meja'] ?? '',
    );
  }
}

class OrderItem {
  final String menuNama;
  final int qty;
  final double harga;
  final double subtotal;

  OrderItem({
    required this.menuNama,
    required this.qty,
    required this.harga,
    required this.subtotal,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      menuNama: json['menu_nama'] ?? '',
      qty: json['qty'] ?? 0,
      harga: _parseDouble(json['harga']),
      subtotal: _parseDouble(json['subtotal']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
}

class RiwayatSummary {
  final int totalTransaksi;
  final double totalPendapatan;
  final double totalCash;
  final double totalTransfer;

  RiwayatSummary({
    required this.totalTransaksi,
    required this.totalPendapatan,
    required this.totalCash,
    required this.totalTransfer,
  });

  factory RiwayatSummary.fromJson(Map<String, dynamic> json) {
    return RiwayatSummary(
      totalTransaksi: json['total_transaksi'] ?? 0,
      totalPendapatan: _parseDouble(json['total_pendapatan']),
      totalCash: _parseDouble(json['total_cash']),
      totalTransfer: _parseDouble(json['total_transfer']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
}
