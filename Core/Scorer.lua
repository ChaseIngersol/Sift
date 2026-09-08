-- Built-in scorer: canonical stats times weights, with per-stat growth to a
-- hypothetical item level, socketed gems and empty sockets. Pure Lua.
local _, ns = ...

local Scorer = {}
ns.Scorer = Scorer

-- Fold an adaptive primary stat into the spec's primary when allowed.
function Scorer.Resolve(item, primaryKey)
  local out = {}
  for k, v in pairs(item.stats or {}) do out[k] = v end
  local flex = item.flex
  if flex and primaryKey and flex[primaryKey] then
    out[primaryKey] = (out[primaryKey] or 0) + (flex.value or 0)
  end
  return out
end

-- growth is a per-level factor: a number for every stat, or a table keyed by
-- stat class (Stats.CLASS_OF).
local function growthFor(growth, key)
  if type(growth) == "number" then return growth end
  if type(growth) == "table" then return growth[ns.Stats.CLASS_OF[key] or ""] end
  return nil
end

-- Worth of one empty socket: the better of the season's primary gem and
-- its secondary gem (rating split into the best-weighted secondaries).
-- socketGem = { primary = n, secondary = { n1, n2 } }; a bare list is read
-- as the secondary split. Returns 0 when the weights value neither.
function Scorer.SocketValue(weights, socketGem, primaryKey)
  if type(socketGem) ~= "table" then return 0 end
  local split = socketGem.secondary or socketGem
  local best = 0
  if socketGem.primary and primaryKey and weights[primaryKey] then
    best = socketGem.primary * weights[primaryKey]
  end
  if type(split) == "table" and #split > 0 then
    local ranked = {}
    for _, key in ipairs(ns.Stats.SECONDARY) do
      local w = weights[key]
      if w and w > 0 then ranked[#ranked + 1] = { key = key, w = w } end
    end
    table.sort(ranked, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.key < b.key end)
    local total = 0
    for i, amount in ipairs(split) do
      local r = ranked[i]
      if not r then break end
      total = total + amount * r.w
    end
    if total > best then best = total end
  end
  return best
end

-- Weighted contribution per stat key. opts = { atIlvl, growth, socketGem }.
-- Base stats scale to atIlvl by stat class; gems and sockets do not scale.
-- Returns contribs, total, scorable. scorable is false when no weighted
-- stat is present, in which case callers fall back to item level.
function Scorer.Contributions(item, weights, primaryKey, opts)
  opts = opts or {}
  local contribs, total, any = {}, 0, false
  local delta = 0
  if opts.atIlvl and item.ilvl and opts.atIlvl ~= item.ilvl then delta = opts.atIlvl - item.ilvl end
  for key, amount in pairs(Scorer.Resolve(item, primaryKey)) do
    local w = weights[key]
    if w and w ~= 0 then
      if delta ~= 0 then
        local g = growthFor(opts.growth, key)
        if g and g > 0 then amount = amount * (g ^ delta) end
      end
      contribs[key] = (contribs[key] or 0) + amount * w
      any = true
    end
  end
  for key, amount in pairs(item.gems or {}) do
    if key == ns.Stats.PRIMARY_GEM then key = primaryKey end
    local w = key and weights[key]
    if w and w ~= 0 then
      contribs[key] = (contribs[key] or 0) + amount * w
      any = true
    end
  end
  local sockets = item.sockets or 0
  if sockets > 0 then
    local v = Scorer.SocketValue(weights, opts.socketGem, primaryKey)
    if v > 0 then
      contribs.SOCKET = sockets * v
      any = true
    end
  end
  for _, v in pairs(contribs) do total = total + v end
  return contribs, total, any
end

function Scorer.Value(item, weights, primaryKey, opts)
  local _, total, any = Scorer.Contributions(item, weights, primaryKey, opts)
  return total, any
end

function Scorer.Percent(candidate, incumbent)
  if not candidate or not incumbent or incumbent <= 0 then return nil end
  return candidate / incumbent - 1
end

-- Does the sign of (cand - inc) survive every weight within +/- band of its
-- value? Weights are linear, so the worst case is each non-primary term
-- pushed against the delta: margin = |delta| - band * sum(|term deltas|).
-- Returns margin, spread. A negative margin means too close to call.
function Scorer.Margin(candContribs, incContribs, primaryKey, band)
  local delta, spread = 0, 0
  local keys = {}
  for k in pairs(candContribs or {}) do keys[k] = true end
  for k in pairs(incContribs or {}) do keys[k] = true end
  for k in pairs(keys) do
    local d = ((candContribs and candContribs[k]) or 0) - ((incContribs and incContribs[k]) or 0)
    delta = delta + d
    if k ~= primaryKey then spread = spread + math.abs(d) end
  end
  return math.abs(delta) - (band or 0) * spread, spread
end

-- Tier bands. threshold is the equip threshold (default 0.01).
function Scorer.Tier(pct, threshold)
  if pct == nil then return nil end
  threshold = threshold or 0.01
  if pct >= 0.05 then return "much_better" end
  if pct >= threshold then return "better" end
  if pct > -threshold then return "equal" end
  return "worse"
end

Scorer.TIER_LABEL = {
  much_better = "clearly better",
  better = "better",
  equal = "about equal",
  worse = "worse",
}
