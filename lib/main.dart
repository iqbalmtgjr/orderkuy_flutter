import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io' show Platform;

// Import sqflite
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/sync_service.dart';
import 'core/database/db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================
  // PENTING: Initialize sqflite untuk Windows/Linux
  // ========================================
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('✅ Using sqflite_common_ffi for ${Platform.operatingSystem}');
  }

  // Initialize locale Indonesia
  await initializeDateFormatting('id_ID', null);

  // Initialize database
  try {
    await DBHelper.db;
    debugPrint('✅ Database initialized');
  } catch (e) {
    debugPrint('❌ Database initialization error: $e');
  }

  // Start auto-sync listener
  try {
    SyncService.startAutoSync();
    debugPrint('✅ Auto-sync listener started');
  } catch (e) {
    debugPrint('⚠️ Auto-sync error: $e');
  }

  // Try to sync products on app start (if online)
  try {
    final result = await SyncService.syncProducts();
    if (result['success']) {
      debugPrint('✅ ${result['message']}');
    } else {
      debugPrint('⚠️ ${result['message']}');
    }
  } catch (e) {
    debugPrint('⚠️ Error syncing products on startup: $e');
  }

  // Try to sync pending orders on app start (if online)
  try {
    final result = await SyncService.syncOrders();
    if (result['success'] && result['synced'] > 0) {
      debugPrint('✅ ${result['synced']} offline orders synced on startup');
    }
  } catch (e) {
    debugPrint('⚠️ Error syncing orders on startup: $e');
  }

  runApp(const OrderKuyApp());
}

class OrderKuyApp extends StatelessWidget {
  const OrderKuyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrderKuy!',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Tampilkan splash selama 2 detik
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;

    // Jika sudah login (ada token), langsung ke Dashboard
    // Jika belum, ke Login Screen
    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon aplikasi
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.network(
                'https://orderkuy.indotechconsulting.com/assets/img/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.restaurant_menu,
                    size: 80,
                    color: Colors.red.shade700,
                  );
                },
              ),
            ),
            const SizedBox(height: 30),

            // Nama aplikasi
            const Text(
              'OrderKuy!',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              'Aplikasi Kasir - ${Platform.operatingSystem.toUpperCase()}',
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 50),

            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 20),

            const Text(
              'Memuat...',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
