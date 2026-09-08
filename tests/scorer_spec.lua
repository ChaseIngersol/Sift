local ns = SiftTest.ns
local S = ns.Scorer

describe("Scorer.Value", function()
  local w = { STRENGTH = 1, CRIT = 0.5, HASTE = 0.5, STAMINA = 0 }

  it("sums weighted stats", function()
    local v, scorable = S.Value({ stats = { STRENGTH = 100, CRIT = 50 } }, w, "STRENGTH")
    expect(v).toBe(125)
    expect(scorable).toBe(true)
  end)

  it("folds an adaptive primary into the spec primary when allowed", function()
    local item = { stats = { CRIT = 10 }, flex = { value = 100, STRENGTH = true, AGILITY = true } }
    local v = S.Value(item, w, "STRENGTH")
    expect(v).toBe(105)
  end)

  it("drops an adaptive primary the spec cannot use", function()
    local item = { stats = { CRIT = 10 }, flex = { value = 100, AGILITY = true, INTELLECT = true } }
    local v = S.Value(item, w, "STRENGTH")
    expect(v).toBe(5)
  end)

  it("reports not scorable when no weighted stat exists", function()
    local v, scorable = S.Value({ stats = { STAMINA = 500 } }, w, "STRENGTH")
    expect(v).toBe(0)
    expect(scorable).toBe(false)
  end)

  it("scales to a hypothetical item level with a uniform factor", function()
    local item = { stats = { STRENGTH = 100 }, ilvl = 300 }
    local base = S.Value(item, w, "STRENGTH")
    local up = S.Value(item, w, "STRENGTH", { atIlvl = 310, growth = 1.01 })
    expect(up).toBeCloseTo(base * (1.01 ^ 10), 1e-6)
    local same = S.Value(item, w, "STRENGTH", { atIlvl = 300, growth = 1.01 })
    expect(same).toBe(base)
  end)

  it("scales each stat by its own class growth", function()
    local item = { stats = { STRENGTH = 100, CRIT = 100, STAMINA = 100 }, ilvl = 300 }
    local weights = { STRENGTH = 1, CRIT = 1, STAMINA = 1 }
    local growth = { primary = 1.01, secondary = 1.005, stamina = 1.012 }
    local c = S.Contributions(item, weights, "STRENGTH", { atIlvl = 310, growth = growth })
    expect(c.STRENGTH).toBeCloseTo(100 * 1.01 ^ 10, 1e-6)
    expect(c.CRIT).toBeCloseTo(100 * 1.005 ^ 10, 1e-6)
    expect(c.STAMINA).toBeCloseTo(100 * 1.012 ^ 10, 1e-6)
    local down = S.Contributions(item, weights, "STRENGTH", { atIlvl = 290, growth = growth })
    expect(down.STRENGTH).toBeCloseTo(100 / 1.01 ^ 10, 1e-6)
  end)

  it("leaves a stat class with no growth factor unscaled", function()
    local item = { stats = { STRENGTH = 100, DPS = 50 }, ilvl = 300 }
    local c = S.Contributions(item, { STRENGTH = 1, DPS = 1 }, "STRENGTH", { atIlvl = 310, growth = { primary = 1.01 } })
    expect(c.DPS).toBe(50)
  end)

  it("adds gems without scaling them", function()
    local item = { stats = { STRENGTH = 100, CRIT = 100 }, ilvl = 300, gems = { CRIT = 16, HASTE = 7 } }
    local c = S.Contributions(item, w, "STRENGTH", { atIlvl = 310, growth = { primary = 1.01, secondary = 1.005 } })
    expect(c.CRIT).toBeCloseTo(100 * 1.005 ^ 10 * 0.5 + 16 * 0.5, 1e-6)
    expect(c.HASTE).toBeCloseTo(7 * 0.5, 1e-6)
    local v, scorable = S.Value({ stats = {}, gems = { CRIT = 16 } }, w, "STRENGTH")
    expect(v).toBe(8)
    expect(scorable).toBe(true)
  end)

  it("values an empty socket as the better of the primary and secondary gems", function()
    local weights = { STRENGTH = 1, HASTE = 0.6, MASTERY = 0.52, CRIT = 0.45, VERSATILITY = 0.38 }
    expect(S.SocketValue(weights, { 16, 7 }, "STRENGTH")).toBeCloseTo(16 * 0.6 + 7 * 0.52, 1e-6)
    expect(S.SocketValue(weights, { primary = 32, secondary = { 16, 7 } }, "STRENGTH")).toBe(32)
    local secondaryHeavy = { STRENGTH = 1, HASTE = 1.5, MASTERY = 1.2 }
    expect(S.SocketValue(secondaryHeavy, { primary = 32, secondary = { 16, 7 } }, "STRENGTH")).toBeCloseTo(16 * 1.5 + 7 * 1.2, 1e-6)
    expect(S.SocketValue(weights, nil, "STRENGTH")).toBe(0)
    expect(S.SocketValue({ STRENGTH = 1 }, { 16, 7 }, "AGILITY")).toBe(0)
    local c = S.Contributions({ stats = { STRENGTH = 10 }, sockets = 2 }, weights, "STRENGTH", { socketGem = { primary = 32, secondary = { 16, 7 } } })
    expect(c.SOCKET).toBe(64)
    local none = S.Contributions({ stats = { STRENGTH = 10 }, sockets = 2 }, weights, "STRENGTH", {})
    expect(none.SOCKET).toBeNil()
  end)

  it("folds a primary-stat gem into the spec's primary", function()
    local c = S.Contributions({ stats = { CRIT = 10 }, gems = { PRIMARY = 32 } }, w, "STRENGTH")
    expect(c.STRENGTH).toBe(32)
    local c2 = S.Contributions({ stats = { CRIT = 10 }, gems = { PRIMARY = 32 } }, { CRIT = 1, INTELLECT = 1 }, "INTELLECT")
    expect(c2.INTELLECT).toBe(32)
    local c3 = S.Contributions({ stats = { CRIT = 10 }, gems = { PRIMARY = 32 } }, { CRIT = 1 }, nil)
    expect(c3.STRENGTH).toBeNil()
    expect(c3.CRIT).toBe(10)
  end)
end)

describe("Scorer.Margin", function()
  it("is positive when a primary stat gap decides it", function()
    local cand = { STRENGTH = 1100, CRIT = 200, HASTE = 100 }
    local inc = { STRENGTH = 1000, CRIT = 100, HASTE = 200 }
    local margin, spread = S.Margin(cand, inc, "STRENGTH", 0.3)
    expect(spread).toBe(200)
    expect(margin).toBeCloseTo(100 - 60, 1e-9)
  end)

  it("is negative when only secondaries differ under a wide band", function()
    local cand = { STRENGTH = 1000, CRIT = 120, HASTE = 0 }
    local inc = { STRENGTH = 1000, CRIT = 0, HASTE = 100 }
    local margin = S.Margin(cand, inc, "STRENGTH", 0.3)
    expect(margin).toBeLessThan(0)
    expect(S.Margin(cand, inc, "STRENGTH", 0.05)).toBeGreaterThan(0)
  end)

  it("handles missing tables and a zero band", function()
    expect(S.Margin(nil, nil, "STRENGTH", 0.3)).toBe(0)
    expect(S.Margin({ CRIT = 10 }, {}, "STRENGTH", 0)).toBe(10)
  end)
end)

describe("Scorer.Percent and Tier", function()
  it("computes relative change", function()
    expect(S.Percent(110, 100)).toBeCloseTo(0.10)
    expect(S.Percent(90, 100)).toBeCloseTo(-0.10)
    expect(S.Percent(90, 0)).toBeNil()
    expect(S.Percent(nil, 100)).toBeNil()
  end)

  it("bands into tiers around the threshold", function()
    expect(S.Tier(0.08, 0.01)).toBe("much_better")
    expect(S.Tier(0.02, 0.01)).toBe("better")
    expect(S.Tier(0.005, 0.01)).toBe("equal")
    expect(S.Tier(-0.005, 0.01)).toBe("equal")
    expect(S.Tier(-0.02, 0.01)).toBe("worse")
    expect(S.Tier(nil)).toBeNil()
  end)
end)
