-- The Great Vault: read what is on offer while the vault window is open,
-- run each item through the engine, rank them. Nothing runs until the
-- vault UI loads, and the events are held only while it is shown.
local ADDON, ns = ...

local Vault = {}
ns.Vault = Vault

local Guard = ns.Guard
local frame = CreateFrame("Frame")
local hooked = false
local ranked, headline, waiting = nil, nil, false
local announced = false
local retries = 0
local timer
local MAX_RETRIES = 8

local TYPE = (Enum and Enum.WeeklyRewardChestThresholdType) or {}
local REWARD_ITEM = (Enum and Enum.CachedRewardType and Enum.CachedRewardType.Item) or 1
-- The "also receive" and concession rows are not picks.
local SKIP_TYPE = { [TYPE.AlsoReceive or 4] = true, [TYPE.Concession or 5] = true }
local preview = false

local function enabled()
  return ns.db ~= nil and ns.db.prefs.vault ~= false
end

function Vault.IsOpen()
  return WeeklyRewardsFrame ~= nil and WeeklyRewardsFrame:IsShown() == true
end

-- "Delves tier 8", "Mythic+ 10", "Raid Heroic", "Rated PvP".
function Vault.Label(a)
  local t, level = a.type, a.level or 0
  if t == TYPE.World then return level > 0 and string.format("Delves tier %d", level) or "Delves" end
  if t == TYPE.Activities then return level > 0 and string.format("Mythic+ %d", level) or "Dungeons" end
  if t == TYPE.Raid then
    local name = level > 0 and GetDifficultyInfo and GetDifficultyInfo(level) or nil
    return name and ("Raid " .. name) or "Raid"
  end
  if t == TYPE.RankedPvP then return "Rated PvP" end
  return "Vault"
end

-- Every item on offer, with its real link (the upgrade track rides on it).
-- With examples, an earned slot that has nothing on offer yet stands in
-- with the example item the game shows for it: right level and track,
-- wrong item. That is for trying the picker before the reset.
function Vault.Read(examples)
  local out = {}
  if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return out end
  for _, a in ipairs(C_WeeklyRewards.GetActivities() or {}) do
    if not SKIP_TYPE[a.type] then
      local offered = false
      for _, r in ipairs(a.rewards or {}) do
        if r.type == REWARD_ITEM and r.itemDBID then
          local link = C_WeeklyRewards.GetItemHyperlink(r.itemDBID)
          if link then
            offered = true
            out[#out + 1] = {
              type = a.type, index = a.index, level = a.level, itemDBID = r.itemDBID, id = r.id, link = link,
              source = Vault.Label(a),
            }
          end
        end
      end
      local earned = (a.progress or 0) >= (a.threshold or math.huge)
      if examples and not offered and earned and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
        local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(a.id)
        if link then
          out[#out + 1] = {
            type = a.type, index = a.index, level = a.level, itemDBID = "example:" .. tostring(a.id),
            id = tonumber(link:match("item:(%d+)")), link = link, source = Vault.Label(a), example = true,
          }
        end
      end
    end
  end
  return out
end

-- Read, evaluate, rank. Returns ranked, headline, waiting (true while some
-- item is not in the client cache yet).
function Vault.Evaluate(examples)
  local list, wait = {}, false
  preview = false
  for _, o in ipairs(Vault.Read(examples)) do
    if o.example then preview = true end
    local facts, why = ns.ItemFacts.FromLink(o.link)
    if not facts then
      if why == "uncached" then wait = true end
    else
      o.item, o.name, o.icon, o.quality = facts, facts.name, facts.icon, facts.quality
      if ns.Slots.IsEquippable(facts.equipLoc) then
        o.verdict = ns.Verdicts.Evaluate(facts)
      end
      list[#list + 1] = o
    end
  end
  ranked = ns.VaultRank.Rank(list)
  headline = ns.VaultRank.Headline(ranked)
  waiting = wait
  return ranked, headline, waiting
end

-- ranked, headline, waiting, preview (true when example items stand in).
function Vault.Current()
  return ranked, headline, waiting, preview
end

local function refresh()
  if not enabled() or not Vault.IsOpen() then return end
  local list, line, wait = Vault.Evaluate()
  if wait and retries < MAX_RETRIES then
    retries = retries + 1
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    Vault.Schedule()
  else
    frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
  end
  if ns.VaultUI then ns.VaultUI.Update(list, wait, false) end
  if ns.Panel then ns.Panel.Refresh() end
  if #list > 0 and not wait and not announced then
    announced = true
    ns.Triggers.Notify({ text = "Great Vault: " .. line })
  end
end

-- Coalesce bursts of updates into one refresh.
function Vault.Schedule()
  if timer then timer:Cancel() end
  timer = C_Timer.NewTimer(0.4, Guard.Wrap(function()
    timer = nil
    refresh()
  end))
end

function Vault.OnShow()
  if not enabled() then return end
  announced, retries = false, 0
  frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
  refresh()
end

function Vault.OnHide()
  frame:UnregisterEvent("WEEKLY_REWARDS_UPDATE")
  frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
  if timer then timer:Cancel(); timer = nil end
  ranked, headline, waiting, preview = nil, nil, false, false
  if ns.VaultUI then ns.VaultUI.Hide() end
  if ns.Panel then ns.Panel.Refresh() end
end

-- Try the picker on the example items for the slots earned this week.
-- Shown under the vault window while it is open; printed either way.
function Vault.Preview()
  local list, line, wait = Vault.Evaluate(true)
  if Vault.IsOpen() then
    if ns.VaultUI then ns.VaultUI.Update(list, wait, preview) end
    if ns.Panel then ns.Panel.Refresh() end
  end
  local out = Vault.Describe()
  if preview then
    table.insert(out, 1, "Preview: example items for the slots you have earned, not your real offers. Right level and track, wrong item.")
  end
  if not Vault.IsOpen() then out[#out + 1] = "Open the Great Vault first to see this under the window." end
  return out
end

-- The verdict behind a tooltip on a vault item: Blizzard's item frames
-- carry the reward's database id, and so do Sift's own vault rows.
function Vault.EntryForTooltip(tooltip, data)
  if not ranked then return nil end
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  local dbid = owner and owner.displayedItemDBID
  local found
  if dbid then
    for _, o in ipairs(ranked) do
      if o.itemDBID == dbid then found = o break end
    end
  elseif data and data.id then
    for _, o in ipairs(ranked) do
      if o.id == data.id then
        if found then return nil end
        found = o
      end
    end
  end
  if not found or not found.verdict then return nil end
  return { facts = found.item, verdict = found.verdict, vault = found, total = #ranked }
end

local function hookFrame()
  if hooked or not WeeklyRewardsFrame then return end
  hooked = true
  WeeklyRewardsFrame:HookScript("OnShow", Guard.Wrap(Vault.OnShow))
  WeeklyRewardsFrame:HookScript("OnHide", Guard.Wrap(Vault.OnHide))
  if WeeklyRewardsFrame:IsShown() then Vault.OnShow() end
end

frame:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" then
    if arg == "Blizzard_WeeklyRewards" then
      Guard.Call(hookFrame)
      frame:UnregisterEvent("ADDON_LOADED")
    end
  else
    Vault.Schedule()
  end
end)
if WeeklyRewardsFrame then
  Guard.Call(hookFrame)
else
  frame:RegisterEvent("ADDON_LOADED")
end

-- Lines for chat and the copy box.
function Vault.Describe()
  local list, line = ranked, headline
  if not list then list, line = Vault.Evaluate() end
  local out = {}
  if #list == 0 then
    out[1] = Vault.IsOpen() and "Nothing on offer yet." or "Nothing on offer, or the vault has not been opened this session."
    return out
  end
  out[1] = line
  local R = ns.VaultRank
  for _, row in ipairs(R.Collapse(list)) do
    local o = row.option
    out[#out + 1] = string.format("  %s %s (%s): %s", R.Verb(o), o.link or o.name or "?", R.SourceText(row), R.Line(o))
  end
  return out
end
