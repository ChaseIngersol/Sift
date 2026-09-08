-- One quiet line on item tooltips: the verdict and its reason.
local ADDON, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local Guard = ns.Guard
local Style = ns.Style
local lastRun = 0

local function isEquipped(guid)
  local me = ns.Character.Self()
  for _, f in pairs(me.slots or {}) do
    if f.guid == guid then return true end
  end
  return false
end

local function entryForTooltip(tooltip, data)
  local Verdicts = ns.Verdicts
  if ns.Vault then
    local entry = ns.Vault.EntryForTooltip(tooltip, data)
    if entry then return entry end
  end
  local guid = data and data.guid
  if guid then
    local cached = Verdicts.Get(guid)
    if cached then return cached end
    -- Equipped items get no verdict; they are the incumbents.
    if isEquipped(guid) then return nil end
  end
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if owner and type(owner.GetBagID) == "function" and type(owner.GetID) == "function" then
    local ok, bag = pcall(owner.GetBagID, owner)
    local ok2, slot = pcall(owner.GetID, owner)
    if ok and ok2 and type(bag) == "number" and type(slot) == "number" then
      local entry = Verdicts.ForBag(bag, slot, false)
      if entry then return entry end
    end
  end
  local _, link = TooltipUtil.GetDisplayedItem(tooltip)
  if not link then return nil end
  return Verdicts.GetByLink(link) or Verdicts.ForLink(link, false)
end

local function onItemTooltip(tooltip, data)
  if not ns.db then return end
  if tooltip:IsForbidden() then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local entry = entryForTooltip(tooltip, data)
  if not entry then return end
  lastRun = GetTime()
  local v = entry.verdict
  local r, g, b = Style.VerdictRGB(v)
  local m = Style.MUTED
  tooltip:AddDoubleLine("Sift", ns.Engine.Headline(v), m[1], m[2], m[3], r, g, b)
  tooltip:AddLine(v.reason, Style.TEXT[1], Style.TEXT[2], Style.TEXT[3], true)
  for _, note in ipairs(v.notes or {}) do
    tooltip:AddLine(note, m[1], m[2], m[3], true)
  end
  if entry.vault then
    local e = Style.VERDICT_RGB.EQUIP
    tooltip:AddLine(ns.VaultRank.PlaceText(entry.vault, entry.total or 1), e[1], e[2], e[3], true)
  end
  -- The math behind it: always on panel rows, on Shift elsewhere.
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if (owner and owner.siftRow) or IsShiftKeyDown() then
    Tooltip.AddMath(tooltip, v)
  end
end

function Tooltip.AddMath(tooltip, v)
  local rows, summary = ns.Engine.Math(v)
  if not rows then return end
  local m, d = Style.MUTED, Style.DIM
  tooltip:AddLine(" ")
  for i, row in ipairs(rows) do
    if i > 8 then break end
    local delta = row.cand - row.inc
    tooltip:AddDoubleLine(row.label, string.format("%.0f vs %.0f (%+.0f)", row.cand, row.inc, delta), m[1], m[2], m[3], m[1], m[2], m[3])
  end
  tooltip:AddLine(summary, d[1], d[2], d[3], true)
end

function Tooltip.LastRun()
  return lastRun
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Guard.Wrap(onItemTooltip))
end
