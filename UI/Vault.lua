-- A strip under the Great Vault window: the pick, then one line per item.
local ADDON, ns = ...

local VaultUI = {}
ns.VaultUI = VaultUI

local Style, Guard = ns.Style, ns.Guard
local PAD, LINE_GAP = 12, 4
local strip, lines
local linesUsed = 0

local function qualityHex(q)
  local _, _, _, hex = C_Item.GetItemQualityColor(q or 1)
  return hex or "ffffffff"
end

local function build()
  strip = CreateFrame("Frame", "SiftLootAdvisorVault", WeeklyRewardsFrame, "BackdropTemplate")
  strip:SetPoint("TOPLEFT", WeeklyRewardsFrame, "BOTTOMLEFT", 0, -6)
  strip:SetPoint("TOPRIGHT", WeeklyRewardsFrame, "BOTTOMRIGHT", 0, -6)
  strip:SetHeight(48)
  strip:SetFrameLevel((WeeklyRewardsFrame:GetFrameLevel() or 1) + 5)
  Style.Backdrop(strip)

  strip.title = strip:CreateFontString(nil, "OVERLAY")
  Style.Text(strip.title, Style.SIZE.title, Style.TEXT, "LEFT")
  strip.title:SetPoint("TOPLEFT", PAD, -PAD)
  strip.title:SetText("Sift")

  strip.head = strip:CreateFontString(nil, "OVERLAY")
  Style.Text(strip.head, Style.SIZE.body, Style.TEXT, "LEFT")
  strip.head:SetPoint("TOPLEFT", strip.title, "TOPRIGHT", 10, -2)
  strip.head:SetPoint("RIGHT", strip, "RIGHT", -PAD, 0)
  strip.head:SetJustifyV("TOP")
  strip.head:SetWordWrap(true)
  lines = {}
end

local function acquireLine()
  linesUsed = linesUsed + 1
  local l = lines[linesUsed]
  if not l then
    l = CreateFrame("Button", nil, strip)
    l.text = l:CreateFontString(nil, "OVERLAY")
    Style.Text(l.text, Style.SIZE.body, Style.MUTED, "LEFT")
    l.text:SetPoint("TOPLEFT", 0, 0)
    l.text:SetPoint("RIGHT", l, "RIGHT", 0, 0)
    l.text:SetJustifyV("TOP")
    l.text:SetWordWrap(true)
    l:SetScript("OnEnter", function(b)
      if b.link then
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(b.link)
        GameTooltip:Show()
      end
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l:SetScript("OnClick", Guard.Wrap(function(b)
      if IsShiftKeyDown() and b.link and ChatEdit_InsertLink then ChatEdit_InsertLink(b.link) end
    end))
    lines[linesUsed] = l
  end
  l:Show()
  return l
end

local function lineText(row)
  local o = row.option
  local R = ns.VaultRank
  local name = string.format("|c%s%s|r", qualityHex(o.quality), o.name or "?")
  return string.format("|cff%s%s|r %s (%s): %s", Style.VERDICT_HEX[R.Kind(o)] or "e6e1d6", R.Verb(o), name, R.SourceText(row), R.Line(o))
end

-- ranked from ns.Vault; waiting while items are still loading; preview
-- when example items stand in for offers that are not there yet.
function VaultUI.Update(ranked, headline, waiting, preview)
  if not WeeklyRewardsFrame then return end
  if not strip then build() end
  if (not ranked or #ranked == 0) and not waiting then
    strip:Hide()
    return
  end
  local text = waiting and (#ranked == 0 and "Reading the vault..." or headline) or headline
  if preview then text = "Preview with example items, not your real offers. " .. text end
  strip.head:SetText(text)
  local width = (strip:GetWidth() or 600) - PAD * 2
  strip.head:SetWidth(math.max(100, width - 50))
  local y = PAD + math.max(Style.SIZE.title + 2, (strip.head.GetStringHeight and strip.head:GetStringHeight()) or 0) + 8
  for i = 1, linesUsed do lines[i]:Hide() end
  linesUsed = 0
  for _, row in ipairs(ns.VaultRank.Collapse(ranked)) do
    local o = row.option
    local l = acquireLine()
    l:SetPoint("TOPLEFT", strip, "TOPLEFT", PAD, -y)
    l:SetWidth(width)
    l.link = o.link
    l.displayedItemDBID = o.itemDBID
    l.text:SetWidth(width)
    l.text:SetText(lineText(row))
    local h = (l.text.GetStringHeight and l.text:GetStringHeight()) or Style.SIZE.body + 3
    l:SetHeight(h)
    y = y + h + LINE_GAP
  end
  strip:SetHeight(y + PAD - LINE_GAP)
  strip:Show()
end

function VaultUI.Hide()
  if strip then strip:Hide() end
end

function VaultUI.IsShown()
  return strip and strip:IsShown() or false
end
