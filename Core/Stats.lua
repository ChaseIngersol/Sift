-- Canonical stat keys and the maps from game tokens and Pawn-string names.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

Stats.PRIMARY = { STRENGTH = true, AGILITY = true, INTELLECT = true }
Stats.SECONDARY = { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }
Stats.TERTIARY = { "LEECH", "AVOIDANCE", "SPEED", "INDESTRUCTIBLE" }

-- Tokens returned by C_Item.GetItemStats to canonical keys.
Stats.TOKEN_TO_KEY = {
  ITEM_MOD_STRENGTH_SHORT = "STRENGTH",
  ITEM_MOD_AGILITY_SHORT = "AGILITY",
  ITEM_MOD_INTELLECT_SHORT = "INTELLECT",
  ITEM_MOD_STAMINA_SHORT = "STAMINA",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
  ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
  ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY",
  ITEM_MOD_VERSATILITY = "VERSATILITY",
  ITEM_MOD_CR_LIFESTEAL_SHORT = "LEECH",
  ITEM_MOD_CR_AVOIDANCE_SHORT = "AVOIDANCE",
  ITEM_MOD_CR_SPEED_SHORT = "SPEED",
  ITEM_MOD_CR_STURDINESS_SHORT = "INDESTRUCTIBLE",
  RESISTANCE0_NAME = "ARMOR",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

-- Tokens for items whose primary stat adapts to the wearer.
Stats.FLEX_TOKENS = {
  ITEM_MOD_AGI_STR_INT_SHORT = { AGILITY = true, STRENGTH = true, INTELLECT = true },
  ITEM_MOD_AGI_STR_SHORT = { AGILITY = true, STRENGTH = true },
  ITEM_MOD_AGI_INT_SHORT = { AGILITY = true, INTELLECT = true },
  ITEM_MOD_STR_INT_SHORT = { STRENGTH = true, INTELLECT = true },
}

-- Pawn-string stat names to canonical keys.
Stats.PAWN_TO_KEY = {
  Strength = "STRENGTH",
  Agility = "AGILITY",
  Intellect = "INTELLECT",
  Stamina = "STAMINA",
  CritRating = "CRIT",
  HasteRating = "HASTE",
  MasteryRating = "MASTERY",
  Versatility = "VERSATILITY",
  Leech = "LEECH",
  Avoidance = "AVOIDANCE",
  MovementSpeed = "SPEED",
  Indestructible = "INDESTRUCTIBLE",
  Armor = "ARMOR",
  Dps = "DPS",
}

-- A gem that gives "Primary Stat" resolves to the wearer's primary; the
-- scorer folds this key into the spec's primary stat.
Stats.PRIMARY_GEM = "PRIMARY"

-- Stat class per key. Growth per item level differs by class.
Stats.CLASS_OF = {
  STRENGTH = "primary", AGILITY = "primary", INTELLECT = "primary",
  STAMINA = "stamina",
  CRIT = "secondary", HASTE = "secondary", MASTERY = "secondary", VERSATILITY = "secondary",
  LEECH = "tertiary", AVOIDANCE = "tertiary", SPEED = "tertiary", INDESTRUCTIBLE = "tertiary",
  ARMOR = "armor", DPS = "dps",
}

Stats.LABEL = {
  STRENGTH = "Strength", AGILITY = "Agility", INTELLECT = "Intellect",
  STAMINA = "Stamina", CRIT = "Crit", HASTE = "Haste", MASTERY = "Mastery",
  VERSATILITY = "Vers", LEECH = "Leech", AVOIDANCE = "Avoidance",
  SPEED = "Speed", INDESTRUCTIBLE = "Indestructible", ARMOR = "Armor", DPS = "DPS",
}

-- Turn a raw token table into canonical stats plus an optional flex-primary
-- record. Unknown tokens are ignored. Returns stats, flex.
function Stats.Normalize(raw)
  local stats, flex = {}, nil
  if type(raw) ~= "table" then return stats, nil end
  for token, value in pairs(raw) do
    local n = tonumber(value)
    if n and n ~= 0 then
      local key = Stats.TOKEN_TO_KEY[token]
      if key then
        stats[key] = (stats[key] or 0) + n
      else
        local allows = Stats.FLEX_TOKENS[token]
        if allows then
          flex = { value = n }
          for k in pairs(allows) do flex[k] = true end
        end
      end
    end
  end
  return stats, flex
end

-- Which primary stats an armor type can carry.
Stats.ARMOR_PRIMARIES = {
  [1] = { INTELLECT = true },
  [2] = { AGILITY = true, INTELLECT = true },
  [3] = { AGILITY = true, INTELLECT = true },
  [4] = { STRENGTH = true, INTELLECT = true },
}
local ARMOR_SLOTS = {
  INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
  INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

-- Armor pieces adapt their primary stat to the wearer, and the game resolves
-- it for the current character before an addon sees it. Restore the adaptive
-- form so a piece scanned on a mage still scores for a warrior alt.
function Stats.NormalizeForArmor(stats, flex, classID, subclassID, equipLoc)
  if flex then return stats, flex end
  local allows = Stats.ARMOR_PRIMARIES[subclassID]
  if classID ~= 4 or not allows or not ARMOR_SLOTS[equipLoc] then return stats, flex end
  local fixed = Stats.FixedPrimary(stats)
  if not fixed then return stats, nil end
  local newFlex = { value = stats[fixed] }
  for k in pairs(allows) do newFlex[k] = true end
  newFlex[fixed] = true
  local out = {}
  for k, v in pairs(stats) do
    if k ~= fixed then out[k] = v end
  end
  return out, newFlex
end

-- The fixed primary stat on an item, or nil if none or adaptive.
function Stats.FixedPrimary(stats)
  for key in pairs(Stats.PRIMARY) do
    if stats[key] and stats[key] > 0 then return key end
  end
  return nil
end

local function escapePattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Parse "+16 Mastery & +7 Haste" style text into canonical stats. names maps
-- a localized stat name to a canonical key. Returns stats, found where found
-- is false when no "+number name" pair was recognized.
function Stats.ParseBonusText(text, names)
  local out, found = {}, false
  if type(text) ~= "string" or type(names) ~= "table" then return out, false end
  for name, key in pairs(names) do
    if type(name) == "string" and name ~= "" then
      local pattern = "%+([%d,%.]+)%s+" .. escapePattern(name)
      local init = 1
      while true do
        local s, e, amount = text:find(pattern, init)
        if not s then break end
        init = e + 1
        local after = text:sub(e + 1, e + 1)
        if not after:match("%a") then
          local n = tonumber((amount:gsub(",", "")))
          if n and n > 0 then
            out[key] = (out[key] or 0) + n
            found = true
          end
        end
      end
    end
  end
  return out, found
end
