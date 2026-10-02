# Sabily — brag plan

`/brag` (slim) · tone **"confident eSIM travel app launch"** (≈ app-store × cinematic) · built with the **reel-motion-stack**.

## 1 · Header

- 1080×1920, 30 fps, **21.0 s**. HyperFrames 0.8.82 (HTML/CSS/GSAP → MP4), one paused GSAP timeline, Three.js through the `three` adapter for the globe.
- Inputs: real Sabily footage recorded today from the current working tree (profile build, `sabily_test` AVD, Arabic UI, live `api.sabily.fr` catalogue), `brands/sabily` assets (intro sting, logo, card background), `assets/pack_art/geo.json` + `assets/pack_art/flags/*.svg` (the app's own pack-art geometry and flags).
- No voice, so there is no words.json: **the soundtrack's beat grid is law** (120 BPM, bar lines at 0.5 s + 2k). Every cue below sits on that grid.

## 2 · Language

- Headlines in **Algerian darja**, `dir="rtl"`; Latin words (connecté, QR, Istanbul, eSIM, €5) in `dir="ltr"` spans with `unicode-bidi: isolate`.
- Fonts: **Cairo 800** (Arabic), **Inter 700** (Latin), **JetBrains Mono** (Figma size labels). All shipped locally.
- The app itself is shown in its own **Arabic RTL UI**. That is a flex in its own right: the whole app mirrors.

## 3 · Style bible

- **Zones**: signal pill y 150–222 · caption band y 270–600 · hero y 620–1750 · bottom 170 px left clear for the Reels UI (phone bleeds off the bottom and fades into the background).
- **DARK** = Sabily pack-art ground `#0F4846 → #002524` (the app's own palette formula) + 72 px grid at 6 %. **LIGHT** = Sabily cream `#F9F2D3` + 72 px grid in deep teal at 6 %.
- **Captions**: word-by-word blur-in (blur 14 → 0, y 30 → 0, 0.4 s, 0.14 s stagger), landing at 100 % so every line is readable.
- **Keyword**: Figma-selection box, `#2F6BFF` 3 px, 4 white corner handles, a `W × H` size label in JetBrains Mono, plus a Fluent 3D emoji sticker.
- **Cards** 28 px radius; the phone is a dark bezel (#0D1413) with a punch-hole, screen radius 62 px.
- **Transitions**: vertical whip pans with a vertical-only motion blur (SVG `feGaussianBlur stdDeviation="0 N"`), LIGHT ↔ DARK alternating every scene.
- **Accents**: Sabily yellow `#FADB14`, mint `#D2F5EC`, logo green `#58B87A`, arc gold `#E0B84A`; Figma blue only on selection boxes.
- **Recurring motif + countdown pill**: a liquid-glass signal pill (4 bars). It starts empty with a ✕ (you just landed, no network), gains one bar per highlight, and at the QR it fills and says **"راك connecté ✓"**.

## 4 · Scenes (cues pinned to the 120 BPM grid)

| # | Time | Bg | What happens | Headline (darja) | Keyword |
|---|---|---|---|---|---|
| S1 HOOK | 0.0–2.5 | DARK | Riser, then **impact at 0.5**. A 3D globe (the app's globe pack art rebuilt in Three.js: same gradient, graticule, white land, #DBE2E1 countries, white rim) snaps in spinning. Flag pins pop on the 8 `popularDestinations` (SAU TUR ARE EGY MAR GBR FRA DZA). Gold flight arcs draw from Algiers to Istanbul, Jeddah, Paris, Dubai. Pill: 0 bars ✕. | سافر… وابقى connecté | connecté 📶 |
| S2 REVEAL | 2.5–4.5 | LIGHT | The client's **original logo animation** (`E:\disk f\Work\Sabily\sabily logo animation final.mp4`, 1080p), speed-ramped from 8.1 s into 2.9 s, ending on the "Sabily / Never be alone" lockup. | الـ eSIM تاع السفر | — |
| S3 +200 | 4.5–7.5 | DARK | Phone rises. Real footage: Store (Arabic) "أكثر من 200 وجهة", carousel "الأكثر اختيارًا للحجاج والمسافرين" swipes Saudi → Türkiye → UAE → Egypt → Morocco → UK. Pill 1 bar. | ‎+200 وجهة · اختار وين رايح | +200 🌍 |
| S4 PACK | 7.5–10.5 | LIGHT | Tap Türkiye, cut to its page, scroll to **One-off Turkey 1GB 7 day(s) · €5.00** and its yellow CTA, then a tap on "اشترِ هذه الباقة". Pill 2 bars. | تركيا؟ · باقة بـ €5 | €5 💶 |
| S5 TRIP | 10.5–13.5 | DARK | Multi-country trip: Türkiye + Saudi Arabia chips, tap "عرض الباقات (2)", results slide in, push-in on **الخيار الأفضل — covers your 2 countries + 6 others**. Pill 3 bars. | عمرة و Istanbul؟ · باقة وحدة تكفي | باقة وحدة ✈️ |
| S6 eSIM | 13.5–16.5 | LIGHT | **My eSIMs** (the screen you sent, live in Arabic: active plans, usage bars, "إعادة الشحن"), tap the Turkey eSIM, detail, push-in on the **QR**. At 15.5 the pill fills: **راك connecté ✓** + success chime. | سكاني الـ QR… · وخلاص! | QR 📲 |
| S7 OUTRO | 16.5–18.5 | DARK | Big hit. Sabily logo over the returning globe. Punchline on the name (sabil = path) + `sabily.fr`. | Sabily · سبيلك للدنيا كامل | سبيلك 🧭 |
| S8 END | 18.5–21.0 | LIGHT | @yaziid_dx profile card; cursor clicks **Follow**, which becomes **Following ✓**. Final tonic chord at 20.5. | — | — |

Readability: every headline is 2–5 words, fully landed by +0.9 s and held at least 1.6 s.

### Music cue guidance (composed for this cut, not a library track)

120 BPM, D major, bars at 0.5 + 2k: `D | G (breakdown under the sting) | D A Bm G | D Bm | G (outro) | A (end card) → D`, landing on the tonic at 20.5. Kick 4/4 · offbeat hats · octave bass sidechained to the kick · 16th pluck arp · supersaw pad · Freeverb. SFX are voiced from the same chord tones and sit under the music: taps on A5, the size-label ticks on chord tones, the success chime is a D-major bell arpeggio, whooshes are band-passed noise sweeps into each whip. Master: soft-clip plus peak normalise, about −14 LUFS.

## 5 · Process

1. Record real footage (done: 4 clips plus stills; demo eSIMs are the app's own debug data, never a real account).
2. Cut segments with ffmpeg (trim the ~2–3 s blank frames the emulator shows on each route push; transitions between app states are re-animated in the composition).
3. Build `composition/index.html` → `npx hyperframes lint` → stills at every scene and mid-whip → fix → `check`.
4. Synthesize `soundtrack.wav` (music + SFX as one mix).
5. English cut: `composition-en/` = `make_en.py` over the Arabic composition + English-UI footage (`cut_segments.sh en`).
6. Render → `brag.mp4`, pick the best settled frame → `brag.jpg`, bake it as frame 0, write `share-copy.txt`.

## Facts checked before building

- "+200 وجهة", "€5.00 Turkey 1GB 7 days", "covers your 2 countries + 6 others", "installs by QR / on this device" are all read off the live app today.
- **No store badges.** This Flutter rebuild isn't on the stores yet (CLAUDE.md: not verified on a real phone; iOS doesn't exist), so the outro points to `sabily.fr`.
- Avoided on screen: the Azerbaijan and South Africa country art (both currently render the wrong image), the demo eSIM's `smdp.example.com / FAKE-MATCHING-ID` text, and the keyboard (its clipboard chip shows a local Windows path).
