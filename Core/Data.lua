-- Class, specialization, armor and weapon data. Data only.
local _, ns = ...

local Data = {}
ns.Data = Data

-- Enum.ItemArmorSubclass
Data.ARMOR = { GENERIC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, COSMETIC = 5, SHIELD = 6 }
-- Enum.ItemClass
Data.ITEM_CLASS = { WEAPON = 2, ARMOR = 4 }
-- Enum.ItemWeaponSubclass
local W = {
  AXE1H = 0, AXE2H = 1, BOW = 2, GUN = 3, MACE1H = 4, MACE2H = 5, POLEARM = 6,
  SWORD1H = 7, SWORD2H = 8, WARGLAIVE = 9, STAFF = 10, FIST = 13, GENERIC = 14,
  DAGGER = 15, CROSSBOW = 18, WAND = 19, FISHINGPOLE = 20,
}
Data.WEAPON = W

local function set(...)
  local t = {}
  for i = 1, select("#", ...) do t[select(i, ...)] = true end
  return t
end

-- Weapon proficiencies are what the class would ever want to score, not the
-- full list of what it can technically equip. Ranged weapons only matter to
-- hunters; wands only to cloth casters.
Data.classes = {
  [1]  = { file = "WARRIOR",     name = "Warrior",      armor = 4, shield = true,
           weapons = set(W.AXE1H, W.AXE2H, W.MACE1H, W.MACE2H, W.POLEARM, W.SWORD1H, W.SWORD2H, W.STAFF, W.DAGGER, W.FIST) },
  [2]  = { file = "PALADIN",     name = "Paladin",      armor = 4, shield = true,
           weapons = set(W.AXE1H, W.AXE2H, W.MACE1H, W.MACE2H, W.POLEARM, W.SWORD1H, W.SWORD2H) },
  [3]  = { file = "HUNTER",      name = "Hunter",       armor = 3, shield = false,
           weapons = set(W.AXE1H, W.AXE2H, W.BOW, W.GUN, W.CROSSBOW, W.POLEARM, W.STAFF, W.SWORD1H, W.SWORD2H, W.DAGGER, W.FIST) },
  [4]  = { file = "ROGUE",       name = "Rogue",        armor = 2, shield = false,
           weapons = set(W.AXE1H, W.MACE1H, W.SWORD1H, W.DAGGER, W.FIST) },
  [5]  = { file = "PRIEST",      name = "Priest",       armor = 1, shield = false, offhand = true,
           weapons = set(W.DAGGER, W.MACE1H, W.STAFF, W.WAND) },
  [6]  = { file = "DEATHKNIGHT", name = "Death Knight", armor = 4, shield = false,
           weapons = set(W.AXE1H, W.AXE2H, W.MACE1H, W.MACE2H, W.SWORD1H, W.SWORD2H, W.POLEARM) },
  [7]  = { file = "SHAMAN",      name = "Shaman",       armor = 3, shield = true, offhand = true,
           weapons = set(W.AXE1H, W.AXE2H, W.MACE1H, W.MACE2H, W.DAGGER, W.FIST, W.STAFF) },
  [8]  = { file = "MAGE",        name = "Mage",         armor = 1, shield = false, offhand = true,
           weapons = set(W.DAGGER, W.SWORD1H, W.STAFF, W.WAND) },
  [9]  = { file = "WARLOCK",     name = "Warlock",      armor = 1, shield = false, offhand = true,
           weapons = set(W.DAGGER, W.SWORD1H, W.STAFF, W.WAND) },
  [10] = { file = "MONK",        name = "Monk",         armor = 2, shield = false, offhand = true,
           weapons = set(W.AXE1H, W.MACE1H, W.SWORD1H, W.FIST, W.POLEARM, W.STAFF) },
  [11] = { file = "DRUID",       name = "Druid",        armor = 2, shield = false, offhand = true,
           weapons = set(W.MACE1H, W.MACE2H, W.DAGGER, W.FIST, W.POLEARM, W.STAFF) },
  [12] = { file = "DEMONHUNTER", name = "Demon Hunter", armor = 2, shield = false,
           weapons = set(W.WARGLAIVE, W.AXE1H, W.SWORD1H, W.DAGGER, W.FIST) },
  [13] = { file = "EVOKER",      name = "Evoker",       armor = 3, shield = false, offhand = true,
           weapons = set(W.AXE1H, W.AXE2H, W.MACE1H, W.MACE2H, W.SWORD1H, W.SWORD2H, W.DAGGER, W.FIST, W.STAFF) },
}

-- Weapon models decide which equipped slots a candidate competes with.
--   TWO_HAND         one two-handed weapon
--   DUAL_WIELD       two one-handers, compared against the weaker
--   ONE_HAND_SHIELD  main hand plus shield or held item
--   RANGED           bow, gun or crossbow
--   CASTER           staff, or main hand plus held item or shield
Data.MODEL = { TWO_HAND = "TWO_HAND", DUAL_WIELD = "DUAL_WIELD", ONE_HAND_SHIELD = "ONE_HAND_SHIELD", RANGED = "RANGED", CASTER = "CASTER" }
local M = Data.MODEL

-- Stat priorities are FALLBACK DATA: a coarse ordering of the four
-- secondaries, used only for specs Core/WeightsData.lua does not cover.
-- Orderings for covered specs are copied from the SimC scale factors
-- (2026-09-06); the rest are guide orderings. They produce tiers, never
-- percentages. Imported sim weights always take precedence.
local function spec(classID, name, primary, role, model, priority, extra)
  local s = { classID = classID, name = name, primary = primary, role = role, model = model, priority = priority }
  if extra then for k, v in pairs(extra) do s[k] = v end end
  return s
end

Data.specs = {
  -- Warrior
  [71]  = spec(1, "Arms",          "STRENGTH",  "dps",  M.TWO_HAND,        { "CRIT", "MASTERY", "VERSATILITY", "HASTE" }),
  [72]  = spec(1, "Fury",          "STRENGTH",  "dps",  M.DUAL_WIELD,      { "HASTE", "VERSATILITY", "MASTERY", "CRIT" }, { twoHandOK = true }),
  [73]  = spec(1, "Protection",    "STRENGTH",  "tank", M.ONE_HAND_SHIELD, { "CRIT", "MASTERY", "VERSATILITY", "HASTE" }),
  -- Paladin
  [65]  = spec(2, "Holy",          "INTELLECT", "heal", M.ONE_HAND_SHIELD, { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [66]  = spec(2, "Protection",    "STRENGTH",  "tank", M.ONE_HAND_SHIELD, { "VERSATILITY", "HASTE", "CRIT", "MASTERY" }),
  [70]  = spec(2, "Retribution",   "STRENGTH",  "dps",  M.TWO_HAND,        { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  -- Hunter
  [253] = spec(3, "Beast Mastery", "AGILITY",   "dps",  M.RANGED,          { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [254] = spec(3, "Marksmanship",  "AGILITY",   "dps",  M.RANGED,          { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }),
  [255] = spec(3, "Survival",      "AGILITY",   "dps",  M.TWO_HAND,        { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  -- Rogue
  [259] = spec(4, "Assassination", "AGILITY",   "dps",  M.DUAL_WIELD,      { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [260] = spec(4, "Outlaw",        "AGILITY",   "dps",  M.DUAL_WIELD,      { "CRIT", "VERSATILITY", "HASTE", "MASTERY" }),
  [261] = spec(4, "Subtlety",      "AGILITY",   "dps",  M.DUAL_WIELD,      { "VERSATILITY", "MASTERY", "HASTE", "CRIT" }),
  -- Priest
  [256] = spec(5, "Discipline",    "INTELLECT", "heal", M.CASTER,          { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [257] = spec(5, "Holy",          "INTELLECT", "heal", M.CASTER,          { "MASTERY", "CRIT", "HASTE", "VERSATILITY" }),
  [258] = spec(5, "Shadow",        "INTELLECT", "dps",  M.CASTER,          { "CRIT", "VERSATILITY", "MASTERY", "HASTE" }),
  -- Death Knight
  [250] = spec(6, "Blood",         "STRENGTH",  "tank", M.TWO_HAND,        { "CRIT", "MASTERY", "VERSATILITY", "HASTE" }),
  [251] = spec(6, "Frost",         "STRENGTH",  "dps",  M.DUAL_WIELD,      { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }, { twoHandOK = true }),
  [252] = spec(6, "Unholy",        "STRENGTH",  "dps",  M.TWO_HAND,        { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }),
  -- Shaman
  [262] = spec(7, "Elemental",     "INTELLECT", "dps",  M.CASTER,          { "CRIT", "VERSATILITY", "HASTE", "MASTERY" }),
  [263] = spec(7, "Enhancement",   "AGILITY",   "dps",  M.DUAL_WIELD,      { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }),
  [264] = spec(7, "Restoration",   "INTELLECT", "heal", M.CASTER,          { "CRIT", "VERSATILITY", "HASTE", "MASTERY" }),
  -- Mage
  [62]  = spec(8, "Arcane",        "INTELLECT", "dps",  M.CASTER,          { "MASTERY", "CRIT", "VERSATILITY", "HASTE" }),
  [63]  = spec(8, "Fire",          "INTELLECT", "dps",  M.CASTER,          { "VERSATILITY", "MASTERY", "HASTE", "CRIT" }),
  [64]  = spec(8, "Frost",         "INTELLECT", "dps",  M.CASTER,          { "CRIT", "MASTERY", "VERSATILITY", "HASTE" }),
  -- Warlock
  [265] = spec(9, "Affliction",    "INTELLECT", "dps",  M.CASTER,          { "CRIT", "VERSATILITY", "HASTE", "MASTERY" }),
  [266] = spec(9, "Demonology",    "INTELLECT", "dps",  M.CASTER,          { "CRIT", "MASTERY", "HASTE", "VERSATILITY" }),
  [267] = spec(9, "Destruction",   "INTELLECT", "dps",  M.CASTER,          { "CRIT", "MASTERY", "HASTE", "VERSATILITY" }),
  -- Monk
  [268] = spec(10, "Brewmaster",   "AGILITY",   "tank", M.TWO_HAND,        { "CRIT", "VERSATILITY", "MASTERY", "HASTE" }, { dualWieldOK = true }),
  [270] = spec(10, "Mistweaver",   "INTELLECT", "heal", M.CASTER,          { "HASTE", "CRIT", "VERSATILITY", "MASTERY" }),
  [269] = spec(10, "Windwalker",   "AGILITY",   "dps",  M.DUAL_WIELD,      { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }, { twoHandOK = true }),
  -- Druid
  [102] = spec(11, "Balance",      "INTELLECT", "dps",  M.CASTER,          { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }),
  [103] = spec(11, "Feral",        "AGILITY",   "dps",  M.CASTER,          { "CRIT", "MASTERY", "HASTE", "VERSATILITY" }),
  [104] = spec(11, "Guardian",     "AGILITY",   "tank", M.CASTER,          { "VERSATILITY", "MASTERY", "HASTE", "CRIT" }),
  [105] = spec(11, "Restoration",  "INTELLECT", "heal", M.CASTER,          { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }),
  -- Demon Hunter. Devourer (id 1480) is an
  -- Intellect ranged spec that shares gear with casters; warglaives adapt.
  [577] = spec(12, "Havoc",        "AGILITY",   "dps",  M.DUAL_WIELD,      { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }),
  [581] = spec(12, "Vengeance",    "AGILITY",   "tank", M.DUAL_WIELD,      { "CRIT", "VERSATILITY", "MASTERY", "HASTE" }),
  [1480] = spec(12, "Devourer",    "INTELLECT", "dps",  M.DUAL_WIELD,      { "CRIT", "HASTE", "MASTERY", "VERSATILITY" }),
  -- Evoker
  [1467] = spec(13, "Devastation", "INTELLECT", "dps",  M.CASTER,          { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [1468] = spec(13, "Preservation","INTELLECT", "heal", M.CASTER,          { "HASTE", "CRIT", "MASTERY", "VERSATILITY" }),
  [1473] = spec(13, "Augmentation","INTELLECT", "dps",  M.CASTER,          { "HASTE", "MASTERY", "CRIT", "VERSATILITY" }),
}

for id, s in pairs(Data.specs) do s.id = id end

function Data.SpecsForClass(classID)
  local out = {}
  for id, s in pairs(Data.specs) do
    if s.classID == classID then out[#out + 1] = s end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function Data.FindClassByName(name)
  if not name then return nil end
  local lname = name:lower():gsub("%s+", "")
  for id, c in pairs(Data.classes) do
    if c.name:lower():gsub("%s+", "") == lname or c.file:lower() == lname then return id, c end
  end
  return nil
end

function Data.FindSpecByName(classID, name)
  if not classID or not name then return nil end
  local lname = name:lower():gsub("%s+", "")
  for id, s in pairs(Data.specs) do
    if s.classID == classID and s.name:lower():gsub("%s+", "") == lname then return id, s end
  end
  return nil
end

-- Melee weapon subclasses that count as two-handed.
Data.TWO_HAND_WEAPONS = set(W.AXE2H, W.MACE2H, W.POLEARM, W.SWORD2H, W.STAFF)
Data.RANGED_WEAPONS = set(W.BOW, W.GUN, W.CROSSBOW)

Data.ARMOR_NAME = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shields" }
Data.WEAPON_NAME = {
  [W.AXE1H] = "one-handed axes", [W.AXE2H] = "two-handed axes", [W.BOW] = "bows", [W.GUN] = "guns",
  [W.MACE1H] = "one-handed maces", [W.MACE2H] = "two-handed maces", [W.POLEARM] = "polearms",
  [W.SWORD1H] = "one-handed swords", [W.SWORD2H] = "two-handed swords", [W.WARGLAIVE] = "warglaives",
  [W.STAFF] = "staves", [W.FIST] = "fist weapons", [W.DAGGER] = "daggers", [W.CROSSBOW] = "crossbows",
  [W.WAND] = "wands", [W.FISHINGPOLE] = "fishing poles",
}
