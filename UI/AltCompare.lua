-- Sift's own "Equipped" panes beside an item tooltip, showing an alt's
-- gear when the row under the mouse says "send to" that alt.
--
-- Blizzard's comparison manager only knows the current character's gear
-- and has no way to point it elsewhere. Rewriting its two panes after it
-- fills them does not stick either: live, a rewritten pane held this
-- character's item again a frame later, through no Lua path that can be
-- hooked. So while a tagged row owns GameTooltip, Blizzard's automatic
-- comparison is suppressed with its own helper and Sift shows two panes
-- of its own, built from Blizzard's ShoppingTooltipTemplate so they look
-- the same, filled from the alt snapshot's item links and anchored the
-- way Blizzard anchors its panes. Sift keeps the full link of everything
-- each alt wears, and a link carries level, bonuses, enchant and gems.
local ADDON, ns = ...

local AltCompare = {}
ns.AltCompare = AltCompare

local HEADER_PAD = 30 -- Blizzard's COMPARE_HEADER_PADDING
local HEADER_VPAD = 5 -- above and below the label: Blizzard's 22 px header around a 12 px line
local DAY = 86400

-- A measurement, or nil when the client will not let insecure code
-- read it. In Midnight a tooltip filled with secret lines has a secret
-- size, and every region anchored to it inherits that: GetWidth on the
-- header's label comes back as a secret number, which Lua cannot add
-- to. Blizzard sizes its own header with that very sum, as secure
-- code may.
local function plain(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local panes = {}
local suppressing = false

local function debugging()
  return ns.db and ns.db.prefs and ns.db.prefs.debug
end

-- Mark a frame: while GameTooltip hangs off it, comparisons show the
-- gear of the character `key` in the slots `equipLoc` maps to. Nil clears.
function AltCompare.Tag(frame, key, equipLoc)
  if key and equipLoc then
    frame.siftAltCompare = { key = key, equipLoc = equipLoc }
  else
    frame.siftAltCompare = nil
  end
end

-- The alt's pieces the candidate competes with, in slot order, plus the
-- snapshot they came from. Nil when nothing is on file for that key.
function AltCompare.Pieces(key, equipLoc)
  local snap = ns.db and ns.db.chars and ns.db.chars[key]
  if not snap then return nil end
  local out = {}
  for _, slot in ipairs(ns.Slots.BY_EQUIPLOC[equipLoc] or {}) do
    local f = snap.slots and snap.slots[slot]
    if f and f.link then out[#out + 1] = f end
  end
  return out, snap
end

-- "yesterday" or "3 days ago"; nil within the first day.
function AltCompare.Ago(seconds)
  local days = math.floor((seconds or 0) / DAY)
  if days < 1 then return nil end
  if days == 1 then return "yesterday" end
  return string.format("%d days ago", days)
end

-- Whether panes belong up at all: the player's own compare setting, the
-- same test Blizzard applies before its automatic comparison.
function AltCompare.ShouldCompare()
  if GetCVarBool and GetCVarBool("alwaysCompareItems") then return true end
  if IsModifiedClick and IsModifiedClick("COMPAREITEMS") then return true end
  return false
end

----------------------------------------------------------------------------
-- Stat changes
----------------------------------------------------------------------------
-- Blizzard's shape ("+61 Haste", green up, red down), for when the client
-- will not compute them for gear it cannot see. Unchanged stats are left
-- out. Labels come from the client's own stat strings where it has them.
local ORDER = { "ARMOR", "STRENGTH", "AGILITY", "INTELLECT", "STAMINA", "CRIT", "HASTE", "MASTERY",
  "VERSATILITY", "LEECH", "AVOIDANCE", "SPEED", "INDESTRUCTIBLE", "DPS" }
local TOKEN_OF = {}
for token, key in pairs(ns.Stats.TOKEN_TO_KEY) do TOKEN_OF[key] = TOKEN_OF[key] or token end

local function statName(key)
  local token = TOKEN_OF[key]
  local s = token and _G[token]
  if type(s) == "string" and s ~= "" then return s end
  return ns.Stats.LABEL[key] or key
end

local PRIMARY = { STRENGTH = true, AGILITY = true, INTELLECT = true }

-- A piece's primary stat: the fixed one it carries, or its flex value
-- (which becomes the wearer's primary). Returns amount, key or nil.
local function primaryOf(f)
  local stats = (f and f.stats) or {}
  for key in pairs(PRIMARY) do
    if (stats[key] or 0) ~= 0 then return stats[key], key end
  end
  if f and f.flex and f.flex.value then return f.flex.value, nil end
  return 0, nil
end

local function line(d, label)
  return string.format("%s%+d|r %s", d > 0 and "|cff00ff00" or "|cffff2020", d, label)
end

function AltCompare.StatLines(candidate, worn)
  local a, b = (candidate and candidate.stats) or {}, (worn and worn.stats) or {}
  local out = {}
  local pa, ka = primaryOf(candidate)
  local pb, kb = primaryOf(worn)
  local primaryDone = false
  -- Flex on either side: one line for the primary, named after whichever
  -- side is fixed. Both fixed: the per-stat loop below handles them.
  if (ka == nil or kb == nil) and (pa ~= 0 or pb ~= 0) then
    if pa - pb ~= 0 then out[#out + 1] = line(pa - pb, statName(ka or kb) or "Primary stat") end
    primaryDone = true
  end
  for _, key in ipairs(ORDER) do
    if not (primaryDone and PRIMARY[key]) then
      local d = (a[key] or 0) - (b[key] or 0)
      if d ~= 0 then out[#out + 1] = line(d, statName(key)) end
    end
  end
  return out
end

-- Blizzard's delta first: the client takes both items by link and, seen
-- live, computes the change against a piece this character does not
-- own. Anything else, or nothing, falls back to Sift's own stat parse.
local function deltaLines(candidateLink, worn)
  local api = C_TooltipComparison and C_TooltipComparison.GetItemComparisonDelta
  if api then
    local ok, delta = pcall(api, { hyperlink = candidateLink }, { hyperlink = worn.link }, nil, false)
    if ok and type(delta) == "table" and #delta > 0 then return delta, "client" end
  end
  return AltCompare.StatLines(ns.ItemFacts.FromLink(candidateLink), worn), "sift"
end

----------------------------------------------------------------------------
-- Panes
----------------------------------------------------------------------------
local function pane(i)
  local p = panes[i]
  if not p then
    p = CreateFrame("GameTooltip", "SiftLootAdvisorComparePane" .. i, UIParent, "ShoppingTooltipTemplate")
    p:SetFrameStrata("TOOLTIP")
    p:SetClampedToScreen(true)
    panes[i] = p
  end
  return p
end

-- One pane: the header names the alt, the body is the alt's item as the
-- client renders its link, then the stat changes, then how old the
-- snapshot is once it is more than a day old. True when it has content.
local function fillPane(tip, worn, candidateLink, snap)
  local data = C_TooltipInfo.GetHyperlink(worn.link)
  if not data then return false end
  tip:SetOwner(GameTooltip, "ANCHOR_NONE")
  tip:ClearAllPoints()
  tip.CompareHeader:Show()
  local label = tip.CompareHeader.Label
  label:SetText(string.format("Equipped on %s", snap.name or "alt"))
  -- The header hugs its label by anchors alone: the label sits where
  -- Blizzard's would, and the header's corners hang off the label's
  -- with the padding in the offsets, so no width is ever measured.
  if not tip.siftHeaderAnchored then
    tip.siftHeaderAnchored = true
    label:ClearAllPoints()
    -- Blizzard's header hangs one pixel over the tooltip's top edge.
    label:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", HEADER_PAD / 2, HEADER_VPAD - 1)
    tip.CompareHeader:ClearAllPoints()
    tip.CompareHeader:SetPoint("TOPLEFT", label, "TOPLEFT", -HEADER_PAD / 2, HEADER_VPAD)
    tip.CompareHeader:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", HEADER_PAD / 2, -HEADER_VPAD)
  end
  tip:ProcessInfo({ tooltipData = data, append = true })
  local lines = deltaLines(candidateLink, worn)
  if #lines > 0 then
    GameTooltip_AddBlankLineToTooltip(tip)
    GameTooltip_AddNormalLine(tip, ITEM_DELTA_DESCRIPTION)
    for _, text in ipairs(lines) do GameTooltip_AddHighlightLine(tip, text) end
  end
  local age = snap.updated and AltCompare.Ago(time() - snap.updated)
  if age then
    GameTooltip_AddBlankLineToTooltip(tip)
    GameTooltip_AddDisabledLine(tip, string.format("As seen on %s %s.", snap.name or "that character", age))
  end
  tip:Show()
  return true
end

local LEFT_ANCHORS = { ANCHOR_LEFT = true, ANCHOR_TOPLEFT = true, ANCHOR_BOTTOMLEFT = true }
local RIGHT_ANCHORS = { ANCHOR_RIGHT = true, ANCHOR_TOPRIGHT = true, ANCHOR_BOTTOMRIGHT = true }

-- Beside the tooltip on whichever side has room, the second pane outside
-- the first, sliding the tooltip over when they would leave the screen:
-- Blizzard's own placement, minus nothing that matters here. A preserved
-- anchor never slides, so the toast's placement stays where it put it.
local function anchor(tip, shown1, shown2)
  if panes[1] then panes[1]:SetShown(shown1) end
  if panes[2] then panes[2]:SetShown(shown2) end
  if not shown1 then return end
  local p1, p2 = panes[1], panes[2]
  local anchorType = tip.GetAnchorType and tip:GetAnchorType()
  -- Widths and edges can be secret (see plain). Without them the panes
  -- take the side the anchor type implies and nothing slides.
  local left, right = plain(tip:GetLeft()), plain(tip:GetRight())
  local w1, w2 = plain(p1:GetWidth()), shown2 and plain(p2:GetWidth()) or 0
  local screenW = plain(GetScreenWidth())
  local measured = left ~= nil and right ~= nil and w1 ~= nil and w2 ~= nil and screenW ~= nil
  local side
  if measured then
    local total = w1 + w2
    local rightDist = screenW - right
    if anchorType and total < left and LEFT_ANCHORS[anchorType] then side = "left"
    elseif anchorType and total < rightDist and RIGHT_ANCHORS[anchorType] then side = "right"
    elseif rightDist < left then side = "left"
    else side = "right" end
  else
    side = (anchorType and LEFT_ANCHORS[anchorType]) and "left" or "right"
  end
  if measured and anchorType and anchorType ~= "ANCHOR_PRESERVE" and tip.SetAnchorType then
    local total = w1 + w2
    local slide = 0
    if side == "left" and total > left then slide = total - left
    elseif side == "right" and right + total > screenW then slide = screenW - (right + total) end
    if slide ~= 0 then tip:SetAnchorType(anchorType, slide, 0) end
  end
  p1:ClearAllPoints()
  p1:SetPoint("TOP", tip, 0, 0)
  if shown2 then
    p2:ClearAllPoints()
    p2:SetPoint("TOP", tip, 0, 0)
    if side == "left" then
      p1:SetPoint("RIGHT", tip, "LEFT")
      p2:SetPoint("TOPRIGHT", p1, "TOPLEFT")
    else
      p2:SetPoint("LEFT", tip, "RIGHT")
      p1:SetPoint("TOPLEFT", p2, "TOPRIGHT")
    end
  elseif side == "left" then
    p1:SetPoint("RIGHT", tip, "LEFT")
  else
    p1:SetPoint("LEFT", tip, "RIGHT")
  end
end

function AltCompare.Hide()
  for _, p in ipairs(panes) do p:Hide() end
end

-- Put the panes up beside `tooltip` for the tagged alt. Panes with
-- nothing to show stay down, so an empty slot on the alt shows no
-- comparison rather than this character's piece. Returns how many.
function AltCompare.Show(tooltip, tag, candidateLink)
  local pieces, snap = AltCompare.Pieces(tag.key, tag.equipLoc)
  local shown = {}
  for i = 1, 2 do
    local worn = pieces and pieces[i]
    shown[i] = (worn and fillPane(pane(i), worn, candidateLink, snap)) and true or false
  end
  anchor(tooltip, shown[1], shown[2])
  return (shown[1] and 1 or 0) + (shown[2] and 1 or 0)
end

function AltCompare.Pane(i)
  return panes[i]
end

----------------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------------
-- While a tagged row owns GameTooltip, Blizzard's automatic comparison
-- stays off (its own helper; the flag is reset by Blizzard when the
-- tooltip hides). Any new owner takes the panes down first.
local function onSetOwner(tooltip, owner)
  AltCompare.Hide()
  if owner and owner.siftAltCompare then
    if GameTooltip_SuppressAutomaticCompareItem then
      GameTooltip_SuppressAutomaticCompareItem(tooltip)
    else
      tooltip.suppressAutomaticCompareItem = true
    end
    suppressing = true
  elseif suppressing then
    tooltip.suppressAutomaticCompareItem = false
    suppressing = false
  end
end

-- Once the item is on the tooltip: Blizzard's panes down for good on
-- this row (with Shift held it compares anyway), then Sift's up when the
-- player's compare setting says so.
local function onItemTooltip(tooltip, data)
  if tooltip ~= GameTooltip or not ns.db then return end
  if tooltip.IsForbidden and tooltip:IsForbidden() then return end
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  local tag = owner and owner.siftAltCompare
  if not tag then return end
  for _, t in ipairs(tooltip.shoppingTooltips or {}) do t:Hide() end
  if not AltCompare.ShouldCompare() then AltCompare.Hide() return end
  local _, link = TooltipUtil.GetDisplayedItem(tooltip)
  link = link or (data and data.hyperlink) or owner.link
  if not link then AltCompare.Hide() return end
  local n = AltCompare.Show(tooltip, tag, link)
  if debugging() then
    ns.Log("debug", string.format("alt compare: %d pane(s) for %s in %s", n, tag.key, tag.equipLoc))
  end
end

if GameTooltip and hooksecurefunc then
  hooksecurefunc(GameTooltip, "SetOwner", ns.Guard.Wrap(onSetOwner))
  GameTooltip:HookScript("OnHide", ns.Guard.Wrap(function() AltCompare.Hide() end))
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Guard.Wrap(onItemTooltip))
end
