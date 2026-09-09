-- Options through the native Settings API. Every switch registers its
-- shipped default from Adapters/DB.lua, so the Defaults button restores
-- those and not whatever was set at login. The page also carries buttons
-- for what used to be chat-only: the weights sheet, the guide, Edit Mode
-- for the toast, and the feedback report.
local ADDON, ns = ...

local Options = {}
ns.Options = Options

local category

-- Leave the settings window so a Sift frame opened from it is not
-- covered by it.
local function leaveSettings()
  if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
end

function Options.Register()
  if category then return end
  if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
  local prefs = ns.db.prefs
  local cdb = ns.cdb
  local cat = Settings.RegisterVerticalLayoutCategory("Sift")

  local function checkbox(key, name, tooltip, tbl)
    tbl = tbl or prefs
    local setting = Settings.RegisterAddOnSetting(cat, "SIFT_" .. key, key, tbl, Settings.VarType.Boolean, name, ns.DB.Default(key, tbl == cdb) and true or false)
    Settings.CreateCheckbox(cat, setting, tooltip)
    return setting
  end

  checkbox("chat", "Chat lines", "One line in chat when an item gets a verdict, delivered at a safe moment, and the reminders at a vendor, an upgrade NPC and a bank. Off, Sift speaks only through the tooltip, the panel and the toast.")
  checkbox("toast", "Toast for each verdict", "A small card with each verdict, at the same safe moments as chat. Place it in Edit Mode.")
  checkbox("sound", "Sound with the toast", "Plays the game's loot-toast chime when a toast appears, once per burst.")
  checkbox("altFirst", "Put alts ahead of offspec holds", "When an item helps an alt more than your other spec, say send instead of hold.")
  checkbox("vault", "Advise on Great Vault picks", "Ranks the vault's items under the vault window, in the panel and in chat while the vault is open.")
  checkbox("lootRoll", "Advise on loot rolls", "Puts Sift's word (Need, Greed, Pass or Sim it) beside each Need/Greed window, with the reason.")
  checkbox("bankReminder", "Remind at the bank", "When a bank opens, rows on the toast for what to deposit for alts and what is waiting for you in the warband bank. They stay until the bank closes or the item moves. The chat line follows the chat setting.")
  if ns.GroupChat and ns.GroupChat.LIVE then
    checkbox("groupChat", "Offer to tell the group", "Tell party on a toast or panel row and Say why beside a roll, in a group, for loot the group can still be traded. Nothing is posted without your click.")
  end
  checkbox("parked", "Park this character", "Parked characters never receive send suggestions.", cdb)
  checkbox("debug", "Debug mode", "Let errors reach BugSack with full traces instead of being swallowed, and list the developer commands in /sift help.")

  if Settings.RegisterProxySetting then
    local minimap = Settings.RegisterProxySetting(cat, "SIFT_minimap", Settings.VarType.Boolean, "Show minimap button", ns.DB.Default("minimap") ~= false,
      function() return prefs.minimap ~= false end,
      function(v) prefs.minimap = v and true or false; if ns.Minimap then ns.Minimap.Refresh() end end)
    Settings.CreateCheckbox(cat, minimap, "Left-click opens the panel, right-click opens settings, drag to move it around the minimap.")
  end

  if Settings.RegisterProxySetting and Settings.CreateSliderOptions then
    local threshold = Settings.RegisterProxySetting(cat, "SIFT_threshold", Settings.VarType.Number,
      "Minimum gain to call something better", ns.DB.Default("threshold") * 100,
      function() return (prefs.threshold or 0.01) * 100 end,
      function(v) prefs.threshold = (tonumber(v) or 1) / 100; ns.Verdicts.InvalidateAll() end)
    local options = Settings.CreateSliderOptions(0, 10, 0.5)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f%%", v) end)
    Settings.CreateSlider(cat, threshold, options, "Gains under this are treated as about equal.")

    local quality = Settings.RegisterProxySetting(cat, "SIFT_minQuality", Settings.VarType.Number,
      "Lowest item quality to evaluate", ns.DB.Default("minQuality"),
      function() return prefs.minQuality or 3 end,
      function(v) prefs.minQuality = tonumber(v) or 3 end)
    local qopts = Settings.CreateSliderOptions(2, 5, 1)
    local names = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
    qopts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return names[v] or tostring(v) end)
    Settings.CreateSlider(cat, quality, qopts, "Items below this quality are ignored.")
  end

  -- The lowest upgrade track worth a catalyst charge. A piece under it
  -- is never a catalyst hold; its verdict says so in a note.
  if Settings.RegisterProxySetting and Settings.CreateDropdown and Settings.CreateControlTextContainer then
    local minTrack = Settings.RegisterProxySetting(cat, "SIFT_catalystMinTrack", Settings.VarType.String,
      "Lowest track to catalyze", ns.DB.Default("catalystMinTrack"),
      function() return prefs.catalystMinTrack or "" end,
      function(v)
        prefs.catalystMinTrack = v or ""
        ns.Verdicts.InvalidateAll()
        if ns.Triggers and ns.Triggers.Refresh then ns.Triggers.Refresh() end
      end)
    local function tracks()
      local c = Settings.CreateControlTextContainer()
      c:Add("", "Any track")
      for _, t in ipairs(ns.Season.trackOrder) do c:Add(t, t) end
      return c:GetData()
    end
    Settings.CreateDropdown(cat, minTrack, tracks,
      "A piece on a lower upgrade track is not suggested for the catalyst, even when it would complete a set. Its verdict says so.")
  end

  -- Doors to the rest of Sift, for anyone who never types a command.
  if CreateSettingsButtonInitializer and SettingsPanel and SettingsPanel.GetLayout then
    local layout = SettingsPanel:GetLayout(cat)
    if layout and layout.AddInitializer then
      local function button(name, text, tooltip, onClick)
        layout:AddInitializer(CreateSettingsButtonInitializer(name, text, ns.Guard.Wrap(function()
          leaveSettings()
          onClick()
        end), tooltip, true))
      end
      if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Sheets and tools"))
      end
      button("Stat weights", "Open the sheet", "Paste a Raidbots Pawn string for this spec. Your own weights beat the shipped defaults.",
        function() ns.WeightsUI.Show() end)
      button("The guide", "Open the guide", "Four pages: what Sift says, where it shows up, what to do first, and what to know.",
        function() ns.Guide.Show() end)
      button("Place the toast", "Open Edit Mode", "Opens the game's Edit Mode, where Sift's toast can be dragged into place.",
        function() Options.OpenEditMode() end)
      button("Send feedback", "Build a report", "Puts a report about this character and Sift's state in a box you can copy, with where to paste it.",
        function() ns.Feedback.Show() end)

      -- Every command, as a row whose button runs it. Developer commands
      -- appear when debug mode is on; the list re-checks as the box is ticked.
      if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Commands",
          "Every /sift command. The button runs it. In chat, add copy to any command to reopen its output in a box you can copy from."))
      end
      local muted = "|cff" .. ((ns.Style and ns.Style.GAIN_HEX and ns.Style.GAIN_HEX.flat) or "9a9ab5")
      local function command(label, cmd, gloss, buttonText, tooltip, opts)
        opts = opts or {}
        local name = "/sift" .. (label ~= "" and (" " .. label) or "") .. (gloss and ("  " .. muted .. gloss .. "|r") or "")
        local init = CreateSettingsButtonInitializer(name, buttonText, ns.Guard.Wrap(function()
          if opts.leave then leaveSettings() end
          if opts.run then opts.run() else SlashCmdList.SIFTLOOTADVISOR(cmd) end
        end), tooltip, true)
        if opts.dev and init.AddShownPredicate then
          init:AddShownPredicate(function() return prefs.debug and true or false end)
        end
        layout:AddInitializer(init)
      end
      command("", "", "the panel", "Open", "Everything waiting on you, grouped by what to do next. Opening it evaluates your bags quietly.",
        { leave = true, run = function() if not ns.Panel.IsShown() then ns.Panel.Toggle() end end })
      command("guide", "guide", "the tour", "Open", "How Sift works, in four pages.", { leave = true, run = function() ns.Guide.Show() end })
      command("scan", "scan", "bag report", "Run", "Evaluate everything in your bags and print each verdict in chat.")
      command("toast", "toast", "fill the toast", "Run", "Show your bag verdicts in the toast, to place or test it. Works even when the toast is off.", { leave = true })
      command("weights", "weights", "the sheet", "Open", "The stat weights sheet. In chat, /sift weights <Pawn string> imports from the command line.",
        { leave = true, run = function() ns.WeightsUI.Show() end })
      command("weights clear", "weights clear", nil, "Run", "Drop the imported weights for this character and go back to the defaults.")
      command("park", "park", nil, "Toggle", "Toggle send suggestions for this character. The same switch is the Park checkbox above.")
      command("vault", "vault", "rank the vault", "Run", "Rank what the Great Vault is offering. The vault window must be open.")
      command("vault preview", "vault preview", nil, "Run", "Try the vault picker on the example items for the slots you have earned this week.")
      command("status", "status", nil, "Run", "Print what Sift knows right now: character, alts, weights, currencies, holds.")
      command("journal", "journal", "the last run", "Run", "What happened around each drop in your last run: every pickup with its verdict, every roll, every line posted to the group. Add all in chat for every run on file.")
      command("feedback", "feedback", "build a report", "Open", "A report to paste to the author, in a box you can copy from.", { leave = true })
      command("copy", "copy", "last output", "Open", "Reopen the last command's output in a box you can copy from.", { leave = true })
      command("chat test", "chat test", nil, "Run", "Print what each toast row would post to the group, without posting. Writes each line to the journal.", { dev = true })
      command("probe", "probe", nil, "Run", "Check the game APIs Sift depends on and store the findings.", { dev = true })
      command("refresh", "refresh", nil, "Run", "Re-run every hold and cached verdict.", { dev = true })
      command("currency <track> <id>", "currency", nil, "Usage", "Pin a crest or catalyst currency id by hand. The button prints the usage; type the command in chat.", { dev = true })
      command("reset confirm", "reset", nil, "Run", "Wipe every snapshot, hold and preference. The button only says what it would do; type /sift reset confirm in chat to do it.", { dev = true })
    end
  end

  Settings.RegisterAddOnCategory(cat)
  category = cat
end

-- The same door the game menu uses, with the same gate.
function Options.OpenEditMode()
  if InCombatLockdown() then ns.Print("Edit Mode cannot open in combat.") return end
  local f = EditModeManagerFrame
  if not f or not ShowUIPanel then return end
  if f.CanEnterEditMode and not f:CanEnterEditMode() then ns.Print("Edit Mode cannot open right now.") return end
  ShowUIPanel(f)
end

function Options.Open()
  if not category then Options.Register() end
  if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end
