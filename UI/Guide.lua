-- The guide: four pages on what Sift says, where it shows up, what to do
-- first and what to know. Opens once, at the first login, and after that
-- from /sift guide, the panel and settings. Built on first show; nothing
-- runs while it is closed.
local ADDON, ns = ...

local Guide = {}
ns.Guide = Guide

local Style, Guard = ns.Style, ns.Guard
local WIDTH, PAD = 620, 18
local TOP_H, FOOT_H = 48, 42
local BODY_W = WIDTH - PAD * 2
local WORD_W = 96   -- the verdict column on the first page
local LABEL_W = 132 -- the surface column on the second
local ROW_GAP, PARA_GAP = 12, 9

local frame, pages, current, counter, backBtn, nextBtn

-- The five words, in their colors. The spine of the first page.
local LEGEND = {
  { "Equip", "EQUIP", "Better than what you wear for your active spec, by the numbers." },
  { "Hold", "HOLD", "Keep it. It wins after upgrades, completes a tier set with the catalyst, or needs a level. The panel says what it is waiting for." },
  { "Sim it", "HOLD", "Too close to call, or a trinket. Only a sim can answer, and Sift would rather say so than guess. Healers see Your call instead, since Raidbots does not sim healing." },
  { "Send", "SEND", "An alt on file wants it more than you do. Press Will send in the panel, then drop it in the warband bank." },
  { "Dispose", "DISPOSE", "Nothing you or your alts can use. Vendor or disenchant." },
}

local SURFACES = {
  { "Tooltip", "One line on every piece you could equip: the verdict and its reason. Hold Shift for the math, or hover a row in the panel." },
  { "Chat", "One line per new verdict, held until you are out of combat. Switch it off in settings if the panel is enough." },
  { "Panel", "/sift, the minimap button, or the addon compartment. Everything waiting on you, grouped by what to do next." },
  { "Toast", "A small card per verdict, at the same safe moments as chat. A click clears a row, Dismiss clears the stack. Place it in Edit Mode; switch it off in settings if the panel is enough." },
  { "Rolls, vault, bank", "A word beside Need and Greed, a ranking under the Great Vault, and reminders when you open a bank." },
}

local STEPS = {
  { "Paste your stat weights (optional but recommended). Sift ships SimulationCraft defaults for most specs, but your own Raidbots weights account for your talents and gear. The sheet walks you through it.",
    "Open the weights sheet", function() ns.WeightsUI.Show() end },
  { "Log into each alt once. Sift remembers their gear, so a drop that helps an alt more than you becomes a Send." },
  { "Pick your surfaces. The chat line, the toast, the quality floor and the lowest track to catalyze are all in settings.",
    "Open settings", function() Guide.Aside(ns.Options.Open) end },
}

local NOTES = {
  "Weights are estimates. When two pieces sit inside the margin of error the answer is Sim it (Your call for healers), not a guess.",
  "Effects are not scored. A trinket always says Sim it. Any other piece with an on-equip effect gets a note, and one you already wear is judged on its stats alone.",
  "A Send is a suggestion until you press Will send. From there Sift follows the piece into the warband bank and tells the alt it is waiting.",
  "Park a character in settings to keep it out of send suggestions. It still gets its own verdicts.",
  "Nothing is equipped, sold or moved for you. Sift only advises.",
}

-- Layout helpers. A page is laid out top down; p.y is the running height.
local function newPage(title)
  local p = CreateFrame("Frame", nil, frame)
  p:SetPoint("TOPLEFT", PAD, -(TOP_H + 12))
  p:SetSize(BODY_W, 10)
  p:Hide()
  p.y = 0
  local t = p:CreateFontString(nil, "OVERLAY")
  Style.Text(t, Style.SIZE.title, Style.TEXT, "LEFT")
  t:SetPoint("TOPLEFT", 0, 0)
  t:SetWidth(BODY_W)
  t:SetText(title)
  p.y = Style.SIZE.title + 12
  return p
end

local function text(p, str, size, rgb, x, width, justify)
  local fs = p:CreateFontString(nil, "OVERLAY")
  Style.Text(fs, size, rgb, justify or "LEFT")
  fs:SetPoint("TOPLEFT", x or 0, -p.y)
  fs:SetWidth(width or (BODY_W - (x or 0)))
  fs:SetWordWrap(true)
  fs:SetJustifyV("TOP")
  fs:SetText(str)
  return fs
end

local function height(fs)
  local h = fs:GetStringHeight()
  if not h or h <= 0 then h = Style.SIZE.body + 4 end
  return h
end

-- The thing to do on a page: an outlined button, flush with the text
-- above it, placed at p.y.
local function action(p, label, onClick, x)
  local b = Style.Button(p, label, Style.SIZE.body, onClick)
  b:SetPoint("TOPLEFT", x or 0, -(p.y + 6))
  p.y = p.y + 6 + b:GetHeight()
  return b
end

local function finish(p)
  p:SetHeight(p.y)
  return p
end

local function pageWhat()
  local p = newPage("What Sift says")
  local lead = text(p, "Every rare or better piece you pick up gets one word and a reason.", Style.SIZE.body, Style.TEXT)
  p.y = p.y + height(lead) + ROW_GAP + 4
  for _, row in ipairs(LEGEND) do
    local word = text(p, row[1], Style.SIZE.verdict, Style.VERDICT_RGB[row[2]], 0, WORD_W)
    local desc = text(p, row[3], Style.SIZE.body, Style.TEXT, WORD_W, BODY_W - WORD_W)
    p.y = p.y + math.max(height(word), height(desc)) + ROW_GAP
  end
  return finish(p)
end

local function pageWhere()
  local p = newPage("Where it shows up")
  for _, row in ipairs(SURFACES) do
    local label = text(p, row[1], Style.SIZE.name, Style.TEXT, 0, LABEL_W)
    local desc = text(p, row[2], Style.SIZE.body, Style.TEXT, LABEL_W, BODY_W - LABEL_W)
    p.y = p.y + math.max(height(label), height(desc)) + ROW_GAP
  end
  return finish(p)
end

local function pageFirst()
  local p = newPage("Do this first")
  for i, step in ipairs(STEPS) do
    local n = text(p, tostring(i), Style.SIZE.body, Style.DIM, 0, 14, "RIGHT")
    local body = text(p, step[1], Style.SIZE.body, Style.TEXT, 22, BODY_W - 22)
    p.y = p.y + math.max(height(n), height(body))
    if step[2] then action(p, step[2], step[3], 22) end
    p.y = p.y + ROW_GAP
  end
  return finish(p)
end

local function pageKnow()
  local p = newPage("Good to know")
  for _, note in ipairs(NOTES) do
    local fs = text(p, note, Style.SIZE.body, Style.TEXT)
    p.y = p.y + height(fs) + PARA_GAP
  end
  p.y = p.y + 4
  local ask = text(p, "Something reads wrong? Build a report to paste to the author, with what you saw.", Style.SIZE.body, Style.MUTED)
  p.y = p.y + height(ask)
  action(p, "Send feedback", function() ns.Feedback.Show() end)
  return finish(p)
end

local function showPage(n)
  current = n
  for i, p in ipairs(pages) do p:SetShown(i == n) end
  local p = pages[n]
  frame:SetHeight(TOP_H + 12 + p:GetHeight() + FOOT_H + 4)
  counter:SetText(string.format("Page %d of %d.  /sift guide reopens this.", n, #pages))
  backBtn:SetShown(n > 1)
  nextBtn.label:SetText(n == #pages and "Done" or "Next")
  nextBtn:SetWidth(nextBtn.label:GetStringWidth() + 12)
end

local function build()
  frame = CreateFrame("Frame", "SiftLootAdvisorGuide", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 400)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  Style.Dialog(frame)
  frame:SetScript("OnHide", function() if ns.db then ns.db.prefs.guideSeen = true end end)
  Style.Backdrop(frame)
  frame:Hide()

  Style.Logo(frame, PAD, TOP_H)

  local title = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(title, Style.SIZE.title, Style.TEXT, "LEFT")
  title:SetPoint("TOPLEFT", PAD + Style.LOGO_W + 8, -PAD)
  title:SetText("Sift")

  local sub = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(sub, Style.SIZE.body, Style.MUTED, "LEFT")
  sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
  sub:SetText("How it works...")

  local close = Style.TextButton(frame, "Close", Style.SIZE.body, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)

  local rule = Style.Rule(frame)
  rule:SetPoint("TOPLEFT", PAD, -TOP_H)
  rule:SetPoint("TOPRIGHT", -PAD, -TOP_H)

  local foot = Style.Rule(frame)
  foot:SetPoint("BOTTOMLEFT", PAD, FOOT_H - 6)
  foot:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H - 6)

  counter = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(counter, Style.SIZE.meta, Style.MUTED, "LEFT")
  counter:SetPoint("BOTTOMLEFT", PAD, 14)

  nextBtn = Style.TextButton(frame, "Next", Style.SIZE.body, function() Guide.Next() end)
  nextBtn:SetPoint("BOTTOMRIGHT", -PAD + 6, 8)
  nextBtn.label:SetTextColor(unpack(Style.TEXT))
  nextBtn:SetScript("OnEnter", function() nextBtn.label:SetTextColor(unpack(Style.VERDICT_RGB.EQUIP)) end)
  nextBtn:SetScript("OnLeave", function() nextBtn.label:SetTextColor(unpack(Style.TEXT)) end)

  backBtn = Style.TextButton(frame, "Back", Style.SIZE.body, function() Guide.Back() end)
  backBtn:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)

  pages = { pageWhat(), pageWhere(), pageFirst(), pageKnow() }
  table.insert(UISpecialFrames, "SiftLootAdvisorGuide")
end

function Guide.Show(page)
  if not frame then build() end
  showPage(page or 1)
  frame:Show()
  Style.Front(frame)
end

-- The settings window is a full-area game panel, and showing one runs
-- the game's CloseAllWindows, which hides every special frame, this one
-- included. So the guide steps aside on purpose and comes back to the
-- same page once settings closes, after the game menu that closing it
-- with Escape leaves behind.
local returnPage, hooked

local function comeBack()
  local page = returnPage
  if not page or not frame then return end
  if SettingsPanel and SettingsPanel:IsShown() then return end
  if GameMenuFrame and GameMenuFrame:IsShown() then return end
  returnPage = nil
  Guide.Show(page)
end

local function hookReturn()
  if hooked then return end
  hooked = true
  for _, name in ipairs({ "SettingsPanel", "GameMenuFrame" }) do
    local f = _G[name]
    if f and f.HookScript then
      f:HookScript("OnHide", function() C_Timer.After(0, Guard.Wrap(comeBack)) end)
    end
  end
end

-- Leave for another window and return here afterwards.
function Guide.Aside(open)
  returnPage = current or 1
  hookReturn()
  if frame then frame:Hide() end
  open()
end

function Guide.Toggle()
  if frame and frame:IsShown() then frame:Hide() return end
  Guide.Show()
end

function Guide.Next()
  if not frame then return end
  if current >= #pages then Guide.Done() return end
  showPage(current + 1)
end

function Guide.Back()
  if not frame or current <= 1 then return end
  showPage(current - 1)
end

function Guide.Done()
  if ns.db then ns.db.prefs.guideSeen = true end
  if frame then frame:Hide() end
end

function Guide.Page()
  return frame and frame:IsShown() and current or nil
end

-- The first login: open the guide once, at a quiet moment. In combat a
-- chat line points the way and the guide waits for the next login.
function Guide.FirstRun()
  if not ns.db or ns.db.prefs.guideSeen then return false end
  if not ns.Triggers.IsSafe() then
    ns.Print("Sift is on. /sift opens the panel, /sift guide the tour.")
    return false
  end
  Guide.Show()
  return true
end
