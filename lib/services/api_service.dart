import 'dart:async';
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
import 'dart:io';

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
        return {'success': false, 'message': 'Token tidak ditemukan'};
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
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // GET MENUS - OFFLINE FIRST STRATEGY
  // ═══════════════════════════════════════════════════════════

  static Future<bool> _isOnline() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) return false;

      // Android: double-check dengan actual DNS lookup
      final result = await InternetAddress.lookup(
        Uri.parse(baseUrl).host, // lookup host API kamu langsung
      ).timeout(const Duration(seconds: 5));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Product>> getMenusOfflineFirst({
    Function(List<Product>)? onDataUpdated,
  }) async {
    List<Product> products = [];

    // STEP 1: Load dari cache dulu (INSTANT)
    try {
      final hasCache = await DBHelper.hasProductsCache();
      if (hasCache) {
        final cachedProducts = await DBHelper.getProductsFromCache();
        products = cachedProducts.map((p) => Product.fromJson(p)).toList();
        debugPrint('✅ Loaded ${products.length} products from cache (INSTANT)');
        // Selalu jalankan background fetch untuk update data
        _fetchMenusInBackground(onDataUpdated);
        return products; // ← Return cache DULU, meski kosong sekalipun
      }
    } catch (e) {
      debugPrint('⚠️ Cache error: $e');
    }

    // STEP 2: Tidak ada cache — cek koneksi
    if (!await _isOnline()) {
      debugPrint('📵 Offline mode, no cache available');
      return products; // return []
    }

    // STEP 3: Ada koneksi tapi tidak ada cache — fetch langsung (blocking)
    try {
      debugPrint('🔄 No cache, fetching from server directly...');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);
      if (token == null) return products;

      final response = await http.get(
        Uri.parse('$baseUrl/menus'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final menusList = data['menus'] as List;
        final menusListCasted =
            menusList.map((menu) => menu as Map<String, dynamic>).toList();
        await DBHelper.saveProductsToCache(menusListCasted);
        products =
            menusListCasted.map((menu) => Product.fromJson(menu)).toList();
        debugPrint('✅ Fetched ${products.length} products from server');
      }
    } catch (e) {
      debugPrint('⚠️ Direct fetch error: $e');
    }

    return products;
  }

  static void _fetchMenusInBackground(Function(List<Product>)? onDataUpdated) {
    Future.microtask(() async {
      try {
        // Check connectivity first
        if (!await _isOnline()) {
          debugPrint('📵 Background fetch skipped: offline');
          return;
        }

        debugPrint('🔄 Background: Fetching menus from server...');
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(Constants.tokenKey);
        if (token == null) {
          debugPrint('⚠️ Background fetch skipped: no token');
          return;
        }

        final response = await http.get(
          Uri.parse('$baseUrl/menus'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(
          const Duration(seconds: 15), // ← Reduced timeout for background
          onTimeout: () {
            debugPrint('⏱️ Background fetch timeout (15s) - using cache');
            throw TimeoutException('Background fetch timeout');
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final menusList = data['menus'] as List;
          final menusListCasted =
              menusList.map((menu) => menu as Map<String, dynamic>).toList();
          await DBHelper.saveProductsToCache(menusListCasted);
          debugPrint('✅ Background: Cached ${menusListCasted.length} products');

          if (onDataUpdated != null) {
            final products =
                menusListCasted.map((menu) => Product.fromJson(menu)).toList();
            onDataUpdated(products);
            debugPrint('✅ Background: UI notified with fresh data');
          }
        } else {
          debugPrint('⚠️ Background: API failed ${response.statusCode}');
        }
      } on TimeoutException {
        // ← Suppress timeout errors - this is expected when offline/slow
        debugPrint(
            '⏱️ Background fetch timed out (expected when offline/slow)');
      } catch (e) {
        // Only log unexpected errors
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup')) {
          debugPrint('📵 Background fetch: No internet connection');
        } else {
          debugPrint('⚠️ Background fetch error: $e');
        }
      }
    });
  }

  static Future<List<Product>> getMenus() async {
    try {
      if (!await _isOnline()) {
        debugPrint('📵 Offline: Loading menus from cache');
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          final cachedProducts = await DBHelper.getProductsFromCache();
          debugPrint('✅ Loaded ${cachedProducts.length} products from cache');
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        } else {
          debugPrint('⚠️ No cached menus available');
          return [];
        }
      }

      debugPrint('📡 Online: Fetching menus from server...');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      if (token == null) {
        debugPrint('❌ Token not found, loading from cache');
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          final cachedProducts = await DBHelper.getProductsFromCache();
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        }
        return [];
      }

      final response = await http.get(
        Uri.parse('$baseUrl/menus'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('⏱️ Request timeout after 30s, loading from cache');
          throw TimeoutException('Request timeout');
        },
      );

      debugPrint('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final menusList = data['menus'] as List;
        final menusListCasted =
            menusList.map((menu) => menu as Map<String, dynamic>).toList();

        DBHelper.saveProductsToCache(menusListCasted).then((_) {
          debugPrint('✅ Cached ${menusListCasted.length} products');
        }).catchError((e) {
          debugPrint('⚠️ Failed to cache products: $e');
        });

        debugPrint('✅ Loaded ${menusListCasted.length} products from server');
        return menusListCasted.map((menu) => Product.fromJson(menu)).toList();
      } else {
        debugPrint('❌ API failed with status: ${response.statusCode}');
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          debugPrint('📦 Loading from cache (API failed)');
          final cachedProducts = await DBHelper.getProductsFromCache();
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        }
        return [];
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Timeout exception: $e');
      debugPrint('📦 Loading from cache due to timeout');
      try {
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          final cachedProducts = await DBHelper.getProductsFromCache();
          debugPrint('✅ Loaded ${cachedProducts.length} products from cache');
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        }
      } catch (cacheError) {
        debugPrint('❌ Cache error: $cacheError');
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting menus: $e');
      try {
        final hasCache = await DBHelper.hasProductsCache();
        if (hasCache) {
          debugPrint('📦 Loading from cache (Error fallback)');
          final cachedProducts = await DBHelper.getProductsFromCache();
          debugPrint('✅ Loaded ${cachedProducts.length} products from cache');
          return cachedProducts.map((p) => Product.fromJson(p)).toList();
        } else {
          debugPrint('❌ No cache available');
        }
      } catch (cacheError) {
        debugPrint('❌ Cache error: $cacheError');
      }
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // GET KATEGORIS - OFFLINE FIRST STRATEGY (NEW!)
  // ═══════════════════════════════════════════════════════════

  static Future<List<Kategori>> getKategorisOfflineFirst({
    Function(List<Kategori>)? onDataUpdated,
  }) async {
    List<Kategori> kategoris = [];

    // STEP 1: Load dari cache dulu (INSTANT)
    try {
      final hasCache = await DBHelper.hasKategorisCache();
      if (hasCache) {
        final cachedKategoris = await DBHelper.getKategorisFromCache();
        kategoris = cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        debugPrint(
            '✅ Loaded ${kategoris.length} kategoris from cache (INSTANT)');
        if (kategoris.isNotEmpty) {
          _fetchKategorisInBackground(onDataUpdated);
          return kategoris;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Kategoris cache error: $e');
    }

    // STEP 2: Check connectivity
    if (!await _isOnline()) {
      debugPrint('📵 Offline mode, using kategoris cache only');
      return kategoris;
    }

    // STEP 3: Fetch in background
    _fetchKategorisInBackground(onDataUpdated);
    return kategoris;
  }

  static void _fetchKategorisInBackground(
      Function(List<Kategori>)? onDataUpdated) {
    Future.microtask(() async {
      try {
        // Check connectivity first
        if (!await _isOnline()) {
          debugPrint('📵 Background kategoris fetch skipped: offline');
          return;
        }

        debugPrint('🔄 Background: Fetching kategoris from server...');
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(Constants.tokenKey);
        if (token == null) {
          debugPrint('⚠️ Background kategoris fetch skipped: no token');
          return;
        }

        final response = await http.get(
          Uri.parse('$baseUrl/kategoris'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(
          const Duration(seconds: 15), // ← Reduced timeout for background
          onTimeout: () {
            debugPrint('⏱️ Background kategoris timeout (15s) - using cache');
            throw TimeoutException('Background fetch timeout');
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success']) {
            final kategorisList = data['kategoris'] as List;
            final kategorisListCasted =
                kategorisList.map((k) => k as Map<String, dynamic>).toList();
            await DBHelper.saveKategorisToCache(kategorisListCasted);
            debugPrint(
                '✅ Background: Cached ${kategorisListCasted.length} kategoris');

            if (onDataUpdated != null) {
              final kategoris =
                  kategorisListCasted.map((k) => Kategori.fromJson(k)).toList();
              onDataUpdated(kategoris);
              debugPrint('✅ Background: Kategoris UI notified');
            }
          }
        } else {
          debugPrint(
              '⚠️ Background: Kategoris API failed ${response.statusCode}');
        }
      } on TimeoutException {
        // ← Suppress timeout errors - this is expected when offline/slow
        debugPrint(
            '⏱️ Background kategoris timed out (expected when offline/slow)');
      } catch (e) {
        // Only log unexpected errors
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup')) {
          debugPrint('📵 Background kategoris: No internet connection');
        } else {
          debugPrint('⚠️ Background kategoris error: $e');
        }
      }
    });
  }

  static Future<List<Kategori>> getKategoris() async {
    try {
      if (!await _isOnline()) {
        debugPrint('📵 Offline: Loading kategoris from cache');
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          debugPrint('✅ Loaded ${cachedKategoris.length} kategoris from cache');
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        } else {
          debugPrint('⚠️ No cached kategoris available');
          return [];
        }
      }

      debugPrint('📡 Online: Fetching kategoris from server');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      if (token == null) {
        debugPrint('❌ Token not found');
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        }
        return [];
      }

      final response = await http.get(
        Uri.parse('$baseUrl/kategoris'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 30), // ← FIXED: 30 seconds timeout!
        onTimeout: () {
          debugPrint('⏱️ Kategoris request timeout');
          throw TimeoutException('Request timeout');
        },
      );

      debugPrint('Kategoris response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final kategorisList = data['kategoris'] as List;
          final kategorisListCasted =
              kategorisList.map((k) => k as Map<String, dynamic>).toList();

          DBHelper.saveKategorisToCache(kategorisListCasted).then((_) {
            debugPrint('✅ Cached ${kategorisListCasted.length} kategoris');
          }).catchError((e) {
            debugPrint('⚠️ Failed to cache kategoris: $e');
          });

          final kategoris =
              kategorisListCasted.map((k) => Kategori.fromJson(k)).toList();
          return kategoris;
        } else {
          debugPrint('❌ API returned success: false');
          final hasCache = await DBHelper.hasKategorisCache();
          if (hasCache) {
            debugPrint('📦 Loading kategoris from cache (API failed)');
            final cachedKategoris = await DBHelper.getKategorisFromCache();
            return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
          }
          return [];
        }
      } else {
        debugPrint('❌ Kategoris API error: ${response.statusCode}');
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          debugPrint('📦 Loading kategoris from cache (Error)');
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        }
        return [];
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Kategoris timeout: $e');
      debugPrint('📦 Loading from cache due to timeout');
      try {
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          debugPrint('✅ Loaded ${cachedKategoris.length} kategoris from cache');
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        }
      } catch (cacheError) {
        debugPrint('❌ Cache error: $cacheError');
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting kategoris: $e');
      try {
        final hasCache = await DBHelper.hasKategorisCache();
        if (hasCache) {
          debugPrint('📦 Loading kategoris from cache (Exception)');
          final cachedKategoris = await DBHelper.getKategorisFromCache();
          debugPrint('✅ Loaded ${cachedKategoris.length} kategoris from cache');
          return cachedKategoris.map((k) => Kategori.fromJson(k)).toList();
        }
      } catch (cacheError) {
        debugPrint('❌ Cache error: $cacheError');
      }
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // GET FREE TABLES & ALL TABLES
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // ORDERS - SAME AS BEFORE
  // ═══════════════════════════════════════════════════════════

  static Future<List<Order>> getOrders({String? filterJenisOrder}) async {
    try {
      // ← TAMBAHKAN: cek offline dulu
      if (!await _isOnline()) {
        debugPrint('📵 Offline: getOrders returning cached offline orders');
        return await _getOfflineOrdersAsOrders();
      }

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
      ).timeout(
        // ← TAMBAHKAN timeout
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ getOrders timeout');
          throw TimeoutException('getOrders timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ordersList = data['orders'] as List;
        return ordersList.map((order) => Order.fromJson(order)).toList();
      } else {
        return [];
      }
    } on TimeoutException {
      debugPrint('⏱️ getOrders timed out, returning offline orders');
      return await _getOfflineOrdersAsOrders();
    } catch (e) {
      debugPrint('Error getting orders: $e');
      return await _getOfflineOrdersAsOrders();
    }
  }

  static Future<List<Order>> _getOfflineOrdersAsOrders() async {
    try {
      final offlineOrders = await DBHelper.getOfflineOrders();
      if (offlineOrders.isEmpty) return [];

      return offlineOrders.map((row) {
        final payload = jsonDecode(row['payload'] as String);
        final items =
            (payload['items'] as List? ?? []).asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return OrderItem(
            id: index,
            orderId: 0,
            menuId: item['menu_id'] ?? 0,
            menuNama: item['nama_produk'] ?? '',
            harga: (item['harga'] as num?)?.toDouble() ?? 0,
            qty: item['qty'] ?? 1,
          );
        }).toList();

        return Order(
          id: 0,
          tokoId: 0,
          userId: 0,
          mejaId: payload['meja_id'],
          mejaNo: null,
          jenisOrder: payload['jenis_order'] ?? 1,
          metodeBayar: payload['metode_bayar'] ?? 1,
          catatan: payload['catatan']?.toString(),
          totalHarga: (payload['total_harga'] as num?)?.toDouble() ?? 0,
          status: 'offline',
          items: items,
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
          kasirNama: 'OFFLINE',
          tokoNama: 'OFFLINE',
          tokoAlamat: '',
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error loading offline orders: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      if (!orderData.containsKey('client_uuid') ||
          orderData['client_uuid'] == null) {
        orderData['client_uuid'] = const Uuid().v4();
      }
      final clientUuid = orderData['client_uuid'] as String;

      if (!await _isOnline()) {
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

      debugPrint('📡 Online: Sending order to server with UUID: $clientUuid');
      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(orderData),
      );

      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        debugPrint('Server error, saving offline');
        await DBHelper.saveOfflineOrder(orderData, clientUuid);
        return {
          'success': false,
          'message': 'Server error. Pesanan disimpan offline.',
          'offline': true,
        };
      }

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Order berhasil dibuat',
          'offline': false,
          'data': responseData['data'],
        };
      } else {
        await DBHelper.saveOfflineOrder(orderData, clientUuid);
        return {
          'success': false,
          'message': '${responseData['message']}. Pesanan disimpan offline.',
          'offline': true,
        };
      }
    } catch (e) {
      debugPrint('❌ Error creating order: $e');
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

  static Future<Map<String, dynamic>> updateOrder(
    int orderId,
    Map<String, dynamic> orderData,
  ) async {
    if (!await _isOnline()) {
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
      if (response.body.trim().startsWith('<!DOCTYPE') ||
          response.body.trim().startsWith('<html')) {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}.',
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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

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
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Order.fromJson(data['order']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PENGELUARAN - SAME AS BEFORE
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getPengeluaran({
    String? search,
    String? tanggalAwal,
    String? tanggalAkhir,
    String? namaPengeluaranFilter,
  }) async {
    if (!await _isOnline()) {
      debugPrint('📵 Offline: Loading pengeluaran from cache');
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
        };
      } else {
        return {
          'success': false,
          'message': 'Tidak ada data cache. Hubungkan internet untuk sync.',
          'offline': true,
        };
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);
      String url = '$baseUrl/pengeluaran';
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> createPengeluaran(
    Map<String, dynamic> pengeluaranData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(Constants.tokenKey);

      if (!pengeluaranData.containsKey('client_uuid') ||
          pengeluaranData['client_uuid'] == null) {
        pengeluaranData['client_uuid'] = const Uuid().v4();
      }
      final clientUuid = pengeluaranData['client_uuid'] as String;
      if (!await _isOnline()) {
        await DBHelper.saveOfflinePengeluaran(pengeluaranData, clientUuid);
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
          'offline': false,
          'data': responseData['data'],
        };
      } else {
        await DBHelper.saveOfflinePengeluaran(pengeluaranData, clientUuid);
        await DBHelper.addPengeluaranToCache(pengeluaranData);
        return {
          'success': false,
          'message': '${responseData['message']}. Disimpan offline.',
          'offline': true,
        };
      }
    } catch (e) {
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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> updatePengeluaran(
    int pengeluaranId,
    Map<String, dynamic> pengeluaranData,
  ) async {
    if (!await _isOnline()) {
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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

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
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // RIWAYAT - SAME AS BEFORE
  // ═══════════════════════════════════════════════════════════

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
      if (token == null) throw Exception('Token tidak ditemukan');
      Map<String, String> queryParams = {'page': page.toString()};
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
      if (token == null) throw Exception('Token tidak ditemukan');
      Map<String, String> queryParams = {};
      if (tanggalDari != null) queryParams['tanggal_dari'] = tanggalDari;
      if (tanggalSampai != null) queryParams['tanggal_sampai'] = tanggalSampai;
      final uri = Uri.parse('$baseUrl/riwayat/summary/stats')
          .replace(queryParameters: queryParams);
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
      } else if (response.statusCode == 404) {
        throw Exception('Endpoint summary tidak ditemukan.');
      } else {
        throw Exception('Gagal memuat summary: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRiwayatDetail(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('Token tidak ditemukan');
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
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // LOGOUT & RAW
  // ═══════════════════════════════════════════════════════════

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
