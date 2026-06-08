# Catch Rate & Catch Failure — 2026-06-08

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved 2026-06-08) — IMPLEMENTED
**Type**: System decision document — menambahkan **peluang GAGAL** pada capture
(sebelumnya catch selalu 100% sukses) dan mengikat **rarity → tingkat kesulitan
tangkap**.

> Cross-ref: `2026-06-07-rarity-droprate.md` (R1 roll wild, R3 statMult/badge,
> **R4** yang dulu menunda pity — keputusan ini MENCABUT penundaan itu),
> `2026-06-07-economy-sinks-fase0.md` (S4 Capture Net = sink), `capture-gdd.md`
> (ARCHIVED — model timing-minigame; capture nyata sekarang item-based
> ProximityPrompt di jalur pack).

---

## Filosofi

Capture tanpa risiko = hadiah otomatis, tidak ada tension. Owner ingin **ada
kemungkinan gagal** menangkap monster, dan monster yang lebih **langka lebih
sulit** ditangkap. Tetap **kid-friendly**: ada lantai rate (tak pernah 0%) +
**pity** (anti-frustrasi) supaya tidak ada streak gagal yang menyakitkan.

Catch rate **hanya** menentukan peluang berhasil per percobaan. Rarity yang
diroll **tetap** mengikuti R1 (Common 80 / Uncommon 20 dari grass) — rarity itu
yang menentukan kesulitan, dan rarity itu juga yang kamu dapat saat berhasil
("apa yang membuatnya susah, itu yang kamu dapat").

---

## Keputusan terkunci

### C1: Roll **rarity dulu**, baru roll sukses
Server meroll rarity tersembunyi monster (R1: Common 80 / Uncommon 20),
menurunkan peluang sukses dari rarity itu, lalu meroll sukses. Sukses → mint
entry dengan rarity itu. Gagal → rarity dibuang (tidak ada yang di-mint).

### C2: **Rarity memengaruhi catch rate** (langka = lebih susah)
Multiplier per-rarity di `RarityConfig.catchRateMult` (satu sumber, sebaris
`statMult`/`evolveCostMult`):

| Rarity | catchRateMult | Rate efektif (base 0.7, streak 0, sebelum clamp) |
|---|---|---|
| Common | ×1.0 | 0.70 |
| Uncommon | ×0.85 | 0.595 |
| Rare | ×0.65 | 0.455 |
| Epic | ×0.45 | 0.315 |
| Legendary | ×0.30 | 0.210 |

> Rare+ tidak pernah diroll dari grass (R1 weight 0), jadi praktis hanya Common
> & Uncommon yang relevan di jalur wild saat ini. Kolom Epic/Legendary aktif
> ketika sumber lain (boss/raid) memakai jalur catch rate yang sama.

### C3: **Net DIKONSUMSI saat gagal** (`consumeNetOnFail = true`)
Percobaan yang gagal tetap menghabiskan attempt (net / koin / free capture) —
risiko nyata + konsisten dengan sink ekonomi S4. Affordability dicek **dulu**:
percobaan tak terjangkau dibatalkan (rejected) sebelum roll/mutasi apa pun, net
tidak dikonsumsi.

### C4: **Pity (anti-frustrasi)** — mencabut R4 "belum ada pity"
Setiap gagal beruntun pada **personality yang sama** menambah peluang sukses
sebesar `pityStepPerFail`; **reset ke 0** saat berhasil menangkap personality
itu. Session-only (tidak dipersist — tujuannya menghaluskan nasib buruk satu
sesi). Plus **lantai rate** (`minCatchRate`) agar tidak pernah 0%.

### C5: Yang sengaja BELUM ada (boleh nanti)
- ❌ Tier net memengaruhi rate (net biasa vs net premium)
- ❌ Level monster memengaruhi rate
- ❌ Item "guaranteed catch"
- ❌ Pity dipersist lintas sesi

---

## Formula (server-authoritative)

```
1. AFFORDABILITY dulu: butuh ≥1 Capture Net (ITEM MODE) ATAU
   freeCapturesRemaining>0 / coins≥captureCostCoins (LEGACY). Gagal → rejected
   (wild tetap, NET TIDAK dikonsumsi, TIDAK ada cinematic).

2. rarity   = RarityConfig.rollRarity()              -- R1: Common 80 / Uncommon 20
   streak   = state.catchPity[personality] or 0      -- gagal beruntun (session)
   rate     = baseCatchRate * RarityConfig.catchRateMult[rarity]
                + streak * pityStepPerFail
   rate     = clamp(rate, minCatchRate, maxCatchRate)
   success  = catchRng:NextNumber() < rate           -- RNG server, tak pernah dari klien

3a. SUCCESS → mint entry (rarity di atas) PERSIST-FIRST; jika add ditolak
    (roster penuh) → rejected, TIDAK ada charge. Lalu settlePrice() (konsumsi
    net/koin/free), catchPity[personality] = 0, cinematic success (despawn).

3b. FAIL → jika consumeNetOnFail: settlePrice(). catchPity[personality] += 1.
    Toast "💨 Lolos!". Cinematic fail (net mantul, monster tetap, NO shrink).
    Wild diberi failCooldownSec sebelum bisa dicoba lagi.

Where (DemoConfig.catch):
  baseCatchRate     : 0-1, Default 0.7   -- rate dasar Common sebelum pity/clamp
  catchRateMult[r]  : 0.05-1.0           -- RarityConfig (C2); langka = kecil
  pityStepPerFail   : 0-0.5, Default 0.12 -- tambah per gagal beruntun (≈3-4 gagal naik 1 tier)
  minCatchRate      : 0-1, Default 0.15  -- lantai (kid-friendly, tak pernah 0%)
  maxCatchRate      : 0-1, Default 0.95  -- plafon (pity panjang tetap bukan jaminan)
  consumeNetOnFail  : bool, Default true (C3)
  failCooldownSec   : 0.5-5, Default 1.5 -- cooldown re-catch wild yang sama (cover fail cinematic)
```

**Contoh pity (Uncommon, base 0.7):** percobaan 1 = 0.595; gagal → 2 = 0.715;
gagal → 3 = 0.835; gagal → 4 = 0.955→clamp 0.95. ~3-4 gagal beruntun menjamin
mendekati plafon. Sukses kapan saja → streak reset ke 0.

---

## Edge cases

- **Roster penuh saat sukses** → `addBrainrot` ditolak → outcome `rejected`,
  net TIDAK dikonsumsi, wild tetap (mirror persist-first handleCatch).
- **Tidak mampu bayar** → `rejected` sebelum roll; toast koin/net habis.
- **Spam retry** → rate-limit `catch` (bucket sama) + `failCooldownSec` pada
  slot + hold ProximityPrompt 0.6s. handlePackCatch & stepWander mengabaikan
  slot selama cooldown.
- **Rate config dimatikan** (`DemoConfig.catch.enabled=false`) → sukses selalu
  true (perilaku legacy 100%).
- **Rarity invalid** → `catchRateMultFor` fallback ×1.0 (netral, tak meledak).
- **DemoServer mati** (bridge absen) → BrainrotPack treat sebagai success
  (degenerate fallback, tanpa roll).
- **Monster mati di combat / respawn saat fail cooldown** → un-freeze hanya
  jika `slot.model` masih model yang sama (guard di task.delay).

---

## File yang tersentuh (implementasi 2026-06-08)

| File | Perubahan |
|---|---|
| `RarityConfig.luau` | + `catchRateMult` table + `catchRateMultFor()` (C2) |
| `DemoConfig.luau` | + blok `catch` (semua knob) + `catchCinematic.failBounceSec`/`failShakeSec` |
| `DemoServer.server.luau` | `PackCatchMint` bridge: roll rarity+rate+sukses, return `{outcome}`; `PlayerState.catchPity`; `catchRng` |
| `BrainrotPack.server.luau` | `handlePackCatch` cabang success/fail/rejected; `handlePackCatchFail` (freeze ringan + cooldown); `Slot.cooldownUntil`; gate `stepWander` |
| `CatchCinematic.client.luau` | `playCinematic(.., success)`; varian fail (net mantul + Highlight flash + shake, tanpa shrink); `netBounceBack` |
| `DemoRemotes.luau` | doc `CatchCinematic` + field `success` |
