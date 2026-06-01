import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shift_service.dart';
import '../services/print_service.dart';

// ─────────────────────────────────────────────────────────────
// Tema Warna Global
// ─────────────────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF1a315b);
  static const primaryDark = Color(0xFF0f2442);
  static const primarySurface = Color(0xFFe8eef5);
  static const accent = Color(0xFF2E6BE6);
  static const accentLight = Color(0xFFD6E4FF);
  static const success = Color(0xFF1D9E75);
  static const successLight = Color(0xFFE6F7F2);
  static const warning = Color(0xFFBA7517);
  static const warningLight = Color(0xFFFFF4E0);
  static const danger = Color(0xFFA32D2D);
  static const dangerLight = Color(0xFFFCEBEB);
  static const bg = Color(0xFFF4F7FC);
  static const card = Colors.white;
  static const textMain = Color(0xFF0f2442);
  static const textSub = Color(0xFF7A8CA0);
  static const divider = Color(0xFFE8EEF5);
}

// ─────────────────────────────────────────────────────────────
// RupiahInputFormatter — format otomatis saat mengetik
// Contoh: 1000000 → "1.000.000"
// getRawValue() → mengembalikan angka bersih (int)
// ─────────────────────────────────────────────────────────────
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Ambil hanya digit
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Hilangkan leading zeros (kecuali input hanya "0")
    final cleaned = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
    final number = cleaned.isEmpty ? '0' : cleaned;

    // Format dengan titik ribuan
    final formatted = _addThousandSeparator(number);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _addThousandSeparator(String number) {
    return number.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }

  /// Ambil nilai int bersih dari controller yang menggunakan formatter ini
  static int getRawValue(TextEditingController ctrl) {
    final raw = ctrl.text.replaceAll('.', '');
    return int.tryParse(raw) ?? 0;
  }
}

// ─────────────────────────────────────────────────────────────
// ShiftScreen
// ─────────────────────────────────────────────────────────────
class ShiftScreen extends StatefulWidget {
  final int tokoId;
  final int userId;
  final void Function(Map<String, dynamic> user, Map<String, dynamic> shift)?
      onShiftOpened;
  final VoidCallback? onShiftClosed;

  const ShiftScreen({
    super.key,
    required this.tokoId,
    required this.userId,
    this.onShiftOpened,
    this.onShiftClosed,
  });

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _shiftAktif = false;
  bool _isOffline = false;
  Map<String, dynamic>? _shift;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _cekShift();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _cekShift() async {
    setState(() => _loading = true);
    try {
      final res = await ShiftService.cekShiftAktif(
        tokoId: widget.tokoId,
        userId: widget.userId,
      );
      setState(() {
        _shiftAktif = res['shift_aktif'] == true;
        _shift = res['shift'];
        _isOffline = res['offline'] == true;
        _loading = false;
      });
      _animCtrl.forward(from: 0);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 15),
                  SizedBox(width: 8),
                  Text(
                    'Offline — Buka/Tutup shift memerlukan koneksi internet',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? _buildLoading()
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: _shiftAktif ? _buildShiftAktif() : _buildBukaShift(),
                  ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: IconButton(
        icon: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 15),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _shiftAktif ? 'Shift Aktif' : 'Buka Shift',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primaryDark, _C.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildBukaShift() {
    return _BukaShiftForm(
      tokoId: widget.tokoId,
      isOffline: _isOffline,
      onBerhasil: (user, shift) {
        setState(() {
          _shiftAktif = true;
          _shift = shift;
          _isOffline = false;
        });
        _animCtrl.forward(from: 0);
        widget.onShiftOpened?.call(user, shift);
      },
    );
  }

  Widget _buildShiftAktif() {
    return _ShiftAktifView(
      shift: _shift!,
      tokoId: widget.tokoId,
      isOffline: _isOffline,
      onTutup: () {
        setState(() {
          _shiftAktif = false;
          _shift = null;
        });
        _animCtrl.forward(from: 0);
        widget.onShiftClosed?.call();
      },
      onRefresh: _cekShift,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Responsive helpers
// ─────────────────────────────────────────────────────────────
bool _isTablet(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide >= 600;

double _hPad(BuildContext context) => _isTablet(context) ? 40.0 : 20.0;

double _maxContentWidth(BuildContext context) =>
    _isTablet(context) ? 680.0 : double.infinity;

// ─────────────────────────────────────────────────────────────
// Header biru dengan kurva bawah
// ─────────────────────────────────────────────────────────────
class _BlueHeader extends StatelessWidget {
  final Widget child;
  const _BlueHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final screenW = MediaQuery.of(context).size.width;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_C.primaryDark, Color(0xFF1e3a6e)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                  top: -screenW * 0.1,
                  right: -screenW * 0.04,
                  child: _circle(screenW * 0.28, 0.05)),
              Positioned(
                  top: screenW * 0.1,
                  right: screenW * 0.1,
                  child: _circle(screenW * 0.08, 0.06)),
              Positioned(
                  bottom: 40,
                  left: -screenW * 0.03,
                  child: _circle(screenW * 0.12, 0.04)),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: isTablet ? 40.0 : 32.0),
                  child: child,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: CustomPaint(
            size: Size(double.infinity, isTablet ? 40.0 : 32.0),
            painter: _BottomCurvePainter(),
          ),
        ),
      ],
    );
  }

  Widget _circle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      );
}

class _BottomCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _C.bg;
    final path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(size.width / 2, 0, size.width, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────
// Form Buka Shift
// ─────────────────────────────────────────────────────────────
class _BukaShiftForm extends StatefulWidget {
  final int tokoId;
  final bool isOffline;
  final void Function(Map<String, dynamic> user, Map<String, dynamic> shift)
      onBerhasil;

  const _BukaShiftForm({
    required this.tokoId,
    required this.isOffline,
    required this.onBerhasil,
  });

  @override
  State<_BukaShiftForm> createState() => _BukaShiftFormState();
}

class _BukaShiftFormState extends State<_BukaShiftForm> {
  final _pinCtrl = TextEditingController();
  final _nominalCtrl = TextEditingController();
  final _catatanCtrl = TextEditingController(text: 'Open kasir pagi');
  bool _loading = false;
  bool _pinVisible = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _nominalCtrl.dispose();
    _catatanCtrl.dispose();
    super.dispose();
  }

  Future<void> _buka() async {
    if (widget.isOffline) {
      setState(() => _error =
          'Tidak dapat membuka shift saat offline. Hubungkan internet terlebih dahulu.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'PIN wajib diisi');
      return;
    }
    // Ambil nilai bersih dari field nominal (hilangkan titik ribuan)
    final nominal = RupiahInputFormatter.getRawValue(_nominalCtrl);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ShiftService.bukaShift(
        tokoId: widget.tokoId,
        pin: _pinCtrl.text,
        openAmount: nominal,
        catatanBuka: _catatanCtrl.text.isNotEmpty ? _catatanCtrl.text : null,
      );
      if (res['success'] == true) {
        widget.onBerhasil(res['user'], res['shift']);
      } else {
        setState(() => _error = res['message'] ?? 'Gagal membuka shift.');
      }
    } catch (e) {
      setState(() => _error = 'Koneksi gagal. Coba lagi.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final hp = _hPad(context);
    final iconSize = isTablet ? 72.0 : 60.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          _BlueHeader(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: _maxContentWidth(context)),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: hp, vertical: isTablet ? 32 : 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius:
                              BorderRadius.circular(isTablet ? 22 : 18),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.25), width: 1),
                        ),
                        child: Icon(Icons.store_rounded,
                            color: Colors.white, size: isTablet ? 34 : 28),
                      ),
                      SizedBox(height: isTablet ? 16 : 12),
                      Text(
                        'Buka Shift Kasir',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTablet ? 22 : 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Masukkan PIN dan uang awal di laci',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: isTablet ? 13 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _maxContentWidth(context)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 24, hp, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFieldLabel('PIN Kasir'),
                    _buildPinField(
                      controller: _pinCtrl,
                      hint: 'Masukkan PIN',
                      pinVisible: _pinVisible,
                      onToggleVisibility: () =>
                          setState(() => _pinVisible = !_pinVisible),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Uang Awal di Laci'),
                    _buildRupiahField(
                      controller: _nominalCtrl,
                      hint: '0',
                      color: _C.primary,
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Catatan (opsional)'),
                    _buildTextField(
                      controller: _catatanCtrl,
                      hint: 'Open kasir pagi',
                      prefix: const Icon(Icons.notes_rounded,
                          color: _C.primary, size: 18),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      _buildErrorBox(_error!),
                      const SizedBox(height: 14),
                    ],
                    _buildPrimaryButton(
                      label: 'Buka Shift',
                      icon: Icons.play_circle_outline_rounded,
                      loading: _loading,
                      onTap: _buka,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shift Aktif View
// ─────────────────────────────────────────────────────────────
class _ShiftAktifView extends StatelessWidget {
  final Map<String, dynamic> shift;
  final int tokoId;
  final bool isOffline;
  final VoidCallback onTutup;
  final VoidCallback onRefresh;

  const _ShiftAktifView({
    required this.shift,
    required this.tokoId,
    required this.isOffline,
    required this.onTutup,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final hp = _hPad(context);

    return SingleChildScrollView(
      child: Column(
        children: [
          _BlueHeader(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: _maxContentWidth(context)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      hp, isTablet ? 24 : 12, hp, isTablet ? 24 : 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D9E75).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFF1D9E75).withOpacity(0.4),
                              width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                color: Color(0xFF4ECFA8), size: 7),
                            SizedBox(width: 6),
                            Text(
                              'SHIFT AKTIF',
                              style: TextStyle(
                                color: Color(0xFF4ECFA8),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isTablet ? 12 : 10),
                      Text(
                        shift['kasir_nama'] ?? '-',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTablet ? 26 : 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shift['opened_at'] ?? '',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: isTablet ? 13 : 11,
                        ),
                      ),
                      SizedBox(height: isTablet ? 16 : 14),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 18 : 14,
                            vertical: isTablet ? 10 : 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                color: Colors.white.withOpacity(0.7),
                                size: isTablet ? 16 : 14),
                            const SizedBox(width: 8),
                            Text(
                              'Kas Awal  Rp ${_fmt(shift['open_amount'])}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _maxContentWidth(context)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 16, hp, 32),
                child: Column(
                  children: [
                    _buildActionTile(
                      context,
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Tambah Uang Kasir',
                      desc: 'Setor kas ke laci kasir',
                      color: _C.success,
                      bgColor: _C.successLight,
                      onTap: isOffline
                          ? () => _showOfflineSnack(context)
                          : () => _showKasDialog(context, 'in'),
                    ),
                    const SizedBox(height: 8),
                    _buildActionTile(
                      context,
                      icon: Icons.remove_circle_outline_rounded,
                      label: 'Kurangi Uang Kasir',
                      desc: 'Ambil kas dari laci kasir',
                      color: _C.warning,
                      bgColor: _C.warningLight,
                      onTap: isOffline
                          ? () => _showOfflineSnack(context)
                          : () => _showKasDialog(context, 'out'),
                    ),
                    const SizedBox(height: 8),
                    _buildActionTile(
                      context,
                      icon: Icons.swap_horiz_rounded,
                      label: 'Ganti Kasir',
                      desc: 'Shift tetap berjalan',
                      color: _C.accent,
                      bgColor: _C.accentLight,
                      onTap: isOffline
                          ? () => _showOfflineSnack(context)
                          : () => _showGantiKasirDialog(context),
                    ),
                    const SizedBox(height: 16),
                    _buildTutupButton(context),
                    const SizedBox(height: 24),
                    _buildRiwayatKasList(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiwayatKasList(BuildContext context) {
    final cashFlows = shift['cash_flows'] as List<dynamic>? ?? [];
    if (cashFlows.isEmpty) return const SizedBox.shrink();

    final isTablet = _isTablet(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Riwayat Kas Shift Ini',
          style: TextStyle(
            fontSize: isTablet ? 15 : 14,
            fontWeight: FontWeight.w700,
            color: _C.textMain,
          ),
        ),
        const SizedBox(height: 12),
        ...cashFlows.map((cf) {
          final type = cf['type'];
          final isIn = type == 'in';
          final color = isIn ? _C.success : _C.warning;
          final nominal = _fmt(cf['jumlah']);

          String time = '-';
          if (cf['created_at'] != null) {
            try {
              final dt = DateTime.parse(cf['created_at']).toLocal();
              time =
                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(isTablet ? 16 : 12),
            decoration: BoxDecoration(
              color: _C.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.divider, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isIn ? _C.successLight : _C.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isIn
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cf['keterangan'] ?? (isIn ? 'Kas Masuk' : 'Kas Keluar'),
                        style: TextStyle(
                          fontSize: isTablet ? 14 : 13,
                          fontWeight: FontWeight.w600,
                          color: _C.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pukul $time',
                        style: TextStyle(
                            fontSize: isTablet ? 12 : 11, color: _C.textSub),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isIn ? '+' : '-'} Rp $nominal',
                  style: TextStyle(
                    fontSize: isTablet ? 14 : 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String desc,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    final isTablet = _isTablet(context);
    return Material(
      color: _C.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 18 : 14, vertical: isTablet ? 16 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.divider, width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: isTablet ? 48 : 40,
                height: isTablet ? 48 : 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
                ),
                child: Icon(icon, color: color, size: isTablet ? 24 : 20),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isTablet ? 15 : 13,
                        fontWeight: FontWeight.w600,
                        color: _C.textMain,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      desc,
                      style: TextStyle(
                          fontSize: isTablet ? 12.5 : 11, color: _C.textSub),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: _C.textSub.withOpacity(0.4), size: isTablet ? 22 : 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showOfflineSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur ini tidak tersedia saat offline'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTutupButton(BuildContext context) {
    final isTablet = _isTablet(context);
    return GestureDetector(
      onTap: isOffline
          ? () => _showOfflineSnack(context)
          : () => _showTutupDialog(context),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 14),
        decoration: BoxDecoration(
          color: _C.dangerLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.danger.withOpacity(0.25), width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded,
                color: _C.danger, size: isTablet ? 20 : 18),
            const SizedBox(width: 8),
            Text(
              'Tutup Shift',
              style: TextStyle(
                color: _C.danger,
                fontSize: isTablet ? 15 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog Kas (Tambah / Kurangi) ─────────────────────────
  void _showKasDialog(BuildContext context, String type) {
    final pinCtrl = TextEditingController();
    final nominalCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    bool loading = false;
    String? error;

    final isIn = type == 'in';
    final color = isIn ? _C.success : _C.warning;
    final label = isIn ? 'Tambah Uang Kasir' : 'Kurangi Uang Kasir';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _BottomSheetWrapper(
          children: [
            _sheetHeader(
              icon: isIn ? Icons.add_rounded : Icons.remove_rounded,
              iconBg: isIn ? _C.successLight : _C.warningLight,
              iconColor: color,
              title: label,
            ),
            const SizedBox(height: 18),
            _buildFieldLabel('PIN Kasir'),
            _buildPinField(
              controller: pinCtrl,
              hint: 'Masukkan PIN',
              pinVisible: false,
              onToggleVisibility: null, // tanpa toggle di sheet
            ),
            const SizedBox(height: 12),
            _buildFieldLabel('Jumlah (Rp)'),
            _buildRupiahField(
              controller: nominalCtrl,
              hint: '0',
              color: color,
            ),
            const SizedBox(height: 12),
            _buildFieldLabel('Keterangan (opsional)'),
            _buildTextField(
              controller: ketCtrl,
              hint: 'Keterangan...',
              prefix:
                  const Icon(Icons.notes_rounded, color: _C.primary, size: 18),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _buildErrorBox(error!),
            ],
            const SizedBox(height: 18),
            _buildPrimaryButton(
              label: isIn ? 'Tambahkan' : 'Kurangkan',
              icon:
                  isIn ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
              loading: loading,
              color: color,
              onTap: () async {
                setS(() {
                  loading = true;
                  error = null;
                });
                try {
                  final res = await ShiftService.tambahKas(
                    shiftId: shift['id'],
                    pin: pinCtrl.text,
                    type: type,
                    jumlah: RupiahInputFormatter.getRawValue(nominalCtrl),
                    keterangan: ketCtrl.text.isNotEmpty ? ketCtrl.text : null,
                  );
                  if (res['success'] == true) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      _snackBar(res['message'], _C.success),
                    );
                    onRefresh();
                  } else {
                    setS(() => error = res['message']);
                  }
                } catch (_) {
                  setS(() => error = 'Koneksi gagal.');
                } finally {
                  setS(() => loading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog Ganti Kasir ───────────────────────────────────
  void _showGantiKasirDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _BottomSheetWrapper(
          children: [
            _sheetHeader(
              icon: Icons.swap_horiz_rounded,
              iconBg: _C.accentLight,
              iconColor: _C.accent,
              title: 'Ganti Kasir',
              subtitle: 'Shift tetap berjalan',
            ),
            const SizedBox(height: 18),
            _buildFieldLabel('PIN Kasir Baru'),
            _buildPinField(
              controller: pinCtrl,
              hint: 'Masukkan PIN kasir baru',
              pinVisible: false,
              onToggleVisibility: null,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _buildErrorBox(error!),
            ],
            const SizedBox(height: 18),
            _buildPrimaryButton(
              label: 'Konfirmasi Ganti Kasir',
              icon: Icons.check_circle_outline_rounded,
              loading: loading,
              onTap: () async {
                setS(() {
                  loading = true;
                  error = null;
                });
                try {
                  final res = await ShiftService.gantiKasir(
                      tokoId: tokoId, pin: pinCtrl.text);
                  if (res['success'] == true) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      _snackBar('Kasir berganti ke ${res['user']['name']}',
                          _C.accent),
                    );
                  } else {
                    setS(() => error = res['message']);
                  }
                } catch (_) {
                  setS(() => error = 'Koneksi gagal.');
                } finally {
                  setS(() => loading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog Tutup Shift ───────────────────────────────────
  void _showTutupDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    final nominalCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _BottomSheetWrapper(
          children: [
            _sheetHeader(
              icon: Icons.lock_outline_rounded,
              iconBg: _C.dangerLight,
              iconColor: _C.danger,
              title: 'Tutup Shift',
              subtitle: 'Hitung uang di laci terlebih dahulu',
            ),
            const SizedBox(height: 18),
            _buildFieldLabel('PIN Kasir'),
            _buildPinField(
              controller: pinCtrl,
              hint: 'Masukkan PIN',
              pinVisible: false,
              onToggleVisibility: null,
            ),
            const SizedBox(height: 12),
            _buildFieldLabel('Uang di Laci Sekarang'),
            _buildRupiahField(
              controller: nominalCtrl,
              hint: '0',
              color: _C.danger,
            ),
            const SizedBox(height: 12),
            _buildFieldLabel('Catatan (opsional)'),
            _buildTextField(
              controller: ketCtrl,
              hint: 'Catatan penutupan...',
              prefix:
                  const Icon(Icons.notes_rounded, color: _C.primary, size: 18),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _buildErrorBox(error!),
            ],
            const SizedBox(height: 18),
            _buildPrimaryButton(
              label: 'Tutup Shift Sekarang',
              icon: Icons.lock_rounded,
              loading: loading,
              color: _C.danger,
              onTap: () async {
                setS(() {
                  loading = true;
                  error = null;
                });
                try {
                  final res = await ShiftService.tutupShift(
                    shiftId: shift['id'],
                    pin: pinCtrl.text,
                    closeAmount: RupiahInputFormatter.getRawValue(nominalCtrl),
                    catatanTutup: ketCtrl.text.isNotEmpty ? ketCtrl.text : null,
                  );
                  if (res['success'] == true) {
                    Navigator.pop(ctx);
                    _showRingkasanDialog(
                        context, res['ringkasan'], res['shift']);
                  } else {
                    setS(() => error = res['message']);
                  }
                } catch (_) {
                  setS(() => error = 'Koneksi gagal.');
                } finally {
                  setS(() => loading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog Ringkasan ─────────────────────────────────────
  void _showRingkasanDialog(BuildContext context,
      Map<String, dynamic> ringkasan, Map<String, dynamic> shiftData) {
    final selisih = (ringkasan['selisih'] as num?)?.toInt() ?? 0;
    final isLebih = selisih >= 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _C.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.summarize_outlined,
                        color: _C.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Ringkasan Shift',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _C.textMain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ringRow('Total Transaksi', '${ringkasan['total_order']} order'),
              _ringRow('Total Penjualan',
                  'Rp ${_fmt(ringkasan['total_penjualan'])}'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: _C.divider, height: 1, thickness: 0.8),
              ),
              _ringRow('Kas Awal', 'Rp ${_fmt(ringkasan['kas_awal'])}'),
              _ringRow('Kas Masuk Manual',
                  'Rp ${_fmt(ringkasan['kas_masuk_manual'])}'),
              _ringRow('Kas Keluar Manual',
                  'Rp ${_fmt(ringkasan['kas_keluar_manual'])}'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: _C.divider, height: 1, thickness: 0.8),
              ),
              _ringRow('Kas Sistem', 'Rp ${_fmt(ringkasan['kas_sistem'])}'),
              _ringRow('Kas Aktual', 'Rp ${_fmt(ringkasan['kas_aktual'])}'),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isLebih ? _C.successLight : _C.dangerLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLebih
                        ? _C.success.withOpacity(0.25)
                        : _C.danger.withOpacity(0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Selisih',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isLebih ? _C.success : _C.danger,
                      ),
                    ),
                    Text(
                      '${isLebih ? '+' : ''}Rp ${_fmt(selisih.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isLebih ? _C.success : _C.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        bool success =
                            await ThermalPrintService.printShiftSummary(
                          shift: shiftData,
                          ringkasan: ringkasan,
                        );
                        if (!success && ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Gagal mencetak struk! Cek koneksi printer.')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _C.primary, width: 1.2),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.print_rounded,
                                color: _C.primary, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Cetak Struk',
                              style: TextStyle(
                                color: _C.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onTutup();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _C.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Selesai',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ringRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12.5, color: _C.textSub)),
            Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _C.textMain)),
          ],
        ),
      );

  String _fmt(dynamic val) {
    if (val == null) return '0';
    final n = (val is num) ? val.toInt() : (int.tryParse(val.toString()) ?? 0);
    return n.abs().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom Sheet Wrapper
// ─────────────────────────────────────────────────────────────
class _BottomSheetWrapper extends StatelessWidget {
  final List<Widget> children;
  const _BottomSheetWrapper({required this.children});

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        top: 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 640.0 : double.infinity,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 32.0 : 22.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 3.5,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: _C.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper widgets (top-level)
// ─────────────────────────────────────────────────────────────

Widget _sheetHeader({
  required IconData icon,
  required Color iconBg,
  required Color iconColor,
  required String title,
  String? subtitle,
}) {
  return Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _C.textMain,
            ),
          ),
          if (subtitle != null)
            Text(subtitle,
                style: const TextStyle(fontSize: 11.5, color: _C.textSub)),
        ],
      ),
    ],
  );
}

SnackBar _snackBar(String msg, Color color) => SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    );

Widget _buildFieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: _C.textSub,
          letterSpacing: 0.2,
        ),
      ),
    );

// ── Field PIN — keyboard angka, tanpa format ──────────────────
// onToggleVisibility null = tanpa tombol show/hide (di bottom sheet)
Widget _buildPinField({
  required TextEditingController controller,
  required String hint,
  required bool pinVisible,
  required VoidCallback? onToggleVisibility,
}) {
  return Container(
    decoration: BoxDecoration(
      color: _C.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.divider, width: 0.8),
    ),
    child: TextField(
      controller: controller,
      obscureText: !pinVisible,
      // Angka saja — numericPassword supaya tetap ada tombol done di iOS
      keyboardType: TextInputType.numberWithOptions(
        signed: false,
        decimal: false,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
        fontSize: 13.5,
        color: _C.textMain,
        fontWeight: FontWeight.w500,
        letterSpacing: 4, // Beri spasi antar digit agar terlihat PIN-like
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: _C.textSub,
          fontSize: 13.5,
          letterSpacing: 0,
        ),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 12, right: 8),
          child: Icon(Icons.lock_outline_rounded, color: _C.primary, size: 18),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: onToggleVisibility != null
            ? IconButton(
                icon: Icon(
                  pinVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _C.textSub,
                  size: 18,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        counterText: '',
      ),
    ),
  );
}

// ── Field Rupiah — format otomatis saat mengetik ──────────────
Widget _buildRupiahField({
  required TextEditingController controller,
  required String hint,
  required Color color,
}) {
  return Container(
    decoration: BoxDecoration(
      color: _C.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.divider, width: 0.8),
    ),
    child: Row(
      children: [
        // Prefix "Rp" dengan border kanan
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: _C.divider, width: 0.8)),
          ),
          child: Text(
            'Rp',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        // Input area
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number, // numpad angka
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, // filter dulu
              RupiahInputFormatter(), // lalu format
            ],
            style: const TextStyle(
              fontSize: 13.5,
              color: _C.textMain,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _C.textSub, fontSize: 13.5),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
              counterText: '',
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Field teks biasa (catatan, keterangan) ────────────────────
Widget _buildTextField({
  required TextEditingController controller,
  required String hint,
  bool obscure = false,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  Widget? prefix,
  Widget? suffix,
}) {
  return Container(
    decoration: BoxDecoration(
      color: _C.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.divider, width: 0.8),
    ),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      style: const TextStyle(
        fontSize: 13.5,
        color: _C.textMain,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.textSub, fontSize: 13.5),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: prefix != null
            ? Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: prefix,
              )
            : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
        counterText: '',
      ),
    ),
  );
}

Widget _buildErrorBox(String message) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.dangerLight,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _C.danger.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _C.danger, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _C.danger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );

Widget _buildPrimaryButton({
  required String label,
  required IconData icon,
  required bool loading,
  required VoidCallback onTap,
  Color? color,
}) {
  final btnColor = color ?? _C.primary;
  return GestureDetector(
    onTap: loading ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 50,
      decoration: BoxDecoration(
        color: btnColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: btnColor.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

String _fmt(dynamic val) {
  if (val == null) return '0';
  final n = (val is num) ? val.toInt() : (int.tryParse(val.toString()) ?? 0);
  return n.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}
