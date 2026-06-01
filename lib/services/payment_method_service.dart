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
  static String _cacheKey(int tokoId) => 'payment_methods_cache_$tokoId';

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
        final methods = list.map((e) => Map<String, dynamic>.from(e)).toList();

        // Simpan cache untuk dipakai saat offline
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey(tokoId), jsonEncode(methods));

        return methods;
      }
    } on TimeoutException {
      debugPrint('⏱️ getPaymentMethods timeout');
    } catch (e) {
      debugPrint('❌ getPaymentMethods error: $e');
    }

    // Coba pakai cache terakhir yang berhasil (ada ID real)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey(tokoId));
      if (cached != null) {
        debugPrint('📦 getPaymentMethods: pakai cache offline');
        final list = jsonDecode(cached) as List;
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}

    // Fallback terakhir — id null, order tidak bisa dikirim ke server
    debugPrint('⚠️ getPaymentMethods: tidak ada cache, fallback id=null');
    return [
      {'id': null, 'nama': 'Tunai', 'kode': 'CASH', 'icon': null},
      {'id': null, 'nama': 'QRIS', 'kode': 'QRIS', 'icon': null},
      {'id': null, 'nama': 'Transfer', 'kode': 'TF', 'icon': null},
    ];
  }
}
