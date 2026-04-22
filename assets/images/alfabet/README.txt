Alfabet Reference Images
=========================

Letakkan gambar referensi isyarat alfabet di folder sesuai mode:

  assets/images/alfabet/sibi/<huruf>.webp     → 1 tangan (SIBI), 24 huruf
  assets/images/alfabet/bisindo/<huruf>.webp  → 2 tangan (BISINDO), 26 huruf

Nama file: lowercase huruf tanpa ekstensi lain.
  Contoh: a.webp, b.webp, c.webp, …, z.webp
  SIBI skip: j.webp, z.webp (dinamis, tidak bisa foto statis)

Spesifikasi rekomendasi:
- Format: WebP lossy (q=80)
- Resolusi: 512px sisi terpanjang
- Latar: putih polos / transparan
- Target ukuran: 15–40 KB per gambar

Cara compress (macOS / Linux):
  # Install cwebp
  brew install webp             # macOS
  sudo apt install webp         # Linux

  # Convert 1 file
  cwebp -q 80 -resize 512 0 input.png -o a.webp

  # Batch semua PNG/JPG di folder
  for f in *.png *.jpg; do
    [ -f "$f" ] || continue
    name="${f%.*}"
    cwebp -q 80 -resize 512 0 "$f" -o "${name,,}.webp"
  done

Kalau file belum ada, widget `AlphabetReferenceImage` akan fallback ke
placeholder ikon otomatis — tidak crash.
