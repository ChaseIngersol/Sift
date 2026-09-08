local ns = SiftTest.ns
local F = require("fixtures")
local V = ns.VaultRank
local S = ns.Slots.ID

-- A verdict shaped like the engine's, with only what the ranking reads.
local function verdict(kind, sub, nowPct, maxPct, extra)
  local v = { kind = kind, sub = sub, reason = "", notes = {}, flags = {},
    details = { self = { { eligible = true, now = { pct = nowPct }, max = maxPct and { pct = maxPct } or nil } } } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end

describe("VaultRank tiers and gains", function()
  it("orders sure gains, sims, stand-ins, offspec, sends, dead ends, not gear", function()
    local options = {
      { name = "Dead", verdict = verdict("DISPOSE", nil, -0.05) },
      { name = "Send", verdict = verdict("SEND", nil, -0.02) },
      { name = "Off", verdict = verdict("HOLD", "offspec", 0.03) },
      { name = "Stand-in", verdict = verdict("HOLD", "instead", 0.02) },
      { name = "Sim", verdict = verdict("HOLD", "sim", 0.01) },
      { name = "Equip", verdict = verdict("EQUIP", nil, 0.02) },
      { name = "Rock" },
    }
    local ranked = V.Rank(options)
    local names = {}
    for i, o in ipairs(ranked) do names[i] = o.name end
    expect(names).toEqual({ "Equip", "Sim", "Stand-in", "Off", "Send", "Dead", "Rock" })
    expect(ranked[1].place).toBe(1)
    expect(ranked[7].tier).toBe(-1)
  end)

  it("ranks a hold by what it reaches at max rank, above a smaller sure equip", function()
    local ranked = V.Rank({
      { name = "Boots", verdict = verdict("EQUIP", nil, 0.015) },
      { name = "Hero Gloves", verdict = verdict("HOLD", "upgrade", -0.02, 0.06) },
      { name = "Catalyst Chest", verdict = verdict("HOLD", "catalyst", -0.01, 0.03) },
    })
    expect(ranked[1].name).toBe("Hero Gloves")
    expect(ranked[2].name).toBe("Catalyst Chest")
    expect(ranked[3].name).toBe("Boots")
    expect(ranked[1].gain).toBeCloseTo(0.06)
  end)

  it("caps an empty slot instead of treating it as infinite", function()
    local ranked = V.Rank({ { name = "Empty", verdict = verdict("EQUIP", nil, math.huge) }, { name = "Big", verdict = verdict("EQUIP", nil, 0.4) } })
    expect(ranked[1].name).toBe("Empty")
    expect(ranked[1].gain).toBe(0.5)
  end)

  it("breaks ties by item level, then by the order offered", function()
    local a = { name = "A", item = { ilvl = 300 }, verdict = verdict("HOLD", "sim", 0) }
    local b = { name = "B", item = { ilvl = 310 }, verdict = verdict("HOLD", "sim", 0) }
    local c = { name = "C", item = { ilvl = 310 }, verdict = verdict("HOLD", "sim", 0) }
    local ranked = V.Rank({ a, b, c })
    expect(ranked[1].name).toBe("B")
    expect(ranked[2].name).toBe("C")
    expect(ranked[3].name).toBe("A")
  end)

  it("keeps copies of one item together, ranked by the best copy, highest level first", function()
    local ranked = V.Rank({
      { name = "Strand", id = 1, item = { ilvl = 305, id = 1 }, verdict = verdict("HOLD", "upgrade", -0.1, 0.176) },
      { name = "Stare", id = 2, item = { ilvl = 305, id = 2 }, verdict = verdict("HOLD", "upgrade", -0.02, 0.177) },
      { name = "Strand", id = 1, item = { ilvl = 315, id = 1 }, verdict = verdict("HOLD", "upgrade", 0.05, 0.184) },
      { name = "Strand", id = 1, item = { ilvl = 308, id = 1 }, verdict = verdict("HOLD", "upgrade", 0.0, 0.179) },
    })
    local got = {}
    for i, o in ipairs(ranked) do got[i] = o.name .. o.item.ilvl end
    expect(got).toEqual({ "Strand315", "Strand308", "Strand305", "Stare305" })
  end)

  it("collapses identical offers into one row with a count", function()
    local link = "|Hitem:9|h[Heart]|h"
    local ranked = V.Rank({
      { name = "Heart", id = 9, link = link, source = "Raid Normal", verdict = verdict("HOLD", "sim", 0) },
      { name = "Heart", id = 9, link = link, source = "Raid Normal", verdict = verdict("HOLD", "sim", 0) },
      { name = "Heart", id = 9, link = link, source = "Raid Normal", verdict = verdict("HOLD", "sim", 0) },
      { name = "Boots", id = 3, link = "|Hitem:3|h[Boots]|h", source = "Delves tier 11", verdict = verdict("EQUIP", nil, 0.02) },
    })
    local rows = V.Collapse(ranked)
    expect(#rows).toBe(2)
    expect(rows[1].option.name).toBe("Boots")
    expect(rows[2].count).toBe(3)
    expect(V.SourceText(rows[2])).toBe("Raid Normal x3")
    expect(V.SourceText(rows[1])).toBe("Delves tier 11")
  end)

  it("adds where a hold stands today and what it reaches at max rank", function()
    local v = verdict("HOLD", "upgrade", -0.02, 0.184, { reason = "Upgrade now. Beats Neck after 2 upgrades (+18.0%, free)." })
    v.details.self[1].max = { pct = 0.184, rank = 6, ilvl = 321 }
    v.details.self[1].upgrade = { ilvl = 318, pct = 0.18 }
    local ranked = V.Rank({ { name = "Strand", verdict = v }, { name = "Rock" } })
    expect(V.Line(ranked[1])).toBe("Beats Neck after 2 upgrades (+18.0%, free). Now -2.0%. Reaches +18.4% at 6/6 (321).")
    -- Passing rank is the max rank: no repeat. A close call today says so.
    v.details.self[1].upgrade = { ilvl = 321, pct = 0.184 }
    v.details.self[1].now = { pct = 0.155, close = true }
    expect(V.Line(ranked[1])).toBe("Beats Neck after 2 upgrades (+18.0%, free). Now +15.5%, too close to call.")
    -- An equip already says its gain today; only the ceiling is added.
    local e = verdict("EQUIP", nil, 0.042, 0.09, { reason = "Equip. +4.2% vs Boots for Fury." })
    e.details.self[1].max = { pct = 0.09, rank = 6, ilvl = 321 }
    expect(V.Line(V.Rank({ { name = "B", verdict = e } })[1])).toBe("+4.2% vs Boots for Fury. Reaches +9.0% at 6/6 (321).")
    expect(V.Line(ranked[2])).toBe("Not gear.")
    expect(V.Line({ verdict = verdict("DISPOSE", nil, -0.1, nil, { reason = "-10.0% vs Boots for Fury now. No alt wants it. Vendor or disenchant." }), tier = 0 })).toBe("-10.0% vs Boots for Fury now. No alt wants it.")
    expect(V.Line({ verdict = verdict("HOLD", "sim", 0, nil, { reason = "Sim it. Trinket effects cannot be scored." }), tier = 4 })).toBe("Trinket effects cannot be scored.")
  end)
end)

describe("VaultRank words", function()
  it("drops a short verb sentence from the reason and keeps a long one", function()
    expect(V.Short({ reason = "Equip. +4.2% vs Boots for Devourer." })).toBe("+4.2% vs Boots for Devourer.")
    expect(V.Short({ reason = "Hold. Beats Boots after 2 upgrades (40 crests)." })).toBe("Beats Boots after 2 upgrades (40 crests).")
    expect(V.Short({ reason = "Catalyze now, then upgrade and equip. Beats X." })).toBe("Catalyze now, then upgrade and equip. Beats X.")
    expect(V.Short({ reason = "Too close to call." })).toBe("Too close to call.")
  end)

  it("says Take for the best sure pick and the headline otherwise", function()
    local ranked = V.Rank({
      { name = "Boots", verdict = verdict("EQUIP", nil, 0.02) },
      { name = "Ring", verdict = verdict("HOLD", "upgrade", -0.01, 0.01, { ready = false }) },
      { name = "Trinket", verdict = verdict("HOLD", "sim", 0) },
      { name = "Rock" },
    })
    expect(V.Verb(ranked[1])).toBe("Take")
    expect(V.Verb(ranked[2])).toBe("Good")
    expect(V.Verb(ranked[3])).toBe("Sim it")
    expect(V.Verb(ranked[4])).toBe("Not gear")
    expect(V.Kind(ranked[1])).toBe("EQUIP")
    expect(V.Kind(ranked[2])).toBe("HOLD")
    expect(V.Kind(ranked[4])).toBe("DISPOSE")
    expect(V.Verb({ verdict = verdict("DISPOSE", nil, -0.1), tier = 0 })).toBe("Pass")
    expect(V.PlaceText(ranked[1], 4)).toBe("Great Vault: take this one.")
    expect(V.PlaceText(ranked[2], 4)).toContain("2nd of 4, a sure gain but a smaller one")
    expect(V.PlaceText(ranked[3], 4)).toBe("Great Vault: 3rd of 4.")
  end)

  it("headlines the pick and names each sim that could compete once", function()
    local ranked = V.Rank({
      { name = "Boots", source = "Delves tier 8", verdict = verdict("EQUIP", nil, 0.042, nil, { reason = "Equip. +4.2% vs Sandals for Devourer." }) },
      { name = "Trinket", verdict = verdict("HOLD", "sim", 0) },
      { name = "Trinket", verdict = verdict("HOLD", "sim", 0) },
      { name = "Grips", verdict = verdict("DISPOSE", nil, -0.1) },
    })
    expect(V.Headline(ranked)).toBe("Take Boots (Delves tier 8): +4.2% vs Sandals for Devourer. Trinket would need a sim to compete.")
  end)

  it("has a sentence for every other outcome", function()
    expect(V.Headline({})).toBe("Nothing to pick yet.")
    expect(V.Headline(V.Rank({ { name = "T", verdict = verdict("HOLD", "sim", 0) } }))).toContain("sim it before you pick")
    expect(V.Headline(V.Rank({ { name = "S", verdict = verdict("HOLD", "instead", 0.02) } }))).toContain("your own piece passes it once upgraded")
    expect(V.Headline(V.Rank({ { name = "O", verdict = verdict("HOLD", "offspec", 0.02) } }))).toContain("other spec")
    local send = verdict("SEND", nil, -0.02, nil, { target = { char = { name = "Garumis" } } })
    expect(V.Headline(V.Rank({ { name = "W", verdict = send } }))).toBe("Nothing here helps you. W is worth sending to Garumis.")
    expect(V.Headline(V.Rank({ { name = "D", verdict = verdict("DISPOSE", nil, -0.1) } }))).toContain("vendors or disenchants best")
  end)
end)

describe("VaultRank with real verdicts", function()
  it("picks the piece with the larger long-term gain from engine output", function()
    local me = F.equipAll(F.char({ importedWeights = { [72] = { weights = { STRENGTH = 1, HASTE = 0.73, CRIT = 0.53 } } } }), 300)
    local boots = F.item({ name = "Boots", equipLoc = "INVTYPE_FEET", stats = { STAMINA = 1520, CRIT = 415, HASTE = 415 }, flex = { value = 1030, STRENGTH = true } })
    local hero = F.item({ name = "Hero Chest", ilvl = 305, track = "Hero", rank = 1, maxRank = 6,
      stats = { STAMINA = 1450, HASTE = 480, CRIT = 300 }, flex = { value = 972, STRENGTH = true } })
    local trinket = F.trinket({ name = "Trinket", ilvl = 310 })
    local options = {}
    for i, item in ipairs({ boots, hero, trinket }) do
      options[i] = { name = item.name, item = item, verdict = ns.Engine.Evaluate(F.ctx({ item = item, self = me })), source = "Delves tier " .. (5 + i) }
    end
    local ranked = V.Rank(options)
    expect(ranked[1].name).toBe("Hero Chest")
    expect(ranked[1].verdict.sub).toBe("upgrade")
    expect(ranked[2].name).toBe("Boots")
    expect(ranked[2].verdict.kind).toBe("EQUIP")
    expect(ranked[3].verdict.sub).toBe("sim")
    local line = V.Headline(ranked)
    expect(line).toContain("Take Hero Chest (Delves tier 7): Beats Equipped 5 after")
    expect(line).toContain("Trinket would need a sim to compete.")
  end)
end)
