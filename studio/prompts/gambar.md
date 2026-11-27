## Langkah: GAMBAR — jana gambar scene Episode {ep} di ChatGPT (Chrome pemilik)

Input: `{series_dir}/Episode-{ep2}-Image-Prompts.md` (satu prompt setiap scene), bilangan scene = panjang
senarai `scenes` dalam `{edit_json}`. Output: `{image_dir}/scene01.png`, `scene02.png`, ... (nombor 2 digit).

1. Muatkan alat Claude in Chrome (satu ToolSearch). Buka tab baru ke https://chatgpt.com.
   Jika belum log masuk: berhenti, `defer` dengan sebab "ChatGPT belum login", beritahu pemilik.
2. Guna chat siri yang sama jika ada (cari tajuk chat yang mengandungi gambar siri ini). Jika chat baru:
   upload `Branding/logo-800.png` dan hantar "Mesej Setup" dari `{series_dir}/Episode-01-Image-Prompts.md`.
   Sebelum scene pertama, hantar peringatan gaya + watak (Cal, tiada misai) bersama logo.
3. Langkau scene yang fail `sceneNN.png` sudah wujud. Untuk setiap scene lain, satu demi satu:
   - Hantar prompt scene, tunggu gambar siap (boleh ambil 1–2 minit).
   - Muat turun gambar (butang download ChatGPT) → fail masuk ke folder Downloads pemilik.
     Muat turun fail perlukan kebenaran pemilik dalam sesi: minta SEKALI untuk semua gambar episod ini
     (nyatakan bilangan dan sumber chatgpt.com) sebelum muat turun pertama.
   - Pindah fail terbaru dari Downloads ke `{image_dir}/sceneNN.png`. Jika format bukan PNG, tukar dengan
     `ffmpeg -y -v error -i <fail> {image_dir}/sceneNN.png` dan buang fail asal dari Downloads.
   - Lihat gambar (Read) untuk semak: 16:9, tiada teks/darah, Cal konsisten. Jika rosak, minta jana semula.
4. Jika ChatGPT menolak kerana had harian: `python studio/engine.py defer youtube-last-shift gambar "had ChatGPT, sambung esok"`
   dan berhenti — run esok akan sambung dari scene yang belum ada.

Selesai (semua scene ada): `python studio/engine.py done youtube-last-shift gambar`
