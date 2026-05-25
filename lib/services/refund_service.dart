import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model Refund
// ─────────────────────────────────────────────────────────────────────────────

class RefundModel {
  final int id;
  final int orderId;
  final int tokoId;
  final int userId;
  final String userNama;
  final int jumlahRefund;
  final String alasan;
  final String? catatan;
  final String status; // pending | approved | rejected
  final String metodeRefund;
  final DateTime createdAt;

  RefundModel({
    required this.id,
    required this.orderId,
    required this.tokoId,
    required this.userId,
    required this.userNama,
    required this.jumlahRefund,
    required this.alasan,
    required this.status,
    this.catatan,
    required this.metodeRefund,
    required this.createdAt,
  });

  factory RefundModel.fromJson(Map<String, dynamic> json) {
    // Helper: parse int aman dari String maupun int maupun null
    int parseInt(dynamic v) =>
        v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);

    return RefundModel(
      id: parseInt(json['id']),
      orderId: parseInt(json['order_id']),
      tokoId: parseInt(json['toko_id']),
      userId: parseInt(json['kasir_id']),
      userNama: json['kasir_nama']?.toString() ?? '-',
      jumlahRefund: parseInt(json['jumlah']),
      alasan: json['alasan']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      catatan: json['catatan_admin']?.toString(),
      metodeRefund: json['metode_refund']?.toString() ?? 'tunai',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

// ─────────────────────────────────────────────────────────────────────────────
// RefundService  — pola identik dengan ApiService yang sudah ada
// ─────────────────────────────────────────────────────────────────────────────

class RefundService {
  static String get _baseUrl => Constants.baseUrl;

  // ── Helper: ambil token dari SharedPreferences ─────────────────────────────
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.tokenKey);
  }

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ─────────────────────────────────────────────────────────────────────────
  // POST /api/orders/{id}/refund
  // Buat refund baru — dipanggil dari RefundDialog
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> createRefund({
    required int orderId,
    required int userId,
    required int jumlahRefund,
    required String alasan,
    String? catatan,
    String metodeRefund = 'tunai',
  }) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/orders/$orderId/refund'),
        headers: _headers(token),
        body: jsonEncode({
          'user_id': userId,
          'jumlah_refund': jumlahRefund,
          'alasan': alasan,
          'catatan': catatan,
          'metode_refund': metodeRefund,
        }),
      );

      // Tangkap HTML error (sama dengan pola di createOrder)
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}.',
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return {
          'success': true,
          'refund': RefundModel.fromJson(data['data']),
          'message': data['message'],
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Gagal membuat refund.',
        'errors': data['errors'],
      };
    } catch (e) {
      debugPrint('❌ RefundService.createRefund error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET /api/orders/{id}/refund
  // Cek refund untuk 1 order — dipanggil saat buka riwayat
  // ─────────────────────────────────────────────────────────────────────────
  static Future<RefundModel?> getRefundByOrder(int orderId) async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/orders/$orderId/refund'),
        headers: _headers(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return RefundModel.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ RefundService.getRefundByOrder error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET /api/refunds?toko_id=x&status=...&page=...
  // Daftar refund per toko
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<RefundModel>> getRefundsByToko({
    required int tokoId,
    String? status,
    int page = 1,
  }) async {
    try {
      final token = await _getToken();

      final queryParams = <String, String>{
        'toko_id': tokoId.toString(),
        'page': page.toString(),
        if (status != null) 'status': status,
      };

      final uri =
          Uri.parse('$_baseUrl/refunds').replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _headers(token));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final list = data['data'] as List;
          return list.map((e) => RefundModel.fromJson(e)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ RefundService.getRefundsByToko error: $e');
      return [];
    }
  }
}
