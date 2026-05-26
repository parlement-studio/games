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
