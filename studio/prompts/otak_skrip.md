## Langkah: OTAK — tulis skrip Episode {ep}

Jika Episode {ep} melebihi {series_episodes} (siri sudah tamat): JANGAN tulis apa-apa. Jalankan
`python studio/engine.py defer youtube-last-shift otak_skrip "siri tamat, perlu keputusan siri baru"`,
hantar notifikasi kepada pemilik, dan berhenti.

1. Baca `{series_dir}/Bible.md` (watak, peraturan dunia, rancangan setiap episod).
2. Baca skrip episod sebelumnya `{series_dir}/Episode-*-Script.md` (sekurang-kurangnya yang terakhir) supaya
   cerita bersambung tepat dari cliffhanger lepas.
3. Tulis `{script}` dengan format yang SAMA seperti skrip terdahulu:
   - Tajuk `# Episode {ep}: Day {ep}`, baris **Series:**, nota `>` dan `---`.
   - 18–23 blok `[SCENE: <penerangan visual satu ayat, bahasa Inggeris>]`, setiap blok diikuti narasi orang pertama (Cal).
   - Sasaran ~1,500–1,700 patah perkataan (≈10 minit dengan Kokoro speed 0.95).
   - Nombor dan masa ditulis dalam perkataan (contoh "two twenty A.M."), tiada digit dalam narasi.
   - Tiada darah/gore dalam penerangan scene. Watak Cal konsisten dengan Bible (tiada misai).
   - Mula dengan imbas kembali ringkas ("Last time, ..."), tamat dengan cliffhanger untuk Day {ep_next}.
4. Semak sendiri: setiap [SCENE] ada narasi, tiada digit.

Selesai: `python studio/engine.py done youtube-last-shift otak_skrip`
