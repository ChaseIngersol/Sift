-- Builders for engine inputs. Every field has a sensible default so a spec
-- only states what matters to it.
local ns = SiftTest.ns
local F = {}

local counter = 0
-- Sentinel so an override can clear a defaulted field (pairs() skips nil).
F.NIL = {}
local function merge(base, over)
  for k, v in pairs(over or {}) do
    if v == F.NIL then base[k] = nil else base[k] = v end
  end
  return base
end

function F.season(over)
  local s = {}
  for k, v in pairs(ns.Season) do s[k] = v end
  return merge(s, over)
end

-- A plate chest with adaptive primary by default.
function F.item(over)
  counter = counter + 1
  local it = {
    guid = "item-" .. counter, name = "Item " .. counter, id = 1000 + counter,
    ilvl = 300, quality = 4, equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 4,
    bind = 1, sendable = false, reqLevel = 80,
    stats = { STAMINA = 1500, CRIT = 400, HASTE = 400 },
    flex = { value = 1000, STRENGTH = true, AGILITY = true, INTELLECT = true },
    track = nil, rank = nil, maxRank = nil, catalystEligible = false, isTier = false,
  }
  return merge(it, over)
end

function F.trinket(over)
  return F.item(merge({ equipLoc = "INVTYPE_TRINKET", subclassID = 0, stats = { STRENGTH = 900, CRIT = 300 }, flex = F.NIL }, over))
end

function F.ring(over)
  return F.item(merge({ equipLoc = "INVTYPE_FINGER", subclassID = 0, stats = { STAMINA = 900, CRIT = 700, HASTE = 500 }, flex = F.NIL }, over))
end

function F.weapon(over)
  return F.item(merge({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { STRENGTH = 700, CRIT = 300, DPS = 800 }, flex = F.NIL }, over))
end

-- Fury warrior by default, with a full plate set of the given level.
function F.char(over)
  counter = counter + 1
  local specs = {}
  local c = {
    key = "Char" .. counter .. "-Realm", name = "Char" .. counter, realm = "Realm",
    classID = 1, level = 80, specs = specs, slots = {}, tierCount = 0, parked = false,
    importedWeights = nil,
  }
  merge(c, over)
  if #c.specs == 0 then c.specs[1] = ns.Data.specs[72] end
  return c
end

-- Fill every armor slot with a plain item at ilvl.
function F.equipAll(char, ilvl, over)
  local S = ns.Slots.ID
  for _, slot in ipairs({ S.HEAD, S.NECK, S.SHOULDER, S.CHEST, S.WAIST, S.LEGS, S.FEET, S.WRIST, S.HANDS, S.BACK }) do
    char.slots[slot] = F.item(merge({ name = "Equipped " .. slot, ilvl = ilvl }, over))
  end
  char.slots[S.FINGER1] = F.ring({ name = "Ring A", ilvl = ilvl })
  char.slots[S.FINGER2] = F.ring({ name = "Ring B", ilvl = ilvl })
  char.slots[S.TRINKET1] = F.trinket({ name = "Trinket A", ilvl = ilvl })
  char.slots[S.TRINKET2] = F.trinket({ name = "Trinket B", ilvl = ilvl })
  char.slots[S.MAINHAND] = F.weapon({ name = "Main Hand", ilvl = ilvl })
  char.slots[S.OFFHAND] = F.weapon({ name = "Off Hand", ilvl = ilvl })
  return char
end

function F.ctx(over)
  local ctx = { item = nil, self = nil, alts = {}, res = { crests = {}, catalystCharges = 0 }, prefs = {}, season = F.season() }
  return merge(ctx, over)
end

function F.eval(over)
  return ns.Engine.Evaluate(F.ctx(over))
end

return F
