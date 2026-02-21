import 'package:flutter/material.dart';
import 'package:orderkuy_kasir/screens/pengeluaran_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'pesanan_screen.dart';
import 'riwayat_screen.dart';
import 'printer_setup_screen.dart';
import 'absensi_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HELPER
// Semua ukuran dihitung relatif terhadap lebar layar,
// sehingga tampilan konsisten di hp kecil (320px) maupun tablet (768px+).
// ─────────────────────────────────────────────────────────────────────────────
class _R {
  final double sw; // screen width
  final double sh; // screen height

  const _R(this.sw, this.sh);

  // ── Breakpoints ──
  bool get isPhone => sw < 480;
  bool get isTablet => sw >= 480 && sw < 768;
  bool get isDesktop => sw >= 768;

  // ── Spacing ──
  double get pagePadH => sw * 0.044; // ~16 pada 360px, ~20 pada 450px
  double get pagePadV => sh * 0.018;
  double get cardRadius => sw * 0.056; // ~20 pada 360px
  double get sectionGap => sh * 0.022;

  // ── Lebar konten header dibatasi agar tidak melar di tablet/desktop ──
  // Konten header di-center dengan maxWidth ini
  double get headerContentMaxW => 520.0;

  // ── Typography — clamp lebih ketat di tablet ──
  double get fontXs => (sw * 0.028).clamp(10, 12); // 10–12
  double get fontSm => (sw * 0.030).clamp(11, 13); // 11–13
  double get fontMd => (sw * 0.034).clamp(13, 15); // 13–15
  double get fontLg => (sw * 0.044).clamp(15, 19); // 15–19
  double get fontXl => (sw * 0.065).clamp(22, 30); // 22–30 (nominal saldo)
  double get fontTitle => (sw * 0.052).clamp(17, 22); // 17–22 (nama toko)

  // ── Icon ──
  double get iconSm => (sw * 0.030).clamp(12, 15);
  double get iconMd => (sw * 0.048).clamp(17, 22);
  double get iconLg => (sw * 0.060).clamp(20, 26);

  // ── Avatar / Menu Icon ──
  double get avatarSize => (sw * 0.100).clamp(36, 46);
  double get menuIconBox => (sw * 0.130).clamp(44, 58);
  double get menuIconSize => (sw * 0.058).clamp(19, 25);

  // ── Card ──
  double get cardPad => sw * 0.05;
  double get saldoCardMarginH => sw * 0.04;

  // ── Grid ──
  int get menuCrossAxis => isDesktop ? 6 : (isTablet ? 5 : 4);
  double get menuAspect => isDesktop ? 0.85 : (isTablet ? 0.82 : 0.78);
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
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
  bool _saldoVisible = true;

  double _uangDiOutlet = 0;
  double _pengeluaran = 0;
  double _transfer = 0;
  double _cash = 0;

  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOut,
    );
    _loadUserData();
    _loadDashboardStats();
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
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final r = _R(
      MediaQuery.of(context).size.width,
      MediaQuery.of(context).size.height,
    );
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r.cardRadius)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.logout, color: Colors.red, size: r.iconMd),
            ),
            SizedBox(width: r.pagePadH * 0.6),
            Text('Konfirmasi Logout',
                style:
                    TextStyle(fontSize: r.fontMd, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text('Apakah Anda yakin ingin keluar?',
            style: TextStyle(fontSize: r.fontSm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(fontSize: r.fontSm)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Logout', style: TextStyle(fontSize: r.fontSm)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _formatRupiah(double amount) {
    final formatted = amount.toStringAsFixed(0);
    return 'Rp${formatted.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    )}';
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD ROOT
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final r = _R(size.width, size.height);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: _isLoading
          ? Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeaderWithCard(r)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          r.pagePadH, r.sectionGap, r.pagePadH, 0),
                      child: _buildMenuSection(r),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          r.pagePadH, r.sectionGap * 0.8, r.pagePadH, 0),
                      child: _buildTransactionSummary(r),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: r.sectionGap * 2)),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HEADER + SALDO CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeaderWithCard(_R r) {
    final hour = DateTime.now().hour;
    String greeting = 'Selamat Pagi';
    if (hour >= 12 && hour < 15)
      greeting = 'Selamat Siang';
    else if (hour >= 15 && hour < 18)
      greeting = 'Selamat Sore';
    else if (hour >= 18) greeting = 'Selamat Malam';

    // Tinggi lengkungan di bawah header — lebih besar = lebih cembung
    final curveHeight = r.sw * 0.09;

    return ClipPath(
      clipper: _BottomWaveClipper(curveHeight),
      child: Container(
        // Tambah padding bawah ekstra agar konten tidak terpotong clipper
        padding: EdgeInsets.only(bottom: curveHeight),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFC62828), Color(0xFFE53935), Color(0xFFEF5350)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // ── Dekorasi Lingkaran ──
            Positioned(
              top: -r.sw * 0.14,
              right: -r.sw * 0.14,
              child: _decorCircle(r.sw * 0.56, 0.05),
            ),
            Positioned(
              top: r.sw * 0.18,
              right: r.sw * 0.18,
              child: _decorCircle(r.sw * 0.25, 0.06),
            ),
            Positioned(
              top: r.sw * 0.05,
              left: -r.sw * 0.08,
              child: _decorCircle(r.sw * 0.28, 0.04),
            ),

            SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  // Batasi lebar konten header — tidak melar di tablet
                  constraints: BoxConstraints(maxWidth: r.headerContentMaxW),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Bar ──
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            r.pagePadH, r.pagePadV, r.pagePadH, 0),
                        child: Row(
                          children: [
                            _buildAvatar(r),
                            SizedBox(width: r.pagePadH * 0.6),
                            Expanded(child: _buildGreeting(r, greeting)),
                            _buildLogoutBtn(r),
                          ],
                        ),
                      ),

                      SizedBox(height: r.pagePadV * 0.9),

                      // ── Nama Toko + Role ──
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: r.pagePadH),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                _tokoNama,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: r.fontTitle,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: r.pagePadH * 0.5),
                            _buildRoleBadge(r),
                          ],
                        ),
                      ),

                      SizedBox(height: r.pagePadV * 1.1),

                      // ── Saldo Card ──
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: r.saldoCardMarginH),
                        child: _buildSaldoCard(r),
                      ),

                      SizedBox(height: r.pagePadV * 1.2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorCircle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      );

  Widget _buildAvatar(_R r) {
    return Container(
      width: r.avatarSize,
      height: r.avatarSize,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withOpacity(0.4), width: r.sw * 0.004),
      ),
      child: Center(
        child: Text(
          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'K',
          style: TextStyle(
            fontSize: r.fontLg * 0.85,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(_R r, String greeting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: TextStyle(
            fontSize: r.fontXs,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        Text(
          _userName,
          style: TextStyle(
            fontSize: r.fontMd * 1.05,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildLogoutBtn(_R r) {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        padding: EdgeInsets.all(r.sw * 0.022),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(r.sw * 0.03),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Icon(Icons.logout_rounded, color: Colors.white, size: r.iconMd),
      ),
    );
  }

  Widget _buildRoleBadge(_R r) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: r.pagePadH * 0.6, vertical: r.pagePadV * 0.25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(r.sw * 0.05),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Text(
        _userRole.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: r.fontXs * 0.9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Saldo Card ──
  Widget _buildSaldoCard(_R r) {
    return Container(
      padding: EdgeInsets.all(r.cardPad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r.cardRadius * 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: r.sw * 0.066,
            offset: Offset(0, r.sw * 0.028),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + Refresh
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: r.sw * 0.022,
                    height: r.sw * 0.022,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: r.sw * 0.016),
                  Text(
                    'Uang di Outlet',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: r.fontSm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _loadDashboardStats,
                child: Container(
                  padding: EdgeInsets.all(r.sw * 0.018),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(r.sw * 0.022),
                  ),
                  child: Icon(Icons.refresh_rounded,
                      color: Colors.grey.shade400, size: r.iconSm * 1.1),
                ),
              ),
            ],
          ),

          SizedBox(height: r.pagePadV * 0.55),

          // Nominal + Toggle
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _saldoVisible
                        ? _formatRupiah(_uangDiOutlet)
                        : 'Rp ••••••••',
                    style: TextStyle(
                      color: const Color(0xFF111111),
                      fontSize: r.fontXl,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                ),
              ),
              SizedBox(width: r.pagePadH * 0.5),
              GestureDetector(
                onTap: () => setState(() => _saldoVisible = !_saldoVisible),
                child: Container(
                  padding: EdgeInsets.all(r.sw * 0.018),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(r.sw * 0.022),
                  ),
                  child: Icon(
                    _saldoVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey.shade500,
                    size: r.iconMd * 0.9,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: r.pagePadV * 0.88),
          Divider(color: Colors.grey.shade100, height: 1),
          SizedBox(height: r.pagePadV * 0.77),

          // Stats: Cash | Transfer | Keluar
          Row(
            children: [
              _buildInlineStat(
                r: r,
                label: 'Cash',
                value: _saldoVisible ? _formatRupiah(_cash) : 'Rp ••••',
                color: const Color(0xFF2E7D32),
                icon: Icons.payments_rounded,
              ),
              _buildVDivider(r),
              _buildInlineStat(
                r: r,
                label: 'Transfer',
                value: _saldoVisible ? _formatRupiah(_transfer) : 'Rp ••••',
                color: const Color(0xFF1565C0),
                icon: Icons.credit_card_rounded,
              ),
              _buildVDivider(r),
              _buildInlineStat(
                r: r,
                label: 'Keluar',
                value: _saldoVisible ? _formatRupiah(_pengeluaran) : 'Rp ••••',
                color: const Color(0xFFE65100),
                icon: Icons.receipt_long_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVDivider(_R r) => Container(
        width: 1,
        height: r.sw * 0.1,
        color: Colors.grey.shade200,
        margin: EdgeInsets.symmetric(horizontal: r.sw * 0.02),
      );

  Widget _buildInlineStat({
    required _R r,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: r.iconSm, color: color),
              SizedBox(width: r.sw * 0.01),
              Text(
                label,
                style: TextStyle(
                  fontSize: r.fontXs,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: r.sw * 0.012),
          Text(
            value,
            style: TextStyle(
              fontSize: r.fontSm * 0.95,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MENU SECTION
  // ═══════════════════════════════════════════════════════════

  Widget _buildMenuSection(_R r) {
    final menus = [
      _MenuData(
        icon: Icons.point_of_sale_rounded,
        label: 'Kasir',
        color: const Color(0xFFD32F2F),
        bgColor: const Color(0xFFFFF0F0),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PesananScreen())),
      ),
      _MenuData(
        icon: Icons.history_rounded,
        label: 'Riwayat',
        color: const Color(0xFF7B1FA2),
        bgColor: const Color(0xFFF5F0FF),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const RiwayatScreen())),
      ),
      _MenuData(
        icon: Icons.money_off_csred_rounded,
        label: 'Pengeluaran',
        color: const Color(0xFF1565C0),
        bgColor: const Color(0xFFEFF4FF),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PengeluaranScreen())),
      ),
      _MenuData(
        icon: Icons.fingerprint_rounded,
        label: 'Absensi',
        color: const Color(0xFF2E7D32),
        bgColor: const Color(0xFFEFF7EF),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AbsensiScreen())),
      ),
      _MenuData(
        icon: Icons.print_rounded,
        label: 'Printer',
        color: const Color(0xFFE65100),
        bgColor: const Color(0xFFFFF3EE),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PrinterSetupScreen())),
      ),
    ];

    return _buildCard(
      r: r,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(r, 'Menu', '${menus.length} fitur'),
          SizedBox(height: r.pagePadV * 0.9),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: r.menuCrossAxis,
              crossAxisSpacing: r.sw * 0.02,
              mainAxisSpacing: r.sw * 0.02,
              childAspectRatio: r.menuAspect,
            ),
            itemCount: menus.length,
            itemBuilder: (_, i) => _buildMenuIcon(r, menus[i]),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuIcon(_R r, _MenuData menu) {
    return GestureDetector(
      onTap: menu.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: r.menuIconBox,
            height: r.menuIconBox,
            decoration: BoxDecoration(
              color: menu.bgColor,
              borderRadius: BorderRadius.circular(r.sw * 0.044),
              boxShadow: [
                BoxShadow(
                  color: menu.color.withOpacity(0.12),
                  blurRadius: r.sw * 0.022,
                  offset: Offset(0, r.sw * 0.008),
                ),
              ],
            ),
            child: Icon(menu.icon, color: menu.color, size: r.menuIconSize),
          ),
          SizedBox(height: r.sw * 0.018),
          Text(
            menu.label,
            style: TextStyle(
              fontSize: r.fontXs,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF444444),
              letterSpacing: -0.1,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // RINGKASAN TRANSAKSI
  // ═══════════════════════════════════════════════════════════

  Widget _buildTransactionSummary(_R r) {
    final today = DateTime.now();
    final dateStr = '${today.day} ${_monthName(today.month)} ${today.year}';
    final totalMasuk = _cash + _transfer;
    final pctCash = totalMasuk > 0 ? _cash / totalMasuk : 0.5;

    return _buildCard(
      r: r,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ringkasan Hari Ini',
                style: TextStyle(
                  fontSize: r.fontMd,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                  letterSpacing: -0.3,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: r.pagePadH * 0.56, vertical: r.pagePadV * 0.22),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F7),
                  borderRadius: BorderRadius.circular(r.sw * 0.05),
                ),
                child: Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: r.fontXs,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: r.pagePadV * 0.88),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(r.sw * 0.022),
            child: Row(
              children: [
                Expanded(
                  flex: (pctCash * 100).round().clamp(1, 99),
                  child: Container(
                      height: r.sw * 0.022, color: const Color(0xFF2E7D32)),
                ),
                Expanded(
                  flex: ((1 - pctCash) * 100).round().clamp(1, 99),
                  child: Container(
                      height: r.sw * 0.022, color: const Color(0xFF1565C0)),
                ),
              ],
            ),
          ),

          SizedBox(height: r.sw * 0.018),

          // Legend
          Row(
            children: [
              _buildLegendDot(r, const Color(0xFF2E7D32), 'Cash'),
              SizedBox(width: r.pagePadH),
              _buildLegendDot(r, const Color(0xFF1565C0), 'Transfer'),
            ],
          ),

          SizedBox(height: r.pagePadV * 0.88),

          // Dua kartu
          Row(
            children: [
              _buildSummaryItem(
                r: r,
                label: 'Total Masuk',
                value: _saldoVisible ? _formatRupiah(totalMasuk) : 'Rp ••••••',
                color: const Color(0xFF2E7D32),
                icon: Icons.arrow_downward_rounded,
              ),
              SizedBox(width: r.pagePadH * 0.56),
              _buildSummaryItem(
                r: r,
                label: 'Pengeluaran',
                value:
                    _saldoVisible ? _formatRupiah(_pengeluaran) : 'Rp ••••••',
                color: const Color(0xFFE65100),
                icon: Icons.arrow_upward_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(_R r, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: r.sw * 0.022,
          height: r.sw * 0.022,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: r.sw * 0.014),
        Text(
          label,
          style: TextStyle(
            fontSize: r.fontXs,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem({
    required _R r,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: r.pagePadH * 0.72, vertical: r.pagePadV * 0.66),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(r.cardRadius * 0.7),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(r.sw * 0.016),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: r.iconSm, color: color),
            ),
            SizedBox(width: r.pagePadH * 0.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: r.fontXs,
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: r.sw * 0.006),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: r.fontSm,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // REUSABLE HELPERS
  // ═══════════════════════════════════════════════════════════

  Widget _buildCard({required _R r, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(r.cardPad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: r.sw * 0.033,
            offset: Offset(0, r.sw * 0.006),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(_R r, String title, String sub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: r.fontMd,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
            letterSpacing: -0.3,
          ),
        ),
        Text(
          sub,
          style: TextStyle(
            fontSize: r.fontXs,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return names[month];
  }
}

// ─────────────────────────────────────────────
// Custom clipper: bagian bawah header melengkung ke bawah (concave wave)
// seperti Wondr BNI — elegant dan memberi kedalaman visual.
// ─────────────────────────────────────────────
class _BottomWaveClipper extends CustomClipper<Path> {
  final double curveHeight;
  _BottomWaveClipper(this.curveHeight);

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - curveHeight);
    // Lengkungan quadratic — titik kontrol di tengah bawah
    path.quadraticBezierTo(
      size.width / 2,
      size.height + curveHeight,
      size.width,
      size.height - curveHeight,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BottomWaveClipper old) => old.curveHeight != curveHeight;
}

// ─────────────────────────────────────────────
class _MenuData {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _MenuData({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
}
