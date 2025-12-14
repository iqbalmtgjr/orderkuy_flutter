class Pengeluaran {
  final int? id;
  final String namaPengeluaran;
  final String? deskripsi;
  final double jumlah;
  final String tanggal;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Pengeluaran({
    this.id,
    required this.namaPengeluaran,
    this.deskripsi,
    required this.jumlah,
    required this.tanggal,
    this.createdAt,
    this.updatedAt,
  });

  factory Pengeluaran.fromJson(Map<String, dynamic> json) {
    // Fungsi helper untuk parsing jumlah yang aman
    double parseJumlah(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        // Hapus format currency jika ada (Rp, titik, koma)
        final cleanValue = value
            .replaceAll('Rp', '')
            .replaceAll('.', '')
            .replaceAll(',', '.')
            .trim();
        return double.tryParse(cleanValue) ?? 0.0;
      }
      return 0.0;
    }

    // Fungsi helper untuk parsing tanggal yang aman
    String parseTanggal(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    // Fungsi helper untuk parsing DateTime yang aman
    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      try {
        if (value is String) return DateTime.parse(value);
        return null;
      } catch (e) {
        return null;
      }
    }

    return Pengeluaran(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0'),
      namaPengeluaran: json['nama_pengeluaran']?.toString() ?? '',
      deskripsi: json['deskripsi']?.toString(),
      jumlah: parseJumlah(json['jumlah']),
      tanggal: parseTanggal(json['tanggal']),
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nama_pengeluaran': namaPengeluaran,
      'deskripsi': deskripsi,
      'jumlah': jumlah,
      'tanggal': tanggal,
    };
  }

  Pengeluaran copyWith({
    int? id,
    String? namaPengeluaran,
    String? deskripsi,
    double? jumlah,
    String? tanggal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pengeluaran(
      id: id ?? this.id,
      namaPengeluaran: namaPengeluaran ?? this.namaPengeluaran,
      deskripsi: deskripsi ?? this.deskripsi,
      jumlah: jumlah ?? this.jumlah,
      tanggal: tanggal ?? this.tanggal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
