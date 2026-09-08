-- A box of selectable text for copying out of the game (status output,
-- probe summaries). Opens with the text highlighted so Ctrl+C is all it takes.
local ADDON, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

local Style, Guard = ns.Style, ns.Guard
local WIDTH, HEIGHT, PAD = 620, 340, 14
local TOP_H = 44
local frame, box

local function build()
  frame = CreateFrame("Frame", "SiftLootAdvisorCopy", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  Style.Dialog(frame)
  Style.Backdrop(frame)
  frame:Hide()

  Style.Logo(frame, PAD, TOP_H)

  local title = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(title, Style.SIZE.title, Style.TEXT, "LEFT")
  title:SetPoint("TOPLEFT", PAD + Style.LOGO_W + 8, -PAD)
  title:SetText("Copy")
  frame.title = title

  local hint = frame:CreateFontString(nil, "OVERLAY")
  Style.Text(hint, Style.SIZE.body, Style.MUTED, "LEFT")
  hint:SetPoint("LEFT", title, "RIGHT", 10, -1)
  hint:SetText("Text is selected. Press Ctrl+C, then Escape.")

  local close = Style.TextButton(frame, "Close", Style.SIZE.body, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)

  local rule = Style.Rule(frame)
  rule:SetPoint("TOPLEFT", PAD, -TOP_H)
  rule:SetPoint("TOPRIGHT", -PAD, -TOP_H)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PAD, -52)
  scroll:SetPoint("BOTTOMRIGHT", -(PAD + 22), PAD)

  box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  box:SetWidth(WIDTH - PAD * 2 - 26)
  Style.Font(box, Style.SIZE.body)
  box:SetTextColor(unpack(Style.TEXT))
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- Read-only in practice: any edit restores the text.
  box:SetScript("OnTextChanged", function(b, userInput)
    if userInput and b.text then b:SetText(b.text); b:HighlightText() end
  end)
  scroll:SetScrollChild(box)

  table.insert(UISpecialFrames, "SiftLootAdvisorCopy")
end

-- Show text ready to copy. title is optional.
function CopyBox.Show(text, title)
  if not frame then build() end
  frame.title:SetText(title or "Copy")
  box.text = text or ""
  box:SetText(box.text)
  frame:Show()
  Style.Front(frame)
  box:SetFocus()
  box:HighlightText()
end

function CopyBox.IsShown()
  return frame and frame:IsShown() or false
end

-- What the box holds right now.
function CopyBox.Text()
  return box and box.text or nil
end
