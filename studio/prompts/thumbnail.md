## Langkah: THUMBNAIL — Episode {ep}

1. Ambil prompt thumbnail dari `{upload_md}` jika ada bahagian "Thumbnail"; jika tiada, tulis satu ikut gaya
   `{series_dir}/Episode-02-Upload.md` (Cal close-up kiri, elemen seram kanan, 2–3 perkataan teks besar putih
   bergaris gelap, palet biru sejuk/hijau, lilitan lengan merah, tiada darah) berdasarkan cliffhanger episod ini.
2. Jana dalam chat ChatGPT siri yang sama (Chrome), muat turun (kebenaran sama seperti langkah gambar).
3. Simpan sebagai `{thumbnail}` (tukar ke JPG dengan `ffmpeg -y -v error -i <fail> -q:v 2 {thumbnail}`).
   Pastikan saiz bawah 2 MB (had YouTube); jika lebih, naikkan nilai -q:v.
4. Lihat thumbnail untuk semak teks boleh dibaca dan tiada salah eja.

Selesai: `python studio/engine.py done youtube-last-shift thumbnail`
