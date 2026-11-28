# Auto Studio — rutin harian

Arahan tetap untuk scheduled task harian (dan bila pemilik kata "jalankan studio"). Balas pemilik dalam Bahasa Melayu.

Folder kerja: `C:\Users\User\OneDrive\Desktop\Bisnes Youtube`. Enjin guna Python sistem (ada PyYAML).

## Kitaran
1. `python studio/engine.py next <workflow>` (workflow lalai: `youtube-last-shift`).
2. Baca output:
   - **CLAUDE STEP** → buat arahan yang dicetak, kemudian jalankan perintah `done` yang dicetak, dan ulang langkah 1.
   - **WAITING FOR OWNER APPROVAL** → ikut "Bila perlukan pemilik" di bawah (notifikasi + soalan dalam sesi), dan berhenti.
     Bila pemilik balas "lulus" / "ok upload": `python studio/engine.py approve <workflow>`, kemudian ulang langkah 1.
     Jika pemilik minta pembaikan: buat pembaikan, padam output yang perlu dijana semula
     (contoh video .mp4 supaya `compile` dijalankan semula), `goto` langkah berkaitan, ulang langkah 1.
   - **Nothing to do** → laporkan ringkas dan berhenti.
   - Ralat / exit code bukan 0 → baca log (`engine.py status`), betulkan jika jelas; jika tidak, laporkan kepada pemilik dengan ralat sebenar.
3. Jika langkah ditangguh kerana had ChatGPT, berhenti — run esok akan sambung.

## Bila perlukan pemilik: tanya terus, jangan tunggu
Pemilik mahu ditanya secara proaktif (2026-11-28), bukan menunggu mereka bertanya.
- Bila langkah perlukan pemilik (izin muat turun gambar, ChatGPT belum login, kelulusan upload):
  `defer` dengan sebab bermula `PEMILIK:`, hantar PushNotification dengan soalan tepat (contoh
  "Ep 4: izin muat turun 21 gambar dari chatgpt.com? Balas ok dalam sesi Auto Studio"), tulis soalan yang
  sama sebagai mesej terakhir dalam sesi, dan berhenti. Bila pemilik balas dalam sesi itu, terus sambung kitaran.
- Rutin berjalan setiap jam (10:00–22:00). Pada setiap run, semak `engine.py status`: jika log terakhir ialah
  `deferred: PEMILIK:` kurang dari 3 jam lalu, berhenti senyap (jangan ganggu pemilik berulang kali);
  jika lebih 3 jam, tanya sekali lagi. Jika tiada apa-apa untuk dibuat, berhenti senyap tanpa notifikasi.

## Peraturan
- Jangan upload atau terbitkan apa-apa sebelum langkah `approval` diluluskan oleh pemilik sendiri dalam chat.
- Muat turun fail perlukan kebenaran pemilik (sekali bagi setiap kumpulan gambar episod).
- Jangan ubah `studio/state/*.json` dengan tangan; guna perintah enjin (`done`, `goto`, `new`).
- Akhir run: ringkasan 2–3 ayat — episod, langkah terakhir, apa yang menunggu pemilik.

## Tambah workflow bisnes lain
Salin `workflows/youtube-last-shift.yaml` sebagai titik mula. Jenis langkah: `python` (`run:` perintah atau
`call:` fungsi dalam `steps.py`), `check` (`files:` / `glob:` + `count_from_json:`, `on_fail:`), `claude`
(`prompt:` fail dalam `prompts/` atau `instructions:`; `requires:` fail wajib sebelum `done`), `approval`.
Pemboleh ubah `{nama}` datang dari `vars`, `init`/state, dan `steps.DERIVED`; nombor `x` dapat `x2` (2 digit) dan `x_next`.
