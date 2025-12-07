class User {
  final int id;
  final String name;
  final String email;
  final String? role;
  final int? tokoId;
  final String? tokoNama;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.tokoId,
    this.tokoNama,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      role: json['role'],
      tokoId: json['toko_id'],
      tokoNama: json['toko_nama'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'toko_id': tokoId,
      'toko_nama': tokoNama,
    };
  }
}
