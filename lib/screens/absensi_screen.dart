import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/absensi_service.dart';

class AbsensiScreen extends StatefulWidget {
  const AbsensiScreen({super.key});

  @override
  State<AbsensiScreen> createState() => _AbsensiScreenState();
}

class _AbsensiScreenState extends State<AbsensiScreen> {
  bool loading = false;

  List<Map<String, dynamic>> karyawan = []; // {id, name}
  int? selectedUserId;
  String password = '';

  @override
  void initState() {
    super.initState();
    loadKaryawan();
  }

  Future<void> loadKaryawan() async {
    karyawan = await AbsensiService.getKaryawan();
    setState(() {});
  }

  Future<Position> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('GPS tidak aktif');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> processAbsensi(bool isCheckIn) async {
    if (selectedUserId == null || password.isEmpty) {
      _msg('Pilih karyawan dan isi password');
      return;
    }

    setState(() => loading = true);

    try {
      final auth = await AbsensiService.auth(
        userId: selectedUserId!,
        password: password,
      );

      if (!auth['success']) {
        _msg(auth['message'] ?? 'Password salah');
        setState(() => loading = false);
        return;
      }

      final pos = await _getLocation();

      final res = isCheckIn
          ? await AbsensiService.checkIn(
              userId: selectedUserId!,
              latitude: pos.latitude,
              longitude: pos.longitude,
            )
          : await AbsensiService.checkOut(
              userId: selectedUserId!,
              latitude: pos.latitude,
              longitude: pos.longitude,
            );

      _msg(res['message'] ?? 'Berhasil');
    } catch (e) {
      _msg('Gagal: $e');
    }

    setState(() => loading = false);
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        title: const Text('ABSENSI KARYAWAN'),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'ABSENSI KARYAWAN',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Pilih Karyawan',
                  border: OutlineInputBorder(),
                ),
                items: karyawan
                    .map<DropdownMenuItem<int>>(
                      (u) => DropdownMenuItem<int>(
                        value: u['id'] as int,
                        child: Text(u['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => selectedUserId = v,
              ),
              const SizedBox(height: 16),
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => password = v,
              ),
              const SizedBox(height: 24),
              if (!loading)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.all(14),
                        ),
                        onPressed: () => processAbsensi(true),
                        child: const Text('CHECK IN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.all(14),
                        ),
                        onPressed: () => processAbsensi(false),
                        child: const Text('CHECK OUT'),
                      ),
                    ),
                  ],
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
