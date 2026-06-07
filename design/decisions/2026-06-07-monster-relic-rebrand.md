# Rebrand Tematik — Monster Relic — 2026-06-07

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved, lore disetujui 2026-06-07)
**Type**: Theme/lore decision document — melapis di atas `2026-05-29-vision-pivot.md`. **Mekanika TIDAK berubah**; yang berubah adalah tema, lore, dan penamaan.

> **Relasi ke Vision Pivot Doc**: Kedelapan keputusan mekanik di `design/decisions/2026-05-29-vision-pivot.md` **tetap berlaku penuh** (multi-place universe, item-based capture, 3-tier boss, Pet AI pillar, token economy, rarity pyramid, dll.). Dokumen ini HANYA mengganti lapisan tema: "Brainrot / The Feed / internet-as-place" → "Monster Relic / reruntuhan peradaban kuno". Konflik penamaan apa pun diselesaikan dengan tabel pemetaan §4 di bawah.

---

## 1. Lore baru (LOCKED — verbatim dari owner)

> Ratusan tahun lalu, sebuah peradaban kuno yang sangat maju runtuh akibat bencana misterius yang berasal dari sebuah **Relic Inti**, sumber energi utama kerajaan tersebut. Ledakan energi relic tidak hanya menghancurkan kerajaan, tetapi juga mengubah makhluk hidup di sekitarnya menjadi **Monster Relic**.
>
> Sejak saat itu, monster-monster tersebut berkeliaran di reruntuhan kuno dan berkembang menjadi berbagai spesies dengan **elemen dan kemampuan yang berbeda**. Sebagian monster bersifat **liar**, sementara sebagian lainnya masih menjalankan tugas mereka sebagai **penjaga kuil, gerbang, dan harta peninggalan** kerajaan kuno.
>
> Pemain berperan sebagai seorang **Relic Hunter** yang menjelajahi reruntuhan untuk mengungkap rahasia jatuhnya peradaban tersebut, sekaligus menjinakkan dan mengumpulkan Monster Relic yang tersebar di seluruh dunia.

---

## 2. Mengapa lore ini cocok dengan struktur yang ada

Lore ini memetakan 1:1 ke arsitektur pasca-pivot — **tidak ada mekanika yang perlu diubah**:

| Elemen lore | Sistem yang sudah ada | Catatan |
|---|---|---|
| Monster liar berkeliaran di reruntuhan | Wild spawns di Areas (#4 Capture v2) | Area theme (Forest/Cave/Sky) → zona reruntuhan bertema |
| Monster penjaga **kuil** | Tier 2 Super Boss (sub-place standalone) | Mengganti kandidat nama "CEO Brainrot" |
| Monster penjaga **gerbang** | Tier 1 Colony Boss (di shared Area) | Penjaga gerbang zona — alasan natural ia spawn di area |
| Monster penjaga **harta peninggalan** | Tier 3 Raid Boss (Raid Dungeon, token-gated) | Dungeon = vault harta kerajaan; loot Legendary = harta |
| Relic Hunter menjinakkan & mengumpulkan | Capture + roster + Kandang | Player fantasy: hunter, bukan manager |
| Mengungkap rahasia keruntuhan | Quest/narrative hook (#17 Daily Quests, FTUE #14) | Memberi spine naratif untuk progresi area unlock |
| **Relic Inti** (sumber bencana) | (baru — endgame hook) | Kandidat final raid content / Phase 2 narrative |

---

## 3. Keputusan yang dikunci

### Keputusan R1: Kreatur = **Monster Relic** (EN: Relic Monster)
Semua referensi "Brainrot" sebagai kreatur diganti **Monster Relic**. Di docs berbahasa campuran, "Monster" cukup sebagai sebutan pendek.

### Keputusan R2: Player fantasy = **Relic Hunter**
Frame "manager/CEO perusahaan brainrot" dibuang. Player = penjelajah/pemburu. Implikasi penamaan turunan: leaderboard "Richest Manager" → **"Richest Hunter"** (slot/key DataStore tetap — lihat §6 catatan kode).

### Keputusan R3: Setting = **Reruntuhan peradaban kuno**
"The Feed" (internet-as-place) **DIBATALKAN** sebagai setting. Dunia = reruntuhan kerajaan kuno yang maju. Lobby = kamp/kota hunter (nama working: **Hunter Camp**, final TBD). Areas = zona reruntuhan bertema (hutan menelan reruntuhan, gua bawah kuil, puncak menara langit, dst.).

### Keputusan R4: Nama game = **"Brainrot Inc." DIPERTAHANKAN SEMENTARA**
Owner memutuskan nama game tetap dulu (2026-06-07). Rename title = open decision terpisah; tidak memblokir pekerjaan docs/kode. Working title internal boleh pakai **"Project Relic"** di dokumen desain baru.

### Keputusan R5: Scope eksekusi = **Konsep & docs dulu, kode menyusul**
- **Sekarang**: decision doc ini + revisi vision-pivot + systems-index + rebrand notice di GDD aktif + GitHub issues.
- **Nanti (per-sistem saat dikerjakan)**: rename identifier kode (`Brainrot_` prefix, `BrainrotAI`, `addBrainrot`, project name `BrainrotInc`, dst.). Kode shipped (#1/#2/#3) TIDAK disentuh sampai ada alasan fungsional.

---

## 4. Tabel pemetaan penamaan (kanonik)

| Konsep | Nama lama | Nama baru | Status |
|---|---|---|---|
| Kreatur | Brainrot | **Monster Relic** | ✅ LOCKED |
| Player fantasy | Manager (idle inc.) | **Relic Hunter** | ✅ LOCKED |
| Setting dunia | The Feed (internet) | **Reruntuhan kuno** (nama dunia TBD) | ✅ LOCKED (nama TBD) |
| Nama game | Brainrot Inc. | (tetap sementara) | 🚧 open decision |
| Lobby | Lobby (social square) | **Hunter Camp** (working) | 🚧 nama final TBD |
| Tier 1 boss | Colony Boss | **Colony Boss / Gate Guardian** | 🚧 pilih satu |
| Tier 2 boss | 🚧 (kandidat: CEO Brainrot / Apex / Overlord) | **Temple Guardian** (kandidat utama — penjaga kuil per lore) | 🚧 confirm |
| Tier 3 boss | Raid Boss | **Vault Guardian / Raid Boss** | 🚧 pilih satu |
| Tier 3 location | Raid Dungeon | **Ancient Vault / Treasure Vault** (kandidat) | 🚧 confirm |
| Raid token | 🚧 (kandidat: Raid Token / Dungeon Key / Boss Pass) | **Relic Key** (kandidat utama — kunci gerbang/vault per lore) | 🚧 confirm |
| Capture item | Forest Item / Cave Item / Sky Item | **🚧 TBD** — kandidat: `Relic Charm` per-area, `Snare Stone` | 🚧 confirm |
| Currency | Meme Coins | **🚧 TBD** — kandidat: `Relic Shards`, `Ancient Coins` | 🚧 confirm |
| Premium currency (P2) | Brain Cells | **🚧 TBD** — kandidat: `Relic Cores`, `Core Fragments` | 🚧 confirm |
| Private base | Kandang | **Kandang** (tetap — masih cocok: kandang monster) | ✅ keep |
| Leaderboard | Richest Manager | **Richest Hunter** | ✅ LOCKED (label UI; key DataStore tetap) |
| Personality 5 | Hyper/Lazy/Chaotic/Loyal/Rebel | (tetap — netral tema) | ✅ keep |

**Catatan elemen (BARU dari lore)**: lore menyebut monster berkembang "dengan **elemen** dan kemampuan berbeda". Sistem saat ini punya **Personality** (behavior axis), BELUM punya **Element** (combat affinity axis). Lihat §7 open decisions — apakah Element jadi sistem mekanik baru (type chart ala Pokémon) atau flavor katalog spesies saja.

---

## 5. Yang TIDAK berubah (preserved)

- ✅ Semua 8 keputusan Vision Pivot 2026-05-29 (arsitektur, capture, boss tiers, Pet AI, token, rarity pyramid)
- ✅ Semua kode shipped: Persistence, Personality, Economy, Leaderboard write, demo/prototype (rename identifier menyusul per Keputusan R5)
- ✅ Semua angka locked: Level/XP curve, baseRatePerWorker 0.5, pendingPoolCapBase 3600, DevProduct ladder, 3 GamePasses, zero-P2W
- ✅ Build order pasca-pivot: #27 World Universe tetap NEXT BLOCKER
- ✅ 5 personality + behavior tags
- ✅ Struktur GDD + systems-index numbering

---

## 6. Catatan kode (untuk eksekusi nanti, per-sistem)

- **Key DataStore TIDAK di-rename** (`Leaderboard_RichestManager_v1`, schema fields, dll.) — data live tidak boleh pecah; rename hanya di label UI/docs. Jika suatu saat mau migrasi key, itu butuh ADR tersendiri.
- Identifier kode (`Brainrot_` prefix, `BrainrotAI.server.luau`, `BrainrotPack.server.luau`, `addBrainrot`, project `BrainrotInc`) di-rename **saat sistem ybs. dikerjakan**, bukan big-bang.
- Prototype pack (`PackConfig.luau` + `BrainrotPack.server.luau`) boleh tetap bernama Brainrot sampai digraduasi/dibuang.

## 7. Open decisions (baru + carry-over yang terdampak)

Baru dari rebrand ini:
1. ~~**Element system** — mekanik baru (type chart, weakness/resist) atau flavor saja?~~ ✅ **RESOLVED (2026-06-07)** — light chart, 5 elemen (Fire/Nature/Water/Volt/Wind), roll uniform saat capture, no reroll, ±25% config-driven. Lihat `design/decisions/2026-06-07-element-system.md`.
2. Nama final: game title, dunia, Lobby/Hunter Camp, currency, capture item, token, ketiga nama boss tier (lihat 🚧 di §4).
3. **Relic Inti** — dipakai sebagai endgame raid content sekarang, atau disimpan untuk Phase 2 narrative?
4. Spesies monster — katalog spesies (berapa spesies di launch? per area berapa?) — masuk world-universe-gdd / capture-v2-gdd.

Carry-over dari Vision Pivot (masih open, sekarang dengan konteks baru):
- Token consumption rule (refund on fail?), token cap, DevProduct ladder harga
- Capture item success rate formula + pricing
- Colony Boss HP scaling
- Friendship gating Trade + Stardust analogue
- Jumlah Area di launch

---

## 8. GDD yang terdampak — mapping aksi

| Dokumen | Aksi |
|---|---|
| `design/decisions/2026-05-29-vision-pivot.md` | Tambah revision note → menunjuk ke doc ini (tema diganti, mekanik tetap) |
| `design/gdd/systems-index.md` v3.0 | Bump v3.1 — revision note + update World context + istilah kunci |
| `design/gdd/persistence-gdd.md` | Rebrand notice (terminologi saja; schema/data tidak berubah) |
| `design/gdd/personality-gdd.md` | Rebrand notice (personality netral, survive utuh) |
| `design/gdd/economy-gdd.md` | Rebrand notice + tandai "Meme Coins" sebagai nama TBD |
| `design/gdd/evolution-gdd.md` | Rebrand notice |
| `design/gdd/pet-combat-gdd.md` | Rebrand notice + flag open decision Element system |
| `design/gdd/capture-gdd.md` | Rebrand notice (sudah ditandai rewrite-pending sejak pivot) |
| `design/gdd/idle-production-gdd.md` | Rebrand notice (sudah ditandai rewrite-pending sejak pivot) |
| GDD baru (world-universe, boss-system, capture-v2, dll.) | Ditulis langsung dengan terminologi baru |
| GitHub issues | Update judul/deskripsi yang menyebut Brainrot (butuh `gh auth login`) |

---

## 9. Audit trail

| Tanggal | Perubahan | Oleh |
|---|---|---|
| 2026-06-07 | Lore Monster Relic disetujui owner; rebrand doc ini ditulis; scope "konsep & docs dulu" dikunci | Owner + Claude |

---

**END OF REBRAND DOC.** Keputusan tema setelah tanggal ini harus rekonsiliasi terhadap doc ini; keputusan mekanik tetap rekonsiliasi terhadap Vision Pivot Doc 2026-05-29.
