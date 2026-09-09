-- SavedVariables lifecycle, defaults and migrations.
local ADDON, ns = ...

local DB = {}
ns.DB = DB

DB.VERSION = 1

local DEFAULTS = {
  version = DB.VERSION,
  prefs = {
    threshold = 0.01,   -- minimum relative gain to call something better
    altFirst = false,   -- put SEND ahead of a self verdict
    chat = true,        -- chat line per new verdict at a safe moment
    toast = true,       -- on-screen toast at safe moments
    sound = false,      -- chime with the toast
    minQuality = 3,     -- evaluate rare and better
    minimap = true,     -- minimap button
    minimapAngle = 200,
    vault = true,       -- rank the Great Vault's items while the vault is open
    lootRoll = true,    -- roll advice beside Need, Greed, Pass windows
    bankReminder = true, -- toast rows at the bank: deposits for alts, pickups for me
    groupChat = true,   -- Tell party / Say why buttons in a group (see Adapters/GroupChat.lua)
    catalystMinTrack = "Champion", -- lowest upgrade track worth a catalyst charge ("" for any)
    guideSeen = false,  -- the guide opened once on first login
    toastRows = 3,      -- rows per toast page
    toastSeconds = 5,   -- seconds a toast row stays
    toastGrow = "down", -- which way the stack grows from its pinned edge
    debug = false,
  },
  chars = {},      -- key -> snapshot (see Adapters/Character.lua)
  watermarks = {}, -- key -> slot group -> highest item level seen there
  holds = {},      -- guid -> { owner, link, name, icon, kind, sub, reason, wake, ready, ts }
  season = { currency = {}, manual = {}, candidates = {}, trackStrings = {} },
  log = {},
  journal = { run = 0, entries = {} }, -- the loot journal (see Adapters/Journal.lua)
  probe = {},
  output = {},     -- last slash command's output, readable after a reload
}

local CHAR_DEFAULTS = {
  parked = false,
  extraSpecs = {},   -- list of spec ids evaluated in addition to the active spec
  imported = {},     -- specID -> { name, weights, ts, gear }
  lastStaleNudge = 0,
}

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      fill(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

local migrations = {
  -- [2] = function(db) ... end,
}

function DB.Init()
  SiftLootAdvisorDB = type(SiftLootAdvisorDB) == "table" and SiftLootAdvisorDB or {}
  SiftLootAdvisorCharDB = type(SiftLootAdvisorCharDB) == "table" and SiftLootAdvisorCharDB or {}
  fill(SiftLootAdvisorDB, DEFAULTS)
  fill(SiftLootAdvisorCharDB, CHAR_DEFAULTS)
  local from = SiftLootAdvisorDB.version or 1
  for v = from + 1, DB.VERSION do
    if migrations[v] then migrations[v](SiftLootAdvisorDB) end
  end
  SiftLootAdvisorDB.version = DB.VERSION
  ns.db = SiftLootAdvisorDB
  ns.cdb = SiftLootAdvisorCharDB
end

function DB.Prefs()
  return (ns.db and ns.db.prefs) or DEFAULTS.prefs
end

-- The shipped default for a preference, so the settings page can offer a
-- real reset. char = true reads the per-character table.
function DB.Default(key, char)
  return (char and CHAR_DEFAULTS or DEFAULTS.prefs)[key]
end

function DB.ResetAll()
  SiftLootAdvisorDB = nil
  SiftLootAdvisorCharDB = nil
  DB.Init()
end
