import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AbsensiService {
  static String get baseUrl => Constants.baseUrl;

  static Future<List<Map<String, dynamic>>> getKaryawan() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(Constants.tokenKey);

    final res = await http.get(
      Uri.parse('$baseUrl/absensi/karyawan'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['data']);
  }

  static Future<Map<String, dynamic>> auth({
    required int userId,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.post(
        Uri.parse('$baseUrl/absensi/auth'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'password': password,
        }),
      );

      // 🔥 CEK RESPONSE BUKAN JSON
      if (response.body.trim().startsWith('<')) {
        return {
          'success': false,
          'message': 'Unauthorized / token invalid',
        };
      }

      return jsonDecode(response.body);
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Ambil status absensi hari ini
  static Future<Map<String, dynamic>> getToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/absensi/today'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {
        'success': false,
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  /// Check-in
  static Future<Map<String, dynamic>> checkIn({
    required int userId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.post(
        Uri.parse('$baseUrl/absensi/check-in'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Check-out
  static Future<Map<String, dynamic>> checkOut({
    required int userId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.post(
        Uri.parse('$baseUrl/absensi/check-out'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
