## Langkah: PAKEJ UPLOAD — Episode {ep}

Tulis `{upload_md}` dengan format SAMA seperti `{series_dir}/Episode-02-Upload.md`:
- Jadual: tayang {publish_date} 09:00 MYT.
- Title: `Zombie Outbreak: 30 Days Trapped in a Freezer Warehouse (Day {ep})`.
- Prompt thumbnail.
- Description: hook 1 ayat, ringkasan 2 ayat, pautan "Watch from Day 1: https://www.youtube.com/watch?v=hbSJN6eJSDE",
  ajakan subscribe untuk Day {ep_next}, bab masa (00:00 ...) — masa bab dikira dari permulaan setiap
  `part*.wav` dalam `{audio_dir}` (tambah 1.2 s jarak antara part), 3 hashtag.
- Tags: senarai yang sama seperti Episode 2.
- Settings: Category 24, Made for kids No, bahasa en, tambah ke playlist siri.

Selesai: `python studio/engine.py done youtube-last-shift upload_pack`
