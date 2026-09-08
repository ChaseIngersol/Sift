-- /sift feedback: a report on this character and Sift's state, opened in
-- the copy box with where to paste it. An addon cannot open a browser or
-- send anything, so the report travels by clipboard.
local ADDON, ns = ...

local Feedback = {}
ns.Feedback = Feedback

-- Where reports go. One place to change when the form moves.
Feedback.URL = "https://github.com/ChaseIngersol/Sift/issues"

local function version()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    v = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  elseif GetAddOnMetadata then
    v = GetAddOnMetadata(ADDON, "Version")
  end
  if not v or v == "" or v:find("@project", 1, true) then v = "dev" end
  return v
end

local function when()
  if type(date) == "function" then return date("%Y-%m-%d %H:%M") end
  return tostring(time())
end

local function prefsLine()
  local p = ns.DB.Prefs()
  local function on(v) return v and "on" or "off" end
  local minTrack = (p.catalystMinTrack and p.catalystMinTrack ~= "") and p.catalystMinTrack or "any track"
  return string.format("settings: chat %s, toast %s, sound %s, vault %s, rolls %s, bank reminder %s, alts first %s, threshold %.1f%%, quality %d and up, catalyst from %s, debug %s",
    on(p.chat), on(p.toast), on(p.sound), on(p.vault ~= false), on(p.lootRoll ~= false), on(p.bankReminder ~= false), on(p.altFirst),
    (p.threshold or 0.01) * 100, p.minQuality or 3, minTrack, on(p.debug))
end

-- The report as lines: versions, the status lines, the settings, the
-- last entries of the log.
function Feedback.Report()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local gameVersion, build = GetBuildInfo()
  add(string.format("Sift %s, game %s (%s), %s", version(), tostring(gameVersion), tostring(build), when()))
  for _, l in ipairs(ns.Status.Lines()) do add(l) end
  add(prefsLine())
  local log = ns.db.log or {}
  if #log > 0 then
    add("recent log:")
    for i = math.max(1, #log - 9), #log do
      local e = log[i]
      add(string.format("  [%s] %s", tostring(e.level), tostring(e.msg)))
    end
  end
  return lines
end

function Feedback.Show()
  local head = "Sift feedback. Paste all of this at " .. Feedback.URL
    .. "\nand add what happened and what you expected instead.\n\n"
  ns.CopyBox.Show(head .. table.concat(Feedback.Report(), "\n"), "Feedback")
  ns.Print("Report ready in the copy box. Paste it at " .. Feedback.URL)
end
