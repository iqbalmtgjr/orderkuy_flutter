import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../utils/constants.dart';
import '../models/product.dart';
import '../models/meja.dart';
import '../models/order.dart';
import '../models/kategori.dart';
import '../models/pengeluaran.dart';
import '../core/database/db_helper.dart';
import '../core/database/offline_queue_db.dart';

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
    final conn = await Connectivity().checkConnectivity();

    // If offline, load from cache
    if (conn == ConnectivityResult.none) {
      debugPrint('Offline: Loading menus from cache');
      final hasCache = await DBHelper.hasProductsCache();
      if (hasCache) {
        final cachedProducts = await DBHelper.getProductsFromCache();
        // Perbaikan: Cast ke List<Map<String, dynamic>>
        return cachedProducts.map((p) => Product.fromJson(p)).toList();
      } else {
        debugPrint('No cached menus available');
        return [];
      }
    }

    // Online: fetch from API and cache
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

        // Perbaikan: Cast setiap item ke Map<String, dynamic>
        final menusListCasted =
            menusList.map((menu) => menu as Map<String, dynamic>).toList();

        // Cache the products
        await DBHelper.saveProductsToCache(menusListCasted);

        return menusListCasted.map((menu) => Product.fromJson(menu)).toList();
      } else {
        // If API fails, try to load from cache
        debugPrint('API failed, loading from cache');
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          final cachedProducts = await DBHelper.getProductsFromCache();
          // Perbaikan: Cast ke List<Map<String, dynamic>>
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        }
        return [];
      }
    } catch (e) {
      debugPrint('Error getting menus: $e');
      // On error, try to load from cache
      final hasCache = await DBHelper.hasProductsCache();
      if (hasCache) {
        final cachedProducts = await DBHelper.getProductsFromCache();
        // Perbaikan: Cast ke List<Map<String, dynamic>>
        return cachedProducts.map((p) => Product.fromJson(p)).toList();
      }
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
  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);
      final conn = await Connectivity().checkConnectivity();

      // Generate UUID if not exists
      if (!orderData.containsKey('client_uuid') ||
          orderData['client_uuid'] == null) {
        orderData['client_uuid'] = const Uuid().v4();
      }

      final clientUuid = orderData['client_uuid'] as String;

      // If offline, save to local database
      if (conn == ConnectivityResult.none) {
        debugPrint('📵 Offline: Saving order locally with UUID: $clientUuid');

        await DBHelper.saveOfflineOrder(orderData, clientUuid);

        return {
          'success': true,
          'message': 'Pesanan disimpan offline (akan diupload saat online)',
          'offline': true,
          'data': {
            'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}',
            'client_uuid': clientUuid,
            'user': {'name': 'OFFLINE'},
            'toko': {'nama_toko': 'OFFLINE'},
          },
        };
      }

      // Online: Send to server
      debugPrint('📡 Online: Sending order to server with UUID: $clientUuid');

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

        // Save offline as fallback
        await DBHelper.saveOfflineOrder(orderData, clientUuid);

        return {
          'success': false,
          'message': 'Server error. Pesanan disimpan offline.',
          'offline': true,
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Order created successfully on server');
        debugPrint('Server ID: ${responseData['data']?['id']}');

        return {
          'success': true,
          'message': responseData['message'] ?? 'Order berhasil dibuat',
          'offline': false,
          'data': responseData['data'],
        };
      } else {
        // Save offline as fallback
        debugPrint('❌ Server rejected order, saving offline');
        await DBHelper.saveOfflineOrder(orderData, clientUuid);

        return {
          'success': false,
          'message': '${responseData['message']}. Pesanan disimpan offline.',
          'offline': true,
        };
      }
    } catch (e) {
      debugPrint('❌ Error creating order: $e');

      // Save offline as fallback
      final clientUuid = orderData['client_uuid'] ?? const Uuid().v4();
      orderData['client_uuid'] = clientUuid;

      try {
        await DBHelper.saveOfflineOrder(orderData, clientUuid);
        return {
          'success': false,
          'message': 'Error koneksi. Pesanan disimpan offline.',
          'offline': true,
          'error': e.toString(),
        };
      } catch (dbError) {
        return {
          'success': false,
          'message': 'Gagal menyimpan pesanan: ${dbError.toString()}',
          'error': e.toString(),
        };
      }
    }
  }

  // Update Order
  static Future<Map<String, dynamic>> updateOrder(
    int orderId,
    Map<String, dynamic> orderData,
  ) async {
    final conn = await Connectivity().checkConnectivity();

    if (conn == ConnectivityResult.none) {
      await OfflineQueueDB.push(
        endpoint: '/orders/$orderId',
        method: 'PUT',
        payload: orderData,
      );
      return {'success': true, 'message': 'Update disimpan offline'};
    }
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
    final conn = await Connectivity().checkConnectivity();

    // ← OFFLINE: Load from cache
    if (conn == ConnectivityResult.none) {
      debugPrint('📵 Offline: Loading pengeluaran from cache');

      final hasCache = await DBHelper.hasPengeluaranCache();
      if (hasCache) {
        final cachedData = await DBHelper.getPengeluaranFromCache();

        // Convert to Pengeluaran objects
        final pengeluaranList =
            cachedData.map((item) => Pengeluaran.fromJson(item)).toList();

        // Calculate total
        double total =
            pengeluaranList.fold(0, (sum, item) => sum + item.jumlah);

        return {
          'success': true,
          'data': pengeluaranList,
          'total_pengeluaran': total,
          'offline': true,
        };
      } else {
        return {
          'success': false,
          'message': 'Tidak ada data cache. Hubungkan internet untuk sync.',
          'offline': true,
        };
      }
    }

    // ← ONLINE: Fetch from API
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

        // ← CACHE the data
        await DBHelper.savePengeluaranToCache(
            pengeluaranList.cast<Map<String, dynamic>>());

        double parseTotalPengeluaran(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) return value.toDouble();
          if (value is String) {
            final cleanValue = value
                .replaceAll('Rp', '')
                .replaceAll('.', '')
                .replaceAll(',', '.')
                .trim();
            return double.tryParse(cleanValue) ?? 0.0;
          }
          return 0.0;
        }

        return {
          'success': true,
          'data': pengeluaran,
          'total_pengeluaran': parseTotalPengeluaran(data['total_pengeluaran']),
          'offline': false,
        };
      } else {
        // API error - fallback to cache
        final hasCache = await DBHelper.hasPengeluaranCache();
        if (hasCache) {
          final cachedData = await DBHelper.getPengeluaranFromCache();
          final pengeluaranList =
              cachedData.map((item) => Pengeluaran.fromJson(item)).toList();

          double total =
              pengeluaranList.fold(0, (sum, item) => sum + item.jumlah);

          return {
            'success': true,
            'data': pengeluaranList,
            'total_pengeluaran': total,
            'offline': true,
            'message': 'Menggunakan data cache (API error)',
          };
        }

        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Gagal memuat pengeluaran',
        };
      }
    } catch (e) {
      debugPrint('Error getting pengeluaran: $e');

      // Fallback to cache on error
      final hasCache = await DBHelper.hasPengeluaranCache();
      if (hasCache) {
        final cachedData = await DBHelper.getPengeluaranFromCache();
        final pengeluaranList =
            cachedData.map((item) => Pengeluaran.fromJson(item)).toList();

        double total =
            pengeluaranList.fold(0, (sum, item) => sum + item.jumlah);

        return {
          'success': true,
          'data': pengeluaranList,
          'total_pengeluaran': total,
          'offline': true,
          'message': 'Menggunakan data cache (Error: $e)',
        };
      }

      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> createPengeluaran(
    Map<String, dynamic> pengeluaranData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);
      final conn = await Connectivity().checkConnectivity();

      // Generate UUID
      if (!pengeluaranData.containsKey('client_uuid') ||
          pengeluaranData['client_uuid'] == null) {
        pengeluaranData['client_uuid'] = const Uuid().v4();
      }

      final clientUuid = pengeluaranData['client_uuid'] as String;

      // ← OFFLINE: Save locally
      if (conn == ConnectivityResult.none) {
        debugPrint(
            '📵 Offline: Saving pengeluaran locally with UUID: $clientUuid');

        await DBHelper.saveOfflinePengeluaran(pengeluaranData, clientUuid);

        // Also add to cache for immediate display
        await DBHelper.addPengeluaranToCache(pengeluaranData);

        return {
          'success': true,
          'message': 'Pengeluaran disimpan offline (akan diupload saat online)',
          'offline': true,
          'data': {
            'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}',
            'client_uuid': clientUuid,
          },
        };
      }

      // ← ONLINE: Send to server
      debugPrint(
          '📡 Online: Sending pengeluaran to server with UUID: $clientUuid');

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
        debugPrint('✅ Pengeluaran created successfully on server');

        return {
          'success': true,
          'message':
              responseData['message'] ?? 'Pengeluaran berhasil ditambahkan',
          'offline': false,
          'data': responseData['data'],
        };
      } else {
        // Server error - save offline
        debugPrint('❌ Server rejected, saving offline');
        await DBHelper.saveOfflinePengeluaran(pengeluaranData, clientUuid);
        await DBHelper.addPengeluaranToCache(pengeluaranData);

        return {
          'success': false,
          'message': '${responseData['message']}. Disimpan offline.',
          'offline': true,
        };
      }
    } catch (e) {
      debugPrint('❌ Error creating pengeluaran: $e');

      // Save offline as fallback
      final clientUuid = pengeluaranData['client_uuid'] ?? const Uuid().v4();
      pengeluaranData['client_uuid'] = clientUuid;

      try {
        await DBHelper.saveOfflinePengeluaran(pengeluaranData, clientUuid);
        await DBHelper.addPengeluaranToCache(pengeluaranData);

        return {
          'success': false,
          'message': 'Error koneksi. Pengeluaran disimpan offline.',
          'offline': true,
          'error': e.toString(),
        };
      } catch (dbError) {
        return {
          'success': false,
          'message': 'Gagal menyimpan: ${dbError.toString()}',
          'error': e.toString(),
        };
      }
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
    final conn = await Connectivity().checkConnectivity();

    if (conn == ConnectivityResult.none) {
      // For offline update, queue it
      await OfflineQueueDB.push(
        endpoint: '/pengeluaran/$pengeluaranId',
        method: 'PUT',
        payload: pengeluaranData,
      );

      return {
        'success': true,
        'message': 'Update disimpan offline',
        'offline': true,
      };
    }

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

  // riwayat
  static Future<Map<String, dynamic>> getRiwayat({
    int page = 1,
    String? tanggalDari,
    String? tanggalSampai,
    int? jenisOrder,
    int? metodePembayaran,
    String? search,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('Token tidak ditemukan');
      }

      // Build query parameters
      Map<String, String> queryParams = {
        'page': page.toString(),
      };

      if (tanggalDari != null) queryParams['tanggal_dari'] = tanggalDari;
      if (tanggalSampai != null) queryParams['tanggal_sampai'] = tanggalSampai;
      if (jenisOrder != null) {
        queryParams['jenis_order'] = jenisOrder.toString();
      }
      if (metodePembayaran != null) {
        queryParams['metode_pembayaran'] = metodePembayaran.toString();
      }
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri =
          Uri.parse('$baseUrl/riwayat').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesi berakhir, silakan login ulang');
      } else {
        throw Exception('Gagal memuat riwayat');
      }
    } catch (e) {
      debugPrint('Error getRiwayat: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRiwayatSummary({
    String? tanggalDari,
    String? tanggalSampai,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('Token tidak ditemukan');
      }

      Map<String, String> queryParams = {};
      if (tanggalDari != null) queryParams['tanggal_dari'] = tanggalDari;
      if (tanggalSampai != null) queryParams['tanggal_sampai'] = tanggalSampai;

      final uri = Uri.parse('$baseUrl/riwayat/summary/stats')
          .replace(queryParameters: queryParams);

      debugPrint('🔍 Calling summary API: $uri'); // Debug log

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
          '📊 Summary response status: ${response.statusCode}'); // Debug log
      debugPrint('📊 Summary response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesi berakhir, silakan login ulang');
      } else if (response.statusCode == 404) {
        throw Exception(
            'Endpoint summary tidak ditemukan. Periksa routing Laravel.');
      } else {
        throw Exception(
            'Gagal memuat summary: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error getRiwayatSummary: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRiwayatDetail(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('Token tidak ditemukan');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/riwayat/$orderId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Gagal memuat detail transaksi');
      }
    } catch (e) {
      debugPrint('Error getRiwayatDetail: $e');
      rethrow;
    }
  }

  static Future<List<Kategori>> getKategoris() async {
    final conn = await Connectivity().checkConnectivity();

    // If offline, load from cache
    if (conn == ConnectivityResult.none) {
      debugPrint('Offline: Loading kategoris from cache');
      final hasCache = await DBHelper.hasKategorisCache();
      if (hasCache) {
        final cachedKategoris = await DBHelper.getKategorisFromCache();
        return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
      } else {
        debugPrint('No cached kategoris available');
        return [];
      }
    }

    // Online: fetch from API and cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      if (token == null) {
        debugPrint('Token tidak ditemukan');
        return [];
      }

      debugPrint('Fetching kategoris from: $baseUrl/kategoris');

      final response = await http.get(
        Uri.parse('$baseUrl/kategoris'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('Kategoris response status: ${response.statusCode}');
      debugPrint('Kategoris response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success']) {
          final kategorisList = data['kategoris'] as List;
          final kategorisListCasted =
              kategorisList.map((k) => k as Map<String, dynamic>).toList();

          // Cache the kategoris
          await DBHelper.saveKategorisToCache(kategorisListCasted);

          final kategoris =
              kategorisListCasted.map((k) => Kategori.fromJson(k)).toList();

          debugPrint('Kategoris loaded: ${kategoris.length}');
          for (var k in kategoris) {
            debugPrint('  - ID: ${k.id}, Nama: ${k.namaKategori}');
          }

          return kategoris;
        } else {
          debugPrint('API returned success: false');

          // Fallback to cache if API fails
          final hasCache = await DBHelper.hasKategorisCache();
          if (hasCache) {
            debugPrint('Loading from cache as fallback');
            final cachedKategoris = await DBHelper.getKategorisFromCache();
            return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
          }

          return [];
        }
      } else {
        debugPrint('API error: ${response.statusCode}');

        // Fallback to cache if API fails
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          debugPrint('Loading from cache due to API error');
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        }

        return [];
      }
    } catch (e) {
      debugPrint('Error getting kategoris: $e');

      // On error, try to load from cache
      final hasCache = await DBHelper.hasKategorisCache();
      if (hasCache) {
        debugPrint('Loading from cache due to error');
        final cachedKategoris = await DBHelper.getKategorisFromCache();
        return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
      }

      return [];
    }
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
    await prefs.remove(Constants.userKey);
  }

  static Future<Map<String, dynamic>> raw({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(Constants.tokenKey);

    final url = Uri.parse('$baseUrl$endpoint');

    http.Response res;

    if (method == 'PUT') {
      res = await http.put(url,
          headers: _headers(token), body: jsonEncode(payload));
    } else if (method == 'DELETE') {
      res = await http.delete(url, headers: _headers(token));
    } else {
      res = await http.post(url,
          headers: _headers(token), body: jsonEncode(payload));
    }

    return jsonDecode(res.body);
  }

  static Map<String, String> _headers(String? token) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
}
