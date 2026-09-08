-- Season data only. No logic lives in this file. Review every patch.
local _, ns = ...

local Season = {}
ns.Season = Season

Season.id = "midnight-s2"
Season.label = "Midnight Season 2"
Season.interface = 120100

-- Crests spent per upgrade rank. Every rank costs the same this season.
Season.crestPerRank = 20

-- Item level by rank for each upgrade track.
-- Adventurer, Veteran and Champion match published Season 2 charts.
-- VERIFY (spike 5): Hero and Myth rows are inferred from the 16-level span
-- of the lower tracks. Ranks above 6 (Ascendant Venomstones) are left out
-- until observed in game. Tracks.IlvlAt anchors on the observed item level,
-- so only the step pattern between ranks has to be right.
Season.tracks = {
  Adventurer = { 266, 269, 272, 276, 279, 282 },
  Veteran    = { 279, 282, 285, 289, 292, 295 },
  Champion   = { 292, 295, 298, 302, 305, 308 },
  Hero       = { 305, 308, 311, 315, 318, 321 },
  Myth       = { 318, 321, 324, 328, 331, 334 },
}
Season.trackOrder = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- Currency IDs, confirmed 2026-09-06 against Wowhead and the live wallet:
-- the 3442-3446 set reports what was earned against the seasonal cap; a
-- second set with the same names (3437-3441, from the 12.1.0 PTR) lingers
-- with leftover quantities and no tracking. Adapters/Resources.lua uses a
-- pin when the client still knows the currency by that name, otherwise
-- discovers by name; /sift currency <track|catalyst> <id> overrides both.
Season.crestCurrency = { Adventurer = 3442, Veteran = 3443, Champion = 3444, Hero = 3445, Myth = 3446 }
Season.crestNamePattern = "Mistcrest"
-- Season 2 catalyst charges are "Venomblight Manaflux" (3378 is the Season 1
-- currency, sitting at its cap of 8).
Season.catalystCurrency = 3465
Season.catalystNamePattern = "Manaflux"
Season.currencyScanRange = { 2900, 3800 }

-- The tooltip's upgrade line carries a trackStringID. Seed what has been
-- seen; Adapters/ItemFacts.lua learns the rest from the line text.
Season.trackStringIDs = { [973] = "Champion" }

-- Multiplicative growth per item level by stat class, used to value an item
-- at a hypothetical level. Measured 2026-09-06 from same-slot pairs across
-- Champion and Hero gear: eight pairs, all within
-- 0.0005 of these. dps and tertiary are seeds only (VERIFY): no weapon
-- pairs and no tertiary pairs have been observed yet. Adapters/Calibrate.lua
-- replaces any class with a live estimate once enough pairs are seen.
Season.statGrowth = {
  primary = 1.0094,
  secondary = 1.0049,
  stamina = 1.0116,
  armor = 1.0064,
  dps = 1.0094,
  tertiary = 1.0049,
}
-- Same-slot pairs needed before a live estimate overrides the seed, and the
-- range a per-level growth factor may take before it is treated as noise.
Season.growthMinSamples = 3
Season.growthSane = { 1.0, 1.03 }

-- The gem a player would cut for an empty socket: either +32 primary stat
-- or rating split into the best secondary and the second best, whichever
-- the spec's weights value more. Both observed live 2026-09-06 (+32
-- Primary Stat on a belt; +16 Mastery and +7 Haste on a neck).
Season.socketGem = { primary = 32, secondary = { 16, 7 } }

-- Equipment slots that hold tier set pieces: head, shoulder, chest, hands, legs.
Season.tierSlots = { [1] = true, [3] = true, [5] = true, [10] = true, [7] = true }
Season.setThresholds = { 2, 4 }
