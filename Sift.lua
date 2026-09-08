-- Entry point: slash commands, addon compartment, public API.
local ADDON, ns = ...

SiftLootAdvisor = SiftLootAdvisor or {}
local Guard = ns.Guard

-- The developer commands stay out of the list unless debug mode is on;
-- they still run.
local function usage()
  ns.Print("commands:")
  ns.Print("  /sift            open the panel")
  ns.Print("  /sift guide      how Sift works, in four pages")
  ns.Print("  /sift scan       evaluate everything in your bags")
  ns.Print("  /sift toast      show your bag verdicts in the toast, to place or test it")
  ns.Print("  /sift weights    open the stat weights sheet (paste a Raidbots string there)")
  ns.Print("  /sift weights <Pawn string>   import sim weights from the command line")
  ns.Print("  /sift weights clear           drop imported weights for this character")
  ns.Print("  /sift park       toggle send suggestions for this character")
  ns.Print("  /sift options    open settings")
  ns.Print("  /sift vault      rank what the Great Vault is offering (open the vault first)")
  ns.Print("  /sift vault preview   try the picker on example items for the slots you have earned")
  ns.Print("  /sift status     show what Sift knows right now")
  ns.Print("  /sift feedback   build a report you can paste to the author")
  ns.Print("  /sift copy       reopen the last command's output in a box you can copy from")
  ns.Print("  Add copy to any command (/sift status copy) to open that box right away.")
  ns.Print("  /siftloot is the same command, for when another addon has claimed /sift.")
  if ns.DB.Prefs().debug then
    ns.Print("  /sift probe      run the API verification probe (watch, stop, bank)")
    ns.Print("  /sift refresh    re-run every hold and cached verdict")
    ns.Print("  /sift currency <track|catalyst> <id>   set a currency id by hand")
    ns.Print("  /sift reset confirm   wipe every snapshot, hold and preference")
  end
end

local function status()
  for _, line in ipairs(ns.Status.Lines()) do
    ns.Print(line)
  end
end

local handlers = {
  scan = function()
    local n = ns.Triggers.ScanAll()
    ns.Print(string.format("scanned %d candidate items", n))
    ns.Panel.Refresh()
  end,
  toast = function()
    local n = ns.Triggers.ShowToast()
    local off = not ns.DB.Prefs().toast
    ns.Print(
      string.format(
        "toast filled with %d bag verdict%s%s",
        n,
        n == 1 and "" or "s",
        off and " (the toast is off in settings; shown anyway)" or ""
      )
    )
    ns.Panel.Refresh()
  end,
  weights = function(rest)
    if rest == "clear" then
      ns.Character.ClearWeights()
      ns.Verdicts.InvalidateAll()
      ns.Print("imported weights cleared for this character")
      return
    end
    if not rest or rest == "" then
      ns.WeightsUI.Toggle()
      return
    end
    local ok, msg = ns.Character.ImportWeights(rest)
    ns.Verdicts.InvalidateAll()
    ns.Print(msg)
    ns.Panel.Refresh()
  end,
  park = function()
    local me = ns.Character.Self()
    ns.Character.SetParked(not me.parked)
    ns.Print(ns.cdb.parked and "parked: this character will not receive send suggestions" or "unparked")
  end,
  options = function()
    ns.Options.Open()
  end,
  guide = function()
    ns.Guide.Toggle()
  end,
  feedback = function()
    ns.Feedback.Show()
  end,
  probe = function(rest)
    if rest == "watch" then
      ns.Probe.Watch(true)
      return
    end
    if rest == "stop" then
      ns.Probe.Watch(false)
      return
    end
    if rest == "bank" then
      ns.Bank.Probe()
      return
    end
    ns.Probe.Run()
  end,
  currency = function(rest)
    local key, id = (rest or ""):match("^(%S+)%s+(%d+)$")
    if not key then
      ns.Print("usage: /sift currency <Adventurer|Veteran|Champion|Hero|Myth|catalyst> <id>")
      return
    end
    ns.Resources.SetManual(key, id)
    ns.Verdicts.InvalidateAll()
    ns.Print("set " .. key .. " to currency " .. id)
  end,
  status = status,
  vault = function(rest)
    local lines = (rest == "preview") and ns.Vault.Preview() or ns.Vault.Describe()
    for _, line in ipairs(lines) do
      ns.Print(line)
    end
  end,
  refresh = function()
    ns.Triggers.Refresh()
    ns.Print("refreshed")
  end,
  help = usage,
  reset = function(rest)
    if rest ~= "confirm" then
      ns.Print("this wipes every snapshot, hold and preference. Type /sift reset confirm to do it.")
      return
    end
    ns.DB.ResetAll()
    ns.Character.Invalidate()
    ns.Character.InvalidateAlts()
    ns.Verdicts.InvalidateAll()
    ns.Print("reset")
  end,
}

-- The command table, for the smoke test's check against docs/COMMANDS.md.
ns.Commands = handlers

-- Every command's output is captured into SiftLootAdvisorDB.output (readable from the
-- SavedVariables file after a reload) and can be reopened in a copy box.
local function showLastOutput()
  local out = ns.db.output
  if not out or not out.lines or #out.lines == 0 then
    ns.Print("nothing to copy yet; run a command first")
    return
  end
  ns.CopyBox.Show(table.concat(out.lines, "\n"), "/sift " .. (out.cmd or ""))
end

local function run(cmd, rest)
  local h = handlers[cmd]
  if not h then
    usage()
    return
  end
  local wantCopy = false
  if rest == "copy" then
    wantCopy, rest = true, ""
  elseif rest:match("%s+copy$") then
    wantCopy, rest = true, rest:gsub("%s+copy$", "")
  end
  ns.capture = {}
  local ok, err = pcall(h, rest)
  local lines = ns.capture
  ns.capture = nil
  local version, build = GetBuildInfo()
  ns.db.output = {
    cmd = cmd .. (rest ~= "" and (" " .. rest) or ""),
    ts = time(),
    build = build,
    char = ns.Character.Key(),
    lines = lines,
  }
  if not ok then
    error(err, 0)
  end
  if wantCopy then
    showLastOutput()
  end
end

SLASH_SIFTLOOTADVISOR1 = "/sift"
SLASH_SIFTLOOTADVISOR2 = "/siftloot"
SlashCmdList.SIFTLOOTADVISOR = Guard.Wrap(function(msg)
  msg = (msg or ""):gsub("^%s+", "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  if not cmd or cmd == "" then
    ns.Panel.Toggle()
    return
  end
  cmd = cmd:lower()
  if cmd == "copy" then
    showLastOutput()
    return
  end
  run(cmd, rest)
end)

function SiftLootAdvisor_OnCompartmentClick()
  Guard.Call(ns.Panel.Toggle)
end

-- Public API for other addons: a verdict for an item link, or nil.
function SiftLootAdvisor.Evaluate(link)
  local ok, entry = Guard.Call(ns.Verdicts.ForLink, link, false)
  return ok and entry and entry.verdict or nil
end
