import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shift_service.dart';

// ─────────────────────────────────────────────────────────────
// ShiftScreen
// Dipakai untuk 2 kondisi:
//   1. Belum ada shift aktif → tampil form buka shift
//   2. Shift sudah aktif     → tampil ringkasan + aksi
//
// Cara pakai:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => ShiftScreen(tokoId: tokoId, userId: userId),
//   ));
// ─────────────────────────────────────────────────────────────

class ShiftScreen extends StatefulWidget {
  final int tokoId;
  final int userId;

  // Callback saat shift berhasil dibuka — kirim data user & shift ke parent
  final void Function(Map<String, dynamic> user, Map<String, dynamic> shift)?
      onShiftOpened;

  const ShiftScreen({
    super.key,
    required this.tokoId,
    required this.userId,
    this.onShiftOpened,
  });

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  bool _loading = true;
  bool _shiftAktif = false;
  Map<String, dynamic>? _shift;

  @override
  void initState() {
    super.initState();
    _cekShift();
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
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_shiftAktif ? 'Shift Aktif' : 'Buka Shift'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _shiftAktif ? _buildShiftAktif() : _buildBukaShift(),
    );
  }

  // ── Halaman buka shift ─────────────────────────────────
  Widget _buildBukaShift() {
    return _BukaShiftForm(
      tokoId: widget.tokoId,
      onBerhasil: (user, shift) {
        setState(() {
          _shiftAktif = true;
          _shift = shift;
        });
        widget.onShiftOpened?.call(user, shift);
      },
    );
  }

  // ── Halaman shift aktif ────────────────────────────────
  Widget _buildShiftAktif() {
    return _ShiftAktifView(
      shift: _shift!,
      tokoId: widget.tokoId,
      onTutup: () {
        setState(() {
          _shiftAktif = false;
          _shift = null;
        });
      },
      onRefresh: _cekShift,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Form Buka Shift
// ─────────────────────────────────────────────────────────────
class _BukaShiftForm extends StatefulWidget {
  final int tokoId;
  final void Function(Map<String, dynamic> user, Map<String, dynamic> shift)
      onBerhasil;

  const _BukaShiftForm({required this.tokoId, required this.onBerhasil});

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

  Future<void> _buka() async {
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'PIN wajib diisi');
      return;
    }
    final nominal = int.tryParse(_nominalCtrl.text.replaceAll('.', '')) ?? 0;

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // Ilustrasi
          const Icon(Icons.store_outlined, size: 64, color: Color(0xFF534AB7)),
          const SizedBox(height: 8),
          const Text(
            'Buka shift kasir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Masukkan PIN dan uang awal di laci kasir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 32),

          // PIN
          _label('PIN Kasir'),
          TextField(
            controller: _pinCtrl,
            obscureText: !_pinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              hintText: 'Masukkan PIN',
              counterText: '',
              suffixIcon: IconButton(
                icon:
                    Icon(_pinVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _pinVisible = !_pinVisible),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Uang awal
          _label('Uang Awal di Laci (Rp)'),
          TextField(
            controller: _nominalCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '0',
              prefixText: 'Rp ',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Catatan
          _label('Catatan (opsional)'),
          TextField(
            controller: _catatanCtrl,
            decoration: const InputDecoration(
              hintText: 'Open kasir pagi',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEBEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFA32D2D), fontSize: 13)),
            ),
            const SizedBox(height: 12),
          ],

          // Tombol buka
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _buka,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF534AB7),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Buka Shift',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87)),
      );
}

// ─────────────────────────────────────────────────────────────
// Shift Aktif View — ringkasan + aksi
// ─────────────────────────────────────────────────────────────
class _ShiftAktifView extends StatelessWidget {
  final Map<String, dynamic> shift;
  final int tokoId;
  final VoidCallback onTutup;
  final VoidCallback onRefresh;

  const _ShiftAktifView({
    required this.shift,
    required this.tokoId,
    required this.onTutup,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info shift aktif
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.radio_button_checked,
                      color: Color(0xFF534AB7), size: 16),
                  const SizedBox(width: 6),
                  const Text('Shift Aktif',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF534AB7))),
                  const Spacer(),
                  Text(shift['opened_at'] ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF534AB7))),
                ]),
                const SizedBox(height: 12),
                _infoRow('Kasir', shift['kasir_nama'] ?? '-'),
                _infoRow('Kas Awal', 'Rp ${_fmt(shift['open_amount'])}'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tombol aksi
          _actionButton(
            context,
            icon: Icons.add_circle_outline,
            label: 'Tambah Uang Kasir',
            color: const Color(0xFF1D9E75),
            onTap: () => _showKasDialog(context, 'in'),
          ),
          const SizedBox(height: 10),
          _actionButton(
            context,
            icon: Icons.remove_circle_outline,
            label: 'Kurangi Uang Kasir',
            color: const Color(0xFFBA7517),
            onTap: () => _showKasDialog(context, 'out'),
          ),
          const SizedBox(height: 10),
          _actionButton(
            context,
            icon: Icons.person_outline,
            label: 'Ganti Kasir',
            color: const Color(0xFF185FA5),
            onTap: () => _showGantiKasirDialog(context),
          ),
          const SizedBox(height: 10),
          _actionButton(
            context,
            icon: Icons.lock_outline,
            label: 'Tutup Shift',
            color: const Color(0xFFA32D2D),
            onTap: () => _showTutupDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _actionButton(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 15, color: color, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ]),
        ),
      ),
    );
  }

  // ── Dialog Tambah/Kurang Kas ───────────────────────────
  void _showKasDialog(BuildContext context, String type) {
    final pinCtrl = TextEditingController();
    final nominalCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                type == 'in' ? 'Tambah Uang Kasir' : 'Kurangi Uang Kasir',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'PIN Kasir', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Jumlah (Rp)',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: ketCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Keterangan (opsional)',
                      border: OutlineInputBorder())),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        setS(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          final res = await ShiftService.tambahKas(
                            shiftId: shift['id'],
                            pin: pinCtrl.text,
                            type: type,
                            jumlah: int.tryParse(nominalCtrl.text) ?? 0,
                            keterangan:
                                ketCtrl.text.isNotEmpty ? ketCtrl.text : null,
                          );
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(res['message']),
                                  backgroundColor: Colors.green),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: type == 'in'
                      ? const Color(0xFF1D9E75)
                      : const Color(0xFFBA7517),
                ),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(type == 'in' ? 'Tambahkan' : 'Kurangkan',
                        style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialog Ganti Kasir ─────────────────────────────────
  void _showGantiKasirDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ganti Kasir',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                  'Shift tetap berjalan, hanya user aktif yang berganti.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 16),
              TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'PIN Kasir Baru',
                      border: OutlineInputBorder())),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
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
                              SnackBar(
                                content: Text(
                                    'Kasir berganti ke ${res['user']['name']}'),
                                backgroundColor: Colors.blue,
                              ),
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF185FA5)),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Konfirmasi Ganti Kasir',
                        style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialog Tutup Shift ─────────────────────────────────
  void _showTutupDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    final nominalCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tutup Shift',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Hitung uang di laci kasir, lalu input jumlahnya.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 16),
              TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'PIN Kasir', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Uang di Laci Sekarang (Rp)',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: ketCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      border: OutlineInputBorder())),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        setS(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          final res = await ShiftService.tutupShift(
                            shiftId: shift['id'],
                            pin: pinCtrl.text,
                            closeAmount: int.tryParse(nominalCtrl.text) ?? 0,
                            catatanTutup:
                                ketCtrl.text.isNotEmpty ? ketCtrl.text : null,
                          );
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            // Tampilkan ringkasan shift
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA32D2D)),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Tutup Shift Sekarang',
                        style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialog Ringkasan setelah tutup shift ───────────────
  void _showRingkasanDialog(BuildContext context,
      Map<String, dynamic> ringkasan, Map<String, dynamic> shiftData) {
    final selisih = (ringkasan['selisih'] as num?)?.toInt() ?? 0;
    final isLebih = selisih >= 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ringkasan Shift',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ringkasanRow(
                'Total Transaksi', '${ringkasan['total_order']} order'),
            _ringkasanRow(
                'Total Penjualan', 'Rp ${_fmt(ringkasan['total_penjualan'])}'),
            const Divider(),
            _ringkasanRow('Kas Awal', 'Rp ${_fmt(ringkasan['kas_awal'])}'),
            _ringkasanRow('Kas Masuk Manual',
                'Rp ${_fmt(ringkasan['kas_masuk_manual'])}'),
            _ringkasanRow('Kas Keluar Manual',
                'Rp ${_fmt(ringkasan['kas_keluar_manual'])}'),
            const Divider(),
            _ringkasanRow('Kas Sistem', 'Rp ${_fmt(ringkasan['kas_sistem'])}'),
            _ringkasanRow('Kas Aktual', 'Rp ${_fmt(ringkasan['kas_aktual'])}'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isLebih ? const Color(0xFFEAF3DE) : const Color(0xFFFCEBEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Selisih',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isLebih
                                ? const Color(0xFF3B6D11)
                                : const Color(0xFFA32D2D))),
                    Text(
                      '${isLebih ? '+' : ''}Rp ${_fmt(selisih.abs())}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isLebih
                              ? const Color(0xFF3B6D11)
                              : const Color(0xFFA32D2D)),
                    ),
                  ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onTutup();
            },
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  Widget _ringkasanRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );

  String _fmt(dynamic val) {
    if (val == null) return '0';
    final n = (val is num) ? val.toInt() : (int.tryParse(val.toString()) ?? 0);
    return n.abs().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }
}

String _fmt(dynamic val) {
  if (val == null) return '0';
  final n = (val is num) ? val.toInt() : (int.tryParse(val.toString()) ?? 0);
  return n.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}
