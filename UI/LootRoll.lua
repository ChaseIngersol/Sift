-- The roll strip: Sift's word beside a Need, Greed, Pass window, with the
-- reason under it. One strip per Blizzard roll frame, parented to it so
-- it comes and goes with the roll and follows when the stack moves.
local ADDON, ns = ...

local LootRollUI = {}
ns.LootRollUI = LootRollUI

local Style = ns.Style
local strips = {}   -- roll frame -> strip
local WIDTH, HEIGHT, GAP = 216, 67, 4

local function build(rollFrame)
  local f = CreateFrame("Frame", nil, rollFrame, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  Style.Backdrop(f)

  -- A colored edge for the glance; the word says the rest.
  f.edge = f:CreateTexture(nil, "ARTWORK")
  f.edge:SetWidth(3)
  f.edge:SetPoint("TOPLEFT", 1, -1)
  f.edge:SetPoint("BOTTOMLEFT", 1, 1)

  f.word = f:CreateFontString(nil, "OVERLAY")
  Style.Text(f.word, Style.SIZE.verdict, Style.TEXT, "LEFT")
  f.word:SetPoint("TOPLEFT", 12, -6)
  f.word:SetPoint("RIGHT", -8, 0)
  f.word:SetWordWrap(false)

  f.line = f:CreateFontString(nil, "OVERLAY")
  Style.Text(f.line, Style.SIZE.body, Style.MUTED, "LEFT")
  f.line:SetPoint("TOPLEFT", f.word, "BOTTOMLEFT", 0, -2)
  f.line:SetPoint("BOTTOMRIGHT", -8, 4)
  f.line:SetJustifyV("TOP")
  f.line:SetWordWrap(true)
  f.line:SetMaxLines(3)

  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- Beside the roll frame, on whichever side has room.
local function place(f, rollFrame)
  f:ClearAllPoints()
  local right, screen = rollFrame:GetRight(), UIParent:GetRight()
  if right and screen and right + GAP + WIDTH > screen then
    f:SetPoint("TOPRIGHT", rollFrame, "TOPLEFT", -GAP, 0)
  else
    f:SetPoint("TOPLEFT", rollFrame, "TOPRIGHT", GAP, 0)
  end
end

-- advice = { word, kind, line, link }
function LootRollUI.Attach(rollFrame, advice)
  local f = strips[rollFrame]
  if not f then
    f = build(rollFrame)
    strips[rollFrame] = f
  end
  local rgb = Style.VERDICT_RGB[advice.kind] or Style.TEXT
  f.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
  f.word:SetText(advice.word or "")
  f.word:SetTextColor(rgb[1], rgb[2], rgb[3])
  f.line:SetText(advice.line or "")
  f.link = advice.link
  f.advice = advice
  ns.AltCompare.Tag(f, advice.altKey, advice.equipLoc)
  place(f, rollFrame)
  f:Show()
end

function LootRollUI.Detach(rollFrame)
  local f = strips[rollFrame]
  if f then
    f.link, f.advice = nil, nil
    f:Hide()
  end
end

-- The advice on a roll frame's strip, or nil when none is up.
function LootRollUI.Current(rollFrame)
  local f = strips[rollFrame]
  return f and f:IsShown() and f.advice or nil
end
