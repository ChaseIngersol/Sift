-- Every entry point from the game runs through Guard so an error can never
-- escape Sift. Each distinct error is logged once per session.
local ADDON, ns = ...

local Guard = {}
ns.Guard = Guard

local PREFIX = "|cff7fd7ffSift|r"
local seen = {}
local MAX_LOG = 50

-- Everything Sift says goes through here. While a slash command runs the
-- lines are also collected (ns.capture) so they can be copied out.
function ns.Print(msg)
  local text = tostring(msg)
  if ns.capture then ns.capture[#ns.capture + 1] = text end
  print(PREFIX .. ": " .. text)
end

-- Lines Sift volunteers on its own (reminders at a vendor, an upgrade NPC
-- or a bank, the stale-weights nudge) follow the chat setting. Answers to
-- a command and errors go through ns.Print regardless.
function ns.Chat(msg)
  local db = rawget(_G, "SiftLootAdvisorDB")
  if db and db.prefs and db.prefs.chat == false then return end
  ns.Print(msg)
end

function ns.Log(level, msg)
  local db = rawget(_G, "SiftLootAdvisorDB")
  if db then
    db.log = db.log or {}
    local log = db.log
    log[#log + 1] = { t = time(), level = level, msg = tostring(msg) }
    while #log > MAX_LOG do table.remove(log, 1) end
  end
  if level == "error" or (db and db.prefs and db.prefs.debug) then
    ns.Print(string.format("[%s] %s", level, tostring(msg)))
  end
end

local function report(err)
  local msg = tostring(err)
  if not seen[msg] then
    seen[msg] = true
    ns.Log("error", msg)
  end
end

-- Call fn(...) and swallow errors. Returns ok, results...
function Guard.Call(fn, ...)
  local db = rawget(_G, "SiftLootAdvisorDB")
  if db and db.prefs and db.prefs.debug then
    -- In debug mode let errors surface so BugSack captures a full trace.
    return true, fn(...)
  end
  local results = { pcall(fn, ...) }
  if not results[1] then
    report(results[2])
    return false
  end
  return unpack(results)
end

-- Wrap fn so it can be handed to SetScript, hooks and timers.
function Guard.Wrap(fn)
  return function(...)
    return select(2, Guard.Call(fn, ...))
  end
end
