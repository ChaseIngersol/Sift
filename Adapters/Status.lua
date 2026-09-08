-- What Sift knows right now, as plain lines. /sift status prints them and
-- the feedback report carries them.
local ADDON, ns = ...

local Status = {}
ns.Status = Status

function Status.Lines()
  local out = {}
  local function say(s) out[#out + 1] = s end
  local me = ns.Character.Self()
  local spec = me.specs and me.specs[1]
  local slotsRead = 0
  for _ in pairs(me.slots) do slotsRead = slotsRead + 1 end
  say(string.format("%s, %s, %d equipped slots read, %d tier pieces", me.name or "?", spec and spec.name or "?", slotsRead, me.tierCount or 0))
  local alts = ns.Character.Alts()
  local holds = 0
  for _ in pairs(ns.db.holds) do holds = holds + 1 end
  if #alts == 0 then
    say(string.format("no alts on file yet (log into a character to add it), %d holds on file", holds))
  else
    local names = {}
    for i, a in ipairs(alts) do
      if i > 8 then names[#names + 1] = string.format("and %d more", #alts - 8) break end
      local aspec = a.specs and a.specs[1]
      names[#names + 1] = string.format("%s (%s %d)", a.name or a.key, aspec and aspec.name or "?", ns.Character.AverageIlvl(a))
    end
    say(string.format("%d alt%s on file: %s. Logging into a character adds it. %d holds on file", #alts, #alts == 1 and "" or "s", table.concat(names, ", "), holds))
  end
  say((ns.Character.DescribeWeights()))
  local res = ns.Resources.Current()
  local parts = {}
  for _, t in ipairs(ns.Season.trackOrder) do parts[#parts + 1] = string.format("%s %d", t, res.crests[t] or 0) end
  say("crests: " .. table.concat(parts, ", ") .. string.format(", catalyst charges %d", res.catalystCharges or 0))
  if #res.missing > 0 then say("currency ids not found for: " .. table.concat(res.missing, ", ") .. " (" .. ns.Resources.Describe() .. ")") end
  for _, key in ipairs({ "Adventurer", "Veteran", "Champion", "Hero", "Myth", "catalyst" }) do
    local c = ns.Resources.Candidates(key)
    if #c > 1 then
      local cparts = {}
      for _, x in ipairs(c) do
        cparts[#cparts + 1] = string.format("%s%d: have %d, earned %s total, %s this week, cap %s, warband %s",
          x.inUse and "using " or "", x.id, x.quantity, tostring(x.totalEarned), tostring(x.thisWeek), tostring(x.max), tostring(x.accountWide))
      end
      say(string.format("%s: %d currencies share the name. %s. /sift currency %s <id> overrides.", key, #c, table.concat(cparts, " | "), key))
    end
  end
  say(ns.SpecScan.Describe())
  say(ns.Calibrate.Describe())
  say(me.parked and "this character is parked" or "this character can receive sends")
  return out
end
