import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import '../core/database/db_helper.dart';

class ShiftService {
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

  static Future<Map<String, dynamic>> bukaShift({
    required int tokoId,
    required String pin,
    required int openAmount,
    String? catatanBuka,
  }) async {
    if (!await _isOnline()) return _offlineError();
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/open'),
            headers: await _headers(),
            body: jsonEncode({
              'toko_id': tokoId,
              'pin': pin,
              'open_amount': openAmount,
              'catatan_buka': catatanBuka ?? 'Open kasir pagi',
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Gagal membuka shift'
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout. Coba lagi.'};
    } catch (e) {
      debugPrint('❌ bukaShift error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> tutupShift({
    required int shiftId,
    required String pin,
    required int closeAmount,
    String? catatanTutup,
  }) async {
    if (!await _isOnline()) return _offlineError();
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/$shiftId/close'),
            headers: await _headers(),
            body: jsonEncode({
              'pin': pin,
              'close_amount': closeAmount,
              'catatan_tutup': catatanTutup,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) return {'success': true, ...data};
      return {
        'success': false,
        'message': data['message'] ?? 'Gagal menutup shift'
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout. Coba lagi.'};
    } catch (e) {
      debugPrint('❌ tutupShift error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> tambahKas({
    required int shiftId,
    required String pin,
    required String type,
    required int jumlah,
    String? keterangan,
  }) async {
    if (!await _isOnline()) return _offlineError();
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/$shiftId/cash-flow'),
            headers: await _headers(),
            body: jsonEncode({
              'pin': pin,
              'type': type,
              'jumlah': jumlah,
              'keterangan': keterangan,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, ...data};
      }
      return {'success': false, 'message': data['message'] ?? 'Gagal'};
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout. Coba lagi.'};
    } catch (e) {
      debugPrint('❌ tambahKas error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> gantiKasir({
    required int tokoId,
    required String pin,
  }) async {
    if (!await _isOnline()) return _offlineError();
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/switch-user'),
            headers: await _headers(),
            body: jsonEncode({'toko_id': tokoId, 'pin': pin}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) return {'success': true, ...data};
      return {
        'success': false,
        'message': data['message'] ?? 'PIN tidak valid'
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout. Coba lagi.'};
    } catch (e) {
      debugPrint('❌ gantiKasir error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<bool> _isOnline() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      return conn.isNotEmpty && conn.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _fromShiftCache(
      int tokoId, int userId) async {
    final cache = await DBHelper.getShiftCache(tokoId, userId);
    if (cache != null) {
      return {
        'success': true,
        'shift_aktif': cache['shift_aktif'],
        'shift': cache['shift'],
        'offline': true,
      };
    }
    return {'success': false, 'shift_aktif': false, 'shift': null, 'offline': true};
  }

  static Future<Map<String, dynamic>> cekShiftAktif({
    required int tokoId,
    required int userId,
  }) async {
    if (!await _isOnline()) {
      debugPrint('📵 Offline: cekShiftAktif returning cached shift');
      return _fromShiftCache(tokoId, userId);
    }
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/shifts/active?toko_id=$tokoId&user_id=$userId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        await DBHelper.saveShiftCache(
          tokoId, userId, data['shift_aktif'] == true, data['shift']);
        return {'success': true, ...data};
      }
      return {'success': false, 'shift_aktif': false, 'shift': null};
    } on TimeoutException {
      debugPrint('⏱️ cekShiftAktif timeout, returning cache');
      return _fromShiftCache(tokoId, userId);
    } catch (e) {
      debugPrint('❌ cekShiftAktif error: $e');
      return _fromShiftCache(tokoId, userId);
    }
  }

  static Map<String, dynamic> _offlineError() =>
      {'success': false, 'message': 'Tidak dapat digunakan saat offline. Hubungkan internet terlebih dahulu.'};

  static Future<Map<String, dynamic>> getRiwayatShift({
    required int tokoId,
    String? from,
    String? to,
    String? status,
    int page = 1,
  }) async {
    try {
      final params = {
        'toko_id': tokoId.toString(),
        'page': page.toString(),
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (status != null) 'status': status,
      };
      final uri = Uri.parse('$baseUrl/shifts').replace(queryParameters: params);
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) return {'success': true, ...data};
      return {
        'success': false,
        'message': data['message'] ?? 'Gagal memuat riwayat shift'
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout.'};
    } catch (e) {
      debugPrint('❌ getRiwayatShift error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> getDetailShift(int shiftId) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/shifts/$shiftId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) return {'success': true, ...data};
      return {
        'success': false,
        'message': data['message'] ?? 'Gagal memuat detail shift'
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Koneksi timeout.'};
    } catch (e) {
      debugPrint('❌ getDetailShift error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
