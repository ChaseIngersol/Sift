-- Ranks the Great Vault's options once each has a verdict. Pure Lua: takes
-- plain tables, returns an ordered list and a sentence.
local _, ns = ...

local VaultRank = {}
ns.VaultRank = VaultRank

local CAP = 0.5 -- an empty slot counts as +50%, not infinity

local function clamp(p)
  if p == nil then return 0 end
  if p > CAP then return CAP end
  if p < -CAP then return -CAP end
  return p
end

-- What a pick delivers once its own upgrades are done, against the worn
-- piece today: the ceiling when ranks are left, else the value now. nil
-- when the verdict has no comparison for the main spec.
function VaultRank.Gain(v)
  local cmp = v and v.details and v.details.self and v.details.self[1]
  if not cmp or not cmp.eligible or not cmp.now then return nil end
  if cmp.max and cmp.max.pct then return cmp.max.pct end
  return cmp.now.pct
end

-- 5 sure gain (equip, or a hold for upgrades, the catalyst or the set),
-- 4 needs a sim, 3 stand-in until your own piece is upgraded, 2 other
-- spec, 1 send to an alt, 0 dead end, -1 not gear.
function VaultRank.Tier(v)
  if not v then return -1 end
  local K = ns.Engine.KIND
  if v.kind == K.EQUIP then return 5 end
  if v.kind == K.HOLD then
    if v.sub == "sim" then return 4 end
    if v.sub == "instead" then return 3 end
    if v.sub == "offspec" then return 2 end
    return 5
  end
  if v.kind == K.SEND then return 1 end
  return 0
end

local function itemID(o)
  return o.id or (o.item and o.item.id) or o.name or o.order
end

-- options: { { name, item, verdict, source }, ... }. Returns a new list,
-- best first; each option gets tier, gain and place. Copies of one item
-- at different levels stay together, ranked by the best of them, then by
-- level: a projection from a lower level is the same item with more
-- growth guessed, not a different piece.
function VaultRank.Rank(options)
  local out, groups = {}, {}
  for i, o in ipairs(options or {}) do
    o.tier = VaultRank.Tier(o.verdict)
    o.gain = clamp(VaultRank.Gain(o.verdict))
    o.order = i
    o.ilvl = (o.item and o.item.ilvl) or 0
    local key = tostring(o.tier) .. ":" .. tostring(itemID(o))
    o.group = key
    local g = groups[key]
    if not g then
      g = { gain = o.gain, ilvl = o.ilvl, order = i }
      groups[key] = g
    else
      if o.gain > g.gain then g.gain = o.gain end
      if o.ilvl > g.ilvl then g.ilvl = o.ilvl end
    end
    out[#out + 1] = o
  end
  table.sort(out, function(a, b)
    if a.tier ~= b.tier then return a.tier > b.tier end
    if a.group ~= b.group then
      local ga, gb = groups[a.group], groups[b.group]
      if ga.gain ~= gb.gain then return ga.gain > gb.gain end
      if ga.ilvl ~= gb.ilvl then return ga.ilvl > gb.ilvl end
      return ga.order < gb.order
    end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.order < b.order
  end)
  for i, o in ipairs(out) do o.place = i end
  return out
end

-- Identical offers (same link, same words) as one row with a count, so
-- three raid slots holding the same trinket read as one line.
function VaultRank.Collapse(ranked)
  local rows = {}
  for _, o in ipairs(ranked or {}) do
    local last = rows[#rows]
    local same = last and last.option.link ~= nil and last.option.link == o.link
      and VaultRank.Verb(last.option) == VaultRank.Verb(o) and (last.option.source == o.source)
    if same then
      last.count = last.count + 1
    else
      rows[#rows + 1] = { option = o, count = 1 }
    end
  end
  return rows
end

-- "Raid Normal" or "Raid Normal x3".
function VaultRank.SourceText(row)
  local src = row.option.source or "vault"
  if (row.count or 1) > 1 then return string.format("%s x%d", src, row.count) end
  return src
end

-- The reason without its leading verb sentence ("Equip. ", "Hold. "), so
-- it can follow "Take X:". Longer openers ("Catalyze now, then ...") stay.
function VaultRank.Short(v)
  local text = v and v.reason or ""
  local first, rest = text:match("^([^%.]+)%.%s+(.+)$")
  if first and #first <= 12 and rest then return rest end
  return text
end

local function ordinal(n)
  local suffix = "th"
  local last, tens = n % 10, n % 100
  if tens < 11 or tens > 13 then
    if last == 1 then suffix = "st" elseif last == 2 then suffix = "nd" elseif last == 3 then suffix = "rd" end
  end
  return tostring(n) .. suffix
end

-- The word in front of each option. Vault words, not verdict words: you
-- take one, the rest are good, need a sim, or are a pass.
function VaultRank.Verb(o)
  if not o.verdict then return "Not gear" end
  if o.place == 1 and o.tier == 5 then return "Take" end
  if o.tier == 5 then return "Good" end
  if o.tier == 4 then return "Sim it" end
  if o.tier == 3 then return "Stand-in" end
  if o.tier == 2 then return "Offspec" end
  if o.tier == 1 then return "Send" end
  return "Pass"
end

-- Which verdict color the verb takes.
function VaultRank.Kind(o)
  if not o.verdict then return "DISPOSE" end
  if o.place == 1 and o.tier == 5 then return "EQUIP" end
  if o.tier >= 2 then return "HOLD" end
  if o.tier == 1 then return "SEND" end
  return "DISPOSE"
end

-- The reason for a vault line: the verdict's words without the verb, plus
-- what the piece reaches at max rank when that is the number the ranking
-- used and it is not already in the text.
function VaultRank.Line(o)
  local v = o.verdict
  if not v then return "Not gear." end
  local text = VaultRank.Short(v):gsub("%s*Vendor or disenchant%.$", "")
  local cmp = v.details and v.details.self and v.details.self[1]
  if o.tier == 5 and cmp then
    local now, u, m = cmp.now, cmp.upgrade, cmp.max
    -- A hold's words say what it beats after upgrades; add where it
    -- stands today, since a close call now can be a large gain.
    if v.kind == ns.Engine.KIND.HOLD and now and now.pct and now.pct ~= math.huge then
      text = text .. string.format(" Now %+.1f%%%s.", now.pct * 100, now.close and ", too close to call" or "")
    end
    if m and m.pct and m.rank and m.ilvl and not (u and u.ilvl == m.ilvl) then
      text = text .. string.format(" Reaches %+.1f%% at %d/%d (%d).", m.pct * 100, m.rank, m.rank, m.ilvl)
    end
  end
  return text
end

-- One line for an item tooltip while the vault is open.
function VaultRank.PlaceText(o, total)
  if o.place == 1 and o.tier == 5 then return "Great Vault: take this one." end
  if o.tier == 5 then return string.format("Great Vault: %s of %d, a sure gain but a smaller one.", ordinal(o.place), total) end
  return string.format("Great Vault: %s of %d.", ordinal(o.place), total)
end

local function named(o)
  local name = o.name or "?"
  if o.source then return string.format("%s (%s)", name, o.source) end
  return name
end

-- One sentence for the vault window and chat.
function VaultRank.Headline(ranked)
  local best = ranked and ranked[1]
  if not best then return "Nothing to pick yet." end
  if best.tier == 5 then
    local line = string.format("Take %s: %s", named(best), VaultRank.Short(best.verdict))
    local sims, seen = {}, {}
    for _, o in ipairs(ranked) do
      local name = o.name or "?"
      if o.tier == 4 and not seen[name] then
        seen[name] = true
        sims[#sims + 1] = name
      end
    end
    if #sims > 0 then
      line = line .. string.format(" %s would need a sim to compete.", table.concat(sims, " and "))
    end
    return line
  elseif best.tier == 4 then
    return string.format("Nothing here is a sure upgrade. %s could be; sim it before you pick.", named(best))
  elseif best.tier == 3 then
    return string.format("Nothing here owns a slot for long. %s is ahead today, but your own piece passes it once upgraded.", named(best))
  elseif best.tier == 2 then
    return string.format("Nothing for your main spec. %s is the pick for your other spec.", named(best))
  elseif best.tier == 1 then
    local t = best.verdict.target
    local who = t and t.char and t.char.name or "an alt"
    return string.format("Nothing here helps you. %s is worth sending to %s.", named(best), who)
  end
  return "Nothing here beats what you have or hold. Pick whatever vendors or disenchants best."
end
