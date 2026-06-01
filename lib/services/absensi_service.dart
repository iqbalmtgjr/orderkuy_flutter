import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AbsensiService {
  static String get baseUrl => Constants.baseUrl;

  // ── Helper: ambil header Authorization dari SharedPreferences ──
  static Future<Map<String, String>> _headers(
      {bool withContentType = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(Constants.tokenKey) ?? '';
    return {
      if (withContentType) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Helper: decode response, tangani jika bukan JSON ──────────
  static Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().startsWith('<')) {
      // Server mengembalikan HTML (biasanya 401/500 dari Laravel)
      return {
        'success': false,
        'message': 'Token tidak valid atau sesi habis. Silakan login ulang.',
      };
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {
        'success': false,
        'message': 'Response tidak valid dari server.',
      };
    }
  }

  /// Ambil daftar karyawan toko ini.
  static Future<List<Map<String, dynamic>>> getKaryawan() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/absensi/karyawan'),
        headers: await _headers(),
      );

      final data = _decode(response);
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Step 1 — Verifikasi PIN karyawan.
  /// Jika berhasil, server mengembalikan [absen_token] yang berlaku 2 menit.
  static Future<Map<String, dynamic>> auth({
    required int userId,
    required String pin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi/auth'),
        headers: await _headers(withContentType: true),
        body: jsonEncode({
          'user_id': userId,
          'pin': pin,
        }),
      );

      return _decode(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal menghubungi server: ${e.toString()}',
      };
    }
  }

  /// Step 2a — Check-in menggunakan [absenToken] dari hasil [auth()].
  /// Tidak perlu kirim user_id — identitas sudah ada di dalam token server.
  static Future<Map<String, dynamic>> checkIn({
    required String absenToken,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi/check-in'),
        headers: await _headers(withContentType: true),
        body: jsonEncode({
          'absen_token': absenToken,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      return _decode(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal menghubungi server: ${e.toString()}',
      };
    }
  }

  /// Step 2b — Check-out menggunakan [absenToken] dari hasil [auth()].
  /// Token bersifat one-time use — setelah dipakai langsung tidak berlaku.
  static Future<Map<String, dynamic>> checkOut({
    required String absenToken,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/absensi/check-out'),
        headers: await _headers(withContentType: true),
        body: jsonEncode({
          'absen_token': absenToken,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      return _decode(response);
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal menghubungi server: ${e.toString()}',
      };
    }
  }

  /// Ambil status absensi hari ini (berdasarkan token tablet).
  static Future<Map<String, dynamic>> getToday() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/absensi/today'),
        headers: await _headers(),
      );

      return _decode(response);
    } catch (e) {
      return {
        'success': false,
        'status': 'error',
        'message': 'Gagal menghubungi server: ${e.toString()}',
      };
    }
  }
}
