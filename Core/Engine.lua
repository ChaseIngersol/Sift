-- The verdict engine. Pure Lua: takes plain tables, returns a verdict.
-- Nothing in this file may reference a WoW global.
local _, ns = ...

local Engine = {}
ns.Engine = Engine

Engine.KIND = { EQUIP = "EQUIP", HOLD = "HOLD", SEND = "SEND", DISPOSE = "DISPOSE" }
local KIND = Engine.KIND

local DEFAULT_THRESHOLD = 0.01
local MAX_SEND_TARGETS = 3

local function pct(cand, inc)
  return ns.Scorer.Percent(cand, inc)
end

local function fmtPct(p)
  if p == nil then return "" end
  return string.format("%+.1f%%", p * 100)
end

local function plural(n, word)
  if n == 1 then return "1 " .. word end
  return string.format("%d %ss", n, word)
end

local function addInto(target, extra)
  for k, v in pairs(extra or {}) do target[k] = (target[k] or 0) + v end
  return target
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function sum(t)
  local total = 0
  for _, v in pairs(t or {}) do total = total + v end
  return total
end

local competeHeld

-- Compare a candidate against one character's equipped gear for one spec.
-- opts = { upgrades = bool, held = list } (held: section below).
local function compareForSpec(item, char, spec, res, prefs, season, opts)
  opts = opts or {}
  local withUpgrades = opts.upgrades
  local threshold = prefs.threshold or DEFAULT_THRESHOLD
  local ok, why = ns.Eligibility.Check(item, char, spec)
  if not ok then
    return { eligible = false, reason = why, spec = spec }
  end

  local candidates = ns.Slots.Candidates(item, spec)
  if #candidates == 0 then
    return { eligible = false, reason = "slot", spec = spec }
  end

  local weights, source = ns.Weights.Resolve(spec, char.importedWeights)
  local offWeights = ns.Weights.ForOffhand(weights)
  local band = ns.Weights.Band(source)
  local growth = season.statGrowth or season.statGrowthPerLevel
  -- hand: "off" scores weapon dps at the off-hand value.
  local function contribsOf(eq, atIlvl, hand)
    local c, total, scorable = ns.Scorer.Contributions(eq, hand == "off" and offWeights or weights, spec.primary,
      { atIlvl = atIlvl, growth = growth, socketGem = season.socketGem })
    if not scorable then return nil end
    return c, total
  end
  local function valueOf(eq, atIlvl)
    local _, total = contribsOf(eq, atIlvl)
    return total
  end

  local inc = ns.Slots.Incumbent(item, char, spec, function(eq) return valueOf(eq) or 0 end)
  local r = { eligible = true, spec = spec, source = source, band = band, incumbent = inc, basis = "stats" }

  if inc.empty then
    r.emptySlot = true
    r.now = { pct = math.huge, close = false }
    return r
  end

  local candContribs, candNow, incContribs, incNow
  local S = ns.Slots.ID

  -- A one-hander for a dual wielder can go in either hand, and the old main
  -- hand can move to the off hand. Score the best arrangement of the pair
  -- against the current pair.
  if spec.model == ns.Data.MODEL.DUAL_WIELD and item.equipLoc == "INVTYPE_WEAPON" and not inc.combined
    and char.slots[S.MAINHAND] and char.slots[S.OFFHAND] then
    local mh, oh = char.slots[S.MAINHAND], char.slots[S.OFFHAND]
    local cMain = contribsOf(mh, nil, "main")
    local cOff = contribsOf(oh, nil, "off")
    if cMain and cOff then
      local current = addInto(copy(cMain), cOff)
      local best
      for _, a in ipairs({
        { main = item, off = oh, displaced = mh, slot = S.MAINHAND, hand = "main" },
        { main = mh, off = item, displaced = oh, slot = S.OFFHAND, hand = "off" },
        { main = item, off = mh, displaced = oh, slot = S.OFFHAND, hand = "main", swap = true },
      }) do
        local m = contribsOf(a.main, nil, "main")
        local o = contribsOf(a.off, nil, "off")
        if m and o then
          local pair = addInto(copy(m), o)
          local total = sum(pair)
          if not best or total > best.total then
            best = { total = total, pair = pair, partner = a.hand == "main" and o or m, arrangement = a }
          end
        end
      end
      if best then
        candContribs, candNow = best.pair, best.total
        incContribs, incNow = current, sum(current)
        r.hand, r.swap, r.partner = best.arrangement.hand, best.arrangement.swap or false, best.partner
        local d = best.arrangement.displaced
        r.incumbent = { item = d, value = valueOf(d) or 0, ilvl = d.ilvl or 0, slot = best.arrangement.slot, combined = false, isTier = false }
        inc = r.incumbent
      end
    end
  end

  if not candContribs then
    candContribs, candNow = contribsOf(item)
    incContribs, incNow = contribsOf(inc.item)
    if incContribs and inc.combined and inc.secondItem then
      local c2, t2 = contribsOf(inc.secondItem, nil, "off")
      if c2 then addInto(incContribs, c2); incNow = incNow + t2 end
    end
  end

  if not candContribs or not incContribs or not incNow or incNow <= 0 then
    -- Fall back to item level when either side has no scorable stats.
    r.basis = "ilvl"
    candNow = item.ilvl or 0
    incNow = inc.ilvl or 0
    if inc.combined and inc.secondItem then
      -- A two-hander replaces both weapons; compare against the better one.
      incNow = math.max(incNow, inc.secondItem.ilvl or 0)
    end
    r.now = { cand = candNow, inc = incNow, pct = pct(candNow, incNow), close = false }
  else
    local margin, spread = ns.Scorer.Margin(candContribs, incContribs, spec.primary, band)
    r.now = { cand = candNow, inc = incNow, pct = pct(candNow, incNow), margin = margin, spread = spread, close = margin < 0 }
    r.contribs = { cand = candContribs, inc = incContribs }
  end

  local candCeilIlvl = ns.Tracks.Ceiling(season, item)
  local incCeilIlvl = ns.Tracks.Ceiling(season, inc.item)
  r.ceiling = { candIlvl = candCeilIlvl, incIlvl = incCeilIlvl }

  -- Which piece owns the slot in the long run: each at its own ceiling.
  -- r.longTerm is "cand", "inc" or "close". When the incumbent wins and the
  -- candidate is ahead today, r.instead is the incumbent's first rank that
  -- catches the candidate, costed with the slot watermark.
  if r.basis == "stats" and not inc.combined and not r.hand then
    local cc, cv = contribsOf(item, candCeilIlvl)
    local ic, iv = contribsOf(inc.item, incCeilIlvl)
    if cc and ic then
      local m = ns.Scorer.Margin(cc, ic, spec.primary, band)
      r.ceiling.cand, r.ceiling.inc, r.ceiling.pct, r.ceiling.close = cv, iv, pct(cv, iv), m < 0
      if m < 0 then r.longTerm = "close" elseif cv > iv then r.longTerm = "cand" else r.longTerm = "inc" end
      if item.rank and item.maxRank and item.rank < item.maxRank then
        r.max = { pct = pct(cv, incNow), ilvl = candCeilIlvl, rank = item.maxRank }
      end
      r.ceiling.candContribs = cc
      local ahead = r.now.pct and r.now.pct >= threshold and not r.now.close
      local it = inc.item
      if r.longTerm == "inc" and ahead and it.track and it.rank and it.maxRank and it.rank < it.maxRank then
        for k = 1, it.maxRank - it.rank do
          local il = ns.Tracks.IlvlAt(season, it, it.rank + k)
          if not il then break end
          local c2, v2 = contribsOf(it, il)
          if c2 and v2 >= candNow then
            local watermark = char.watermarks and char.watermarks[ns.Tracks.WatermarkGroup(it.equipLoc) or ""]
            local crests, free = ns.Tracks.UpgradeCost(season, it, k, watermark)
            local have = (res.crests and res.crests[it.track]) or 0
            r.instead = { ranks = k, rank = it.rank + k, maxRank = it.maxRank, ilvl = il, crests = crests, free = free,
              watermark = watermark, track = it.track, have = have, ready = have >= crests,
              close = ns.Scorer.Margin(c2, candContribs, spec.primary, band) < 0 }
            break
          end
        end
      end
    end
  end

  if opts.held and r.longTerm then
    r.competition = competeHeld(item, char, spec, opts.held, season, r, contribsOf, band)
  end

  local wantsUpgradeSearch = r.now.pct ~= nil and (r.now.pct < threshold or r.now.close)
  if withUpgrades and wantsUpgradeSearch and item.track and item.rank and item.maxRank and item.rank < item.maxRank then
    for k = 1, item.maxRank - item.rank do
      local il = ns.Tracks.IlvlAt(season, item, item.rank + k)
      if not il then break end
      local c, v, close
      if r.basis == "stats" then
        c, v = contribsOf(item, il, r.hand)
        if c and r.partner then
          c = addInto(copy(c), r.partner)
          v = sum(c)
        end
        close = c and (ns.Scorer.Margin(c, incContribs, spec.primary, band) < 0) or false
      else
        v, close = il, false
      end
      local p = pct(v, incNow)
      if p and p >= threshold then
        local watermark = char.watermarks and char.watermarks[ns.Tracks.WatermarkGroup(item.equipLoc) or ""]
        local crests, free = ns.Tracks.UpgradeCost(season, item, k, watermark)
        local have = (res.crests and res.crests[item.track]) or 0
        local u = { ranks = k, ilvl = il, crests = crests, free = free, watermark = watermark, track = item.track, have = have, ready = have >= crests, pct = p, close = close }
        if not close then
          r.upgrade = u
          break
        elseif not r.upgradeClose then
          r.upgradeClose = u
        end
      end
    end
  end

  return r
end

-- Other pieces that could own the same slots: worn pieces beyond the
-- incumbent (the second ring) and items the character is holding for the
-- same slot family. Each is scored at its own ceiling against the candidate
-- at its ceiling, under the weight band. The candidate is outclassed when
-- at least as many of them beat it with confidence as there are slots.
-- held = { { item = facts, sub = holdSub }, ... }. Holds that are dead
-- ends themselves (instead) or for another spec (offspec) cannot own the
-- slot and are skipped, as are trinkets (sim only) and two-handers.
competeHeld = function(item, char, spec, held, season, r, contribsOf, band)
  local family = ns.Tracks.WatermarkGroup(item.equipLoc)
  if not family or item.equipLoc == "INVTYPE_TRINKET" then return nil end
  local slots, combined = ns.Slots.Candidates(item, spec)
  if combined or #slots == 0 then return nil end
  local key = table.concat(slots, ",")
  local cc, cv = r.ceiling.candContribs, r.ceiling.cand
  if not cc or not cv then return nil end
  local out = { slots = #slots, beaten = {}, close = {} }
  local function consider(other, where, sub)
    if not other or other == item or (other.guid and other.guid == item.guid) then return end
    if sub == "offspec" or sub == "instead" then return end
    if ns.Tracks.WatermarkGroup(other.equipLoc) ~= family then return end
    local otherSlots, otherCombined = ns.Slots.Candidates(other, spec)
    if otherCombined or table.concat(otherSlots, ",") ~= key then return end
    if not ns.Eligibility.Check(other, char, spec) then return end
    local ceil = ns.Tracks.Ceiling(season, other)
    local c, v = contribsOf(other, ceil)
    if not c then return end
    local m = ns.Scorer.Margin(c, cc, spec.primary, band)
    local entry = { item = other, where = where, ilvl = ceil, value = v, pct = pct(cv, v) }
    if m < 0 then
      out.close[#out.close + 1] = entry
    elseif v > cv then
      out.beaten[#out.beaten + 1] = entry
    end
  end
  local incItem = r.incumbent and r.incumbent.item
  for _, slot in ipairs(slots) do
    local eq = char.slots and char.slots[slot]
    if eq and eq ~= incItem then consider(eq, "worn") end
  end
  for _, h in ipairs(held) do consider(h.item or h, "held", h.sub) end
  -- Strongest first; the piece the candidate would have to pass to own the
  -- last slot is beaten[slots].
  local function byValue(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.item.name or "") < (b.item.name or "")
  end
  table.sort(out.beaten, byValue)
  table.sort(out.close, byValue)
  out.outclassed = #out.beaten >= out.slots
  if out.outclassed then out.by = out.beaten[out.slots] end
  if not out.outclassed then
    for _, c in ipairs(out.close) do
      if c.where == "held" then out.rival = c; break end
    end
  end
  return out
end

-- A character seen at the level the item asks for. Everything else reads
-- through to the real one. Only used when level is the sole blocker.
local function atLevel(char, level)
  return setmetatable({ level = level }, { __index = char })
end

-- Is the item's level requirement the only thing keeping this character
-- from using it? True when every spec fails the check with "level".
local function levelLocked(item, char)
  if not item.reqLevel or not char.level or item.reqLevel <= char.level then return false end
  local specs = char.specs or {}
  if #specs == 0 then return false end
  for _, spec in ipairs(specs) do
    local ok, why = ns.Eligibility.Check(item, atLevel(char, item.reqLevel), spec)
    if not ok and why ~= "level" then return false end
  end
  return true
end

-- Is the piece on a track at or above the player's catalyst minimum? A
-- track the season does not list, or none at all, passes: a parsing miss
-- must never hide a catalyst. Returns allowed, minimum.
function Engine.CatalystAllowed(item, prefs, season)
  if not item.catalystEligible then return false end
  local min = prefs and prefs.catalystMinTrack
  if not min or min == "" then return true end
  local order = (season and season.trackOrder) or ns.Season.trackOrder or {}
  local minIdx, itemIdx
  for i, t in ipairs(order) do
    if t == min then minIdx = i end
    if t == item.track then itemIdx = i end
  end
  if not minIdx or not itemIdx then return true end
  return itemIdx >= minIdx, min
end

-- What equipping or catalyzing the candidate does to the character's set
-- count. `breaks`: a non-tier piece over a tier piece at a threshold.
-- `completes`: the count reaches a threshold, by wearing a tier piece of
-- the worn set (`wear`) or by catalyzing an eligible piece. `toward`: a
-- tier piece of the worn set that raises the count short of the next
-- threshold, which still needs it.
local function setImpact(item, char, inc, season)
  local out = {}
  if not inc or not inc.slot or not season.tierSlots[inc.slot] then return out end
  local count = char.tierCount or 0
  local incIsTier = inc.item and inc.item.isTier
  if incIsTier and not item.isTier then
    for _, t in ipairs(season.setThresholds) do
      if count == t then out.breaks = t end
    end
  end
  local sameSet = item.isTier and count > 0
    and (char.tierSetID == nil or item.setID == nil or item.setID == char.tierSetID)
  if (sameSet or item.catalystEligible) and not incIsTier then
    for _, t in ipairs(season.setThresholds) do
      if count < t then
        if count + 1 >= t then
          out.completes, out.wear = t, sameSet or nil
        elseif sameSet then
          out.toward = t
        end
        break
      end
    end
  end
  return out
end

-- Measured weights (imported or SimC) earn a percentage; shipped
-- priorities only earn a tier word.
local function measured(cmp)
  return cmp.source == "imported" or cmp.source == "simc"
end

local function tierWord(cmp, threshold)
  if cmp.emptySlot then return "empty slot" end
  local p = cmp.now and cmp.now.pct
  if measured(cmp) and p then return fmtPct(p) end
  local tier = ns.Scorer.Tier(p, threshold)
  return ns.Scorer.TIER_LABEL[tier] or "unknown"
end

-- "+3.2% vs" or "clearly better than", to sit before the incumbent's name.
local function versus(cmp, threshold)
  local p = cmp.now and cmp.now.pct
  if measured(cmp) and p and not cmp.emptySlot then return fmtPct(p) .. " vs" end
  return tierWord(cmp, threshold) .. " than"
end

local function weightsLabel(cmp)
  return ns.Weights.SOURCE_LABEL[cmp.source] or "default"
end

-- The brief: the same facts as the reason, in fixed slots the panel and
-- toast lay out the same way for every verdict. gain is a percentage
-- with measured weights, a tier word otherwise, an item level for
-- trinkets; versus names what it was scored against; when is the
-- condition (after N upgrades, at level 80, at max ranks); note is one
-- short clause of nuance; who is the alt on a send.
-- Which way the comparison went, for the color of the gain: "up" when
-- better with confidence, "down" when worse, "flat" when inside the
-- threshold or the weight band.
local function briefSign(cmp, threshold)
  local p = cmp.now and cmp.now.pct
  if p == nil then return nil end
  if cmp.now.close then return "flat" end
  if p >= threshold then return "up" end
  if p <= -threshold then return "down" end
  return "flat"
end

local function briefVersus(cmp, threshold)
  if cmp.emptySlot then
    return nil, string.format("Your %s is empty", ns.Slots.LABEL[cmp.incumbent and cmp.incumbent.slot or 0] or "slot"), "up"
  end
  local p = cmp.now and cmp.now.pct
  local name = "vs " .. (cmp.incumbent and cmp.incumbent.item and cmp.incumbent.item.name or "equipped item")
  local sign = briefSign(cmp, threshold)
  if measured(cmp) and p then return fmtPct(p), name, sign end
  local word = ns.Scorer.TIER_LABEL[ns.Scorer.Tier(p, threshold)] or "unknown"
  return (word:gsub("^%l", string.upper)), name, sign
end

-- "after 2 upgrades, free" or "after 2 upgrades, 40 Champion crests".
local function briefWhen(u)
  if not u then return nil end
  local cost = u.crests == 0 and "free" or string.format("%d %s crests", u.crests, u.track or "")
  return string.format("after %s, %s", plural(u.ranks, "upgrade"), cost)
end

local function incumbentName(cmp)
  local inc = cmp.incumbent
  if not inc or not inc.item then return "empty " .. (ns.Slots.LABEL[inc and inc.slot or 0] or "slot") end
  return inc.item.name or "equipped item"
end

local function specLabel(spec)
  return spec and spec.name or "?"
end

local function capitalize(s)
  return (s:gsub("^%l", string.upper))
end

-- Why the character cannot use the item at all, in plain words.
local function ineligibleText(item, char, cmp)
  local Data, Stats = ns.Data, ns.Stats
  local why = cmp and cmp.reason
  local spec = cmp and cmp.spec
  local class = Data.classes[char.classID]
  if why == "armor" then
    return string.format("%s, and you wear %s.", capitalize(Data.ARMOR_NAME[item.subclassID] or "another armor type"),
      Data.ARMOR_NAME[class and class.armor] or "something else")
  elseif why == "primary" and spec then
    local fixed = Stats.FixedPrimary(item.stats or {})
    local label = fixed and Stats.LABEL[fixed]
    if not label and item.flex then
      local names = {}
      for k in pairs(item.flex) do if k ~= "value" and Stats.LABEL[k] then names[#names + 1] = Stats.LABEL[k] end end
      table.sort(names)
      label = table.concat(names, " or ")
    end
    return string.format("%s gear, and %s uses %s.", label or "Other-stat", spec.name, Stats.LABEL[spec.primary] or spec.primary)
  elseif why == "weapon" then
    return string.format("%s cannot use %s.", class and class.name or "You", Data.WEAPON_NAME[item.subclassID] or "this weapon type")
  elseif why == "model" and spec then
    return string.format("Not a weapon shape %s uses.", spec.name)
  elseif why == "shield" then
    return "You cannot use that off-hand."
  elseif why == "level" then
    return string.format("Needs level %d.", item.reqLevel or 0)
  elseif why == "slot" then
    return "Not something you can equip."
  end
  return "No use for you."
end

local function slotLabel(cmp)
  return ns.Slots.LABEL[cmp.incumbent and cmp.incumbent.slot or 0] or "slot"
end

-- Build the SEND target list from alts. Close calls are kept aside: a
-- sidegrade is not worth a trip to the bank.
local function sendTargets(item, alts, prefs, season)
  local threshold = prefs.threshold or DEFAULT_THRESHOLD
  local targets, close = {}, {}
  for _, alt in ipairs(alts or {}) do
    if not alt.parked then
      local best, bestClose = nil, nil
      -- An alt below the item's level is scored at that level: the piece
      -- is worth banking for the day they get there.
      local needsLevel = levelLocked(item, alt) and item.reqLevel or nil
      local who = needsLevel and atLevel(alt, needsLevel) or alt
      for _, spec in ipairs(alt.specs or {}) do
        local cmp = compareForSpec(item, who, spec, {}, prefs, season)
        if cmp.eligible and cmp.longTerm ~= "inc" and (cmp.emptySlot or (cmp.now.pct and cmp.now.pct >= threshold)) then
          local t = {
            char = alt, spec = spec, cmp = cmp, needsLevel = needsLevel,
            pct = cmp.emptySlot and math.huge or cmp.now.pct,
            ilvlDelta = (item.ilvl or 0) - ((cmp.incumbent and cmp.incumbent.ilvl) or 0),
          }
          if cmp.now.close then
            if not bestClose or (t.pct or 0) > (bestClose.pct or 0) then bestClose = t end
          elseif not best or (t.pct or 0) > (best.pct or 0) then
            best = t
          end
        end
      end
      if best then targets[#targets + 1] = best elseif bestClose then close[#close + 1] = bestClose end
    end
  end
  -- Alts who can wear it today come before those who must level first.
  local function byGain(a, b)
    if (a.needsLevel ~= nil) ~= (b.needsLevel ~= nil) then return a.needsLevel == nil end
    if a.pct ~= b.pct then return a.pct > b.pct end
    return (a.char.name or "") < (b.char.name or "")
  end
  table.sort(targets, byGain)
  table.sort(close, byGain)
  while #targets > MAX_SEND_TARGETS do table.remove(targets) end
  return targets, close
end

local function describeTarget(t, threshold)
  local who = t.char.name or "an alt"
  if t.cmp.emptySlot then
    return string.format("%s (%s): empty %s", who, specLabel(t.spec), slotLabel(t.cmp))
  end
  local delta = t.ilvlDelta or 0
  local levels = delta ~= 0 and string.format(" (%+d ilvl)", delta) or ""
  local when = t.needsLevel and string.format(", at level %d (now %d)", t.needsLevel, t.char.level or 0) or ""
  return string.format("%s (%s): %s in %s%s%s", who, specLabel(t.spec), tierWord(t.cmp, threshold), slotLabel(t.cmp), levels, when)
end

-- "(20 Champion Mistcrests, you have 30)" with free ranks called out. With
-- measured weights the gain at that rank leads, so two holds can be
-- compared at a glance.
local function costText(u, cmp)
  local text
  if u.crests == 0 then
    text = string.format("free, your slot has reached %d", u.watermark or 0)
  else
    local free = (u.free or 0) > 0 and string.format(", %s free", plural(u.free, "rank")) or ""
    text = string.format("%d %s Mistcrests%s, you have %d", u.crests, u.track, free, u.have)
  end
  if cmp and u.pct and measured(cmp) then text = fmtPct(u.pct) .. ", " .. text end
  return text
end

local function capsText(cmp)
  local c = cmp.ceiling
  if not c or not cmp.incumbent or not cmp.incumbent.item then return nil end
  if c.incIlvl > c.candIlvl then
    return string.format("%s caps higher (%d vs %d).", incumbentName(cmp), c.incIlvl, c.candIlvl)
  elseif c.candIlvl > c.incIlvl then
    return string.format("Caps at %d vs %d.", c.candIlvl, c.incIlvl)
  end
  return nil
end

-- ctx = { item, self, alts, res, prefs, season, held }
-- Healers cannot sim on Raidbots. Where a sim would settle a close call
-- the word for them is "Your call", and no note sends them to one.
local function simWord(v)
  local f = v.flags
  if (f and f.noSim) or v.noSim then return "Your call" end
  return "Sim it"
end

function Engine.Evaluate(ctx)
  local item, me, alts = ctx.item, ctx.self, ctx.alts or {}
  local res, prefs, season = ctx.res or {}, ctx.prefs or {}, ctx.season
  local threshold = prefs.threshold or DEFAULT_THRESHOLD

  -- Too low a level for it, and nothing else in the way: judge it as if
  -- the level were there. Anything worth wearing then is a hold that
  -- wakes on the level; a send or a dispose stands as it is.
  if me and levelLocked(item, me) then
    local future = {}
    for k, val in pairs(ctx) do future[k] = val end
    future.self = atLevel(me, item.reqLevel)
    local v = Engine.Evaluate(future)
    if v.kind == KIND.EQUIP or v.kind == KIND.HOLD then
      local then_ = v.reason:gsub("^%u[%l ]-%. ", "")
      local b = v.brief or {}
      v.brief = { gain = b.gain, versus = b.versus, sign = b.sign, when = string.format("at level %d", item.reqLevel),
        note = string.format("Then %s.", Engine.Headline(v):lower()) }
      v.kind, v.sub, v.ready = KIND.HOLD, "level", false
      v.wake = { type = "level", need = item.reqLevel }
      v.reason = string.format("Needs level %d (you are %d). Then: %s", item.reqLevel, me.level or 0, then_)
      v.instead, v.target = nil, nil
    end
    v.flags.level = item.reqLevel
    return v
  end

  local v = { kind = nil, sub = nil, reason = "", notes = {}, flags = {}, details = {} }
  local role = me and me.specs and me.specs[1] and me.specs[1].role
  if role == "heal" then v.flags.noSim = true end
  if item.hasEffect then v.flags.effect = true end
  if item.cantrip then v.flags.cantrip = true end

  local results = {}
  for i, spec in ipairs(me.specs or {}) do
    results[i] = compareForSpec(item, me, spec, res, prefs, season, { upgrades = true, held = i == 1 and ctx.held or nil })
  end
  v.details.self = results

  local primary = results[1]
  local isTrinket = item.equipLoc == "INVTYPE_TRINKET"
  if primary and primary.eligible then
    local set = setImpact(item, me, primary.incumbent, season)
    local now = primary.now
    local betterNow = primary.emptySlot or (now.pct and now.pct >= threshold)
    local charges = res.catalystCharges or 0
    local incName, spec = incumbentName(primary), specLabel(primary.spec)
    local canCatalyze = Engine.CatalystAllowed(item, prefs, season)
    if item.catalystEligible and not canCatalyze and (set.completes or set.breaks) then
      v.flags.catalystBelowMin = true
      v.notes[#v.notes + 1] = string.format("Not for the catalyst: %s is under your %s minimum%s.",
        item.track or "its track", prefs.catalystMinTrack,
        set.completes and string.format(", though it would complete your %d-piece", set.completes) or "")
    end

    if isTrinket and not primary.emptySlot then
      -- Trinket effects cannot be weighed. Only item level is worth saying.
      local incIlvl = primary.incumbent.ilvl or 0
      local cap = primary.ceiling and primary.ceiling.candIlvl or (item.ilvl or 0)
      if cap < incIlvl then
        primary.trinketBelow = true
      else
        v.kind, v.sub = KIND.HOLD, "sim"
        v.flags.sim = true
        local levels
        if (item.ilvl or 0) >= incIlvl then
          levels = string.format("%d vs %s at %d", item.ilvl or 0, incName, incIlvl)
        else
          levels = string.format("%d vs %s at %d, %d after upgrades", item.ilvl or 0, incName, incIlvl, cap)
        end
        v.reason = string.format("%s. Trinket effects cannot be scored. %s.", simWord(v), levels)
        v.brief = { gain = tostring(item.ilvl or 0), versus = string.format("vs %s at %d", incName, incIlvl),
          when = cap > (item.ilvl or 0) and string.format("%d after upgrades", cap) or nil, note = v.flags.noSim and "Trinket effects are not scored." or "Trinket effects need a sim.", sign = "flat" }
      end
    elseif set.completes and set.wear then
      -- A tier piece of the worn set, into a slot that holds none: wearing
      -- it completes the set. The bonus is not scored, and no stat gap is
      -- worth leaving it in the bag.
      v.kind = KIND.EQUIP
      v.flags.completesSet = set.completes
      v.reason = string.format("Equip. Completes your %d-piece set; %s %s for %s.", set.completes, versus(primary, threshold), incName, spec)
      local g, vs, sg = briefVersus(primary, threshold)
      v.brief = { gain = g, versus = vs, sign = sg, note = string.format("Completes your %d-piece.", set.completes) }
    elseif set.completes and canCatalyze then
      v.kind, v.sub = KIND.HOLD, "catalyst"
      v.ready = charges > 0
      v.wake = (not v.ready) and { type = "catalyst" } or nil
      v.reason = string.format("Catalyze%s. Completes your %d-piece set%s.",
        v.ready and " now" or " when a charge is ready", set.completes,
        (betterNow and not now.close) and ", then equip" or "")
      local g, vs, sg = briefVersus(primary, threshold)
      v.brief = { gain = g, versus = vs, sign = sg, note = string.format("Completes your %d-piece.%s", set.completes, (betterNow and not now.close) and " Then equip." or "") }
    elseif primary.longTerm == "inc" then
      -- The incumbent owns the slot in the long run. Ahead today or not,
      -- the candidate never gets an Equip; at most it fills in until the
      -- incumbent's own upgrade lands.
      local u = primary.instead
      if betterNow and not now.close and u then
        v.kind, v.sub = KIND.HOLD, "instead"
        v.ready = u.ready
        v.wake = (not u.ready) and { type = "crests", track = u.track, need = u.crests } or nil
        v.instead = { name = incName, rank = u.rank, maxRank = u.maxRank, ilvl = u.ilvl }
        v.reason = string.format("Upgrade %s instead: at %d/%d (%d) it passes this and caps at %d (%s). Wear this meanwhile if you like.",
          incName, u.rank, u.maxRank, u.ilvl, primary.ceiling.incIlvl, costText(u))
        local g, vs, sg = briefVersus(primary, threshold)
        v.brief = { gain = g, versus = vs, sign = sg, note = string.format("Upgrade %s to %d/%d (%d) instead. Wear this meanwhile.", incName, u.rank, u.maxRank, u.ilvl) }
        if u.close then v.notes[#v.notes + 1] = v.flags.noSim and "Close call at that rank." or "Close call at that rank; a sim could disagree." end
      end
    elseif primary.competition and primary.competition.outclassed then
      -- Something else in the bags (or the other ring) owns the slot in
      -- the long run. A dead end for this character: the dispose text
      -- below names the piece; alts still get their chance.
      v.flags.outclassed = true
      if betterNow and not now.close then
        v.notes[#v.notes + 1] = string.format("Ahead of %s today (%s), so it can fill in meanwhile.", incName, tierWord(primary, threshold))
      end
    elseif primary.longTerm == "close" and betterNow and not now.close and primary.ceiling.incIlvl > primary.ceiling.candIlvl then
      v.kind, v.sub = KIND.HOLD, "sim"
      v.flags.sim = true
      v.reason = string.format("Better now (%s), but %s at %d against this at %d is too close to call. %s.",
        fmtPct(now.pct), incName, primary.ceiling.incIlvl, primary.ceiling.candIlvl, simWord(v))
      local g, vs = briefVersus(primary, threshold)
      v.brief = { gain = g, versus = vs, sign = "flat", note = string.format("Better now, but %s caps higher (%d vs %d). Too close to call.", incName, primary.ceiling.incIlvl, primary.ceiling.candIlvl) }
    elseif (betterNow and not now.close) or primary.upgrade then
      local u = primary.upgrade
      local gain = u and not (betterNow and not now.close)
      if set.breaks then
        -- Replacing a tier piece at a set threshold. The set bonus is not
        -- scored, and no marginal gain is worth losing it: catalyze the
        -- piece so it keeps the set, or hold it for the off-piece slot.
        local gainText = gain
          and string.format("Beats %s after %s (%s) for %s", incName, plural(u.ranks, "upgrade"), costText(u, primary), spec)
          or string.format("%s %s for %s", versus(primary, threshold), incName, spec)
        local g, vs, sg = briefVersus(primary, threshold)
        if gain then g, sg = measured(primary) and fmtPct(u.pct) or "Better", "up" end
        if canCatalyze then
          v.kind, v.sub = KIND.HOLD, "catalyst"
          v.ready = charges > 0
          v.wake = (not v.ready) and { type = "catalyst" } or nil
          v.reason = string.format("Catalyze%s, then %s. %s; as a tier piece it keeps your %d-piece.",
            v.ready and " now" or " when a charge is ready", gain and "upgrade and equip" or "equip", gainText, set.breaks)
          v.brief = { gain = g, versus = vs, sign = sg, when = gain and briefWhen(u) or nil,
            note = string.format("Then %s. Keeps your %d-piece as a tier piece.", gain and "upgrade and equip" or "equip", set.breaks) }
        else
          v.kind, v.sub = KIND.HOLD, "set"
          v.reason = string.format("Hold. %s, but equipping it breaks your %d-piece. It is your off-piece once another tier piece frees the slot.",
            gainText, set.breaks)
          v.brief = { gain = g, versus = vs, sign = sg, when = gain and briefWhen(u) or nil,
            note = string.format("Breaks your %d-piece. Off-piece once another tier piece frees the slot.", set.breaks) }
        end
        v.flags.breaksSet = set.breaks
      elseif not gain then
        v.kind = KIND.EQUIP
        if primary.emptySlot then
          v.reason = string.format("Equip. Your %s is empty.", slotLabel(primary))
        else
          v.reason = string.format("Equip. %s %s for %s.", versus(primary, threshold), incName, spec)
        end
        local g, vs, sg = briefVersus(primary, threshold)
        v.brief = { gain = g, versus = vs, sign = sg }
      else
        v.kind, v.sub = KIND.HOLD, "upgrade"
        v.ready = u.ready
        v.wake = (not u.ready) and { type = "crests", track = u.track, need = u.crests } or nil
        v.reason = string.format("%s. Beats %s after %s (%s).",
          u.ready and "Upgrade now" or "Hold", incName, plural(u.ranks, "upgrade"), costText(u, primary))
        if now.close then
          v.notes[#v.notes + 1] = string.format(v.flags.noSim and "Too close to call as-is (%s); wearing it now is fine too."
            or "Too close to call as-is (%s), so a sim could say equip now.", fmtPct(now.pct))
        end
        v.brief = { gain = measured(primary) and fmtPct(u.pct) or "Better", versus = "vs " .. incName, sign = "up", when = briefWhen(u),
          note = now.close and (v.flags.noSim and "Too close to call as-is; wearing it now is fine too."
            or "Too close to call as-is; a sim could say equip now.") or nil }
      end
    elseif now.close or primary.upgradeClose then
      v.kind, v.sub = KIND.HOLD, "sim"
      v.flags.sim = true
      if now.close then
        v.reason = string.format("Too close to call. %s vs %s for %s under %s weights. %s.",
          fmtPct(now.pct), incName, spec, weightsLabel(primary), simWord(v))
        v.brief = { gain = fmtPct(now.pct), versus = "vs " .. incName, sign = "flat",
          note = string.format("Inside the margin of error of %s weights.", weightsLabel(primary)) }
      else
        local u = primary.upgradeClose
        v.reason = string.format(v.flags.noSim and "Might beat %s after %s (%s); too close to call. Your call."
          or "Might beat %s after %s (%s), but only a sim can say. Sim it.",
          incName, plural(u.ranks, "upgrade"), costText(u))
        v.brief = { gain = measured(primary) and fmtPct(u.pct) or nil, versus = "vs " .. incName, sign = "flat", when = briefWhen(u),
          note = v.flags.noSim and "Might beat it; too close to call." or "Might beat it, but only a sim can say." }
      end
    end

    if not v.kind and set.toward then
      -- A tier piece of the worn set with a threshold still ahead. Not a
      -- dead end whatever the numbers say: the next threshold needs it.
      local nth = (me.tierCount or 0) + 1
      v.kind, v.sub = KIND.HOLD, "set"
      v.flags.outclassed = nil
      v.flags.towardSet = set.toward
      v.reason = string.format("Hold. Tier piece %d toward your %d-piece; %s %s for %s today.",
        nth, set.toward, versus(primary, threshold), incName, spec)
      local g, vs, sg = briefVersus(primary, threshold)
      v.brief = { gain = g, versus = vs, sign = sg, note = string.format("Tier piece %d toward your %d-piece.", nth, set.toward) }
    end

    local rival = v.kind and primary.competition and primary.competition.rival
    if rival then
      v.notes[#v.notes + 1] = string.format("Also holding %s for this slot; too close to call between them at max ranks.", rival.item.name or "another piece")
    end

    if v.kind and primary.hand and v.kind ~= KIND.DISPOSE then
      if primary.swap then
        v.notes[#v.notes + 1] = "Main hand; your current main hand moves to the off hand."
      elseif primary.hand == "off" then
        v.notes[#v.notes + 1] = "Off hand."
      else
        v.notes[#v.notes + 1] = "Main hand."
      end
    end

    if v.kind and not isTrinket then
      local caps = capsText(primary)
      if caps and (v.kind == KIND.HOLD or caps:find("caps higher", 1, true)) then
        v.notes[#v.notes + 1] = caps
      end
    end
  end

  if not v.kind then
    for i = 2, #results do
      local r = results[i]
      if r.eligible and r.longTerm ~= "inc" and (r.emptySlot or (r.now.pct and r.now.pct >= threshold)) then
        if r.now.close then
          v.notes[#v.notes + 1] = string.format("Might be an upgrade for %s (%s), too close to call.", specLabel(r.spec), fmtPct(r.now.pct))
        else
          v.kind, v.sub = KIND.HOLD, "offspec"
          v.reason = string.format("Hold. %s %s for %s.", versus(r, threshold), incumbentName(r), specLabel(r.spec))
          local g, vs, sg = briefVersus(r, threshold)
          v.brief = { gain = g, versus = vs .. " for " .. specLabel(r.spec), sign = sg }
          break
        end
      end
    end
  end

  local targets, closeTargets = {}, {}
  if item.sendable then
    targets, closeTargets = sendTargets(item, alts, prefs, season)
  end
  v.details.targets = targets
  v.details.closeTargets = closeTargets

  if #targets > 0 then
    local lines = {}
    for i, t in ipairs(targets) do lines[i] = describeTarget(t, threshold) end
    if v.kind and not prefs.altFirst then
      v.notes[#v.notes + 1] = "Also for " .. lines[1] .. "."
    else
      if v.kind then
        v.notes[#v.notes + 1] = v.reason
      end
      if v.flags.outclassed then
        v.notes[#v.notes + 1] = string.format("Outclassed by %s for you.", primary.competition.by.item.name or "another piece")
      end
      v.kind, v.sub = KIND.SEND, nil
      v.target = targets[1]
      v.wake = { type = "bank" }
      v.reason = "Send to " .. lines[1] .. "."
      for i = 2, #lines do v.notes[#v.notes + 1] = "Or " .. lines[i] .. "." end
      local t = targets[1]
      local g, vs, sg = briefVersus(t.cmp, threshold)
      v.brief = { gain = g, versus = vs, sign = sg, who = t.char.name or "an alt",
        when = t.needsLevel and string.format("at level %d", t.needsLevel) or nil,
        note = lines[2] and ("Or " .. lines[2] .. ".") or nil }
    end
  end

  if not v.kind then
    v.kind = KIND.DISPOSE
    local text
    if primary and primary.eligible then
      local name, spec = incumbentName(primary), specLabel(primary.spec)
      if primary.trinketBelow then
        local cap = primary.ceiling and primary.ceiling.candIlvl or item.ilvl or 0
        text = string.format(v.flags.noSim and "Below %s (%d) even fully upgraded (%d); trinket effects are not scored."
          or "Below %s (%d) even fully upgraded (%d), and trinket effects need a sim.",
          name, primary.incumbent.ilvl or 0, cap)
        v.brief = { gain = tostring(item.ilvl or 0), versus = string.format("vs %s at %d", name, primary.incumbent.ilvl or 0),
          when = cap > (item.ilvl or 0) and string.format("%d after upgrades", cap) or nil, note = "Cannot reach it even fully upgraded.", sign = "down" }
      elseif v.flags.outclassed then
        local by = primary.competition.by
        local gap = measured(primary) and fmtPct(by.pct) or "worse"
        text = string.format("Outclassed by %s%s: %s at max ranks (%d vs %d) for %s.",
          by.item.name or "another piece", by.where == "held" and " in your bags" or ", which you wear",
          gap, primary.ceiling.candIlvl, by.ilvl, spec)
        v.brief = { gain = measured(primary) and fmtPct(by.pct) or "Worse",
          versus = string.format("vs %s %s", by.item.name or "another piece", by.where == "held" and "in your bags" or "you wear"),
          when = "at max ranks", sign = "down" }
      else
        local pctMode = measured(primary) and primary.now and primary.now.pct
        if pctMode then
          text = string.format("%s vs %s for %s", fmtPct(primary.now.pct), name, spec)
        else
          local tier = ns.Scorer.Tier(primary.now and primary.now.pct, threshold)
          text = string.format("%s %s for %s", tier == "equal" and "About the same as" or "Worse than", name, spec)
        end
        local m = primary.max
        local saidAhead = m and m.pct and primary.longTerm == "inc" and m.pct >= threshold
        local g, vs, sg = briefVersus(primary, threshold)
        v.brief = { gain = g, versus = vs, sign = sg }
        if m and m.pct then
          if saidAhead then
            text = text .. string.format(" now. Fully upgraded (%d) it would pass %s today, but %s at %d stays ahead.",
              m.ilvl, name, name, primary.ceiling.incIlvl)
            v.brief.note = string.format("Fully upgraded it would pass today, but %s at %d stays ahead.", name, primary.ceiling.incIlvl)
          elseif pctMode then
            text = text .. string.format(" now, still %s at %d/%d (%d).", fmtPct(m.pct), m.rank, m.rank, m.ilvl)
            v.brief.when = string.format("still %s at max", fmtPct(m.pct))
          else
            text = text .. string.format(" now and at %d/%d (%d).", m.rank, m.rank, m.ilvl)
            v.brief.when = "even at max"
          end
        else
          text = text .. "."
        end
        local caps = capsText(primary)
        if caps and caps:find("caps higher", 1, true) and not saidAhead then
          v.notes[#v.notes + 1] = caps
        end
      end
    elseif primary then
      text = ineligibleText(item, me, primary)
      v.brief = { versus = (text:gsub("%.$", "")) }
    else
      text = "No use for you."
      v.brief = { versus = "No use for you" }
    end
    if item.sendable then
      if #alts == 0 then
        text = text .. " No alts on file yet."
      elseif #closeTargets > 0 then
        text = text .. string.format(" Only a close call for %s.", closeTargets[1].char.name or "an alt")
        if v.brief and not v.brief.note then v.brief.note = string.format("Only a close call for %s.", closeTargets[1].char.name or "an alt") end
      else
        text = text .. " No alt wants it."
      end
    end
    v.reason = text .. " Vendor or disenchant."
  end

  if v.flags.effect and not v.flags.sim then v.notes[#v.notes + 1] = "Has an effect that stats cannot score." end
  if v.flags.cantrip then v.notes[#v.notes + 1] = "Cantrip: " .. tostring(item.cantrip) end

  return v
end

-- Short headline for tooltips and chat, e.g. "Equip", "Hold", "Send", "Vendor".
function Engine.Headline(v)
  if v.kind == KIND.EQUIP then return "Equip" end
  if v.kind == KIND.HOLD then
    if v.sub == "catalyst" then return v.ready and "Catalyze" or "Hold for catalyst" end
    if v.sub == "upgrade" then return v.ready and "Upgrade" or "Hold" end
    if v.sub == "sim" then return simWord(v) end
    if v.sub == "instead" then return v.ready and "Upgrade yours" or "Hold" end
    if v.sub == "level" then return "Hold" end
    return "Hold"
  end
  if v.kind == KIND.SEND then return "Send" end
  return "Dispose"
end

-- The brief on one line, for the toast and chat-sized places: gain, the
-- alt on a send, versus, condition. nil when the verdict has no brief.
function Engine.BriefLine(v, colors)
  local b = v and v.brief
  if not b then return nil end
  local parts = {}
  if b.gain then
    local hex = colors and b.sign and colors[b.sign]
    parts[#parts + 1] = hex and string.format("|cff%s%s|r", hex, b.gain) or b.gain
  end
  if b.who then parts[#parts + 1] = "for " .. b.who end
  if b.versus then parts[#parts + 1] = b.versus end
  local line = table.concat(parts, " ")
  if b.when then line = line .. ", " .. b.when end
  return line
end

-- One number for ordering verdicts: the gain the verdict is about. A
-- send is about the alt's gain, a hold about what the piece reaches at
-- max rank, the rest about today. An empty slot is infinite. nil when
-- nothing was scored.
function Engine.Gain(v)
  if not v then return nil end
  if v.kind == KIND.SEND and v.target then return v.target.pct end
  local cmp = v.details and v.details.self and v.details.self[1]
  if not cmp or not cmp.eligible or not cmp.now then return nil end
  if cmp.max and cmp.max.pct then return cmp.max.pct end
  return cmp.now.pct
end

-- Sort rows carrying gain and name in place, best first; rows without a
-- gain go last, ties by name.
function Engine.SortByGain(rows)
  table.sort(rows, function(a, b)
    local ga, gb = a.gain, b.gain
    if ga ~= gb then
      if ga == nil then return false end
      if gb == nil then return true end
      return ga > gb
    end
    return (a.name or "") < (b.name or "")
  end)
  return rows
end

-- The comparison behind a verdict, as short lines for a hover. Returns a
-- list of { label, cand, inc } rows plus a summary line, or nil.
function Engine.Math(v)
  local cmp = v.details and v.details.self and v.details.self[1]
  if not cmp or not cmp.eligible or cmp.emptySlot or not cmp.now then return nil end
  local rows = {}
  if cmp.contribs then
    local keys = {}
    for k in pairs(cmp.contribs.cand) do keys[k] = true end
    for k in pairs(cmp.contribs.inc) do keys[k] = true end
    local order = {}
    for k in pairs(keys) do order[#order + 1] = k end
    table.sort(order, function(a, b)
      local da = math.abs((cmp.contribs.cand[a] or 0) - (cmp.contribs.inc[a] or 0))
      local db = math.abs((cmp.contribs.cand[b] or 0) - (cmp.contribs.inc[b] or 0))
      if da ~= db then return da > db end
      return a < b
    end)
    for _, k in ipairs(order) do
      rows[#rows + 1] = { label = (k == "SOCKET" and "Empty socket") or ns.Stats.LABEL[k] or k, cand = cmp.contribs.cand[k] or 0, inc = cmp.contribs.inc[k] or 0 }
    end
  end
  local summary
  if cmp.basis == "ilvl" then
    summary = string.format("By item level: %d vs %d.", cmp.now.cand or 0, cmp.now.inc or 0)
  else
    local band = math.floor((cmp.band or 0) * 100 + 0.5)
    summary = string.format("Score %.0f vs %.0f (%s), %s weights. %s within %d%% weight error.",
      cmp.now.cand or 0, cmp.now.inc or 0, fmtPct(cmp.now.pct), weightsLabel(cmp),
      cmp.now.close and "Sign flips" or "Sign holds", band)
    local c = cmp.ceiling
    if c and c.cand and (c.candIlvl ~= (cmp.incumbent.ilvl or 0) or c.incIlvl ~= (cmp.incumbent.ilvl or 0)) then
      summary = summary .. string.format(" At max ranks, %d vs %d: %.0f vs %.0f (%s%s).",
        c.candIlvl, c.incIlvl, c.cand, c.inc, fmtPct(c.pct), c.close and ", close" or "")
    end
    local comp = cmp.competition
    if comp and comp.by then
      summary = summary .. string.format(" %s at %d scores %.0f.", comp.by.item.name or "Held piece", comp.by.ilvl, comp.by.value)
    end
  end
  return rows, summary, cmp
end
