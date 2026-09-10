-- Visual tokens. One typeface, four verdict colors, quiet everything else.
local ADDON, ns = ...

local Style = {}
ns.Style = Style

Style.FONT = "Fonts\\FRIZQT__.TTF"

Style.SIZE = { title = 15, verdict = 14, name = 12, body = 11, meta = 10 }

-- Panel surface and rules.
Style.BG = { 0.078, 0.102, 0.133, 0.94 }
Style.BORDER = { 0.169, 0.204, 0.251, 1 }
Style.RULE = { 0.169, 0.204, 0.251, 1 }
Style.ROW_HOVER = { 1, 1, 1, 0.05 }

-- Text.
Style.TEXT = { 0.902, 0.882, 0.839 }
Style.MUTED = { 0.553, 0.569, 0.600 }
Style.DIM = { 0.40, 0.41, 0.44 }

-- Verdict colors, chosen to sit apart from item quality colors.
Style.VERDICT_HEX = { EQUIP = "5fd3a8", HOLD = "e8b458", SEND = "8fb8ff", DISPOSE = "9a9ab5" }
Style.VERDICT_RGB = {
  EQUIP = { 0.373, 0.827, 0.659 },
  HOLD = { 0.910, 0.706, 0.345 },
  SEND = { 0.561, 0.722, 1.000 },
  DISPOSE = { 0.604, 0.604, 0.710 },
}

-- A groupmate's drop, on the toast and the panel: not one of the
-- verdict colors, so "Marcus got" never reads as a verdict.
Style.THEIRS_RGB = { 0.780, 0.640, 0.940 }

-- The gain at the head of a row: how the comparison went, not which
-- group the row sits in. Green better, red worse, grey too close to
-- call or only an item level.
Style.GAIN_HEX = { up = "5fd3a8", flat = "9a9ab5", down = "e07b74" }
Style.GAIN_RGB = { up = { 0.373, 0.827, 0.659 }, flat = { 0.604, 0.604, 0.710 }, down = { 0.878, 0.482, 0.455 } }

function Style.VerdictColor(v)
  return Style.VERDICT_HEX[v and v.kind] or "e6e1d6"
end

function Style.VerdictRGB(v)
  return unpack(Style.VERDICT_RGB[v and v.kind] or Style.TEXT)
end

function Style.QualityRGB(quality)
  local r, g, b = C_Item.GetItemQualityColor(quality or 1)
  return r or 1, g or 1, b or 1
end

function Style.Font(fs, size, flags)
  fs:SetFont(Style.FONT, size or Style.SIZE.body, flags or "")
  fs:SetShadowColor(0, 0, 0, 0.6)
  fs:SetShadowOffset(1, -1)
end

function Style.Text(fs, size, rgb, justify)
  Style.Font(fs, size)
  fs:SetTextColor(rgb[1], rgb[2], rgb[3])
  if justify then fs:SetJustifyH(justify) end
end

function Style.Backdrop(frame, alphaOverride)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(Style.BG[1], Style.BG[2], Style.BG[3], alphaOverride or Style.BG[4])
  frame:SetBackdropBorderColor(unpack(Style.BORDER))
end

-- The header mark: the frameless keeper, centered in a header of the
-- given height. The same texture the minimap and the addon list show.
Style.LOGO = "Interface\\AddOns\\SiftLootAdvisor\\Media\\minimap-icon.tga"
Style.LOGO_W = 22

function Style.Logo(parent, x, headerHeight)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(Style.LOGO_W, Style.LOGO_W)
  t:SetPoint("TOPLEFT", x, -math.floor((headerHeight - Style.LOGO_W) / 2))
  t:SetTexture(Style.LOGO)
  return t
end

function Style.Rule(parent)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(Style.RULE[1], Style.RULE[2], Style.RULE[3], Style.RULE[4])
  t:SetHeight(1)
  return t
end

-- Plain text button: muted at rest, text color on hover. Returns the button.
function Style.TextButton(parent, text, size, onClick)
  local b = CreateFrame("Button", nil, parent)
  local fs = b:CreateFontString(nil, "OVERLAY")
  Style.Text(fs, size or Style.SIZE.body, Style.MUTED)
  fs:SetText(text)
  fs:SetPoint("CENTER")
  b:SetSize(fs:GetStringWidth() + 12, (size or Style.SIZE.body) + 8)
  b.label = fs
  b:SetScript("OnEnter", function() fs:SetTextColor(unpack(Style.TEXT)) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(unpack(Style.MUTED)) end)
  b:SetScript("OnClick", ns.Guard.Wrap(onClick))
  return b
end

-- Sift's dialogs share the DIALOG stratum. Equal frame levels there
-- interleave: both backdrops draw, then both sets of text, so two open
-- windows read through each other. The one shown last gets a level above
-- every other open dialog and its children, and a click brings any of
-- them forward again (toplevel).
local dialogs = {}

-- Every dialog takes the mouse (so a click lands on it instead of on
-- whatever is beneath) and can be dragged by any bare part of itself.
function Style.Dialog(frame)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
  dialogs[#dialogs + 1] = frame
end

function Style.Front(frame)
  local top = 0
  for _, d in ipairs(dialogs) do
    if d ~= frame and d:IsShown() then top = math.max(top, d:GetFrameLevel()) end
  end
  frame:SetFrameLevel(top + 10)
end

-- Outlined button, the shape of a thing to do: a jade hairline and a
-- faint fill at rest, brighter under the mouse, the label dipping a pixel
-- while pressed. Text buttons stay for the quiet actions around it.
Style.ACTION = Style.VERDICT_RGB.EQUIP
function Style.Button(parent, text, size, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  local fs = b:CreateFontString(nil, "OVERLAY")
  Style.Text(fs, size or Style.SIZE.body, Style.TEXT)
  fs:SetText(text)
  fs:SetPoint("CENTER", 0, 0)
  b:SetSize(fs:GetStringWidth() + 24, (size or Style.SIZE.body) + 12)
  b.label = fs
  local a = Style.ACTION
  local function rest()
    b:SetBackdropColor(a[1], a[2], a[3], 0.07)
    b:SetBackdropBorderColor(a[1], a[2], a[3], 0.45)
    fs:SetTextColor(unpack(Style.TEXT))
  end
  local function hover()
    b:SetBackdropColor(a[1], a[2], a[3], 0.16)
    b:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    fs:SetTextColor(a[1], a[2], a[3])
  end
  rest()
  b:SetScript("OnEnter", hover)
  b:SetScript("OnLeave", rest)
  b:SetScript("OnMouseDown", function()
    b:SetBackdropColor(a[1], a[2], a[3], 0.26)
    fs:SetPoint("CENTER", 0, -1)
  end)
  b:SetScript("OnMouseUp", function()
    fs:SetPoint("CENTER", 0, 0)
    if b:IsMouseOver() then hover() else rest() end
  end)
  b:SetScript("OnClick", ns.Guard.Wrap(onClick))
  return b
end

function Style.Money(copper)
  copper = tonumber(copper) or 0
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  if g > 0 then return string.format("%dg %ds", g, s) end
  local c = copper % 100
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

-- The same amount with the game's coin icons in place of the letters.
local COIN = { g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t", s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t", c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t" }
function Style.MoneyText(copper)
  return (Style.Money(copper):gsub("(%d+)([gsc])", function(n, unit) return n .. COIN[unit] end))
end

-- An inline texture by file id, sized to the font, or nothing.
function Style.IconText(fileID)
  if not fileID then return "" end
  return string.format("|T%s:0|t ", tostring(fileID))
end

-- The class icon atlas inline, when the client has it, or nothing.
function Style.ClassIcon(classFile)
  if type(classFile) ~= "string" or classFile == "" then return "" end
  local name = "classicon-" .. classFile:lower()
  if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) then return "" end
  return string.format("|A:%s:12:12|a ", name)
end
