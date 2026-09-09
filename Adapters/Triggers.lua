-- Event wiring: pickup detection, wake inputs, safe-moment notifications.
-- Wake events are registered only while something depends on them.
local ADDON, ns = ...

local Triggers = {}
ns.Triggers = Triggers

local Guard = ns.Guard
local frame = CreateFrame("Frame")
local known = {}
local seeded = false
local pendingUncached = {}
local queue = {}
local timers = {}
local wakeState = {}
local INTERACTION = Enum and Enum.PlayerInteractionType or {}

local function debounce(key, delay, fn)
  if timers[key] then timers[key]:Cancel() end
  timers[key] = C_Timer.NewTimer(delay, Guard.Wrap(function()
    timers[key] = nil
    fn()
  end))
end

function Triggers.IsSafe()
  if InCombatLockdown() or UnitAffectingCombat("player") then return false end
  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then return false end
  if IsEncounterInProgress and IsEncounterInProgress() then return false end
  return true
end

local function flush()
  if #queue == 0 or not Triggers.IsSafe() then return end
  local prefs = ns.DB.Prefs()
  for i = 1, #queue do
    local n = queue[i]
    if prefs.chat and n.text then ns.Print(n.text) end
    if prefs.toast and n.toast and ns.Toast then ns.Toast.Show(n.toast) end
  end
  for i = #queue, 1, -1 do queue[i] = nil end
end

-- n = { text = "...", toast = { icon, headline, line, quality } }
function Triggers.Notify(n)
  queue[#queue + 1] = n
  flush()
end

local function headlineColor(v)
  return ns.Style and ns.Style.VerdictColor(v) or "ffffff"
end

-- The toast row for a verdict. compare: how many equipped pieces the
-- item's tooltip will be compared against (two for rings, trinkets and
-- one-handers), so the toast can leave room for them. altKey: for a
-- send, whose gear those comparisons show instead of this character's.
local function toastFor(entry)
  local f, v = entry.facts, entry.verdict
  local slots = ns.Slots.BY_EQUIPLOC[f.equipLoc]
  return {
    icon = f.icon, headline = ns.Engine.Headline(v), line = ns.Engine.BriefLine(v, ns.Style and ns.Style.GAIN_HEX) or v.reason, quality = f.quality,
    verdict = v, facts = f, link = f.link, compare = (type(slots) == "table" and #slots > 1) and 2 or 1,
    altKey = ns.Verdicts.SendKey(v), equipLoc = f.equipLoc,
  }
end

-- chatOnly: a scan repeats what the panel already shows, so it never
-- toasts. The toast is for what just landed.
local function announce(entry, prefixWord, chatOnly)
  local f, v = entry.facts, entry.verdict
  local head = ns.Engine.Headline(v)
  local text = string.format("|cff%s%s|r %s: %s", headlineColor(v), head, f.link or f.name, v.reason)
  if prefixWord then text = prefixWord .. " " .. text end
  Triggers.Notify({ text = text, toast = (not chatOnly) and toastFor(entry) or nil })
end

local function want(event, flag)
  if flag and not wakeState[event] then frame:RegisterEvent(event); wakeState[event] = true end
  if not flag and wakeState[event] then frame:UnregisterEvent(event); wakeState[event] = nil end
end

-- A bank is open: its closing matters until it happens.
function Triggers.WatchBankClose()
  want("BANKFRAME_CLOSED", true)
end

-- Which wake events matter right now, from the persisted holds.
function Triggers.SyncWakeEvents()
  local me = ns.Character.Key()
  local needCurrency, needBank, needVendor, needUpgrade, needLevel = false, false, false, false, false
  for _, h in pairs(ns.db.holds) do
    if h.owner == me then
      -- Ready holds keep watching: crests spent elsewhere make them wait again.
      if h.kind == "HOLD" and (h.sub == "upgrade" or h.sub == "catalyst" or h.sub == "instead") then needCurrency = true end
      if h.kind == "SEND" then needBank = true end
      if h.kind == "HOLD" and (h.sub == "upgrade" or h.sub == "instead") then needUpgrade = true end
      if h.kind == "HOLD" and h.sub == "level" then needLevel = true end
    end
  end
  -- Something under way to this character: the bank matters here too.
  if next(ns.Verdicts.SendsForMe()) ~= nil then needBank = true end
  if next(ns.Verdicts.SessionDispose()) ~= nil then needVendor = true end

  want("CURRENCY_DISPLAY_UPDATE", needCurrency)
  want("BANKFRAME_OPENED", needBank)
  want("BANKFRAME_CLOSED", needBank or (ns.Bank and ns.Bank.IsOpen()))
  want("MERCHANT_SHOW", needVendor)
  want("PLAYER_LEVEL_UP", needLevel)
  want("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", needBank or needUpgrade or ns.db.probe.watch)
end

-- Re-run the holds and say what changed. A new hold can outclass an old
-- one, and a hold leaving the bags can free a piece it had outclassed.
local function reevaluate(prefixWord)
  for _, t in ipairs(ns.Verdicts.ReevaluateHolds()) do
    announce({ facts = t.facts, verdict = t.verdict }, prefixWord)
  end
end

local function evaluateSlots(list, prefixWord)
  local newHold = false
  for _, s in ipairs(list) do
    local entry, why = ns.Verdicts.ForBag(s.bag, s.slot, true)
    if entry then
      ns.Verdicts.SyncHold(entry.facts, entry.verdict)
      if ns.Journal then ns.Journal.Drop(entry) end
      announce(entry, prefixWord)
      if entry.verdict.kind == ns.Engine.KIND.HOLD then newHold = true end
    elseif why == "uncached" and s.guid then
      pendingUncached[s.guid] = s
      frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    end
  end
  if newHold then reevaluate("Update:") end
  Triggers.SyncWakeEvents()
end

-- Diff bag GUIDs against what we have seen. New GUIDs are pickups; a held
-- item that is no longer there is a departure worth a re-evaluation.
local present = {}
local function scanBags()
  local found, now = {}, {}
  for bag = 0, 4 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc:IsValid() then
          local guid = C_Item.GetItemGUID(loc)
          if guid then
            now[guid] = true
            if not known[guid] then
              known[guid] = true
              if seeded then found[#found + 1] = { bag = bag, slot = slot, guid = guid } end
            end
          end
        end
      end
    end
  end
  local gone = false
  local me = ns.Character.Key()
  for guid in pairs(present) do
    local h = not now[guid] and ns.db.holds[guid]
    if h and h.owner == me then gone = true end
  end
  present = now
  return found, gone
end

-- The open panel follows along; hidden, this costs a function call.
local function refreshPanel()
  if ns.Panel then ns.Panel.Refresh() end
end

local function onBagUpdate()
  local found, gone = scanBags()
  if #found > 0 then evaluateSlots(found) end
  if gone then
    reevaluate("Update:")
    Triggers.SyncWakeEvents()
  end
  if ns.Bank.IsOpen() then ns.Bank.OnBagUpdate() end
  refreshPanel()
end

-- Worn gear the client had not loaded yet leaves holes in the snapshot,
-- and every verdict against a hole says the slot is empty. The snapshot
-- asks the client to call back as each missing item loads; this runs
-- then. Still incomplete, the new build has asked again; whole, rebuild
-- the picture and re-run everything that was judged against the holes.
local wornRebuilds = 0
local function checkWorn()
  if not ns.Character.Self().incomplete then return end
  ns.Character.Invalidate()
  if ns.Character.Self().incomplete then return end
  wornRebuilds = wornRebuilds + 1
  ns.Log("info", "worn gear read whole after item data arrived; verdicts re-run")
  ns.Verdicts.InvalidateAll()
  ns.Character.Snapshot()
  ns.Verdicts.ScanAll()
  reevaluate("Update:")
  Triggers.SyncWakeEvents()
  refreshPanel()
end
function Triggers.CheckWorn() checkWorn() end
-- How many times this session the worn picture had to be read again;
-- /sift status shows it, so a cold start can be told from a warm one.
function Triggers.WornRebuilds() return wornRebuilds end

local function retryUncached()
  local list = {}
  for guid, s in pairs(pendingUncached) do list[#list + 1] = s end
  pendingUncached = {}
  frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
  if #list > 0 then evaluateSlots(list) end
  checkWorn()
  refreshPanel()
end

local function onInputsChanged()
  ns.Character.Invalidate()
  ns.Verdicts.InvalidateAll()
  ns.Character.Snapshot()
  reevaluate("Update:")
  Triggers.SyncWakeEvents()
  refreshPanel()
end

local function onCurrencyChanged()
  ns.Verdicts.InvalidateAll()
  local transitions = ns.Verdicts.ReevaluateHolds()
  for _, t in ipairs(transitions) do
    if t.verdict.ready then announce({ facts = t.facts, verdict = t.verdict }, "Ready:") end
  end
  Triggers.SyncWakeEvents()
  refreshPanel()
end

local function onBankOpened()
  ns.Bank.Open()
  refreshPanel()
end

local function onBankClosed()
  ns.Bank.Close()
  reevaluate("Update:")
  Triggers.SyncWakeEvents()
  refreshPanel()
end

local function remindDispose()
  local lines = {}
  for _, d in ipairs(ns.Verdicts.SessionDispose()) do
    lines[#lines + 1] = d.entry.facts.link or d.entry.facts.name
  end
  if #lines > 0 then ns.Chat("Sell or disenchant: " .. table.concat(lines, ", ")) end
end

local function remindUpgrades()
  local lines, own = {}, {}
  for _, h in ipairs(ns.Verdicts.MyHolds()) do
    if h.loc and h.hold.kind == "HOLD" and h.hold.ready then
      if h.hold.sub == "upgrade" then
        lines[#lines + 1] = h.hold.link or h.hold.name
      elseif h.hold.sub == "instead" and h.hold.instead then
        own[#own + 1] = string.format("%s to %d/%d (instead of %s)", h.hold.instead.name, h.hold.instead.rank, h.hold.instead.maxRank, h.hold.link or h.hold.name)
      end
    end
  end
  if #lines > 0 then ns.Chat("Ready to upgrade: " .. table.concat(lines, ", ")) end
  if #own > 0 then ns.Chat("Upgrade your own gear: " .. table.concat(own, ", ")) end
end

local function onInteraction(kind)
  if ns.db.probe.watch then
    ns.db.probe.interactions = ns.db.probe.interactions or {}
    ns.db.probe.interactions[tostring(kind)] = (ns.db.probe.interactions[tostring(kind)] or 0) + 1
    ns.Print("interaction type " .. tostring(kind))
  end
  if kind == INTERACTION.Banker or kind == INTERACTION.AccountBanker then onBankOpened() end
  if kind == INTERACTION.ItemUpgrade then remindUpgrades() end
end

local initialized = false
local function onEnterWorld()
  if ns.Journal then ns.Journal.Sync() end
  if initialized then flush() return end
  initialized = true
  ns.SpecScan.Load()
  C_Timer.After(3, Guard.Wrap(function()
    if ns.Specs.Source() ~= "client" then ns.SpecScan.Load() end
    scanBags()
    seeded = true
    local whole = not ns.Character.Self().incomplete
    ns.Character.Snapshot()
    ns.Resources.Discover()
    if whole then ns.Verdicts.ReevaluateHolds() end
    Triggers.SyncWakeEvents()
    if ns.Minimap then ns.Minimap.Init() end
    ns.Character.StaleNudge()
    if ns.Guide then ns.Guide.FirstRun() end
  end))
end

local handlers = {
  ADDON_LOADED = function(name)
    if name ~= ADDON then return end
    ns.DB.Init()
    if ns.Options then ns.Options.Register() end
    frame:UnregisterEvent("ADDON_LOADED")
  end,
  PLAYER_ENTERING_WORLD = onEnterWorld,
  PLAYER_LOGOUT = function() ns.Character.Snapshot() end,
  BAG_UPDATE_DELAYED = function() if seeded then debounce("bags", 0.4, onBagUpdate) end end,
  GET_ITEM_INFO_RECEIVED = function() debounce("uncached", 0.5, retryUncached) end,
  PLAYER_EQUIPMENT_CHANGED = function() if seeded then debounce("inputs", 1.0, onInputsChanged) end end,
  PLAYER_SPECIALIZATION_CHANGED = function(unit) if unit == "player" and seeded then debounce("inputs", 1.0, onInputsChanged) end end,
  PLAYER_LEVEL_UP = function() if seeded then debounce("inputs", 1.0, onInputsChanged) end end,
  CURRENCY_DISPLAY_UPDATE = function() debounce("currency", 1.5, onCurrencyChanged) end,
  BANKFRAME_OPENED = onBankOpened,
  BANKFRAME_CLOSED = onBankClosed,
  MERCHANT_SHOW = remindDispose,
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = onInteraction,
  PLAYER_REGEN_ENABLED = flush,
  CHALLENGE_MODE_COMPLETED = flush,
  CHALLENGE_MODE_START = function() if ns.Journal then ns.Journal.NewRun() end end,
  ZONE_CHANGED_NEW_AREA = flush,
}

frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then Guard.Call(h, ...) end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED",
  "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_START", "ZONE_CHANGED_NEW_AREA" }) do
  frame:RegisterEvent(e)
end

-- Manual full scan from the slash command.
function Triggers.ScanAll()
  local entries = ns.Verdicts.ScanAll()
  for _, e in ipairs(entries) do announce(e, nil, true) end
  Triggers.SyncWakeEvents()
  return #entries
end

-- Fill the toast with the bag verdicts, to place it or see it with real
-- rows. Shown even when the toast is switched off. Returns the count.
function Triggers.ShowToast()
  if not ns.Toast then return 0 end
  local entries = ns.Verdicts.ScanAll()
  Triggers.SyncWakeEvents()
  ns.Toast.Clear()
  for _, e in ipairs(entries) do ns.Toast.Show(toastFor(e)) end
  return #entries
end

function Triggers.Refresh()
  onInputsChanged()
end
