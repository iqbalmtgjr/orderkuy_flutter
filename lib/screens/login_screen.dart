import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../services/api_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _emailFocused = false;
  bool _passwordFocused = false;

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;

  late Animation<double> _logoSlide;
  late Animation<double> _logoFade;
  late Animation<double> _titleSlide;
  late Animation<double> _titleFade;
  late Animation<double> _cardSlide;
  late Animation<double> _cardFade;
  late Animation<double> _pulse = const AlwaysStoppedAnimation(1.0);
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();

    // ── Entry animation (semua elemen muncul berurutan) ──
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _logoSlide = Tween<double>(begin: -40, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    // ── Pulse: lingkaran dekorasi bergerak perlahan ──
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // ── Shimmer pada tombol login ──
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Focus listeners untuk efek highlight field
    _emailFocus.addListener(() {
      setState(() => _emailFocused = _emailFocus.hasFocus);
    });
    _passwordFocus.addListener(() {
      setState(() => _passwordFocused = _passwordFocus.hasFocus);
    });

    // Mulai animasi entry
    _entryController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final result = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      setState(() => _isLoading = false);
      if (!mounted) return;

      if (result['success']) {
        HapticFeedback.mediumImpact();
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const DashboardScreen(),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else {
        HapticFeedback.heavyImpact();
        _showError(result['message'] ?? 'Login gagal');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      _showError('Koneksi bermasalah. Coba lagi.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFF0a1a2e),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF050d1a),
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // ── Background layer ──
            _buildBackground(size),

            // ── Konten ──
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 440 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 0 : 24,
                      vertical: 32,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: size.height * 0.04),
                          _buildLogo(),
                          const SizedBox(height: 28),
                          _buildTitle(),
                          const SizedBox(height: 40),
                          _buildFormCard(),
                          const SizedBox(height: 24),
                          _buildFooter(),
                          SizedBox(height: size.height * 0.04),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BACKGROUND: geometric circles + gradient
  // ─────────────────────────────────────────────

  Widget _buildBackground(Size size) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // Base gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0d1e3a),
                  Color(0xFF152848),
                  Color(0xFF050d1a),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Lingkaran besar kiri atas — pulse
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Positioned(
              top: -size.width * 0.25,
              left: -size.width * 0.2,
              child: Transform.scale(
                scale: _pulse.value ?? 1.0,
                child: Container(
                  width: size.width * 0.85,
                  height: size.width * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF1a315b).withOpacity(0.28),
                        const Color(0xFF1a315b).withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Lingkaran kecil kanan tengah
          Positioned(
            top: size.height * 0.38,
            right: -size.width * 0.18,
            child: Container(
              width: size.width * 0.55,
              height: size.width * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2a4a7f).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Lingkaran bawah kiri
          Positioned(
            bottom: -size.width * 0.15,
            left: -size.width * 0.1,
            child: Container(
              width: size.width * 0.6,
              height: size.width * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF1a315b).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Grid dots pattern
          CustomPaint(
            size: size,
            painter: _DotGridPainter(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LOGO
  // ─────────────────────────────────────────────

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _logoSlide.value),
        child: Opacity(
          opacity: _logoFade.value.clamp(0.0, 1.0),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1a315b).withOpacity(0.5),
                  blurRadius: 32,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                'https://orderkuy.indotechconsulting.com/assets/img/btb.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.restaurant_menu_rounded,
                    size: 48,
                    color: Color(0xFF1a315b),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TITLE
  // ─────────────────────────────────────────────

  Widget _buildTitle() {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _titleSlide.value),
        child: Opacity(
          opacity: _titleFade.value.clamp(0.0, 1.0),
          child: Column(
            children: [
              // "OrderKuy!" dengan gaya display
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFFFFF), Color(0xFFCDD8F0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  'Kasvo',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.2,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.12), width: 1),
                ),
                child: const Text(
                  'Sistem Kasir Digital',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // FORM CARD — glassmorphism
  // ─────────────────────────────────────────────

  Widget _buildFormCard() {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _cardSlide.value),
        child: Opacity(
          opacity: _cardFade.value.clamp(0.0, 1.0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            decoration: BoxDecoration(
              // Glassmorphism: putih semi-transparan
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                const Text(
                  'Masuk ke Akun',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gunakan email & password kasir Anda',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.45),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 28),

                // Email Field
                _buildField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  isFocused: _emailFocused,
                  label: 'Email',
                  hint: 'kasir@example.com',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email wajib diisi';
                    if (!v.contains('@')) return 'Format email tidak valid';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Password Field
                _buildField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  isFocused: _passwordFocused,
                  label: 'Password',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: GestureDetector(
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    child: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password wajib diisi';
                    if (v.length < 6) return 'Minimal 6 karakter';
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // Login Button — shimmer effect
                _buildLoginButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isFocused,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF2a4a7f).withOpacity(0.7)
              : Colors.white.withOpacity(0.1),
          width: isFocused ? 1.5 : 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: const Color(0xFF2a4a7f),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isFocused
                ? const Color(0xFF7a9fd4)
                : Colors.white.withOpacity(0.4),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 15,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Icon(
              icon,
              color: isFocused
                  ? const Color(0xFF2a4a7f)
                  : Colors.white.withOpacity(0.35),
              size: 20,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: suffixIcon,
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          errorStyle: const TextStyle(
            color: Color(0xFF7a9fd4),
            fontSize: 11,
          ),
        ),
        validator: validator,
        onFieldSubmitted: (_) {
          if (label == 'Email') {
            FocusScope.of(context).requestFocus(_passwordFocus);
          } else {
            _login();
          }
        },
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0f2040), Color(0xFF1a315b)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            )
          : GestureDetector(
              onTap: _login,
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0f2040),
                        Color(0xFF1a315b),
                        Color(0xFF243f70),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1a315b).withOpacity(0.55),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Shimmer layer
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Transform.translate(
                          offset: Offset(_shimmer.value * 200, 0),
                          child: Container(
                            width: 80,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.0),
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Label
                      const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Masuk',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────
  // FOOTER
  // ─────────────────────────────────────────────

  Widget _buildFooter() {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (_, __) => Opacity(
        opacity: (_cardFade.value * 0.7).clamp(0.0, 1.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 1,
                  color: Colors.white.withOpacity(0.15),
                ),
                const SizedBox(width: 12),
                Text(
                  'Hanya untuk akun kasir',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 32,
                  height: 1,
                  color: Colors.white.withOpacity(0.15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '© 2025 Kasvo · Indotech Consulting',
              style: TextStyle(
                color: Colors.white.withOpacity(0.18),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOT GRID PAINTER — titik-titik halus di background
// ─────────────────────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    const dotRadius = 1.2;

    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        // Variasi opacity berdasarkan posisi untuk efek gradient
        final distFromCenter = math.sqrt(
          math.pow(x - size.width / 2, 2) + math.pow(y - size.height * 0.4, 2),
        );
        final maxDist = math.sqrt(
          math.pow(size.width / 2, 2) + math.pow(size.height * 0.4, 2),
        );
        final opacity =
            (0.03 + 0.05 * (1 - distFromCenter / maxDist)).clamp(0.01, 0.08);
        canvas.drawCircle(
          Offset(x, y),
          dotRadius,
          paint..color = Colors.white.withOpacity(opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
