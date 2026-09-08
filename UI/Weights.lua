-- The stat weights sheet: what Sift is scoring with for this spec, how to
-- get your own numbers, and a box to paste them into. Built on first open.
local ADDON, ns = ...

local WeightsUI = {}
ns.WeightsUI = WeightsUI

local Style, Guard = ns.Style, ns.Guard
local WIDTH, PAD = 560, 14
local TOP_H = 44

local frame, using, hint, box, result
local steps, stepsShown = {}, true
local BODY_W = WIDTH - PAD * 2
local STEP_X = 22      -- step text starts here; its number sits right-aligned before it
local BOX_H = 28
local BUTTONS_W = 132  -- room beside the paste box for Import and Clear

local STEPS = {
  "Type /simc in game and copy the text it shows (the Simulationcraft addon).",
  "Paste it at raidbots.com and run a Stat Weights sim.",
  "Copy the Pawn string from the result and paste it below.",
}

local function place()
  frame:ClearAllPoints()
  local panel = _G.SiftLootAdvisorPanel
  if panel and panel:IsShown() then
    frame:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -6)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

local function height(fs)
  local h = fs:GetStringHeight()
  if not h or h <= 0 then h = Style.SIZE.body + 4 end
  return h
end

-- Top down, every block at the left margin, the sheet ending where its
-- content does. Runs whenever a text changes, since the weights line and
-- the result can wrap.
local function layout()
  if not frame then return end
  local y = TOP_H + 14
  using:SetPoint("TOPLEFT", PAD, -y)
  y = y + height(using) + 6
  hint:SetPoint("TOPLEFT", PAD, -y)
  y = y + height(hint) + 12
  for _, s in ipairs(steps) do
    s.n:SetShown(stepsShown)
    s.text:SetShown(stepsShown)
    if stepsShown then
      s.n:SetPoint("TOPLEFT", PAD, -y)
      s.text:SetPoint("TOPLEFT", PAD + STEP_X, -y)
      y = y + height(s.text) + 6
    end
  end
  y = y + 8
  box:SetPoint("TOPLEFT", PAD, -y)
  box:SetPoint("TOPRIGHT", -(PAD + BUTTONS_W), -y)
  y = y + BOX_H + 10
  result:SetPoint("TOPLEFT", PAD, -y)
  y = y + height(result)
  frame:SetHeight(y + PAD)
end

local function setResult(text, rgb)
  result:SetText(text or "")
  result:SetTextColor(rgb[1], rgb[2], rgb[3])
  layout()
end

local function refresh()
  local me = ns.Character.Self()
  local spec = me.specs and me.specs[1]
  frame.who:SetText(string.format("%s, %s", me.name or "", spec and spec.name or ""))
  local line, st = ns.Character.DescribeWeights()
  using:SetText(line)
  -- Raidbots does not sim healing, so the three steps are not for healers.
  stepsShown = not (spec and spec.role == "heal")
  if not stepsShown then
    hint:SetText("Raidbots does not sim healing, so there is no sim to run. Any Pawn string pasted below replaces the defaults, from a guide or your own sheet.")
  elseif st.source == "imported" then
    hint:SetText("Paste a new string any time. Re-sim after a talent change or a few new pieces.")
  else
    hint:SetText("Your own weights account for your talents, trinkets and gear. Three steps:")
  end
  layout()
end

local function paragraph(size, rgb, width)
  local fs = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(fs, size, rgb, "LEFT")
  fs:SetWidth(width or BODY_W)
  fs:SetWordWrap(true)
  fs:SetJustifyV("TOP")
  return fs
end

local function build()
  frame = CreateFrame("Frame", "SiftLootAdvisorWeights", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 300)
  Style.Dialog(frame)
  Style.Backdrop(frame)
  frame:Hide()

  Style.Logo(frame, PAD, TOP_H)

  local title = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(title, Style.SIZE.title, Style.TEXT, "LEFT")
  title:SetPoint("TOPLEFT", PAD + Style.LOGO_W + 8, -PAD)
  title:SetText("Stat weights")

  local who = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(who, Style.SIZE.body, Style.MUTED, "LEFT")
  who:SetPoint("LEFT", title, "RIGHT", 10, -1)
  frame.who = who

  local close = Style.TextButton(frame, "Close", Style.SIZE.body, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)

  local rule = Style.Rule(frame)
  rule:SetPoint("TOPLEFT", PAD, -TOP_H)
  rule:SetPoint("TOPRIGHT", -PAD, -TOP_H)

  using = paragraph(Style.SIZE.name, Style.TEXT)
  hint = paragraph(Style.SIZE.body, Style.MUTED)

  for i, text in ipairs(STEPS) do
    local n = frame:CreateFontString(nil, "OVERLAY")
    Style.Text(n, Style.SIZE.body, Style.DIM, "RIGHT")
    n:SetWidth(STEP_X - 8)
    n:SetText(tostring(i))
    local step = paragraph(Style.SIZE.body, Style.TEXT, BODY_W - STEP_X)
    step:SetText(text)
    steps[i] = { n = n, text = step }
  end

  box = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
  box:SetHeight(BOX_H)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  box:SetTextInsets(8, 8, 0, 0)
  Style.Font(box, Style.SIZE.body)
  box:SetTextColor(unpack(Style.TEXT))
  box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  box:SetBackdropColor(0, 0, 0, 0.35)
  box:SetBackdropBorderColor(unpack(Style.BORDER))
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  box:SetScript("OnEnterPressed", Guard.Wrap(function(b) WeightsUI.Import(b:GetText()) end))
  box:SetScript("OnEditFocusGained", function(b) b:SetBackdropBorderColor(unpack(Style.MUTED)) end)
  box:SetScript("OnEditFocusLost", function(b) b:SetBackdropBorderColor(unpack(Style.BORDER)) end)

  local placeholder = box:CreateFontString(nil, "OVERLAY")
  Style.Text(placeholder, Style.SIZE.body, Style.DIM, "LEFT")
  placeholder:SetPoint("LEFT", 8, 0)
  placeholder:SetText("( Pawn: v1: ... )")
  box.placeholder = placeholder
  box:SetScript("OnTextChanged", function(b) placeholder:SetShown(b:GetText() == "") end)

  local import = Style.Button(frame, "Import", Style.SIZE.body, function() WeightsUI.Import(box:GetText()) end)
  import:SetPoint("LEFT", box, "RIGHT", 8, 0)

  local clear = Style.TextButton(frame, "Clear", Style.SIZE.body, function()
    ns.Character.ClearWeights()
    ns.Verdicts.InvalidateAll()
    box:SetText("")
    setResult("Imported weights cleared for this character.", Style.MUTED)
    refresh()
    if ns.Panel then ns.Panel.Refresh() end
  end)
  clear:SetPoint("LEFT", import, "RIGHT", 4, 0)

  result = paragraph(Style.SIZE.body, Style.MUTED)
  frame.steps, frame.box, frame.result = steps, box, result

  table.insert(UISpecialFrames, "SiftLootAdvisorWeights")
end

-- Import a pasted string. Returns ok, message.
function WeightsUI.Import(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    setResult("Paste a Pawn string first.", Style.VERDICT_RGB.HOLD)
    return false
  end
  local ok, msg = ns.Character.ImportWeights(text)
  ns.Verdicts.InvalidateAll()
  if ok then
    box:SetText("")
    box:ClearFocus()
    setResult((msg:gsub("^%l", string.upper)) .. ". Verdicts now use these weights.", Style.VERDICT_RGB.EQUIP)
  else
    setResult("Could not import: " .. tostring(msg) .. ".", Style.VERDICT_RGB.HOLD)
  end
  refresh()
  if ns.Panel then ns.Panel.Refresh() end
  return ok, msg
end

function WeightsUI.Toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() return end
  WeightsUI.Show()
end

function WeightsUI.Show()
  if not frame then build() end
  place()
  setResult("", Style.MUTED)
  refresh()
  frame:Show()
  Style.Front(frame)
end

function WeightsUI.IsShown()
  return frame and frame:IsShown() or false
end
