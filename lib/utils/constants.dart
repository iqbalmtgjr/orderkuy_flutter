class Constants {
  // ============================================
  // PRODUCTION - Domain Online
  // ============================================
  static const String baseUrl = 'https://orderkuy.indotechconsulting.com/api';

  // ============================================
  // DEVELOPMENT - Local IP (Commented)
  // ============================================
  // static const String baseUrl = 'http://192.168.1.100:8000/api';

  // Endpoints
  static const String loginEndpoint = '/login';
  static const String logoutEndpoint = '/logout';
  static const String menusEndpoint = '/menus';
  static const String mejasEndpoint = '/mejas';
  static const String ordersEndpoint = '/orders';

  // Storage Keys
  static const String tokenKey = 'token';
  static const String userKey = 'user';
  static const String printerAddressKey = 'printer_address';

  // Order Status
  static const String statusPending = 'pending';
  static const String statusPaid = 'paid';
  static const String statusCompleted = 'completed';

  // Jenis Order
  static const int jenisOrderDineIn = 1;
  static const int jenisOrderTakeAway = 2;

  // Metode Bayar
  static const int metodeBayarCash = 1;
  static const int metodeBayarTransfer = 2;
}

/*
CATATAN PENTING:
1. Domain sudah HTTPS ✅
2. Tidak perlu /api jika sudah ada routing di Laravel
3. Pastikan CORS sudah di-enable di Laravel
4. Test API dengan Postman dulu sebelum test di Flutter
*/
