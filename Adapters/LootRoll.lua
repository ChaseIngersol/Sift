-- Group loot rolls: when a Need, Greed, Pass window opens, read the item
-- behind it and hand the verdict to the roll strip. Blizzard keeps four
-- roll frames (GroupLootFrame1..4) that exist before any addon loads;
-- each is hooked once and the strip lives beside it.
local ADDON, ns = ...

local LootRoll = {}
ns.LootRoll = LootRoll

local Guard = ns.Guard
local frame = CreateFrame("Frame")
local active = {}      -- roll frame -> { rollID, link, retries, done }
local timer
local hooked = false
local MAX_RETRIES = 6
local NUM_FRAMES = 4

local function enabled()
  return ns.DB.Prefs().lootRoll ~= false
end

-- Returns true when settled (a strip is up, or there is nothing to show),
-- false when the item's data has not arrived yet.
local function evaluate(rollFrame)
  local st = active[rollFrame]
  if not st then return true end
  st.link = st.link or GetLootRollItemLink(st.rollID)
  if not st.link then return false end
  local entry, why = ns.Verdicts.ForLink(st.link)
  if not entry then return why ~= "uncached" end
  local advice = ns.Roll.Advice(entry.verdict)
  if advice and ns.LootRollUI then
    ns.LootRollUI.Attach(rollFrame, {
      word = advice.word, kind = advice.kind, line = ns.Roll.Line(entry.verdict), link = st.link,
      altKey = ns.Verdicts.SendKey(entry.verdict), equipLoc = entry.facts.equipLoc,
    })
  end
  return true
end

local function retry()
  local pending = false
  for rollFrame, st in pairs(active) do
    if not st.done then
      st.done = evaluate(rollFrame)
      if not st.done then
        st.retries = st.retries + 1
        if st.retries < MAX_RETRIES then pending = true else st.done = true end
      end
    end
  end
  if not pending then frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

function LootRoll.OnShow(rollFrame)
  if not enabled() or not rollFrame.rollID then return end
  local st = { rollID = rollFrame.rollID, retries = 0 }
  active[rollFrame] = st
  st.done = evaluate(rollFrame)
  if not st.done then frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
end

function LootRoll.OnHide(rollFrame)
  active[rollFrame] = nil
  if ns.LootRollUI then ns.LootRollUI.Detach(rollFrame) end
  if next(active) == nil then frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

-- Rolls with a strip or still waiting on item data.
function LootRoll.Count()
  local n = 0
  for _ in pairs(active) do n = n + 1 end
  return n
end

frame:SetScript("OnEvent", function()
  if timer then timer:Cancel() end
  timer = C_Timer.NewTimer(0.3, Guard.Wrap(function()
    timer = nil
    retry()
  end))
end)

local function hookFrames()
  if hooked then return end
  hooked = true
  for i = 1, NUM_FRAMES do
    local f = _G["GroupLootFrame" .. i]
    if f and f.HookScript then
      f:HookScript("OnShow", Guard.Wrap(LootRoll.OnShow))
      f:HookScript("OnHide", Guard.Wrap(LootRoll.OnHide))
    end
  end
end
hookFrames()
