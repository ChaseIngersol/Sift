local ns = SiftTest.ns
local R = ns.Roll

local function verdict(kind, sub, reason, extra)
  local v = { kind = kind, sub = sub, reason = reason or "", notes = {}, flags = {} }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end

describe("Roll advice", function()
  it("says Need in equip color for an upgrade today", function()
    expect(R.Advice(verdict("EQUIP"))).toEqual({ word = "Need", kind = "EQUIP" })
  end)

  it("says Need in hold color for value that comes later", function()
    for _, sub in ipairs({ "upgrade", "catalyst", "set", "level" }) do
      expect(R.Advice(verdict("HOLD", sub))).toEqual({ word = "Need", kind = "HOLD" })
    end
    expect(R.Advice(verdict("HOLD"))).toEqual({ word = "Need", kind = "HOLD" })
  end)

  it("names the offspec", function()
    expect(R.Advice(verdict("HOLD", "offspec"))).toEqual({ word = "Need, offspec", kind = "HOLD" })
  end)

  it("says Sim it for a close call", function()
    expect(R.Advice(verdict("HOLD", "sim"))).toEqual({ word = "Sim it", kind = "HOLD" })
  end)

  it("says Greed when the worn piece should be upgraded instead", function()
    expect(R.Advice(verdict("HOLD", "instead"))).toEqual({ word = "Greed", kind = "HOLD" })
  end)

  it("says Greed for an alt", function()
    expect(R.Advice(verdict("SEND"))).toEqual({ word = "Greed", kind = "SEND" })
  end)

  it("says Pass for a dead end", function()
    expect(R.Advice(verdict("DISPOSE"))).toEqual({ word = "Pass", kind = "DISPOSE" })
  end)

  it("has nothing to say without a verdict", function()
    expect(R.Advice(nil)).toBe(nil)
  end)
end)

describe("Roll line", function()
  it("drops the verdict word the roll word already says", function()
    expect(R.Line(verdict("EQUIP", nil, "Equip. +3.2% vs Worn Bracers for Arms."))).toBe("+3.2% vs Worn Bracers for Arms.")
    expect(R.Line(verdict("HOLD", "upgrade", "Hold. Beats Worn Bracers after 2 upgrades."))).toBe("Beats Worn Bracers after 2 upgrades.")
  end)

  it("keeps the alt's name on a send", function()
    expect(R.Line(verdict("SEND", nil, "Send to Bob. Retribution wants it (+8.0%)."))).toBe("Send to Bob. Retribution wants it (+8.0%).")
  end)

  it("drops the vendor line, since the item is not in the bags yet", function()
    expect(R.Line(verdict("DISPOSE", nil, "Dispose. Below Worn Boots even fully upgraded. Vendor or disenchant."))).toBe("Below Worn Boots even fully upgraded.")
  end)

  it("is empty without a verdict", function()
    expect(R.Line(nil)).toBe("")
  end)
end)

describe("Roll advice for healers", function()
  it("says Your call where a sim would have settled it", function()
    expect(R.Advice(verdict("HOLD", "sim", "", { flags = { noSim = true } }))).toEqual({ word = "Your call", kind = "HOLD" })
    expect(R.Advice(verdict("HOLD", "sim"))).toEqual({ word = "Sim it", kind = "HOLD" })
  end)
end)
