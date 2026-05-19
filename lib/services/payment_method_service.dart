import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class PaymentMethodService {
  static String get baseUrl => Constants.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(Constants.tokenKey);
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ────────────────────────────────────────────────────────
  // GET /api/payment-methods?toko_id=x
  // Dipanggil saat kasir buka app atau payment dialog dibuka
  // ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPaymentMethods(
      int tokoId) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/payment-methods?toko_id=$tokoId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data'] as List? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } on TimeoutException {
      debugPrint('⏱️ getPaymentMethods timeout');
    } catch (e) {
      debugPrint('❌ getPaymentMethods error: $e');
    }

    // Fallback default jika gagal (agar kasir tetap bisa transaksi)
    return [
      {'id': null, 'nama': 'Tunai', 'kode': 'CASH', 'icon': null},
      {'id': null, 'nama': 'QRIS', 'kode': 'QRIS', 'icon': null},
      {'id': null, 'nama': 'Transfer', 'kode': 'TF', 'icon': null},
    ];
  }
}
