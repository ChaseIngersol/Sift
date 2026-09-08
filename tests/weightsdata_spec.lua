-- Shape checks on the generated Core/WeightsData.lua. Loaded into its own
-- namespace so the engine specs stay independent of generated numbers.
local ns = SiftTest.ns
local root = SiftTest.root

describe("WeightsData", function()
  local scratch = {}
  local chunk = loadfile(root .. "/Core/WeightsData.lua")
  it("loads", function()
    expect(chunk).toBeTruthy()
    chunk("Sift", scratch)
    expect(type(scratch.WeightsData)).toBe("table")
    expect(type(scratch.WeightsData.specs)).toBe("table")
  end)

  it("has a sane entry for every spec it covers", function()
    local n = 0
    for id, entry in pairs(scratch.WeightsData.specs or {}) do
      n = n + 1
      local spec = ns.Data.specs[id]
      expect(spec).toBeTruthy()
      expect(entry.weights[spec.primary]).toBe(1)
      for _, key in ipairs(ns.Stats.SECONDARY) do
        expect(entry.weights[key]).toBeGreaterThan(0)
        expect(entry.weights[key]).toBeLessThan(2)
      end
      expect(type(entry.profile)).toBe("string")
      if spec.primary ~= "INTELLECT" and spec.model ~= ns.Data.MODEL.RANGED then
        expect(entry.weights.DPS).toBeGreaterThan(0)
      end
    end
    if n > 0 then
      expect(type(scratch.WeightsData.generated)).toBe("string")
      expect(type(scratch.WeightsData.commit)).toBe("string")
    end
  end)
end)
