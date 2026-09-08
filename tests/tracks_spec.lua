local ns = SiftTest.ns
local F = require("fixtures")
local T = ns.Tracks

describe("Tracks", function()
  local season = F.season()

  it("anchors rank math on the observed item level", function()
    -- Table says Champion 2/6 is 295; the item says 296. Keep the offset.
    local item = { track = "Champion", rank = 2, maxRank = 6, ilvl = 296 }
    expect(T.IlvlAt(season, item, 6)).toBe(309)
    expect(T.IlvlAt(season, item, 3)).toBe(299)
    expect(T.Ceiling(season, item)).toBe(309)
  end)

  it("uses the current level when there is no track", function()
    expect(T.Ceiling(season, { ilvl = 300 })).toBe(300)
    expect(T.IlvlAt(season, { ilvl = 300 }, 3)).toBeNil()
    expect(T.Ceiling(season, nil)).toBe(0)
  end)

  it("returns nil for unknown tracks or ranks", function()
    expect(T.IlvlAt(season, { track = "Legend", rank = 1, maxRank = 6, ilvl = 300 }, 2)).toBeNil()
    expect(T.IlvlAt(season, { track = "Hero", rank = 1, maxRank = 6, ilvl = 300 }, 9)).toBeNil()
  end)

  it("waives crests for ranks at or under the slot watermark", function()
    local item = { track = "Champion", rank = 1, maxRank = 6, ilvl = 292 }
    expect({ T.UpgradeCost(season, item, 2, nil) }).toEqual({ 40, 0 })
    expect({ T.UpgradeCost(season, item, 2, 295) }).toEqual({ 20, 1 })
    expect({ T.UpgradeCost(season, item, 2, 298) }).toEqual({ 0, 2 })
    expect({ T.UpgradeCost(season, item, 3, 298) }).toEqual({ 20, 2 })
    expect({ T.UpgradeCost(season, { ilvl = 300 }, 2, 310) }).toEqual({ 40, 0 })
  end)

  it("groups paired and weapon slots for watermarks", function()
    expect(T.WatermarkGroup("INVTYPE_FINGER")).toBe("finger")
    expect(T.WatermarkGroup("INVTYPE_ROBE")).toBe("chest")
    expect(T.WatermarkGroup("INVTYPE_2HWEAPON")).toBe(T.WatermarkGroup("INVTYPE_WEAPON"))
    expect(T.WatermarkGroup("INVTYPE_SHIELD")).toBe("offhand")
    expect(T.WatermarkGroup("INVTYPE_BOGUS")).toBeNil()
  end)

  it("computes remaining ranks and crest cost", function()
    expect(T.RanksRemaining({ rank = 2, maxRank = 6 })).toBe(4)
    expect(T.RanksRemaining({ rank = 6, maxRank = 6 })).toBe(0)
    expect(T.RanksRemaining(nil)).toBe(0)
    expect(T.CrestCost(season, 3)).toBe(60)
  end)
end)
