-- The toast: a stack of verdict rows. Rows arrive as items land, a
-- page shows a few at a time, the wheel scrolls through the rest, and
-- the stack collapses one page per "seconds shown": the oldest page
-- leaves together and the next takes its place. Hovering pauses the
-- clock and shows the item tooltip; a click dismisses a row, shift-click
-- links the item. Placed in Edit Mode (UI/EditMode.lua): while it is
-- open the stack stands in with a page of sample rows, and its settings
-- live in the dialog beside it.
local ADDON, ns = ...

local Toast = {}
ns.Toast = Toast

local Style = ns.Style
local Guard = ns.Guard
local frame
local rows = {}        -- row frames, reused
local entries = {}     -- { t = payload, sample = bool }, arrival order
local first = 1        -- index of the first row on the page (the wheel moves it)
local pageAt           -- when the oldest page's clock started
local ticker
local pausedAt
local lastChime = 0
local editing = false

local WIDTH, ROW_H, GAP, PAD, FOOT_H = 360, 44, 4, 6, 14
local TICK = 0.25
-- Top center, under the game's own error text.
local DEFAULT = { point = "TOP", relPoint = "TOP", x = 0, y = -200 }
local ICON = ns.Style.LOGO

-- What the placeholder shows in Edit Mode: one page of rows that look
-- like the real thing.
local SAMPLES = {
  { headline = "Equip", link = "[Sample Bracers]", line = "|cff5fd3a8+3.2%|r vs Worn Bracers", quality = 4, verdict = { kind = "EQUIP" } },
  { headline = "Hold", link = "[Sample Helm]", line = "|cff5fd3a8+4.8%|r vs Worn Helm, after 2 upgrades, 40 Champion crests", quality = 3, verdict = { kind = "HOLD" } },
  { headline = "Send", link = "[Sample Ring]", line = "|cff5fd3a8+6.1%|r for an alt vs Old Ring", quality = 4, verdict = { kind = "SEND" } },
  { headline = "Dispose", link = "[Sample Cloak]", line = "|cffe07b74-4.0%|r vs Worn Cloak, still -1.2% at max", quality = 3, verdict = { kind = "DISPOSE" } },
}

local function prefs() return ns.DB.Prefs() end
local function clamp(v, lo, hi, default)
  v = tonumber(v) or default
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
function Toast.RowsShown() return clamp(prefs().toastRows, 1, 8, 3) end
function Toast.Seconds() return clamp(prefs().toastSeconds, 1, 30, 5) end
function Toast.GrowsUp() return prefs().toastGrow == "up" end

local function maxFirst()
  return math.max(1, #entries - Toast.RowsShown() + 1)
end

----------------------------------------------------------------------------
-- Position: the edge the stack grows away from is the one that is pinned,
-- so growing never moves what the player placed.
----------------------------------------------------------------------------
local function place()
  local p = ns.db and ns.db.prefs and ns.db.prefs.toastPos or DEFAULT
  frame:ClearAllPoints()
  frame:SetPoint(p.point or DEFAULT.point, UIParent, p.relPoint or p.point or DEFAULT.relPoint, p.x or 0, p.y or 0)
end

local function savePosition()
  local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
  if left and top and bottom then
    local up = Toast.GrowsUp()
    ns.db.prefs.toastPos = {
      point = up and "BOTTOM" or "TOP", relPoint = "BOTTOMLEFT",
      x = left + frame:GetWidth() / 2, y = up and bottom or top,
    }
  else
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return end
    ns.db.prefs.toastPos = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
  end
  place()
end

-- Where the item tooltip goes. Blizzard hangs the equipped comparisons
-- off the tooltip itself, on whichever side of it has room, without
-- looking at what is underneath; so the tooltip goes beside the toast
-- only when tooltip plus comparisons fit there, and otherwise above or
-- below the stack, where the comparisons can spread sideways over
-- nothing of ours. Widths are estimates; the game clamps the rest.
local TIP_W, CMP_W, TIP_GAP = 330, 310, 6
local function showTooltip(row, e)
  local link, compare = e.t.link, e.t.compare or 1
  local screenW, screenH = UIParent:GetRight(), UIParent:GetTop()
  local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (screenW and screenH and left and right and top and bottom) then
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  else
    local needed = TIP_W + compare * CMP_W
    if screenW - right >= needed then
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    elseif left >= needed then
      GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    else
      GameTooltip:SetOwner(row, "ANCHOR_PRESERVE")
      GameTooltip:ClearAllPoints()
      if bottom >= screenH - top then
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -TIP_GAP)
      else
        GameTooltip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, TIP_GAP)
      end
    end
  end
  GameTooltip:SetHyperlink(link)
  GameTooltip:Show()
end

----------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------
local function fill(r, t, sample)
  r.icon:SetTexture(sample and ICON or (t.icon or 134400))
  if sample then r.icon:SetTexCoord(0, 1, 0, 1) else r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  local cr, cg, cb = Style.VerdictRGB(t.verdict)
  r.verb:SetText(t.headline or "")
  r.verb:SetTextColor(cr, cg, cb)
  local qr, qg, qb = Style.QualityRGB(t.quality)
  r.name:SetText(t.link and t.link:match("%[(.-)%]") or "")
  r.name:SetTextColor(qr, qg, qb)
  r.line:SetText(t.line or "")
  ns.AltCompare.Tag(r, (not sample) and t.altKey or nil, t.equipLoc)
  -- One click tells the group, when the piece can be traded to it.
  r.line:ClearAllPoints()
  r.line:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 0)
  if not sample and ns.GroupChat and ns.GroupChat.Offers(t.facts) then
    r.tell.label:SetText(ns.GroupChat.Label())
    r.tell:SetWidth(r.tell.label:GetStringWidth() + 12)
    r.tell:Show()
    r.line:SetPoint("RIGHT", r.tell, "LEFT", -2, 0)
  else
    r.tell:Hide()
    r.line:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  end
end

local function newRow(i)
  local r = CreateFrame("Button", nil, frame)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp")

  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(34, 34)
  r.icon:SetPoint("LEFT", 4, 0)

  r.verb = r:CreateFontString(nil, "OVERLAY")
  Style.Text(r.verb, Style.SIZE.verdict, Style.TEXT, "LEFT")
  r.verb:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)

  r.name = r:CreateFontString(nil, "OVERLAY")
  Style.Text(r.name, Style.SIZE.name, Style.TEXT, "LEFT")
  r.name:SetPoint("LEFT", r.verb, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.name:SetWordWrap(false)

  r.line = r:CreateFontString(nil, "OVERLAY")
  Style.Text(r.line, Style.SIZE.body, Style.MUTED, "LEFT")
  r.line:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 0)
  r.line:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.line:SetWordWrap(false)

  local hover = r:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.05)

  r.tell = Style.TextButton(r, "Tell party", Style.SIZE.meta, function()
    local e = r.entry
    if editing or not e or not e.t.facts then return end
    ns.GroupChat.Tell(e.t.facts, e.t.verdict)
  end)
  r.tell:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 1)
  r.tell:Hide()

  r:SetScript("OnClick", Guard.Wrap(function(self)
    local e = self.entry
    if editing or not e then return end
    if IsShiftKeyDown() and e.t.link then
      ChatEdit_InsertLink(e.t.link)
      return
    end
    Toast.Dismiss(e)
  end))
  r:SetScript("OnEnter", Guard.Wrap(function(self)
    local e = self.entry
    if editing or not e or e.sample or not e.t.link then return end
    showTooltip(self, e)
  end))
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:EnableMouseWheel(true)
  r:SetScript("OnMouseWheel", Guard.Wrap(function(_, delta) Toast.Scroll(delta) end))
  rows[i] = r
  return r
end

-- The thumb runs along the rows: as tall as the page's share of the
-- queue, placed by how much of the queue lies beyond the top of the
-- page. On a stack growing up, later rows are above, so the top of the
-- track is the end of the queue.
local function updateThumb(up, n, last)
  local total, shown = #entries, Toast.RowsShown()
  if total <= shown or n == 0 then frame.thumb:Hide() return end
  local trackH = n * ROW_H + (n - 1) * GAP
  local h = math.max(12, trackH * (shown / total))
  local beyond = up and (total - last) or (first - 1)
  local offset = (beyond / (total - shown)) * (trackH - h)
  local top = PAD + (up and FOOT_H or 0)
  frame.thumb:SetHeight(h)
  frame.thumb:ClearAllPoints()
  frame.thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -(top + offset))
  frame.thumb:Show()
end

-- Lay the page out from the pinned edge.
local function layout()
  local up = Toast.GrowsUp()
  local shown = Toast.RowsShown()
  first = math.min(first, maxFirst())
  local last = math.min(#entries, first + shown - 1)
  for _, r in ipairs(rows) do r:Hide(); r.entry = nil end
  local n = 0
  for i = first, last do
    n = n + 1
    local e = entries[i]
    local r = rows[n] or newRow(n)
    r.entry = e
    fill(r, e.t, e.sample)
    r:EnableMouse(not editing)
    r:ClearAllPoints()
    local offset = PAD + (n - 1) * (ROW_H + GAP)
    if up then
      r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, offset)
      r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, offset)
    else
      r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -offset)
      r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -offset)
    end
    r:Show()
  end
  local height = PAD * 2 + n * ROW_H + math.max(0, n - 1) * GAP
  if #entries > shown then
    frame.footer:SetText(string.format("%d-%d of %d", first, last, #entries))
    frame.footer:ClearAllPoints()
    if up then
      frame.footer:SetPoint("TOP", frame, "TOP", 0, -3)
    else
      frame.footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 3)
    end
    frame.footer:Show()
    height = height + FOOT_H
  else
    frame.footer:Hide()
  end
  frame:SetHeight(height)
  updateThumb(up, n, last)
end

----------------------------------------------------------------------------
-- Timing. One ticker while anything is up, nothing when idle. The clock
-- belongs to the oldest page: when it runs out that page leaves together.
----------------------------------------------------------------------------
local function stopTicker()
  if ticker then ticker:Cancel(); ticker = nil end
  pausedAt = nil
  pageAt = nil
end

local function finish()
  stopTicker()
  first = 1
  UIFrameFadeOut(frame, 0.6, 1, 0)
  C_Timer.After(0.65, function()
    if #entries == 0 and not editing then frame:Hide() end
  end)
end

-- Whether any row is on the clock. Sticky rows (bank reminders) sit it
-- out; they leave through Toast.Remove or a click.
function Toast.HasClock()
  for _, e in ipairs(entries) do
    if not e.t.sticky then return true end
  end
  return false
end

-- The oldest page of ordinary rows leaves together; sticky rows stay
-- where they are.
local function dropOldestPage(now)
  local n = Toast.RowsShown()
  local removed, i = 0, 1
  while i <= #entries and removed < n do
    if entries[i].t.sticky then i = i + 1 else table.remove(entries, i); removed = removed + 1 end
  end
  first = math.max(1, first - removed)
  if #entries == 0 then finish() return end
  if Toast.HasClock() then pageAt = now else pageAt = nil; stopTicker() end
  layout()
end

local function tick()
  local now = GetTime()
  if frame:IsMouseOver() then
    pausedAt = pausedAt or now
    return
  end
  if pausedAt then
    if pageAt then pageAt = pageAt + (now - pausedAt) end
    pausedAt = nil
  end
  if pageAt and now - pageAt >= Toast.Seconds() then dropOldestPage(now) end
end

local function startTicker()
  if not ticker then ticker = C_Timer.NewTicker(TICK, Guard.Wrap(tick)) end
end

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------
local function build()
  frame = CreateFrame("Frame", "SiftLootAdvisorToast", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, PAD * 2 + ROW_H)
  -- Same stratum as the panel, well above it: a toast lands over the
  -- panel whole instead of interleaving with its rows, and the dialogs
  -- in the stratum above still cover both.
  frame:SetFrameStrata("HIGH")
  frame:SetFrameLevel(50)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  Style.Backdrop(frame)
  place()
  frame:Hide()

  frame.footer = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(frame.footer, Style.SIZE.meta, Style.MUTED, "CENTER")
  frame.footer:Hide()

  -- The panel's thin scroll thumb: an indicator in the right gutter.
  frame.thumb = frame:CreateTexture(nil, "OVERLAY")
  frame.thumb:SetColorTexture(Style.MUTED[1], Style.MUTED[2], Style.MUTED[3], 0.6)
  frame.thumb:SetWidth(2)
  frame.thumb:Hide()

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", Guard.Wrap(function(_, delta) Toast.Scroll(delta) end))
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------
-- t = { icon, headline, line, quality, verdict, link }
function Toast.Show(t)
  if editing then return end
  if not frame then build() end
  entries[#entries + 1] = { t = t }
  local now = GetTime()
  -- A row landing on the oldest page restarts that page's clock, so a
  -- burst is read as one page; rows beyond it wait their turn.
  if not pageAt or #entries <= Toast.RowsShown() then pageAt = now end
  if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
  frame:SetAlpha(1)
  frame:Show()
  layout()
  -- One chime per burst, the game's own loot-toast sound.
  if prefs().sound and now - lastChime > 1 then
    lastChime = now
    PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
  end
  startTicker()
end

-- Wheel up shows earlier rows on a stack that grows down, later rows on
-- one that grows up: whatever is further along the growing edge.
function Toast.Scroll(delta)
  if editing or #entries == 0 then return end
  local step = Toast.GrowsUp() and delta or -delta
  local target = math.max(1, math.min(maxFirst(), first + step))
  if target == first then return end
  first = target
  layout()
end

function Toast.Dismiss(e)
  for i, x in ipairs(entries) do
    if x == e then table.remove(entries, i) break end
  end
  if #entries == 0 then finish() else layout() end
end

-- Take out every row `pred(payload)` picks. Returns how many left.
function Toast.Remove(pred)
  local removed = 0
  for i = #entries, 1, -1 do
    if pred(entries[i].t) then table.remove(entries, i); removed = removed + 1 end
  end
  if removed == 0 then return 0 end
  first = math.max(1, math.min(first, #entries))
  if #entries == 0 then finish() else layout() end
  return removed
end

function Toast.Clear()
  entries = {}
  first = 1
  stopTicker()
  if frame then
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
    frame:SetAlpha(1)
    frame:Hide()
  end
end

-- How many rows are queued, how many are on the page, how many wait,
-- and where the page starts.
function Toast.Count() return #entries end
function Toast.Visible() return math.min(#entries, Toast.RowsShown()) end
function Toast.Overflow() return math.max(0, #entries - Toast.RowsShown()) end
function Toast.First() return first end
function Toast.Entries() return entries end
function Toast.Row(i) return rows[i] end

function Toast.ResetPosition()
  if ns.db and ns.db.prefs then ns.db.prefs.toastPos = nil end
  if frame then place() end
end

-- Settings changed (rows, seconds, grow): relay the page, keep the
-- pinned edge where it is.
function Toast.Refresh()
  if not frame then return end
  if ns.db.prefs.toastPos then savePosition() end
  if editing then
    Toast.EnterEditMode()
  elseif #entries > 0 then
    layout()
  end
end

-- Edit Mode. Only a toast that is turned on has a place to set. Returns
-- the frame to dress, or nil.
function Toast.EnterEditMode()
  if not prefs().toast then return nil end
  if not frame then build() end
  Toast.Clear()
  editing = true
  for i = 1, Toast.RowsShown() do
    entries[i] = { t = SAMPLES[(i - 1) % #SAMPLES + 1], sample = true }
  end
  frame:SetAlpha(1)
  place()
  frame:Show()
  layout()
  return frame
end

function Toast.ExitEditMode()
  if not editing then return end
  editing = false
  entries = {}
  first = 1
  frame:Hide()
end

function Toast.IsEditing()
  return editing
end

if ns.EditMode then
  ns.EditMode.Register({
    name = "Sift Toast",
    toggleLabel = "Toast",
    toggle = { get = function() return prefs().toast end, set = function(v) ns.db.prefs.toast = v end },
    onEnter = Toast.EnterEditMode,
    onExit = Toast.ExitEditMode,
    onDrop = savePosition,
    onChange = Toast.Refresh,
    settings = {
      { type = "slider", label = "Rows per page", min = 1, max = 8, step = 1,
        get = Toast.RowsShown, set = function(v) ns.db.prefs.toastRows = v end },
      { type = "slider", label = "Seconds shown", min = 1, max = 30, step = 1,
        format = function(v) return string.format("%ds", v) end,
        get = Toast.Seconds, set = function(v) ns.db.prefs.toastSeconds = v end },
      { type = "dropdown", label = "Grow", options = { { value = "down", text = "Down" }, { value = "up", text = "Up" } },
        get = function() return ns.db.prefs.toastGrow or "down" end, set = function(v) ns.db.prefs.toastGrow = v end },
      { type = "checkbox", label = "Sound",
        get = function() return ns.db.prefs.sound end, set = function(v) ns.db.prefs.sound = v end },
    },
    buttons = { { text = "Reset position", onClick = Toast.ResetPosition } },
  })
end
