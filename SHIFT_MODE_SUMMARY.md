# Fitur Shift Mode — Ringkasan Implementasi

## Konteks

Aplikasi kasir Flutter (Kasvo) memiliki fitur **shift** yang otomatis redirect ke `ShiftScreen` setelah login.
Permintaan: toko dapat mengaktifkan/menonaktifkan fitur shift ini melalui pengaturan di Laravel.

---

## Status Flutter ✅ SELESAI

Perubahan dilakukan di `lib/screens/dashboard_screen.dart`:

### 1. Tambah state variable
```dart
bool _shiftMode = true; // default true = fitur shift aktif
```

### 2. Baca `shift_mode` dari login response
```dart
// di _loadUserData()
_shiftMode = user['shift_mode'] ?? true;
```

### 3. Skip redirect ke ShiftScreen jika shift_mode = false
```dart
// di _cekShiftAktif()
if (!_shiftMode) return;
```

### 4. Sembunyikan UI shift jika shift_mode = false
- Banner "Shift belum dibuka" tidak muncul
- Banner "Shift aktif" tidak muncul
- Menu item "Shift" di dashboard tidak muncul

### Catatan penting Flutter
- Default `?? true` → toko lama yang belum punya field `shift_mode` tetap berjalan normal
- Field dibaca dari `SharedPreferences` key `user` (disimpan saat login)

---

## Yang Harus Dilakukan di Laravel ⚠️ BELUM

### 1. Migrasi — tambah kolom ke tabel `toko`

```php
// database/migrations/xxxx_add_shift_mode_to_toko_table.php

public function up(): void
{
    Schema::table('toko', function (Blueprint $table) {
        $table->boolean('shift_mode')->default(true)->after('refund_auto_approve');
    });
}

public function down(): void
{
    Schema::table('toko', function (Blueprint $table) {
        $table->dropColumn('shift_mode');
    });
}
```

### 2. Sertakan `shift_mode` di login response

Flutter membaca `data['user']['shift_mode']` — field ini harus flat (bukan nested) di dalam object `user`.

Contoh response yang diharapkan Flutter:
```json
{
  "token": "...",
  "user": {
    "id": 1,
    "name": "Kasir A",
    "role": "kasir",
    "toko_id": 5,
    "toko_nama": "Warung Makan",
    "shift_mode": true
  }
}
```

Tambahkan di controller login (sesuaikan dengan lokasi kode Anda):
```php
'shift_mode' => (bool) $user->kasir->toko->shift_mode,
// atau jika ada relasi langsung ke toko:
'shift_mode' => (bool) $toko->shift_mode,
```

### 3. Endpoint/UI untuk mengubah setting (opsional, di panel admin)

Jika ingin admin bisa toggle dari web panel:
```php
// Contoh di TokoController
public function updateShiftMode(Request $request, Toko $toko)
{
    $request->validate(['shift_mode' => 'required|boolean']);
    $toko->update(['shift_mode' => $request->shift_mode]);
    return response()->json(['success' => true]);
}
```

---

## Alur Lengkap

```
[Laravel] toko.shift_mode = false
      ↓
[Login API] user.shift_mode = false dalam response
      ↓
[Flutter] simpan ke SharedPreferences['user']
      ↓
[DashboardScreen] _shiftMode = false
      ↓
→ _cekShiftAktif() langsung return (tidak redirect)
→ Banner shift tidak ditampilkan
→ Menu "Shift" tidak muncul di dashboard
```

---

## Nilai Default

| Kondisi | Perilaku |
|---|---|
| `shift_mode = true` | Shift screen muncul seperti biasa |
| `shift_mode = false` | Shift screen tidak pernah muncul |
| Field tidak ada di response | Default `true` (backward compatible) |
