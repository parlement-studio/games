# Element System — 2026-06-07

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved 2026-06-07)
**Type**: System decision document — menyelesaikan open decision #1 dari `2026-06-07-monster-relic-rebrand.md` §7. Membuka blokir `boss-system-gdd`, `capture-v2-gdd`, dan ekstensi 3-tier `pet-combat-gdd`.

> **Konteks lore**: Monster Relic "berkembang menjadi berbagai spesies dengan elemen dan kemampuan yang berbeda" (rebrand doc §1). Dokumen ini mengunci bagaimana "elemen" itu bekerja secara mekanik.

---

## 1. Keputusan terkunci

### Keputusan E1: Kedalaman = **Light chart** (bukan full matrix, bukan flavor)
Element adalah **mekanik combat** dengan lingkaran keunggulan sederhana + 1 multiplier flat. Bukan matriks N×N ala Pokémon (terlalu mahal balance untuk solo dev), bukan kosmetik (membuang demand trade + counter-play).

**Rationale**: element bermekanik = mesin permintaan untuk 3 sistem sekaligus — alasan capture variety (#4), demand trade (#30 "aku butuh elemen Water"), counter-play boss (#6). Biaya: 1 fungsi + 1 enum + 1 field schema.

### Keputusan E2: **5 elemen, lingkaran 1-arah** (LOCKED — nama + arah)

```
🔥 Fire  → unggul atas → 🌿 Nature
🌿 Nature → unggul atas → 💧 Water
💧 Water → unggul atas → ⚡ Volt
⚡ Volt  → unggul atas → 🌪️ Wind
🌪️ Wind  → unggul atas → 🔥 Fire
```

Logika kid-friendly: api membakar tanaman; tanaman menyerap air; air memadamkan/menghantarkan listrik; listrik menembus angin; angin meniup padam api.

Tiap elemen unggul atas **tepat satu** elemen dan kalah dari **tepat satu**. Elemen sama vs sama = netral.

### Keputusan E3: Element **di-roll saat capture, uniform 20%**
- Roll **server-side** saat mint `BrainrotEntry` (waktu capture berhasil), uniform `1/5` per elemen, **tanpa bias area**.
- Spesies yang sama bisa muncul dengan elemen berbeda → variety datang dari **kombinasi** (spesies × 5 elemen × 5 personality), bukan jumlah model 3D. 10 spesies = 250 varian unik.
- Boss TIDAK di-roll — element boss **fixed per spec boss** (konten yang didesain; ditampilkan di UI pre-encounter supaya player bisa counter-pick). *(Default keputusan — direkonfirmasi saat boss-system-gdd ditulis.)*

### Keputusan E4: Element **TIDAK bisa di-reroll** (permanen sejak capture)
Hanya Personality yang punya reroll ladder (#11). Element permanen melindungi demand trade + nilai hunting ("mau Emberling Water? berburu lagi atau trade").

### Keputusan E5: Multiplier = **1.25 / 1.00 / 0.75** (config-driven)

---

## 2. Formula (eksplisit)

```
beats = {
    Fire   = "Nature",
    Nature = "Water",
    Water  = "Volt",
    Volt   = "Wind",
    Wind   = "Fire",
}

elementMod(attackerElem, defenderElem):
    if beats[attackerElem] == defenderElem then return advantageMod   -- 1.25
    if beats[defenderElem] == attackerElem then return disadvantageMod -- 0.75
    return 1.00                                                        -- netral (termasuk sama-elemen)

-- Ekstensi formula damage Pet AI (pet-combat-gdd §8):
dmg = baseDmg * levelScale(L) * elementMod(attacker.element, defender.element)
```

**Berlaku simetris dua arah**: summon player → boss DAN boss → summon player memakai fungsi yang sama.

| Parameter | Default | Range tuning | Catatan |
|---|---|---|---|
| `advantageMod` | 1.25 | 1.15–1.40 | Config, jangan hardcode |
| `disadvantageMod` | 0.75 | 0.60–0.85 | Simetris dengan advantage |
| `rollWeights` | uniform 0.20 ×5 | per-elemen | Uniform di launch (Keputusan E3); struktur config tetap per-elemen agar bisa di-tune tanpa migrasi |

---

## 3. Dampak schema & data (persistence #1)

- **Field baru**: `BrainrotEntry.element: "Fire" | "Nature" | "Water" | "Volt" | "Wind"`.
- **Migrasi**: entri roster lama (pre-element) di-backfill **roll uniform sekali** saat migrasi schema, lalu tersimpan permanen. Infra migrasi sudah ada (`Migrations.luau`).
- **Trade (#30)**: element melekat pada monster (ikut pindah saat trade); tidak ada operasi terpisah.
- **Key/format DataStore**: tidak ada rename; murni penambahan field (aturan rebrand doc §6 tetap berlaku).

## 4. Scope efek (orthogonality — LOCKED)

| Sistem | Element berpengaruh? |
|---|---|
| Pet AI boss combat (#25, semua 3 tier) | ✅ via `elementMod` |
| Idle production Kandang (#26) | ❌ — axis idle milik **Personality**, element murni combat |
| Capture success rate (#4) | ❌ — success rate milik item tier vs rarity |
| Trade value (#30) | ✅ implisit (dimensi permintaan pasar) |
| Evolution (#8) | ❌ di MVP — multi-branch Phase 2 boleh mempertimbangkan |
| UI (#13) | ✅ ikon elemen di kartu monster, layar pre-boss (elemen boss + panah hijau/merah di summon picker) |

**Pembagian axis final**: Personality = *bagaimana* monster berperilaku (idle + gaya tarung, rollable + rerollable). Element = *terhadap apa* ia kuat/lemah (combat murni, rollable, permanen).

## 5. Edge cases

1. **Roster lama tanpa element** → backfill roll saat migrasi (§3), bukan default ke satu elemen (hindari banjir elemen tunggal di market trade).
2. **Elemen sama vs sama** (Fire vs Fire) → netral 1.00, bukan resist.
3. **Boss tanpa element di spec** (kesalahan konten) → fallback netral 1.00 + warn log; jangan crash combat.
4. **Roll manipulation** — roll WAJIB server-side dengan RNG server; client tidak pernah mengirim hasil roll (anti-exploit standar remotes).
5. **Party mixed-element vs boss** (Tier 2/3) — tiap summon dihitung individual; tidak ada agregasi party-level.
6. **Demo/prototype** (`BrainrotPack`, `DemoServer`) — TIDAK disentuh; element masuk saat sistem produksi dibangun.

## 6. Yang dibuka blokirnya

- ✅ `boss-system-gdd.md` — boleh ditulis (boss punya elemen fixed, loot/counter-play jelas)
- ✅ `capture-v2-gdd.md` — boleh ditulis (roll element = bagian flow capture)
- ✅ `pet-combat-gdd.md` ekstensi 3-tier — formula §2 siap diintegrasikan ke §8
- ✅ Katalog spesies (world-universe / capture-v2) — spesies tidak perlu dikali elemen; model 3D bebas elemen

## 7. Open follow-ups (tidak memblokir)

- Visual treatment per-elemen pada model (tint/VFX/partikel?) — technical-artist, saat asset pipeline jalan
- Ikon final 5 elemen (placeholder emoji dulu)
- Nama elemen versi in-game per bahasa (EN locked di atas; ID translation saat localization)
- Rekonfirmasi element fixed per boss saat `boss-system-gdd` ditulis (E3 default)

## 8. Audit trail

| Tanggal | Perubahan | Oleh |
|---|---|---|
| 2026-06-07 | E1–E5 dikunci owner (light chart, 5 elemen Fire/Nature/Water/Volt/Wind, roll uniform 20% saat capture, no reroll, ±25% config-driven) | Owner + Claude |

---

**END OF ELEMENT SYSTEM DOC.** Keputusan element selanjutnya rekonsiliasi terhadap doc ini; mekanik combat umum tetap ke Vision Pivot Doc; tema ke Rebrand Doc.
