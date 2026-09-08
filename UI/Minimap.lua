-- Minimap button. No library; position is an angle saved in prefs.
local ADDON, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local Style, Guard = ns.Style, ns.Guard
local button
local RADIUS = 80

local function angleToPoint(angle)
  local rad = math.rad(angle)
  return math.cos(rad) * RADIUS, math.sin(rad) * RADIUS
end

local function place()
  local x, y = angleToPoint(ns.db.prefs.minimapAngle or 200)
  button:ClearAllPoints()
  button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

local function counts()
  local waiting, sends = 0, 0
  local me = ns.Character.Key()
  for _, h in pairs(ns.db.holds) do
    if h.owner == me then
      if h.kind == "SEND" then sends = sends + 1 else waiting = waiting + 1 end
    end
  end
  return waiting, sends
end

local function onDragUpdate()
  local mx, my = _G.Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = _G.Minimap:GetEffectiveScale() or 1
  if not mx or not cx then return end
  cx, cy = cx / scale, cy / scale
  local angle = math.deg(math.atan2(cy - my, cx - mx))
  ns.db.prefs.minimapAngle = angle
  place()
end

local function build()
  button = CreateFrame("Button", "SiftLootAdvisorMinimapButton", _G.Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  local overlay = button:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetPoint("TOPLEFT", 7, -5)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture(ns.Style.LOGO)
  icon:SetPoint("TOPLEFT", 7, -6)
  button.icon = icon

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", Guard.Wrap(function(_, which)
    if which == "RightButton" then ns.Options.Open() else ns.Panel.Toggle() end
  end))
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", Guard.Wrap(onDragUpdate))
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", Guard.Wrap(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Sift", Style.TEXT[1], Style.TEXT[2], Style.TEXT[3])
    local waiting, sends = counts()
    local m = Style.MUTED
    if waiting == 0 and sends == 0 then
      GameTooltip:AddLine("Nothing waiting on you.", m[1], m[2], m[3])
    else
      if waiting > 0 then GameTooltip:AddLine(string.format("%d waiting on crests, charges or a spec swap", waiting), m[1], m[2], m[3]) end
      if sends > 0 then GameTooltip:AddLine(string.format("%d to drop in the warband bank", sends), m[1], m[2], m[3]) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: panel. Right-click: settings. Drag to move.", m[1], m[2], m[3])
    GameTooltip:Show()
  end))
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
end

function Minimap.Init()
  if not _G.Minimap then return end
  Minimap.Refresh()
end

function Minimap.Refresh()
  if ns.db.prefs.minimap == false then
    if button then button:Hide() end
    return
  end
  if not button then build() end
  button:Show()
end
