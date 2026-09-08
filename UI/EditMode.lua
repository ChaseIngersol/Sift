-- Edit Mode for Sift's own frames. Blizzard has no public way to add an
-- addon frame as a system, so each registered frame gets the dress a
-- system gets, drawn with Blizzard's own atlases: the translucent rounded
-- selection, the hover glow with "Click to Edit", the name once selected,
-- and a settings dialog beside it. Nothing of the manager is touched; it
-- only announces itself through EventRegistry.
local ADDON, ns = ...

local EditMode = {}
ns.EditMode = EditMode

local Guard = ns.Guard

-- Blizzard's selection layout (EditModeSystemTemplates.lua): atlas names
-- with the texture kit substituted in. The utility creates the pieces.
local LAYOUT = {
  TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
  TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
  BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
  BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
  TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
  BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
  LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
  RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
  Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
  "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local HIGHLIGHT, SELECTED = "editmode-actionbar-highlight", "editmode-actionbar-selected"
local CHECKBOX = "Interface\\Buttons\\UI-CheckBox-"
local DIALOG_W, ROW_W, ROW_H, LABEL_W, GAP = 383, 343, 32, 100, 2

local systems = {}
local selected
local active = false
local dialog

local function clickToEdit()
  return HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT or "Click to Edit"
end

local function applyKit(container, kit)
  if container.kit == kit then return true end
  if NineSliceUtil and NineSliceUtil.ApplyLayout then
    NineSliceUtil.ApplyLayout(container, LAYOUT, kit)
    container.kit = kit
    return true
  end
  return false
end

----------------------------------------------------------------------------
-- Selection overlay
----------------------------------------------------------------------------
local function updateLabel(sys)
  local o = sys.overlay
  if sys == selected then
    o.label:SetText(sys.spec.name)
    o.label:Show()
  elseif sys.hovered then
    o.label:SetText(clickToEdit())
    o.label:Show()
  else
    o.label:Hide()
  end
end

local function hover(sys, on)
  sys.hovered = on
  sys.overlay.glow:SetShown(on)
  updateLabel(sys)
  if on and sys ~= selected then
    GameTooltip:SetOwner(sys.overlay, "ANCHOR_CURSOR")
    GameTooltip:SetText(sys.spec.name)
    GameTooltip:Show()
  else
    GameTooltip:Hide()
  end
end

local function buildOverlay(sys)
  local f = sys.frame
  local o = CreateFrame("Frame", nil, f, "BackdropTemplate")
  o:SetAllPoints()
  o:SetFrameLevel((f:GetFrameLevel() or 0) + 40)
  o:EnableMouse(true)
  o:RegisterForDrag("LeftButton")

  -- The hover glow: the highlight kit again, faint and additive.
  o.glow = CreateFrame("Frame", nil, o)
  o.glow:SetAllPoints()
  o.glow:SetAlpha(0.4)
  o.glow:Hide()
  if applyKit(o.glow, HIGHLIGHT) then
    for _, name in ipairs(PIECES) do
      local piece = o.glow[name]
      if piece and piece.SetBlendMode then piece:SetBlendMode("ADD") end
    end
  end
  if not applyKit(o, HIGHLIGHT) then
    -- No nine-slice utility: a plain edge in the selection color.
    o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    o:SetBackdropBorderColor(0.498, 0.843, 1, 1)
  end

  o.label = o:CreateFontString(nil, "OVERLAY")
  o.label:SetFontObject("GameFontHighlightLarge")
  o.label:SetAllPoints()
  o.label:SetJustifyH("CENTER")
  o.label:Hide()

  o:SetScript("OnEnter", Guard.Wrap(function() hover(sys, true) end))
  o:SetScript("OnLeave", Guard.Wrap(function() hover(sys, false) end))
  o:SetScript("OnMouseDown", Guard.Wrap(function() EditMode.Select(sys) end))
  o:SetScript("OnDragStart", function() f:StartMoving() end)
  o:SetScript("OnDragStop", Guard.Wrap(function()
    f:StopMovingOrSizing()
    if sys.spec.onDrop then sys.spec.onDrop() end
  end))
  sys.overlay = o
end

----------------------------------------------------------------------------
-- Settings dialog: Blizzard's translucent dialog border, a title, one
-- row per setting, buttons under them.
----------------------------------------------------------------------------
local function buildDialog()
  local d = CreateFrame("Frame", "SiftLootAdvisorEditModeDialog", UIParent)
  d:SetSize(DIALOG_W, 200)
  d:SetFrameStrata("DIALOG")
  d:SetFrameLevel(200)
  d:SetMovable(true)
  d:SetClampedToScreen(true)
  d:EnableMouse(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", function(f) f:StartMoving() end)
  d:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)

  d.border = CreateFrame("Frame", nil, d, "DialogBorderTranslucentTemplate")
  d.border:SetAllPoints()

  d.title = d:CreateFontString(nil, "ARTWORK")
  d.title:SetFontObject("GameFontHighlightLarge")
  d.title:SetPoint("TOP", 0, -15)

  d.close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
  d.close:SetPoint("TOPRIGHT", 0, 0)
  d.close:SetScript("OnClick", Guard.Wrap(function() EditMode.Deselect() end))

  d.rows, d.buttons = {}, {}
  d:Hide()
  return d
end

local function rowLabel(row, text)
  row.label = row:CreateFontString(nil, "ARTWORK")
  row.label:SetFontObject("GameFontHighlightMedium")
  row.label:SetJustifyH("LEFT")
  row.label:SetSize(LABEL_W, ROW_H)
  row.label:SetPoint("LEFT")
  row.label:SetText(text)
end

local function sliderRow(row, s)
  rowLabel(row, s.label)
  local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
  slider:SetSize(200, ROW_H)
  slider:SetPoint("LEFT", row.label, "RIGHT", 5, 0)
  row.control = slider
  local Mixin = MinimalSliderWithSteppersMixin or {}
  local formatters = {}
  if CreateMinimalSliderFormatter and Mixin.Label then
    formatters[Mixin.Label.Right] = CreateMinimalSliderFormatter(Mixin.Label.Right, s.format or function(v) return tostring(v) end)
  end
  local step = s.step or 1
  row.init = true
  if slider.Init then slider:Init(s.get(), s.min, s.max, (s.max - s.min) / step, formatters) end
  row.init = false
  local event = Mixin.Event and Mixin.Event.OnValueChanged or "OnValueChanged"
  if slider.RegisterCallback then
    slider:RegisterCallback(event, function(_, value)
      if not row.init then row.apply(value) end
    end, row)
  end
end

local function dropdownRow(row, s)
  rowLabel(row, s.label)
  local dd = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
  dd:SetPoint("LEFT", row.label, "RIGHT", 5, 0)
  dd:SetWidth(200)
  row.control = dd
  if dd.SetupMenu then
    dd:SetupMenu(function(_, root)
      for _, option in ipairs(s.options) do
        root:CreateRadio(option.text, function(v) return s.get() == v end, function(v) row.apply(v) end, option.value)
      end
    end)
  end
end

local function checkboxRow(row, s)
  local b = CreateFrame("CheckButton", nil, row)
  b:SetSize(32, 32)
  b:SetPoint("LEFT", -5, 0)
  b:SetNormalTexture(CHECKBOX .. "Up")
  b:SetPushedTexture(CHECKBOX .. "Down")
  b:SetHighlightTexture(CHECKBOX .. "Highlight", "ADD")
  b:SetCheckedTexture(CHECKBOX .. "Check")
  b:SetDisabledCheckedTexture(CHECKBOX .. "Check-Disabled")
  b:SetChecked(s.get() and true or false)
  b:SetScript("OnClick", Guard.Wrap(function(self) row.apply(self:GetChecked() and true or false) end))
  row.control = b
  row.label = row:CreateFontString(nil, "ARTWORK")
  row.label:SetFontObject("GameFontHighlightMedium")
  row.label:SetJustifyH("LEFT")
  row.label:SetSize(300, ROW_H)
  row.label:SetPoint("LEFT", b, "RIGHT", 5, 0)
  row.label:SetText(s.label)
end

local BUILDERS = { slider = sliderRow, dropdown = dropdownRow, checkbox = checkboxRow }

-- Rows and buttons are built once per system and reused.
local function populate(sys)
  local d = dialog
  for _, r in ipairs(d.rows) do r:Hide() end
  for _, b in ipairs(d.buttons) do b:Hide() end
  d.title:SetText(sys.spec.name)
  sys.rows = sys.rows or {}
  sys.buttonFrames = sys.buttonFrames or {}
  local y = -15 - 24 - 12
  for i, s in ipairs(sys.spec.settings or {}) do
    local row = sys.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, d)
      row:SetSize(ROW_W, ROW_H)
      row.apply = function(value)
        s.set(value)
        if sys.spec.onChange then sys.spec.onChange() end
      end
      local build = BUILDERS[s.type]
      if build then build(row, s) end
      sys.rows[i] = row
      d.rows[#d.rows + 1] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOP", d, "TOP", 0, y)
    row:Show()
    y = y - ROW_H - GAP
  end
  y = y - 10
  for i, b in ipairs(sys.spec.buttons or {}) do
    local btn = sys.buttonFrames[i]
    if not btn then
      btn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
      btn:SetSize(130, 22)
      btn:SetText(b.text)
      btn:SetScript("OnClick", Guard.Wrap(function()
        b.onClick()
        if sys.spec.onChange then sys.spec.onChange() end
      end))
      sys.buttonFrames[i] = btn
      d.buttons[#d.buttons + 1] = btn
    end
    btn:ClearAllPoints()
    btn:SetPoint("TOP", d, "TOP", 0, y)
    btn:Show()
    y = y - 22 - GAP
  end
  d:SetHeight(-y + 20)
end

-- Beside the system, on whichever side has room.
local function anchorDialog(sys)
  local d = dialog
  d:ClearAllPoints()
  local right, screen = sys.frame:GetRight(), UIParent:GetRight()
  if right and screen and right + 20 + DIALOG_W > screen then
    d:SetPoint("TOPRIGHT", sys.frame, "TOPLEFT", -20, 0)
  else
    d:SetPoint("TOPLEFT", sys.frame, "TOPRIGHT", 20, 0)
  end
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------
-- spec = {
--   name,            the label once selected and the dialog title
--   onEnter,         called when Edit Mode opens; returns the frame to
--                    dress, or nil when there is nothing to place
--   onExit,          called when Edit Mode closes
--   onDrop,          called after a drag ends
--   onChange,        called after any setting or button
--   settings = { { type = "slider"|"dropdown"|"checkbox", label, get, set, ... } },
--   buttons = { { text, onClick } },
-- }
function EditMode.Register(spec)
  local sys = { spec = spec }
  systems[#systems + 1] = sys
  return sys
end

function EditMode.Select(sys)
  if selected == sys then return end
  local old = selected
  selected = sys
  if old and old.overlay then
    applyKit(old.overlay, HIGHLIGHT)
    updateLabel(old)
  end
  applyKit(sys.overlay, SELECTED)
  updateLabel(sys)
  GameTooltip:Hide()
  if not dialog then dialog = buildDialog() end
  populate(sys)
  anchorDialog(sys)
  dialog:Show()
end

function EditMode.Deselect()
  local old = selected
  selected = nil
  if old and old.overlay then
    applyKit(old.overlay, HIGHLIGHT)
    updateLabel(old)
  end
  if dialog then dialog:Hide() end
end

-- Show or hide one system's placeholder and overlay for the current
-- state of its toggle.
local function dress(sys)
  local frame = sys.spec.onEnter and sys.spec.onEnter()
  if frame then
    if sys.overlay and sys.frame ~= frame then sys.overlay:Hide(); sys.overlay = nil end
    sys.frame = frame
    if not sys.overlay then buildOverlay(sys) end
    applyKit(sys.overlay, HIGHLIGHT)
    sys.hovered = false
    updateLabel(sys)
    sys.overlay:Show()
  else
    if sys == selected then EditMode.Deselect() end
    if sys.overlay then sys.overlay:Hide() end
    if sys.spec.onExit then sys.spec.onExit() end
  end
end

function EditMode.Enter()
  active = true
  for _, sys in ipairs(systems) do dress(sys) end
  if ns.EditModePanel then ns.EditModePanel.Show() end
end

-- A system's toggle changed while Edit Mode is open.
function EditMode.Refresh(sys)
  if active then dress(sys) end
end

function EditMode.Exit()
  if not active then return end
  active = false
  EditMode.Deselect()
  if ns.EditModePanel then ns.EditModePanel.Hide() end
  for _, sys in ipairs(systems) do
    if sys.overlay then
      sys.overlay.glow:Hide()
      sys.overlay.label:Hide()
      sys.overlay:Hide()
    end
    if sys.spec.onExit then sys.spec.onExit() end
  end
end

function EditMode.IsActive() return active end
function EditMode.Selected() return selected end
function EditMode.Systems() return systems end
function EditMode.Dialog() return dialog end

if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("EditMode.Enter", function() Guard.Call(EditMode.Enter) end, EditMode)
  EventRegistry:RegisterCallback("EditMode.Exit", function() Guard.Call(EditMode.Exit) end, EditMode)
end
