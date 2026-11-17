# Ride N Cut Barberhome

Website booking barber home service dengan halaman pelanggan dan dashboard admin.

## Teknologi

- Next.js 15
- React 19
- Supabase (Database dan Auth)
- EmailJS (notifikasi email booking)
- Vercel (deployment)

## Menjalankan secara lokal

1. Install dependency: `npm install`
2. Salin `.env.example` menjadi `.env.local`.
3. Isi kredensial project Supabase dan EmailJS.
4. Jalankan: `npm run dev`
5. Buka `http://localhost:3000`.

## Environment variables

| Variable | Kegunaan |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | URL project Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Publishable/anon key Supabase |
| `EMAILJS_PUBLIC_KEY` | Public key EmailJS yang digunakan endpoint notifikasi |

Jangan pernah memasukkan Supabase service-role key ke variabel `NEXT_PUBLIC_*` atau ke kode browser. Kredensial produksi harus disimpan melalui Environment Variables di Vercel, bukan di Git.

## Konfigurasi layanan eksternal

### Supabase

Buat tabel dan fungsi yang dipakai aplikasi, lalu aktifkan Row Level Security (RLS) dengan kebijakan yang sesuai. Aplikasi membutuhkan:

- `barbers`: `id`, `name`, `is_active`
- `bookings`: `id`, `customer_name`, `phone`, `address`, `barber_id`, `start_at`, `notes`, `status`, `booking_code`
- `site_settings`: `id`, `brand_name`, `hero_title`, `hero_subtitle`, `accent_color`, `services`, `schedule_config`
- RPC `customer_booking_history(p_phone, p_code)`
- RPC `customer_cancel_booking(p_phone, p_code, p_booking_id)`

Dashboard admin memakai Supabase Auth email/password. Buat akun admin melalui Supabase Auth dan batasi izin tulis/hapus data hanya untuk akun admin. Jangan membuat kebijakan RLS yang mengizinkan publik mengubah status, menghapus booking, atau mengelola barber/pengaturan.

Untuk mencegah dua pelanggan mengambil slot yang sama secara bersamaan, database harus memiliki constraint/transactional validation pada kombinasi barber dan waktu booking (dengan booking berstatus selain cancelled). Pemeriksaan di browser saja tidak cukup untuk mencegah race condition.

### EmailJS

Endpoint `/api/booking-notification` menggunakan service ID `service_u6yhrju`, template ID `template_srgzub4`, dan `EMAILJS_PUBLIC_KEY`. Pastikan template EmailJS memiliki variabel:

- `customer_name`
- `phone`
- `address`
- `barber_name`
- `booking_date`
- `notes`
- `booking_code`

EmailJS merupakan layanan eksternal; pengiriman notifikasi perlu diuji dengan konfigurasi akun yang aktif.

## Build dan pemeriksaan

- `npm run build`: pemeriksaan build produksi.
- `npm run dev`: pemeriksaan alur lokal.
- Uji booking pelanggan, riwayat, pembatalan, login admin, pengelolaan barber, pengaturan jadwal, perubahan status, dan notifikasi email sebelum go-live.

## Halaman

- Pelanggan: `/`
- Admin: `/admin`
