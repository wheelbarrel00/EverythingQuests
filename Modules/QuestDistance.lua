local _, ns = ...

-- Era and TBC cannot say how far away a quest is, so EQ measures it from its own tables for EQ Objective Tracker's Distance sort
local D = ns:RegisterSubsystem("QuestDistance", {})

local function core()
    return LibStub and LibStub("HereBeDragons-2.0", true)
end

-- [questID] = its points on the player's continent in world yards, read again only when what they came from changes
D._points = {}
local _points = D._points
local _known, _seen, _maps, _mapInst = {}, {}, {}, {}

-- The objective count leads, so a list of another length never reads as the old one, and a number builds no string per call
local function signature(q)
    local objs = q.objectives
    local n = objs and #objs or 0
    local s = n
    for i = 1, n do s = s * 2 + (objs[i].finished and 1 or 0) end
    return s * 2 + (q.isComplete and 1 or 0)
end

local function mapInstance(HBD, map)
    local inst = _mapInst[map]
    if inst == nil then
        local _, _, found = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, map)
        inst = found
        if inst then _mapInst[map] = inst end
    end
    return inst
end

local function add(c, HBD, x, y, map)
    local wx, wy = HBD:GetWorldCoordinatesFromZone(x, y, map)
    if not (wx and wy) then return end
    local k = c.n + 1
    c.n, c.wx[k], c.wy[k] = k, wx, wy
end

-- On the shipped Era and TBC data a quest's single point marks one of its objectives exactly when its map holds a spawn of theirs that is not a dungeon entrance
local function marksObjective(qid, map)
    local spawns = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    local list = spawns and spawns[qid] and spawns[qid][map]
    for i = 1, list and #list or 0 do
        if not ns.QuestIsEntrance(math.floor(list[i] % 1e9 / 1e8)) then return true end
    end
    return false
end

local function collect(HBD, Provider, qid, q, pinst)
    local sig = signature(q)
    local c = _points[qid]
    if c and c.sig == sig and c.inst == pinst then return c end
    if not c then
        c = { wx = {}, wy = {}, n = 0 }
        _points[qid] = c
    end
    -- Stamped only at the end, so a read an error cut short runs again on the next call
    local old = #c.wx
    c.sig, c.n = nil, 0
    Provider:MapsFor(qid, q, nil, _maps)
    local found = 0
    for m = 1, #_maps do
        local map = _maps[m]
        if mapInstance(HBD, map) == pinst then
            local n, _, source = Provider:PointsFor(qid, map, q, true)
            -- Only a finished quest with no hand-in row reaches a single point on a map holding its spawns, every objective done by then
            if source == "single" and marksObjective(qid, map) then n = 0 end
            found = found + n
            for i = 1, n do add(c, HBD, Provider._ptX[i], Provider._ptY[i], map) end
        end
    end
    for m = 1, #_maps do
        if found > 0 then break end
        local map = _maps[m]
        if mapInstance(HBD, map) ~= pinst then found = found + Provider:PointsFor(qid, map, q, true) end
    end
    -- With no point left anywhere the single point stands in, unless it marks an objective, every objective with points being done by now
    if found == 0 then
        local packed = ns.CLASSIC_QUEST_COORDS and ns.CLASSIC_QUEST_COORDS[qid]
        if packed then
            local map, rest = math.floor(packed / 1e8), packed % 1e8
            if mapInstance(HBD, map) == pinst and not marksObjective(qid, map) then
                add(c, HBD, math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, map)
            end
        end
    end
    for k = c.n + 1, old do c.wx[k], c.wy[k] = nil, nil end
    c.sig, c.inst = sig, pinst
    return c
end

-- Yards to the quest's nearest point on your continent, or nil inside an instance, on another continent or with nothing to measure
function D:Yards(questID)
    local HBD = core()
    local Provider = ns:GetSubsystem("MapPOIProvider")
    local Cache = ns:GetSubsystem("Cache")
    if not (HBD and Provider and Provider.PointsFor and Provider.MapsFor and Cache) then return nil end
    if IsInInstance and IsInInstance() then return nil end
    local px, py, pinst = HBD:GetPlayerWorldPosition()
    if not (px and py and pinst) then return nil end
    local q = Cache:Get(questID)
    if not q then return nil end
    local c = collect(HBD, Provider, questID, q, pinst)
    local wx, wy, best = c.wx, c.wy, nil
    for k = 1, c.n do
        local dx, dy = wx[k] - px, wy[k] - py
        local d = dx * dx + dy * dy
        if not best or d < best then best = d end
    end
    return best and math.sqrt(best) or nil
end

local function check()
    local Cache = ns:GetSubsystem("Cache")
    if not Cache then return end
    local changed = false
    wipe(_seen)
    for qid, q in pairs(Cache:All()) do
        _seen[qid] = true
        local s = signature(q)
        if _known[qid] ~= s then _known[qid], changed = s, true end
    end
    for qid in pairs(_known) do
        if not _seen[qid] then _known[qid], changed = nil, true end
    end
    for qid in pairs(_points) do
        if not _seen[qid] then _points[qid] = nil end
    end
    if changed and D._onChanged then D._onChanged() end
end

-- Only EQ's own inputs are watched, as the tracker re-sorts by itself as you move
function D:Watch(onChanged)
    if self._onChanged then return end
    self._onChanged = onChanged
    local Events = ns:GetSubsystem("Events")
    local function soon() Events:Debounce("QuestDistance", 0.3, check) end
    Events:On("QUEST_LOG_UPDATE", soon)
    Events:On("QUEST_ACCEPTED", soon)
    Events:On("QUEST_REMOVED", soon)
    -- A loading screen can put you on another continent or in an instance
    Events:On("PLAYER_ENTERING_WORLD", function() onChanged() end)
    soon()
end
