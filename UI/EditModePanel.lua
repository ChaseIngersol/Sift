-- A small Sift panel docked beside the Edit Mode window, the way other
-- addons do it: one checkbox per placeable element, so a toast that is
-- turned off can be found and turned on from Edit Mode itself. Anchored
-- to the manager window, never parented to it, so its layout is left
-- alone.
local ADDON, ns = ...

local Panel = {}
ns.EditModePanel = Panel

local Guard = ns.Guard
local CHECKBOX = "Interface\\Buttons\\UI-CheckBox-"
local WIDTH, ROW_H, TOP = 160, 32, 12 + 22 + 4
local frame
local rows = {}

local function build()
  local anchor = EditModeManagerFrame
  frame = CreateFrame("Frame", "SiftLootAdvisorEditModePanel", UIParent)
  frame:SetFrameStrata(anchor:GetFrameStrata() or "DIALOG")
  frame:SetFrameLevel((anchor:GetFrameLevel() or 0) + 5)
  frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
  frame:SetSize(WIDTH, TOP + ROW_H + 12)
  frame.rows = rows

  frame.border = CreateFrame("Frame", nil, frame, "DialogBorderTranslucentTemplate")
  frame.border:SetAllPoints()

  frame.title = frame:CreateFontString(nil, "ARTWORK")
  frame.title:SetFontObject("GameFontHighlightLarge")
  frame.title:SetPoint("TOP", 0, -12)
  frame.title:SetText("Sift")
  frame:Hide()
end

local function row(i, sys)
  local r = rows[i]
  if not r then
    r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 20, ROW_H)

    r.button = CreateFrame("CheckButton", nil, r)
    r.button:SetSize(32, 32)
    r.button:SetPoint("LEFT", 0, 0)
    r.button:SetNormalTexture(CHECKBOX .. "Up")
    r.button:SetPushedTexture(CHECKBOX .. "Down")
    r.button:SetHighlightTexture(CHECKBOX .. "Highlight", "ADD")
    r.button:SetCheckedTexture(CHECKBOX .. "Check")
    r.button:SetScript("OnClick", Guard.Wrap(function(b)
      r.sys.spec.toggle.set(b:GetChecked() and true or false)
      ns.EditMode.Refresh(r.sys)
    end))

    r.label = r:CreateFontString(nil, "ARTWORK")
    r.label:SetFontObject("GameFontHighlightMedium")
    r.label:SetJustifyH("LEFT")
    r.label:SetSize(WIDTH - 60, ROW_H)
    r.label:SetPoint("LEFT", r.button, "RIGHT", 5, 0)
    rows[i] = r
  end
  r.sys = sys
  r.label:SetText(sys.spec.toggleLabel or sys.spec.name)
  r.button:SetChecked(sys.spec.toggle.get() and true or false)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -TOP - (i - 1) * ROW_H)
  r:Show()
end

function Panel.Show()
  if not EditModeManagerFrame then return end
  if not frame then build() end
  local n = 0
  for _, sys in ipairs(ns.EditMode.Systems()) do
    if sys.spec.toggle then
      n = n + 1
      row(n, sys)
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  if n == 0 then frame:Hide() return end
  frame:SetHeight(TOP + n * ROW_H + 12)
  frame:Show()
end

function Panel.Hide()
  if frame then frame:Hide() end
end

function Panel.Frame()
  return frame
end
