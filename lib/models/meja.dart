class Meja {
  final int id;
  final String noMeja;
  final int status; // 0: free, 1: occupied
  final int tokoId;

  Meja({
    required this.id,
    required this.noMeja,
    required this.status,
    required this.tokoId,
  });

  factory Meja.fromJson(Map<String, dynamic> json) {
    return Meja(
      id: json['id'],
      noMeja: json['no_meja'].toString(), // ← Ensure string
      status: _parseInt(json['status']), // ← Handle string/int
      tokoId: json['toko_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'no_meja': noMeja,
      'status': status,
      'toko_id': tokoId,
    };
  }

  bool get isFree => status == 0;
  bool get isOccupied => status == 1;

  String get statusText => isFree ? 'Kosong' : 'Terisi';

  // Helper function
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
