import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class ShiftService {
  // static final String _base = '${AppConstants.baseUrl}/shifts';
  static String get _base => Constants.baseUrl;

  // ── Buka shift ──────────────────────────────────────────
  static Future<Map<String, dynamic>> bukaShift({
    required int tokoId,
    required String pin,
    required int openAmount,
    String? catatanBuka,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/open'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({
        'toko_id': tokoId,
        'pin': pin,
        'open_amount': openAmount,
        'catatan_buka': catatanBuka ?? 'Open kasir pagi',
      }),
    );
    return jsonDecode(res.body);
  }

  // ── Tutup shift ─────────────────────────────────────────
  static Future<Map<String, dynamic>> tutupShift({
    required int shiftId,
    required String pin,
    required int closeAmount,
    String? catatanTutup,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/$shiftId/close'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({
        'pin': pin,
        'close_amount': closeAmount,
        'catatan_tutup': catatanTutup,
      }),
    );
    return jsonDecode(res.body);
  }

  // ── Tambah/kurang kas ────────────────────────────────────
  static Future<Map<String, dynamic>> tambahKas({
    required int shiftId,
    required String pin,
    required String type, // 'in' atau 'out'
    required int jumlah,
    String? keterangan,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/$shiftId/cash-flow'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({
        'pin': pin,
        'type': type,
        'jumlah': jumlah,
        'keterangan': keterangan,
      }),
    );
    return jsonDecode(res.body);
  }

  // ── Ganti kasir (switch user) ────────────────────────────
  static Future<Map<String, dynamic>> gantiKasir({
    required int tokoId,
    required String pin,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/switch-user'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({
        'toko_id': tokoId,
        'pin': pin,
      }),
    );
    return jsonDecode(res.body);
  }

  // ── Cek shift aktif ──────────────────────────────────────
  static Future<Map<String, dynamic>> cekShiftAktif({
    required int tokoId,
    required int userId,
  }) async {
    final res = await http.get(
      Uri.parse('$_base/active?toko_id=$tokoId&user_id=$userId'),
      headers: {'Accept': 'application/json'},
    );
    return jsonDecode(res.body);
  }

  // ── Riwayat shift (laporan) ──────────────────────────────
  static Future<Map<String, dynamic>> getRiwayatShift({
    required int tokoId,
    String? from,
    String? to,
    String? status,
    int page = 1,
  }) async {
    final params = {
      'toko_id': tokoId.toString(),
      'page': page.toString(),
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (status != null) 'status': status,
    };
    final uri = Uri.parse(_base).replace(queryParameters: params);
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    return jsonDecode(res.body);
  }

  // ── Detail 1 shift ───────────────────────────────────────
  static Future<Map<String, dynamic>> getDetailShift(int shiftId) async {
    final res = await http.get(
      Uri.parse('$_base/$shiftId'),
      headers: {'Accept': 'application/json'},
    );
    return jsonDecode(res.body);
  }
}
