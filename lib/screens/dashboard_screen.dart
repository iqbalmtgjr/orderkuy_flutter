import 'package:flutter/material.dart';
import 'package:orderkuy_kasir/screens/pengeluaran_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'pesanan_screen.dart';
import 'printer_setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  String _userName = '';
  String _userRole = '';
  String _tokoNama = '';
  bool _isLoading = true;

  // Stats data
  double _uangDiOutlet = 0;
  double _pengeluaran = 0;
  double _transfer = 0;
  double _cash = 0;

  // Nullable animations to avoid LateInitializationError
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadUserData();
    _loadDashboardStats();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animationController!, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');

      if (userJson != null) {
        final user = jsonDecode(userJson);
        setState(() {
          _userName = user['name'] ?? 'Kasir';
          _userRole = user['role'] ?? 'kasir';
          _tokoNama = user['toko_nama'] ?? 'OrderKuy!';
        });
        _animationController?.forward();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadDashboardStats() async {
    setState(() => _isLoading = true);

    try {
      // Panggil API untuk get dashboard stats
      final response = await ApiService.getDashboardStats();

      if (response['success']) {
        final data = response['data'];
        setState(() {
          _uangDiOutlet = (data['uang_di_outlet'] ?? 0).toDouble();
          _pengeluaran = (data['pengeluaran'] ?? 0).toDouble();
          _transfer = (data['transfer'] ?? 0).toDouble();
          _cash = (data['cash'] ?? 0).toDouble();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading dashboard stats: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Konfirmasi Logout'),
          ],
        ),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red.shade900,
                    Colors.red.shade700,
                    Colors.orange.shade600,
                  ],
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red.shade900,
                    Colors.red.shade700,
                    Colors.orange.shade600,
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Custom App Bar
                    _buildCustomAppBar(),

                    // Main Content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(top: 20),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(30),
                            topRight: Radius.circular(30),
                          ),
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnimation ??
                              const AlwaysStoppedAnimation(1.0),
                          child: SlideTransition(
                              position: _slideAnimation ??
                                  const AlwaysStoppedAnimation(Offset.zero),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(24.0),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 900),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildWelcomeText(),
                                        const SizedBox(height: 24),
                                        _buildStatsCards(),
                                        const SizedBox(height: 32),
                                        const Text(
                                          'Menu Utama',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildMenuGrid(),
                                        const SizedBox(height: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          // Avatar with Animation
          Hero(
            tag: 'user_avatar',
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : 'K',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Store Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tokoNama,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _userRole.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Logout Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeText() {
    final hour = DateTime.now().hour;
    String greeting = 'Selamat Pagi';
    if (hour >= 12 && hour < 15) {
      greeting = 'Selamat Siang';
    } else if (hour >= 15 && hour < 18) {
      greeting = 'Selamat Sore';
    } else if (hour >= 18) {
      greeting = 'Selamat Malam';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _userName,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;

    if (isTablet) {
      return GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: [
          _buildStatCard(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Uang di Outlet',
            value: _formatRupiah(_uangDiOutlet),
            subtitle: 'Hari ini',
            color: Colors.green,
          ),
          _buildStatCard(
            icon: Icons.receipt_long_rounded,
            title: 'Pengeluaran',
            value: _formatRupiah(_pengeluaran),
            subtitle: 'Hari ini',
            color: Colors.orange,
          ),
          _buildStatCard(
            icon: Icons.credit_card_rounded,
            title: 'Transfer',
            value: _formatRupiah(_transfer),
            subtitle: 'Hari ini',
            color: Colors.blue,
          ),
          _buildStatCard(
            icon: Icons.payments_rounded,
            title: 'Cash',
            value: _formatRupiah(_cash),
            subtitle: 'Hari ini',
            color: Colors.purple,
          ),
        ],
      );
    }

    // layout lama (2 kolom) untuk mobile
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Uang di Outlet',
                value: _formatRupiah(_uangDiOutlet),
                subtitle: 'Hari ini',
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.receipt_long_rounded,
                title: 'Pengeluaran',
                value: _formatRupiah(_pengeluaran),
                subtitle: 'Hari ini',
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.credit_card_rounded,
                title: 'Transfer',
                value: _formatRupiah(_transfer),
                subtitle: 'Hari ini',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.payments_rounded,
                title: 'Cash',
                value: _formatRupiah(_cash),
                subtitle: 'Hari ini',
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    )}';
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    final width = MediaQuery.of(context).size.width;
    // Breakpoint sederhana: <=600 mobile, >600 tablet/desktop [web:5][web:9]
    int crossAxisCount = 2;
    double childAspectRatio = 1.0;

    if (width > 600 && width <= 1024) {
      crossAxisCount = 3; // tablet
      childAspectRatio = 1.1;
    } else if (width > 1024) {
      crossAxisCount = 4; // desktop / tablet besar
      childAspectRatio = 1.1;
    }

    final items = [
      {
        'icon': Icons.point_of_sale_rounded,
        'title': 'Kasir',
        'subtitle': 'Buat Transaksi Baru',
        'gradient': LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade700, Colors.red.shade900],
        ),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PesananScreen()),
          );
        },
      },
      {
        'icon': Icons.print_rounded,
        'title': 'Printer',
        'subtitle': 'Kelola Printer',
        'gradient': LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange.shade600, Colors.orange.shade800],
        ),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PrinterSetupScreen()),
          );
        },
      },
      {
        'icon': Icons.money_off_csred_rounded,
        'title': 'Pengeluaran',
        'subtitle': 'Catat Pengeluaran',
        'gradient': LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade800],
        ),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PengeluaranScreen()),
          );
        },
      },
      {
        'icon': Icons.history_rounded,
        'title': 'Riwayat',
        'subtitle': 'Lihat Transaksi',
        'gradient': LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.purple.shade600, Colors.purple.shade800],
        ),
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Fitur dalam pengembangan'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.settings_rounded,
        'title': 'Pengaturan',
        'subtitle': 'Atur Aplikasi',
        'gradient': LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade600, Colors.teal.shade800],
        ),
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Fitur dalam pengembangan'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildModernMenuCard(
          icon: item['icon'] as IconData,
          title: item['title'] as String,
          subtitle: item['subtitle'] as String,
          gradient: item['gradient'] as Gradient,
          onTap: item['onTap'] as VoidCallback,
        );
      },
    );
  }

  Widget _buildModernMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
