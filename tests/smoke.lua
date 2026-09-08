-- Smoke test: load every file in TOC order under a fake WoW environment and
-- drive the main paths with Guard in debug mode so any error surfaces.
-- Usage: lua5.1 tests/smoke.lua
local script = arg and arg[0] or "tests/smoke.lua"
local root = script:match("^(.*)/tests/smoke%.lua$") or "."

----------------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------------
local timers = {}
local printed = {}
local newWidget

local Widget = {}
Widget.__index = function(t, k)
  -- Real frames return nil for fields addon code sets itself (lowercase);
  -- only widget methods (CamelCase) get a stub.
  if type(k) ~= "string" or k:sub(1, 2) == "__" or k:sub(1, 1):match("%l") then return nil end
  if k == "GetHeight" or k == "GetWidth" or k == "GetStringWidth" then return function() return 100 end end
  if k == "GetLeft" or k == "GetRight" or k == "GetTop" or k == "GetBottom" then return function() return 100 end end
  if k == "GetStringHeight" then return function() return 40 end end
  if k == "GetVerticalScroll" then return function() return 0 end end
  if k == "GetAlpha" then return function() return 1 end end
  if k == "IsShown" or k == "IsVisible" then return function(self) return self.__shown end end
  if k == "Show" then return function(self) self.__shown = true end end
  if k == "Hide" then return function(self) self.__shown = false end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "IsMouseOver" then return function() return false end end
  if k == "IsForbidden" then return function() return false end end
  if k == "GetOwner" then return function(self) return self.__owner end end
  if k == "SetText" then return function(self, text) self.__text = text end end
  if k == "GetText" then return function(self) return self.__text end end
  if k == "GetFrameLevel" then return function(self) return self.__level or 1 end end
  if k == "SetShown" then return function(self, shown) self.__shown = shown and true or false end end
  if k == "SetHeight" then return function(self, h) self.__height = h end end
  if k == "SetFrameStrata" then return function(self, s) self.__strata = s end end
  if k == "SetFrameLevel" then return function(self, l) self.__level = l end end
  if k == "EnableMouse" then return function(self, on) self.__mouse = on and true or false end end
  if k == "SetPoint" then return function(self, ...) self.__point = { ... } end end
  if k == "SetChecked" then return function(self, on) self.__checked = on and true or false end end
  if k == "GetChecked" then return function(self) return self.__checked end end
  if k == "GetName" then return function(self) return self.__name end end
  if k == "CreateFontString" or k == "CreateTexture" then return function() return newWidget() end end
  if k == "SetScript" then return function(self, ev, fn) self.__scripts = self.__scripts or {}; self.__scripts[ev] = fn end end
  if k == "HookScript" then return function(self, ev, fn) self.__hooks = self.__hooks or {}; self.__hooks[ev] = self.__hooks[ev] or {}; table.insert(self.__hooks[ev], fn) end end
  if k == "GetScript" then return function(self, ev) return self.__scripts and self.__scripts[ev] end end
  if k == "RegisterEvent" then return function(self, e) self.__events = self.__events or {}; self.__events[e] = true end end
  if k == "UnregisterEvent" then return function(self, e) if self.__events then self.__events[e] = nil end end end
  if k == "GetBagID" then return function(self) return self.__bag end end
  if k == "GetID" then return function(self) return self.__slot end end
  return function() return nil end
end
newWidget = function(name) return setmetatable({ __name = name, __shown = false }, Widget) end

local eventFrames = {}
local decorateShopping -- gives a frame what ShoppingTooltipTemplate would; set below
function CreateFrame(kind, name, parent, template)
  local f = newWidget(name)
  eventFrames[#eventFrames + 1] = f
  if name then _G[name] = f end
  if template then
    f.__template = template
    if template == "ShoppingTooltipTemplate" and decorateShopping then decorateShopping(f) end
  end
  return f
end
local function fire(event, ...)
  for _, f in ipairs(eventFrames) do
    if f.__events and f.__events[event] and f.__scripts and f.__scripts.OnEvent then
      f.__scripts.OnEvent(f, event, ...)
    end
  end
end
-- Show or hide a Blizzard frame the way the client would: the frame's own
-- script first, then everything hooked onto it.
local function runHandlers(f, ev)
  if f.__scripts and f.__scripts[ev] then f.__scripts[ev](f) end
  for _, fn in ipairs(f.__hooks and f.__hooks[ev] or {}) do fn(f) end
end
local function showFrame(f) f.__shown = true; runHandlers(f, "OnShow") end
local function hideFrame(f) f.__shown = false; runHandlers(f, "OnHide") end
local function runTimers()
  local list = timers
  timers = {}
  for _, t in ipairs(list) do
    if not t.cancelled then t.fn() end
  end
end

UIParent = newWidget("UIParent")
Minimap = newWidget("Minimap")
function GetCursorPosition() return 100, 100 end
GameTooltip = newWidget("GameTooltip")
GameTooltip.__lines = {}
GameTooltip.AddLine = function(self, text) self.__lines[#self.__lines + 1] = tostring(text) end
GameTooltip.AddDoubleLine = function(self, l, r) self.__lines[#self.__lines + 1] = tostring(l) .. " " .. tostring(r) end
GameTooltip.SetHyperlink = function(self, l) self.__link = l end
GameTooltip.SetOwner = function(self, owner, anchor) self.__owner = owner; self.__anchor = anchor end
ItemRefTooltip = newWidget("ItemRefTooltip")
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, UI_EPICLOOT_TOAST = 31578 }
MinimalSliderWithSteppersMixin = { Label = { Right = 1 }, Event = { OnValueChanged = "OnValueChanged" } }
function CreateMinimalSliderFormatter(_, fn) return fn end
-- The real utility creates one texture per layout piece on the container.
NineSliceUtil = { ApplyLayout = function(container, layout)
  for name in pairs(layout) do
    if not rawget(container, name) then container[name] = newWidget() end
  end
end }
function PlaySound() end
function UIFrameFadeOut() end
function UIFrameFadeRemoveFrame() end
function ChatEdit_InsertLink() return true end
function IsShiftKeyDown() return false end

local tickers = {}
C_Timer = {
  After = function(_, fn) timers[#timers + 1] = { fn = fn } end,
  NewTimer = function(_, fn)
    local t = { fn = fn }
    t.Cancel = function() t.cancelled = true end
    timers[#timers + 1] = t
    return t
  end,
  NewTicker = function(_, fn)
    local t = { fn = fn }
    t.Cancel = function() t.cancelled = true end
    tickers[#tickers + 1] = t
    return t
  end,
}
-- Tickers run every time this is called until cancelled.
local function runTickers()
  for _, t in ipairs(tickers) do
    if not t.cancelled then t.fn() end
  end
end

Enum = {
  WeeklyRewardChestThresholdType = { None = 0, Activities = 1, RankedPvP = 2, Raid = 3, AlsoReceive = 4, Concession = 5, World = 6 },
  CachedRewardType = { None = 0, Item = 1, Currency = 2 },
  TooltipDataLineType = { ItemBinding = 20, ItemLevel = 31, ItemUpgradeLevel = 32, ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46 },
  ItemBind = { OnEquip = 2, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 },
  PlayerInteractionType = { Banker = 8, AccountBanker = 63, ItemUpgrade = 39 },
  TooltipDataType = { Item = 0 },
}

local settingsCalls = 0
local settingsDropdowns, settingsButtons = {}, {}
local settingsDefaults = {}
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  CreateControlTextContainer = function()
    local c = { data = {} }
    function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
    function c:GetData() return self.data end
    return c
  end,
  CreateDropdown = function(_, _, optionsFn) settingsCalls = settingsCalls + 1; settingsDropdowns[#settingsDropdowns + 1] = optionsFn() end,
  RegisterVerticalLayoutCategory = function() settingsCalls = settingsCalls + 1; return { GetID = function() return 7 end } end,
  RegisterAddOnSetting = function(_, _, key, _, _, _, default) settingsCalls = settingsCalls + 1; settingsDefaults[key] = default; return {} end,
  RegisterProxySetting = function(_, name, _, _, default, get, set) settingsCalls = settingsCalls + 1; settingsDefaults[name] = default; set(get()); return {} end,
  CreateCheckbox = function() settingsCalls = settingsCalls + 1 end,
  CreateSliderOptions = function() return { SetLabelFormatter = function(_, _, fn) fn(2) end } end,
  CreateSlider = function() settingsCalls = settingsCalls + 1 end,
  RegisterAddOnCategory = function() settingsCalls = settingsCalls + 1 end,
  OpenToCategory = function() settingsCalls = settingsCalls + 1 end,
}
local settingsRows = {}
function CreateSettingsButtonInitializer(name, text, onClick, tooltip)
  local init = { name = name, text = text, click = onClick, tooltip = tooltip }
  function init:AddShownPredicate(fn) self.shown = fn end
  settingsRows[#settingsRows + 1] = init
  return init
end
function CreateSettingsListSectionHeaderInitializer(name) return { header = name } end
SettingsPanel = newWidget("SettingsPanel")
GameMenuFrame = newWidget("GameMenuFrame")
SettingsPanel.GetLayout = function() return { AddInitializer = function(_, init) if init.click then settingsButtons[init.name] = init.click end end } end
function HideUIPanel(f) f.__shown = false end
function ShowUIPanel(f) f.__shown = true end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0-smoke" end }
function date(fmt) return "2026-09-07 12:00" end

-- Every item post-call registered, run in order like the client does.
local tooltipHooks = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipHooks[#tooltipHooks + 1] = fn end }
local function tooltipHook(...)
  for _, fn in ipairs(tooltipHooks) do fn(...) end
end
TooltipUtil = { GetDisplayedItem = function(tt) return "x", tt.__link, 1 end }

----------------------------------------------------------------------------
-- Items and bags
----------------------------------------------------------------------------
local ITEMS = {
  [1001] = { name = "Bracers of the Test", quality = 4, ilvl = 292, reqLevel = 80, equipLoc = "INVTYPE_WRIST", icon = 11, sell = 4000, classID = 4, subclassID = 4, bind = 9,
    stats = { ITEM_MOD_AGI_STR_INT_SHORT = 580, ITEM_MOD_STAMINA_SHORT = 880, ITEM_MOD_CRIT_RATING_SHORT = 240, ITEM_MOD_HASTE_RATING_SHORT = 230 },
    tooltip = { { type = 20, leftText = "Warbound until equipped" }, { type = 3, leftText = "+16 Mastery & +7 Haste" }, { type = 32, leftText = "Upgrade Level: Champion 9/9", currentLevel = 1, maxLevel = 6, trackStringID = 975 } } },
  [1002] = { name = "Worn Bracers", quality = 3, ilvl = 292, reqLevel = 80, equipLoc = "INVTYPE_WRIST", icon = 12, sell = 100, classID = 4, subclassID = 4, bind = 1,
    stats = { ITEM_MOD_AGI_STR_INT_SHORT = 600, ITEM_MOD_STAMINA_SHORT = 900, ITEM_MOD_CRIT_RATING_SHORT = 250, ITEM_MOD_HASTE_RATING_SHORT = 240 },
    tooltip = { { type = 20, leftText = "Soulbound" } } },
  [1003] = { name = "Chestplate of Tests", quality = 4, ilvl = 305, reqLevel = 80, equipLoc = "INVTYPE_CHEST", icon = 13, sell = 200, classID = 4, subclassID = 4, bind = 1, setID = 900,
    stats = { ITEM_MOD_AGI_STR_INT_SHORT = 1000, ITEM_MOD_STAMINA_SHORT = 1500, ITEM_MOD_CRIT_RATING_SHORT = 400, ITEM_MOD_HASTE_RATING_SHORT = 400 },
    tooltip = { { type = 20, leftText = "Soulbound" }, { type = 3, leftText = "Prismatic Socket" }, { type = 32, leftText = "Aufwertung", currentLevel = 1, maxLevel = 6, trackStringID = 975 } } },
  [1004] = { name = "Trinket of Nothing", quality = 4, ilvl = 280, reqLevel = 80, equipLoc = "INVTYPE_TRINKET", icon = 14, sell = 300, classID = 4, subclassID = 0, bind = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 500, ITEM_MOD_CRIT_RATING_SHORT = 100 },
    tooltip = { { type = 20, leftText = "Soulbound" }, { type = 3, leftText = "+32 Primary Stat" }, { type = 44, leftText = "Use: Nothing happens." } } },
  [1005] = { name = "Cloth Scraps", quality = 1, ilvl = 1, reqLevel = 1, equipLoc = "", icon = 15, sell = 1, classID = 7, subclassID = 5, bind = 0, stats = {}, tooltip = {} },
  [1006] = { name = "Hero Bracers", quality = 4, ilvl = 305, reqLevel = 80, equipLoc = "INVTYPE_WRIST", icon = 16, sell = 5000, classID = 4, subclassID = 4, bind = 1,
    stats = { ITEM_MOD_AGI_STR_INT_SHORT = 600, ITEM_MOD_STAMINA_SHORT = 900, ITEM_MOD_CRIT_RATING_SHORT = 200, ITEM_MOD_HASTE_RATING_SHORT = 290 },
    tooltip = { { type = 20, leftText = "Soulbound" }, { type = 32, leftText = "Upgrade Level: Hero 1/6", currentLevel = 1, maxLevel = 6, trackStringID = 974 } } },
  -- What the alt on file wears; its link is what the alt comparison shows.
  [1007] = { name = "Old Bracers", quality = 3, ilvl = 270, reqLevel = 70, equipLoc = "INVTYPE_WRIST", icon = 17, sell = 50, classID = 4, subclassID = 4, bind = 1,
    stats = { ITEM_MOD_AGI_STR_INT_SHORT = 300, ITEM_MOD_STAMINA_SHORT = 500, ITEM_MOD_CRIT_RATING_SHORT = 100, ITEM_MOD_HASTE_RATING_SHORT = 100 },
    tooltip = { { type = 20, leftText = "Soulbound" } } },
}
local function link(id) return string.format("|cffa335ee|Hitem:%d::::::::80:72:::::::::|h[%s]|h|r", id, ITEMS[id].name) end
local function idOf(l) return tonumber((tostring(l)):match("item:(%d+)")) end

-- Bags 0-4, and 13 is the one warband bank tab.
local bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [13] = {} }
local equipped = { [9] = { id = 1002, guid = "eq-9" }, [5] = { id = 1003, guid = "eq-5" } }
local nextGuid = 0
local function putInBag(bag, slot, id, extra)
  nextGuid = nextGuid + 1
  local c = { id = id, guid = "bag-" .. nextGuid }
  for k, v in pairs(extra or {}) do c[k] = v end
  bags[bag][slot] = c
  return c
end

C_Item = {
  GetItemInfo = function(l)
    local it = ITEMS[idOf(l)]
    if not it then return nil end
    return it.name, l, it.quality, it.ilvl, it.reqLevel, "Armor", "Plate", 1, it.equipLoc, it.icon, it.sell, it.classID, it.subclassID, it.bind, 10, it.setID, false
  end,
  GetDetailedItemLevelInfo = function(l) local it = ITEMS[idOf(l)]; return it and it.ilvl end,
  GetItemStats = function(l) local it = ITEMS[idOf(l)]; return it and it.stats end,
  GetItemGUID = function(loc) return loc.guid end,
  IsBound = function(loc) return loc.bound or false end,
  IsItemConvertibleAndValidForPlayer = function(loc) return loc.catalyst or false end,
  GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
}
-- ItemMixin for worn slots: the callback runs at once when the item's data
-- is there, otherwise it waits for loadItems().
local itemLoadWaiters = {}
Item = {
  CreateFromEquipmentSlot = function(_, slot)
    local e = equipped[slot]
    return {
      IsItemEmpty = function() return e == nil end,
      ContinueOnItemLoad = function(_, fn)
        if e and C_Item.GetItemInfo(link(e.id)) then fn() else itemLoadWaiters[#itemLoadWaiters + 1] = fn end
      end,
    }
  end,
}
local function loadItems()
  local w = itemLoadWaiters
  itemLoadWaiters = {}
  for _, fn in ipairs(w) do fn() end
end
ItemLocation = {
  CreateFromBagAndSlot = function(_, bag, slot)
    local c = bags[bag] and bags[bag][slot]
    return { IsValid = function() return c ~= nil end, guid = c and c.guid, catalyst = c and c.catalyst, bound = c and c.bound }
  end,
  CreateFromEquipmentSlot = function(_, slot)
    local e = equipped[slot]
    return { IsValid = function() return e ~= nil end, guid = e and e.guid, bound = true }
  end,
}
C_Container = {
  GetContainerNumSlots = function() return 16 end,
  GetContainerItemInfo = function(bag, slot)
    local c = bags[bag] and bags[bag][slot]
    if not c then return nil end
    return { hyperlink = link(c.id), itemID = c.id, quality = ITEMS[c.id].quality }
  end,
}
C_TooltipInfo = {
  GetBagItem = function(bag, slot) local c = bags[bag][slot]; return { lines = ITEMS[c.id].tooltip, guid = c.guid } end,
  GetInventoryItem = function(_, slot) local e = equipped[slot]; return { lines = ITEMS[e.id].tooltip, guid = e.guid } end,
  GetHyperlink = function(l) return { lines = ITEMS[idOf(l)].tooltip } end,
}
local currencies = {
  [3100] = { name = "Champion Mistcrest", quantity = 12, discovered = true, totalEarned = 100 },
  [3105] = { name = "Champion Mistcrest", quantity = 45, discovered = true, totalEarned = 500, iconFileID = 555 },
  [3101] = { name = "Hero Mistcrest", quantity = 80 },
  [3099] = { name = "Hero Mistcrest", quantity = 0, totalEarned = 300, maxQuantity = 300 },
  [3200] = { name = "Venomblight Manaflux", quantity = 1, iconFileID = 556 },
}
C_CurrencyInfo = { GetCurrencyInfo = function(id) return currencies[id] end }
C_Texture = { GetAtlasInfo = function(name) if name:find("^classicon%-") then return { name = name } end return nil end }
local vaultActivities = {}
local vaultLinks = {}
C_WeeklyRewards = {
  GetActivities = function() return vaultActivities end,
  GetItemHyperlink = function(dbid) return vaultLinks[dbid] end,
  HasAvailableRewards = function() return #vaultActivities > 0 end,
  CanClaimRewards = function() return #vaultActivities > 0 end,
  OnUIInteract = function() end,
  GetExampleRewardItemHyperlinks = function(id) return vaultLinks["example" .. id] end,
}
function GetDifficultyInfo(id) return id == 15 and "Heroic" or "Normal" end
C_ChallengeMode = { IsChallengeModeActive = function() return false end }
local CLASS_SPECS = {
  [1] = { { id = 71, name = "Arms", role = "DAMAGER", primaryStat = 1 }, { id = 72, name = "Fury", role = "DAMAGER", primaryStat = 1 }, { id = 73, name = "Protection", role = "TANK", primaryStat = 1 } },
  [12] = { { id = 577, name = "Havoc", role = "DAMAGER", primaryStat = 2 }, { id = 581, name = "Vengeance", role = "TANK", primaryStat = 2 }, { id = 1480, name = "Devourer", role = "DAMAGER", primaryStat = 4 } },
}
C_SpecializationInfo = {
  GetSpecialization = function() return 2 end,
  GetSpecializationInfo = function(i, _, _, _, _, _, classID)
    local list = CLASS_SPECS[classID or 1]
    return list and list[i] or nil
  end,
  GetNumSpecializationsForClassID = function(classID) return CLASS_SPECS[classID] and #CLASS_SPECS[classID] or 0 end,
}
function UnitName() return "Tester" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 80 end
function UnitAffectingCombat() return false end
function GetRealmName() return "Realm" end
function GetNormalizedRealmName() return "Realm" end
function GetInventoryItemLink(_, slot) local e = equipped[slot]; return e and link(e.id) end
function InCombatLockdown() return false end
function IsEncounterInProgress() return false end
function IsInInstance() return false, "none" end
function GetBuildInfo() return "12.1.0", "69587" end
function GetTime() return os.clock() end

-- Blizzard's four roll frames and the Edit Mode window exist before any
-- addon loads.
for i = 1, 4 do CreateFrame("Frame", "GroupLootFrame" .. i) end
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame")
EditModeManagerFrame.CanEnterEditMode = function() return true end
local rollLinks = {}
function GetLootRollItemLink(rollID) return rollLinks[rollID] end

-- Edit Mode announces itself through the callback registry.
EventRegistry = { __cb = {} }
function EventRegistry:RegisterCallback(ev, fn, owner)
  self.__cb[ev] = self.__cb[ev] or {}
  table.insert(self.__cb[ev], fn)
end
function EventRegistry:TriggerEvent(ev, ...)
  for _, fn in ipairs(self.__cb[ev] or {}) do fn(nil, ...) end
end

-- Blizzard's two comparison panes exist before addons load, and any
-- frame made from their template gets the same parts: a compare header
-- with a label, and a body that remembers what it was given.
function hooksecurefunc(tbl, name, fn)
  if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
  local orig = tbl[name]
  tbl[name] = function(...)
    local a, b, c = orig(...)
    fn(...)
    return a, b, c
  end
end
decorateShopping = function(t)
  t.__lines = {}
  t.CompareHeader = newWidget()
  t.CompareHeader.Label = newWidget()
  t.ClearLines = function(self) self.__lines = {}; self.__data = nil; self.CompareHeader:Hide() end
  t.SetOwner = function(self, owner, anchor) self:ClearLines(); self.__owner = owner; self.__anchor = anchor end
  t.ProcessInfo = function(self, info) self.__data = info.tooltipData; self.__append = info.append; self.__shown = true; return true end
  t.AddLine = GameTooltip.AddLine
  return t
end
CreateFrame("GameTooltip", "ShoppingTooltip1", nil, "ShoppingTooltipTemplate")
CreateFrame("GameTooltip", "ShoppingTooltip2", nil, "ShoppingTooltipTemplate")
GameTooltip.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 }
C_TooltipComparison = { GetItemComparisonDelta = function() return nil end }
ITEM_DELTA_DESCRIPTION = "If you replace this item, the following stat changes will occur:"
function GameTooltip_AddBlankLineToTooltip(t) t:AddLine(" ") end
function GameTooltip_AddNormalLine(t, s) t:AddLine(s) end
function GameTooltip_AddHighlightLine(t, s) t:AddLine(s) end
function GameTooltip_AddDisabledLine(t, s) t:AddLine(s) end
function GameTooltip_SuppressAutomaticCompareItem(t) t.suppressAutomaticCompareItem = true end
local cvars = { alwaysCompareItems = false }
function GetCVarBool(name) return cvars[name] and true or false end
function IsModifiedClick() return false end
function GetScreenWidth() return 1000 end
Enum.BankType = Enum.BankType or { Character = 0, Account = 1 }
C_Bank = { FetchPurchasedBankTabIDs = function() return { 13 } end }
time = os.time
ITEM_UPGRADE_TOOLTIP_FORMAT = "Upgrade Level: %s %d/%d"
ITEM_MOD_MASTERY_RATING_SHORT = "Mastery"
ITEM_MOD_HASTE_RATING_SHORT = "Haste"
ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike"
ITEM_MOD_VERSATILITY = "Versatility"
ITEM_BIND_TO_BNETACCOUNT_UNTIL_EQUIP = "Warbound until equipped"
ITEM_BNETACCOUNTBOUND = "Warbound"
ITEM_BIND_ON_EQUIP = "Binds when equipped"
ITEM_SOULBOUND = "Soulbound"

local realPrint = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(parts, " ")
end

----------------------------------------------------------------------------
-- Load in TOC order
----------------------------------------------------------------------------
SiftLootAdvisorDB = { prefs = { debug = true, toast = true } }
SiftLootAdvisorDB.chars = {
  ["Altie-Realm"] = { name = "Altie", realm = "Realm", classID = 1, classFile = "WARRIOR", level = 80, specIDs = { 71 }, tierCount = 0, parked = false, updated = 1,
    slots = { [9] = { name = "Old Bracers", link = link(1007), ilvl = 270, equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 4, stats = { STAMINA = 500, CRIT = 100, HASTE = 100 }, flex = { value = 300, STRENGTH = true } } } },
}
local ns = {}
local toc = assert(io.open(root .. "/SiftLootAdvisor.toc")):read("*a")
for line in toc:gmatch("[^\r\n]+") do
  if line:match("%.lua$") and not line:match("^#") then
    local rel = line:gsub("\\", "/")
    local chunk, err = loadfile(root .. "/" .. rel)
    if not chunk then error(err) end
    chunk("Sift", ns)
  end
end

----------------------------------------------------------------------------
-- Drive
----------------------------------------------------------------------------
local checks, failures = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then failures[#failures + 1] = what end
end

fire("ADDON_LOADED", "Sift")
check(ns.db ~= nil and ns.db.prefs.threshold == 0.01, "DB initialized with defaults")
check(settingsCalls > 5, "options registered")

fire("PLAYER_ENTERING_WORLD")
runTimers()
check(ns.db.chars["Tester-Realm"] ~= nil, "self snapshot written at login")
check(ns.db.season.currency.Champion == 3105, "Champion crest currency picked as the newer id among duplicates")
check(ns.db.season.candidates.Champion and #ns.db.season.candidates.Champion == 2, "both Champion candidates recorded")
check(ns.db.season.currency.Hero == 3099, "Hero pick prefers the currency with seasonal tracking over the newer untracked one")
check(ns.Resources.Current().crests.Hero == 0, "Hero crests read from the tracked currency")
check(_G.SiftLootAdvisorMinimapButton and _G.SiftLootAdvisorMinimapButton.__shown, "minimap button built and shown")

-- The guide opens once, at the first login, and pages through to Done.
check(_G.SiftLootAdvisorGuide and _G.SiftLootAdvisorGuide.__shown and ns.Guide.Page() == 1, "guide opened on the first login")
check(not ns.db.prefs.guideSeen, "guide not marked seen until it closes")
ns.Guide.Back()
check(ns.Guide.Page() == 1, "back stays on the first page")
ns.Guide.Next(); ns.Guide.Next(); ns.Guide.Next()
check(ns.Guide.Page() == 4, "three nexts reach the last page")
ns.Guide.Next()
check(not _G.SiftLootAdvisorGuide.__shown and ns.db.prefs.guideSeen == true, "Done on the last page closes the guide and marks it seen")
check(not ns.Guide.FirstRun() and not _G.SiftLootAdvisorGuide.__shown, "a seen guide does not open again at login")
ns.db.prefs.guideSeen = false
local wasLockdown = InCombatLockdown
InCombatLockdown = function() return true end
local before = #printed
check(not ns.Guide.FirstRun() and not _G.SiftLootAdvisorGuide.__shown, "in combat the first run waits")
check(#printed == before + 1 and printed[#printed]:find("/sift guide", 1, true), "and a chat line points at the guide")
InCombatLockdown = wasLockdown
check(ns.Guide.FirstRun() and _G.SiftLootAdvisorGuide.__shown, "out of combat it opens")
hideFrame(_G.SiftLootAdvisorGuide)
check(ns.db.prefs.guideSeen == true, "closing the guide any other way also marks it seen")
check(ns.db.season.currency.catalyst == 3200, "catalyst currency discovered")

-- Loot a warbound Champion 1/6 bracer that beats the worn one after upgrades.
local looted = putInBag(0, 3, 1001)
putInBag(0, 4, 1005)
fire("BAG_UPDATE_DELAYED")
runTimers()
local hold = ns.db.holds[looted.guid]
check(hold ~= nil, "hold recorded for looted bracers")
check(hold and hold.kind == "HOLD" and hold.sub == "upgrade", "looted bracers are a HOLD upgrade (" .. tostring(hold and hold.kind) .. "/" .. tostring(hold and hold.sub) .. ")")
check(hold and hold.ready == true, "hold is ready with 45 crests")
local sawChat = false
for _, p in ipairs(printed) do if p:find("Bracers of the Test", 1, true) and p:find("Upgrade", 1, true) then sawChat = true end end
check(sawChat, "chat line announced the verdict")
check(ns.db.holds[looted.guid] and (ns.db.holds[looted.guid].notes or {})[1] ~= nil, "verdict carries a note (alt or ceiling)")

-- Structured upgrade fields win over the text, and unknown text resolves through the learned id.
local looterFacts = ns.ItemFacts.FromBag(0, 3)
check(looterFacts.rank == 1 and looterFacts.maxRank == 6 and looterFacts.track == "Champion", "rank from currentLevel/maxLevel, track from text")
check(ns.db.season.trackStrings[975] == "Champion", "track string id learned from a parseable line")
local chestFacts = ns.ItemFacts.FromEquipped(5)
check(chestFacts.track == "Champion", "unparseable line resolved through learned track id")
check(chestFacts.flex and chestFacts.flex.STRENGTH and chestFacts.flex.INTELLECT and not chestFacts.stats.STRENGTH, "plate primary restored to adaptive form")
check(looterFacts.gems and looterFacts.gems.MASTERY == 16 and looterFacts.gems.HASTE == 7, "gem read from the socket line")
local trinketFacts = ns.ItemFacts.FromLink(link(1004))
check(trinketFacts.gems and trinketFacts.gems.PRIMARY == 32 and not trinketFacts.sockets, "primary stat gem read as PRIMARY")
check(chestFacts.sockets == 1 and chestFacts.gems == nil, "empty socket counted")
check(ns.Specs.Source() == "client" and ns.db.specs.summary.specs == 6, "spec registry loaded from the client (" .. tostring(ns.db.specs and ns.db.specs.summary.specs) .. ")")
check(ns.Character.Self().specs[1].id == 72 and ns.Character.Self().specs[1].source == "client", "active spec resolved through the registry")
check(#ns.Specs.Diffs() == 0, "shipped data agrees with the client stub")
check(ns.db.season.growth and ns.db.season.growth.groups ~= nil, "growth observations recorded")
check(ns.db.watermarks["Tester-Realm"] and ns.db.watermarks["Tester-Realm"].wrist == 292 and ns.db.watermarks["Tester-Realm"].chest == 305, "slot watermarks recorded from worn gear")

-- Tooltip on the bag slot.
GameTooltip.__lines = {}
GameTooltip.__owner = newWidget("ContainerFrame1Item3")
GameTooltip.__owner.__bag, GameTooltip.__owner.__slot = 0, 3
GameTooltip.__link = link(1001)
tooltipHook(GameTooltip, { guid = looted.guid })
check(#GameTooltip.__lines >= 2 and GameTooltip.__lines[1]:find("Sift", 1, true), "tooltip lines added: " .. table.concat(GameTooltip.__lines, " / "))

-- Tooltip on a bare link with no cached verdict (chat link path).
GameTooltip.__lines = {}
GameTooltip.__owner = nil
GameTooltip.__link = link(1004)
tooltipHook(GameTooltip, {})
check(#GameTooltip.__lines >= 2, "tooltip for a chat link evaluated lazily")

-- Tooltip on an equipped item must add nothing.
GameTooltip.__lines = {}
GameTooltip.__owner = newWidget("CharacterWristSlot")
GameTooltip.__link = link(1002)
tooltipHook(GameTooltip, { guid = "eq-9" })
check(#GameTooltip.__lines == 0, "no verdict on equipped items")

-- Slash commands.
local slash = SlashCmdList.SIFTLOOTADVISOR
slash("")
check(_G.SiftLootAdvisorPanel and _G.SiftLootAdvisorPanel.__shown, "panel opened")
local tools = _G.SiftLootAdvisorPanel.tools or {}
check(#tools == 3 and tools[1].name == "Settings" and tools[2].name == "Guide" and tools[3].name == "Weights", "panel header carries Settings, Guide and Weights")
tools[2].__scripts.OnClick(tools[2])
check(_G.SiftLootAdvisorGuide.__shown, "the header Guide button opens the guide")
tools[2].__scripts.OnClick(tools[2])
check(not _G.SiftLootAdvisorGuide.__shown, "and closes it again")
tools[3].__scripts.OnClick(tools[3])
check(_G.SiftLootAdvisorWeights and _G.SiftLootAdvisorWeights.__shown, "the header Weights button opens the sheet")
tools[3].__scripts.OnClick(tools[3])
check(not _G.SiftLootAdvisorWeights.__shown, "and closes it again")
slash("status")
check(ns.db.output and ns.db.output.cmd == "status" and #ns.db.output.lines >= 5, "status lines stored in SavedVariables")
slash("status copy")
check(_G.SiftLootAdvisorCopy and _G.SiftLootAdvisorCopy.__shown, "status copy box opened")
_G.SiftLootAdvisorCopy.__shown = false
slash("copy")
check(_G.SiftLootAdvisorCopy.__shown, "/sift copy reopens the last output")
_G.SiftLootAdvisorCopy.__shown = false
slash("scan")
slash("weights ( Pawn: v1: \"Smoke\": Class=Warrior, Spec=Fury, Strength=1.00, CritRating=0.5, HasteRating=0.6 )")
check(ns.cdb.imported[72] ~= nil, "weights imported for Fury")
check(ns.cdb.imported[72].gear ~= nil, "import records a gear fingerprint")
local wline, wst = ns.Character.DescribeWeights()
check(wst.source == "imported" and wst.changed == 0 and not wst.stale, "fresh import is not stale: " .. wline)
ns.cdb.imported[72].ts = os.time() - 20 * 86400
check(select(2, ns.Character.DescribeWeights()).stale == true, "old import is stale")
check(ns.Character.StaleNudge() == true and ns.Character.StaleNudge() == false, "stale nudge prints once a day")
slash("weights bogus")
slash("weights clear")
check(ns.cdb.imported[72] == nil, "weights cleared")
slash("weights")
check(_G.SiftLootAdvisorWeights and _G.SiftLootAdvisorWeights.__shown, "weights sheet opened from the command")
do -- The sheet is laid out top down at one left margin, and ends where its content does.
  local w = _G.SiftLootAdvisorWeights
  local aligned, descending, lastY = true, true, 0
  for _, s in ipairs(w.steps) do
    if s.n.__point[2] ~= 14 or s.text.__point[2] ~= 36 then aligned = false end
    if s.n.__point[3] >= lastY then descending = false end
    lastY = s.n.__point[3]
  end
  check(aligned, "every step number sits at the margin and every step text 22 px in")
  check(descending, "the steps run down the sheet")
  check(w.box.__point[3] < lastY and w.result.__point[3] < w.box.__point[3], "the paste box follows the steps and the result line follows the box")
  check(w.__height == -w.result.__point[3] + 40 + 14, "the sheet ends one pad below the result line (" .. tostring(w.__height) .. ")")
end
local okImp = ns.WeightsUI.Import("( Pawn: v1: \"Sheet\": Class=Warrior, Spec=Fury, Strength=1.00, CritRating=0.5 )")
check(okImp == true and ns.cdb.imported[72] and ns.cdb.imported[72].name == "Sheet", "sheet import stored weights")
check(ns.WeightsUI.Import("") == false, "sheet refuses an empty paste")
check(ns.WeightsUI.Import("( Pawn: v1: \"Mage\": Class=Mage, Spec=Frost, Intellect=1 )") == false, "sheet refuses another class")
slash("weights clear")
slash("weights")
check(not _G.SiftLootAdvisorWeights.__shown, "weights sheet toggled closed")
slash("park")
check(ns.cdb.parked == true, "parked")
slash("park")
slash("currency Hero 3101")
check(ns.db.season.manual.Hero == 3101, "manual currency set")
slash("currency Champion 3100")
check(ns.Resources.Current().crests.Champion == 12, "manual pick overrides the discovered one")
ns.Resources.Discover(true)
check(ns.Resources.Current().crests.Champion == 12, "manual pick survives rediscovery")
slash("currency Champion 3105")
slash("probe copy")
check(ns.db.probe.last ~= nil and #ns.db.probe.last.items >= 2, "probe stored findings")
check(_G.SiftLootAdvisorCopy.__shown and ns.db.output.cmd == "probe", "probe output captured and copy box opened")
local sawSocket = false
for _, l in ipairs(ns.db.output.lines) do if l:find("socket line on", 1, true) then sawSocket = true end end
check(sawSocket, "probe prints the socket lines it saw")
slash("probe watch")
slash("probe stop")
slash("options")
slash("help")
local function helpMentions(word)
  for _, l in ipairs(ns.db.output.lines) do if l:find(word, 1, true) then return true end end
  return false
end
check(helpMentions("/sift guide") and helpMentions("/sift feedback") and helpMentions("/sift probe"), "help lists the guide, feedback and, in debug mode, the developer commands")
ns.db.prefs.debug = false
slash("help")
check(not helpMentions("/sift probe") and not helpMentions("/sift refresh") and helpMentions("/sift status"), "developer commands leave the list when debug is off")
ns.db.prefs.debug = true
slash("guide")
check(_G.SiftLootAdvisorGuide.__shown and ns.Guide.Page() == 1, "/sift guide opens the guide on page one")
do -- Windows opened from the guide land on top of it, and settings hands the guide back.
  ns.Guide.Next(); ns.Guide.Next()
  ns.WeightsUI.Show()
  check(_G.SiftLootAdvisorWeights.__strata == _G.SiftLootAdvisorGuide.__strata and _G.SiftLootAdvisorWeights.__level >= _G.SiftLootAdvisorGuide.__level + 10,
    "the weights sheet opened from the guide shares its stratum and sits well above it")
  ns.Feedback.Show()
  check(_G.SiftLootAdvisorCopy.__strata == _G.SiftLootAdvisorGuide.__strata and _G.SiftLootAdvisorCopy.__level >= _G.SiftLootAdvisorWeights.__level + 10,
    "the feedback box sits above both")
  hideFrame(_G.SiftLootAdvisorCopy)
  local sheetLevel = _G.SiftLootAdvisorWeights.__level
  ns.Guide.Show(3)
  check(_G.SiftLootAdvisorGuide.__level >= sheetLevel + 10, "the guide shown again goes back in front of the open sheet")
  hideFrame(_G.SiftLootAdvisorWeights)
  ns.WeightsUI.Show(); hideFrame(_G.SiftLootAdvisorWeights)
  ns.WeightsUI.Show()
  check(_G.SiftLootAdvisorWeights.__level == _G.SiftLootAdvisorGuide.__level + 10, "levels are measured from what is open, not from a counter")
  hideFrame(_G.SiftLootAdvisorWeights)
  local before = settingsCalls
  ns.Guide.Aside(ns.Options.Open)
  check(not _G.SiftLootAdvisorGuide.__shown and settingsCalls == before + 1, "Open settings from the guide hides the guide and opens settings")
  SettingsPanel.__shown = true
  hideFrame(SettingsPanel)
  GameMenuFrame.__shown = true
  runTimers()
  check(not _G.SiftLootAdvisorGuide.__shown, "while the game menu that Escape leaves behind is up, the guide waits")
  hideFrame(GameMenuFrame)
  runTimers()
  check(_G.SiftLootAdvisorGuide.__shown and ns.Guide.Page() == 3, "once the menu closes the guide is back on the same page")
  hideFrame(SettingsPanel); runTimers()
  check(ns.Guide.Page() == 3, "a later settings close does not reopen or reset it")
  local solid = true
  for _, name in ipairs({ "SiftLootAdvisorGuide", "SiftLootAdvisorWeights", "SiftLootAdvisorCopy" }) do
    local d = _G[name]
    if not (d.__mouse and d.__scripts.OnDragStart and d.__scripts.OnDragStop) then solid = false end
  end
  check(solid, "every dialog takes the mouse and can be dragged, so clicks never fall through to the one beneath")
end
slash("guide")
check(not _G.SiftLootAdvisorGuide.__shown, "/sift guide again closes it")
slash("feedback")
local report = ns.CopyBox.Text() or ""
check(_G.SiftLootAdvisorCopy.__shown and report:find("Sift 1.0.0-smoke, game 12.1.0 (69587)", 1, true), "/sift feedback opens the report in the copy box with the versions")
check(report:find(ns.Feedback.URL, 1, true) and report:find("settings: chat", 1, true) and report:find("Tester, ", 1, true), "the report carries where to paste it, the settings and the status lines")
check(report:find("catalyst from Champion", 1, true), "the report names the catalyst minimum")
_G.SiftLootAdvisorCopy.__shown = false
local trackOptions = settingsDropdowns[1] or {}
check(#trackOptions == 6 and trackOptions[1].label == "Any track" and trackOptions[4].value == "Champion", "the catalyst minimum is a dropdown of every track plus any")
check(settingsButtons["Stat weights"] and settingsButtons["The guide"] and settingsButtons["Place the toast"] and settingsButtons["Send feedback"], "settings carries doors to the sheet, the guide, Edit Mode and feedback")
SettingsPanel.__shown = true
settingsButtons["Stat weights"]()
check(not SettingsPanel.__shown and _G.SiftLootAdvisorWeights.__shown, "the weights door leaves settings and opens the sheet")
do -- The command reference: one row per command, developer rows only with debug on, the button runs it.
  local rows, dev, user = {}, 0, 0
  for _, r in ipairs(settingsRows) do
    if r.name:find("^/sift") then
      rows[r.name:match("^/sift ?([%w ]*)"):gsub("%s+$", "")] = r
      if r.shown then dev = dev + 1 else user = user + 1 end
    end
  end
  local missing = {}
  for cmd in pairs(ns.Commands) do
    if cmd ~= "help" and cmd ~= "options" then
      local found = false
      for name in pairs(rows) do if name == cmd or name:find("^" .. cmd .. " ") then found = true end end
      if not found then missing[#missing + 1] = cmd end
    end
  end
  check(#missing == 0, "every command has a row on the settings page (missing: " .. table.concat(missing, ", ") .. ")")
  check(user == 12 and dev == 4, "twelve player rows and four developer rows (" .. user .. "/" .. dev .. ")")
  -- The Defaults button restores what ships, not what was set at login
  -- (debug was on in this world from the start).
  check(settingsDefaults.debug == false and settingsDefaults.toast == true and settingsDefaults.sound == false and settingsDefaults.parked == false,
    "checkboxes register the shipped defaults, not the values at login")
  check(settingsDefaults.SIFT_threshold == 1 and settingsDefaults.SIFT_minQuality == 3 and settingsDefaults.SIFT_catalystMinTrack == "Champion" and settingsDefaults.SIFT_minimap == true,
    "sliders, the dropdown and the minimap switch register the shipped defaults too")
  check(ns.DB.Default("toast") == true and ns.DB.Default("sound") == false and ns.DB.Default("parked", true) == false, "DB.Default reads the shipped tables")
  local probe = rows["probe"]
  local debugWas = ns.db.prefs.debug
  ns.db.prefs.debug = false
  local hiddenOff = probe and probe.shown() == false
  ns.db.prefs.debug = true
  local shownOn = probe and probe.shown() == true
  ns.db.prefs.debug = debugWas
  check(hiddenOff and shownOn, "developer rows follow the debug setting")
  local before = #printed
  rows["status"].click()
  check(#printed > before and printed[before + 1]:find("Sift", 1, true) == nil or #printed > before, "the status row runs the command (" .. (#printed - before) .. " lines)")
  local wasShown = _G.SiftLootAdvisorWeights.__shown
  _G.SiftLootAdvisorWeights.__shown = false
  SettingsPanel.__shown = true
  rows["weights"].click()
  check(not SettingsPanel.__shown and _G.SiftLootAdvisorWeights.__shown, "a row that opens a window leaves settings first")
  _G.SiftLootAdvisorWeights.__shown = wasShown
end
_G.SiftLootAdvisorWeights.__shown = false
settingsButtons["Place the toast"]()
check(EditModeManagerFrame.__shown, "the toast door opens Edit Mode")
EditModeManagerFrame.__shown = false
settingsButtons["Send feedback"]()
check(_G.SiftLootAdvisorCopy.__shown, "the feedback door builds the report")
_G.SiftLootAdvisorCopy.__shown = false
slash("refresh")
runTimers()
ns.db.prefs.panelSize = { w = 720, h = 500 }
ns.Panel.Refresh()
ns.db.prefs.panelSize = nil
ns.Panel.Refresh()
slash("")
check(not _G.SiftLootAdvisorPanel.__shown, "panel toggled closed")

-- Minimap button: clicks, tooltip, drag.
local mm = _G.SiftLootAdvisorMinimapButton
mm.__scripts.OnClick(mm, "LeftButton")
check(_G.SiftLootAdvisorPanel.__shown, "minimap left-click opens the panel")
mm.__scripts.OnClick(mm, "LeftButton")
local before = settingsCalls
mm.__scripts.OnClick(mm, "RightButton")
check(settingsCalls > before, "minimap right-click opens settings")
mm.__scripts.OnEnter(mm)
mm.__scripts.OnLeave(mm)
mm.__scripts.OnDragStart(mm)
if mm.__scripts.OnUpdate then mm.__scripts.OnUpdate(mm) end
mm.__scripts.OnDragStop(mm)
ns.db.prefs.minimap = false
ns.Minimap.Refresh()
check(not mm.__shown, "minimap button hides when the option is off")
ns.db.prefs.minimap = true
ns.Minimap.Refresh()

-- Wake inputs: crests drop to zero, hold should flip to not ready.
currencies[3105].quantity = 0
fire("CURRENCY_DISPLAY_UPDATE")
runTimers()
check(ns.db.holds[looted.guid] and ns.db.holds[looted.guid].ready == false, "hold flipped to waiting after crests changed")

-- Bank, vendor, upgrade NPC and spec change.
fire("BANKFRAME_OPENED")
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 63)
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 39)
fire("BANKFRAME_CLOSED")
fire("MERCHANT_SHOW")
fire("PLAYER_EQUIPMENT_CHANGED", 9)
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
runTimers()
fire("PLAYER_REGEN_ENABLED")
fire("ZONE_CHANGED_NEW_AREA")

-- Item leaves the bags: hold is dropped on the next re-evaluation.
bags[0][3] = nil
fire("PLAYER_EQUIPMENT_CHANGED", 9)
runTimers()
check(ns.db.holds[looted.guid] == nil, "hold dropped after item left bags")

-- Held items compete. A Hero bracer that wins at max ranks outclasses the
-- Champion hold: Dispose while no alt wants it, Send once one does. When
-- the winner leaves the bags, the hold comes back.
local function sawLine(a, b)
  for _, p in ipairs(printed) do if p:find(a, 1, true) and p:find(b, 1, true) then return true end end
  return false
end
ns.db.chars["Altie-Realm"].parked = true
ns.Character.InvalidateAlts()
local champ = putInBag(0, 6, 1001)
fire("BAG_UPDATE_DELAYED")
runTimers()
check(ns.db.holds[champ.guid] and ns.db.holds[champ.guid].kind == "HOLD", "champion bracers held again")
local heroBracers = putInBag(0, 5, 1006)
fire("BAG_UPDATE_DELAYED")
runTimers()
local heroHold = ns.db.holds[heroBracers.guid]
check(heroHold and heroHold.kind == "HOLD", "hero bracers held (" .. tostring(heroHold and heroHold.kind) .. "/" .. tostring(heroHold and heroHold.sub) .. ")")
check(ns.db.holds[champ.guid] == nil, "champion hold dropped once outclassed")
local outclassed = ns.Verdicts.Get(champ.guid)
check(outclassed and outclassed.verdict.kind == "DISPOSE" and outclassed.verdict.flags.outclassed, "champion bracers now a dispose flagged outclassed")
check(outclassed and outclassed.verdict.reason:find("Outclassed by Hero Bracers in your bags", 1, true) ~= nil, "dispose reason names the held winner: " .. tostring(outclassed and outclassed.verdict.reason))
check(sawLine("Update:", "Outclassed by Hero Bracers in your bags"), "chat announced the update")
-- An alt comes back into play: the dead end is still worth sending.
ns.db.chars["Altie-Realm"].parked = false
ns.Character.InvalidateAlts()
fire("PLAYER_EQUIPMENT_CHANGED", 9)
runTimers()
local sent = ns.db.holds[champ.guid]
check(sent and sent.kind == "SEND", "outclassed warbound piece becomes a send when an alt wants it")
check(sent and table.concat(sent.notes or {}, " "):find("Outclassed by Hero Bracers for you", 1, true) ~= nil, "send carries the outclassed note")
-- The send's "Equipped" panes show Altie's bracers, not this character's:
-- the hold remembers whom, the panel row carries it, and when the row's
-- tooltip shows an item Blizzard's automatic comparison is held off and
-- Sift's own panes come up from Altie's snapshot, with Sift's own stat
-- changes when the client gives none.
check(sent and sent.targetKey == "Altie-Realm" and sent.equipLoc == "INVTYPE_WRIST", "send hold remembers which character and slot it is for")
check(ns.Verdicts.SendKey({ kind = "SEND", target = { char = { key = "Altie-Realm" } } }) == "Altie-Realm"
  and ns.Verdicts.SendKey({ kind = "HOLD", target = { char = { key = "Altie-Realm" } } }) == nil, "only a send points at a character")
local panelWasShown = ns.Panel.IsShown()
if panelWasShown then ns.Panel.Refresh() else ns.Panel.Toggle() end
local sendRow, plainRow
for i = 1, 40 do
  local r = ns.Panel.Row(i)
  if r and r.__shown then
    if r.siftAltCompare and r.siftAltCompare.key == "Altie-Realm" then sendRow = sendRow or r
    elseif r.link then plainRow = plainRow or r end
  end
end
check(sendRow ~= nil and sendRow.siftAltCompare.equipLoc == "INVTYPE_WRIST", "panel send row is tagged with the alt and slot")
check(plainRow ~= nil and plainRow.siftAltCompare == nil, "other rows carry no tag")
cvars.alwaysCompareItems = true
ShoppingTooltip1.__shown = true
local function hoverRow(row)
  row.__scripts.OnEnter(row)
  tooltipHook(GameTooltip, { hyperlink = row.link })
  local p = ns.AltCompare.Pane(1)
  return p and table.concat(p.__lines, "\n") or ""
end
local paneText = hoverRow(sendRow)
local pane1 = ns.AltCompare.Pane(1)
check(GameTooltip.suppressAutomaticCompareItem == true, "Blizzard's automatic comparison is held off for a tagged row")
check(not ShoppingTooltip1.__shown, "Blizzard's own panes are put down for a tagged row")
check(pane1 and pane1.__shown and pane1.__template == "ShoppingTooltipTemplate", "Sift's first pane is up, built from Blizzard's template")
check(pane1.CompareHeader.__shown and pane1.CompareHeader.Label.__text == "Equipped on Altie", "pane header names the alt (" .. tostring(pane1.CompareHeader.Label.__text) .. ")")
check(pane1.__data and pane1.__data.lines == ITEMS[1007].tooltip and pane1.__append == true, "pane body is the alt's own item link, appended under the header")
check(paneText:find(ITEM_DELTA_DESCRIPTION, 1, true) ~= nil and paneText:find("+380|r Stamina", 1, true) ~= nil
  and paneText:find("+140|r Critical Strike", 1, true) ~= nil and paneText:find("+280|r Primary stat", 1, true) ~= nil
  and paneText:find("+130|r Haste", 1, true) ~= nil, "stat changes computed by Sift when the client gives none, flex primaries on one line:\n" .. paneText)
check(paneText:find("As seen on Altie", 1, true) ~= nil and paneText:find("days ago", 1, true) ~= nil, "an old snapshot says how old it is")
check(pane1.__point and pane1.__point[1] == "LEFT" and pane1.__point[2] == GameTooltip and pane1.__point[3] == "RIGHT", "one pane, beside the tooltip on the right (" .. tostring(pane1.__point and pane1.__point[1]) .. ")")
check(ns.AltCompare.Pane(2) == nil, "no second pane built for a one-slot piece")
hideFrame(GameTooltip)
check(not pane1.__shown, "panes go down with the tooltip")
C_TooltipComparison.GetItemComparisonDelta = function(a, b) return { "|cff00ff00+1|r Haste (client " .. tostring(idOf(a.hyperlink)) .. ">" .. tostring(idOf(b.hyperlink)) .. ")" } end
paneText = hoverRow(sendRow)
check(paneText:find("(client 1001>1007)", 1, true) ~= nil and paneText:find("+380|r Stamina", 1, true) == nil, "the client's own delta is used when it computes one")
C_TooltipComparison.GetItemComparisonDelta = function() return nil end
ns.db.chars["Altie-Realm"].updated = os.time()
paneText = hoverRow(sendRow)
check(paneText:find("As seen on", 1, true) == nil, "a fresh snapshot needs no age line")
ns.db.chars["Altie-Realm"].updated = 1
ns.AltCompare.Tag(sendRow, "Altie-Realm", "INVTYPE_CHEST")
hoverRow(sendRow)
check(not pane1.__shown, "an empty slot on the alt shows no pane rather than this character's piece")
ns.AltCompare.Tag(sendRow, "Nobody-Realm", "INVTYPE_WRIST")
hoverRow(sendRow)
check(not pane1.__shown, "a character no longer on file shows no pane")
ns.AltCompare.Tag(sendRow, "Altie-Realm", "INVTYPE_WRIST")
cvars.alwaysCompareItems = false
hoverRow(sendRow)
check(not pane1.__shown and GameTooltip.suppressAutomaticCompareItem == true, "compare setting off and no Shift: no panes, Blizzard's still held off")
cvars.alwaysCompareItems = true
hoverRow(sendRow)
check(pane1.__shown, "panes back with the setting")
hoverRow(plainRow)
check(not pane1.__shown and GameTooltip.suppressAutomaticCompareItem == false, "an untagged row takes the panes down and gives Blizzard its comparison back")
plainRow.__scripts.OnLeave(plainRow)
check(#ns.AltCompare.StatLines({ stats = { INTELLECT = 10, HASTE = 5 } }, { stats = { INTELLECT = 10, HASTE = 5 } }) == 0, "identical pieces change nothing")
check(ns.AltCompare.StatLines({ stats = { HASTE = 5 } }, { stats = { HASTE = 9, ARMOR = 3 } })[1]:find("-3|r Armor", 1, true) ~= nil, "lost stats come out red, armor first")
check(ns.AltCompare.StatLines({ flex = { value = 50 } }, { flex = { value = 40 } })[1]:find("+10|r Primary stat", 1, true) ~= nil, "two flex pieces compare on the primary")
check(ns.AltCompare.Ago(3600) == nil and ns.AltCompare.Ago(86400) == "yesterday" and ns.AltCompare.Ago(3 * 86400 + 5) == "3 days ago", "snapshot age words")
if not panelWasShown then ns.Panel.Toggle() end
do -- The open panel follows the events that change what it shows.
  local count, real = 0, ns.Panel.Refresh
  ns.Panel.Refresh = function(...) count = count + 1; return real(...) end
  fire("PLAYER_EQUIPMENT_CHANGED", 9); runTimers()
  local afterEquip = count
  fire("BAG_UPDATE_DELAYED"); runTimers()
  ns.Panel.Refresh = real
  check(afterEquip >= 1 and count > afterEquip, "an open panel refreshes after equipment and bag events (" .. afterEquip .. "/" .. count .. ")")
end
do -- Worn gear the client has not cached yet: a hole now, whole once the data lands.
  local key, slot = ns.Character.Key(), nil
  for s = 1, 17 do if equipped[s] then slot = s break end end
  local coldID, realInfo = equipped[slot].id, C_Item.GetItemInfo
  C_Item.GetItemInfo = function(l) if idOf(l) == coldID then return nil end return realInfo(l) end
  ns.Character.Invalidate()
  local me = ns.Character.Self()
  check(me.slots[slot] == nil and me.incomplete == 1, "an uncached worn piece leaves a hole and marks the snapshot incomplete")
  check(table.concat(ns.Status.Lines(), "\n"):find("(1 waiting on item data)", 1, true) ~= nil, "status says a slot is waiting on item data")
  ns.Character.Snapshot()
  check(ns.db.chars[key].slots[slot] ~= nil, "an incomplete snapshot leaves the saved one alone")
  check(#itemLoadWaiters == 1, "the hole asked the client to call back when its item loads")
  C_Item.GetItemInfo = realInfo
  loadItems(); runTimers()
  me = ns.Character.Self()
  check(me.slots[slot] ~= nil and me.incomplete == nil, "the picture is rebuilt whole when the item data arrives")
  check(ns.db.chars[key].slots[slot] ~= nil, "and the saved snapshot is whole too")
  check(ns.Triggers.WornRebuilds() == 1 and table.concat(ns.Status.Lines(), "\n"):find("re-read 1 time after item data arrived", 1, true) ~= nil,
    "status counts the re-read, so a cold start can be told from a warm one")
  -- The debug command fakes cold pieces whose data is in fact loaded, so
  -- the callbacks run at once and only the deferral stands between the
  -- holes and the rebuild.
  local worn = 0
  for s = 1, 17 do if equipped[s] then worn = worn + 1 end end
  slash("probe cold")
  check(ns.Character.Self().incomplete == math.min(3, worn), "probe cold leaves holes (" .. tostring(ns.Character.Self().incomplete) .. " of " .. worn .. " worn)")
  for _ = 1, 4 do runTimers() end
  check(ns.Character.Self().incomplete == nil and ns.Triggers.WornRebuilds() == 2, "the load callbacks rebuild the picture, no clock involved")
end
-- A send has a life: suggested until Tester says "Will send" or the item
-- turns up in a warband tab, then banked until Altie picks it up. The
-- bank reminder lands on the toast and leaves as items move.
local function groupOf(key)
  for _, g in ipairs(ns.Panel.Groups()) do if g.key == key then return g end end
end
local function rowIn(group, guid)
  for _, r in ipairs(group and group.items or {}) do if r.guid == guid then return r end end
end
local function saidLately(text)
  for i = #printed, math.max(1, #printed - 12), -1 do
    if printed[i]:find(text, 1, true) then return true end
  end
  return false
end
ns.Toast.Clear()
local sendRow0 = rowIn(groupOf("send"), champ.guid)
check(sendRow0 and sendRow0.ackable and sendRow0.verb == "Send", "a suggested send offers Will send")
check(next(ns.Verdicts.SendsForMe()) == nil, "nothing is on its way to Tester")
check(ns.Verdicts.AckSend(champ.guid) and ns.Verdicts.SendState(ns.db.holds[champ.guid]) == "sending", "Will send marks the hold")
sendRow0 = rowIn(groupOf("send"), champ.guid)
check(sendRow0 and not sendRow0.ackable and sendRow0.verb == "Sending" and sendRow0.reason:find("^Put it in the warband bank%.") ~= nil, "a marked send says so on the panel")
check(sendRow0 and sendRow0.brief and sendRow0.brief.note == "Put it in the warband bank." and sendRow0.brief.who == "Altie", "its brief carries the step and the alt")
check(sendRow0 and sendRow0.meta:find("|A:classicon-warrior:12:12|a to Altie", 1, true) ~= nil, "the alt's class icon leads the send meta: " .. tostring(sendRow0 and sendRow0.meta))
do
  local open = ns.Panel.IsShown()
  if open then ns.Panel.Refresh() else ns.Panel.Toggle() end
  local drawn
  for i = 1, 40 do local r = ns.Panel.Row(i); if r and r.__shown and r.guid == champ.guid then drawn = r end end
  check(drawn and drawn.versus.__shown and drawn.versus.__text:match("^|cff5fd3a8%+%d+%.%d%%|r for Altie vs Old Bracers$") ~= nil, "the row draws gain, alt and versus on one line, the gain in green: " .. tostring(drawn and drawn.versus.__text))
  check(drawn and drawn.reason.__shown and drawn.reason.__text == "Put it in the warband bank.", "and the step as the muted note")
  if not open then ns.Panel.Toggle() end
end
fire("PLAYER_EQUIPMENT_CHANGED", 9)
runTimers()
check(ns.Verdicts.SendState(ns.db.holds[champ.guid]) == "sending", "the mark survives a re-evaluation")
fire("BANKFRAME_OPENED")
check(ns.Bank.IsOpen(), "a bank opened")
check(saidLately("Deposit for alts:") and saidLately("to Altie"), "bank reminder in chat")
local depositRow
for _, e in ipairs(ns.Toast.Entries()) do if e.t.bank == "deposit" and e.t.guid == champ.guid then depositRow = e.t end end
check(depositRow ~= nil and depositRow.sticky and depositRow.headline == "Deposit" and depositRow.altKey == "Altie-Realm", "bank reminder on the toast: sticky, comparing against Altie's gear on hover")
bags[13][1] = bags[0][6]
bags[0][6] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
local bankedHold = ns.db.holds[champ.guid]
check(bankedHold and bankedHold.owner == "Tester-Realm" and ns.Verdicts.SendState(bankedHold) == "banked" and bankedHold.send.tab == 13, "the item seen in a warband tab marks the send banked")
check(saidLately("In the warband bank:"), "the deposit is announced")
local bankRows = 0
for _, e in ipairs(ns.Toast.Entries()) do if e.t.bank then bankRows = bankRows + 1 end end
check(bankRows == 0, "the deposit row leaves the toast once the item is in")
local bankedRow = rowIn(groupOf("banked"), champ.guid)
check(bankedRow and bankedRow.verb == "Waiting" and bankedRow.meta:find("for Altie$") ~= nil and bankedRow.dismissable, "the panel lists it under In the warband bank")
check(bankedRow and bankedRow.brief and bankedRow.brief.note == "In the warband bank, waiting to be picked up." and bankedRow.brief.who == "Altie", "the banked row's brief says it waits")
check(rowIn(groupOf("send"), champ.guid) == nil, "and no longer under For alts")
fire("BANKFRAME_CLOSED")
runTimers()
check(not ns.Bank.IsOpen() and ns.db.holds[champ.guid] ~= nil and ns.Verdicts.SendState(ns.db.holds[champ.guid]) == "banked", "a banked send outlives the bank session and the item's absence from the bags")
-- As Altie.
UnitName = function() return "Altie" end
ns.Character.Invalidate()
ns.Character.InvalidateAlts()
check(ns.Verdicts.SendsForMe()[champ.guid] ~= nil, "Altie sees the send on its way")
local heldRow = rowIn(groupOf("held"), champ.guid)
check(heldRow and heldRow.verb == "Waiting" and heldRow.meta:find("warband bank$") ~= nil and heldRow.reason:find("^From Tester, waiting in the warband bank: ") ~= nil and not heldRow.dismissable,
  "Altie's panel says it is waiting in the warband bank, from Tester (" .. tostring(heldRow and heldRow.reason) .. ")")
ns.Triggers.SyncWakeEvents()
fire("BANKFRAME_OPENED")
check(saidLately("Waiting for you in the warband bank:"), "Altie's bank reminder names the pickup")
local pickupRow
for _, e in ipairs(ns.Toast.Entries()) do if e.t.bank == "pickup" and e.t.guid == champ.guid then pickupRow = e.t end end
check(pickupRow ~= nil and pickupRow.headline == "Pick up" and pickupRow.sticky, "pickup row on the toast")
bags[0][6] = bags[13][1]
bags[13][1] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
local after = ns.db.holds[champ.guid]
check(after == nil or after.owner == "Altie-Realm", "picked up: Altie's own verdict takes over (" .. tostring(after and after.kind) .. ")")
bankRows = 0
for _, e in ipairs(ns.Toast.Entries()) do if e.t.bank then bankRows = bankRows + 1 end end
check(bankRows == 0, "the pickup row leaves the toast")
fire("BANKFRAME_CLOSED")
runTimers()
-- Back as Tester: the item is in the bags again, so it is a plain suggestion.
UnitName = function() return "Tester" end
ns.Character.Invalidate()
ns.Character.InvalidateAlts()
local fresh = ns.Verdicts.ForBag(0, 6, true)
if fresh then ns.Verdicts.SyncHold(fresh.facts, fresh.verdict) end
ns.Triggers.SyncWakeEvents()
check(ns.db.holds[champ.guid] and ns.db.holds[champ.guid].kind == "SEND" and ns.Verdicts.SendState(ns.db.holds[champ.guid]) == "suggested", "back with Tester it is a plain suggestion again")
ns.db.prefs.bankReminder = false
fire("BANKFRAME_OPENED")
bankRows = 0
for _, e in ipairs(ns.Toast.Entries()) do if e.t.bank then bankRows = bankRows + 1 end end
check(bankRows == 0 and saidLately("Deposit for alts:"), "reminder off: chat line only")
fire("BANKFRAME_CLOSED")
runTimers()
ns.db.prefs.bankReminder = true
ns.Toast.Clear()
-- The probe says what the client shows of the tabs.
fire("BANKFRAME_OPENED")
slash("probe bank")
check(saidLately("tab ids: 13") and saidLately("tab 13: 16 slots, 0 items") and saidLately("not in the tabs"), "probe bank reports the tabs and the sends")
fire("BANKFRAME_CLOSED")
runTimers()
-- Tabs the client will not read: an item that left the bags while the
-- bank was open is taken as deposited rather than dropped.
local realTabs = C_Bank.FetchPurchasedBankTabIDs
C_Bank.FetchPurchasedBankTabIDs = function() return {} end
fire("BANKFRAME_OPENED")
bags[13][2] = bags[0][6]
bags[0][6] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
fire("BANKFRAME_CLOSED")
runTimers()
local assumed = ns.db.holds[champ.guid]
check(assumed and ns.Verdicts.SendState(assumed) == "banked" and assumed.send.tab == nil and saidLately("could not be read"), "unreadable tabs: the send is taken as deposited, and says so")
C_Bank.FetchPurchasedBankTabIDs = realTabs
bags[0][6] = bags[13][2]
bags[13][2] = nil
fire("BANKFRAME_OPENED")
fire("BAG_UPDATE_DELAYED")
runTimers()
fire("BANKFRAME_CLOSED")
runTimers()
check(ns.db.holds[champ.guid] and ns.db.holds[champ.guid].kind == "SEND" and ns.Verdicts.SendState(ns.db.holds[champ.guid]) == "suggested", "back in the bags with readable tabs: a plain suggestion again")
ns.Toast.Clear()
-- The warband bank may hand an item a new GUID on the way in and again on
-- the way out. The record follows the item by link into the bank, and
-- the pickup under a third GUID retires it.
check(ns.Bank.LinkKey(link(1001)) == ns.Bank.LinkKey("|cffa335ee|Hitem:1001::::::::32:62:::::::::|h[Bracers of the Test]|h|r")
  and ns.Bank.LinkKey(link(1001)) ~= ns.Bank.LinkKey(link(1006)), "link keys ignore the viewer's level and spec but not the item")
fire("BANKFRAME_OPENED")
bags[13][3] = { id = 1001, guid = "bank-new" }
bags[0][6] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
check(ns.db.holds[champ.guid] == nil and ns.db.holds["bank-new"] ~= nil and ns.Verdicts.SendState(ns.db.holds["bank-new"]) == "banked"
  and ns.db.holds["bank-new"].owner == "Tester-Realm", "a deposit under a new GUID is matched by link and the record moves to it")
check(saidLately("In the warband bank:"), "and is announced")
fire("BANKFRAME_CLOSED")
runTimers()
UnitName = function() return "Altie" end
ns.Character.Invalidate()
ns.Character.InvalidateAlts()
check(ns.Verdicts.SendsForMe()["bank-new"] ~= nil, "Altie sees it waiting under the bank's GUID")
ns.Triggers.SyncWakeEvents()
fire("BANKFRAME_OPENED")
bags[13][3] = nil
bags[0][6] = { id = 1001, guid = "alt-new" }
fire("BAG_UPDATE_DELAYED")
runTimers()
check(ns.db.holds["bank-new"] == nil, "picked up under yet another GUID: the bank record retires")
fire("BANKFRAME_CLOSED")
runTimers()
ns.db.holds["alt-new"] = nil
UnitName = function() return "Tester" end
ns.Character.Invalidate()
ns.Character.InvalidateAlts()
bags[0][6] = champ
fresh = ns.Verdicts.ForBag(0, 6, true)
if fresh then ns.Verdicts.SyncHold(fresh.facts, fresh.verdict) end
ns.Triggers.SyncWakeEvents()
check(ns.db.holds[champ.guid] and ns.db.holds[champ.guid].kind == "SEND", "back with Tester under the original GUID")
ns.Toast.Clear()

-- The winner leaves: the champion hold is restored.
bags[0][5] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
check(ns.db.holds[heroBracers.guid] == nil, "hero hold dropped after it left the bags")
local back = ns.db.holds[champ.guid]
check(back and back.kind == "HOLD" and back.sub == "upgrade", "champion hold restored after the winner left (" .. tostring(back and back.kind) .. "/" .. tostring(back and back.sub) .. ")")
check(sawLine("Update:", "Beats Worn Bracers"), "chat announced the restored hold")
slash("scan")
check(ns.db.holds[champ.guid] and ns.db.holds[champ.guid].kind == "HOLD", "scan keeps the restored hold")
check(ns.db.holds[champ.guid].gain ~= nil, "hold records carry the gain the panel sorts by")
-- Panel groups run best to worst by that gain.
local ordered, scored = true, 0
for _, g in ipairs(ns.Panel.Groups()) do
  if g.key ~= "vault" then
    for i = 2, #g.items do
      local a, b = g.items[i - 1].gain, g.items[i].gain
      if b ~= nil and (a == nil or a < b) then ordered = false end
    end
    for _, r in ipairs(g.items) do if r.gain then scored = scored + 1 end end
  end
end
check(ordered and scored > 0, "panel rows run best to worst within each group (" .. scored .. " scored)")

-- Rows read as a gain column, a versus line and a muted note; the vendor
-- group folds into a header that says what it holds.
local wasOpen = ns.Panel.IsShown()
if wasOpen then ns.Panel.Refresh() else ns.Panel.Toggle() end
local briefRows, gainRow, noteRow = 0, nil, nil
for i = 1, 40 do
  local r = ns.Panel.Row(i)
  if r and r.__shown and r.versus.__shown then
    briefRows = briefRows + 1
    if (r.versus.__text or ""):match("^|cff%x+[+-]%d+%.%d%%|r vs ") then gainRow = gainRow or r end
    if r.reason.__shown and (r.reason.__text or "") ~= "" then noteRow = noteRow or r end
  end
end
check(briefRows > 0 and gainRow ~= nil, "panel rows open with the gain in its sign's color, then the versus text (" .. briefRows .. " brief rows)")
local upgradeHold = ns.db.holds[champ.guid]
check(upgradeHold and upgradeHold.brief and upgradeHold.brief.when and upgradeHold.brief.when:find("^after ") ~= nil and upgradeHold.track == "Champion",
  "hold records carry the brief and the track (" .. tostring(upgradeHold and upgradeHold.brief and upgradeHold.brief.when) .. ")")
local champRow = rowIn(groupOf("wait"), champ.guid) or rowIn(groupOf("now"), champ.guid)
check(champRow and champRow.meta:find("|T555:0|t", 1, true) ~= nil, "the crest icon leads the hold meta: " .. tostring(champRow and champRow.meta))
-- Four old bracers land: four dispose rows, more than the group shows open.
for slot = 10, 13 do putInBag(0, slot, 1007) end
fire("BAG_UPDATE_DELAYED")
runTimers()
local vendor = groupOf("vendor")
check(vendor and vendor.toggles and vendor.total == 200 and #vendor.items == 4, "vendor group carries its total (" .. tostring(vendor and #vendor.items) .. " rows, " .. tostring(vendor and vendor.total) .. "c)")
local function disposeRowsShown()
  local n = 0
  for i = 1, 40 do local r = ns.Panel.Row(i); if r and r.__shown and r.verb.__text == "Dispose" then n = n + 1 end end
  return n
end
local function vendorHeader()
  for i = 1, 12 do local h = ns.Panel.Header(i); if h and h.__shown and h.text.__text == "Vendor or disenchant" then return h end end
end
ns.Panel.Refresh()
local vh = vendorHeader()
check(vh and vh.toggles and not vh.open and disposeRowsShown() == 0, "four dispose rows fold by default")
ns.db.prefs.vendorOpen = false
ns.Panel.Refresh()
vh = vendorHeader()
check(vh and vh.toggles and not vh.open and (vh.count.__text or ""):find("piece", 1, true) and (vh.count.__text or ""):find("Show", 1, true), "a closed vendor group counts its pieces and gold and offers Show: " .. tostring(vh and vh.count.__text))
check(disposeRowsShown() == 0, "its rows stay hidden")
vh.__scripts.OnClick(vh)
check(ns.db.prefs.vendorOpen == true and disposeRowsShown() == #vendor.items, "clicking the header opens it and remembers (" .. disposeRowsShown() .. " rows)")
do
  local red = 0
  for i = 1, 40 do
    local r = ns.Panel.Row(i)
    if r and r.__shown and r.verb.__text == "Dispose" and (r.versus.__text or ""):find("^|cffe07b74%-%d") then red = red + 1 end
  end
  check(red == #vendor.items, "dispose rows open with the gain in red (" .. red .. " of " .. #vendor.items .. ")")
end
vh = vendorHeader()
check(vh and vh.open and (vh.count.__text or ""):find("Hide", 1, true), "an open vendor group offers Hide")
ns.db.prefs.vendorOpen = nil
for slot = 10, 12 do bags[0][slot] = nil end
fire("BAG_UPDATE_DELAYED")
runTimers()
ns.Panel.Refresh()
check(disposeRowsShown() == 1 and vendorHeader() and vendorHeader().open, "with no preference a short vendor list stays open")
bags[0][13] = nil
fire("BAG_UPDATE_DELAYED")
runTimers()
if not wasOpen then ns.Panel.Toggle() end

-- Opening the panel evaluates the bags quietly: a piece that landed without
-- an event is on it, and chat says nothing. The reminders that follow obey
-- the chat setting.
do
  bags[0][13] = nil
  local wasShown = ns.Panel.IsShown()
  local function bracers()
    local n = 0
    for _, it in ipairs((groupOf("vendor") or {}).items or {}) do if it.name == "Old Bracers" then n = n + 1 end end
    return n
  end
  if wasShown then ns.Panel.Toggle() end
  ns.Panel.Toggle()
  local none = bracers()
  ns.Panel.Toggle()
  putInBag(0, 14, 1007)
  local before = #printed
  ns.Panel.Toggle()
  check(none == 0 and _G.SiftLootAdvisorPanel.__shown and bracers() == 1, "opening the panel picks up a piece that landed without an event (" .. none .. " -> " .. bracers() .. ")")
  check(#printed == before, "and says nothing in chat about it")
  local chatWas = ns.db.prefs.chat
  ns.db.prefs.chat = false
  fire("MERCHANT_SHOW")
  check(#printed == before, "with chat off a vendor visit prints no reminder")
  ns.db.prefs.chat = true
  fire("MERCHANT_SHOW")
  check(#printed == before + 1 and printed[#printed]:find("Sell or disenchant", 1, true) ~= nil, "with chat on it prints the sell reminder")
  ns.db.prefs.chat = chatWas
  bags[0][14] = nil
  if not wasShown then ns.Panel.Toggle() end
end

-- Great Vault: the window loads on demand, Sift hooks it, ranks the offers.
WeeklyRewardsFrame = CreateFrame("Frame", "WeeklyRewardsFrame")
fire("ADDON_LOADED", "Blizzard_WeeklyRewards")
vaultLinks = { db1 = link(1003), db2 = link(1006), db3 = link(1004) }
vaultActivities = {
  { type = 6, index = 1, level = 8, threshold = 2, progress = 2, rewards = { { type = 1, id = 1003, quantity = 1, itemDBID = "db1" } } },
  { type = 1, index = 1, level = 10, threshold = 1, progress = 1, rewards = { { type = 1, id = 1006, quantity = 1, itemDBID = "db2" } } },
  { type = 3, index = 1, level = 15, threshold = 2, progress = 2, rewards = { { type = 1, id = 1004, quantity = 1, itemDBID = "db3" } } },
  { type = 3, index = 2, level = 15, threshold = 4, progress = 1, rewards = {} },
}
WeeklyRewardsFrame.__shown = true
ns.Vault.OnShow()
runTimers()
local ranked, headline = ns.Vault.Current()
check(ranked and #ranked == 3, "vault read three offers (" .. tostring(ranked and #ranked) .. ")")
check(ranked and ranked[1].name == "Hero Bracers" and ranked[1].source == "Mythic+ 10", "hero bracers ranked first from Mythic+ 10")
check(headline and headline:find("Take Hero Bracers (Mythic+ 10)", 1, true) ~= nil, "vault headline: " .. tostring(headline))
check(ranked and ranked[3].source == "Raid Heroic" and ranked[3].verdict.kind == "DISPOSE", "intellect trinket from Raid Heroic is last, a dispose for a warrior")
check(_G.SiftLootAdvisorVault and _G.SiftLootAdvisorVault.__shown, "vault strip shown under the vault window")
check(sawLine("Great Vault:", "Take Hero Bracers"), "vault pick announced in chat once")
GameTooltip.__lines = {}
GameTooltip.__owner = newWidget("VaultItem")
GameTooltip.__owner.displayedItemDBID = "db2"
GameTooltip.__link = link(1006)
tooltipHook(GameTooltip, { id = 1006 })
check(table.concat(GameTooltip.__lines, " / "):find("Great Vault: take this one", 1, true) ~= nil, "vault item tooltip carries the pick: " .. table.concat(GameTooltip.__lines, " / "))
slash("")
check(_G.SiftLootAdvisorPanel.__shown, "panel open with the vault group")
slash("")
slash("vault")
check(ns.db.output.cmd == "vault" and #ns.db.output.lines == 4, "/sift vault prints the headline and three lines (" .. tostring(#ns.db.output.lines) .. ")")
check(ns.db.watermarks["Tester-Realm"].wrist == 305, "a vault offer does not raise the slot watermark")
WeeklyRewardsFrame.__shown = false
ns.Vault.OnHide()
check(not _G.SiftLootAdvisorVault.__shown and ns.Vault.Current() == nil, "vault strip hidden and ranking cleared on close")
ns.db.prefs.vault = false
WeeklyRewardsFrame.__shown = true
ns.Vault.OnShow()
check(not _G.SiftLootAdvisorVault.__shown, "vault advice off when the option is off")
ns.db.prefs.vault = true
-- Claimed already: slots earned, nothing on offer. The preview stands in
-- with example items; the concession row is never a pick.
vaultLinks = { example301 = link(1006), example302 = link(1003) }
vaultActivities = {
  { type = 6, index = 1, level = 11, threshold = 2, progress = 8, rewards = {}, id = 301 },
  { type = 6, index = 2, level = 11, threshold = 4, progress = 8, rewards = {}, id = 302 },
  { type = 6, index = 3, level = 11, threshold = 8, progress = 8, rewards = {}, id = 303 },
  { type = 3, index = 1, level = 14, threshold = 2, progress = 1, rewards = {}, id = 304 },
  { type = 5, index = 2, level = 0, threshold = 3, progress = 9, rewards = { { type = 2, id = 3444, quantity = 1 } }, id = 305 },
}
ns.Vault.OnShow()
runTimers()
check(not _G.SiftLootAdvisorVault.__shown, "nothing on offer keeps the strip hidden")
slash("vault preview")
local out = table.concat(ns.db.output.lines, " ")
local plain = out:gsub("|c%x+", ""):gsub("|r", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
check(plain:find("Preview: example items", 1, true) ~= nil and plain:find("Take [Hero Bracers] (Delves tier 11)", 1, true) ~= nil, "preview ranks the example items: " .. plain)
check(_G.SiftLootAdvisorVault.__shown, "preview strip shown under the vault window")
local pr = ns.Vault.Current()
check(pr and #pr == 2, "unearned raid slot and concession row are not previewed (" .. tostring(pr and #pr) .. ")")
WeeklyRewardsFrame.__shown = false
ns.Vault.OnHide()

-- Loot rolls: a Need/Greed window opens on the hero bracers and Sift's
-- word sits beside it. The strip goes with the window.
rollLinks[7] = link(1006)
GroupLootFrame1.rollID = 7
showFrame(GroupLootFrame1)
local advice = ns.LootRollUI.Current(GroupLootFrame1)
check(advice and advice.word == "Need", "roll strip says Need for the hero bracers (" .. tostring(advice and advice.word) .. ")")
check(advice and advice.line ~= "" and not advice.line:find("^Hold%.") and not advice.line:find("^Equip%."), "roll strip line drops the verdict word: " .. tostring(advice and advice.line))
rollLinks[8] = link(1004)
GroupLootFrame2.rollID = 8
showFrame(GroupLootFrame2)
local a2 = ns.LootRollUI.Current(GroupLootFrame2)
check(a2 and a2.word == "Pass" and a2.kind == "DISPOSE", "roll strip says Pass for the intellect trinket (" .. tostring(a2 and a2.word) .. ")")
rollLinks[9] = link(1005)
GroupLootFrame3.rollID = 9
showFrame(GroupLootFrame3)
check(ns.LootRollUI.Current(GroupLootFrame3) == nil, "no roll strip for something that is not gear")
rollLinks[10] = "|cffa335ee|Hitem:9999::::::::80:72:::::::::|h[Unknown]|h|r"
GroupLootFrame4.rollID = 10
showFrame(GroupLootFrame4)
check(ns.LootRollUI.Current(GroupLootFrame4) == nil and ns.LootRoll.Count() == 4, "an uncached roll item waits for its data")
fire("GET_ITEM_INFO_RECEIVED")
runTimers()
check(ns.LootRollUI.Current(GroupLootFrame4) == nil, "still nothing to show for an item the client never resolves")
for i = 1, 4 do hideFrame(_G["GroupLootFrame" .. i]) end
check(ns.LootRollUI.Current(GroupLootFrame1) == nil and ns.LootRoll.Count() == 0, "roll strips gone with the roll windows")
ns.db.prefs.lootRoll = false
showFrame(GroupLootFrame1)
check(ns.LootRollUI.Current(GroupLootFrame1) == nil, "roll advice off when the option is off")
hideFrame(GroupLootFrame1)
ns.db.prefs.lootRoll = true
check(ns.db.watermarks["Tester-Realm"].wrist == 305, "a roll does not raise the slot watermark")

-- Toast stack: rows arrive, a page shows a few, the wheel scrolls the
-- rest, the oldest page leaves together on its clock, hovering pauses
-- it and shows the item tooltip, a click dismisses one, shift-click
-- links instead.
ns.db.prefs.toast = true
ns.db.prefs.toastRows = 2
ns.db.prefs.sound = true
local chimes = {}
PlaySound = function(id) chimes[#chimes + 1] = id end
ns.Toast.Clear()
local realGetTime = GetTime
local clock = 1000
GetTime = function() return clock end
ns.Toast.Show({ headline = "Equip", link = link(1001), line = "a", verdict = { kind = "EQUIP" } })
ns.Toast.Show({ headline = "Hold", link = link(1003), line = "b", verdict = { kind = "HOLD" } })
ns.Toast.Show({ headline = "Send", link = link(1006), line = "c", verdict = { kind = "SEND" } })
check(_G.SiftLootAdvisorToast.__shown and ns.Toast.Count() == 3 and ns.Toast.Visible() == 2 and ns.Toast.Overflow() == 1, "three verdicts stack, two on the page, one waiting")
check(#chimes == 1 and chimes[1] == SOUNDKIT.UI_EPICLOOT_TOAST, "one chime per burst, the loot-toast sound (" .. #chimes .. ")")
ns.db.prefs.sound = false
do local pt = _G.SiftLootAdvisorToast.__point; check(pt and pt[1] == "TOP" and pt[3] == "TOP" and pt[5] == -200, "the toast starts top center, under the error text") end
check(_G.SiftLootAdvisorToast.__strata == _G.SiftLootAdvisorPanel.__strata and (_G.SiftLootAdvisorToast.__level or 1) >= (_G.SiftLootAdvisorPanel.__level or 1) + 10,
  "the toast sits well above the panel in the same stratum")
check(_G.SiftLootAdvisorToast.footer.__shown and _G.SiftLootAdvisorToast.footer.__text == "1-2 of 3", "footer counts the page: " .. tostring(_G.SiftLootAdvisorToast.footer.__text))
local thumb = _G.SiftLootAdvisorToast.thumb
check(thumb.__shown and thumb.__height and thumb.__height < 92 and thumb.__point[5] == -6, "thumb shown at the top of the track, two thirds of it tall (" .. tostring(thumb.__height) .. ")")
_G.SiftLootAdvisorToast.__scripts.OnMouseWheel(_G.SiftLootAdvisorToast, -1)
check(ns.Toast.First() == 2 and _G.SiftLootAdvisorToast.footer.__text == "2-3 of 3", "wheel down scrolls to the later rows on a stack growing down")
check(thumb.__point[5] < -6, "thumb moves down the track with the page (" .. tostring(thumb.__point[5]) .. ")")
_G.SiftLootAdvisorToast.__scripts.OnMouseWheel(_G.SiftLootAdvisorToast, -1)
check(ns.Toast.First() == 2, "scrolling stops at the end")
_G.SiftLootAdvisorToast.__scripts.OnMouseWheel(_G.SiftLootAdvisorToast, 1)
check(ns.Toast.First() == 1, "wheel up scrolls back")
GameTooltip.__link = nil
ns.Toast.Row(1).__scripts.OnEnter(ns.Toast.Row(1))
check(GameTooltip.__link == link(1001), "hovering a row shows the item tooltip")
-- Where it goes depends on room for the equipped comparisons: beside the
-- toast when they fit, above or below it when they do not.
check(GameTooltip.__anchor == "ANCHOR_PRESERVE", "no room beside a toast on a tiny screen: tooltip goes above or below (" .. tostring(GameTooltip.__anchor) .. ")")
ns.Toast.Row(1).__scripts.OnLeave(ns.Toast.Row(1))
UIParent.GetRight = function() return 2000 end
ns.Toast.Row(1).__scripts.OnEnter(ns.Toast.Row(1))
check(GameTooltip.__anchor == "ANCHOR_RIGHT", "room on the right for tooltip and one comparison: beside the toast")
ns.Toast.Row(1).__scripts.OnLeave(ns.Toast.Row(1))
ns.Toast.Entries()[1].t.compare = 2
UIParent.GetRight = function() return 1000 end
ns.Toast.Row(1).__scripts.OnEnter(ns.Toast.Row(1))
check(GameTooltip.__anchor == "ANCHOR_PRESERVE", "two comparisons that would not fit beside it: above or below instead")
ns.Toast.Row(1).__scripts.OnLeave(ns.Toast.Row(1))
UIParent.GetRight = nil
clock = 1003
runTickers()
check(ns.Toast.Count() == 3, "nothing leaves before its time")
clock = 1006
runTickers()
check(ns.Toast.Count() == 1 and ns.Toast.Visible() == 1 and ns.Toast.First() == 1, "the oldest page leaves together and the waiting row gets its turn (" .. ns.Toast.Count() .. ")")
check(not thumb.__shown, "thumb gone once everything fits")
clock = 1007
_G.SiftLootAdvisorToast.IsMouseOver = function() return true end
runTickers()
clock = 1020
runTickers()
check(ns.Toast.Count() == 1, "hovering pauses the clock")
_G.SiftLootAdvisorToast.IsMouseOver = nil
clock = 1021
runTickers()
check(ns.Toast.Count() == 1, "time under the cursor did not count")
clock = 1026
runTickers()
runTimers()
check(ns.Toast.Count() == 0 and not _G.SiftLootAdvisorToast.__shown, "the last page leaves and the toast goes")
clock = 1100
ns.Toast.Show({ headline = "Equip", link = link(1001), line = "a", verdict = { kind = "EQUIP" } })
clock = 1104
ns.Toast.Show({ headline = "Hold", link = link(1003), line = "b", verdict = { kind = "HOLD" } })
clock = 1106
runTickers()
check(ns.Toast.Count() == 2, "a row landing on a page with room restarts its clock, so a burst reads as one page")
clock = 1109
runTickers()
runTimers()
check(ns.Toast.Count() == 0, "and the page leaves together")
ns.Toast.Show({ headline = "Equip", link = link(1001), line = "a", verdict = { kind = "EQUIP" } })
IsShiftKeyDown = function() return true end
ns.Toast.Row(1).__scripts.OnClick(ns.Toast.Row(1))
check(ns.Toast.Count() == 1, "shift-click links the item and keeps the row")
IsShiftKeyDown = function() return false end
ns.Toast.Row(1).__scripts.OnClick(ns.Toast.Row(1))
runTimers()
check(ns.Toast.Count() == 0 and not _G.SiftLootAdvisorToast.__shown, "a click dismisses the row")
ns.db.prefs.toastGrow = "up"
ns.Toast.Show({ headline = "Equip", link = link(1001), line = "a", verdict = { kind = "EQUIP" } })
ns.Toast.Show({ headline = "Hold", link = link(1003), line = "b", verdict = { kind = "HOLD" } })
ns.Toast.Show({ headline = "Send", link = link(1006), line = "c", verdict = { kind = "SEND" } })
check(thumb.__shown and thumb.__point[5] < -20, "growing up, the thumb starts low: the end of the queue is at the top (" .. tostring(thumb.__point[5]) .. ")")
_G.SiftLootAdvisorToast.__scripts.OnMouseWheel(_G.SiftLootAdvisorToast, 1)
check(ns.Toast.GrowsUp() and ns.Toast.First() == 2, "on a stack growing up, wheel up shows the later rows")
check(thumb.__point[5] == -20, "and the thumb rises to the top of the track (" .. tostring(thumb.__point[5]) .. ")")
-- A bag scan repeats the panel and never toasts; /sift toast fills the
-- toast with the bag verdicts on purpose, even with the toast off.
ns.Toast.Clear()
slash("scan")
check(ns.Toast.Count() == 0, "a bag scan does not toast")
ns.db.prefs.toast = false
slash("toast")
check(ns.Toast.Count() > 0 and _G.SiftLootAdvisorToast.__shown and ns.db.output.lines[1]:find("shown anyway", 1, true) ~= nil, "/sift toast fills the toast with bag verdicts (" .. ns.Toast.Count() .. ")")
ns.db.prefs.toast = true
ns.db.prefs.toastGrow = "down"
ns.Toast.Clear()
-- Sticky rows (bank reminders) sit out the clock and leave on request.
clock = 2000
ns.Toast.Show({ headline = "Deposit", link = link(1001), line = "for Altie", verdict = { kind = "SEND" }, sticky = true, bank = "deposit", guid = "g1" })
ns.Toast.Show({ headline = "Hold", link = link(1003), line = "b", verdict = { kind = "HOLD" } })
clock = 2006
runTickers()
check(ns.Toast.Count() == 1 and ns.Toast.Entries()[1].t.sticky and not ns.Toast.HasClock(), "the clock takes the ordinary row and leaves the sticky one")
check(ns.Toast.Remove(function(t) return t.bank == "deposit" and t.guid == "g1" end) == 1 and ns.Toast.Count() == 0, "a sticky row leaves when asked")
ns.Toast.Clear()
GetTime = realGetTime
ns.db.prefs.toastRows = 3

-- Edit Mode: with the toast on, it stands in as a placeholder dressed
-- like a Blizzard system: hover glow and "Click to Edit", click to select
-- and open its dialog, drag to move, settings applied live.
ns.db.prefs.toast = true
EventRegistry:TriggerEvent("EditMode.Enter")
check(_G.SiftLootAdvisorToast and _G.SiftLootAdvisorToast.__shown and ns.Toast.IsEditing() and ns.EditMode.IsActive(), "toast placeholder shown in Edit Mode")
check(ns.Toast.Count() == ns.Toast.RowsShown(), "placeholder shows one full page of sample rows")
local sys = ns.EditMode.Systems()[1]
check(sys and sys.overlay and sys.overlay.__shown and sys.overlay.kit == "editmode-actionbar-highlight", "selection overlay up with Blizzard's highlight kit")
sys.overlay.__scripts.OnEnter(sys.overlay)
check(sys.overlay.glow.__shown and sys.overlay.label.__shown and sys.overlay.label.__text == "Click to Edit", "hover shows the glow and Click to Edit")
sys.overlay.__scripts.OnLeave(sys.overlay)
check(not sys.overlay.glow.__shown and not sys.overlay.label.__shown, "leaving clears the glow and the label")
sys.overlay.__scripts.OnDragStop(sys.overlay)
check(ns.db.prefs.toastPos and ns.db.prefs.toastPos.point == "TOP" and ns.db.prefs.toastPos.relPoint == "BOTTOMLEFT", "toast position saved on drop, pinned at its top edge")
sys.overlay.__scripts.OnMouseDown(sys.overlay)
local dlg = ns.EditMode.Dialog()
check(ns.EditMode.Selected() == sys and sys.overlay.kit == "editmode-actionbar-selected" and sys.overlay.label.__text == "Sift Toast", "click selects the toast and names it")
check(dlg and dlg.__shown and dlg.title.__text == "Sift Toast" and #dlg.rows == 4 and #dlg.buttons == 1, "settings dialog opens with four rows and a button")
dlg.rows[1].apply(5)
check(ns.db.prefs.toastRows == 5 and ns.Toast.Count() == 5, "rows per page applies live to the placeholder")
dlg.rows[2].apply(9)
check(ns.db.prefs.toastSeconds == 9, "seconds shown applies")
dlg.rows[3].apply("up")
check(ns.db.prefs.toastGrow == "up" and ns.db.prefs.toastPos.point == "BOTTOM", "growing up re-pins the toast at its bottom edge")
dlg.rows[4].control.__scripts.OnClick(dlg.rows[4].control)
check(ns.db.prefs.sound == (dlg.rows[4].control.__checked or false), "sound checkbox writes the pref")
dlg.buttons[1].__scripts.OnClick(dlg.buttons[1])
check(ns.db.prefs.toastPos == nil, "reset button puts the toast back")
ns.Toast.Show({ headline = "Equip", line = "x", verdict = { kind = "EQUIP" } })
check(_G.SiftLootAdvisorToast.__shown and ns.Toast.IsEditing() and ns.Toast.Count() == 5, "a verdict does not replace the placeholder while editing")
dlg.close.__scripts.OnClick(dlg.close)
check(ns.EditMode.Selected() == nil and not dlg.__shown and sys.overlay.kit == "editmode-actionbar-highlight", "closing the dialog deselects")
EventRegistry:TriggerEvent("EditMode.Exit")
check(not _G.SiftLootAdvisorToast.__shown and not ns.Toast.IsEditing() and not sys.overlay.__shown and not ns.EditMode.IsActive(), "toast placeholder and overlay hidden when Edit Mode closes")
ns.db.prefs.toastRows, ns.db.prefs.toastSeconds, ns.db.prefs.toastGrow, ns.db.prefs.sound = 3, 5, "down", false
ns.db.prefs.toast = false
EventRegistry:TriggerEvent("EditMode.Enter")
check(not _G.SiftLootAdvisorToast.__shown and not sys.overlay.__shown, "toast stays out of Edit Mode when it is off")
-- The docked Sift panel lists it anyway, so it can be turned on from here.
local panel = ns.EditModePanel.Frame()
check(panel and panel.__shown and #panel.rows == 1 and panel.rows[1].label.__text == "Toast" and not panel.rows[1].button.__checked, "Sift panel docked beside the Edit Mode window with the toast unticked")
panel.rows[1].button.__checked = true
panel.rows[1].button.__scripts.OnClick(panel.rows[1].button)
check(ns.db.prefs.toast == true and _G.SiftLootAdvisorToast.__shown and sys.overlay.__shown, "ticking Toast in the panel turns it on and shows the placeholder")
sys.overlay.__scripts.OnMouseDown(sys.overlay)
panel.rows[1].button.__checked = false
panel.rows[1].button.__scripts.OnClick(panel.rows[1].button)
check(ns.db.prefs.toast == false and not _G.SiftLootAdvisorToast.__shown and not sys.overlay.__shown and ns.EditMode.Selected() == nil and not dlg.__shown, "unticking hides it again and closes its dialog")
EventRegistry:TriggerEvent("EditMode.Exit")
check(not panel.__shown, "the panel goes with Edit Mode")

-- Every slash command is written up, and nothing written up is missing.
local doc = assert(io.open(root .. "/docs/COMMANDS.md")):read("*a")
for name in pairs(ns.Commands) do
  check(doc:find("\n### /sift " .. name .. "\n", 1, true) ~= nil, "docs/COMMANDS.md documents /sift " .. name)
end
for name in doc:gmatch("\n### /sift (%w+)\n") do
  check(ns.Commands[name] ~= nil or name == "copy", "documented /sift " .. name .. " exists")
end

-- Public API and logout.
check(SiftLootAdvisor.Evaluate(link(1001)) ~= nil, "public SiftLootAdvisor.Evaluate returns a verdict")
check(SiftLootAdvisor.Evaluate(link(1005)) == nil, "public SiftLootAdvisor.Evaluate ignores junk")
fire("PLAYER_LOGOUT")

realPrint(string.format("%d checks, %d failed, %d chat lines", checks, #failures, #printed))
for _, f in ipairs(failures) do realPrint("  FAIL " .. f) end
if os.getenv("SIFT_SMOKE_VERBOSE") then for _, p in ipairs(printed) do realPrint("  chat: " .. p) end end
os.exit(#failures == 0 and 0 or 1)
