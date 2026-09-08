local ns = SiftTest.ns
local W = ns.Weights

describe("Weights.FromSpec", function()
  it("gives the primary stat weight 1 and decays secondaries by priority", function()
    local spec = ns.Data.specs[72]
    local w = W.FromSpec(spec)
    expect(w.STRENGTH).toBe(1.0)
    for i, key in ipairs(spec.priority) do expect(w[key]).toBe(W.SECONDARY_DECAY[i]) end
    expect(W.SECONDARY_DECAY[1]).toBeGreaterThan(W.SECONDARY_DECAY[4])
    expect(W.SECONDARY_DECAY[4]).toBeGreaterThan(0.4)
    expect(w.AGILITY).toBeNil()
  end)

  it("values stamina and avoidance more for tanks", function()
    local dps = W.FromSpec(ns.Data.specs[72])
    local tank = W.FromSpec(ns.Data.specs[73])
    expect(tank.STAMINA).toBeGreaterThan(dps.STAMINA)
    expect(tank.AVOIDANCE).toBeGreaterThan(dps.AVOIDANCE)
  end)

  it("gives damage specs no stamina weight at all", function()
    expect(W.FromSpec(ns.Data.specs[72]).STAMINA).toBe(0)
    expect(W.FromSpec(ns.Data.specs[73]).STAMINA).toBeGreaterThan(0)
  end)

  it("assumes a wider weight error for shipped priorities than imported weights", function()
    expect(W.Band("shipped")).toBeGreaterThan(W.Band("imported"))
    expect(W.Band("bogus")).toBe(W.Band("shipped"))
  end)

  it("gives casters no weapon DPS weight and melee a large one", function()
    expect(W.FromSpec(ns.Data.specs[63]).DPS).toBe(0)
    expect(W.FromSpec(ns.Data.specs[72]).DPS).toBeGreaterThan(1)
  end)

  it("knows Devourer is an intellect spec", function()
    expect(ns.Data.specs[1480].primary).toBe("INTELLECT")
    expect(W.FromSpec(ns.Data.specs[1480]).DPS).toBe(0)
  end)

  it("covers every shipped spec without error", function()
    for id, spec in pairs(ns.Data.specs) do
      local w = W.FromSpec(spec)
      expect(w[spec.primary]).toBe(1.0)
      expect(#spec.priority).toBe(4)
    end
  end)
end)

describe("Weights.Resolve", function()
  it("prefers imported weights for the spec", function()
    local imported = { [72] = { weights = { STRENGTH = 2, CRIT = 1 } } }
    local w, source = W.Resolve(ns.Data.specs[72], imported)
    expect(source).toBe("imported")
    expect(w.STRENGTH).toBe(2)
  end)

  it("falls back to shipped when the import is for another spec or empty", function()
    local _, s1 = W.Resolve(ns.Data.specs[72], { [71] = { weights = { STRENGTH = 1 } } })
    expect(s1).toBe("shipped")
    local _, s2 = W.Resolve(ns.Data.specs[72], { [72] = { weights = {} } })
    expect(s2).toBe("shipped")
    local _, s3 = W.Resolve(ns.Data.specs[72], nil)
    expect(s3).toBe("shipped")
  end)
end)

describe("Weights.Resolve with SimulationCraft data", function()
  local saved = ns.WeightsData
  local function withData(data, fn)
    ns.WeightsData = data
    local ok, err = pcall(fn)
    ns.WeightsData = saved
    if not ok then error(err, 2) end
  end

  it("prefers imported, then SimC, then shipped", function()
    withData({ specs = { [72] = { weights = { STRENGTH = 1, HASTE = 0.97, CRIT = 0.72 }, profile = "MID2_Warrior_Fury" } } }, function()
      local w, source = W.Resolve(ns.Data.specs[72], nil)
      expect(source).toBe("simc")
      expect(w.HASTE).toBe(0.97)
      local _, s2 = W.Resolve(ns.Data.specs[72], { [72] = { weights = { STRENGTH = 1 } } })
      expect(s2).toBe("imported")
      local _, s3 = W.Resolve(ns.Data.specs[71], nil)
      expect(s3).toBe("shipped")
    end)
  end)

  it("ignores SimC entries that lack the spec's primary stat", function()
    withData({ specs = { [72] = { weights = { AGILITY = 1, HASTE = 0.97 } } } }, function()
      local _, source = W.Resolve(ns.Data.specs[72], nil)
      expect(source).toBe("shipped")
    end)
    withData(nil, function()
      expect(select(2, W.Resolve(ns.Data.specs[72], nil))).toBe("shipped")
    end)
  end)

  it("uses a middle band for SimC weights", function()
    expect(W.Band("simc")).toBeGreaterThan(W.Band("imported"))
    expect(W.Band("simc")).toBeLessThan(W.Band("shipped"))
  end)
end)
