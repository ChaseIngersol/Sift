-- Feeds observed items into Core/Growth.lua and hands the engine a season
-- view whose growth factors are calibrated from what this account has seen.
local ADDON, ns = ...

local Calibrate = {}
ns.Calibrate = Calibrate

local seasonView = nil
local resolved, sources, estimates = nil, nil, nil

local function store()
  if not ns.db then return nil end
  ns.db.season.growth = ns.db.season.growth or {}
  return ns.db.season.growth
end

-- Record one item's stats for growth estimation. Cheap: a few table reads.
function Calibrate.Observe(facts)
  local s = store()
  if not s or not facts then return end
  if ns.Growth.Observe(s, facts) then seasonView = nil end
end

local function resolve()
  local s = store()
  local season = ns.Season
  resolved, sources, estimates = ns.Growth.Resolve(s, season.statGrowth, season.growthMinSamples, season.growthSane)
  if s then s.dirty = nil end
end

-- Season data with statGrowth replaced by live estimates where enough
-- same-slot pairs exist. Everything else reads through to Core/Season.lua.
function Calibrate.Season()
  if seasonView then return seasonView end
  resolve()
  seasonView = setmetatable({ statGrowth = resolved }, { __index = ns.Season })
  return seasonView
end

function Calibrate.Invalidate()
  seasonView = nil
end

-- One line for /sift status.
function Calibrate.Describe()
  Calibrate.Season()
  local parts = {}
  for _, class in ipairs(ns.Growth.CLASSES) do
    local g = resolved and resolved[class]
    if g then
      local e = estimates and estimates[class]
      parts[#parts + 1] = string.format("%s %.2f%% (%s%s)", class, (g - 1) * 100, sources[class] or "seed",
        e and string.format(", %d pairs seen", e.samples) or "")
    end
  end
  return "growth per item level: " .. table.concat(parts, ", ")
end
