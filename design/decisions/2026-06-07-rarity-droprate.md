# Rarity & Drop Rate — 2026-06-07

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved 2026-06-07)
**Type**: System decision document — melengkapi S3 (rarity 5 tier) dari
`2026-06-07-economy-sinks-fase0.md`. Mengunci distribusi roll, drop boss, dan
payoff stat per rarity.

> Cross-ref: Vision Pivot **Decision 8** (rarity-by-source pyramid, LOCKED),
> `2026-06-07-economy-sinks-fase0.md` S2/S3 (evolveCost × rarityMult),
> `first-hour-daily-loop-gdd.md` (first-kill harian — pengikat drop boss),
> `2026-06-07-element-system.md` (pembanding kekuatan ±25%).

---

## Filosofi (turunan Decision 8)

**Rarity datang dari SUMBER, bukan satu kolam gacha.** Catch wild tidak pernah
menghasilkan Rare+ — tier tinggi adalah hadiah KONTEN (boss). Progresi =
mainkan kontennya, bukan berdoa pada roll. Kid-friendly, zero-P2W-aligned.

```
Wild (catch)        → roll Common 80% / Uncommon 20%
Colony Boss (kill)  → DROP Rare: 20% first-kill harian / 2% berulang
Super Boss  [nanti] → Epic (angka saat boss-system-gdd)
Raid Boss   [nanti] → Legendary (angka saat boss-system-gdd)
```

## Keputusan terkunci

### R1: Roll wild = **Common 80% / Uncommon 20%**
Server-side saat mint (bersama roll element + personality). "Catch sempurna"
(elemen target + Uncommon) ≈ 4% — momen seru organik tanpa sistem tambahan.

### R2: Drop Rare boss = **20% first-kill/hari/tipe, 2% kill berulang**
- Terikat infra first-kill harian (#28 langkah 4) — **kedua fitur saling
  mengunci dan dibangun bersama**.
- Ekspektasi pemain harian penuh (5 tipe boss): ≈ **1 Rare/hari**.
- Tanpa ikatan ini boss respawn 30 detik = farm Rare 10 menit → nilai runtuh.
- Drop = langsung masuk roster (bukan catch); roster penuh → drop dibatalkan
  dengan banner (jangan auto-release apa pun).

### R3: Stat multiplier per rarity = **moderat ×1.0–×2.0**

| Rarity | rollWild | statMult | evolveMult (S2) | Badge |
|---|---|---|---|---|
| Common | 80% | ×1.0 | ×1.0 | abu-abu `#9CA3AF` |
| Uncommon | 20% | ×1.15 | ×1.5 | hijau `#22C55E` |
| Rare | boss drop | ×1.35 | ×2.5 | biru `#3B82F6` |
| Epic | (nanti) | ×1.6 | ×4.0 | ungu `#A855F7` |
| Legendary | (nanti) | ×2.0 | ×6.0 | emas `#F59E0B` |

`statMult` dikalikan ke HP + damage turunan fighter (faktor sejajar
`levelScale` dan evolusi). **Urutan kekuatan yang dijaga**:
`level (≤×8.9) > evolusi (≤×2.0) ≥ rarity (≤×2.0) > element (±25%)` —
usaha tetap mengalahkan keberuntungan; Legendary Lv1 kalah dari Rare Lv20.

### R4: Yang sengaja TIDAK ada (sederhana dulu)
- ❌ Pity / bad-luck protection (tambah nanti jika playtest terasa kejam)
- ❌ Capture item memengaruhi odds rarity (item = akses, bukan keberuntungan;
  revisit di Capture v2)
- ❌ Sub-tier / bintang / upgrade rarity

### R5: Schema & backfill
- `entry.rarity: "Common"|"Uncommon"|"Rare"|"Epic"|"Legendary"` — aditif.
- Backfill roster lama: **roll 80/20** (pola element backfill — hindari
  semua-Common membanjiri ekonomi trade nanti). Idempotent: rarity valid
  yang tersimpan tidak pernah di-re-roll (permanen, seperti element).
- Demo: roll wild aktif langsung; drop Rare boss menunggu infra first-kill.

## Audit trail

| Tanggal | Perubahan | Oleh |
|---|---|---|
| 2026-06-07 | R1–R5 dikunci (80/20, 20%/2% first-kill, statMult moderat) | Owner + Claude |
