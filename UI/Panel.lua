-- The /sift panel: one column, grouped by what to do next. Built on first
-- open, rows pooled, no OnUpdate.
local ADDON, ns = ...

local Panel = {}
ns.Panel = Panel

local Style, Guard = ns.Style, ns.Guard
local WIDTH, PAD = 520, 14
local MIN_W, MIN_H, MAX_W, MAX_H_HARD = 480, 220, 1100, 1400
local ROW_H, HEADER_H, GAP = 54, 30, 6
local TOP_H, FOOT_H = 44, 34
local ICON_W, META_W = 48, 150
local REASON_TOP, ROW_PAD = 26, 8
local VENDOR_AUTO_OPEN = 3

local frame, scroll, content, thumb, footer, empty
local listH = 10 -- height of the laid-out list, set by layout()

-- The visible height of the list, from the frame's own height so it is
-- right in the same frame a resize or relayout changed it.
local function viewHeight()
  return math.max(1, (frame:GetHeight() or 0) - (TOP_H + 8) - FOOT_H)
end
local rows, headers = {}, {}
local rowsUsed, headersUsed = 0, 0

local function savePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  ns.db.prefs.panelPos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- The player's own size sticks; otherwise the height follows the content
-- up to most of the screen.
local function saveSize()
  ns.db.prefs.panelSize = { w = math.floor(frame:GetWidth() + 0.5), h = math.floor(frame:GetHeight() + 0.5) }
end

local function resetSize()
  ns.db.prefs.panelSize = nil
  frame:SetWidth(WIDTH)
end

local function maxHeight()
  local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
  if not screen or screen < 400 then screen = 900 end
  return math.floor(screen * 0.7)
end

local function restorePosition()
  local p = ns.db.prefs.panelPos
  frame:ClearAllPoints()
  if p and p.point then
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  end
end

local function updateThumb()
  local viewH = scroll:GetHeight()
  local totalH = content:GetHeight()
  if totalH <= viewH + 1 then thumb:Hide() return end
  local trackH = viewH
  local h = math.max(18, trackH * (viewH / totalH))
  local offset = (scroll:GetVerticalScroll() / (totalH - viewH)) * (trackH - h)
  thumb:SetHeight(h)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -offset)
  thumb:Show()
end

-- Six dots in the corner: drag to resize, double-click to reset.
local function buildGrip()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(18, 18)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip.dots = {}
  for _, pos in ipairs({ { 2, 2 }, { 6, 2 }, { 10, 2 }, { 2, 6 }, { 6, 6 }, { 2, 10 } }) do
    local d = grip:CreateTexture(nil, "OVERLAY")
    d:SetSize(2, 2)
    d:SetColorTexture(Style.MUTED[1], Style.MUTED[2], Style.MUTED[3], 0.8)
    d:SetPoint("BOTTOMRIGHT", -pos[1], pos[2])
    grip.dots[#grip.dots + 1] = d
  end
  local function tint(rgb, a)
    for _, d in ipairs(grip.dots) do d:SetColorTexture(rgb[1], rgb[2], rgb[3], a) end
  end
  grip:RegisterForDrag("LeftButton")
  grip:RegisterForClicks("LeftButtonUp")
  grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnDragStop", Guard.Wrap(function()
    frame:StopMovingOrSizing()
    saveSize()
    savePosition()
    Panel.Refresh()
  end))
  grip:SetScript("OnDoubleClick", Guard.Wrap(function() resetSize(); Panel.Refresh() end))
  grip:SetScript("OnEnter", function(g)
    tint(Style.TEXT, 1)
    GameTooltip:SetOwner(g, "ANCHOR_LEFT")
    GameTooltip:SetText("Drag to resize. Double-click to let the panel size itself.")
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() tint(Style.MUTED, 0.8); GameTooltip:Hide() end)
  return grip
end

local function build()
  frame = CreateFrame("Frame", "SiftLootAdvisorPanel", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 320)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H_HARD) end
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop", Guard.Wrap(function(f) f:StopMovingOrSizing(); savePosition() end))
  Style.Backdrop(frame)
  restorePosition()
  local size = ns.db.prefs.panelSize
  if size and size.w then frame:SetWidth(size.w) end
  frame:Hide()

  Style.Logo(frame, PAD, TOP_H)

  local title = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(title, Style.SIZE.title, Style.TEXT, "LEFT")
  title:SetPoint("TOPLEFT", PAD + Style.LOGO_W + 8, -PAD)
  title:SetText("Sift")
  frame.title = title

  local who = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(who, Style.SIZE.body, Style.MUTED, "LEFT")
  who:SetPoint("LEFT", title, "RIGHT", 10, -1)
  who:SetWordWrap(false)
  frame.who = who

  local close = Style.TextButton(frame, "Close", Style.SIZE.body, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
  frame.close = close

  -- The rest of Sift, one word each, so nothing stays chat-only.
  frame.tools = {}
  frame.toolsWidth = 0
  local anchorTo = close
  for _, t in ipairs({
    { "Settings", function() ns.Options.Open() end },
    { "Guide", function() ns.Guide.Toggle() end },
    { "Weights", function() ns.WeightsUI.Toggle() end },
  }) do
    local b = Style.TextButton(frame, t[1], Style.SIZE.body, t[2])
    b:SetPoint("RIGHT", anchorTo, "LEFT", -2, 0)
    b.name = t[1]
    frame.tools[#frame.tools + 1] = b
    frame.toolsWidth = frame.toolsWidth + b:GetWidth() + 2
    anchorTo = b
  end

  local rule = Style.Rule(frame)
  rule:SetPoint("TOPLEFT", PAD, -TOP_H)
  rule:SetPoint("TOPRIGHT", -PAD, -TOP_H)

  scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", PAD, -(TOP_H + 8))
  scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(s, delta)
    local maxScroll = math.max(0, listH - viewHeight())
    local next = math.max(0, math.min(maxScroll, s:GetVerticalScroll() - delta * ROW_H))
    s:SetVerticalScroll(next)
    updateThumb()
  end)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - PAD * 2, 10)
  scroll:SetScrollChild(content)

  thumb = frame:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(Style.MUTED[1], Style.MUTED[2], Style.MUTED[3], 0.6)
  thumb:SetWidth(2)
  thumb:Hide()

  local foot = Style.Rule(frame)
  foot:SetPoint("BOTTOMLEFT", PAD, FOOT_H - 6)
  foot:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H - 6)

  -- The footer names the weights in use and opens the weights sheet.
  footer = Style.TextButton(frame, "", Style.SIZE.meta, function() ns.WeightsUI.Toggle() end)
  footer:SetPoint("BOTTOMLEFT", PAD - 6, 4)
  footer.label:ClearAllPoints()
  footer.label:SetPoint("LEFT", 6, 0)
  footer.label:SetJustifyH("LEFT")
  footer.label:SetWordWrap(false)

  buildGrip()

  empty = content:CreateFontString(nil, "OVERLAY")
  Style.Text(empty, Style.SIZE.body, Style.MUTED, "CENTER")
  empty:SetPoint("TOP", content, "TOP", 0, -28)
  empty:SetWidth(WIDTH - PAD * 6)
  empty:SetText("Nothing waiting. Your bags hold nothing to act on; verdicts show up here as you loot gear.")
  empty:Hide()

  table.insert(UISpecialFrames, "SiftLootAdvisorPanel")
end

local function acquireHeader()
  headersUsed = headersUsed + 1
  local h = headers[headersUsed]
  if not h then
    h = CreateFrame("Button", nil, content)
    h:SetHeight(HEADER_H)
    h:RegisterForClicks("LeftButtonUp")
    h:SetScript("OnClick", Guard.Wrap(function(self)
      if not self.toggles then return end
      ns.db.prefs.vendorOpen = not self.open
      Panel.Refresh()
    end))
    h.text = h:CreateFontString(nil, "OVERLAY")
    Style.Text(h.text, Style.SIZE.body, Style.MUTED, "LEFT")
    h.text:SetPoint("BOTTOMLEFT", 0, 7)
    h.rule = Style.Rule(h)
    h.rule:SetPoint("BOTTOMLEFT", 0, 2)
    h.rule:SetPoint("BOTTOMRIGHT", 0, 2)
    h.count = h:CreateFontString(nil, "OVERLAY")
    Style.Text(h.count, Style.SIZE.meta, Style.DIM, "RIGHT")
    h.count:SetPoint("BOTTOMRIGHT", 0, 7)
    headers[headersUsed] = h
  end
  h:Show()
  return h
end

local function onRowEnter(row)
  row.hover:Show()
  if row.dismissable then row.dismiss:Show() end
  if row.ackable then row.act:Show() end
  if row.tellable then
    row.tell.label:SetText(ns.GroupChat.Label())
    row.tell:SetWidth(row.tell.label:GetStringWidth() + 12)
    row.tell:Show()
  end
  if row.link then
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row.link)
    GameTooltip:Show()
  end
end

local function onRowLeave(row)
  row.hover:Hide()
  if row.dismiss and not row.dismiss:IsMouseOver() then row.dismiss:Hide() end
  if row.act and not row.act:IsMouseOver() then row.act:Hide() end
  if row.tell and not row.tell:IsMouseOver() then row.tell:Hide() end
  GameTooltip:Hide()
end

local function acquireRow()
  rowsUsed = rowsUsed + 1
  local r = rows[rowsUsed]
  if not r then
    r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(unpack(Style.ROW_HOVER))
    r.hover:Hide()

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(34, 34)
    r.icon:SetPoint("TOPLEFT", 4, -10)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.verb = r:CreateFontString(nil, "OVERLAY")
    Style.Text(r.verb, Style.SIZE.verdict, Style.TEXT, "RIGHT")
    r.verb:SetPoint("TOPRIGHT", -6, -7)

    r.meta = r:CreateFontString(nil, "OVERLAY")
    Style.Text(r.meta, Style.SIZE.meta, Style.MUTED, "RIGHT")
    r.meta:SetPoint("TOPRIGHT", r.verb, "BOTTOMRIGHT", 0, -5)
    r.meta:SetWidth(META_W)
    r.meta:SetWordWrap(false)

    r.name = r:CreateFontString(nil, "OVERLAY")
    Style.Text(r.name, Style.SIZE.name, Style.TEXT, "LEFT")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.name:SetPoint("RIGHT", r.verb, "LEFT", -12, 0)
    r.name:SetWordWrap(false)

    -- Two fixed lines under the name, both flush with it. The first
    -- opens with the gain in the verdict's color, then the versus text
    -- and condition; the second is one muted clause of nuance and may
    -- be empty.
    r.versus = r:CreateFontString(nil, "OVERLAY")
    Style.Text(r.versus, Style.SIZE.body, Style.TEXT, "LEFT")
    r.versus:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.versus:SetJustifyV("TOP")
    r.versus:SetWordWrap(true)
    if r.versus.SetMaxLines then r.versus:SetMaxLines(2) end

    -- The note, or the whole reason for rows without a brief.
    r.reason = r:CreateFontString(nil, "OVERLAY")
    Style.Text(r.reason, Style.SIZE.body, Style.MUTED, "LEFT")
    r.reason:SetJustifyV("TOP")
    r.reason:SetWordWrap(true)
    if r.reason.SetMaxLines then r.reason:SetMaxLines(4) end

    r.dismiss = Style.TextButton(r, "Dismiss", Style.SIZE.meta, function()
      if r.guid then ns.Verdicts.ClearHold(r.guid) end
      ns.Triggers.SyncWakeEvents()
      Panel.Refresh()
    end)
    r.dismiss:SetPoint("RIGHT", r.verb, "LEFT", -4, 0)
    r.dismiss:Hide()
    r.dismiss:SetScript("OnLeave", function() r.dismiss.label:SetTextColor(unpack(Style.MUTED)); if not r:IsMouseOver() then r.dismiss:Hide(); r.act:Hide(); r.hover:Hide() end end)

    -- "Will send" on a suggested send: the sender's word that it is happening.
    r.act = Style.TextButton(r, "Will send", Style.SIZE.meta, function()
      if r.guid and ns.Verdicts.AckSend(r.guid) then Panel.Refresh() end
    end)
    r.act:SetPoint("RIGHT", r.dismiss, "LEFT", -4, 0)
    r.act:Hide()
    r.act:SetScript("OnLeave", function() r.act.label:SetTextColor(unpack(Style.MUTED)); if not r:IsMouseOver() then r.act:Hide(); r.dismiss:Hide(); r.hover:Hide() end end)

    -- "Tell party" on a piece the group could still be traded.
    r.tell = Style.TextButton(r, "Tell party", Style.SIZE.meta, function()
      if r.entry then ns.GroupChat.Tell(r.entry.facts, r.entry.verdict) end
    end)
    r.tell:SetPoint("RIGHT", r.act, "LEFT", -4, 0)
    r.tell:Hide()
    r.tell:SetScript("OnLeave", function() r.tell.label:SetTextColor(unpack(Style.MUTED)); if not r:IsMouseOver() then r.tell:Hide(); r.act:Hide(); r.dismiss:Hide(); r.hover:Hide() end end)

    r.siftRow = true
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", onRowEnter)
    r:SetScript("OnLeave", onRowLeave)
    r:SetScript("OnClick", Guard.Wrap(function(self)
      if IsShiftKeyDown() and self.link and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end))
    rows[rowsUsed] = r
  end
  r:Show()
  return r
end

-- A brief for a row that adds its own note, or drops the alt's name when
-- the row is on the alt's own panel.
local function briefWith(b, note, mine)
  if not b then return nil end
  local out = {}
  for k, val in pairs(b) do out[k] = val end
  out.note = note
  if mine then out.who = nil end
  return out
end

local function classIconOf(key)
  local c = key and ns.db.chars[key]
  return Style.ClassIcon(c and c.classFile)
end

local function currencyIcon(key)
  return Style.IconText(ns.Resources.Icon(key))
end

local function wakeText(h)
  local w = h.wake
  if h.ready then
    if h.sub == "catalyst" then return currencyIcon("catalyst") .. "charge ready" end
    if h.sub == "upgrade" then return currencyIcon(h.track) .. "crests in hand" end
    if h.sub == "instead" then return currencyIcon(h.instead and h.instead.track or h.track) .. "crests in hand" end
    return "ready"
  end
  if h.sub == "set" then return "tier slot in use" end
  if h.sub == "offspec" then return "other spec" end
  if not w then return "" end
  if w.type == "crests" then return currencyIcon(w.track) .. string.format("%d %s Mistcrests", w.need or 0, w.track or "") end
  if w.type == "catalyst" then return currencyIcon("catalyst") .. "next catalyst charge" end
  if w.type == "bank" then return "to " .. (h.target or "an alt") end
  if w.type == "level" then return string.format("level %d", w.need or 0) end
  return ""
end

-- Gather rows into ordered groups.
local function collect()
  local Verdicts = ns.Verdicts
  local groups = {
    { key = "vault", title = "Great Vault, pick one", items = {} },
    { key = "now", title = "Do now", items = {} },
    { key = "wait", title = "Waiting on crests or charges", items = {} },
    { key = "sim", title = "Too close to call, sim it", items = {} },
    { key = "keep", title = "Keeping for later", items = {} },
    { key = "send", title = "For alts", items = {} },
    { key = "banked", title = "In the warband bank", items = {} },
    { key = "held", title = "On the way to you", items = {} },
    { key = "vendor", title = "Vendor or disenchant", items = {} },
  }
  local byKey = {}
  for _, g in ipairs(groups) do byKey[g.key] = g end

  if ns.Vault and ns.Vault.IsOpen() then
    local ranked, _, _, preview = ns.Vault.Current()
    if preview then byKey.vault.title = "Great Vault preview, example items" end
    local R = ns.VaultRank
    for _, row in ipairs(R.Collapse(ranked)) do
      local o = row.option
      table.insert(byKey.vault.items, { icon = o.icon, name = o.name, quality = o.quality, link = o.link, itemDBID = o.itemDBID,
        reason = R.Line(o), verb = R.Verb(o), kind = R.Kind(o), meta = R.SourceText(row) })
    end
  end

  for _, e in ipairs(Verdicts.SessionEquip()) do
    local f, v = e.entry.facts, e.entry.verdict
    table.insert(byKey.now.items, { icon = f.icon, name = f.name, quality = f.quality, link = f.link, gain = ns.Engine.Gain(v), entry = e.entry,
      reason = v.reason, brief = v.brief, verb = "Equip", kind = "EQUIP", meta = ns.Slots.LABEL[v.details and v.details.self and v.details.self[1] and v.details.self[1].incumbent and v.details.self[1].incumbent.slot or 0] or "" })
  end

  local catalystRows = {}
  for _, h in ipairs(Verdicts.MyHolds()) do
    local hold = h.hold
    if not h.loc then
      -- Out of the bags and into the warband bank: waiting for the alt.
      if hold.kind == "SEND" and Verdicts.SendState(hold) == "banked" then
        table.insert(byKey.banked.items, { guid = h.guid, icon = hold.icon, name = hold.name, quality = hold.quality, link = hold.link,
          reason = "In the warband bank. " .. (hold.reason or ""), brief = briefWith(hold.brief, "In the warband bank, waiting to be picked up."),
          verb = "Waiting", kind = "SEND",
          meta = classIconOf(hold.targetKey) .. "for " .. (hold.target or "an alt"), dismissable = true, gain = hold.gain,
          altKey = hold.targetKey, equipLoc = hold.equipLoc })
      end
    else
      local row = { guid = h.guid, icon = hold.icon, name = hold.name, quality = hold.quality, link = hold.link,
        reason = hold.reason, brief = hold.brief, kind = hold.kind, meta = wakeText(hold), dismissable = true, gain = hold.gain }
      -- The cached verdict behind the hold, for the Tell button; only
      -- looked up while the buttons show at all.
      if ns.GroupChat.Showing() then row.entry = Verdicts.ForBag(h.loc.bag, h.loc.slot) end
      local fake = { kind = hold.kind, sub = hold.sub, ready = hold.ready, noSim = hold.noSim }
      row.verb = ns.Engine.Headline(fake)
      if hold.kind == "SEND" then
        row.altKey, row.equipLoc = hold.targetKey, hold.equipLoc
        row.meta = classIconOf(hold.targetKey) .. row.meta
        -- A suggestion offers "Will send"; a marked send says what to do.
        if Verdicts.SendState(hold) == "sending" then
          row.verb = "Sending"
          row.reason = "Put it in the warband bank. " .. (hold.reason or "")
          row.brief = briefWith(hold.brief, "Put it in the warband bank.")
        else
          row.ackable = true
        end
        table.insert(byKey.send.items, row)
      elseif hold.ready then
        table.insert(byKey.now.items, row)
        if hold.sub == "catalyst" then catalystRows[#catalystRows + 1] = row end
      elseif hold.sub == "sim" then
        row.meta = "raidbots.com"
        table.insert(byKey.sim.items, row)
      elseif hold.sub == "offspec" or hold.sub == "set" then
        table.insert(byKey.keep.items, row)
      else
        table.insert(byKey.wait.items, row)
      end
    end
  end

  -- More pieces ready for the catalyst than charges to spend: say so on
  -- each, rather than "charge ready" on all of them.
  local charges = ns.Resources.Current().catalystCharges or 0
  if #catalystRows > charges then
    for _, row in ipairs(catalystRows) do
      row.meta = currencyIcon("catalyst") .. string.format("%d charge%s for %d pieces", charges, charges == 1 and "" or "s", #catalystRows)
    end
  end

  -- Sends under way to this character: marked by the sender, or already
  -- in the warband bank. A suggestion nobody acted on is not shown.
  for guid, hold in pairs(Verdicts.SendsForMe()) do
    local from = hold.owner and (hold.owner:match("^(.-)%-") or hold.owner) or "another character"
    local gist = (hold.reason or ""):gsub("^Send to [^:]+: ", "")
    local banked = Verdicts.SendState(hold) == "banked"
    table.insert(byKey.held.items, { guid = guid, icon = hold.icon, name = hold.name, quality = hold.quality, link = hold.link, gain = hold.gain,
      reason = (banked and string.format("From %s, waiting in the warband bank: ", from) or string.format("%s will send this: ", from)) .. gist,
      brief = briefWith(hold.brief, banked and string.format("From %s, waiting in the warband bank.", from) or string.format("%s will send it.", from), true),
      verb = banked and "Waiting" or "Coming", kind = "SEND",
      meta = classIconOf(hold.owner) .. (banked and "warband bank" or (from .. "'s bags")) })
  end

  byKey.vendor.total = 0
  for _, d in ipairs(Verdicts.SessionDispose()) do
    local f, v = d.entry.facts, d.entry.verdict
    byKey.vendor.total = byKey.vendor.total + (tonumber(f.sellPrice) or 0)
    table.insert(byKey.vendor.items, { icon = f.icon, name = f.name, quality = f.quality, link = f.link, gain = ns.Engine.Gain(v), entry = d.entry,
      reason = v.reason, brief = v.brief, verb = "Dispose", kind = "DISPOSE", meta = "vendor " .. Style.MoneyText(f.sellPrice) })
  end
  -- One action for the whole vendor list: collapsed past a few rows
  -- unless the player has opened it, and the header says what it holds.
  local vendorOpen = ns.db.prefs.vendorOpen
  if vendorOpen == nil then vendorOpen = #byKey.vendor.items <= VENDOR_AUTO_OPEN end
  byKey.vendor.toggles = true
  byKey.vendor.open = vendorOpen

  -- Best to worst within each group, by the gain the verdict is about.
  -- The vault group is already ranked.
  local out = {}
  for _, g in ipairs(groups) do
    if #g.items > 0 then
      if g.key ~= "vault" then ns.Engine.SortByGain(g.items) end
      out[#out + 1] = g
    end
  end
  return out
end

-- The groups as the panel would show them, for tests and debugging.
-- The i-th row frame of the last layout, for tests.
function Panel.Row(i)
  return rows[i]
end

function Panel.Header(i)
  return headers[i]
end

function Panel.Groups()
  return collect()
end

function Panel.ScrollFrame()
  return scroll
end

local function layout(groups)
  local keep = scroll:GetVerticalScroll() or 0
  for i = 1, rowsUsed do rows[i]:Hide() end
  for i = 1, headersUsed do headers[i]:Hide() end
  rowsUsed, headersUsed = 0, 0

  local y = 0
  local width = math.floor((frame:GetWidth() or WIDTH) - PAD * 2)
  content:SetWidth(width)
  local reasonWidth = math.max(120, width - ICON_W - META_W - 18)
  for _, g in ipairs(groups) do
    local h = acquireHeader()
    h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    h:SetWidth(width)
    h.text:SetText(g.title)
    h.toggles, h.open = g.toggles, g.open
    if g.toggles then
      local n = #g.items
      h.count:SetText(string.format("%d piece%s, %s  |cff%s%s|r", n, n == 1 and "" or "s", Style.MoneyText(g.total or 0),
        "e6e1d6", g.open and "Hide" or "Show"))
    else
      h.count:SetText(#g.items > 1 and tostring(#g.items) or "")
    end
    y = y + HEADER_H
    for _, item in ipairs(g.toggles and not g.open and {} or g.items) do
      local r = acquireRow()
      r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      r:SetWidth(width)
      r.guid, r.link, r.displayedItemDBID = item.guid, item.link, item.itemDBID
      ns.AltCompare.Tag(r, item.altKey, item.equipLoc)
      r.icon:SetTexture(item.icon or 134400)
      local qr, qg, qb = Style.QualityRGB(item.quality)
      r.name:SetText(item.name or "")
      r.name:SetTextColor(qr, qg, qb)
      local b = item.brief
      local textH
      if b then
        local versus = (b.who and ("for " .. b.who .. " ") or "") .. (b.versus or "")
        if b.when then versus = versus .. ", " .. b.when end
        if b.gain and b.gain ~= "" then
          versus = string.format("|cff%s%s|r %s", (b.sign and Style.GAIN_HEX[b.sign]) or "e6e1d6", b.gain, versus)
        end
        r.versus:SetWidth(reasonWidth)
        r.versus:SetText(versus)
        r.versus:Show()
        r.reason:ClearAllPoints()
        r.reason:SetPoint("TOPLEFT", r.versus, "BOTTOMLEFT", 0, -2)
        r.reason:SetWidth(reasonWidth)
        r.reason:SetText(b.note or "")
        r.reason:SetShown(b.note ~= nil and b.note ~= "")
        local vh = (r.versus.GetStringHeight and r.versus:GetStringHeight()) or 0
        local nh = b.note and ((r.reason.GetStringHeight and r.reason:GetStringHeight()) or 0) or 0
        textH = vh + (b.note and (nh + 2) or 0)
      else
        r.versus:Hide()
        r.reason:ClearAllPoints()
        r.reason:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.reason:SetWidth(reasonWidth)
        r.reason:SetText(item.reason or "")
        r.reason:Show()
        textH = (r.reason.GetStringHeight and r.reason:GetStringHeight()) or 0
      end
      r.verb:SetText(item.verb or "")
      r.verb:SetTextColor(unpack(Style.VERDICT_RGB[item.kind] or Style.TEXT))
      r.meta:SetText(item.meta or "")
      r.dismiss:Hide()
      r.act:Hide()
      r.tell:Hide()
      r.dismissable = item.dismissable
      r.ackable = item.ackable
      r.entry = item.entry
      r.tellable = item.entry ~= nil and ns.GroupChat.Offers(item.entry.facts)
      local h = math.max(ROW_H, math.ceil(textH) + REASON_TOP + ROW_PAD)
      r:SetHeight(h)
      y = y + h
    end
    y = y + GAP
  end

  if #groups == 0 then
    empty:Show()
    y = 90
  else
    empty:Hide()
  end

  listH = math.max(y, 10)
  content:SetHeight(listH)
  local size = ns.db.prefs.panelSize
  if size and size.h then
    frame:SetHeight(size.h)
  else
    local total = TOP_H + 8 + y + FOOT_H + 4
    frame:SetHeight(math.min(maxHeight(), math.max(180, total)))
  end
  -- A refresh keeps the reader's place. The offset is clamped to the new
  -- list, so a shorter list never leaves the view past its end. Opening
  -- the panel fresh starts at the top (see Toggle).
  scroll:SetVerticalScroll(math.max(0, math.min(keep, listH - viewHeight())))
  updateThumb()
end

local function footerText()
  local line, st = ns.Character.DescribeWeights()
  if st.source == "imported" then
    local age = st.ageDays and (st.ageDays == 0 and "today" or string.format("%dd ago", st.ageDays)) or ""
    local changed = st.changed and st.changed > 0 and string.format(", %d slots changed", st.changed) or ""
    return string.format("Weights: %s, %s%s.%s", st.name or "yours", age, changed, st.stale and " Re-sim." or ""), st.stale
  elseif st.source == "simc" then
    return "Weights: SimulationCraft defaults. Paste your own.", false
  end
  return "Weights: rough priorities, no sim data. Paste your own.", true
end

local function whoText(me, spec)
  local alts = ns.Character.Alts()
  local altText
  if #alts == 0 then
    altText = "no alts on file yet"
  else
    altText = string.format("%d alt%s on file", #alts, #alts == 1 and "" or "s")
  end
  return string.format("%s, %s. %s.", me.name or "", spec and spec.name or "", altText)
end

function Panel.Refresh()
  if not frame or not frame:IsShown() then return end
  local me = ns.Character.Self()
  local spec = me.specs and me.specs[1]
  frame.who:SetWidth(math.max(1, frame:GetWidth() - PAD * 2 - Style.LOGO_W
    - frame.title:GetStringWidth() - frame.close:GetWidth() - (frame.toolsWidth or 0) - 30))
  frame.who:SetText(whoText(me, spec))
  local text, nudge = footerText()
  footer.label:SetText(text)
  footer.label:SetTextColor(unpack(nudge and Style.VERDICT_RGB.HOLD or Style.MUTED))
  footer:SetScript("OnLeave", function() footer.label:SetTextColor(unpack(nudge and Style.VERDICT_RGB.HOLD or Style.MUTED)) end)
  footer:SetSize(math.min(WIDTH - 140, footer.label:GetStringWidth() + 12), Style.SIZE.meta + 8)
  layout(collect())
end

-- Opening the panel evaluates every candidate in the bags, quietly: no
-- chat, no toast. Pieces that were in the bags before Sift, or that
-- landed without an event, are on the panel the first time it opens.
function Panel.Toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() return end
  ns.Verdicts.ScanAll()
  ns.Triggers.SyncWakeEvents()
  scroll:SetVerticalScroll(0)
  frame:Show()
  Panel.Refresh()
end

function Panel.IsShown()
  return frame and frame:IsShown() or false
end
