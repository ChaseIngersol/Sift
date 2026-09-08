-- Maps an item to the equipped slots it competes with and picks the incumbent.
local _, ns = ...

local Slots = {}
ns.Slots = Slots

Slots.ID = {
  HEAD = 1, NECK = 2, SHOULDER = 3, SHIRT = 4, CHEST = 5, WAIST = 6, LEGS = 7,
  FEET = 8, WRIST = 9, HANDS = 10, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13,
  TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17, TABARD = 19,
}
local S = Slots.ID

Slots.BY_EQUIPLOC = {
  INVTYPE_HEAD = { S.HEAD }, INVTYPE_NECK = { S.NECK }, INVTYPE_SHOULDER = { S.SHOULDER },
  INVTYPE_BODY = { S.SHIRT }, INVTYPE_CHEST = { S.CHEST }, INVTYPE_ROBE = { S.CHEST },
  INVTYPE_WAIST = { S.WAIST }, INVTYPE_LEGS = { S.LEGS }, INVTYPE_FEET = { S.FEET },
  INVTYPE_WRIST = { S.WRIST }, INVTYPE_HAND = { S.HANDS },
  INVTYPE_FINGER = { S.FINGER1, S.FINGER2 }, INVTYPE_TRINKET = { S.TRINKET1, S.TRINKET2 },
  INVTYPE_CLOAK = { S.BACK }, INVTYPE_WEAPON = { S.MAINHAND, S.OFFHAND },
  INVTYPE_SHIELD = { S.OFFHAND }, INVTYPE_2HWEAPON = { S.MAINHAND },
  INVTYPE_WEAPONMAINHAND = { S.MAINHAND }, INVTYPE_WEAPONOFFHAND = { S.OFFHAND },
  INVTYPE_HOLDABLE = { S.OFFHAND }, INVTYPE_RANGED = { S.MAINHAND },
  INVTYPE_RANGEDRIGHT = { S.MAINHAND }, INVTYPE_TABARD = { S.TABARD },
}

Slots.LABEL = {
  [1] = "head", [2] = "neck", [3] = "shoulders", [5] = "chest", [6] = "belt",
  [7] = "legs", [8] = "boots", [9] = "wrists", [10] = "gloves", [11] = "ring",
  [12] = "ring", [13] = "trinket", [14] = "trinket", [15] = "cloak",
  [16] = "main hand", [17] = "off hand",
}

function Slots.IsEquippable(equipLoc)
  return equipLoc ~= nil and equipLoc ~= "" and Slots.BY_EQUIPLOC[equipLoc] ~= nil
    and equipLoc ~= "INVTYPE_BODY" and equipLoc ~= "INVTYPE_TABARD"
end

-- Which slots does the candidate compete with for this spec, and does it
-- replace two at once (a two-hander over main hand plus off hand)?
function Slots.Candidates(item, spec)
  local loc = item.equipLoc
  local M = ns.Data.MODEL
  if loc == "INVTYPE_WEAPON" then
    if spec.model == M.DUAL_WIELD then return { S.MAINHAND, S.OFFHAND }, false end
    return { S.MAINHAND }, false
  end
  if loc == "INVTYPE_2HWEAPON" or loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" then
    return { S.MAINHAND }, true
  end
  return Slots.BY_EQUIPLOC[loc] or {}, false
end

-- Pick the incumbent: for two-slot items the weaker equipped piece, for a
-- two-hander the combined main hand and off hand. valueFn(equippedItem) ->
-- number. Returns { item, value, ilvl, slot, combined, isTier, empty }.
function Slots.Incumbent(item, char, spec, valueFn)
  local candidates, combined = Slots.Candidates(item, spec)
  local equipped = char.slots or {}
  local best = nil
  for _, slot in ipairs(candidates) do
    local eq = equipped[slot]
    if not eq then
      return { item = nil, value = 0, ilvl = 0, slot = slot, combined = combined, empty = true }
    end
    local v = valueFn(eq) or 0
    if not best or v < best.value then
      best = { item = eq, value = v, ilvl = eq.ilvl or 0, slot = slot, combined = combined, isTier = eq.isTier or false }
    end
  end
  if not best then
    return { item = nil, value = 0, ilvl = 0, slot = candidates[1], combined = combined, empty = true }
  end
  if combined then
    local off = equipped[S.OFFHAND]
    if off then
      best.value = best.value + (valueFn(off) or 0)
      best.secondItem = off
    end
  end
  return best
end
