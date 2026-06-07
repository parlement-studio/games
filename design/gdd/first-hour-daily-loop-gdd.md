# First Hour + Daily Loop GDD (Retention Pacing — Fase 0 Demo)

**Version**: 1.0
**Last Updated**: 2026-06-07
**Author**: game-designer + Owner
**Status**: Approved (arah disetujui owner 2026-06-07; implementasi Fase 0 demo)

> **Scope**: versi MINI untuk demo Fase 0 — mendesain kurva sesi pertama (~1 jam)
> dan ritme harian (~1 jam/hari) di atas sistem demo yang SUDAH hidup (pack
> catch berbayar, kandang + upgrade, boss 5 elemen, element counter-play).
> Versi penuh digantikan nanti oleh **#14 Onboarding/FTUE** + **#17 Daily
> Quests** (systems-index v3.2) — semua mekanik di sini didesain agar datanya
> dan vibe-nya **carry forward** ke sistem produksi tersebut.
>
> Cross-ref: `design/decisions/2026-05-29-vision-pivot.md` (Decision 7: daily
> free token), `design/decisions/2026-06-07-element-system.md` (counter-play),
> `design/gdd/economy-gdd.md` v1.3 (faucet/sink, kurva upgrade LOCKED).

---

## 1. Overview & Purpose

Dua tujuan retensi:

1. **First Hour**: player baru bermain ±60 menit di sesi pertama TANPA merasa
   diarahkan paksa — dicapai lewat tangga tujuan yang selalu terlihat,
   berjarak 3–10 menit, dengan klimaks di menit ~35 dan cliffhanger di menit 60.
2. **Daily Loop**: ±1 jam/hari terasa "tuntas" (bukan grind tanpa ujung —
   kid-friendly): login reward → 3 daily quest (~40 menit aktif) → first-kill
   bonus boss → logout dengan alasan kembali besok.

Prinsip psikologis: dopamin pertama < 60 detik; kekalahan yang MENGAJAR
(boss pertama kalah by design → "aku butuh elemen counter"); akhir sesi selalu
menanam tujuan sesi berikutnya.

## 2. Core Mechanics

### 2.1 Kurva Jam Pertama (menit demi menit)

| Menit | Beat | Economy |
|---|---|---|
| 0–3 | Tangkap 3 GRATIS (onboarding, `freeCapturesRemaining`) | 0 koin; slot-machine element+personality |
| 3–6 | Buka Kandang (F) → taruh 3 monster → koin mengalir | ~6/s; hook idle "angka naik sendiri" |
| 6–10 | Upgrade Kandang Lv1 (200) | Pelajaran: koin → investasi |
| 10–15 | Catch berbayar (25) → isi 6 slot + cadangan tas | Rate ~12/s; sink catch aktif |
| 15–18 | Summon pertama vs minion → menang (+25, +XP, level-up #1) | Combat = faucet aktif |
| 18–25 | **Boss pertama → KALAH (by design)**; boss menampilkan elemennya 👑 | Pelajaran kunci: counter + level |
| 25–35 | Berburu elemen counter + level-up + upgrade Lv3–5 | Loop inti penuh |
| ~35 | **BOSS KILL PERTAMA** (+250, +200 XP ≈ 2 level) — klimaks | Reward terbesar sesi |
| 35–50 | 5 boss = 5 puzzle elemen; upgrade Lv6–8 | Variasi per pack |
| 50–60 | Tujuan panjang terlihat (Lv10 = 4.0K); **cliffhanger kandang penuh** | Alasan kembali tertanam |

**Validasi pacing terhadap kurva LOCKED** (`EconomyConfig.upgrades.factory`,
`cost(n) = 200 × 1.35^n`):

```
income(t) ≈ Σ_slot baseRatePerSlot × prodMult × (1 + 0.15 × lvl)
Lv1–10  : Σcost ≈ 10.9K  → tercapai ±menit 40 (sambil combat)
Lv11–15 : Σcost ≈ 40K    → tujuan sesi ke-2  ✓
Lv30    : Σcost ≈ 4.6M   → sink endgame      ✓
```

### 2.2 Daily Loop (±1 jam)

```
LOGIN  (0–5')    💰 klaim offline (CAPPED) + 🎁 daily login reward kecil
HARIAN (5–40')   📜 3 Daily Quest (reset server-clock 00:00 UTC):
                   Q1 "Tangkap N monster [elemen acak]"   (~10')
                   Q2 "Kalahkan N Colony Boss"            (~10')
                   Q3 "Kumpulkan N koin dari kandang"     (pasif)
KLIMAKS (40–60') 👑 First-kill-of-the-day bonus per tipe boss (5 tipe × 2x reward)
                 🎟️ [pasca-#31] 1 Raid Token gratis/hari
LOGOUT           kandang menabung (cap) + quest besok terlihat
```

**3 tuas retensi**: (a) offline/pending cap = dorongan login tanpa hukuman;
(b) daily quest + first-kill = ±40 menit aktif lalu "tuntas"; (c) daily free
token menjatah konten terbaik ke ritme harian (Vision Pivot Decision 7).

### 2.3 Anti-farm boss (KEPUTUSAN BALANCE)

Boss respawn 30 detik + reward flat 250 = farm tanpa batas → merusak ritme.
**Lock**: reward boss menurun setelah kill pertama per hari per tipe:

```
bossReward(type, hari_ini) = firstKill ? winCoins×10 (250) : winCoins×3 (75)
xpReward(type, hari_ini)   = firstKill ? xpPerWin×4 (200)  : xpPerWin×2 (100)
```

First-kill reset bersama daily reset. Farming tetap boleh (75 > minion 25)
tapi tidak lagi mendominasi faucet.

## 3. Data Schema (persisted, ekstensi `PlayerData`)

```lua
daily: {
    lastResetAt: number,        -- os.time() reset terakhir yang DITERAPKAN
    loginClaimed: boolean,      -- daily login reward hari ini
    quests: {                   -- tepat 3, di-roll saat reset
        { id: string, kind: "catch_element"|"boss_kills"|"earn_coins",
          param: string?,       -- mis. elemen target Q1
          target: number, progress: number, claimed: boolean },
    },
    bossFirstKill: { [string]: boolean }, -- personality -> sudah first-kill hari ini
}
```

Backfill via `Migrations` (defensive, pola `base`): record lama → `daily` baru
dengan `lastResetAt = 0` (memicu reset pertama saat load). Field baru murni
aditif — tidak ada migrasi destruktif.

## 4. Client-Server Split

- **Server**: pemilik penuh — jadwal reset (cek saat load + timer per menit),
  roll quest, progress tracking (hook ke catch/boss-kill/coin-flush yang sudah
  ada), klaim reward, first-kill map. Client TIDAK pernah mengirim progress.
- **Client**: render checklist tujuan (first hour) + panel daily quest +
  banner reset/claim. Murni presentasi dari payload server.

## 5. RemoteEvents/Functions

| Remote | Arah | Payload |
|---|---|---|
| `DailyUpdate` | S→C | `{ quests, loginClaimed, bossFirstKill, resetInSec }` — saat load, reset, tiap progress berubah |
| `ClaimDailyQuest` | C→S | `(questId)` — validasi progress ≥ target, idempotent |
| `GoalUpdate` (first-hour) | S→C | `{ goalIndex, done }` — checklist FTUE-lite |

Validasi standar: type-check semua arg, rate-limit bucket existing, klaim
idempotent (claimed flag persisted).

## 6. Player-Facing UI

1. **Goal checklist (FTUE-lite)**: panel kecil pojok kiri, 6 tujuan berurutan
   (Tangkap 3 → Taruh di kandang → Upgrade Lv1 → Menangkan duel → Kalahkan 1
   boss → Capai kandang Lv5). Selesai semua → panel berganti ke Daily Quest.
2. **Daily Quest panel**: 3 baris quest + progress bar + tombol CLAIM (pola
   visual = menu Kandang: badge hijau claim-able, redup belum).
3. **Banner** (`Moment`, sudah ada): reset harian, quest selesai, first-kill
   bonus, kandang penuh.

## 7. Edge Cases & Error States

1. **Relog melewati tengah malam** → reset diterapkan saat load (`lastResetAt`
   < batas hari UTC berjalan), BUKAN dobel saat timer juga menembak.
2. **Server hidup melewati tengah malam** → timer per menit menerapkan reset
   untuk semua player online; progress quest lama hangus (by design).
3. **Clock skew antar server** → semua perbandingan pakai `os.time()` UTC
   server; `lastResetAt` disimpan absolut, bukan offset.
4. **Klaim ganda / spam klaim** → `claimed` flag persisted + rate limit;
   klaim kedua no-op.
5. **Quest "catch_element" elemen X tapi player miskin** → 3 free onboarding
   hanya sesi pertama; quest reward harus > biaya catch yang dibutuhkan
   (lihat §8 — reward Q1 ≥ 3 × 25 × buffer 4).
6. **First-kill map menggelembung** → key terbatas 5 personality; bersih total
   saat reset.
7. **Offline melewati ≥1 reset** → terapkan SEKALI (quest kemarin hangus,
   roll hari ini); tidak ada "rapel" reward login.
8. **DataStore gagal saat klaim** → klaim lewat `update()` atomik existing;
   gagal = tidak ada reward & tidak ada flag (retry aman).

## 8. Balancing Parameters (config-driven, BUKAN hardcode)

```lua
DemoConfig.daily = {
    resetHourUTC = 0,            -- jam reset (0 = 00:00 UTC). Range: 0-23
    loginRewardCoins = 100,      -- kecil; ritual, bukan faucet. Range: 0-10000
    quests = {
        catchElement = { target = 3,  rewardCoins = 300 },  -- ≥ 3×25×4 buffer
        bossKills    = { target = 3,  rewardCoins = 400 },
        earnCoins    = { target = 2000, rewardCoins = 500 },
    },
    bossRepeatCoinsMult = 3,     -- kill ke-2+ per tipe/hari (×winCoins). First-kill tetap 10.
    bossRepeatXpMult = 2,        -- idem untuk XP (first-kill tetap 4)
}
```

Total faucet harian quest+login ≈ 1.3K — kecil vs idle (≈29K/jam @8/s) →
quest adalah PENGARAH AKTIVITAS, bukan sumber kekayaan. Sink harian organik
(catch + upgrade) tetap dominan.

## 9. Integration Points

| Sistem | Hubungan |
|---|---|
| Persistence #1 | Field `daily` baru (aditif) + backfill migrasi |
| Economy #3 | Faucet `quest_daily` + `reward_generic` (SUDAH di whitelist) — dipakai pertama kali |
| Element System | Q1 menarget elemen → mendorong eksplorasi counter |
| Pet AI / Boss demo | Hook boss-kill → progress Q2 + first-kill map |
| Kandang demo | Hook coin-flush → progress Q3; cliffhanger pending-cap |
| **#14 Onboarding (penerus)** | Goal checklist = prototipe FTUE; step config-driven carry forward |
| **#17 Daily Quests (penerus)** | Schema `daily.quests` didesain kompatibel (id/kind/param/target/progress/claimed) |
| **#31 Items+Token (nanti)** | Slot reward token di quest sudah dicadangkan (Decision 7 sumber b) |

## 10. Build Order (Fase 0 — tracking di GitHub issue)

1. **Goal checklist UI** (FTUE-lite 6 langkah) — penentu terbesar sesi 1 jam
2. **Daily reset infra** (schema `daily` + reset saat load + timer + migrasi)
3. **3 Daily Quest** + panel UI + klaim
4. **First-kill-of-the-day bonus boss** (+ reward berulang menurun — §2.3)
5. **Offline/pending cap di demo** + banner "kandang penuh"

---

**Changelog**
- **1.0 (2026-06-07)** — draft pertama; arah first-hour + daily-loop disetujui
  owner; kurva divalidasi terhadap angka sink demo yang baru hidup (commit
  `1fbc71a`).
