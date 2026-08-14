local _, ns = ...

local M = ns:RegisterSubsystem("MapPOIProvider", {})

local PIN_TEMPLATE = "EQQuestPinTemplate"

local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

-- SetPinTemplateType only applies to the current canvas, so it has to be registered here in OnAdded
function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

-- Every pin this provider draws, so a hovered pin can aggregate its neighbours without
-- enumerating the canvas - ExecuteOnAllPins and RegisterPin are both absent on Era.
M._drawnN = 0
M._drawnQ, M._drawnX, M._drawnY, M._drawnK, M._drawnM = {}, {}, {}, {}, {}

-- The quest list of an available-quest pin, which has no quest log entry for the tooltip to reach.
-- Nil for every pin backed by the quest log, which is every pin on retail.
M._drawnA = {}

local function record(qid, x, y, kind, mask, avail)
    local n = M._drawnN + 1
    M._drawnN, M._drawnQ[n], M._drawnX[n], M._drawnY[n] = n, qid, x, y
    M._drawnK[n], M._drawnM[n], M._drawnA[n] = kind, mask, avail
end

function providerMixin:RemoveAllData()
    M._drawnN = 0
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

local _seenQids = {}

-- Classic has no Blizzard coordinate source, so a generated table is the only one there. One
-- packed number per quest: m*1e8 + floor(x*1e4)*1e4 + floor(y*1e4). The gate is the table's own
-- presence, never a build number - only the flavor TOCs list it, so retail gets nil here.
local function classicWaypoint(questID, mapID)
    local coords = ns.CLASSIC_QUEST_COORDS
    local packed = coords and coords[questID]
    if not packed or math.floor(packed / 1e8) ~= mapID then return nil end
    local rest = packed % 1e8
    return math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
end

local function waypointFor(questID, mapID)
    if C_QuestLog.GetNextWaypointForMap then
        local x, y = C_QuestLog.GetNextWaypointForMap(questID, mapID)
        if type(x) == "number" and type(y) == "number" then return x, y end
    end
    return classicWaypoint(questID, mapID)
end

local function spawnPoints(questID, mapID)
    local byMap = ns.CLASSIC_QUEST_SPAWNS and ns.CLASSIC_QUEST_SPAWNS[questID]
    return byMap and byMap[mapID]
end

-- Its own table because the single-point table stores the OBJECTIVE, so a finished quest read
-- from there pins the field you farmed instead of the person waiting.
local function turnInMaps(questID)
    return ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
end

-- The slider's far right means draw them all, so it needs a number to sit at.
ns.MAPPOI_MAX_PINS = 250

-- Applied here, not in the generator, so the table stays uncapped and the slider can still
-- reach unlimited. Zone coverage peaks at 0.015 - raising it for tidiness measures worse.
local PIN_SEPARATION = 0.015

-- Map coordinates are 0-1 on both axes but the canvas is about 1002x668, so the same number is
-- half again as much ground in x.
local MAP_ASPECT = 1.5

-- Grid rather than pairwise distance: one quest can offer over a thousand points on one map,
-- and comparing each candidate against every accepted one is quadratic.
local _spreadCells = {}
local function spreadReset() wipe(_spreadCells) end
local function spreadAccepts(x, y)
    local cx = math.floor(x * MAP_ASPECT / PIN_SEPARATION)
    local cy = math.floor(y / PIN_SEPARATION)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if _spreadCells[(cx + dx) * 4096 + (cy + dy)] then return false end
        end
    end
    _spreadCells[cx * 4096 + cy] = true
    return true
end

-- Returns nil for unlimited, not a huge number, so a caller cannot forget to special case a
-- sentinel.
local function pinLimit()
    local DB = ns:GetSubsystem("DB")
    local n = DB and DB.db.profile.map and DB.db.profile.map.pinCap
    if type(n) ~= "number" then return 50 end
    if n >= ns.MAPPOI_MAX_PINS then return nil end
    return math.max(1, math.floor(n))
end

-- Shared scratch for PointsFor, which the world map and the minimap both call. Read the arrays
-- before calling again.
M._ptX, M._ptY, M._ptKind, M._ptMask = {}, {}, {}, {}

-- The generator's kind values against the client's own objective `type` strings. Shared with
-- Modules/Nameplates so one number never means two different objective types.
ns.QUEST_KIND_TYPE = { [1] = "monster", [2] = "object", [3] = "item" }

-- A point inside an instance carries its real kind plus this, so the pin marks the way in. The
-- kind has to survive underneath - the objective index is numbered within that kind's bucket.
ns.QUEST_KIND_ENTRANCE = 4
function ns.QuestRealKind(kind)
    if not kind then return nil end
    return kind > ns.QUEST_KIND_ENTRANCE and (kind - ns.QUEST_KIND_ENTRANCE) or kind
end
function ns.QuestIsEntrance(kind)
    return kind ~= nil and kind > ns.QUEST_KIND_ENTRANCE
end

-- The quest's objectives bucketed by type, in client order, so bit i of a point's mask indexes
-- straight into the right one. Reused scratch - read it before the next call.
local _byType = {}
local function bucketObjectives(q)
    wipe(_byType)
    local objs = q and q.objectives
    if not objs then return end
    for i = 1, #objs do
        local o = objs[i]
        local t = o.type
        if t then
            local bucket = _byType[t]
            if not bucket then bucket = {}; _byType[t] = bucket end
            bucket[#bucket + 1] = o
        end
    end
end

-- Fails open. Before the quest log populates the client reports no objectives of this type, and
-- hiding on that would empty the map during loading.
local function maskWanted(mask, kind)
    local bucket = _byType[ns.QUEST_KIND_TYPE[ns.QuestRealKind(kind)] or ""]
    if not bucket or #bucket == 0 then return true end
    local rest, i = mask, 0
    while rest > 0 do
        if rest % 2 == 1 then
            local o = bucket[i + 1]
            -- An index past what the client reported is not evidence the objective is done
            if not o or not o.finished then return true end
        end
        rest, i = math.floor(rest / 2), i + 1
    end
    return false
end

-- The third return is a string, not a boolean, because /eqsprobe has to tell three sources apart
-- that look identical on the map and share no cause when they go wrong.
function M:PointsFor(questID, mapID, q)
    local X, Y, K, MK = self._ptX, self._ptY, self._ptKind, self._ptMask
    local isComplete = q and q.isComplete

    -- A finished quest wants the turn-in, not the places you were farming. Every finisher
    -- location is drawn, not one picked point, because 176 quests hand in on more than one map
    -- and choosing one of those leaves the other zone with no pin at all.
    if isComplete then
        local byMap = turnInMaps(questID)
        if byMap then
            -- The table knows this quest, so it is AUTHORITATIVE for every map, not just this
            -- one. Falling through here let the single-point table answer with the OBJECTIVE
            -- location instead - measured on 475 quests whose turn-in is in a different zone
            -- from their objective. Quest 1787 hands in at Stormwind and drew "Ready to turn in"
            -- on the Elwynn field it was farmed in.
            local turnIn = byMap[mapID]
            if not turnIn then return 0, 0, "none" end
            for i = 1, #turnIn do
                local v = turnIn[i]
                local rest = v % 1e8
                X[i], Y[i] = math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
                -- The kind rides along only so an entrance pin can be tinted and named. The
                -- icon is the turn-in mark either way, chosen from isComplete.
                K[i], MK[i] = math.floor(v / 1e8), nil
            end
            return #turnIn, 0, "turnin"
        end
    end

    local spawns = (not isComplete) and spawnPoints(questID, mapID)
    if not spawns then
        local x, y = waypointFor(questID, mapID)
        if not x then return 0, 0, "none" end
        X[1], Y[1], K[1], MK[1] = x, y, nil, nil
        return 1, 0, "single"
    end

    bucketObjectives(q)
    local limit = pinLimit()
    local n, thinned = 0, 0
    -- Per quest, so two different quests may still pin the same spot
    spreadReset()
    -- The list is stored densest first, so walking it in order is what makes a lower limit keep
    -- the best locations. Never reorder it here.
    for i = 1, #spawns do
        if limit and n >= limit then break end
        local v = spawns[i]
        local mask = math.floor(v / 1e9)
        local kind = math.floor(v % 1e9 / 1e8)
        -- Judged before the separation grid, so a point for a finished objective cannot claim a
        -- cell and crowd out one that is still wanted.
        if maskWanted(mask, kind) then
            local rest = v % 1e8
            local x = math.floor(rest / 1e4) / 1e4
            local y = (rest % 1e4) / 1e4
            if spreadAccepts(x, y) then
                n = n + 1
                X[n], Y[n], K[n], MK[n] = x, y, kind, mask
            else
                thinned = thinned + 1
            end
        end
    end
    return n, thinned, "spawn"
end

-- Read by /eqsprobe mappoi. Three failures look identical from outside - never called, called
-- and found nothing, called and drew pins that are not visible - and they share no fix.
M._refreshes, M._pins, M._stage, M._mapID = 0, 0, "never ran", nil
M._spawnPins, M._spawnThinned, M._availPins, M._turnInPins = 0, 0, 0, 0

function providerMixin:_DoRefresh()
    self:RemoveAllData()
    M._refreshes = M._refreshes + 1
    M._pins, M._mapID, M._spawnPins, M._spawnThinned = 0, nil, 0, 0
    M._availPins, M._turnInPins = 0, 0

    -- Owned pins only. Available quests have their own checkbox, which is what the option's
    -- own tooltip promises, so this must not return early past the available block below.
    local DB = ns:GetSubsystem("DB")
    local ownedWanted = not (DB and DB.db.profile.map and DB.db.profile.map.showQuestPins == false)
    M._ownedOff = not ownedWanted

    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        M._stage = "world map not shown"
        return
    end

    local map = self:GetMap()
    if not map then
        M._stage = "provider has no canvas"
        return
    end
    local mapID = map:GetMapID()
    if not mapID then
        M._stage = "canvas has no mapID"
        return
    end
    M._stage, M._mapID = "ran", mapID

    local Cache = ns:GetSubsystem("Cache")
    wipe(_seenQids)

    local primary = ownedWanted and C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
    if primary then
        for i = 1, #primary do
            local info = primary[i]
            local qid  = info and info.questID
            if qid then
                local x, y = info.x, info.y
                if not x or not y then
                    x, y = waypointFor(qid, mapID)
                end
                if type(x) == "number" and type(y) == "number" then
                    _seenQids[qid] = true
                    local q = Cache:Get(qid)
                    if q then
                        map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete, mapID)
                        record(qid, x, y)
                        M._pins = M._pins + 1
                    end
                end
            end
        end
    end

    -- Not gated on GetNextWaypointForMap, which is absent on Classic. waypointFor answers nil
    -- when neither source has the quest, so no gate is needed.
    if Cache and ownedWanted then
        for qid, q in pairs(Cache:All()) do
            if not _seenQids[qid] then
                local n, thinned, source = M:PointsFor(qid, mapID, q)
                M._spawnThinned = M._spawnThinned + thinned
                for i = 1, n do
                    local x, y = M._ptX[i], M._ptY[i]
                    map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete, mapID,
                                   M._ptKind[i], M._ptMask[i])
                    record(qid, x, y, M._ptKind[i], M._ptMask[i])
                    M._pins = M._pins + 1
                    if source == "spawn" then
                        M._spawnPins = M._spawnPins + 1
                    elseif source == "turnin" then
                        M._turnInPins = M._turnInPins + 1
                    end
                end
            end
        end
    end

    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail and Avail.PointsFor then
        local n = Avail:PointsFor(mapID)
        for i = 1, n do
            local x, y = Avail._locX[i], Avail._locY[i]
            local quests = Avail._locQuests[i]
            -- Keyed on the first quest so the tooltip aggregation has a stable id per location.
            -- The whole list travels alongside it, so nothing is lost by picking one.
            map:AcquirePin(PIN_TEMPLATE, quests[1], x, y, false, mapID, nil, nil, quests)
            record(quests[1], x, y, nil, nil, quests)
            M._pins = M._pins + 1
            M._availPins = M._availPins + 1
        end
    end
end

function providerMixin:RefreshAllData()
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.05, function()
        self._refreshPending = false
        self:_DoRefresh()
    end)
end

function providerMixin:OnMapChanged()
    self:RefreshAllData()
end

local function attach(self)
    if self.attached then return end
    if not WorldMapFrame then return end
    local Lib = LibStub("LibMapPinHandler-1.0", true)
    if not Lib then return end
    local shadow = Lib:GetShadowCanvas(WorldMapFrame)
    if not shadow then return end

    self.provider = CreateFromMixins(providerMixin)
    shadow:AddDataProvider(self.provider)
    self.shadow   = shadow
    self.attached = true
end

function M:OnEnable()
    local Events = ns:GetSubsystem("Events")

    Events:On("PLAYER_ENTERING_WORLD", function() attach(self) end)

    local function refresh()
        if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
            self.provider:RefreshAllData()
        end
    end
    Events:On("QUEST_LOG_UPDATE",       refresh)
    Events:On("QUEST_ACCEPTED",         refresh)
    Events:On("QUEST_REMOVED",          refresh)
    Events:On("QUEST_TURNED_IN",        refresh)
    Events:On("SUPER_TRACKING_CHANGED", refresh)
end
