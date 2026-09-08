-- Hard filters that run before scoring. An item that fails is never scored.
local _, ns = ...

local Eligibility = {}
ns.Eligibility = Eligibility

local NO_ARMOR_CHECK = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_HOLDABLE = true }
local ARMOR_TYPES = { [1] = true, [2] = true, [3] = true, [4] = true }

-- Returns ok, reason. reason is one of: level, armor, shield, weapon, model, primary.
function Eligibility.Check(item, char, spec)
  local Data = ns.Data
  local class = Data.classes[char.classID]
  if not class then return false, "class" end
  if not spec then return false, "spec" end

  if item.classID == Data.ITEM_CLASS.ARMOR then
    local sub = item.subclassID
    local M = Data.MODEL
    local offhandModel = spec.model == M.ONE_HAND_SHIELD or spec.model == M.CASTER
    if sub == Data.ARMOR.SHIELD then
      if not class.shield then return false, "shield" end
      if not offhandModel then return false, "model" end
    elseif item.equipLoc == "INVTYPE_HOLDABLE" then
      if not class.offhand then return false, "shield" end
      if not offhandModel then return false, "model" end
    elseif ARMOR_TYPES[sub] and not NO_ARMOR_CHECK[item.equipLoc] then
      if sub ~= class.armor then return false, "armor" end
    end
  elseif item.classID == Data.ITEM_CLASS.WEAPON then
    local sub = item.subclassID
    if not class.weapons[sub] then return false, "weapon" end
    local ok = Eligibility.WeaponFitsModel(item, spec)
    if not ok then return false, "model" end
  end

  local fixed = ns.Stats.FixedPrimary(item.stats or {})
  if fixed and fixed ~= spec.primary then return false, "primary" end
  if item.flex and not item.flex[spec.primary] then return false, "primary" end

  -- Last, because it is the one reason that goes away on its own.
  if item.reqLevel and char.level and item.reqLevel > char.level then
    return false, "level"
  end

  return true
end

-- Does this weapon shape make sense for the spec's weapon model?
function Eligibility.WeaponFitsModel(item, spec)
  local Data = ns.Data
  local M = Data.MODEL
  local loc = item.equipLoc
  local sub = item.subclassID
  local isRanged = loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" or Data.RANGED_WEAPONS[sub]
  local isTwoHand = loc == "INVTYPE_2HWEAPON" or Data.TWO_HAND_WEAPONS[sub]
  local isOneHand = loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" or loc == "INVTYPE_WEAPONOFFHAND"

  if spec.model == M.RANGED then return isRanged end
  if isRanged then return false end
  if spec.model == M.TWO_HAND then
    if isTwoHand then return true end
    return spec.dualWieldOK and isOneHand or false
  end
  if spec.model == M.DUAL_WIELD then
    if isOneHand then return true end
    return spec.twoHandOK and isTwoHand or false
  end
  if spec.model == M.ONE_HAND_SHIELD then
    return isOneHand and loc ~= "INVTYPE_WEAPONOFFHAND"
  end
  if spec.model == M.CASTER then
    return isTwoHand or (isOneHand and loc ~= "INVTYPE_WEAPONOFFHAND")
  end
  return false
end
