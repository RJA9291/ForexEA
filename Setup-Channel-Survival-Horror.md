# Setup Channel YouTube: Survival Horror Bersiri (English, Bajet Percuma)

Dibina berdasarkan video E'Calm, *"Free Claude AI Monetize My YouTube Channel In 7 Days (Full System)"*
(youtube.com/watch?v=ZxTudE4T5fw, 12 Nov 2026), ditambah data vidIQ yang ditarik pada 26 Nov 2026.

> **Nota:** Prompt asal E'Calm dijual di Gumroad, jadi saya tiada salinannya. Prompt dalam fail ini saya tulis sendiri untuk ikut aliran kerja yang sama.

---

## 1. Sistem dalam video tu (ringkas)

| # | Langkah | Tool dalam video | Versi percuma kita |
|---|---|---|---|
| 1 | Buat Gmail, hidupkan 2-step verification, buat channel | Google | Sama |
| 2 | Branding: nama, description, logo, banner, watak utama | ChatGPT | ChatGPT / Gemini (percuma) |
| 3 | Settings Studio + channel keywords | YouTube Studio + vidIQ | Sama (keyword dah siap di bawah) |
| 4 | Cari idea siri (10 pilihan) | Claude | Claude percuma, Prompt B |
| 5 | Tulis skrip episod demi episod dalam **satu chat yang di-pin** | Claude | Claude percuma, Prompt C + D |
| 6 | Jadikan video: watak konsisten, voiceover, animasi | Vsub (berbayar, link affiliate) | Gambar AI + Google Flow + CapCut |
| 7 | Thumbnail yang dimodelkan dari channel serupa | Vsub + ChatGPT | ChatGPT / Gemini, Prompt F |
| 8 | Upload: title, description SEO, playlist ikut siri, tags, bahasa, unlisted dulu, tunggu HD siap baru public | YouTube + vidIQ + Claude | Prompt E |

**Dakwaan dalam video yang perlu diambil dengan berhati-hati:**
- *"Akaun lama perform lagi bagus"*: dia sendiri cakap YouTube tak pernah sahkan perkara ni. Ini pengalaman peribadi dia, bukan fakta.
- *"Monetize dalam 7 hari"* dan *"$400K dalam 3 bulan"*: ini angka dari channel yang dah viral. Dia sendiri letak disclaimer "not typical". Video ni juga jual kursus, prompt dan link affiliate (Vsub, vidIQ).
- Inti sistem dia memang betul: **idea yang buat orang klik + skrip yang buat orang terus tengok + upload yang dioptimumkan.**

---

## 2. Data niche (vidIQ, 26 Nov 2026)

### Keyword utama
| Keyword | Anggaran carian/bulan | Competition (0–100, rendah = senang) |
|---|---|---|
| horror story | 2.66 juta | 75 |
| reddit stories | 1.78 juta | 68 |
| horror stories | 1.68 juta | 72 |
| zombie apocalypse | 1.50 juta | 49 |
| creepypasta | 776K | 74 |
| scary stories | 739K | 66 |
| **zombie survival** | **569K** | **32** ← permintaan tinggi, persaingan rendah |
| survival story | 260K | 63 (permintaan naik +47%) |
| creepy stories | 166K | 54 |
| **zombie outbreak story** | **70K** | **38** |
| survive zombie apocalypse | 45K | 46 |
| survival horror | 43K | 55 |
| horror story narration | 24K | 50 |
| **post apocalyptic story** | **4.7K** | **32** |

Ada satu perkara yang perlu tahu: carian "zombie survival" turun 40% berbanding sebelum ni, tapi jumlahnya masih besar.

### Format yang tengah meletup (outlier 3 bulan terakhir)
Channel **kecil** (1.8K–4K subscriber) dapat 100K–550K views dengan format yang hampir sama:

- "Zombie Outbreak: 30 Days Trapped inside the Crane Cabin": 547K views, channel 1.9K sub
- "Zombie Outbreak: 30 Days Trapped on an Airplane": 138K views, channel 2.1K sub
- "Zombie Outbreak Survival: Day 1 To Day 200 (Full Movie)": 225K views, channel 3.3K sub
- "The Best Place to Sleep in a Zombie Apocalypse": 112K views (127x purata channel dia)
- "Zombie Outbreak: 30 Days Locked Inside a Supermarket": **4.8 juta views**

**Formula tajuk:** `[Bencana]: [X] Days Trapped [di tempat spesifik yang pelik]`

**Risiko:** ramai orang dah copy format ni. Hampir semua video atas berlabel AI dan engagement dia rendah (0.3–0.7%). Untuk menonjol, kena ada **watak utama yang orang ingat** dan **lokasi yang belum orang buat**.

---

## 3. Checklist setup akaun (kena buat sendiri)

Langkah-langkah ni melibatkan akaun, password, nombor telefon dan IC awak sendiri, jadi saya tak boleh buat untuk awak.

- [ ] Buat Gmail baru untuk channel (atau guna yang sedia ada)
- [ ] myaccount.google.com → Security → hidupkan **2-Step Verification**
- [ ] YouTube → profile → Switch account → View all channels → **Create a channel**
- [ ] youtube.com/verify → sahkan dengan nombor telefon. Ini membuka upload lebih 15 minit dan custom thumbnail.
- [ ] Buat email bisnes **berasingan** untuk kolaborasi (jangan guna email channel)

## 4. Settings YouTube Studio

- [ ] Settings → **Upload defaults** → Visibility: **Unlisted**
- [ ] Upload defaults → Category: **Entertainment**, bahasa video: **English**
- [ ] Settings → Channel → **Advanced settings** → Made for kids: **"Review this setting for every video"** (pilihan tengah). Kandungan seram memang bukan untuk kanak-kanak.
- [ ] Advanced settings → hidupkan **Auto-dubbing**
- [ ] Basic info → **Keywords**: copy blok di bawah

```
zombie survival, zombie apocalypse, zombie outbreak story, survival story, survival horror, horror stories, scary stories, creepy stories, survive zombie apocalypse, post apocalyptic story, horror story narration, survival horror tales, animated horror story, day 1 to day 100, 30 days survival, apocalypse survival story
```

- [ ] Customization → **Watermark**: butang subscribe berbentuk segi empat dengan background lutsinar, paparan "Entire video"
- [ ] Bila upload video yang ada visual AI realistik, tandakan **"Altered or synthetic content"**. YouTube wajibkan ni untuk kandungan realistik. Kalau gaya kartun atau stickman, biasanya tak perlu.

---

## 5. Prompt Pack

### Prompt A: Branding (untuk ChatGPT atau Gemini, sebab dua-dua boleh hasilkan gambar)

```
You are a YouTube brand strategist. I'm launching a faceless English YouTube channel that tells
serialized survival-horror stories (zombie outbreaks, disasters, being trapped in unusual places),
narrated in first person by ONE recurring main character across every series.

Step 1: Give me 10 channel name ideas. Rules: 1–3 words, easy to spell, available-sounding as a
@handle, evokes survival + dread, NOT generic ("Horror Stories TV"). Avoid these existing names:
Nobody Gets In, Stick Survival, Drawn to Survive, Archival Survival Stories, Headlamp Guy.
Then STOP and wait for me to pick one.

Step 2 (after I pick): Give me 5 channel descriptions (max 1,000 characters each). Each must say
what viewers get, how often new episodes drop, and naturally include: zombie survival, survival
story, horror stories, zombie apocalypse.

Step 3: Design the MAIN CHARACTER as a full-body reference sheet: front view, side view,
plain white background, consistent 2D animated style, one distinctive item they always carry
(e.g. a cracked orange hard hat, a taped-up radio). Describe the character in a fixed text block
I can reuse in every future image prompt.

Step 4: Generate a square logo (the character's head or distinctive item, bold, readable at
small size) and a 2560x1440 banner with the channel name centred in the safe area (1546x423).
```

> Simpan "fixed text block" watak tu dalam Google Doc. Guna teks yang sama dalam **setiap** prompt gambar supaya rupa watak kekal konsisten.

### Prompt B: Idea siri (Claude, versi percuma)

```
You are a YouTube strategist for a faceless survival-horror channel.
Proven title format in this niche: "[Disaster]: [X] Days Trapped [in a specific, unusual place]".
Recent outliers: trapped in a crane cabin (547K views), on an airplane, in a supermarket (4.8M),
in a school, in a moving truck, frozen city.

Give me 10 NEW series ideas that use places nobody has done yet. For each give:
1. Title (max 60 characters, follows the format)
2. The hook: why a viewer MUST click (one line)
3. The location's built-in danger and built-in resource
4. How many episodes it can sustain (aim for 10–20)
5. A 1-line cliffhanger for the end of Episode 1
Rank them by click potential and explain your top pick in 2 sentences.
```

### Prompt C: Bible siri + Episode 1 (Claude, chat baru, **pin chat tu**)

```
We're writing a serialized survival-horror story for YouTube. Narrated in first person,
present tense, by our recurring main character:
[PASTE CHARACTER TEXT BLOCK]

Series: [PASTE CHOSEN IDEA]

First, write a SERIES BIBLE (keep it short): setting map, rules of the threat, resources
available, 3 side characters, the season's overall arc in [N] episodes with one-line summaries.

Then write EPISODE 1 as a narration script:
- Length: 1,400–1,700 words (about 10–12 minutes spoken)
- First 15 seconds: drop straight into danger, then state the stakes (no intro, no "welcome back")
- Every 60–90 seconds: a new problem, discovery, or decision
- Concrete numbers and details (levels, distances, hours of battery left), like a real log
- End on a cliffhanger that makes Episode 2 unmissable
- Mark scene breaks with [SCENE: short visual description for image generation]
- Plain spoken English, short sentences, no gore beyond what YouTube allows for advertisers
```

### Prompt D: Episode seterusnya (dalam chat yang sama)

E'Calm tekankan perkara ni: **guna prompt penuh setiap kali**, jangan cuma taip "next episode".

```
Write EPISODE [N] following the series bible and everything that happened so far.
Same rules as Episode 1: 1,400–1,700 words, open in the middle of tension, recap the previous
cliffhanger in max 2 sentences, new problem every 60–90 seconds, [SCENE: ...] markers,
end on a cliffhanger. Do not repeat a scene or escape method already used.
```

### Prompt E: Description SEO (Claude)

```
Write a YouTube description for a survival-horror story episode.
Title: [TITLE]
Target keywords (from vidIQ): [PASTE 6–7 KEYWORDS]
Script: [PASTE SCRIPT]

Rules: first 2 lines (shown before "more") must hook AND contain the main keyword naturally.
Then a spoiler-free 3–4 sentence summary, a line pointing to the series playlist,
5 timestamps based on the [SCENE] breaks, and 3 hashtags. No keyword stuffing. Under 1,500 characters.
```

### Prompt F: Thumbnail (ChatGPT atau Gemini)

```
Create a 1280x720 YouTube thumbnail in the same 2D animated style as this character:
[PASTE CHARACTER TEXT BLOCK, and upload the reference sheet]
Scene: [ONE dramatic moment from the episode]
Composition: character large on the left third with a clear emotion (fear/determination),
the threat or location on the right, high contrast, one bright accent colour.
Text: max 3 words, huge, e.g. "DAY 1" or "DON'T OPEN".
Model the style on these reference thumbnails (do not copy them): [upload 2–3 from top channels]
```

---

## 6. Aliran kerja penghasilan (RM0)

| Bahagian | Tool percuma | Nota |
|---|---|---|
| Skrip | Claude (percuma) | Baca semula dan betulkan dalam Google Docs sebelum guna |
| Voiceover | CapCut text-to-speech, atau ElevenLabs free tier | ElevenLabs ada had karakter setiap bulan. Pilih suara yang tak ramai orang guna. |
| Gambar scene | ChatGPT / Gemini + character text block + reference sheet | Satu gambar setiap tanda [SCENE] |
| Animasi | Google Flow (image-to-video) | Kredit percuma terhad. Animasikan **30 saat pertama** dulu, selebihnya guna gambar dengan zoom/pan. |
| Edit | CapCut | Kesan bunyi, zoom perlahan, caption |
| Thumbnail | Prompt F | Buat 2 versi dan guna **Test & Compare** dalam Studio |

**Masalah bajet percuma:** satu episod mungkin ambil 1–2 hari. E'Calm sendiri cakap kelajuan penting, iaitu 1 episod setiap 1–2 hari untuk bina momentum. Cara atasi: **siapkan 3–5 episod dulu sebelum upload episod pertama.**

---

## 7. Checklist setiap kali upload

- [ ] Title dari Prompt B (≤ 60 karakter)
- [ ] Description dari Prompt E
- [ ] Thumbnail
- [ ] **Playlist:** buat satu playlist untuk setiap siri (nama = tajuk siri). Semua episod siri tu masuk playlist yang sama.
- [ ] Tags: 10–15 keyword dari vidIQ
- [ ] Category: Entertainment · Language: English · Altered content: ikut gaya visual
- [ ] Save sebagai **Unlisted** → tunggu pemprosesan HD siap → baru tukar ke **Public**
- [ ] Ikut jadual yang sama setiap kali, contohnya setiap 2 hari pada 8 malam waktu US Eastern (9 pagi Malaysia)

---

## 8. Pelan 14 hari pertama

| Hari | Kerja |
|---|---|
| 1 | Langkah akaun (Bahagian 3) + Prompt A (branding) + settings (Bahagian 4) |
| 2 | Prompt B, pilih siri, Prompt C (bible + Ep 1) |
| 3–6 | Tulis Ep 2–5 (Prompt D), hasilkan Ep 1–3 |
| 7 | Upload Ep 1 |
| 9, 11, 13 | Upload Ep 2, 3, 4 sambil siapkan episod seterusnya |
| 14 | Semak Analytics: CTR (sasaran > 5%) dan average view duration (sasaran > 40%) |

**Lepas 14 hari:** kalau CTR rendah, tukar thumbnail atau title. Kalau orang berhenti tengok awal, betulkan 30 saat pertama skrip.

---

## 9. Jangkaan realistik

- **Syarat iklan YPP:** 1,000 subscriber + 4,000 jam tontonan public dalam 12 bulan (atau 10 juta Shorts views dalam 90 hari). Sahkan dalam YouTube Studio → Earn, sebab syarat boleh berubah.
- **Polisi "inauthentic content":** YouTube boleh tolak monetization untuk channel yang upload kandungan berulang atau dihasilkan secara pukal. Pastikan setiap episod ada cerita, lokasi dan keputusan yang betul-betul berbeza, dan skrip disunting oleh awak sendiri. Kalau ikut Bahagian 5–6, ini sepatutnya selamat, tapi tiada jaminan.
- **RPM** $5–8 yang disebut dalam video tu angka channel dia untuk penonton English (banyak dari US). Channel lain mungkin dapat lebih rendah.
