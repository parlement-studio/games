# World Universe Architecture GDD (System #27 · GH #23)

**Version**: 1.1
**Last Updated**: 2026-06-09
**Author**: Owner + Claude (assistant)
**Status**: Draft (arsitektur + island-tier + traversal dikunci owner 2026-06-09; angka tunable TBD via playtest)

> **Parent**: `design/gdd/systems-index.md` — System **#27** (FOUNDATION, P0). Tracking **GH #23**.
> **Anchor**: `design/decisions/2026-05-29-vision-pivot.md` Decision 1/5/6/7
> — **DIREVISI** oleh GDD ini (lihat kotak di bawah).
> **Dependencies**: #1 Persistence (cross-place handoff — butuh ekstensi §11).
> **Depended On By**: #26 Kandang, #4/#5 Capture (Areas), #6/#24 Boss System,
> #29/#26 Party, #30/#27 Trade — **semua butuh batas place dari GDD ini**.

> ⚠️ **REVISI Vision Pivot Decision 1 (2026-06-09).** Decision 1 lama = "per-area =
> place TERPISAH (Lobby + sub-place per Area)". Owner memilih **single Overworld
> seamless** (laut + 4-5 pulau dalam SATU place ber-StreamingEnabled, no loading
> antar pulau). Yang TETAP terpisah: Raid, Super Boss zone, Kandang (privat/
> instanced). Lobby/Hunter Camp **dilebur** jadi pulau-port di Overworld. Lihat
> revision note di vision-pivot doc.

---

## 1. Overview & Purpose

Sistem ini mendefinisikan **kerangka dunia Roblox**: ada berapa *place*, masing-
masing untuk apa, model multiplayer-nya (shared / party-instanced / privat), dan
**protokol pindah antar-place** (`TeleportService` + `TeleportData` +
`MemoryStoreService`). Ini **fondasi P0** — setiap sistem lain (Kandang, Capture,
Boss, Party, Trade) butuh tahu batas place sebelum bisa didesain detail.

**Mental model utama** (analogi "channel"): satu *place* dijalankan Roblox dalam
**banyak salinan server paralel**. `MaxPlayers` = kapasitas **per salinan**, BUKAN
batas total pemain game. Pemain main bareng dengan **sengaja** masuk salinan yang
sama (Join Friend / Party), bukan dari matchmaking acak.

Tujuan:
1. Kunci daftar place + peran + model multiplayer tiap ruang.
2. Definisikan teleport flow + `TeleportData` schema (server-authoritative,
   client tak dipercaya).
3. Tetapkan aturan StreamingEnabled, traversal antar pulau, dan scaling spawn.
4. Sediakan titik integrasi (entry Kandang/Raid, party grouping) untuk GDD lain.

---

## 2. Core Mechanics

### 2.1 Peta universe (daftar place)

| Place (logical) | Peran | Model server | MaxPlayers (default, TBD) | Streaming |
|---|---|---|---|---|
| **Overworld** | Laut + **4–5 pulau berburu** + **Hunter Camp** (pulau-port: shop, trade, party-forming, leaderboard) + **Colony Boss (Tier 1)** per pulau | **Shared publik** (matchmaking) | **26** | **ON (wajib)** |
| **Super Boss Zone** (Tier 2) | 1 Super Boss, eksklusif, no regulars | **Party-instanced** (reserved server) | 6 | ON opsional |
| **Raid Map A / B** (Tier 3) | Raid Dungeon, **token-gated** | **Party-instanced** (reserved server) | 6 | ON opsional |
| **Kandang** | Basis privat: idle production, deploy monster, upgrade | **Privat per-owner** (reserved, key = UserId) | 8 (owner + visitor) | OFF (kecil) |

> "2 map raid"-mu = Raid A + Raid B (Tier 3). Tier-2 Super Boss = 1 place
> party-instanced terpisah. Semua Tier-2/3 + Kandang **bukan** di Overworld karena
> Overworld shared (privasi & eksklusivitas mustahil di map bersama).

**Island TIER (LOCKED 2026-06-09):** tiap pulau berburu punya **Tier berbeda** —
progression difficulty/rarity naik per Tier (Tier 1 starter → Tier 2 → … → Tier
N). Tier menentukan: rarity wild yang muncul, kekuatan Colony Boss, dan tier
Capture Item yang dibutuhkan (sinkron dgn rarity-by-source + area-tier items
capture-v2). **Gating**: pulau Tier lebih tinggi di-unlock by progression (level /
kill boss tier sebelumnya — angka final di capture-v2 + boss-system). Pulau Tier-1
= sekitar **Hunter Camp port** (pulau pertama `land 1`); Tier lebih tinggi makin
jauh berlayar.

**Hunter Camp = pulau-port (LOCKED).** Hunter Camp BUKAN place terpisah — dia
**satu pulau khusus di Overworld** yang jadi titik mulai + hub: shop (Merchant),
trade, party-forming, leaderboard, dermaga perahu, dan entry dock ke Kandang/Raid.

### 2.2 Model multiplayer per-ruang (LOCKED)

- **Shared publik** — Overworld. ~26 pemain se-salinan saling lihat & berburu;
  **tangkapan personal** (monster spawn untuk semua, tapi catch milik masing-masing
  — server-authoritative). Vibe Adopt Me / Pokémon GO.
- **Party-instanced** — Super Boss + Raid. Party dapat **server privat** via
  `TeleportService:ReserveServer` → `TeleportToPrivateServer` (atau
  `TeleportPartyAsync`). Tak ada orang asing; reward 100% milik party.
- **Privat per-owner** — Kandang. Reserved server di-key ke UserId pemilik
  (mapping via MemoryStore) supaya revisit + visitor mendarat di instance yang sama.

### 2.3 Traversal (gerak dalam dunia) — LOCKED 2026-06-09

- **Antar pulau di Overworld = GERAK BIASA, BUKAN teleport** (semuanya satu place,
  StreamingEnabled). Pemain berlayar; pulau di-stream sesuai posisi.
- **PERAHU dulu (eksplor) → fast-travel menyusul (unlock per pulau).**
  - **Discovery via perahu**: pulau yang **BELUM pernah dikunjungi** hanya bisa
    dicapai dengan **berlayar** dari Hunter Camp port. Berlayar = inti eksplorasi
    open-map (rasa archipelago) + gate penemuan pulau Tier lebih tinggi.
  - **Fast-travel unlock**: begitu sebuah pulau **pertama kali dikunjungi**
    (mendarat di dermaganya), pulau itu **ter-unlock** untuk **dock fast-travel** —
    kunjungan berikutnya bisa loncat instan dari dermaga mana pun (fade →
    `Character:PivotTo(targetDock)`, reposisi DALAM place, no loading). Status
    unlock **dipersist** (#1: `discoveredIslands` set per pemain).
  - Konsekuensi: **perahu (vehicle) masuk scope sejak awal**. Networking vehicle
    lebih kompleks — rekomendasi: **server-owned boat** (`SetNetworkOwner(nil)`)
    atau owner-driven dgn validasi posisi anti-teleport-hack. Perahu spawn di
    dermaga port; satu per pemain (atau shared per party). Detail mekanik perahu →
    sub-spec terpisah saat implementasi.
- **Antar PLACE = TeleportService** (Overworld ↔ Raid/Super Boss/Kandang) — pakai
  loading screen + `TeleportData`. BEDA dari fast-travel intra-Overworld (yang cuma
  reposisi dalam place, tanpa TeleportService).

### 2.4 Player grouping ("cara ketemu & main bareng")

1. **Join Friend** — fitur Roblox bawaan; masuk salinan persis teman (kalau ada slot).
2. **Party (#29)** — bentuk party di Hunter Camp → `TeleportPartyAsync` ke Overworld
   ATAU ke reserved server Raid. **Jalur utama** co-op terjamin se-channel.
3. **Reserved server** — Raid/Super Boss/Kandang pakai server privat (`ReserveServer`).

> Detail mekanik party (formation UI, invite, finder) **didelegasikan ke
> `party-matchmaking-gdd.md` (#29)**. GDD ini cuma tetapkan TITIK integrasinya
> (party-forming di Hunter Camp + dispatch teleport).

### 2.5 Spawn density scaling (anti sepi/rebutan)

Jumlah wild monster yang hidup di sebuah region pulau **skala dengan jumlah pemain**
di region itu:
```
spawnTarget(region) = clamp(baseSpawn + perPlayer * playersInRegion, minSpawn, maxSpawn)

Where:
  playersInRegion : pemain dalam radius region pulau (server hitung)
  baseSpawn       : minimal saat 0-1 pemain (pulau tak pernah kosong)
  perPlayer       : tambahan slot monster per pemain
  min/maxSpawn    : pagar bawah/atas (perf mobile)
```
Semua angka di `WorldConfig` (§8). Director server-authoritative (mirip
`BrainrotPack` sekarang, tapi per-region).

---

## 3. Data Schema

### 3.1 Place registry (config, ReplicatedStorage — bukan rahasia)

```lua
-- ReplicatedStorage/Shared/Config/WorldConfig.luau (designer + publish-time)
type PlaceKind = "overworld" | "super_boss" | "raid" | "kandang"
return {
    version = 1,
    universeId = 0,                 -- diisi saat publish
    places = {
        overworld  = { placeId = 0, kind = "overworld", maxPlayers = 26 },
        super_boss = { placeId = 0, kind = "super_boss", maxPlayers = 6 },
        raid_a     = { placeId = 0, kind = "raid",       maxPlayers = 6 },
        raid_b     = { placeId = 0, kind = "raid",       maxPlayers = 6 },
        kandang    = { placeId = 0, kind = "kandang",    maxPlayers = 8 },
    },
    -- StreamingEnabled (overworld)
    streaming = { targetRadius = 1024, minRadius = 256, pauseMode = "Default" },
    -- spawn scaling (§2.5)
    spawn = { baseSpawn = 6, perPlayer = 2, minSpawn = 4, maxSpawn = 40 },
}
```
> `placeId` diisi NOL sampai tiap place dipublish (Open Cloud / Studio). Sampai
> itu, teleport ke place tsb di-skip + warning. (Release-manager mengisinya.)

### 3.2 TeleportData (state yang ikut pindah place)

```lua
type TeleportData = {
    schemaVersion: number,
    fromPlace: string,            -- "overworld" | "kandang" | ...
    intent: string,              -- "enter_kandang" | "visit_kandang" | "start_raid"
                                  -- | "start_super_boss" | "return_overworld"
    targetOwnerUserId: number?,   -- visit_kandang: pemilik kandang yg dikunjungi
    partyUserIds: { number }?,    -- party teleport (semua anggota)
    returnSpawn: string?,         -- nama dock/spawn saat balik ke Overworld
}
```
> 🔒 **TeleportData CLIENT-VISIBLE & bisa dipalsukan** (lewat batas client). Server
> tujuan **WAJIB re-validasi** semua klaim: token raid benar-benar dikonsumsi,
> kepemilikan/izin visit, party valid (lihat §7). JANGAN otorisasi dari TeleportData.

### 3.3 MemoryStore (koordinasi lintas-server)

```lua
-- MemoryStoreService — TTL pendek, lintas semua server salinan.
KANDANG_INSTANCES : SortedMap  key=tostring(ownerUserId) -> accessCode  (TTL ~ sesi)
PARTY_RESERVATIONS: SortedMap  key=partyId               -> accessCode  (TTL ~ 5 mnt)
```
- Kandang revisit/visit: cek MemoryStore → kalau ada accessCode aktif, masuk
  instance yg sama; kalau tidak, `ReserveServer` baru lalu simpan.
- Wajib `pcall` (MemoryStore bisa gagal) — fallback: reserve server baru.

### 3.4 Persistence cross-place handoff (#1 ekstensi — wajib)

- **Save-before-teleport**: server **flush profil** (DataStore) SEBELUM
  `TeleportService:Teleport...`. Place tujuan load profil fresh dari UserId key.
- **Session lock** harus toleran teleport (pemain "berpindah", bukan keluar):
  rilis lock saat `PlayerRemoving` karena teleport, place tujuan ambil lock saat join.
  Gunakan `BindToClose` + retry. (Detail di persistence-gdd §11 — GDD ini memicu
  kebutuhannya.)
- **Idle Kandang** dihitung dari `state + timestamp` (offline earnings) — TIDAK
  butuh server Kandang menyala (lihat §2.1 & kandang-gdd #26).
- **`discoveredIslands`** (set per pemain) — pulau yang sudah pernah dikunjungi
  (mendarat via perahu). Dipersist; gate fast-travel (§2.3): hanya pulau di set ini
  yang bisa fast-travel, sisanya wajib berlayar. Backfill: kosong = belum ada yang
  ke-unlock (Tier-1/port selalu dianggap discovered).

---

## 4. Client-Server Split

| Concern | Client | Server (authoritative) |
|---|---|---|
| Pilih tujuan (dock/portal) | Tampilkan prompt + UI; kirim intent via Remote | Validasi (jarak, izin, token), panggil TeleportService |
| TeleportData | TIDAK pernah dipercaya untuk otorisasi | Re-validasi semua klaim di place tujuan |
| Reserved server (raid/kandang) | — | `ReserveServer` + simpan accessCode di MemoryStore |
| Token raid | Tampilkan jumlah (read-only) | **Konsumsi + validasi** sebelum dispatch (atomic) |
| Spawn monster/Colony Boss | Render dari replikasi | Spawn director (per-region scaling), authoritative catch |
| Streaming | Engine stream parts; jangan asumsikan part ada | Logika spawn/world server-side, stream-independent |
| Posisi antar pulau (fast-travel) | Minta fast-travel | Validasi + `PivotTo` (reposisi dalam place) |

---

## 5. RemoteEvents / Functions & TeleportService

Per `remotes.md`: **tanpa C→S RemoteFunction**; semua C→S = RemoteEvent ber-validasi
+ rate limit. Teleport selalu **server** yang panggil (client cuma minta intent).

| Name | Type | Dir | Args | Validasi | Rate |
|---|---|---|---|---|---|
| `RequestTeleport` | RemoteEvent | C→S | `(intent: string, targetUserId: number?)` | intent ∈ whitelist; in-range dock; izin/token; not already teleporting | 2/sec |
| `TeleportStatus` | RemoteEvent | S→C | `(state, reason?)` | server-authored (mis. "full","no_token","reserving","ok") | n/a |

**TeleportService surface (server-side):**
- `TeleportService:ReserveServer(placeId)` → `(accessCode, privateServerId)` untuk
  raid/super-boss/kandang.
- `TeleportService:TeleportToPrivateServer(placeId, accessCode, players, _, teleportData)`.
- `TeleportService:TeleportPartyAsync(placeId, players, teleportData)` untuk party
  ke Overworld/raid.
- `TeleportService:Teleport(placeId, player, teleportData, gui)` untuk solo
  (Kandang sendiri / return overworld).
- Semua **dibungkus pcall** + retry (TeleportService bisa throw). Gagal → kembalikan
  `TeleportStatus{state="error"}`, pemain tetap di tempat (tidak hilang).

---

## 6. Player-Facing UI

1. **Dock / portal di Overworld** (Hunter Camp port): prompt besar mobile-friendly —
   `🏠 Kandang-ku`, `⚔ Mulai Raid` (kalau punya token + party), `🌋 Super Boss`.
   Antar pulau: dermaga `⛵ Berlayar ke <Pulau>` (fast-travel).
2. **Teleport feedback** — layar loading singkat + status ("Menyiapkan server…",
   "Server penuh, coba lagi", "Butuh Token"). Reuse framework UI (#13/#6).
3. **Map / minimap** (opsional MVP) — tunjuk posisi pemain + pulau + dermaga.
4. **Party panel** — di Hunter Camp (detail di #29). GDD ini cuma sediakan entry +
   tombol "Masuk Dunia bareng Party".
5. **Visit Kandang** — dari sosial/leaderboard: tombol "Kunjungi Kandang" (read-only).

---

## 7. Edge Cases & Error States

1. **Teleport gagal / TeleportService throw** → pcall + retry sekali; tetap gagal →
   `TeleportStatus{error}`, pemain **tetap di place asal** (tidak ter-stuck/hilang).
2. **Server tujuan PENUH** (shared overworld / join friend) → Roblox tolak; tampilkan
   "Server penuh — coba lagi / pakai Party". Party teleport meminta kapasitas
   bareng sehingga lebih jarang gagal.
3. **TeleportData dipalsukan** (intent/token/ownership) → place tujuan **re-validasi
   server-side**; klaim tak sah → tendang balik ke Overworld + log. JANGAN beri
   reward/akses dari TeleportData.
4. **Token raid**: konsumsi **sebelum** dispatch, atomik. Kalau dispatch gagal →
   **refund token** (atau jangan konsumsi sampai server raid konfirmasi join).
   (Aturan consume-on-fail final → boss-system-gdd / Decision 7.)
5. **Profil belum ter-save sebelum teleport** → save-before-teleport di-`pcall`;
   gagal → batalkan teleport (jangan pindah dgn state belum aman), tampilkan
   "Hiccup — coba lagi". Cegah kehilangan/duplikasi state.
6. **Reserved server kadaluarsa / accessCode mati** (MemoryStore TTL habis) →
   reserve baru + update MemoryStore; visitor lama yg minta join kandang yg sudah
   tutup → reserve instance baru (owner tak online → mode read-only snapshot, lihat
   kandang-gdd).
7. **Visit Kandang pemilik OFFLINE** → tetap bisa (read-only) dari **data tersimpan**
   (snapshot deploy), bukan server live. Tak ada mutasi.
8. **StreamingEnabled pop-in** — client belum stream-in pulau → tak render/prompt;
   range check server tetap authoritative (catch/boss butuh pemain benar-benar dekat).
9. **Anggota party offline/leave saat dispatch** → filter daftar; party kosong →
   batal + pesan. Leader leave → re-assign atau bubarkan (detail #29).
10. **Place belum dipublish** (`placeId == 0`) → skip teleport + warning developer
    (mencegah crash saat build belum lengkap).

---

## 8. Balancing Parameters

Semua di `WorldConfig` (§3.1). Bukan balance gameplay — knob infra/perf.

```
overworldMaxPlayers = 26     -- per salinan; Range 10-40; TBD via playtest+FPS profiling
raidMaxPlayers      = 6      -- party cap (sejalan ukuran party #29)
kandangMaxPlayers   = 8      -- owner + visitor
streaming.targetRadius = 1024 studs   -- jangkauan stream penuh (Range 512-2048)
streaming.minRadius    = 256 studs    -- jangkauan minimum dijamin ada
spawn.baseSpawn = 6   perPlayer = 2   minSpawn = 4   maxSpawn = 40   (§2.5 formula)
teleport.retry = 1    teleport.timeoutSec = 10
memoryStore.kandangTTLsec = 1800   partyReservationTTLsec = 300
boat.speed = 48 studs/s (TBD)   boat.spawnAtPort = true   boat.perParty = false
fastTravel.requiresDiscovered = true   fastTravel.fadeSec = 0.4
```

**Formula spawn density** (diulang dari §2.5):
```
spawnTarget = clamp(baseSpawn + perPlayer * playersInRegion, minSpawn, maxSpawn)
```

> Penjelasan kapasitas: `overworldMaxPlayers` = jumlah pemain **per salinan dunia**,
> bukan batas total. Roblox menjalankan banyak salinan paralel (lihat §1). Angka
> dipilih demi FPS mobile; difinalkan setelah playtest + MicroProfiler
> (performance-analyst).

---

## 9. Integration Points

| System | Arah | Interaksi |
|---|---|---|
| **#1 Persistence** | World → it | Save-before-teleport, session-lock toleran teleport, profil per-UserId di tiap place. **Butuh ekstensi §11** (cross-place TeleportData). |
| **#26 Kandang** | World → it | Entry dock di port + teleport ke place Kandang privat; idle dari state tersimpan. |
| **#4/#5 Capture (Areas)** | World → it | 4-5 pulau = Areas; spawn director + area-tier item per pulau; catch authoritative di shared server. |
| **#6/#24 Boss System** | World → it | Colony (Tier1) di Overworld; Super Boss (Tier2) + Raid (Tier3) = place party-instanced; token gate. |
| **#29 Party + Matchmaking** | World ↔ it | Party-forming di Hunter Camp; `TeleportPartyAsync`/reserved server; GDD ini sediakan entry, #29 sediakan mekanik. |
| **#30/#27 Trade** | World → it | Trade di Hunter Camp (shared overworld port). |
| **#13/#6 UI/HUD** | World ↔ it | Dock prompts, teleport loading, minimap, visit buttons. |
| Remotes (Shared) | World → it | `RequestTeleport`, `TeleportStatus`; didokumentasikan di `remotes-manifest.md`. |

**Events:** `GameEvents.PlayerTeleporting:Fire({player, intent, toPlace})` agar
Analytics/Persistence bisa react (flush, funnel) tanpa coupling.

---

## 10. Open Decisions & Build Order

**Resolved (owner 2026-06-09):**
- ✅ **Island Tier** — tiap pulau Tier berbeda; progression difficulty/rarity naik
  per Tier; Tier-1 dekat port, makin tinggi makin jauh berlayar (§2.1).
- ✅ **Traversal** — perahu dulu (eksplor/discovery) → fast-travel unlock per pulau
  setelah dikunjungi (§2.3).
- ✅ **Hunter Camp** — satu pulau-port di Overworld, bukan place terpisah (§2.1).

**Masih open:**
- Angka tema/tier final 4-5 pulau (rarity per Tier, syarat unlock level/kill) →
  finalize bareng capture-v2 + boss-system.
- Tier-2 Super Boss: place sendiri (default) vs lebur ke salah satu raid map.
- `overworldMaxPlayers` final (playtest + FPS profiling).
- Mekanik perahu detail (kecepatan, server-owned vs owner-driven, shared per party).
- Token consume-on-fail untuk raid entry (lintas dengan Decision 7 / boss-system).

**Build order (bertahap):**
1. **`WorldConfig` + place registry** + stub teleport service (server) — fondasi.
2. **Overworld place**: StreamingEnabled, pulau pertama (sudah ada `land 1`) +
   Hunter Camp port + spawn director per-region.
3. **Kandang place** + entry dock + reserve-by-UserId + MemoryStore mapping.
4. **Persistence §11**: save-before-teleport + session-lock teleport-aware.
5. **Raid/Super Boss places** + party dispatch (butuh #29 party).
6. **Fast-travel dock** antar pulau + teleport UI/feedback.

> Catatan implementasi: pulau `land 1` (collision sudah diperbaiki ke
> PreciseConvexDecomposition + spawn di pulau, 2026-06-09) = pulau pertama Overworld.
> Ukuran ~611×618 studs OK untuk 1 pulau dari 4-5.
