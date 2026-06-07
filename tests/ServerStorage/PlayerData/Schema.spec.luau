--!nocheck
-- tests/ServerStorage/PlayerData/Schema.spec.luau
--
-- TestEZ specs for Schema + Migrations (System #1). AAA pattern, isolated
-- tests, no real DataStore. Covers: new-profile defaults, mint, migrate from
-- old/partial data, count self-heal, corrupt-data handling, idempotency of
-- migrate.

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local Schema = require(ServerStorage.PlayerData.Schema)
    local Migrations = require(ServerStorage.PlayerData.Migrations)
    local CaptureConfig = require(ReplicatedStorage.Shared.Config.CaptureConfig)

    describe("Schema.default", function()
        it("returns a fully-populated profile at the current schema version values", function()
            -- Arrange / Act
            local data = Schema.default()

            -- Assert
            expect(data.coins).to.equal(0)
            expect(data.gems).to.equal(0)
            expect(data.rosterCount).to.equal(0)
            expect(data.nextSeq).to.equal(1)
            expect(type(data.roster)).to.equal("table")
            expect(type(data.txLog)).to.equal("table")
            expect(data.stats.totalCoinsEarned).to.equal(0)
        end)

        it("seeds freeCapturesRemaining from CaptureConfig (single source of truth)", function()
            -- Act
            local data = Schema.default()

            -- Assert
            expect(data.freeCapturesRemaining).to.equal(CaptureConfig.freeCapturesOnboarding)
        end)

        it("seeds the base block with exactly one starting building 'b1'", function()
            -- Act
            local data = Schema.default()

            -- Assert
            expect(data.base.buildings.b1).to.be.ok()
            expect(data.base.buildings.b1.id).to.equal("b1")
            expect(data.base.buildings.b1.factoryLevel).to.equal(0)
            expect(data.base.pendingOnline).to.equal(0)
            expect(data.base.deployedCount).to.equal(0)
            expect(Schema.countKeys(data.base.buildings)).to.equal(1)
        end)

        it("sets lastSeen and createdAt to the same server time on creation", function()
            -- Act
            local data = Schema.default()

            -- Assert
            expect(data.lastSeen).to.equal(data.createdAt)
        end)
    end)

    describe("Schema.newBrainrot", function()
        it("mints an entry with a unique id, level 1, and seeded history", function()
            -- Arrange / Act
            local a = Schema.newBrainrot({ species = 7, personality = "Hyper", source = "manual", hotspotId = "hs1" })
            local b = Schema.newBrainrot({ species = 7, personality = "Hyper", source = "manual", hotspotId = "hs1" })

            -- Assert
            expect(a.id).never.to.equal(b.id) -- unique GUIDs
            expect(a.level).to.equal(1)
            expect(a.xp).to.equal(0)
            expect(a.evoStage).to.equal(0)
            expect(a.species).to.equal(7)
            expect(a.personality).to.equal("Hyper")
            expect(a.history.coins).to.equal(0)
            expect(a.history.captureSource).to.equal("manual")
            expect(a.history.hotspotId).to.equal("hs1")
            expect(a.fav).to.equal(false)
        end)

        it("rolls a valid element when args omit it (E3 standard capture path)", function()
            -- Act
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Assert
            expect(Schema.isValidElement(entry.element)).to.equal(true)
        end)

        it("keeps a supplied VALID element (deterministic caller)", function()
            -- Act
            local entry = Schema.newBrainrot({
                species = 1,
                personality = "Loyal",
                element = "Volt",
                source = "manual",
                hotspotId = "",
            })

            -- Assert
            expect(entry.element).to.equal("Volt")
        end)

        it("re-rolls (never trusts) a supplied INVALID element", function()
            -- Act
            local entry = Schema.newBrainrot({
                species = 1,
                personality = "Loyal",
                element = "Shadow" :: any,
                source = "manual",
                hotspotId = "",
            })

            -- Assert: not the garbage value; a valid roll instead.
            expect(entry.element).never.to.equal("Shadow")
            expect(Schema.isValidElement(entry.element)).to.equal(true)
        end)

        it("rolls a WILD rarity (Common/Uncommon only) when args omit it (R1)", function()
            -- Act + Assert: 30 mints — never a boss-tier rarity from grass.
            for _ = 1, 30 do
                local entry =
                    Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })
                expect(entry.rarity == "Common" or entry.rarity == "Uncommon").to.equal(true)
            end
        end)

        it("keeps a supplied VALID rarity (boss-drop path, e.g. Rare)", function()
            -- Act
            local entry = Schema.newBrainrot({
                species = 1,
                personality = "Loyal",
                rarity = "Rare",
                source = "manual",
                hotspotId = "boss",
            })

            -- Assert
            expect(entry.rarity).to.equal("Rare")
        end)

        it("falls back to the wild roll on a supplied INVALID rarity", function()
            -- Act
            local entry = Schema.newBrainrot({
                species = 1,
                personality = "Loyal",
                rarity = "Mythic" :: any,
                source = "manual",
                hotspotId = "",
            })

            -- Assert: not the garbage value; a rollable wild tier instead.
            expect(entry.rarity).never.to.equal("Mythic")
            expect(entry.rarity == "Common" or entry.rarity == "Uncommon").to.equal(true)
        end)
    end)

    describe("Schema.isValidRarity", function()
        it("accepts every valid rarity enum value", function()
            for _, r in ipairs(Schema.RARITIES) do
                expect(Schema.isValidRarity(r)).to.equal(true)
            end
        end)

        it("rejects an invalid or non-string rarity", function()
            expect(Schema.isValidRarity("Mythic")).to.equal(false)
            expect(Schema.isValidRarity(42)).to.equal(false)
            expect(Schema.isValidRarity(nil)).to.equal(false)
        end)
    end)

    describe("Schema.isValidElement", function()
        it("accepts every valid element enum value", function()
            for _, e in ipairs(Schema.ELEMENTS) do
                expect(Schema.isValidElement(e)).to.equal(true)
            end
        end)

        it("rejects an invalid or non-string element", function()
            expect(Schema.isValidElement("Shadow")).to.equal(false)
            expect(Schema.isValidElement(42)).to.equal(false)
            expect(Schema.isValidElement(nil)).to.equal(false)
        end)
    end)

    describe("Schema.isValidPersonality", function()
        it("accepts every valid personality enum value", function()
            for _, p in ipairs(Schema.PERSONALITIES) do
                expect(Schema.isValidPersonality(p)).to.equal(true)
            end
        end)

        it("rejects an invalid or non-string personality", function()
            expect(Schema.isValidPersonality("Nope")).to.equal(false)
            expect(Schema.isValidPersonality(42)).to.equal(false)
            expect(Schema.isValidPersonality(nil)).to.equal(false)
        end)
    end)

    describe("Migrations.migrate", function()
        it("treats an untagged legacy table as v1 and stamps the current version", function()
            -- Arrange: a minimal legacy record with no version field.
            local legacy = { coins = 500 }

            -- Act
            local migrated = Migrations.migrate(legacy)

            -- Assert
            expect(migrated.version).to.equal(Schema.CURRENT_SCHEMA_VERSION)
            expect(migrated.coins).to.equal(500) -- existing data preserved
        end)

        it("backfills every missing field on a partial record", function()
            -- Arrange: only coins present.
            local partial = { coins = 100 }

            -- Act
            local d = Migrations.migrate(partial)

            -- Assert: defensive backfill filled the rest.
            expect(d.gems).to.equal(0)
            expect(d.rosterCount).to.equal(0)
            expect(d.nextSeq).to.equal(1)
            expect(d.freeCapturesRemaining).to.equal(CaptureConfig.freeCapturesOnboarding)
            expect(d.base.buildings.b1).to.be.ok()
            expect(d.pendingOffline.coins).to.equal(0)
            expect(d.stats.totalCoinsEarned).to.equal(0)
            expect(type(d.txLog)).to.equal("table")
        end)

        it("self-heals a drifted rosterCount cache from the actual roster map", function()
            -- Arrange: two entries but a wrong cached count.
            local data = {
                roster = {
                    ["id-a"] = { personality = "Loyal" },
                    ["id-b"] = { personality = "Hyper" },
                },
                rosterCount = 99, -- deliberately wrong
            }

            -- Act
            local d = Migrations.migrate(data)

            -- Assert
            expect(d.rosterCount).to.equal(2)
        end)

        it("repairs an invalid personality on a roster entry without throwing", function()
            -- Arrange
            local data = {
                roster = { ["id-x"] = { personality = "Garbage", level = 5 } },
            }

            -- Act
            local d = Migrations.migrate(data)

            -- Assert: enum repaired to a valid value; other fields preserved.
            expect(Schema.isValidPersonality(d.roster["id-x"].personality)).to.equal(true)
            expect(d.roster["id-x"].level).to.equal(5)
            expect(d.roster["id-x"].id).to.equal("id-x") -- id backfilled from map key
        end)

        it("is idempotent: running twice yields the same stable result", function()
            -- Arrange
            local once = Migrations.migrate({ coins = 10 })

            -- Act
            local twice = Migrations.migrate(once)

            -- Assert
            expect(twice.version).to.equal(Schema.CURRENT_SCHEMA_VERSION)
            expect(twice.coins).to.equal(10)
            expect(twice.rosterCount).to.equal(0)
        end)

        it("throws on structurally-unusable input so the load path can treat it as a failed load (E8)", function()
            -- Arrange / Act / Assert
            expect(function()
                Migrations.migrate("not a table")
            end).to.throw()
        end)

        it("normalizes a LEGACY array-form txLog into the map + order list (ADR-001 C1)", function()
            -- Arrange: an old record whose txLog is a plain array of keys.
            local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
            local legacy = { coins = 1, txLog = { "k-a", "k-b", "k-c" } }

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: map presence + preserved insertion order; values default true.
            expect(d.txLog["k-a"]).to.equal(true)
            expect(d.txLog["k-c"]).to.equal(true)
            expect(#d.txLogOrder).to.equal(3)
            expect(d.txLogOrder[1]).to.equal("k-a")
            expect(d.txLogOrder[3]).to.equal("k-c")
            -- And it remains bounded.
            expect(#d.txLogOrder <= Config.txLogMaxEntries).to.equal(true)
        end)

        it("backfills consumedReceipts + consumedReceiptsOrder on an older record (ADR-001 §3)", function()
            -- Arrange: a record predating durable receipts.
            local d = Migrations.migrate({ coins = 1 })

            -- Assert
            expect(type(d.consumedReceipts)).to.equal("table")
            expect(type(d.consumedReceiptsOrder)).to.equal("table")
            expect(#d.consumedReceiptsOrder).to.equal(0)
        end)

        it("MIGRATES legacy boolean-true consumedReceipts markers to numeric timestamps (ADR-002 H-2)", function()
            -- Arrange: an in-flight profile in the OLD presence-set shape
            -- ({ [purchaseId] = true }) plus a matching order list.
            local before = os.time()
            local legacy = {
                coins = 1,
                consumedReceipts = { x = true, y = true },
                consumedReceiptsOrder = { "x", "y" },
            }

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: each boolean marker is now a numeric stamp (~now), so it
            -- is NOT immediately pruned by the next consume; order preserved.
            expect(type(d.consumedReceipts.x)).to.equal("number")
            expect(type(d.consumedReceipts.y)).to.equal("number")
            expect(d.consumedReceipts.x >= before).to.equal(true)
            expect(#d.consumedReceiptsOrder).to.equal(2)
        end)

        it("trims an over-cap legacy txLog array to txLogMaxEntries (oldest evicted)", function()
            -- Arrange
            local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
            local keys = {}
            for i = 1, Config.txLogMaxEntries + 10 do
                keys[i] = "k-" .. i
            end
            local legacy = { coins = 1, txLog = keys }

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: trimmed; oldest gone, newest present.
            expect(#d.txLogOrder).to.equal(Config.txLogMaxEntries)
            expect(d.txLog["k-1"]).to.equal(nil)
            expect(d.txLog["k-" .. (Config.txLogMaxEntries + 10)]).to.equal(true)
        end)

        it("BACKFILLS a missing element on a legacy roster entry with a valid ROLL (element doc §3)", function()
            -- Arrange: a pre-element roster entry (no element field).
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-legacy"] = { id = "guid-legacy", species = 3, personality = "Hyper" },
                },
            }

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: a valid element was rolled in (not nil, not garbage).
            expect(Schema.isValidElement(d.roster["guid-legacy"].element)).to.equal(true)
        end)

        it("KEEPS a valid stored element on re-migration (idempotency; element is PERMANENT, E4)", function()
            -- Arrange: an entry that already carries Volt.
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-volt"] = { id = "guid-volt", species = 3, personality = "Hyper", element = "Volt" },
                },
            }

            -- Act: migrate twice (load, save, load again).
            local once = Migrations.migrate(legacy)
            local twice = Migrations.migrate(once)

            -- Assert: Volt survives both passes — never re-rolled.
            expect(once.roster["guid-volt"].element).to.equal("Volt")
            expect(twice.roster["guid-volt"].element).to.equal("Volt")
        end)

        it("RE-ROLLS an invalid stored element (corruption repair) via the repair hook", function()
            -- Arrange: a corrupted enum + a deterministic injected repair so the
            -- assertion is exact (mirrors the setPersonalityRepair test idiom).
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-bad"] = { id = "guid-bad", species = 3, personality = "Hyper", element = "Shadow" },
                },
            }
            local Migs = Migrations
            Migs.setElementRepair(function(entry)
                if Schema.isValidElement(entry.element) then
                    return entry.element
                end
                return "Water"
            end)

            -- Act
            local d = Migs.migrate(legacy)

            -- Assert: the corrupt value was replaced by the injected repair.
            expect(d.roster["guid-bad"].element).to.equal("Water")

            -- Cleanup: restore the production repair (valid-keep + uniform roll).
            local ElementConfig = require(ReplicatedStorage.Shared.Config.ElementConfig)
            Migs.setElementRepair(function(entry)
                if Schema.isValidElement(entry.element) then
                    return entry.element
                end
                return ElementConfig.rollElement()
            end)
        end)

        it("BACKFILLS a missing rarity on a legacy entry with a WILD roll (R5)", function()
            -- Arrange: a pre-rarity roster entry.
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-old"] = { id = "guid-old", species = 3, personality = "Hyper", element = "Fire" },
                },
            }

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: a rollable wild tier (never a boss tier from backfill).
            local rarity = d.roster["guid-old"].rarity
            expect(rarity == "Common" or rarity == "Uncommon").to.equal(true)
        end)

        it("KEEPS a valid stored rarity on re-migration (idempotency; permanent per R5)", function()
            -- Arrange: an entry that already carries Rare (boss drop).
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-rare"] = {
                        id = "guid-rare",
                        species = 2,
                        personality = "Lazy",
                        element = "Water",
                        rarity = "Rare",
                    },
                },
            }

            -- Act: migrate twice (load, save, load again).
            local once = Migrations.migrate(legacy)
            local twice = Migrations.migrate(once)

            -- Assert: Rare survives both passes — never re-rolled.
            expect(once.roster["guid-rare"].rarity).to.equal("Rare")
            expect(twice.roster["guid-rare"].rarity).to.equal("Rare")
        end)

        it("RE-ROLLS an invalid stored rarity via the repair hook", function()
            -- Arrange: corrupted enum + deterministic injected repair.
            local legacy = {
                coins = 1,
                roster = {
                    ["guid-bad-r"] = {
                        id = "guid-bad-r",
                        species = 1,
                        personality = "Rebel",
                        element = "Volt",
                        rarity = "Mythic",
                    },
                },
            }
            Migrations.setRarityRepair(function(entry)
                if Schema.isValidRarity(entry.rarity) then
                    return entry.rarity
                end
                return "Uncommon"
            end)

            -- Act
            local d = Migrations.migrate(legacy)

            -- Assert: the corrupt value was replaced by the injected repair.
            expect(d.roster["guid-bad-r"].rarity).to.equal("Uncommon")

            -- Cleanup: restore the production repair (valid-keep + wild roll).
            local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)
            Migrations.setRarityRepair(function(entry)
                if Schema.isValidRarity(entry.rarity) then
                    return entry.rarity
                end
                return RarityConfig.rollRarity()
            end)
        end)
    end)

    describe("Schema.addToRoster / removeFromRoster (pure helpers)", function()
        it("adds to the passed data, maintains rosterCount, and does NOT bump nextSeq", function()
            -- Arrange
            local data = Schema.default()
            local seqBefore = data.nextSeq
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act
            local ok = Schema.addToRoster(data, entry)

            -- Assert: roster + count updated; nextSeq untouched (that is update()'s job).
            expect(ok).to.equal(true)
            expect(data.rosterCount).to.equal(1)
            expect(data.roster[entry.id]).to.be.ok()
            expect(data.nextSeq).to.equal(seqBefore)
        end)

        it("returns the roster_full sentinel at the cap without mutating the roster (C5)", function()
            -- Arrange
            local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
            local data = Schema.default()
            for i = 1, Config.rosterCap do
                data.roster["id-" .. i] = { id = "id-" .. i, personality = "Loyal" }
            end
            data.rosterCount = Config.rosterCap
            local extra = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })

            -- Act
            local ok, reason = Schema.addToRoster(data, extra)

            -- Assert
            expect(ok).to.equal(false)
            expect(reason).to.equal("roster_full")
            expect(data.rosterCount).to.equal(Config.rosterCap)
            expect(data.roster[extra.id]).never.to.be.ok()
        end)

        it("refuses to remove a fav-locked entry unless forced", function()
            -- Arrange
            local data = Schema.default()
            local entry = Schema.newBrainrot({ species = 1, personality = "Loyal", source = "manual", hotspotId = "" })
            entry.fav = true
            Schema.addToRoster(data, entry)

            -- Act
            local ok1, reason = Schema.removeFromRoster(data, entry.id)
            local ok2 = Schema.removeFromRoster(data, entry.id, true)

            -- Assert
            expect(ok1).to.equal(false)
            expect(reason).to.equal("favorited")
            expect(ok2).to.equal(true)
            expect(data.rosterCount).to.equal(0)
        end)
    end)

    describe("Schema.validate", function()
        it("accepts a freshly defaulted profile", function()
            local ok = Schema.validate(Schema.default())
            expect(ok).to.equal(true)
        end)

        it("rejects a profile with an invalid personality entry", function()
            local data = Schema.default()
            data.roster["bad"] = { id = "bad", personality = "Nope" }
            local ok = Schema.validate(data)
            expect(ok).to.equal(false)
        end)
    end)
end
