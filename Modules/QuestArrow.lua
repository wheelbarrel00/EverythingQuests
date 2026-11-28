local _, ns = ...

-- One TomTom slot for every EQ arrow, so a new one replaces the last instead of leaving two
local Arrow = ns:RegisterSubsystem("QuestArrow", {})

-- _questID is the quest the slot follows, kept with no waypoint showing until a spot is known
local _uid, _questID, _title, _followed
local _m, _x, _y
local _sig, _progress, _rows, _settling
local FROM = "Everything Quests"

local function tomtom()
    local T = _G.TomTom
    return (T and T.AddWaypoint) and T or nil
end

-- Retail ships none of the Classic quest tables, so there PointFor and Retarget read the game's own answers
local function retail()
    return not (ns.CLASSIC_QUEST_COORDS or ns.CLASSIC_QUEST_TURNIN)
end

function Arrow:Available()
    return tomtom() ~= nil
end

-- Another addon can answer TomTom's calls while TomTom itself is not loaded
function Arrow:StandIn()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return (tomtom() and loaded and not loaded("TomTom")) and true or false
end

-- TomTom brings saved waypoints back at login, when EQ no longer holds their handle
local function removeLeftovers(T)
    local all = type(T.waypoints) == "table" and T.waypoints
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

local function takeDown(T)
    if not (T and T.RemoveWaypoint) then return end
    -- First: after TomTom reloads its waypoints the held handle is stale, and removing it takes the live copy out of TomTom's list while it stays shown
    removeLeftovers(T)
    if _uid then
        pcall(T.RemoveWaypoint, T, _uid)
        _uid = nil
    end
end

-- Takes the waypoint down and stops following its quest
function Arrow:Clear()
    _questID, _followed = nil, false
    takeDown(tomtom())
end

-- TomTom takes a waypoint down on arrival without telling EQ, so the held handle is looked for in its list. A list EQ cannot read counts as showing
local function showing(T)
    if not _uid then return false end
    local all = T and type(T.waypoints) == "table" and T.waypoints
    if not all then return true end
    local byKey = all[_m]
    if type(byKey) ~= "table" then return false end
    for _, uid in pairs(byKey) do
        if uid == _uid then return true end
    end
    return false
end

-- Which objectives are done and whether the quest is, so a count going up moves nothing. Progress and rows tell a step back
local function stateOf(q)
    local objs = q.objectives
    local n = objs and #objs or 0
    local s, finished = n, 0
    for i = 1, n do
        local f = objs[i].finished and 1 or 0
        s, finished = s * 2 + f, finished + f
    end
    local ready = (ns.QuestIsDone and ns.QuestIsDone(q)) and 1 or 0
    return s * 2 + ready, finished + ready * 100, n
end

local function cached(questID)
    local Cache = ns:GetSubsystem("Cache")
    return Cache and Cache:Get(questID)
end

local function remember(questID)
    local q = questID and cached(questID)
    _sig, _progress, _rows = nil, nil, nil
    if q then _sig, _progress, _rows = stateOf(q) end
end

-- followed marks an arrow the focus listener placed, the only kind unticking the focus arrow box takes down
function Arrow:Set(mapID, x, y, title, questID, followed)
    local T = tomtom()
    if not (T and mapID and x and y) then return false end
    takeDown(T)
    -- persistent, minimap and world are left unset so TomTom's own profile decides them
    local ok, uid = pcall(T.AddWaypoint, T, mapID, x, y, {
        title = title,
        from  = FROM,
        crazy = true,
    })
    -- TomTom raises when it cannot take a waypoint, and Shortest Path Forever standing in for it answers nil
    if not (ok and uid) then
        _m, _x, _y = nil, nil, nil
        -- An arrow asked for elsewhere ends the old follow, whose waypoint is already down
        if questID and questID == _questID then remember(questID) else _questID, _followed = nil, false end
        return false
    end
    _uid, _questID, _title, _followed = uid, questID, title, followed == true
    _m, _x, _y = mapID, x, y
    remember(questID)
    return true
end

-- Nothing to point at yet, so the waypoint goes and the slot keeps the quest, for its arrow to come once a spot is known
function Arrow:Follow(questID, followed)
    local T = tomtom()
    if not T then return end
    takeDown(T)
    local q = cached(questID)
    _questID, _followed, _title = questID, followed == true, q and q.title
    _m, _x, _y = nil, nil, nil
    remember(questID)
end

function Arrow:Holds(questID)
    return questID ~= nil and _uid ~= nil and _questID == questID
end

-- Whether the slot is for this quest, its waypoint showing or still waiting for a spot
function Arrow:Follows(questID)
    return questID ~= nil and _questID == questID
end

function Arrow:Followed()
    return _uid ~= nil and _followed == true
end

-- A quest the focus follows with no waypoint showing goes too
function Arrow:ClearFollowed()
    if _followed then self:Clear() end
end

-- With no arrow held, every EQ waypoint TomTom shows came back from an earlier session
function Arrow:ClearLeftovers()
    if not _uid then takeDown(tomtom()) end
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

-- The quest's own zone is kept off retail, and was measured on WoW Forever: Tirisfal's row from Orgrimmar (2026-11-05)
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

-- Retail has no Classic tables, so the game answers: its next waypoint, the quest's row on your map, else a world quest's own spot
local function retailPoint(self, questID)
    local m, x, y = self:GamePoint(questID)
    if m then return m, x, y end
    local T = C_TaskQuest
    local zone = T and T.GetQuestZoneID and T.GetQuestZoneID(questID)
    if zone and zone ~= 0 and T.GetQuestLocation then
        x, y = T.GetQuestLocation(questID, zone)
        if x and y and (x ~= 0 or y ~= 0) then return zone, x, y end
    end
    return nil
end

local function core()
    return LibStub and LibStub("HereBeDragons-2.0", true)
end

-- MapsFor, and PointsFor with all set, read only isComplete and objectives, so isComplete can carry QuestIsDone's answer, which the cached flag can lag behind
local _view, _maps, _mapInst = {}, {}, {}

local function mapInstance(HBD, map)
    local inst = _mapInst[map]
    if inst == nil then
        local _, _, found = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, map)
        inst = found
        if inst then _mapInst[map] = inst end
    end
    return inst
end

local function near(a, b) return math.abs(a - b) < 1e-4 end

-- Yards from a spot TomTom took down within which the player still counts as standing at it, or TomTom's own clear distance if wider
local AT_SPOT = 40

local function playerAt(m, x, y)
    local HBD = core()
    if not HBD then return false end
    local px, py, pinst = HBD:GetPlayerWorldPosition()
    local sx, sy, sinst = HBD:GetWorldCoordinatesFromZone(x, y, m)
    if not (px and py and sx and sy) or pinst ~= sinst then return false end
    local T = tomtom()
    local saved = T and type(T.profile) == "table" and type(T.profile.persistence) == "table" and T.profile.persistence
    local reach = math.max(AT_SPOT, saved and tonumber(saved.cleardistance) or 0)
    local dx, dy = sx - px, sy - py
    return dx * dx + dy * dy <= reach * reach
end

-- km, kx, ky while still one of them, else the nearest on your continent, else your map's first point, else the busiest map's with the lower id on a tie
local function locate(questID, q, km, kx, ky)
    local Provider = ns:GetSubsystem("MapPOIProvider")
    if not (Provider and Provider.PointsFor and Provider.MapsFor) then return nil end
    _view.isComplete = (q and ns.QuestIsDone and ns.QuestIsDone(q)) and true or false
    _view.objectives = q and q.objectives
    local HBD = core()
    local px, py, pinst
    if HBD then px, py, pinst = HBD:GetPlayerWorldPosition() end
    local here = playerMap()
    Provider:MapsFor(questID, _view, nil, _maps)
    table.sort(_maps)
    local best, bm, bx, by, fm, fx, fy, fn
    local kept = false
    for i = 1, #_maps do
        local map = _maps[i]
        local n, _, source = Provider:PointsFor(questID, map, _view, true)
        -- A single point can be the hand-in standing in for an objective, so place weighs it apart
        if (source == "turnin" or source == "spawn") and n > 0 then
            local X, Y = Provider._ptX, Provider._ptY
            if not fm or (fm ~= here and (map == here or n > fn)) then fm, fx, fy, fn = map, X[1], Y[1], n end
            if map == km then
                for k = 1, n do
                    if near(X[k], kx) and near(Y[k], ky) then kept = true end
                end
            end
            if px and py and mapInstance(HBD, map) == pinst then
                for k = 1, n do
                    local wx, wy = HBD:GetWorldCoordinatesFromZone(X[k], Y[k], map)
                    if wx and wy then
                        local dx, dy = wx - px, wy - py
                        local d = dx * dx + dy * dy
                        if not best or d < best then best, bm, bx, by = d, map, X[k], Y[k] end
                    end
                end
            end
        end
    end
    _view.objectives = nil
    if kept then return km, kx, ky end
    if bm then return bm, bx, by end
    return fm, fx, fy
end

-- On the shipped Era, TBC and Forever data a quest's single point marks one of its objectives exactly when its map holds a spawn of the quest that is not a dungeon entrance
local function marksObjective(questID, mapID)
    local spawns = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    local list = spawns and spawns[questID] and spawns[questID][mapID]
    for i = 1, list and #list or 0 do
        if not ns.QuestIsEntrance(math.floor(list[i] % 1e9 / 1e8)) then return true end
    end
    return false
end

-- The objective types the data places. One still open with no point known gets no point here rather than the hand-in
local PLACED = { monster = true, object = true, item = true }
local function needsSpot(q)
    local objs = q and q.objectives
    for i = 1, objs and #objs or 0 do
        if not objs[i].finished and PLACED[objs[i].type] then return true end
    end
    return false
end

local function place(self, questID, q, km, kx, ky)
    local m, x, y = locate(questID, q, km, kx, ky)
    if m then return m, x, y end
    -- On Forever the game's own marker stands in where EQ has no spot, ahead of the stored point, which here can only be the hand-in
    if ns.HAS_CLASSIC_SPAWNS and C_SuperTrack then
        m, x, y = self:GamePoint(questID)
        if m then return m, x, y end
    end
    -- A done quest with no hand-in known, or an open objective with no point known, gets no point rather than a wrong one
    if (q and ns.QuestIsDone and ns.QuestIsDone(q)) or needsSpot(q) then return nil end
    -- Where the data's explore places were filled from a second source, an open exploration, escort or scripted quest with none gets no point rather than the hand-in
    local Avail = ns.CLASSIC_EXPLORE_PLACES_FILLED and q and ns:GetSubsystem("AvailableQuests")
    if Avail and Avail.IsExplorationOrScripted and Avail:IsExplorationOrScripted(questID) then return nil end
    local packed = ns.CLASSIC_QUEST_COORDS and ns.CLASSIC_QUEST_COORDS[questID]
    if not packed then return nil end
    m = math.floor(packed / 1e8)
    if marksObjective(questID, m) then return nil end
    local rest = packed % 1e8
    return m, math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
end

-- Chain Guide pins and the Quest Browser ask on every redraw, so an answer stands for a second while the quest's state and your map hold
local _memo = {}

-- On retail the game's own answer. Elsewhere the nearest open objective or hand-in, else Forever's own marker, else the stored point when nothing left can be placed
function Arrow:PointFor(questID)
    if not questID then return nil end
    if retail() then return retailPoint(self, questID) end
    local q = cached(questID)
    local sig = q and stateOf(q)
    local here, now = playerMap(), GetTime and GetTime()
    local hit = _memo[questID]
    if not (hit and now and now < hit.t + 1 and hit.sig == sig and hit.here == here) then
        local m, x, y = place(self, questID, q)
        hit = { t = now or 0, sig = sig, here = here, m = m, x = x, y = y }
        if now then _memo[questID] = hit end
    end
    if not hit.m then return nil end
    return hit.m, hit.x, hit.y, q and q.title
end

-- Without TomTom nothing is read, as PointFor asks the game's map rows for an arrow that could not be drawn
function Arrow:PointAtQuest(questID)
    if not tomtom() then return false end
    local mapID, x, y, title = self:PointFor(questID)
    if not mapID then return false end
    return self:Set(mapID, x, y, title or (ns.Util and ns.Util.QuestTitle(questID, true)), questID, true)
end

-- Retail's route moves without an objective finishing, so the game's answer is compared with the spot last set, and a spot TomTom took down stays down until the answer moves
local function retargetRetail(self, questID)
    local m, x, y = retailPoint(self, questID)
    -- No answer for a moment, around a loading screen, leaves the arrow where it is
    if not m then return end
    if _x and m == _m and near(x, _x) and near(y, _y) then return end
    self:Set(m, x, y, _title or (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(questID, true)), questID, _followed)
end

-- A followed quest is read again when an objective or the quest changes state, keeping a spot that still serves it
function Arrow:Retarget()
    local questID = _questID
    if not questID then return end
    if retail() then return retargetRetail(self, questID) end
    -- A quest missing from the log does not end a follow, as the log can miss one for a moment around a loading screen
    local q = cached(questID)
    if not q then return end
    local sig, progress, rows = stateOf(q)
    if sig == _sig then return end
    -- For a while after a loading screen the log can read objectives undone and the quest not ready, so a step back then waits
    local waiting = _settling and (not GetTime or GetTime() < _settling)
    if waiting and _progress and (progress < _progress or rows < _rows) then return end
    local keep = showing(tomtom())
    local m, x, y = place(self, questID, q, keep and _m, _x, _y)
    if not m then
        self:Follow(questID, _followed)
        return
    end
    -- A spot already set is not set again, nor one taken down, on arrival or by hand, while the player still stands at it
    if m == _m and near(x, _x) and near(y, _y) and (keep or playerAt(m, x, y)) then
        _sig, _progress, _rows = sig, progress, rows
        return
    end
    self:Set(m, x, y, _title or q.title, questID, _followed)
end

-- How long after a loading screen a step back in the followed quest is taken for a stale read
local SETTLE = 10

local function isTask(questID)
    local log = C_QuestLog
    return log and ((log.IsWorldQuest and log.IsWorldQuest(questID)) or (log.IsQuestTask and log.IsQuestTask(questID)))
end

function Arrow:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not (Events and Events.On and Events.Debounce) then return end
    local function retarget() Arrow:Retarget() end
    local function soon()
        if _questID and tomtom() then Events:Debounce("QuestArrow", 0.3, retarget) end
    end
    local function gone(event, questID)
        if questID == nil or questID ~= _questID then return end
        -- A world quest or bonus objective leaves the log as you leave its area, so that removal is not taken as its end
        if event == "QUEST_REMOVED" and isTask(questID) then return end
        Arrow:Clear()
    end
    if retail() then
        Events:On("QUEST_LOG_UPDATE", soon)
        Events:On("QUEST_POI_UPDATE", soon)
        Events:On("SUPER_TRACKING_PATH_UPDATED", soon)
        Events:On("QUEST_REMOVED", gone)
        Events:On("QUEST_TURNED_IN", gone)
        return
    end
    local function settling()
        _settling = (GetTime and GetTime() or 0) + SETTLE
        if C_Timer and C_Timer.After then C_Timer.After(SETTLE, soon) end
    end
    Events:On("QUEST_LOG_UPDATE", soon)
    Events:On("QUEST_REMOVED", gone)
    Events:On("QUEST_TURNED_IN", gone)
    Events:On("PLAYER_LEAVING_WORLD", settling)
    Events:On("LOADING_SCREEN_ENABLED", settling)
    -- Again once the world is in, so a long load does not use the wait up
    Events:On("PLAYER_ENTERING_WORLD", settling)
end
