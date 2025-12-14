import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orderkuy_kasir/models/pengeluaran.dart';

// ignore: must_be_immutable
class PengeluaranForm extends StatefulWidget {
  Pengeluaran? pengeluaran;
  final ValueChanged<Map<String, dynamic>> onSave;

  PengeluaranForm({
    super.key,
    this.pengeluaran,
    required this.onSave,
  });

  @override
  State<PengeluaranForm> createState() => _PengeluaranFormState();
}

class _PengeluaranFormState extends State<PengeluaranForm> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  final _deskripsiController = TextEditingController();
  final _jumlahController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final p = widget.pengeluaran;
    if (p != null) {
      _namaController.text = p.namaPengeluaran;
      _deskripsiController.text = p.deskripsi ?? '';
      _jumlahController.text = p.jumlah.toString();
      _selectedDate = DateTime.tryParse(p.tanggal);
    }
  }

  @override
  void dispose() {
    _namaController.dispose();
    _deskripsiController.dispose();
    _jumlahController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Silakan pilih tanggal'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    var dateFormat = DateFormat('yyyy-MM-dd');
    final data = <String, dynamic>{
      'nama_pengeluaran': _namaController.text.trim(),
      'deskripsi': _deskripsiController.text.trim().isEmpty
          ? null
          : _deskripsiController.text.trim(),
      'jumlah': double.parse(_jumlahController.text),
      'tanggal': dateFormat.format(_selectedDate!),
    };

    widget.onSave(data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade900, Colors.red.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.pengeluaran != null
                      ? 'Edit Pengeluaran'
                      : 'Tambah Pengeluaran',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _namaController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Pengeluaran *',
                        hintText: 'Masukkan nama pengeluaran',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nama pengeluaran tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _deskripsiController,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi',
                        hintText: 'Masukkan deskripsi (opsional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _jumlahController,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah *',
                        hintText: 'Masukkan jumlah pengeluaran',
                        border: OutlineInputBorder(),
                        prefixText: 'Rp ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Jumlah tidak boleh kosong';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return 'Jumlah harus berupa angka positif';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() => _selectedDate = date);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tanggal *',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDate != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(_selectedDate!)
                                  : 'Pilih tanggal',
                              style: TextStyle(
                                color: _selectedDate != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          widget.pengeluaran != null
                              ? 'Simpan Perubahan'
                              : 'Tambah Pengeluaran',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
