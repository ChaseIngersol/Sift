-- Turns shipped stat priorities into coarse weights, and prefers imported sim
-- weights when a character has them.
local _, ns = ...

local Weights = {}
ns.Weights = Weights

-- Average of the sorted secondary ratios across the 28 SimC-modeled specs
-- (tools/gen-weights, 2026-09-06): 0.73, 0.65, 0.60, 0.53.
Weights.SECONDARY_DECAY = { 0.73, 0.65, 0.60, 0.53 }

-- Relative error assumed on every non-primary weight when deciding whether
-- a comparison's sign is trustworthy (docs/HOW-IT-WORKS.md, "When Sift is unsure"). Shipped
-- priorities are an ordering, not a measurement; imported sim weights are.
Weights.BAND = { shipped = 0.30, simc = 0.20, imported = 0.10 }

function Weights.Band(source)
  return Weights.BAND[source] or Weights.BAND.shipped
end

-- Midnight gear carries roughly twenty times as much stamina as primary
-- stat, so per-point stamina weights must be tiny.
local STAMINA_BY_ROLE = { dps = 0, heal = 0.002, tank = 0.03 }
local LEECH_BY_ROLE = { dps = 0.06, heal = 0.06, tank = 0.15 }
local AVOID_BY_ROLE = { dps = 0.03, heal = 0.03, tank = 0.10 }
local ARMOR_BY_ROLE = { dps = 0, heal = 0, tank = 0.05 }

-- Weapon DPS matters a great deal to physical specs and not at all to casters.
local function weaponDpsWeight(spec)
  if spec.primary == "INTELLECT" then return 0 end
  if spec.role == "tank" then return 2.0 end
  return 4.0
end

function Weights.FromSpec(spec)
  local w = {}
  w[spec.primary] = 1.0
  for i, key in ipairs(spec.priority or {}) do
    w[key] = Weights.SECONDARY_DECAY[i] or Weights.SECONDARY_DECAY[#Weights.SECONDARY_DECAY]
  end
  w.STAMINA = STAMINA_BY_ROLE[spec.role] or 0.03
  w.LEECH = LEECH_BY_ROLE[spec.role] or 0.06
  w.AVOIDANCE = AVOID_BY_ROLE[spec.role] or 0.03
  w.SPEED = 0.02
  w.INDESTRUCTIBLE = 0
  w.ARMOR = ARMOR_BY_ROLE[spec.role] or 0
  w.DPS = weaponDpsWeight(spec)
  return w
end

-- Weights generated offline from SimulationCraft's profiles
-- (Core/WeightsData.lua, tools/gen-weights), or nil for specs it lacks.
function Weights.FromSimC(spec)
  local data = ns.WeightsData
  local entry = data and data.specs and data.specs[spec.id]
  if not entry or type(entry.weights) ~= "table" or not entry.weights[spec.primary] then return nil end
  return entry.weights, entry
end

-- imported: table keyed by spec id -> { weights = {...}, name = "..." } or nil.
-- Returns weights, source where source is "imported", "simc" or "shipped".
function Weights.Resolve(spec, imported)
  local entry = imported and imported[spec.id]
  if entry and type(entry.weights) == "table" and next(entry.weights) then
    return entry.weights, "imported"
  end
  local simc = Weights.FromSimC(spec)
  if simc then return simc, "simc" end
  return Weights.FromSpec(spec), "shipped"
end

Weights.SOURCE_LABEL = { imported = "your", simc = "SimC default", shipped = "default" }

-- A point of off-hand weapon dps is worth less than a main-hand point.
-- SimC reports both (Fury: 0.375); this ratio stands in when a weight set
-- has no DPS_OH of its own.
Weights.OFFHAND_DPS_RATIO = 0.4

-- The same weights with DPS swapped for the off-hand value. Cached per
-- weight table; the tables are small and long-lived.
local offhandCache = setmetatable({}, { __mode = "k" })
function Weights.ForOffhand(weights)
  local cached = offhandCache[weights]
  if cached then return cached end
  local out = {}
  for k, v in pairs(weights) do out[k] = v end
  out.DPS = weights.DPS_OH or ((weights.DPS or 0) * Weights.OFFHAND_DPS_RATIO)
  out.DPS_OH = nil
  offhandCache[weights] = out
  return out
end
