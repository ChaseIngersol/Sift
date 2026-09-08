local ns = SiftTest.ns
local F = require("fixtures")
local E = ns.Engine
local S = ns.Slots.ID
local W = ns.Data.WEAPON

-- Chest that is clearly better than the fixture default (about +10%).
local function betterChest(over)
  local o = { stats = { STAMINA = 1500, CRIT = 450, HASTE = 450 }, flex = { value = 1100, STRENGTH = true, AGILITY = true, INTELLECT = true } }
  for k, v in pairs(over or {}) do o[k] = v end
  return F.item(o)
end

local function warrior(over)
  return F.equipAll(F.char(over), 300)
end

describe("Engine EQUIP", function()
  it("equips a clearly better piece for the primary spec", function()
    local v = F.eval({ item = betterChest(), self = warrior() })
    expect(v.kind).toBe("EQUIP")
    expect(v.reason).toContain("clearly better")
    expect(v.reason).toContain("Fury")
    expect(E.Headline(v)).toBe("Equip")
  end)

  it("equips into an empty slot", function()
    local me = warrior()
    me.slots[S.CHEST] = nil
    local v = F.eval({ item = F.item(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.reason).toContain("empty")
  end)

  it("does not equip for a gain under the threshold", function()
    local item = F.item({ stats = { STAMINA = 1500, CRIT = 403, HASTE = 403 } })
    local v = F.eval({ item = item, self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("About the same as Equipped 5 for Fury.")
  end)

  it("treats leather resolved to intellect as usable by a Devourer", function()
    local me = F.equipAll(F.char({ classID = 12, specs = { ns.Data.specs[1480] } }), 300)
    me.slots[S.CHEST] = F.item({ subclassID = 2, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, AGILITY = true, INTELLECT = true } })
    local leather = F.item({ subclassID = 2, stats = { STAMINA = 1500, CRIT = 450, HASTE = 450 }, flex = { value = 1100, AGILITY = true, INTELLECT = true } })
    local v = F.eval({ item = leather, self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.reason).toContain("Devourer")
  end)

  it("respects a custom threshold", function()
    local v = F.eval({ item = betterChest(), self = warrior(), prefs = { threshold = 0.20 } })
    expect(v.kind).toBe("DISPOSE")
  end)

  it("shows a percentage when the spec has imported weights", function()
    local me = warrior({ importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.5 } } } })
    local v = F.eval({ item = betterChest(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.reason).toContain("%")
    expect(v.details.self[1].source).toBe("imported")
  end)

  it("falls back to item level when the candidate has no scorable stats", function()
    local v = F.eval({ item = F.item({ ilvl = 310, stats = {}, flex = F.NIL }), self = warrior() })
    expect(v.kind).toBe("EQUIP")
    expect(v.details.self[1].basis).toBe("ilvl")
  end)

  it("compares a ring against the weaker equipped ring", function()
    local me = warrior()
    me.slots[S.FINGER1] = F.ring({ name = "Ring A", ilvl = 310, stats = { STAMINA = 1080, CRIT = 840, HASTE = 600 } })
    me.slots[S.FINGER2] = F.ring({ name = "Ring B", ilvl = 290, stats = { STAMINA = 720, CRIT = 560, HASTE = 400 } })
    local v = F.eval({ item = F.ring({ ilvl = 300 }), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.reason).toContain("Ring B")
  end)

  it("compares a two-hander against both weapons combined", function()
    local me = warrior()
    local twoH = F.weapon({ equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 1400, CRIT = 600, DPS = 1700 } })
    local v = F.eval({ item = twoH, self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.details.self[1].incumbent.combined).toBe(true)
    local weak = F.weapon({ equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 900, CRIT = 300, DPS = 900 } })
    expect(F.eval({ item = weak, self = warrior() }).kind).toBe("DISPOSE")
  end)
end)

describe("Engine HOLD upgrade", function()
  local function champ1()
    return F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6,
      stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true, AGILITY = true, INTELLECT = true } })
  end

  it("holds a piece that beats the incumbent after one upgrade", function()
    local v = F.eval({ item = champ1(), self = warrior() })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("upgrade")
    local u = v.details.self[1].upgrade
    expect(u.ranks).toBe(1)
    expect(u.crests).toBe(20)
    expect(u.ilvl).toBe(295)
    expect(v.ready).toBe(false)
    expect(v.wake).toEqual({ type = "crests", track = "Champion", need = 20 })
    expect(v.reason).toContain("1 upgrade")
    expect(v.reason).toContain("20 Champion Mistcrests")
    expect(E.Headline(v)).toBe("Hold")
  end)

  it("marks the hold ready when enough crests are held", function()
    local v = F.eval({ item = champ1(), self = warrior(), res = { crests = { Champion = 45 } } })
    expect(v.kind).toBe("HOLD")
    expect(v.ready).toBe(true)
    expect(v.wake).toBeNil()
    expect(v.reason).toContain("you have 45")
    expect(E.Headline(v)).toBe("Upgrade")
  end)

  it("needs more ranks when the gap is larger", function()
    local item = champ1()
    item.stats = { STAMINA = 1350, CRIT = 360, HASTE = 360 }
    item.flex.value = 900
    local v = F.eval({ item = item, self = warrior() })
    expect(v.kind).toBe("HOLD")
    expect(v.details.self[1].upgrade.ranks).toBeGreaterThan(1)
  end)

  it("disposes when even the max rank cannot beat the incumbent", function()
    local item = champ1()
    item.stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }
    item.flex.value = 600
    local v = F.eval({ item = item, self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.details.self[1].upgrade).toBeNil()
  end)

  it("does not hold an item already at max rank", function()
    local item = champ1()
    item.rank, item.maxRank = 6, 6
    local v = F.eval({ item = item, self = warrior() })
    expect(v.kind).toBe("DISPOSE")
  end)

  it("upgrades the incumbent instead when it caps higher and wins at max", function()
    local me = warrior()
    me.slots[S.CHEST] = F.item({ name = "Hero Chest", ilvl = 305, track = "Hero", rank = 1, maxRank = 6 })
    local v = F.eval({ item = betterChest({ ilvl = 308, track = "Champion", rank = 6, maxRank = 6 }), self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("instead")
    expect(v.details.self[1].longTerm).toBe("inc")
    expect(v.reason).toContain("Upgrade Hero Chest instead")
    expect(v.reason).toContain("caps at 321")
    expect(v.reason).toContain("Wear this meanwhile")
    expect(v.wake.type).toBe("crests")
    expect(v.wake.track).toBe("Hero")
    expect(E.Headline(v)).toBe("Hold")
  end)

  it("notes when the held piece caps higher", function()
    local v = F.eval({ item = champ1(), self = warrior() })
    local found = false
    for _, n in ipairs(v.notes) do if n:find("Caps at 308 vs 300", 1, true) then found = true end end
    expect(found).toBe(true)
  end)
end)

describe("Engine HOLD offspec", function()
  it("holds a piece that is only better for a secondary spec", function()
    local me = warrior({ specs = { ns.Data.specs[72], ns.Data.specs[73] } })
    me.slots[S.OFFHAND] = F.item({ name = "Old Shield", equipLoc = "INVTYPE_SHIELD", subclassID = 6, stats = { STAMINA = 1500, CRIT = 300 }, flex = { value = 1500, STRENGTH = true, INTELLECT = true } })
    local shield = F.item({ equipLoc = "INVTYPE_SHIELD", subclassID = 6, stats = { STAMINA = 2000, CRIT = 500 }, flex = { value = 2500, STRENGTH = true, INTELLECT = true } })
    local v = F.eval({ item = shield, self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("offspec")
    expect(v.reason).toContain("Protection")
    expect(v.details.self[1].eligible).toBe(false)
    expect(v.details.self[1].reason).toBe("model")
  end)

  it("does not consider specs that are not listed", function()
    local shield = F.item({ equipLoc = "INVTYPE_SHIELD", subclassID = 6, stats = { STAMINA = 2000 }, flex = { value = 2500, STRENGTH = true, INTELLECT = true } })
    expect(F.eval({ item = shield, self = warrior() }).kind).toBe("DISPOSE")
  end)
end)

describe("Engine brief", function()
  it("gives an equip a percentage and the worn piece", function()
    local me = warrior()
    me.importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.6 } } }
    local v = F.eval({ item = betterChest(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.brief.gain:match("^%+%d+%.%d%%$") ~= nil).toBe(true)
    expect(v.brief.versus).toBe("vs Equipped 5")
    expect(v.brief.when).toBeNil()
    expect(v.brief.sign).toBe("up")
    expect(E.BriefLine(v)).toBe(v.brief.gain .. " vs Equipped 5")
    expect(E.BriefLine(v, { up = "00ff00" })).toBe("|cff00ff00" .. v.brief.gain .. "|r vs Equipped 5")
  end)

  it("uses a tier word without measured weights and names an empty slot", function()
    local v = F.eval({ item = betterChest(), self = warrior() })
    expect(v.brief.gain).toBe("Clearly better")
    local me = warrior()
    me.slots[S.CHEST] = nil
    local empty = F.eval({ item = F.item(), self = me })
    expect(empty.brief.gain).toBeNil()
    expect(empty.brief.versus).toBe("Your chest is empty")
  end)

  it("puts the upgrade count and cost in the condition of a hold", function()
    local me = warrior()
    local item = F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6,
      stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true, AGILITY = true, INTELLECT = true } })
    local v = F.eval({ item = item, self = me, res = { crests = { Champion = 45 } } })
    expect(v.sub).toBe("upgrade")
    expect(v.brief.versus).toBe("vs Equipped 5")
    expect(v.brief.when:find("^after %d upgrades?, %d+ Champion crests$") ~= nil).toBe(true)
    expect(E.BriefLine(v)).toContain(", after")
  end)

  it("names the set on a catalyst and the trinket on a sim", function()
    local me = warrior({ tierCount = 1 })
    local c = F.eval({ item = F.item({ catalystEligible = true }), self = me })
    expect(c.brief.note).toBe("Completes your 2-piece.")
    local t = F.eval({ item = F.trinket({ ilvl = 305 }), self = warrior() })
    expect(t.sub).toBe("sim")
    expect(t.brief.gain).toBe("305")
    expect(t.brief.sign).toBe("flat")
    expect(t.brief.versus).toBe("vs Trinket A at 300")
    expect(t.brief.note).toBe("Trinket effects need a sim.")
  end)

  it("carries the alt on a send and the level on a locked piece", function()
    local alt = F.equipAll(F.char({ name = "Altie" }), 250)
    local v = F.eval({ item = betterChest({ sendable = true, bind = 9 }), self = warrior(), alts = { alt }, prefs = { altFirst = true } })
    expect(v.kind).toBe("SEND")
    expect(v.brief.who).toBe("Altie")
    expect(v.brief.versus).toBe("vs Equipped 5")
    expect(E.BriefLine(v)).toContain("for Altie vs Equipped 5")
    local locked = F.eval({ item = betterChest({ reqLevel = 90 }), self = warrior({ level = 80 }) })
    expect(locked.sub).toBe("level")
    expect(locked.brief.when).toBe("at level 90")
    expect(locked.brief.note).toBe("Then equip.")
  end)

  it("keeps a dispose short and says what it lost to", function()
    local me = warrior()
    me.importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.6 } } }
    local worse = F.item({ ilvl = 280, track = "Champion", rank = 1, maxRank = 2, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } })
    local v = F.eval({ item = worse, self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.brief.gain:sub(1, 1)).toBe("-")
    expect(v.brief.sign).toBe("down")
    expect(v.brief.versus).toBe("vs Equipped 5")
    expect(v.brief.when:find("^still %-%d+%.%d%% at max$") ~= nil).toBe(true)
    local plate = F.eval({ item = F.item({ subclassID = 1 }), self = me })
    expect(plate.brief.gain).toBeNil()
    expect(plate.brief.versus).toBe("Cloth, and you wear plate")
  end)
end)

describe("Engine catalyst minimum track", function()
  it("skips the catalyst for a piece under the minimum and says why", function()
    local me = warrior({ tierCount = 1 })
    local v = F.eval({ item = F.item({ catalystEligible = true, track = "Veteran", rank = 1, maxRank = 6 }), self = me,
      prefs = { catalystMinTrack = "Champion" } })
    expect(v.sub == "catalyst").toBeFalsy()
    expect(v.flags.catalystBelowMin).toBe(true)
    expect(v.notes[1]).toContain("Not for the catalyst: Veteran is under your Champion minimum")
    expect(v.notes[1]).toContain("complete your 2-piece")
  end)

  it("catalyzes at and above the minimum", function()
    for _, track in ipairs({ "Champion", "Hero" }) do
      local me = warrior({ tierCount = 1 })
      local v = F.eval({ item = F.item({ catalystEligible = true, track = track, rank = 1, maxRank = 6 }), self = me,
        prefs = { catalystMinTrack = "Champion" } })
      expect(v.sub).toBe("catalyst")
      expect(v.flags.catalystBelowMin).toBeNil()
    end
  end)

  it("keeps the set-saving catalyst above the minimum and drops it below", function()
    local me = warrior({ tierCount = 4 })
    me.slots[S.CHEST].isTier = true
    local above = F.eval({ item = betterChest({ catalystEligible = true, track = "Hero", rank = 1, maxRank = 6 }), self = me,
      res = { catalystCharges = 1 }, prefs = { catalystMinTrack = "Champion" } })
    expect(above.sub).toBe("catalyst")
    local below = F.eval({ item = betterChest({ catalystEligible = true, track = "Veteran", rank = 1, maxRank = 6 }), self = me,
      res = { catalystCharges = 1 }, prefs = { catalystMinTrack = "Champion" } })
    expect(below.kind).toBe("HOLD")
    expect(below.sub).toBe("set")
    expect(below.notes[1]).toContain("under your Champion minimum")
  end)

  it("passes a piece whose track is unknown, and everything when the minimum is empty", function()
    local me = warrior({ tierCount = 1 })
    local untracked = F.eval({ item = F.item({ catalystEligible = true }), self = me, prefs = { catalystMinTrack = "Champion" } })
    expect(untracked.sub).toBe("catalyst")
    local any = F.eval({ item = F.item({ catalystEligible = true, track = "Adventurer", rank = 1, maxRank = 6 }), self = me,
      prefs = { catalystMinTrack = "" } })
    expect(any.sub).toBe("catalyst")
    local ok, min = E.CatalystAllowed({ catalystEligible = true, track = "Veteran" }, { catalystMinTrack = "Hero" }, ns.Season)
    expect(ok).toBe(false)
    expect(min).toBe("Hero")
    expect(E.CatalystAllowed({ catalystEligible = false }, {}, ns.Season)).toBe(false)
  end)
end)

describe("Engine catalyst", function()
  it("holds a piece that would complete the 2-piece", function()
    local me = warrior({ tierCount = 1 })
    local v = F.eval({ item = F.item({ catalystEligible = true }), self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("catalyst")
    expect(v.ready).toBe(false)
    expect(v.wake).toEqual({ type = "catalyst" })
    expect(v.reason).toContain("2-piece")
    expect(E.Headline(v)).toBe("Hold for catalyst")
  end)

  it("is ready when a charge exists and says to equip after when it is also better", function()
    local me = warrior({ tierCount = 3 })
    local v = F.eval({ item = betterChest({ catalystEligible = true }), self = me, res = { catalystCharges = 1 } })
    expect(v.kind).toBe("HOLD")
    expect(v.ready).toBe(true)
    expect(v.reason).toContain("4-piece")
    expect(v.reason).toContain("then equip")
    expect(E.Headline(v)).toBe("Catalyze")
  end)

  it("does not count a catalyst hold for a non-tier slot", function()
    local me = warrior({ tierCount = 1 })
    local v = F.eval({ item = F.item({ equipLoc = "INVTYPE_WAIST", catalystEligible = true }), self = me })
    expect(v.kind).toBe("DISPOSE")
  end)

  it("does not complete a set when replacing an existing tier piece", function()
    local me = warrior({ tierCount = 4 })
    me.slots[S.CHEST].isTier = true
    local worse = F.item({ catalystEligible = true, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } })
    expect(F.eval({ item = worse, self = me }).kind).toBe("DISPOSE")
  end)

  it("holds instead of equipping a piece that would break the 4-piece", function()
    local me = warrior({ tierCount = 4 })
    me.slots[S.CHEST].isTier = true
    local v = F.eval({ item = betterChest(), self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("set")
    expect(v.flags.breaksSet).toBe(4)
    expect(v.reason).toContain("breaks your 4-piece")
    expect(v.reason).toContain("off-piece")
    expect(v.wake).toBeNil()
    expect(E.Headline(v)).toBe("Hold")
  end)

  it("does not tell you to upgrade a piece that would then break the 4-piece", function()
    local me = warrior({ tierCount = 4 })
    me.slots[S.CHEST].isTier = true
    local item = F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6,
      stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true, AGILITY = true, INTELLECT = true } })
    local v = F.eval({ item = item, self = me, res = { crests = { Champion = 45 } } })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("set")
    expect(v.reason).toContain("after 1 upgrade")
    expect(v.reason).toContain("breaks your 4-piece")
    local c = F.eval({ item = F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6, catalystEligible = true,
      stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true, AGILITY = true, INTELLECT = true } }),
      self = me, res = { crests = { Champion = 45 }, catalystCharges = 1 } })
    expect(c.sub).toBe("catalyst")
    expect(c.reason).toContain("then upgrade and equip")
    expect(c.reason).toContain("keeps your 4-piece")
  end)

  it("prefers catalyzing over breaking the set when the piece is eligible", function()
    local me = warrior({ tierCount = 4 })
    me.slots[S.CHEST].isTier = true
    local v = F.eval({ item = betterChest({ catalystEligible = true }), self = me, res = { catalystCharges = 1 } })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("catalyst")
    expect(v.ready).toBe(true)
    expect(v.reason).toContain("keeps your 4-piece")
    expect(v.reason).toContain("then equip")
    expect(E.Headline(v)).toBe("Catalyze")
  end)

  it("does not warn at 3 or 5 pieces", function()
    local me = warrior({ tierCount = 3 })
    me.slots[S.CHEST].isTier = true
    local v = F.eval({ item = betterChest(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.flags.breaksSet).toBeNil()
  end)

  -- A tier piece already owned, worse than the worn piece by the numbers.
  local function tierChest(over)
    local it = F.item({ name = "Tier Chest", isTier = true, setID = 7,
      stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } })
    for k, val in pairs(over or {}) do it[k] = val end
    return it
  end

  it("equips a tier piece that completes the 4-piece, whatever its stats say", function()
    local me = warrior({ tierCount = 3, tierSetID = 7 })
    local v = F.eval({ item = tierChest(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.flags.completesSet).toBe(4)
    expect(v.reason).toContain("Completes your 4-piece set")
    expect(v.brief.note).toBe("Completes your 4-piece.")
    expect(v.brief.sign).toBe("down")
    expect(E.Headline(v)).toBe("Equip")
    local two = F.eval({ item = tierChest(), self = warrior({ tierCount = 1, tierSetID = 7 }) })
    expect(two.kind).toBe("EQUIP")
    expect(two.flags.completesSet).toBe(2)
  end)

  it("completes the set ahead of a better piece held in the bags", function()
    local me = warrior({ tierCount = 3, tierSetID = 7 })
    local held = { { item = F.item({ name = "Held Chest", ilvl = 320, stats = { STAMINA = 2000, CRIT = 600, HASTE = 600 },
      flex = { value = 1400, STRENGTH = true, AGILITY = true, INTELLECT = true } }), sub = "upgrade" } }
    local v = F.eval({ item = tierChest(), self = me, held = held })
    expect(v.kind).toBe("EQUIP")
    expect(v.flags.outclassed).toBeNil()
    expect(v.reason).toContain("Completes your 4-piece set")
    local plain = F.eval({ item = tierChest({ isTier = false }), self = me, held = held })
    expect(plain.kind).toBe("DISPOSE")
  end)

  it("holds a third tier piece for the 4-piece instead of disposing it", function()
    local v = F.eval({ item = tierChest(), self = warrior({ tierCount = 2, tierSetID = 7 }) })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("set")
    expect(v.flags.towardSet).toBe(4)
    expect(v.reason).toContain("Tier piece 3 toward your 4-piece")
    expect(v.brief.note).toBe("Tier piece 3 toward your 4-piece.")
    expect(v.wake).toBeNil()
    expect(E.Headline(v)).toBe("Hold")
  end)

  it("judges a fifth piece, another set's piece and a tier-for-tier swap by the numbers", function()
    expect(F.eval({ item = tierChest(), self = warrior({ tierCount = 4, tierSetID = 7 }) }).kind).toBe("DISPOSE")
    expect(F.eval({ item = tierChest({ setID = 9 }), self = warrior({ tierCount = 3, tierSetID = 7 }) }).kind).toBe("DISPOSE")
    local me = warrior({ tierCount = 3, tierSetID = 7 })
    me.slots[S.CHEST].isTier = true
    local swap = F.eval({ item = tierChest(), self = me })
    expect(swap.kind).toBe("DISPOSE")
    expect(swap.flags.completesSet).toBeNil()
  end)
end)

describe("Engine SEND", function()
  local function mage()
    return F.equipAll(F.char({ classID = 8, specs = { ns.Data.specs[63] } }), 300)
  end
  local function weakWarrior(over)
    local alt = F.equipAll(F.char(over), 290)
    alt.slots[S.CHEST] = F.item({ name = "Old Chest", ilvl = 290, stats = { STAMINA = 1350, CRIT = 360, HASTE = 360 }, flex = { value = 900, STRENGTH = true } })
    return alt
  end

  it("sends a piece the owner cannot use to an alt that can", function()
    local alt = weakWarrior({ name = "Mudpaw" })
    local v = F.eval({ item = F.item({ sendable = true }), self = mage(), alts = { alt } })
    expect(v.kind).toBe("SEND")
    expect(v.target.char.name).toBe("Mudpaw")
    expect(v.wake).toEqual({ type = "bank" })
    expect(v.reason).toContain("Send to Mudpaw (Fury)")
    expect(v.reason).toContain("+10 ilvl")
    expect(E.Headline(v)).toBe("Send")
  end)

  it("does not send when the item is bound", function()
    local v = F.eval({ item = F.item({ sendable = false }), self = mage(), alts = { weakWarrior() } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Plate, and you wear cloth.")
  end)

  it("ranks alts by gain and keeps the top three", function()
    local a = weakWarrior({ name = "Small" })
    local b = weakWarrior({ name = "Big" })
    b.slots[S.CHEST] = F.item({ ilvl = 270, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } })
    local c = weakWarrior({ name = "Mid" })
    c.slots[S.CHEST] = F.item({ ilvl = 280, stats = { STAMINA = 1200, CRIT = 300, HASTE = 300 }, flex = { value = 800, STRENGTH = true } })
    local d = weakWarrior({ name = "Parked", parked = true })
    d.slots[S.CHEST] = F.item({ ilvl = 200, stats = { STAMINA = 100 }, flex = { value = 100, STRENGTH = true } })
    local e = weakWarrior({ name = "Fourth" })
    local v = F.eval({ item = F.item({ sendable = true }), self = mage(), alts = { a, b, c, d, e } })
    expect(v.kind).toBe("SEND")
    expect(v.target.char.name).toBe("Big")
    expect(#v.details.targets).toBe(3)
    expect(v.details.targets[2].char.name).toBe("Mid")
    local names = {}
    for _, t in ipairs(v.details.targets) do names[#names + 1] = t.char.name end
    for _, n in ipairs(names) do expect(n ~= "Parked").toBe(true) end
  end)

  it("skips alts that cannot use the item", function()
    local rogue = F.equipAll(F.char({ classID = 4, specs = { ns.Data.specs[260] } }), 250)
    local v = F.eval({ item = F.item({ sendable = true }), self = mage(), alts = { rogue } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("No alt wants it.")
  end)

  it("sends to an alt with an empty slot", function()
    local alt = weakWarrior({ name = "Bare" })
    alt.slots[S.CHEST] = nil
    local v = F.eval({ item = F.item({ sendable = true }), self = mage(), alts = { alt } })
    expect(v.kind).toBe("SEND")
    expect(v.reason).toContain("empty chest")
  end)

  it("uses the best spec of an alt", function()
    local alt = weakWarrior({ name = "Dual", specs = { ns.Data.specs[71], ns.Data.specs[73] } })
    alt.slots[S.OFFHAND] = F.item({ name = "Old Shield", equipLoc = "INVTYPE_SHIELD", subclassID = 6, stats = { STAMINA = 1500, CRIT = 300 }, flex = { value = 1500, STRENGTH = true, INTELLECT = true } })
    local shield = F.item({ equipLoc = "INVTYPE_SHIELD", subclassID = 6, sendable = true, stats = { STAMINA = 2000, CRIT = 500 }, flex = { value = 2500, STRENGTH = true, INTELLECT = true } })
    local v = F.eval({ item = shield, self = mage(), alts = { alt } })
    expect(v.kind).toBe("SEND")
    expect(v.target.spec.name).toBe("Protection")
  end)
end)

describe("Engine precedence", function()
  local function altWarrior()
    local alt = F.equipAll(F.char({ name = "Alt" }), 280)
    alt.slots[S.CHEST] = F.item({ ilvl = 280, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } })
    return alt
  end

  it("keeps a self verdict first and mentions the alt", function()
    local v = F.eval({ item = betterChest({ sendable = true }), self = warrior(), alts = { altWarrior() } })
    expect(v.kind).toBe("EQUIP")
    expect(v.notes[1]).toContain("Also for Alt")
  end)

  it("puts the alt first when the preference says so", function()
    local v = F.eval({ item = betterChest({ sendable = true }), self = warrior(), alts = { altWarrior() }, prefs = { altFirst = true } })
    expect(v.kind).toBe("SEND")
    expect(v.notes[1]).toContain("Equip.")
  end)

  it("falls through to SEND when there is no self verdict", function()
    local item = F.item({ sendable = true, stats = { STAMINA = 1500, CRIT = 403, HASTE = 403 } })
    local v = F.eval({ item = item, self = warrior(), alts = { altWarrior() } })
    expect(v.kind).toBe("SEND")
  end)
end)

describe("Engine DISPOSE and flags", function()
  it("explains a worse item", function()
    local v = F.eval({ item = F.item({ stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Worse than Equipped 5 for Fury.")
    expect(E.Headline(v)).toBe("Dispose")
  end)

  it("explains a primary stat mismatch", function()
    local v = F.eval({ item = F.trinket({ stats = { INTELLECT = 900, CRIT = 100 } }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Intellect gear, and Fury uses Strength.")
  end)

  it("explains an adaptive item the spec cannot use", function()
    local v = F.eval({ item = F.item({ subclassID = 2, flex = { value = 1200, AGILITY = true, INTELLECT = true } }), self = F.equipAll(F.char({ classID = 4, specs = { ns.Data.specs[260] } }), 300) })
    expect(v.kind).toBe("EQUIP")
    local v2 = F.eval({ item = F.item({ subclassID = 4, flex = { value = 500, AGILITY = true, INTELLECT = true } }), self = warrior() })
    expect(v2.reason).toContain("Agility or Intellect gear, and Fury uses Strength.")
  end)

  it("explains a weapon the class cannot use", function()
    local bow = F.weapon({ equipLoc = "INVTYPE_RANGEDRIGHT", subclassID = W.BOW, stats = { AGILITY = 500, DPS = 900 } })
    local v = F.eval({ item = bow, self = warrior() })
    expect(v.reason).toContain("Warrior cannot use bows.")
  end)

  it("shows a percentage in the dispose reason with imported weights", function()
    local me = warrior({ importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.5 } } } })
    local v = F.eval({ item = F.item({ stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } }), self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("% vs Equipped 5 for Fury.")
  end)

  it("says when no alts are on file for a sendable item", function()
    local v = F.eval({ item = F.item({ sendable = true, stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } }), self = warrior(), alts = {} })
    expect(v.reason).toContain("No alts on file yet.")
  end)

  it("flags effects and cantrips as notes", function()
    local v = F.eval({ item = F.item({ hasEffect = true, cantrip = "Echo of Ula'tek", stats = { STAMINA = 1000, CRIT = 200, HASTE = 200 }, flex = { value = 600, STRENGTH = true } }), self = warrior() })
    expect(v.flags.effect).toBe(true)
    expect(v.flags.cantrip).toBe(true)
    local joined = table.concat(v.notes, " | ")
    expect(joined).toContain("effect")
    expect(joined).toContain("Echo of Ula'tek")
  end)

  it("handles a character with no specs", function()
    local me = F.char({ specs = {} })
    me.specs = {}
    local v = F.eval({ item = F.item(), self = me })
    expect(v.kind).toBe("DISPOSE")
  end)

  it("treats an unknown equip location as unusable", function()
    local v = F.eval({ item = F.item({ equipLoc = "INVTYPE_BOGUS" }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.details.self[1].eligible).toBe(false)
    expect(v.details.self[1].reason).toBe("slot")
  end)
end)

describe("Engine confidence", function()
  -- Same primary, secondaries shuffled: only the ordering decides, and the
  -- shipped ordering is not trusted that far.
  local function sidegrade(over)
    local o = { stats = { STAMINA = 1500, MASTERY = 450, VERSATILITY = 450 }, flex = { value = 1000, STRENGTH = true, AGILITY = true, INTELLECT = true } }
    for k, v in pairs(over or {}) do o[k] = v end
    return F.item(o)
  end

  it("says sim it when the sign does not survive the weight band", function()
    local v = F.eval({ item = sidegrade(), self = warrior() })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.flags.sim).toBe(true)
    expect(v.reason).toContain("Too close to call")
    expect(v.reason).toContain("Sim it.")
    expect(v.details.self[1].now.close).toBe(true)
    expect(E.Headline(v)).toBe("Sim it")
    expect(v.wake).toBeNil()
  end)

  it("trusts imported weights further", function()
    local me = warrior({ importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.5, MASTERY = 0.8, VERSATILITY = 0.4 } } } })
    local v = F.eval({ item = sidegrade(), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.details.self[1].now.close).toBe(false)
    expect(v.details.self[1].band).toBe(0.10)
  end)

  it("keeps equipping when a primary stat gap decides it", function()
    local v = F.eval({ item = betterChest(), self = warrior() })
    expect(v.kind).toBe("EQUIP")
    expect(v.details.self[1].now.close).toBe(false)
    expect(v.details.self[1].now.margin).toBeGreaterThan(0)
  end)

  it("still disposes a clearly worse piece", function()
    local v = F.eval({ item = F.item({ stats = { STAMINA = 1000, MASTERY = 200, VERSATILITY = 200 }, flex = { value = 600, STRENGTH = true } }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.details.self[1].now.close).toBe(false)
  end)

  it("holds for an upgrade that becomes confident and notes the close call now", function()
    local item = F.item({ ilvl = 300, track = "Champion", rank = 3, maxRank = 6, stats = { STAMINA = 1500, CRIT = 420, HASTE = 380 } })
    local v = F.eval({ item = item, self = warrior() })
    expect(v.details.self[1].now.close).toBe(true)
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("upgrade")
    expect(v.details.self[1].upgrade.ranks).toBe(1)
    local joined = table.concat(v.notes, " | ")
    expect(joined).toContain("Too close to call as-is")
  end)

  it("never finds a confident rank when the secondaries are all different", function()
    local item = sidegrade({ ilvl = 300, track = "Champion", rank = 3, maxRank = 6 })
    local v = F.eval({ item = item, self = warrior() })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.details.self[1].upgrade).toBeNil()
  end)

  it("says sim it when an upgrade only reaches a close call", function()
    local item = F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6, stats = { STAMINA = 1500, CRIT = 200, HASTE = 600 }, flex = { value = 850, STRENGTH = true, AGILITY = true, INTELLECT = true } })
    local v = F.eval({ item = item, self = warrior() })
    expect(v.details.self[1].now.close).toBe(false)
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.reason).toContain("Might beat")
    expect(v.details.self[1].upgradeClose).toBeTruthy()
    expect(v.details.self[1].upgrade).toBeNil()
  end)

  it("does not hold a close call for an offspec, only notes it", function()
    local me = warrior({ specs = { ns.Data.specs[72], ns.Data.specs[71] } })
    local item = F.item({ stats = { STAMINA = 1000, MASTERY = 200, VERSATILITY = 200 }, flex = { value = 600, STRENGTH = true } })
    local v = F.eval({ item = item, self = me })
    expect(v.kind).toBe("DISPOSE")
    me.slots[S.CHEST] = sidegrade({ name = "Arms Chest" })
    local v2 = F.eval({ item = F.item({ name = "Sidegrade" }), self = me })
    expect(v2.kind).toBe("HOLD")
    expect(v2.sub).toBe("sim")
  end)

  it("keeps close calls off the send list", function()
    local alt = F.equipAll(F.char({ name = "Alt" }), 300)
    alt.slots[S.CHEST] = sidegrade({ name = "Alt Chest", stats = { STAMINA = 1500, MASTERY = 380, VERSATILITY = 380 } })
    local mage = F.equipAll(F.char({ classID = 8, specs = { ns.Data.specs[63] } }), 300)
    local v = F.eval({ item = F.item({ sendable = true }), self = mage, alts = { alt } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Only a close call for Alt.")
    expect(#v.details.targets).toBe(0)
    expect(#v.details.closeTargets).toBe(1)
  end)

  it("exposes the math behind a verdict", function()
    local v = F.eval({ item = betterChest(), self = warrior() })
    local rows, summary = E.Math(v)
    expect(#rows).toBeGreaterThan(1)
    expect(rows[1].label).toBe("Strength")
    expect(rows[1].cand).toBeGreaterThan(rows[1].inc)
    expect(summary).toContain("Sign holds")
    expect(summary).toContain("30%")
    local me = warrior()
    me.slots[S.CHEST] = nil
    expect(E.Math(F.eval({ item = F.item(), self = me }))).toBeNil()
  end)
end)

describe("Engine trinkets", function()
  it("always asks for a sim when a trinket could compete", function()
    local v = F.eval({ item = F.trinket({ ilvl = 305, stats = { STRENGTH = 1200, CRIT = 400 } }), self = warrior() })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.reason).toContain("Trinket effects cannot be scored")
    expect(v.reason).toContain("305 vs Trinket A at 300")
    expect(v.notes[1]).toBeNil()
  end)

  it("mentions the reachable level for a lower trinket with upgrades left", function()
    local v = F.eval({ item = F.trinket({ ilvl = 295, track = "Champion", rank = 2, maxRank = 6, stats = { STRENGTH = 500, CRIT = 100 } }), self = warrior() })
    expect(v.sub).toBe("sim")
    expect(v.reason).toContain("308 after upgrades")
  end)

  it("disposes a trinket that cannot reach the weaker equipped one", function()
    local v = F.eval({ item = F.trinket({ ilvl = 280, stats = { STRENGTH = 2000, CRIT = 900 } }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Below Trinket A (300) even fully upgraded (280)")
    expect(v.reason).toContain("need a sim")
  end)

  it("equips a trinket into an empty slot without a sim", function()
    local me = warrior()
    me.slots[S.TRINKET2] = nil
    local v = F.eval({ item = F.trinket(), self = me })
    expect(v.kind).toBe("EQUIP")
  end)

  it("still rejects a trinket with the wrong primary", function()
    local v = F.eval({ item = F.trinket({ ilvl = 320, stats = { INTELLECT = 900 } }), self = warrior() })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Intellect gear")
  end)
end)

describe("Engine gems and growth", function()
  it("counts a gem on the candidate and an empty socket on the incumbent", function()
    local me = warrior()
    local base = F.item({ stats = { STAMINA = 1500, CRIT = 400, HASTE = 400 } })
    local v0 = F.eval({ item = base, self = me })
    expect(v0.kind).toBe("DISPOSE")
    local gemmed = F.item({ stats = { STAMINA = 1500, CRIT = 400, HASTE = 400 }, gems = { HASTE = 50 } })
    local v1 = F.eval({ item = gemmed, self = me })
    expect(v1.kind).toBe("EQUIP")
    me.slots[S.CHEST].sockets = 1
    local v2 = F.eval({ item = gemmed, self = me })
    expect(v2.details.self[1].contribs.inc.SOCKET).toBeGreaterThan(0)
    expect(v2.details.self[1].now.pct).toBeLessThan(v1.details.self[1].now.pct)
  end)

  it("uses per-class growth for upgrade projections", function()
    local season = F.season({ statGrowth = { primary = 1.0, secondary = 1.0, stamina = 1.0 } })
    local item = F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6, stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true } })
    local flat = F.eval({ item = item, self = warrior(), season = season })
    expect(flat.kind).toBe("DISPOSE")
    local grown = F.eval({ item = item, self = warrior() })
    expect(grown.kind).toBe("HOLD")
    expect(grown.sub).toBe("upgrade")
  end)
end)

describe("Engine with SimulationCraft weights", function()
  local saved = ns.WeightsData
  local function withFury(fn)
    ns.WeightsData = { generated = "2026-09-06", specs = { [72] = { profile = "MID2_Warrior_Fury",
      weights = { STRENGTH = 1, HASTE = 0.97, VERSATILITY = 0.79, MASTERY = 0.78, CRIT = 0.72, DPS = 3.7 } } } }
    local ok, err = pcall(fn)
    ns.WeightsData = saved
    if not ok then error(err, 2) end
  end

  it("speaks in percentages and names the source", function()
    withFury(function()
      local v = F.eval({ item = betterChest(), self = warrior() })
      expect(v.kind).toBe("EQUIP")
      expect(v.details.self[1].source).toBe("simc")
      expect(v.details.self[1].band).toBe(0.20)
      expect(v.reason).toContain("% vs Equipped 5 for Fury.")
      local rows, summary = E.Math(v)
      expect(summary).toContain("SimC default weights")
      expect(summary).toContain("20%")
    end)
  end)

  it("still defers to imported weights", function()
    withFury(function()
      local me = warrior({ importedWeights = { [72] = { weights = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.5 } } } })
      local v = F.eval({ item = betterChest(), self = me })
      expect(v.details.self[1].source).toBe("imported")
    end)
  end)
end)

describe("Engine dual wield hands", function()
  local function fury()
    local me = warrior()
    me.slots[S.MAINHAND] = F.weapon({ name = "Main Hand", stats = { STRENGTH = 700, CRIT = 300, DPS = 800 } })
    me.slots[S.OFFHAND] = F.weapon({ name = "Off Hand", stats = { STRENGTH = 700, CRIT = 300, DPS = 700 } })
    return me
  end

  it("puts a better weapon in the main hand and moves the old one down", function()
    local v = F.eval({ item = F.weapon({ stats = { STRENGTH = 700, CRIT = 300, DPS = 900 } }), self = fury() })
    expect(v.kind).toBe("EQUIP")
    local cmp = v.details.self[1]
    expect(cmp.hand).toBe("main")
    expect(cmp.swap).toBe(true)
    expect(cmp.incumbent.item.name).toBe("Off Hand")
    expect(v.reason).toContain("Off Hand")
    expect(table.concat(v.notes, " | ")).toContain("moves to the off hand")
  end)

  it("scores the off hand's dps at the off-hand rate", function()
    local w = ns.Weights.FromSpec(ns.Data.specs[72])
    local off = ns.Weights.ForOffhand(w)
    expect(off.DPS).toBeCloseTo(w.DPS * ns.Weights.OFFHAND_DPS_RATIO, 1e-9)
    expect(off.STRENGTH).toBe(w.STRENGTH)
    expect(ns.Weights.ForOffhand(w)).toBe(off)
    local own = ns.Weights.ForOffhand({ STRENGTH = 1, DPS = 4, DPS_OH = 1.5 })
    expect(own.DPS).toBe(1.5)
    expect(own.DPS_OH).toBeNil()
  end)

  it("compares against the current pair, not the weaker weapon alone", function()
    local me = fury()
    -- Slightly better than the off hand alone but a wash for the pair once
    -- off-hand dps counts less: stays a dispose.
    local v = F.eval({ item = F.weapon({ stats = { STRENGTH = 700, CRIT = 300, DPS = 705 } }), self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.details.self[1].now.inc).toBeCloseTo(v.details.self[1].now.cand - (5 * ns.Weights.FromSpec(ns.Data.specs[72]).DPS * ns.Weights.OFFHAND_DPS_RATIO), 1e-6)
  end)

  it("projects upgrades in the chosen hand", function()
    local me = fury()
    local item = F.weapon({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6, stats = { STRENGTH = 660, CRIT = 280, DPS = 760 } })
    local v = F.eval({ item = item, self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("upgrade")
    expect(v.details.self[1].hand).toBe("off")
    expect(v.details.self[1].upgrade.ranks).toBe(1)
  end)

  it("leaves two-handers and single-weapon specs on the old path", function()
    local me = warrior({ specs = { ns.Data.specs[71] } })
    me.slots[S.MAINHAND] = F.weapon({ name = "Big Sword", equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 1400, CRIT = 600, DPS = 1700 } })
    me.slots[S.OFFHAND] = nil
    local v = F.eval({ item = F.weapon({ equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 1500, CRIT = 650, DPS = 1800 } }), self = me })
    expect(v.kind).toBe("EQUIP")
    expect(v.details.self[1].hand).toBeNil()
  end)
end)

describe("Engine slot watermarks", function()
  local function champ1()
    return F.item({ ilvl = 292, track = "Champion", rank = 1, maxRank = 6,
      stats = { STAMINA = 1470, CRIT = 396, HASTE = 396 }, flex = { value = 990, STRENGTH = true, AGILITY = true, INTELLECT = true } })
  end

  it("makes an upgrade free and ready when the slot has reached that level", function()
    local me = warrior({ watermarks = { chest = 298 } })
    local v = F.eval({ item = champ1(), self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("upgrade")
    expect(v.ready).toBe(true)
    expect(v.wake).toBeNil()
    expect(v.details.self[1].upgrade.crests).toBe(0)
    expect(v.reason).toContain("free, your slot has reached 298")
    expect(E.Headline(v)).toBe("Upgrade")
  end)

  it("charges only for ranks above the watermark", function()
    local me = warrior({ watermarks = { chest = 295 } })
    local item = champ1()
    item.stats = { STAMINA = 1350, CRIT = 360, HASTE = 360 }
    item.flex.value = 900
    local v = F.eval({ item = item, self = me })
    local u = v.details.self[1].upgrade
    expect(u.free).toBe(1)
    expect(u.crests).toBe(20 * (u.ranks - 1))
    expect(v.reason).toContain("1 rank free")
  end)

  it("ignores watermarks of other slots", function()
    local me = warrior({ watermarks = { legs = 320 } })
    local v = F.eval({ item = champ1(), self = me })
    expect(v.details.self[1].upgrade.crests).toBe(20)
    expect(v.ready).toBe(false)
  end)
end)

describe("Engine long term", function()
  -- Fury with imported weights so secondary differences are trusted.
  local function fury(over)
    local me = warrior({ importedWeights = { [72] = { weights = { STRENGTH = 1, HASTE = 0.73, VERSATILITY = 0.65, MASTERY = 0.60, CRIT = 0.53 } } } })
    for k, v in pairs(over or {}) do me[k] = v end
    return me
  end
  local function champMax(over)
    local o = { name = "Champion Chest", ilvl = 308, track = "Champion", rank = 6, maxRank = 6 }
    for k, v in pairs(over or {}) do o[k] = v end
    return F.item(o)
  end

  it("never equips a dead end that is ahead today", function()
    local me = fury()
    me.slots[S.CHEST] = F.item({ name = "Hero Gloves", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 480, CRIT = 300 }, flex = { value = 972, STRENGTH = true } })
    local v = F.eval({ item = champMax(), self = me })
    expect(v.details.self[1].now.pct).toBeGreaterThan(0.01)
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("instead")
    local u = v.details.self[1].instead
    expect(u.rank).toBe(2)
    expect(u.ilvl).toBe(308)
    expect(u.crests).toBe(20)
    expect(v.ready).toBe(false)
    expect(v.wake).toEqual({ type = "crests", track = "Hero", need = 20 })
    expect(v.reason).toContain("Upgrade Hero Gloves instead: at 2/6 (308)")
    expect(v.reason).toContain("20 Hero Mistcrests, you have 0")
    expect(v.instead.name).toBe("Hero Gloves")
  end)

  it("is ready when the incumbent's rank is free or affordable", function()
    local me = fury({ watermarks = { chest = 308 } })
    me.slots[S.CHEST] = F.item({ name = "Hero Gloves", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 480, CRIT = 300 }, flex = { value = 972, STRENGTH = true } })
    local v = F.eval({ item = champMax(), self = me })
    expect(v.sub).toBe("instead")
    expect(v.ready).toBe(true)
    expect(v.wake).toBeNil()
    expect(v.reason).toContain("free, your slot has reached 308")
    expect(E.Headline(v)).toBe("Upgrade yours")
    local paid = F.eval({ item = champMax(), self = (function() local m = fury(); m.slots[S.CHEST] = me.slots[S.CHEST]; return m end)(), res = { crests = { Hero = 80 } } })
    expect(paid.ready).toBe(true)
    expect(paid.reason).toContain("you have 80")
  end)

  it("applies with equal ceilings when the incumbent wins at equal level", function()
    local me = fury({ watermarks = { chest = 308 } })
    me.slots[S.CHEST] = F.item({ name = "Champion Gloves", ilvl = 302, track = "Champion", rank = 4, maxRank = 6,
      stats = { STAMINA = 1400, HASTE = 480, CRIT = 300 }, flex = { value = 945, STRENGTH = true } })
    local v = F.eval({ item = champMax(), self = me })
    expect(v.sub).toBe("instead")
    expect(v.details.self[1].instead.rank).toBe(6)
    expect(v.ready).toBe(true)
  end)

  it("keeps the candidate when it wins at its own ceiling", function()
    local me = fury()
    me.slots[S.CHEST] = F.item({ name = "Hero Gloves", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 100, CRIT = 100 }, flex = { value = 972, STRENGTH = true } })
    local v = F.eval({ item = champMax(), self = me })
    expect(v.details.self[1].longTerm).toBe("cand")
    expect(v.kind).toBe("EQUIP")
    expect(v.notes[1]).toContain("caps higher (321 vs 308)")
  end)

  it("says sim it when the ceilings are too close to call", function()
    local me = warrior()
    me.slots[S.CHEST] = F.item({ name = "Hero Gloves", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 100, CRIT = 600 }, flex = { value = 972, STRENGTH = true } })
    local v = F.eval({ item = champMax(), self = me })
    expect(v.details.self[1].longTerm).toBe("close")
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.reason).toContain("Better now")
    expect(v.reason).toContain("at 321 against this at 308")
  end)

  it("disposes a lower-ceiling piece with the projection spelled out", function()
    local me = fury()
    me.slots[S.HANDS] = F.item({ name = "Stonereaper", ilvl = 308, track = "Hero", rank = 2, maxRank = 6, equipLoc = "INVTYPE_HAND",
      stats = { STAMINA = 2172, CRIT = 106, HASTE = 29 }, flex = { value = 111, STRENGTH = true } })
    local grips = F.item({ name = "Grips", ilvl = 298, track = "Champion", rank = 3, maxRank = 6, equipLoc = "INVTYPE_HAND",
      stats = { STAMINA = 1935, CRIT = 75, VERSATILITY = 53 }, flex = { value = 101, STRENGTH = true } })
    local v = F.eval({ item = grips, self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("vs Stonereaper for Fury now, still")
    expect(v.reason).toContain("at 6/6 (308)")
    expect(table.concat(v.notes, " | ")).toContain("Stonereaper caps higher (321 vs 308)")
    local rows, summary = E.Math(v)
    expect(summary).toContain("At max ranks, 308 vs 321")
  end)

  it("does not hold a dead end for its own upgrades", function()
    local me = fury()
    me.slots[S.CHEST] = F.item({ name = "Hero Chest", ilvl = 311, track = "Hero", rank = 3, maxRank = 6,
      stats = { STAMINA = 1500, HASTE = 440, CRIT = 360 }, flex = { value = 1000, STRENGTH = true } })
    local cand = F.item({ ilvl = 302, track = "Champion", rank = 4, maxRank = 6,
      stats = { STAMINA = 1400, HASTE = 480, CRIT = 320 }, flex = { value = 945, STRENGTH = true } })
    local v = F.eval({ item = cand, self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("stays ahead")
  end)

  it("keeps a dead end off the send list", function()
    local alt = F.equipAll(F.char({ name = "Alt", importedWeights = { [72] = { weights = { STRENGTH = 1, HASTE = 0.73, CRIT = 0.53 } } } }), 300)
    alt.slots[S.CHEST] = F.item({ name = "Alt Hero Chest", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 480, CRIT = 300 }, flex = { value = 972, STRENGTH = true } })
    local mage = F.equipAll(F.char({ classID = 8, specs = { ns.Data.specs[63] } }), 300)
    local v = F.eval({ item = champMax({ sendable = true }), self = mage, alts = { alt } })
    expect(v.kind).toBe("DISPOSE")
    expect(#v.details.targets).toBe(0)
  end)
end)

describe("Engine held competition", function()
  -- Fury with imported weights so ceilings are compared with the tight band.
  local WEIGHTS = { [72] = { weights = { STRENGTH = 1, HASTE = 0.73, VERSATILITY = 0.65, MASTERY = 0.60, CRIT = 0.53 } } }
  local function fury(over)
    local me = warrior({ importedWeights = WEIGHTS })
    for k, v in pairs(over or {}) do me[k] = v end
    return me
  end
  -- Champion 6/6 chest, ahead of the worn 300 today.
  local function champMax(over)
    local o = { name = "Champion Chest", ilvl = 308, track = "Champion", rank = 6, maxRank = 6,
      stats = { STAMINA = 1550, CRIT = 430, HASTE = 430 }, flex = { value = 1050, STRENGTH = true } }
    for k, v in pairs(over or {}) do o[k] = v end
    return F.item(o)
  end
  -- Hero 1/6 chest, behind the worn 300 today, well ahead at 321.
  local function heroOne(over)
    local o = { name = "Hero Chest", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 480, CRIT = 300 }, flex = { value = 972, STRENGTH = true } }
    for k, v in pairs(over or {}) do o[k] = v end
    return F.item(o)
  end

  it("disposes a piece that a held piece beats at max ranks", function()
    local hero = heroOne()
    local v = F.eval({ item = champMax(), self = fury(), held = { { item = hero, sub = "upgrade" } } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.flags.outclassed).toBe(true)
    expect(v.reason).toContain("Outclassed by Hero Chest in your bags")
    expect(v.reason).toContain("at max ranks (308 vs 321) for Fury")
    expect(v.reason).toContain("%")
    expect(v.reason).toContain("Vendor or disenchant")
    expect(table.concat(v.notes, " | ")).toContain("Ahead of Equipped 5 today")
    local c = v.details.self[1].competition
    expect(c.outclassed).toBe(true)
    expect(c.by.item).toBe(hero)
    expect(c.by.where).toBe("held")
    local _, summary = E.Math(v)
    expect(summary).toContain("Hero Chest at 321 scores")
  end)

  it("keeps the piece that wins at its own ceiling", function()
    local v = F.eval({ item = heroOne(), self = fury(), held = { { item = champMax(), sub = "upgrade" } } })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("upgrade")
    local c = v.details.self[1].competition
    expect(c.outclassed).toBe(false)
    expect(#c.beaten).toBe(0)
  end)

  it("keeps both and says so when the ceilings are too close to call", function()
    local rival = champMax({ name = "Rival Chest", stats = { STAMINA = 1550, CRIT = 300, HASTE = 520 } })
    local v = F.eval({ item = champMax(), self = fury(), held = { { item = rival, sub = "sim" } } })
    expect(v.kind).toBe("EQUIP")
    expect(v.flags.outclassed).toBeNil()
    expect(table.concat(v.notes, " | ")).toContain("Also holding Rival Chest for this slot; too close to call")
    expect(v.details.self[1].competition.rival.item).toBe(rival)
  end)

  it("accepts bare item tables in the held list", function()
    local v = F.eval({ item = champMax(), self = fury(), held = { heroOne() } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.flags.outclassed).toBe(true)
  end)

  it("ignores holds that cannot own the slot", function()
    local hero = heroOne()
    for _, sub in ipairs({ "offspec", "instead" }) do
      local v = F.eval({ item = champMax(), self = fury(), held = { { item = hero, sub = sub } } })
      expect(v.kind).toBe("EQUIP")
    end
    local cloth = heroOne({ subclassID = 1, name = "Cloth Hero" })
    expect(F.eval({ item = champMax(), self = fury(), held = { { item = cloth, sub = "upgrade" } } }).kind).toBe("EQUIP")
    local gloves = heroOne({ equipLoc = "INVTYPE_HAND", name = "Hero Gloves" })
    expect(F.eval({ item = champMax(), self = fury(), held = { { item = gloves, sub = "upgrade" } } }).kind).toBe("EQUIP")
    local same = champMax()
    expect(F.eval({ item = same, self = fury(), held = { { item = same, sub = "upgrade" } } }).kind).toBe("EQUIP")
  end)

  it("lets the worn incumbent speak first", function()
    local me = fury()
    me.slots[S.CHEST] = heroOne({ name = "Worn Hero" })
    local v = F.eval({ item = champMax(), self = me, held = { { item = heroOne({ name = "Held Hero" }), sub = "upgrade" } } })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("instead")
    expect(v.reason).toContain("Upgrade Worn Hero instead")
  end)

  it("needs two better pieces before a ring is outclassed", function()
    local me = fury()
    me.slots[S.FINGER1] = F.ring({ name = "Ring A", ilvl = 310, stats = { STAMINA = 1080, CRIT = 840, HASTE = 600 } })
    me.slots[S.FINGER2] = F.ring({ name = "Ring B", ilvl = 290, stats = { STAMINA = 720, CRIT = 560, HASTE = 400 } })
    local heldRing = F.ring({ name = "Held Ring", stats = { STAMINA = 900, CRIT = 750, HASTE = 560 } })
    local v = F.eval({ item = F.ring({ name = "New Ring" }), self = me, held = { { item = heldRing, sub = "sim" } } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Outclassed by Held Ring in your bags")
    local c = v.details.self[1].competition
    expect(c.slots).toBe(2)
    expect(#c.beaten).toBe(2)
    expect(c.beaten[1].item.name).toBe("Ring A")
    expect(table.concat(v.notes, " | ")).toContain("Ahead of Ring B today")

    -- With a weaker Ring A the held ring alone is not enough: both get worn.
    me.slots[S.FINGER1] = F.ring({ name = "Ring A", ilvl = 300, stats = { STAMINA = 900, CRIT = 600, HASTE = 450 } })
    local v2 = F.eval({ item = F.ring({ name = "New Ring" }), self = me, held = { { item = heldRing, sub = "sim" } } })
    expect(v2.kind).toBe("EQUIP")
    expect(#v2.details.self[1].competition.beaten).toBe(1)
  end)

  it("names the worn ring when that is the one in the way", function()
    local me = fury()
    me.slots[S.FINGER1] = F.ring({ name = "Ring A", ilvl = 310, stats = { STAMINA = 1080, CRIT = 840, HASTE = 600 } })
    me.slots[S.FINGER2] = F.ring({ name = "Ring B", ilvl = 290, stats = { STAMINA = 720, CRIT = 560, HASTE = 400 } })
    local strong = F.ring({ name = "Strong Held Ring", stats = { STAMINA = 1100, CRIT = 900, HASTE = 700 } })
    local v = F.eval({ item = F.ring({ name = "New Ring" }), self = me, held = { { item = strong, sub = "upgrade" } } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Outclassed by Ring A, which you wear")
  end)

  it("leaves trinkets and two-handers alone", function()
    local me = fury()
    local t = F.eval({ item = F.trinket({ ilvl = 310 }), self = me, held = { { item = F.trinket({ ilvl = 330 }), sub = "sim" } } })
    expect(t.sub).toBe("sim")
    expect(t.details.self[1].competition).toBeNil()
    local twoH = F.weapon({ equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 1400, CRIT = 600, DPS = 1700 } })
    local bigger = F.weapon({ equipLoc = "INVTYPE_2HWEAPON", subclassID = W.SWORD2H, stats = { STRENGTH = 1600, CRIT = 700, DPS = 1900 } })
    local w = F.eval({ item = twoH, self = warrior(), held = { { item = bigger, sub = "sim" } } })
    expect(w.kind).toBe("EQUIP")
    expect(w.details.self[1].competition).toBeNil()
  end)

  it("still sends an outclassed piece to an alt that wants it", function()
    local alt = F.equipAll(F.char({ name = "Alt" }), 280)
    local v = F.eval({ item = champMax({ sendable = true }), self = fury(), alts = { alt }, held = { { item = heroOne(), sub = "upgrade" } } })
    expect(v.kind).toBe("SEND")
    expect(v.reason).toContain("Send to Alt")
    expect(table.concat(v.notes, " | ")).toContain("Outclassed by Hero Chest for you")
  end)

  it("does not compete for offspecs", function()
    local me = fury({ specs = { ns.Data.specs[72], ns.Data.specs[73] } })
    local v = F.eval({ item = champMax(), self = me, held = { { item = heroOne(), sub = "upgrade" } } })
    expect(v.details.self[1].competition).toBeTruthy()
    expect(v.details.self[2].competition).toBeNil()
  end)
end)

describe("Engine level requirements", function()
  local function sandals(over)
    local o = { name = "Clutchguard Sandals", equipLoc = "INVTYPE_FEET", ilvl = 266, reqLevel = 90, sendable = true,
      stats = { STAMINA = 1325, CRIT = 52, MASTERY = 57 }, flex = { value = 75, STRENGTH = true, INTELLECT = true } }
    for k, v in pairs(over or {}) do o[k] = v end
    return F.item(o)
  end
  local function leveler(over)
    local alt = F.equipAll(F.char({ name = "Garumis", level = 80, classID = 2, specs = { ns.Data.specs[70] } }), 150, { subclassID = 4 })
    alt.slots[S.FEET] = F.item({ name = "Old Boots", equipLoc = "INVTYPE_FEET", ilvl = 150, subclassID = 4,
      stats = { STAMINA = 300, CRIT = 20, HASTE = 20 }, flex = { value = 30, STRENGTH = true, INTELLECT = true } })
    for k, v in pairs(over or {}) do alt[k] = v end
    return alt
  end
  -- A Devourer main who cannot wear plate at all.
  local function devourer()
    return F.equipAll(F.char({ classID = 12, level = 90, specs = { ns.Data.specs[1480] } }), 300, { subclassID = 2 })
  end

  it("sends a piece above an alt's level to the alt who will grow into it", function()
    local v = F.eval({ item = sandals(), self = devourer(), alts = { leveler() } })
    expect(v.kind).toBe("SEND")
    expect(v.reason).toContain("Send to Garumis (Retribution): clearly better in boots (+116 ilvl), at level 90 (now 80).")
    expect(v.details.targets[1].needsLevel).toBe(90)
  end)

  it("still rejects the alt for other reasons at that level", function()
    local cloth = leveler({ classID = 8, specs = { ns.Data.specs[63] } })
    local v = F.eval({ item = sandals(), self = devourer(), alts = { cloth } })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("No alt wants it.")
  end)

  it("puts an alt who can wear it today ahead of one who must level", function()
    local now = F.equipAll(F.char({ name = "Ready", level = 90, classID = 1 }), 250)
    now.slots[S.FEET] = F.item({ name = "Worn Boots", equipLoc = "INVTYPE_FEET", ilvl = 250, stats = { STAMINA = 1200, CRIT = 50, MASTERY = 50 }, flex = { value = 70, STRENGTH = true } })
    local v = F.eval({ item = sandals(), self = devourer(), alts = { leveler(), now } })
    expect(v.kind).toBe("SEND")
    expect(v.reason).toContain("Send to Ready")
    expect(table.concat(v.notes, " | ")).toContain("Or Garumis (Retribution)")
    expect(table.concat(v.notes, " | ")).toContain("at level 90 (now 80)")
  end)

  it("holds a piece above your own level until you get there", function()
    local me = leveler()
    local v = F.eval({ item = sandals({ sendable = false }), self = me })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("level")
    expect(v.ready).toBe(false)
    expect(v.wake).toEqual({ type = "level", need = 90 })
    expect(v.reason).toContain("Needs level 90 (you are 80). Then: clearly better than Old Boots for Retribution.")
    expect(v.flags.level).toBe(90)
    expect(E.Headline(v)).toBe("Hold")
  end)

  it("disposes a piece above your level that would not help you anyway", function()
    local me = leveler()
    me.slots[S.FEET] = F.item({ name = "Great Boots", equipLoc = "INVTYPE_FEET", ilvl = 300, subclassID = 4,
      stats = { STAMINA = 2000, CRIT = 120, HASTE = 120 }, flex = { value = 150, STRENGTH = true } })
    local v = F.eval({ item = sandals({ sendable = false }), self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Great Boots")
  end)

  it("keeps the plain level message when the level is not the only problem", function()
    local me = leveler({ classID = 8, specs = { ns.Data.specs[63] } })
    local v = F.eval({ item = sandals({ sendable = false }), self = me })
    expect(v.kind).toBe("DISPOSE")
    expect(v.reason).toContain("Plate, and you wear cloth.")
  end)
end)

describe("Engine gain and ordering", function()
  local function verdict(kind, now, max, extra)
    local v = { kind = kind, details = { self = { { eligible = true, now = { pct = now }, max = max and { pct = max } or nil } } } }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
  end

  it("is today's gain, or the max-rank gain when there is one", function()
    expect(E.Gain(verdict("EQUIP", 0.03))).toBe(0.03)
    expect(E.Gain(verdict("HOLD", -0.01, 0.04))).toBe(0.04)
    expect(E.Gain(verdict("DISPOSE", -0.12, -0.05))).toBe(-0.05)
  end)

  it("is the alt's gain for a send", function()
    expect(E.Gain(verdict("SEND", -0.2, nil, { target = { pct = 0.5 } }))).toBe(0.5)
  end)

  it("is nil when nothing was scored", function()
    expect(E.Gain(nil)).toBe(nil)
    expect(E.Gain({ kind = "DISPOSE", details = { self = { { eligible = false } } } })).toBe(nil)
  end)

  it("sorts best first, unscored last, ties by name", function()
    local rows = {
      { name = "b", gain = 0.1 }, { name = "z" }, { name = "a", gain = 0.1 },
      { name = "c", gain = math.huge }, { name = "d", gain = -0.3 },
    }
    E.SortByGain(rows)
    local names = {}
    for i, r in ipairs(rows) do names[i] = r.name end
    expect(names).toEqual({ "c", "a", "b", "d", "z" })
  end)
end)

describe("Engine healers", function()
  local function priest()
    return F.equipAll(F.char({ classID = 5, specs = { ns.Data.specs[257] } }), 300)
  end
  it("says Your call for a trinket, since Raidbots does not sim healing", function()
    local v = F.eval({ item = F.trinket({ ilvl = 305, stats = { INTELLECT = 900, CRIT = 300 } }), self = priest() })
    expect(v.kind).toBe("HOLD")
    expect(v.sub).toBe("sim")
    expect(v.flags.noSim).toBe(true)
    expect(E.Headline(v)).toBe("Your call")
    expect(v.reason:find("Your call", 1, true) ~= nil).toBe(true)
    expect(v.reason:lower():find("sim", 1, true)).toBe(nil)
    expect(v.brief.note).toBe("Trinket effects are not scored.")
  end)
  it("says Your call on a close call and never points at a sim", function()
    local item = F.item({ subclassID = 1, stats = { STAMINA = 1500, CRIT = 650, HASTE = 150 } })
    local me = priest()
    me.importedWeights = { [257] = { weights = { INTELLECT = 1, CRIT = 0.5, HASTE = 0.5 } } }
    me.slots[S.CHEST] = F.item({ subclassID = 1 })
    local v = F.eval({ item = item, self = me })
    expect(v.sub).toBe("sim")
    expect(E.Headline(v)).toBe("Your call")
    expect(v.reason:find("Your call", 1, true) ~= nil).toBe(true)
    expect(v.reason:find("Sim it", 1, true)).toBe(nil)
  end)
  it("keeps Sim it for everyone else", function()
    local v = F.eval({ item = F.trinket({ ilvl = 305 }), self = warrior() })
    expect(E.Headline(v)).toBe("Sim it")
    expect(v.flags.noSim).toBe(nil)
  end)
end)

-- Every spec the addon knows, through the engine with a piece in each
-- kind of slot: nothing may error, every verdict must be one of the four.
describe("Engine spec sweep", function()
  local TWO_HAND = { [1] = true, [5] = true, [6] = true, [8] = true, [10] = true }
  local RANGED = { [2] = true, [3] = true, [18] = true, [19] = true }
  local KINDS = { EQUIP = true, HOLD = true, SEND = true, DISPOSE = true }
  local ids = {}
  for id in pairs(ns.Data.specs) do ids[#ids + 1] = id end
  table.sort(ids)
  it("covers all forty specs", function()
    expect(#ids).toBe(40)
  end)
  for _, id in ipairs(ids) do
    local spec = ns.Data.specs[id]
    local class = ns.Data.classes[spec.classID]
    it(string.format("scores every slot for %s %s (%s)", class.name, spec.name, spec.role), function()
      local me = F.equipAll(F.char({ classID = spec.classID, specs = { spec } }), 300)
      local candidates = {
        F.item({ subclassID = class.armor, stats = { STAMINA = 1500, CRIT = 450, HASTE = 450 }, flex = { value = 1100, STRENGTH = true, AGILITY = true, INTELLECT = true } }),
        F.trinket({ ilvl = 305, stats = { [spec.primary] = 900, CRIT = 300 } }),
        F.ring({ stats = { STAMINA = 900, CRIT = 800, HASTE = 600 } }),
      }
      local weapon
      for sub in pairs(class.weapons) do if not weapon or sub < weapon then weapon = sub end end
      if weapon then
        local loc = TWO_HAND[weapon] and "INVTYPE_2HWEAPON" or RANGED[weapon] and "INVTYPE_RANGEDRIGHT" or "INVTYPE_WEAPON"
        candidates[#candidates + 1] = F.weapon({ subclassID = weapon, equipLoc = loc, stats = { STAMINA = 700, CRIT = 300, DPS = 800 }, flex = { value = 800, STRENGTH = true, AGILITY = true, INTELLECT = true } })
      end
      for _, item in ipairs(candidates) do
        local ok, v = pcall(F.eval, { item = item, self = me })
        expect(ok).toBe(true)
        expect(KINDS[v.kind]).toBe(true)
        expect(type(v.reason) == "string" and #v.reason > 0).toBe(true)
        expect(#E.Headline(v) > 0).toBe(true)
        E.BriefLine(v)
        if item.equipLoc == "INVTYPE_TRINKET" and v.sub == "sim" then
          expect(E.Headline(v)).toBe(spec.role == "heal" and "Your call" or "Sim it")
        end
      end
    end)
  end
end)
