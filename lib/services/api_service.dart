import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../models/product.dart';
import '../models/meja.dart';
import '../models/order.dart';
import '../models/pengeluaran.dart';

class ApiService {
  static String get baseUrl => Constants.baseUrl;

  // Login
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Simpan token dan user data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(Constants.tokenKey, data['token']);
        await prefs.setString(Constants.userKey, jsonEncode(data['user']));

        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': 'Login gagal. Periksa email dan password Anda.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  // Dashboard
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        return {
          'success': false,
          'message': 'Token tidak ditemukan',
        };
      }

      final response = await http.get(
        Uri.parse('$baseUrl/dashboard'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Gagal memuat data',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  // Get Menu/Products
  static Future<List<Product>> getMenus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/menus'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final menusList = data['menus'] as List;
        return menusList.map((menu) => Product.fromJson(menu)).toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error getting menus: $e');
      return [];
    }
  }

  // Get Free Tables (Meja Kosong)
  static Future<List<Meja>> getFreeTables() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/mejas/free'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mejasList = data['mejas'] as List;
        return mejasList.map((meja) => Meja.fromJson(meja)).toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error getting tables: $e');
      return [];
    }
  }

  // Get All Tables (Semua Meja)
  static Future<List<Meja>> getAllTables() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/mejas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mejasList = data['mejas'] as List;
        return mejasList.map((meja) => Meja.fromJson(meja)).toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error getting all tables: $e');
      return [];
    }
  }

  // Get Orders (Pesanan hari ini dengan status pending)
  // Response format: { "success": true, "orders": [...] }
  static Future<List<Order>> getOrders({String? filterJenisOrder}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      String url = '$baseUrl/orders';
      if (filterJenisOrder != null && filterJenisOrder.isNotEmpty) {
        url += '?filter_jenis_order=$filterJenisOrder';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Response format dari Laravel: { "success": true, "orders": [...] }
        final ordersList = data['orders'] as List;
        final orders =
            ordersList.map((order) => Order.fromJson(order)).toList();

        // Debug: print first order to check structure
        if (orders.isNotEmpty) {
          debugPrint('=== FIRST ORDER DATA ===');
          debugPrint('Order ID: ${orders[0].id}');
          debugPrint('Kasir: ${orders[0].kasirNama ?? "NULL"}');
          debugPrint('Toko: ${orders[0].tokoNama ?? "NULL"}');
          debugPrint('Alamat: ${orders[0].tokoAlamat ?? "NULL"}');
          debugPrint('=======================');
        }

        return orders;
      } else {
        debugPrint('Error loading orders: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Error getting orders: $e');
      return [];
    }
  }

  // Create Order (Buat Pesanan Baru)
  // Response format: { "success": true, "message": "...", "data": {...} }
  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(orderData),
      );

      // Check if response is HTML error page
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        debugPrint('=== SERVER ERROR RESPONSE ===');
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Response Body: ${response.body.substring(0, 500)}...');
        debugPrint('============================');

        return {
          'success': false,
          'message':
              'Server error: ${response.statusCode}. Silakan coba lagi atau hubungi administrator.',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Debug: print response data
        debugPrint('=== CREATE ORDER RESPONSE ===');
        debugPrint('Success: ${responseData['success']}');
        if (responseData['data'] != null) {
          debugPrint('Order ID: ${responseData['data']['id']}');
          debugPrint('Kasir: ${responseData['data']['user']?['name']}');
          debugPrint('Toko: ${responseData['data']['toko']?['nama_toko']}');
          debugPrint('Alamat: ${responseData['data']['toko']?['alamat']}');
        }
        debugPrint('============================');
        debugPrint(jsonDecode(response.body).toString());

        return {
          'success': true,
          'message': responseData['message'] ?? 'Order berhasil dibuat',
          'data': responseData['data'], // Include user dan toko dari backend
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Gagal membuat order',
        };
      }
    } catch (e) {
      debugPrint('Error creating order: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Update Order
  static Future<Map<String, dynamic>> updateOrder(
    int orderId,
    Map<String, dynamic> orderData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.put(
        Uri.parse('$baseUrl/orders/$orderId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(orderData),
      );

      // Check if response is HTML error page
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        debugPrint('=== SERVER ERROR RESPONSE (UPDATE) ===');
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Response Body: ${response.body.substring(0, 200)}...');
        debugPrint('============================');

        return {
          'success': false,
          'message':
              'Server error: ${response.statusCode}. Silakan coba lagi atau hubungi administrator.',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Order berhasil diupdate',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Gagal memperbarui pesanan',
        };
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Mark Order as Completed (Selesai)
  static Future<Map<String, dynamic>> completeOrder(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/orders/$orderId/selesai'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Check if response is HTML error page
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        debugPrint('=== SERVER ERROR RESPONSE (COMPLETE) ===');
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Response Body: ${response.body.substring(0, 200)}...');
        debugPrint('============================');

        return {
          'success': false,
          'message':
              'Server error: ${response.statusCode}. Silakan coba lagi atau hubungi administrator.',
        };
      }

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Pesanan selesai'};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Gagal menyelesaikan pesanan',
        };
      }
    } catch (e) {
      debugPrint('Error completing order: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Get Order Detail
  static Future<Order?> getOrderDetail(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/orders/$orderId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Check if response is HTML error page
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        debugPrint('=== SERVER ERROR RESPONSE (DETAIL) ===');
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Response Body: ${response.body.substring(0, 200)}...');
        debugPrint('============================');
        return null;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Order.fromJson(data['order']);
      } else {
        debugPrint('Error getting order detail: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting order detail: $e');
      return null;
    }
  }

  // Get Pengeluaran (Expenditures)
  static Future<Map<String, dynamic>> getPengeluaran({
    String? search,
    String? tanggalAwal,
    String? tanggalAkhir,
    String? namaPengeluaranFilter,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      String url = '$baseUrl/pengeluaran';
      final queryParams = <String, String>{};

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (tanggalAwal != null && tanggalAwal.isNotEmpty) {
        queryParams['tanggal_awal'] = tanggalAwal;
      }
      if (tanggalAkhir != null && tanggalAkhir.isNotEmpty) {
        queryParams['tanggal_akhir'] = tanggalAkhir;
      }
      if (namaPengeluaranFilter != null && namaPengeluaranFilter.isNotEmpty) {
        queryParams['nama_pengeluaran_filter'] = namaPengeluaranFilter;
      }

      if (queryParams.isNotEmpty) {
        url +=
            '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pengeluaranList = data['data'] as List;
        final pengeluaran =
            pengeluaranList.map((item) => Pengeluaran.fromJson(item)).toList();

        // Fungsi helper untuk parsing total pengeluaran yang aman
        double parseTotalPengeluaran(dynamic value) {
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

        // Debug: Print response untuk troubleshooting
        debugPrint('API Response: ${data.toString()}');
        debugPrint('Total Pengeluaran Key: ${data['total_pengeluaran']}');

        return {
          'success': true,
          'data': pengeluaran,
          'total_pengeluaran': parseTotalPengeluaran(data['total_pengeluaran']),
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Gagal memuat pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error getting pengeluaran: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Create Pengeluaran
  static Future<Map<String, dynamic>> createPengeluaran(
    Map<String, dynamic> pengeluaranData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.post(
        Uri.parse('$baseUrl/pengeluaran'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(pengeluaranData),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message':
              responseData['message'] ?? 'Pengeluaran berhasil ditambahkan',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Gagal menambahkan pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error creating pengeluaran: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Get Pengeluaran Detail
  static Future<Map<String, dynamic>> getPengeluaranDetail(
      int pengeluaranId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.get(
        Uri.parse('$baseUrl/pengeluaran/$pengeluaranId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': Pengeluaran.fromJson(data['data']),
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Gagal memuat detail pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error getting pengeluaran detail: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Update Pengeluaran
  static Future<Map<String, dynamic>> updatePengeluaran(
    int pengeluaranId,
    Map<String, dynamic> pengeluaranData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.put(
        Uri.parse('$baseUrl/pengeluaran/$pengeluaranId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(pengeluaranData),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message':
              responseData['message'] ?? 'Pengeluaran berhasil diperbarui',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Gagal memperbarui pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error updating pengeluaran: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Delete Pengeluaran
  static Future<Map<String, dynamic>> deletePengeluaran(
      int pengeluaranId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      final response = await http.delete(
        Uri.parse('$baseUrl/pengeluaran/$pengeluaranId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Pengeluaran berhasil dihapus',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Gagal menghapus pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error deleting pengeluaran: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
    await prefs.remove(Constants.userKey);
  }
}
