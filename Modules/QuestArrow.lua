local _, ns = ...

-- One TomTom waypoint slot shared by the map pin and the tracker's focused row, so clicking
-- one after the other retargets instead of leaving two arrows that cannot clear each other.
local Arrow = ns:RegisterSubsystem("QuestArrow", {})

local _uid

local function tomtom()
    local T = _G.TomTom
    return (T and T.AddWaypoint) and T or nil
end

function Arrow:Available()
    return tomtom() ~= nil
end

function Arrow:Clear()
    local T = tomtom()
    -- Drop the handle only when the waypoint is really gone, or that arrow is stranded with
    -- nothing left to remove it by.
    if T and _uid and T.RemoveWaypoint then
        pcall(T.RemoveWaypoint, T, _uid)
        _uid = nil
    end
end

function Arrow:Set(mapID, x, y, title)
    local T = tomtom()
    if not (T and mapID and x and y) then return false end
    self:Clear()
    -- persistent, minimap and world are left unset so TomTom's own profile decides them.
    local ok, uid = pcall(T.AddWaypoint, T, mapID, x, y, {
        title = title,
        from  = "Everything Quests",
        crazy = true,
    })
    if ok then _uid = uid end
    return ok and true or false
end

local function playerMap()
    local f = C_Map and C_Map.GetBestMapForUnit
    if not f then return nil end
    local ok, id = pcall(f, "player")
    return ok and id or nil
end

-- srcID*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4), with the map as the outer key. Only
-- the coordinate half is wanted here, so v % 1e8 skips the rest. Deliberately NOT the same
-- packing as ns.CLASSIC_QUEST_COORDS below, which carries the MAP where this carries a kind,
-- so the two decoders cannot be shared.
local function turnInPoint(questID)
    local byMap = ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
    if not byMap then return nil end

    local pick = playerMap()
    if not (pick and byMap[pick]) then
        -- Lowest map id rather than pairs order, so a quest that hands in on several maps
        -- sends the arrow to the same place every time it is clicked.
        pick = nil
        for mapID in pairs(byMap) do
            if not pick or mapID < pick then pick = mapID end
        end
    end
    if not pick then return nil end

    local v = byMap[pick][1]
    if not v then return nil end
    local rest = v % 1e8
    return pick, math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
end

-- m*1e8 + floor(x*1e4)*1e4 + floor(y*1e4). The map rides inside the number, so a quest id is
-- the only input needed. Both tables are listed by the flavor TOCs only, so this answers nil
-- on retail and the caller falls through to nothing.
local function objectivePoint(questID)
    local packed = ns.CLASSIC_QUEST_COORDS and ns.CLASSIC_QUEST_COORDS[questID]
    if not packed then return nil end
    local rest = packed % 1e8
    return math.floor(packed / 1e8), math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
end

-- A finished quest wants the finisher, not the field it was farmed in. Once the turn-in table
-- knows a quest it is authoritative, so there is no fall through to the objective table for
-- one that does - 475 quests hand in on a different map from their objective and every one of
-- them would point at the wrong zone.
function Arrow:PointAtQuest(questID)
    if not questID then return false end

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(questID)

    local mapID, x, y
    if q and ns.QuestIsDone and ns.QuestIsDone(q) then
        mapID, x, y = turnInPoint(questID)
        if not mapID and ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID] then
            return false
        end
    end
    if not mapID then mapID, x, y = objectivePoint(questID) end
    if not mapID then return false end

    return self:Set(mapID, x, y, q and q.title)
end
