# UI Design Brief — Inventory / Monster / Skills

**Version**: 1.0
**Last Updated**: 2026-06-08
**Author**: Owner + Claude
**Status**: Brief untuk eksekusi desain (siap dipakai sebagai prompt Claude design)

> **Cara pakai**: tempel bagian §1–§3 + satu §layar ke Claude design per sesi.
> Semua token warna/ukuran di sini SUDAH hidup di kode (`UITheme`,
> `RarityConfig.display`, `ElementConfig.display`) — desain harus memakainya,
> bukan menciptakan palet baru.

---

## 1. Konteks game

Multi-place creature-hunter Roblox, mobile-first, audiens anak (kid-friendly,
zero-P2W). Loop: tangkap monster (roll element + rarity + personality) →
taruh di Kandang (idle coin) → summon lawan boss → level → evolve ✨.
Vibe: ceria-petualang, rounded, gelap-lembut dengan aksen warna cerah
(BUKAN horror, BUKAN korporat).

## 2. Design tokens (WAJIB dipakai)

### Warna dasar (UITheme)
| Token | Pakai untuk |
|---|---|
| `Panel` (gelap) | latar panel/kartu |
| `PanelLight` | baris/slot di atas panel |
| `SlotEmpty` | slot kosong / tombol non-aktif |
| `Stroke` | garis tepi default |
| `Text` / `TextDim` / `TextOnBright` | teks |
| Aksi: hijau `#2A9D71` (beli/taruh), merah hangat `#E76F51` (ambil/bahaya), ungu `#A855F7` (evolve) | tombol aksi |

### Rarity (border → gradien → glow, makin langka makin mewah)
| Tier | Hex | Treatment kartu |
|---|---|---|
| Common | `#9CA3AF` | border tipis polos |
| Uncommon | `#22C55E` | border + tint latar 10% |
| Rare | `#3B82F6` | border tebal + gradien latar |
| Epic | `#A855F7` | gradien + corner shine |
| Legendary | `#F59E0B` | gradien emas + glow + partikel halus |

### Element (ikon + warna)
🔥 `#FF5A3C` · 🌿 `#3CB043` · 💧 `#3C8DFF` · ⚡ `#FFD23C` · 🌪️ `#9AD7D8`

### Evolusi
Stage 0 (tanpa badge) → 1 ✨ → 2 🌟 → 3 💫 (+aura warna elemen di dunia)

### Aturan teknis Roblox
- Touch target ≥ 44px; grid kartu monster ≥ 84px
- `TextScaled` + font Gotham (Bold/Heavy untuk judul)
- Corner radius: panel 20, kartu 12, tombol/badge 8–10
- Mockup dasar 1280×720; UIScale menangani resolusi lain
- ViewportFrame tersedia untuk render model 3D di UI

---

## 3. Pola navigasi yang sudah ada (jangan diubah)

Top bar pojok kanan-atas: `Inventory | Monster | Skill | Galery | Mission`
→ membuka SATU panel tengah ber-tab. Coin HUD kiri-atas. Panel ⚔ Summon
kanan (collapsible). Layar yang didesain = ISI panel tengah per tab.

---

## 4. LAYAR: 🎒 Inventory ("laci yang rapi")

- **Grid slot 4–5 kolom**, slot kotak rounded `PanelLight`, ikon item besar
  di tengah, **badge count** pojok kanan-bawah (pill gelap "×12")
- Section header per kategori: `CONSUMABLE` (Capture Net), `KEY ITEMS`
  (Raid Token — placeholder), header kecil `TextDim` huruf kapital
- **Slot kosong terlihat**: outline putus-putus `SlotEmpty` — rasa "bisa diisi"
- Tap slot → **drawer detail** naik dari bawah (≈40% tinggi): ikon besar kiri,
  nama + deskripsi kanan, baris aksi ("🛒 Beli lagi" → arah ke shop Kandang)
- Empty state: ilustrasi tas + "Backpack kosong — beli Capture Net di Kandang!"

Item saat ini: `Capture Net` 🕸️ (Consumable). Desain harus memuat 12+ jenis
item ke depan tanpa redesign.

## 5. LAYAR: 🐾 Monster (hero screen — paling mewah)

- **Baris filter/sort** di atas grid: chips `Semua 🔥 💧 ⚡ 🌿 🌪️` +
  dropdown sort `Level ↓ | Rarity ↓ | Terbaru`
- **Kartu grid** (3 kolom mobile): 
  - Latar: gradien sesuai rarity (lihat token §2)
  - **ViewportFrame model 3D monster** (pose statis) memenuhi 60% kartu
  - Pojok kiri-atas: ikon elemen; kanan-atas: badge evo ✨/🌟/💫
  - Bawah: nama personality (HYPER) + `Lv 12` + bar XP tipis
  - Indikator status kecil: 🏠 (di kandang) / ⚔ (sedang summon) — abu jika di tas
- Tap kartu → **halaman detail** (mengganti isi panel, ada tombol ←):
  - Layout 2 panel (kiri: model 3D besar bisa diputar + nama + badges;
    kanan: HP/Power, XP bar, riwayat menang/coins, tombol aksi)
  - Tombol aksi stack: `⚔ SUMMON` (hijau) `🏠 TARUH` (biru) `✨ EVOLVE` (ungu,
    menampilkan biaya + syarat level)
  - Mobile sempit: stack vertikal, model di atas
- Empty state: siluet monster + "Belum ada monster — ayo berburu! 🕸️"

## 6. LAYAR: 🌟 Skills (pohon 3 jalur)

- **3 jalur vertikal** berdampingan dengan header ikon:
  `⚔ SUMMONER` · `🏠 KANDANG` · `🕸️ HUNTER`
- Node = lingkaran 56px tersambung **garis konektor vertikal**; garis menyala
  (warna jalur) saat node di atasnya dimiliki
- State node:
  - ✅ Dimiliki: penuh warna jalur + glow tipis
  - 💰 Bisa dibeli: outline pulse + label harga di bawah node ("25K 🪙")
  - 🔒 Terkunci: abu `SlotEmpty` + ikon gembok kecil
- Tap node → tooltip/popover: nama, efek, harga, syarat (node sebelumnya)
- Header layar: saldo koin (mirror) + spacer untuk "Reset" (nanti)
- Konten awal (placeholder S5 — tampilkan sebagai 2 node pertama jalur
  SUMMONER): `Slot Summon ke-4 (25K)` → `Slot Summon ke-5 (250K)`; jalur lain
  penuh node 🔒 "???" — pohon terlihat LUAS sejak hari pertama (aspirasional)

## 7. Komponen bersama (design system mini)

- **Badge**: pill rounded-8, ikon + teks pendek; varian: count (×12), level
  (⭐ Lv12), rarity (◆Rare berwarna), status (🏠/⚔)
- **Tombol aksi**: tinggi 48–52, rounded-12, ikon + label, 3 state
  (normal / disabled-redup / loading)
- **Drawer bawah** (mobile) & **popover** (tooltip node) — satu pola konsisten
- **Empty state**: selalu ilustrasi + 1 kalimat ajakan + (opsional) 1 tombol
- **Transisi**: panel fade+scale 0.15s; drawer slide 0.2s; JANGAN berlebihan

## 8. Deliverable yang diminta dari sesi desain

1. Mockup statis 1280×720 per layar (3 layar) + varian mobile sempit (≈ 9:16)
2. Spritesheet/spec komponen bersama (§7)
3. Anotasi spacing + warna (pakai token §2 by name)
4. Bonus: state varian (empty / penuh / Legendary card / node pulse)
