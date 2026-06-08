# Localization / Language System GDD (System #32)

**Version**: 1.1
**Last Updated**: 2026-06-08
**Author**: game-designer
**Status**: Draft (approach **B**; **English-first** sequencing — owner 2026-06-08)

> **Parent**: `design/gdd/systems-index.md` — System #32 (support/infra, P2).
> **Tracking**: GitHub issue **#30**.
> **Approach decision (2026-06-08)**: owner memilih **B — custom string table**
> (kontrol penuh, terjemahan ditulis tangan) di atas A (Roblox native cloud
> LocalizationTable). Alasan: owner ingin pilihan bahasa **eksplisit di dalam
> game**, kualitas terjamin tanpa mesin-translate. Door tetap terbuka ke A nanti
> karena langkah pertama (sentralisasi string) sama untuk keduanya.
>
> **SEQUENCING UPDATE (2026-06-08)**: owner menetapkan **English sebagai bahasa
> resmi/sumber game**, terjemahan (Indonesia dll.) **belakangan**. Konsekuensi:
> - **Precursor SELESAI** — semua teks pemain yang tadinya campur ID/EN sudah
>   dinormalisasi ke **English in-place** (bukan via modul `Strings`). Lihat
>   §10 langkah 0. Game sekarang satu-bahasa: **English**.
> - **Default/source language = `en`** (bukan `id`). Indonesia menjadi **kolom
>   terjemahan yang ditambahkan nanti**, bukan default.
> - Sistem toggle + sentralisasi `Strings` (langkah 1-6) **ditunda** sampai owner
>   minta translate — saat itu nilai English tinggal diekstrak ke key.
> **Dependencies**: #1 Persistence (simpan setting bahasa), #13 UI/HUD (semua teks),
> #12 Moment (toast). **Depended On By**: setiap sistem yang menampilkan teks.

---

## 1. Overview & Purpose

Dulu teks game **campur Bahasa Indonesia + Inggris** dan ditulis langsung
(hardcoded). **Per 2026-06-08 sudah dinormalisasi ke English in-place** (precursor
SELESAI — §10 langkah 0), jadi game sekarang **satu bahasa resmi: English**.

Sistem ini (fase berikutnya, ditunda sampai owner minta translate) menyediakan
**satu sumber teks terpusat** dengan **pilihan bahasa yang dipilih pemain di
dalam game**, tersimpan permanen. Tujuan:
1. Sumber = **English**; bahasa lain (Indonesia, dst.) = kolom terjemahan tambahan.
2. Pemain memilih bahasa sendiri (toggle), pilihan dipersist.
3. Semua teks pemain (UI, toast, prompt) lewat satu fungsi `t(key)` — tidak ada
   lagi literal tersebar.

**Bukan** memakai cloud LocalizationTable / auto-translate Roblox (Approach A).
Murni tabel string custom yang kita kelola sendiri (Approach B).

---

## 2. Core Mechanics

### 2.1 Tabel string terpusat
Satu modul `Strings` (ReplicatedStorage, shared — TIDAK ada rahasia) memetakan
**key → { per-locale string }**:

```lua
Strings["catch.fail"]      = { id = "💨 Lolos! Monster kabur dari jaring.", en = "💨 It escaped the net!" }
Strings["menu.kandang.title"] = { id = "🏠 Kandang", en = "🏠 Pen" }
Strings["shop.net.buy_one"] = { id = "Beli 1 Jaring", en = "Buy 1 Net" }
```

- **Locale didukung**: `en` (English, **default/sumber**). `id` (Bahasa
  Indonesia) + bahasa lain = **ditambahkan nanti** sebagai kolom terjemahan.
- **Konvensi key**: `domain.subkey` titik-terpisah (mis. `menu.*`, `catch.*`,
  `shop.*`, `combat.*`, `prompt.*`). Stabil — key tidak diterjemahkan, hanya nilainya.

### 2.2 Fungsi terjemahan `t(key, args?)`
Controller client `Locale` menyimpan bahasa aktif + meng-ekspos:

```lua
Locale.t("catch.fail")                          -- -> string bahasa aktif
Locale.t("shop.net.owned", { n = 6 })           -- interpolasi placeholder bernama
```

- **Interpolasi**: template pakai placeholder bernama `{name}` (mis.
  `"Sisa {n} jaring"` / `"{n} nets left"`). Tidak ada perakitan kalimat via
  konkatenasi (urutan kata beda antar bahasa) — selalu satu template per kalimat.
- **Fallback berantai**: locale diminta → default `id` → string `key` mentah
  (kelihatan tapi tidak crash) + `warn` di Studio.

### 2.3 Pilihan bahasa pemain
- Disimpan di profil: `settings.language` (default `en`).
- **Deteksi pertama kali**: saat profil baru dibuat + sudah ada terjemahan, baca
  `Player.LocaleId` (mis. `"id-id"` → `id` bila tersedia, selain itu → `en`)
  sebagai default awal; setelah pemain memilih manual, **hormati pilihan
  tersimpan**. Selama hanya `en` yang ada, semua pemain dapat English.
- **Toggle in-game**: switch bahasa di panel Settings (mis. `EN | ID` saat ID
  sudah ada). Menekan → `SetLanguage` remote → server persist → client
  **re-render semua UI terbuka** seketika.

---

## 3. Data Schema

```lua
-- ReplicatedStorage/Shared/Localization/Strings.luau  (shared, no secrets)
export type LocaleId = "en" | "id"                     -- en = sumber; id ditambah nanti
export type Entry = { [LocaleId]: string }             -- minimal en; locale lain opsional
-- Strings: { [string]: Entry }

-- ReplicatedStorage/Shared/Localization/LocaleConfig.luau
return {
    version = 1,
    defaultLanguage = "en",                            -- LocaleId (sumber resmi)
    supported = { "en" },                              -- MVP English saja; "id" ditambah saat translate
    -- Map Player.LocaleId prefix -> LocaleId untuk deteksi join pertama (aktif
    -- hanya setelah locale target ada di `supported`).
    -- Range: prefix string | Default: "id-*" -> id (nanti), sisanya -> en
    autodetect = { ["id"] = "id" },
    autodetectFallback = "en",
}
```

**Field profil baru** (owned by Persistence #1):
```lua
settings = {                                           -- objek settings (baru jika belum ada)
    language = "en",                                   -- LocaleId; default "en"; migrasi: inject "en" bila absen
}
```
- **Migrasi**: profil lama tanpa `settings.language` → set `"en"` saat load
  (backfill, idempotent). Bump schema version bila perlu per persistence-gdd.

---

## 4. Client-Server Split

| Concern | Client | Server (authoritative) |
|---|---|---|
| Tabel `Strings` + `t()` | Render teks dari key untuk bahasa aktif | Tidak render; hanya kirim **key + args** |
| Bahasa aktif | Cache lokal, re-render saat berubah | Sumber kebenaran = `settings.language` tersimpan |
| Set bahasa | Kirim intent `SetLanguage` | Validasi enum, persist, ack |
| Toast / event server | Terima `{ key, args }`, localize via `t()` | Emit **key**, bukan literal (lihat §5) |

**Keputusan kunci**: teks server-side (Moment toast, banner) dikirim sebagai
**key + args**, di-render di client dengan bahasa pemain. Keuntungan: satu sumber
string (di client/shared), bandwidth kecil, tidak perlu server tahu nilai string.
Server cukup tahu **key**-nya. (Tabel `Strings` di ReplicatedStorage shared, jadi
key juga bisa divalidasi server bila mau.)

---

## 5. RemoteEvents / Functions

| Name | Type | Dir | Args | Validasi | Rate limit |
|---|---|---|---|---|---|
| `SetLanguage` | RemoteEvent | C→S | `(lang: string)` | `lang ∈ supported`; else abaikan | 2/sec |
| (existing) `Moment`/`CatchCinematic`/dll | S→C | S→C | payload `text` → **`key` + `args`** | server-authored | n/a |

- `SetLanguage`: server set `settings.language`, persist (pcall), lalu bahasa
  awal dikirim dalam sinkron profil saat join (tidak perlu remote balasan khusus).
- **Migrasi payload**: selama transisi, payload boleh dukung KEDUA `text` (lama,
  literal) dan `key` (baru). Begitu semua call dimigrasi ke `key`, `text` dibuang.

---

## 6. Player-Facing UI

1. **Toggle bahasa** — switch `🇮🇩 ID | 🇬🇧 EN` di panel Settings (atau pill kecil
   di menu). Menandai bahasa aktif; tap = ganti seketika + persist.
2. **Re-render langsung** — saat ganti, semua teks UI terbuka berganti tanpa
   perlu reload (pemain langsung lihat efeknya).
3. **Default mulus** — pemain ID dapat ID otomatis (deteksi LocaleId), tidak perlu
   set apa pun untuk pengalaman bahasa-asli.

Semua teks pemain (judul menu, tombol, toast, prompt `ActionText`/`ObjectText`,
banner combat, label cinematic) bersumber dari `t(key)`.

---

## 7. Edge Cases & Error States

1. **Key tidak ada** → tampilkan string `key` mentah + `warn` Studio (tidak crash).
2. **Locale value kosong** untuk key tertentu → fallback ke `id`, lalu ke key mentah.
3. **Pemain baru (deteksi)** → `LocaleId` "id-*" → `id`, selain itu → `en`; setelah
   set manual, deteksi tidak menimpa lagi.
4. **Ganti bahasa di tengah sesi** → client re-render UI terbuka; toast masa depan
   tetap benar karena server kirim key (bukan teks beku).
5. **Argumen `:format`/placeholder tidak cocok** (mis. `{n}` tak diberi) → guard;
   tampilkan template apa adanya, jangan error.
6. **Persistence tidak tersedia saat `SetLanguage`** → terapkan di sesi (client),
   set persist gagal di-pcall + retry; default `id` bila profil belum termuat.
7. **String dengan angka dinamis** (koin, jumlah) → wajib placeholder bernama,
   tidak boleh konkatenasi tengah-kalimat (urutan kata beda ID/EN).
8. **Spam `SetLanguage`** → rate-limit 2/sec; nilai sama = no-op.

---

## 8. Balancing Parameters

Bukan sistem balance — "tunable" = isi tabel string + default language.

```
defaultLanguage = "en"          -- bahasa resmi/sumber (sebelum deteksi/override)
supported       = { "en" }      -- MVP English saja; tambah locale = tambah kolom Entry
autodetect      = "id-*" -> id  -- aktif setelah "id" ada di supported; selain itu -> en
fallback chain  = requested -> defaultLanguage(en) -> raw key
```

- Menambah bahasa (mis. `id` Indonesia, lalu `ms` Melayu) = tambah field di tiap
  `Entry` + daftarkan di `supported`. Tidak ada perubahan kode pemanggil `t()`.
- **MVP sekarang**: hanya `en` (sumber resmi), in-place — belum ada modul `Strings`.
  Terjemahan manual ditambahkan saat owner minta, tanpa cloud table Roblox.

---

## 9. Integration Points

| System | Arah | Interaksi |
|---|---|---|
| #1 Persistence | Localization → it | Field `settings.language` + migrasi backfill `"id"`; persist via remote. |
| #13 UI / HUD | Localization ↔ it | Semua teks UI lewat `t(key)`; toggle bahasa hidup di Settings panel. |
| #12 Moment | Localization → it | Toast emit **key + args**, client render. |
| Capture / Kandang / Shop / Combat / Cinematic | downstream | Semua string pemainnya dimigrasi ke key. |
| Remotes (Shared) | Localization → it | Daftar `SetLanguage`; payload toast `text`→`key`. |

---

## 10. Build Order (bertahap — tidak sekaligus)

**0. English normalization (precursor) — ✅ SELESAI 2026-06-08.** Semua teks
pemain yang campur ID/EN diubah ke **English in-place** (bukan via modul):
`DemoConfig` (prompt Kandang/Shop), `DemoServer` (≈11 toast), `DemoUI` (≈16
string UI). Identifier internal (instance Name `KandangPanel`/`KandangPrompt`,
remote `RequestKandang`/`UpgradeKandang`/`OpenKandangMenu`, key status
`"kandang"`) **sengaja dibiarkan** — tak terlihat pemain, mengubahnya = refactor
berisiko (lookup/wire protocol), bukan lokalisasi. Glossary: Kandang→Pen,
Koin→Coins, Jaring→Net, Belanja→Shop, Beli→Buy, Punya→Owned, Semua→All,
Terbaru→Newest, Lolos→Escaped. Game sekarang satu bahasa: **English**.

> **Langkah 1-6 di bawah DITUNDA** sampai owner minta translate (tambah Indonesia
> dll.). Saat itu nilai English tinggal diekstrak ke key.

1. **Fondasi**: `Strings` module + `LocaleConfig` + controller `Locale` (`t()` +
   interpolasi + fallback). Belum ubah pemanggil — infrastruktur dulu.
2. **Persist + remote**: `settings.language` (+ migrasi default `id`) +
   `SetLanguage` + deteksi `LocaleId` saat join pertama.
3. **Migrasi `DemoUI`** (bagian terbesar, ~59 string) → key. Tahap per-panel.
4. **Migrasi toast server** (Moment/CatchCinematic) → payload `key + args`.
5. **Toggle UI** `ID | EN` di Settings + re-render saat ganti.
6. **Sweep sisa**: prompt `ActionText`/`ObjectText`, label `DemoConfig`,
   `CatchCinematic`, dll. Verifikasi tidak ada literal pemain tersisa.

**Definition of done** (fase toggle, nanti): tidak ada string pemain hardcoded
(semua via key); switch bahasa mengganti SELURUH teks UI + toast; pilihan
tersimpan lintas sesi; default `en` (sumber resmi), autodetect ke locale lain
saat terjemahannya sudah ada.
