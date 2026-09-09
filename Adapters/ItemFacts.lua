-- Reads game item APIs and tooltip data into the plain fact tables the
-- engine consumes. Nothing here reads unit, aura or combat data.
local ADDON, ns = ...

local Facts = {}
ns.ItemFacts = Facts

local LINE = Enum and Enum.TooltipDataLineType or {}
local LINE_BINDING = LINE.ItemBinding or 20
local LINE_UPGRADE = LINE.ItemUpgradeLevel or 32
local LINE_ONUSE = LINE.ItemSpellTriggerOnUse or 44
local LINE_ONEQUIP = LINE.ItemSpellTriggerOnEquip or 45
local LINE_ONPROC = LINE.ItemSpellTriggerOnProc or 46
local LINE_SOCKET = LINE.GemSocket or 3

local BIND = Enum and Enum.ItemBind or {}
local BIND_ON_EQUIP = BIND.OnEquip or 2
local BIND_WARBAND = BIND.ToBnetAccount or 8
local BIND_WARBAND_UNTIL_EQUIPPED = BIND.ToBnetAccountUntilEquipped or 9

-- Build a Lua pattern from a global string such as "Upgrade Level: %s %d/%d".
local upgradePattern
local function getUpgradePattern()
  if upgradePattern then return upgradePattern end
  local fmt = rawget(_G, "ITEM_UPGRADE_TOOLTIP_FORMAT")
  if type(fmt) == "string" and fmt:find("%%s") and fmt:find("%%d") then
    local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    upgradePattern = "^" .. p .. "$"
  else
    upgradePattern = "^.-:%s*(.-)%s+(%d+)/(%d+)$"
  end
  return upgradePattern
end

local function bindingFromText(text)
  if not text then return nil end
  local wue = rawget(_G, "ITEM_BIND_TO_BNETACCOUNT_UNTIL_EQUIP")
  local wb1 = rawget(_G, "ITEM_BNETACCOUNTBOUND")
  local wb2 = rawget(_G, "ITEM_ACCOUNTBOUND")
  local boe = rawget(_G, "ITEM_BIND_ON_EQUIP")
  local sb = rawget(_G, "ITEM_SOULBOUND")
  if wue and text == wue then return "wue" end
  if (wb1 and text == wb1) or (wb2 and text == wb2) then return "warband" end
  if boe and text == boe then return "boe" end
  if sb and text == sb then return "soulbound" end
  return nil
end

-- Localized short stat names ("Mastery", "Critical Strike") to canonical
-- keys, for reading the text of a socketed gem.
local bonusNames
local function getBonusNames()
  if bonusNames then return bonusNames end
  bonusNames = {}
  for token, key in pairs(ns.Stats.TOKEN_TO_KEY) do
    local name = rawget(_G, token)
    if type(name) == "string" and name ~= "" then bonusNames[name] = key end
  end
  -- Gems that give "+32 Primary Stat". The adaptive
  -- stat tokens and the plain English name both map to the primary key.
  for token in pairs(ns.Stats.FLEX_TOKENS) do
    local name = rawget(_G, token)
    if type(name) == "string" and name ~= "" then bonusNames[name] = ns.Stats.PRIMARY_GEM end
  end
  bonusNames["Primary Stat"] = ns.Stats.PRIMARY_GEM
  return bonusNames
end

-- A socket line either names an empty socket or carries the gem's bonus
-- text ("+16 Mastery & +7 Haste"). Gems do not scale with item level, so
-- they are kept apart from stats.
local function readSocketLine(f, line)
  local text = line.leftText or ""
  local gems, found = ns.Stats.ParseBonusText(text, getBonusNames())
  if found then
    f.gems = f.gems or {}
    for k, v in pairs(gems) do f.gems[k] = (f.gems[k] or 0) + v end
  elseif not text:find("%+%d") then
    f.sockets = (f.sockets or 0) + 1
  end
end

-- "You may trade this item with players that were also eligible..." up
-- to its first placeholder, in the client's language.
local tradeHead
local function getTradeHead()
  if tradeHead == nil then
    local fmt = rawget(_G, "BIND_TRADE_TIME_REMAINING")
    tradeHead = (type(fmt) == "string" and fmt:match("^(.-)%%")) or false
    if tradeHead == "" then tradeHead = false end
  end
  return tradeHead
end

function Facts.ReadTooltip(f, data)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return end
  local pattern = getUpgradePattern()
  local trade = getTradeHead()
  for _, line in ipairs(data.lines) do
    local t = line.type
    local text = line.leftText
    if trade and text and text:sub(1, #trade) == trade then f.tradeable = true end
    if t == LINE_SOCKET then
      readSocketLine(f, line)
    elseif t == LINE_UPGRADE and text then
      local track, rank, maxRank = text:match(pattern)
      if not track then track, rank, maxRank = text:match("(%a+)%s+(%d+)/(%d+)%s*$") end
      local sid = line.trackStringID
      local learned = ns.db and ns.db.season and ns.db.season.trackStrings
      if track then
        track = track:gsub("^%s+", ""):gsub("%s+$", "")
        if sid and learned and not learned[sid] and ns.Season.tracks[track] then learned[sid] = track end
      elseif sid then
        track = (learned and learned[sid]) or ns.Season.trackStringIDs[sid]
      end
      if track then
        f.track = track
        f.rank = tonumber(line.currentLevel) or tonumber(rank)
        f.maxRank = tonumber(line.maxLevel) or tonumber(maxRank)
        f.trackStringID = sid
        f.upgradeText = text
      end
    elseif t == LINE_BINDING and text then
      f.binding = bindingFromText(text) or f.binding
      f.bindingText = text
    elseif t == LINE_ONUSE or t == LINE_ONPROC then
      f.hasEffect = true
    elseif t == LINE_ONEQUIP and text then
      -- "Equip:" lines that are plain stat bumps are already in GetItemStats;
      -- anything else is an effect we cannot score.
      if not text:find("^Equip:%s*%+") then f.hasEffect = true end
    end
    if text and not f.cantrip and text:find("^Cantrip") then
      f.cantrip = text:gsub("^Cantrip:?%s*", "")
    end
  end
end

function Facts.IsSendable(f)
  if f.binding == "wue" or f.binding == "warband" or f.binding == "boe" then return true end
  if f.binding == "soulbound" then return false end
  if f.bound == true then return false end
  return f.bind == BIND_WARBAND_UNTIL_EQUIPPED or f.bind == BIND_WARBAND or f.bind == BIND_ON_EQUIP
end

-- link: item link. loc: ItemLocation or nil. tooltipFn: returns tooltip data.
function Facts.Build(link, loc, tooltipFn)
  if type(link) ~= "string" then return nil end
  local name, _, quality, ilvlBase, reqLevel, _, _, _, equipLoc, icon, sellPrice, classID, subclassID, bindType, _, setID = C_Item.GetItemInfo(link)
  if not name then return nil, "uncached" end

  local ilvl = C_Item.GetDetailedItemLevelInfo(link) or ilvlBase or 0
  local raw = C_Item.GetItemStats(link)
  local stats, flex = ns.Stats.Normalize(raw)
  stats, flex = ns.Stats.NormalizeForArmor(stats, flex, classID, subclassID, equipLoc)

  local f = {
    link = link, name = name, quality = quality or 0, ilvl = ilvl, reqLevel = reqLevel or 0,
    equipLoc = equipLoc, icon = icon, sellPrice = sellPrice or 0,
    classID = classID, subclassID = subclassID, bind = bindType,
    stats = stats, flex = flex, setID = setID,
    isTier = (setID ~= nil and setID ~= 0),
    id = tonumber(link:match("item:(%d+)")),
  }

  if loc and loc.IsValid and loc:IsValid() then
    f.guid = C_Item.GetItemGUID(loc)
    f.bound = C_Item.IsBound(loc)
    if C_Item.IsItemConvertibleAndValidForPlayer then
      f.catalystEligible = C_Item.IsItemConvertibleAndValidForPlayer(loc) and true or false
    end
  end

  if tooltipFn then
    local ok, data = pcall(tooltipFn)
    if ok then Facts.ReadTooltip(f, data) end
  end
  -- A link with no location (a vault offer, a roll window) cannot be
  -- asked about the catalyst. Infer it: a non-tier piece in a tier slot
  -- on a current-season track converts in practice. Marked as inferred.
  if f.catalystEligible == nil and f.track and not f.isTier then
    local slots = ns.Slots.BY_EQUIPLOC[f.equipLoc]
    if slots and ns.Season.tierSlots[slots[1]] then
      f.catalystEligible, f.catalystAssumed = true, true
    end
  end
  f.sendable = Facts.IsSendable(f)
  return f
end

function Facts.FromBag(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or not info.hyperlink then return nil end
  local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
  return Facts.Build(info.hyperlink, loc, function() return C_TooltipInfo.GetBagItem(bag, slot) end)
end

function Facts.FromEquipped(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return nil end
  local loc = ItemLocation:CreateFromEquipmentSlot(slot)
  return Facts.Build(link, loc, function() return C_TooltipInfo.GetInventoryItem("player", slot) end)
end

function Facts.FromLink(link)
  return Facts.Build(link, nil, function() return C_TooltipInfo.GetHyperlink(link) end)
end

-- Compact copy for snapshots: enough for the engine, nothing transient.
function Facts.Compact(f)
  if not f then return nil end
  return {
    link = f.link, name = f.name, ilvl = f.ilvl, equipLoc = f.equipLoc,
    classID = f.classID, subclassID = f.subclassID, stats = f.stats, flex = f.flex,
    isTier = f.isTier, setID = f.setID, track = f.track, rank = f.rank, maxRank = f.maxRank,
    icon = f.icon, quality = f.quality, gems = f.gems, sockets = f.sockets, id = f.id,
  }
end

function Facts.IsCandidate(f, prefs)
  if not f then return false end
  if not ns.Slots.IsEquippable(f.equipLoc) then return false end
  if (f.quality or 0) < (prefs.minQuality or 3) then return false end
  return true
end
