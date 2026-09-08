-- Roll advice: what a verdict means at a Need, Greed, Pass window. Pure;
-- the adapter reads the roll, the UI draws the words.
local _, ns = ...

local Roll = {}
ns.Roll = Roll

-- Returns { word, kind }, kind picking the verdict color, or nil when
-- there is nothing to say.
--   Need: Sift would equip it now (green) or hold it for later, for
--         upgrades, the catalyst, the set or a level (amber).
--   Need, offspec: only the other spec wants it.
--   Sim it: too close to call.
--   Greed: not for this character's slot but not worthless: an alt wants
--          it, or the better move is upgrading the worn piece and keeping
--          this one as a stand-in.
--   Pass: a dead end.
function Roll.Advice(v)
  if not v then return nil end
  local K = ns.Engine.KIND
  if v.kind == K.EQUIP then return { word = "Need", kind = "EQUIP" } end
  if v.kind == K.HOLD then
    if v.sub == "sim" then return { word = (v.flags and v.flags.noSim) and "Your call" or "Sim it", kind = "HOLD" } end
    if v.sub == "offspec" then return { word = "Need, offspec", kind = "HOLD" } end
    if v.sub == "instead" then return { word = "Greed", kind = "HOLD" } end
    return { word = "Need", kind = "HOLD" }
  end
  if v.kind == K.SEND then return { word = "Greed", kind = "SEND" } end
  return { word = "Pass", kind = "DISPOSE" }
end

-- The reason without the verdict word the roll word already says, and
-- without the vendor line: the item is not in the bags yet. A send keeps
-- its first sentence, which names the alt.
function Roll.Line(v)
  if not v then return "" end
  local text = v.kind == ns.Engine.KIND.SEND and (v.reason or "") or ns.VaultRank.Short(v)
  text = text:gsub("%s*Vendor or disenchant%.$", "")
  return text
end
