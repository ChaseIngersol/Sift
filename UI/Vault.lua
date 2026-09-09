-- The Great Vault window, marked in place: Sift's word on each card, the
-- gain beside it, a jade edge down the pick, and one sentence under the
-- window. The full reason stays in the card's tooltip.
local ADDON, ns = ...

local VaultUI = {}
ns.VaultUI = VaultUI

local Style = ns.Style
local PAD, FOOT_W = 12, 640
-- The word sits where the game's "Item Level" text sits, mirrored: that
-- text is anchored to the card's bottom-right at (-15, 15).
local INSET = 15
local strip
local badges = {}     -- activity frame -> badge
local used = {}       -- activity frame -> true this update

local function build()
  strip = CreateFrame("Frame", "SiftLootAdvisorVault", WeeklyRewardsFrame, "BackdropTemplate")
  strip:SetPoint("TOP", WeeklyRewardsFrame, "BOTTOM", 0, -6)
  strip:SetSize(FOOT_W, 40)
  strip:SetFrameLevel((WeeklyRewardsFrame:GetFrameLevel() or 1) + 5)
  Style.Backdrop(strip)

  strip.title = strip:CreateFontString(nil, "OVERLAY")
  Style.Text(strip.title, Style.SIZE.title, Style.TEXT, "LEFT")
  strip.title:SetPoint("TOPLEFT", PAD, -PAD + 2)
  strip.title:SetText("Sift")

  strip.head = strip:CreateFontString(nil, "OVERLAY")
  Style.Text(strip.head, Style.SIZE.body, Style.TEXT, "LEFT")
  strip.head:SetPoint("TOPLEFT", strip.title, "TOPRIGHT", 10, -2)
  strip.head:SetPoint("RIGHT", strip, "RIGHT", -PAD, 0)
  strip.head:SetJustifyV("TOP")
  strip.head:SetWordWrap(true)
end

-- The card's own item-level text is the model for ours: font, size,
-- flags and shadow, read each update rather than once, since a UI
-- addon that restyles the game's text does so after the card shows.
local function copyType(fs, model)
  if type(model) ~= "table" or not model.GetFont then return false end
  local font, size, flags = model:GetFont()
  if not font then return false end
  fs:SetFont(font, size, flags)
  if model.GetShadowColor then fs:SetShadowColor(model:GetShadowColor()) end
  if model.GetShadowOffset then fs:SetShadowOffset(model:GetShadowOffset()) end
  return true
end

-- A badge lives on the card, above the item frame and below the shade
-- the game draws over unselected cards, so it dims with the card.
local function badgeFor(af)
  local b = badges[af]
  if b then return b end
  b = CreateFrame("Frame", nil, af)
  b:SetAllPoints(af)
  local item = af.ItemFrame
  local level = (item and item.GetFrameLevel and item:GetFrameLevel()) or (af:GetFrameLevel() or 1) + 50
  b:SetFrameLevel(level + 5)

  b.edge = b:CreateTexture(nil, "OVERLAY")
  b.edge:SetWidth(3)
  b.edge:SetPoint("TOPLEFT", 3, -3)
  b.edge:SetPoint("BOTTOMLEFT", 3, 3)

  b.word = b:CreateFontString(nil, "OVERLAY")
  local model = af.Progress
  if not copyType(b.word, model) then
    Style.Text(b.word, Style.SIZE.body, Style.TEXT, "LEFT")
  end
  -- When the model's type changes, ours follows in the same frame, so
  -- a restyle after the card shows never leaves the two apart.
  if type(model) == "table" and hooksecurefunc then
    local function sync() copyType(b.word, model) end
    for _, m in ipairs({ "SetFont", "SetFontObject", "SetShadowColor", "SetShadowOffset" }) do
      if model[m] then hooksecurefunc(model, m, sync) end
    end
  end
  b.word:SetJustifyH("LEFT")
  b.word:SetPoint("BOTTOMLEFT", INSET, INSET)
  b.word:SetWordWrap(false)

  badges[af] = b
  af.siftBadge = b
  return b
end

local function activityFrame(o)
  if not WeeklyRewardsFrame.GetActivityFrame then return nil end
  return WeeklyRewardsFrame:GetActivityFrame(o.type, o.index)
end

-- One option per card: the one the card displays, else the best ranked.
local function pickPerCard(ranked)
  local chosen, order = {}, {}
  for _, o in ipairs(ranked) do
    local af = activityFrame(o)
    if af then
      local shown = af.ItemFrame and af.ItemFrame.displayedItemDBID
      local cur = chosen[af]
      if not cur then
        chosen[af] = o
        order[#order + 1] = af
      elseif shown and o.itemDBID == shown and cur.itemDBID ~= shown then
        chosen[af] = o
      end
    end
  end
  return chosen, order
end

local function mark(af, o)
  local R = ns.VaultRank
  local word, kind, gain, sign = R.Badge(o)
  local b = badgeFor(af)
  if not word then b:Hide() return end
  local rgb = Style.VERDICT_RGB[kind] or Style.TEXT
  copyType(b.word, af.Progress)
  local text = word
  if gain then text = string.format("%s |cff%s%s|r", word, Style.GAIN_HEX[sign] or Style.GAIN_HEX.flat, gain) end
  b.word:SetText(text)
  b.word:SetTextColor(rgb[1], rgb[2], rgb[3])
  if kind == "EQUIP" then
    b.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    b.edge:Show()
  else
    b.edge:Hide()
  end
  b:Show()
end

-- ranked from ns.Vault; waiting while items are still loading; preview
-- when example items stand in for offers that are not there yet.
function VaultUI.Update(ranked, waiting, preview)
  if not WeeklyRewardsFrame then return end
  if not strip then build() end
  for af in pairs(used) do used[af] = nil end
  if (not ranked or #ranked == 0) and not waiting then
    VaultUI.Hide()
    return
  end

  local chosen, order = pickPerCard(ranked or {})
  for _, af in ipairs(order) do
    mark(af, chosen[af])
    used[af] = true
  end
  for af, b in pairs(badges) do
    if not used[af] then b:Hide() end
  end

  local text = ns.VaultRank.Footer(ranked)
  if waiting and #ranked == 0 then text = "Reading the vault..." end
  if preview then text = "Preview with example items, not your real offers. " .. text end
  strip.head:SetText(text)
  strip.head:SetWidth(FOOT_W - PAD * 2 - 40)
  local h = (strip.head.GetStringHeight and strip.head:GetStringHeight()) or Style.SIZE.body + 3
  strip:SetHeight(math.max(Style.SIZE.title + 2, h) + PAD * 2 - 4)
  strip:Show()
end

function VaultUI.Hide()
  if strip then strip:Hide() end
  for _, b in pairs(badges) do b:Hide() end
end

function VaultUI.IsShown()
  return strip and strip:IsShown() or false
end
