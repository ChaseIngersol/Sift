local ns = SiftTest.ns
local G = ns.Growth

local function piece(ilvl, prim, sec, stam, over)
  local it = { equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 4, ilvl = ilvl, id = 100 + (ilvl or 0),
    stats = { STAMINA = stam, CRIT = sec / 2, HASTE = sec / 2 }, flex = { value = prim, STRENGTH = true } }
  for k, v in pairs(over or {}) do it[k] = v end
  return it
end

describe("Growth.Totals", function()
  it("sums stats by class and counts the adaptive primary", function()
    local t = G.Totals(piece(300, 100, 160, 2000))
    expect(t.primary).toBe(100)
    expect(t.secondary).toBe(160)
    expect(t.stamina).toBe(2000)
    expect(t.armor).toBeNil()
  end)

  it("ignores gems", function()
    local t = G.Totals(piece(300, 100, 160, 2000, { gems = { MASTERY = 16 } }))
    expect(t.secondary).toBe(160)
  end)
end)

describe("Growth.Observe", function()
  it("groups by slot and item class, keeps distinct levels", function()
    local store = {}
    expect(G.Observe(store, piece(300, 100, 160, 2000))).toBe(true)
    expect(G.Observe(store, piece(300, 100, 160, 2000))).toBe(false)
    expect(G.Observe(store, piece(310, 110, 168, 2240))).toBe(true)
    expect(G.Observe(store, piece(310, 110, 168, 2240, { equipLoc = "INVTYPE_ROBE" }))).toBe(false)
    local n = 0
    for _ in pairs(store.groups) do n = n + 1 end
    expect(n).toBe(1)
    expect(#store.groups["INVTYPE_CHEST:4:4"]).toBe(2)
  end)

  it("replaces a same-level observation whose stats differ", function()
    local store = {}
    G.Observe(store, piece(300, 100, 160, 2000))
    G.Observe(store, piece(300, 100, 170, 2000))
    local g = store.groups["INVTYPE_CHEST:4:4"]
    expect(#g).toBe(1)
    expect(g[1].secondary).toBe(170)
  end)

  it("rejects items without a level or slot and caps the group", function()
    local store = {}
    expect(G.Observe(store, piece(nil, 100, 160, 2000))).toBe(false)
    expect(G.Observe(store, piece(300, 100, 160, 2000, { equipLoc = "" }))).toBe(false)
    expect(G.Observe(store, { equipLoc = "INVTYPE_CHEST", ilvl = 300, stats = {} })).toBe(false)
    for i = 1, G.MAX_PER_GROUP + 3 do G.Observe(store, piece(280 + i, 100, 160, 2000)) end
    expect(#store.groups["INVTYPE_CHEST:4:4"]).toBe(G.MAX_PER_GROUP)
  end)
end)

describe("Growth.Estimate and Resolve", function()
  local seeds = { primary = 1.0094, secondary = 1.0049, stamina = 1.0116, armor = 1.0064, dps = 1.0094, tertiary = 1.0049 }

  it("recovers per-level growth from same-slot pairs", function()
    local store = {}
    local g = { primary = 1.01, secondary = 1.005, stamina = 1.012 }
    for _, il in ipairs({ 292, 298, 305, 321 }) do
      local d = il - 292
      G.Observe(store, piece(il, 100 * g.primary ^ d, 160 * g.secondary ^ d, 2000 * g.stamina ^ d))
    end
    local est = G.Estimate(store)
    expect(est.primary.samples).toBe(6)
    expect(est.primary.value).toBeCloseTo(1.01, 1e-6)
    expect(est.secondary.value).toBeCloseTo(1.005, 1e-6)
    expect(est.stamina.value).toBeCloseTo(1.012, 1e-6)
    expect(est.armor).toBeNil()
  end)

  it("skips pairs that are too close together and values outside the sane band", function()
    local store = {}
    G.Observe(store, piece(300, 100, 160, 2000))
    G.Observe(store, piece(302, 200, 160, 2000))
    expect(G.Estimate(store).primary).toBeNil()
    G.Observe(store, piece(310, 900, 168, 2240))
    local est = G.Estimate(store, { 1.0, 1.03 })
    expect(est.primary).toBeNil()
    expect(est.secondary.samples).toBe(2)
  end)

  it("keeps seeds until enough pairs exist, then goes live", function()
    local store = {}
    G.Observe(store, piece(300, 100, 160, 2000))
    G.Observe(store, piece(310, 110, 168, 2240))
    local out, source = G.Resolve(store, seeds, 3)
    expect(out.primary).toBe(1.0094)
    expect(source.primary).toBe("seed")
    G.Observe(store, piece(320, 121, 176.4, 2508.8))
    out, source = G.Resolve(store, seeds, 3)
    expect(source.primary).toBe("live")
    expect(out.primary).toBeCloseTo(1.01, 1e-3)
    expect(source.dps).toBe("seed")
    expect(out.dps).toBe(1.0094)
  end)

  it("survives an empty store", function()
    local out, source = G.Resolve(nil, seeds, 3)
    expect(out.secondary).toBe(1.0049)
    expect(source.secondary).toBe("seed")
    expect(G.Estimate(nil)).toEqual({})
  end)
end)
