local _, ns = ...

-- One TomTom waypoint slot shared by the map pin and the tracker's focused row, so clicking
-- one after the other retargets instead of leaving two arrows that cannot clear each other.
local Arrow = ns:RegisterSubsystem("QuestArrow", {})

local _uid, _questID, _title
local FROM = "Everything Quests"

local function tomtom()
    local T = _G.TomTom
    return (T and T.AddWaypoint) and T or nil
end

function Arrow:Available()
    return tomtom() ~= nil
end

-- TomTom brings saved waypoints back at login, when EQ no longer holds their handle. Retail's Chain Guide adds its own under the same tag
local function removeLeftovers(T)
    local all = ns.HAS_CLASSIC_SPAWNS and type(T.waypoints) == "table" and T.waypoints
    if not all then return end
    local stale = {}
    for _, byKey in pairs(all) do
        if type(byKey) == "table" then
            for _, uid in pairs(byKey) do
                if type(uid) == "table" and uid.from == FROM then stale[#stale + 1] = uid end
            end
        end
    end
    for i = 1, #stale do pcall(T.RemoveWaypoint, T, stale[i]) end
end

function Arrow:Clear()
    local T = tomtom()
    if not (T and T.RemoveWaypoint) then return end
    -- First: after TomTom reloads its waypoints the held handle is stale, and removing it takes the live copy out of TomTom's list while it stays shown
    removeLeftovers(T)
    if _uid then
        pcall(T.RemoveWaypoint, T, _uid)
        _uid = nil
    end
end

function Arrow:Set(mapID, x, y, title, questID)
    local T = tomtom()
    if not (T and mapID and x and y) then return false end
    self:Clear()
    -- persistent, minimap and world are left unset so TomTom's own profile decides them.
    local ok, uid = pcall(T.AddWaypoint, T, mapID, x, y, {
        title = title,
        from  = FROM,
        crazy = true,
    })
    if ok then _uid, _questID, _title = uid, questID, title end
    return ok and true or false
end

function Arrow:Holds(questID)
    return questID ~= nil and _uid ~= nil and _questID == questID
end

-- The game's point moves as objectives finish, and TomTom drops a waypoint on arrival, so a held arrow is set again
function Arrow:Refresh(questID)
    if not self:Holds(questID) then return false end
    local m, x, y = self:GamePoint(questID)
    if m then self:Set(m, x, y, _title, questID) end
    return true
end

local function playerMap()
    local f = C_Map and C_Map.GetBestMapForUnit
    if not f then return nil end
    local ok, id = pcall(f, "player")
    return ok and id or nil
end

local function mapRow(mapID, questID)
    local list = mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if e.questID == questID and e.x and e.y and (e.x ~= 0 or e.y ~= 0) then return e.x, e.y end
    end
end

-- The quest's own zone is kept off retail, whose guide reads what it always did. Forever gave Tirisfal's row from Orgrimmar (2026-11-05)
function Arrow:GamePoint(questID)
    if not questID then return nil end
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local m, x, y = C_QuestLog.GetNextWaypoint(questID)
        if m and x and y and (x ~= 0 or y ~= 0) then return m, x, y end
    end
    local here = playerMap()
    local x, y = mapRow(here, questID)
    if x then return here, x, y end
    local own = ns.HAS_CLASSIC_SPAWNS and _G.GetQuestUiMapID and _G.GetQuestUiMapID(questID)
    if own and own ~= 0 and own ~= here then
        x, y = mapRow(own, questID)
        if x then return own, x, y end
    end
    return nil
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
function Arrow:PointFor(questID)
    if not questID then return nil end

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(questID)

    local mapID, x, y
    if q and ns.QuestIsDone and ns.QuestIsDone(q) then
        mapID, x, y = turnInPoint(questID)
        if not mapID and ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID] then
            return nil
        end
    end
    if not mapID then mapID, x, y = objectivePoint(questID) end
    if not mapID then return nil end
    return mapID, x, y, q and q.title
end

function Arrow:PointAtQuest(questID)
    local mapID, x, y, title = self:PointFor(questID)
    if not mapID then return false end
    return self:Set(mapID, x, y, title)
end

-- Forever only: following a quest on retail never set a TomTom arrow, and Era and TBC have no super-track to follow
function Arrow:PointAtGame(questID)
    if not (ns.HAS_CLASSIC_SPAWNS and C_SuperTrack and tomtom()) then return false end
    local mapID, x, y = self:GamePoint(questID)
    if not mapID then return false end
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(questID)
    local title = (q and q.title) or (ns.Util and ns.Util.QuestTitle(questID, true))
    return self:Set(mapID, x, y, title, questID)
end
