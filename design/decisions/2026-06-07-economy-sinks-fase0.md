# Economy Sinks Fase 0 — 2026-06-07

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved 2026-06-07)
**Type**: System decision document — hasil diskusi economy mendalam pasca sink
pertama (`1fbc71a`). Mengunci sink berikutnya + sistem rarity dasar.

> Cross-ref: `economy-gdd.md` v1.3 (faucet/sink + kurva LOCKED),
> `evolution-gdd.md` v1.3 (Axis A/B), Vision Pivot Decision 2 (item capture)
> + Decision 8 (rarity pyramid), `first-hour-daily-loop-gdd.md` v1.0,
> `2026-06-07-element-system.md` (aura warna elemen).

---

## Keputusan terkunci

### S1: Level-up monster BERBAYAR DIBATALKAN → diganti EVOLUTION sink
Usulan awal "beli level dengan koin" **ditolak** karena bertabrakan dengan lock
`evolution-gdd` Axis B (*"XP comes ONLY from WINNING battles"*) — koin akan
mem-bypass combat dan mematikan loop berburu. Gantinya: **Evolution** menjadi
sink per-monster (S2). Ide "training berbayar" juga di-park (tidak dibangun).

### S2: Evolution = HYBRID "layak dulu, bayar untuk memicu"
```
Syarat evolve = MILESTONE (gratis, dari bermain) + BIAYA AKTIVASI (koin = sink)

evolveCost(stage, rarity) = baseCost[stage] × rarityMult[rarity]
baseCost   = { 2500, 30000, 300000 }   -- stage 1/2/3 (basis Common)
rarityMult = { Common = 1.0, Uncommon = 1.5, Rare = 2.5, Epic = 4.0, Legendary = 6.0 }
```

| Stage | Milestone | Efek (demo) |
|---|---|---|
| 1 ✨ | Lv 5 | stat ×1.25, aura tipis |
| 2 🌟 | Lv 15 | stat ×1.5, **aura warna elemen** |
| 3 💫 | Lv 30 | stat ×2.0, aura intens + model sedikit lebih besar |

- **Milestone level SAMA untuk semua rarity** (kelangkaan sudah dibayar via
  koin + sulitnya memperoleh monster; tidak dihukum dua kali).
- Identitas Axis A (work-based) terjaga: milestone = bagian "work"; koin hanya
  pemicu upacara. `evolution-gdd` mendapat revision note (bukan rewrite).
- Total sink per monster Common ≈ 333K; Legendary ≈ 2M. Bersifat per-monster →
  sink agregat menskalakan dengan kekayaan + ukuran roster.
- Field `entry.evoStage` (schema v1, selama ini default 0) menjadi konsumen.
- Sink reason produksi baru: `evolve` (ditambah ke whitelist EconomyConfig
  saat graduasi; demo memakai float debit seperti sink demo lain).

### S3: Rarity = 5 TIER, sesederhana itu dulu
`Common | Uncommon | Rare | Epic | Legendary` — selaras Vision Pivot
**Decision 8** (sumber → rarity: Wild = Common–Uncommon, Colony Boss = Rare,
Super Boss = Epic, Raid Boss = Legendary). Belum ada mekanik tambahan
(tanpa sub-tier, tanpa pity, tanpa upgrade rarity). Field schema aditif
`entry.rarity` menyusul saat dibangun; demo sementara memperlakukan semua
monster **Common (×1.0)** — formula sudah menerima parameter rarity sejak
hari pertama (zero rework).

**Parkir (bahasan rarity lanjutan)**: distribusi rarity wild (Common vs
Uncommon roll?), stat payoff per rarity, warna/badge UI per tier.

### S4: Capture memakai ITEM dari backpack (jalur ke Capture v2)
Mengganti debit koin langsung (sementara di `1fbc71a`) dengan item:
```
Shop (kiosk) → beli Capture Item → backpack (persisted) → catch konsumsi 1 item
```
- Harga efektif tetap **25/item**; bundel **10 = 225** (diskon ~10% —
  pre-commitment "beli 10 jaring dulu, baru berburu").
- 3 free onboarding → menjadi **3 item gratis di backpack** profil baru
  (lebih terlihat daripada counter tersembunyi).
- Selaras **Vision Pivot Decision 2** — demo ini adalah migrasi natural ke
  Capture v2 (area-tier items menyusul bersama World Universe).
- Schema aditif: `items: { [itemId]: number }` + migrasi backfill
  (`freeCapturesRemaining` yang tersisa dikonversi jadi item gratis).
- Sink reason produksi: `capture_item_purchase` (sudah diantisipasi extension
  pivot di economy-gdd notice).
- Nama item placeholder **"Capture Net"**; nama final ikut rebrand
  (kandidat `Relic Charm`, lihat rebrand doc §4).

### S5: Slot summon + efek buff = DITUNDA (big-ticket berikutnya)
Slot summon ke-4/5 (usulan 25K / 250K) adalah sink big-ticket terbaik
berikutnya TAPI seluruh balance boss didesain di sekitar **3 summon** —
keputusan ini WAJIB dibundel dengan open question *Colony Boss HP scaling*
(Vision Pivot Decision 5). Efek/buff summon diarahkan jadi "Hunter skill
tree" terpisah, dibahas tersendiri.

---

## Peta sink lengkap (sesudah build)

| Fase pemain | Sink | Skala | Status |
|---|---|---|---|
| Menit 1+ | Capture Item (25; bundel 225/10) | kecil, berulang | S4 — build #1 |
| Menit 6+ | Upgrade Kandang | 200 → 4.6M | ✅ hidup |
| Menit ~50+ | Evolution ✨ (×rarity) | 2.5K → 1.8M/monster | S2 — build #2 |
| Jam 2+ | Slot summon 4/5 | 25K / 250K | S5 — ditunda |
| Produksi | Reroll (LOCKED 250–2K), Raid Token, Trade fee | — | sistem masing-masing |

## Urutan build (Fase 0) — FINAL pasca lock rarity

> Rarity & drop rate dikunci menyusul di `2026-06-07-rarity-droprate.md`
> (R1–R5) — roll wild 80/20 DILIPAT ke build #1 (satu sentuhan mint path),
> dan drop Rare boss TERIKAT infra first-kill (#28 langkah 4): kedua fitur
> itu dibangun BERSAMA, bukan terpisah.

1. **Capture Item + Shop** (issue #29-1) — schema `items` + migrasi, kiosk/
   shop UI, mint bridge konsumsi item, konversi onboarding, **+ roll rarity
   wild 80/20 + badge warna + statMult (R1/R3)**
2. **Evolution + aura elemen** (issue #29-2) — tombol evolve di stat sheet,
   `evolveCost(stage, rarity)` (rarity kini NYATA, bukan default), stat mult
   di fighter derivation, ParticleEmitter aura warna `ElementConfig.display`
3. **First Hour + Daily Loop** (issue #28) — goal checklist → daily reset →
   3 quest → first-kill bonus **+ drop Rare boss 20%/2% (R2)** → offline cap

## Papan status keputusan economy (akhir sesi 2026-06-07)

| Keputusan | Status |
|---|---|
| Sink Upgrade Kandang + catch berbayar | ✅ LIVE di demo (`1fbc71a`) |
| Capture via item backpack (S4) | 🔒 locked, build #1 |
| Evolution hybrid × rarity (S2) | 🔒 locked, build #2 |
| Rarity 5 tier + roll + drop + statMult (R1–R5) | 🔒 locked, terlipat ke build #1 & #3 |
| First hour + daily loop | 🔒 GDD v1.0, build #3 |
| Slot summon 4/5 (S5) | ⏸️ ditunda — bundel dengan Colony Boss HP scaling |
| Nama currency (ganti "Meme Coins") | ⏸️ TBD rebrand |
| Re-balance rate demo vs GDD (2.0 vs 0.5/s) | ⏸️ belum dibahas |
| Faucet `boss_kill_drop` resmi di whitelist | ⏸️ saat graduasi EconomyService |

## Audit trail

| Tanggal | Perubahan | Oleh |
|---|---|---|
| 2026-06-07 | S1–S5 dikunci dalam diskusi economy; build order ditetapkan | Owner + Claude |
| 2026-06-07 | Rarity R1–R5 dikunci (doc terpisah); build order difinalkan dengan fold-in rarity + interlock #28↔#29; papan status ditambahkan | Owner + Claude |
