-- Upgrade track math. Anchors on the observed item level so only the step
-- pattern between ranks in Season.tracks has to be right.
local _, ns = ...

local Tracks = {}
ns.Tracks = Tracks

-- Item level of this item at another rank on its track. Returns nil if the
-- item has no track or the track is unknown.
function Tracks.IlvlAt(season, item, rank)
  local steps = item.track and season.tracks[item.track]
  if not steps or not item.rank or not item.ilvl then return nil end
  local base, target = steps[item.rank], steps[rank]
  if not base or not target then return nil end
  return item.ilvl + (target - base)
end

-- Highest item level this item can reach on its track. Falls back to the
-- current level when there is no track information.
function Tracks.Ceiling(season, item)
  if not item then return 0 end
  if not item.track or not item.rank or not item.maxRank then return item.ilvl or 0 end
  return Tracks.IlvlAt(season, item, item.maxRank) or item.ilvl or 0
end

function Tracks.RanksRemaining(item)
  if not item or not item.rank or not item.maxRank then return 0 end
  return math.max(0, item.maxRank - item.rank)
end

function Tracks.CrestCost(season, ranks)
  return (season.crestPerRank or 0) * ranks
end

-- Slot family for upgrade watermarks: the game waives crests up to the
-- highest item level already reached in a slot, and paired slots share it.
local GROUP = {
  INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
  INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
  INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
  INVTYPE_TRINKET = "trinket", INVTYPE_WEAPON = "weapon", INVTYPE_2HWEAPON = "weapon",
  INVTYPE_WEAPONMAINHAND = "weapon", INVTYPE_RANGED = "weapon", INVTYPE_RANGEDRIGHT = "weapon",
  INVTYPE_WEAPONOFFHAND = "offhand", INVTYPE_SHIELD = "offhand", INVTYPE_HOLDABLE = "offhand",
}
function Tracks.WatermarkGroup(equipLoc)
  return GROUP[equipLoc]
end

-- Crests for the next `ranks` ranks of an item, minus ranks whose target
-- level is at or under the slot watermark (those are free). Returns
-- crests, freeRanks.
function Tracks.UpgradeCost(season, item, ranks, watermark)
  local per = season.crestPerRank or 0
  if not watermark or not item.track or not item.rank then return per * ranks, 0 end
  local crests, free = 0, 0
  for k = 1, ranks do
    local il = Tracks.IlvlAt(season, item, item.rank + k)
    if il and il <= watermark then free = free + 1 else crests = crests + per end
  end
  return crests, free
end
