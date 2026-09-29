local _, ns = ...

local M = ns:RegisterSubsystem("MapPOIProvider", {})

local PIN_TEMPLATE = "EQQuestPinTemplate"

local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

-- SetPinTemplateType only applies to the current canvas, so it has to be registered here in OnAdded
function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

-- Every pin drawn, so a hovered pin finds its neighbors without ExecuteOnAllPins, which Era lacks
M._drawnN = 0
M._drawnQ, M._drawnX, M._drawnY, M._drawnK, M._drawnM = {}, {}, {}, {}, {}
M._drawnS = {}

-- An available pin's quest list, nil for every pin backed by the quest log
M._drawnA = {}

local function record(qid, x, y, kind, mask, avail, srcID)
    local n = M._drawnN + 1
    M._drawnN, M._drawnQ[n], M._drawnX[n], M._drawnY[n] = n, qid, x, y
    M._drawnK[n], M._drawnM[n], M._drawnA[n] = kind, mask, avail
    -- Assigned even when nil, or a reused index keeps the last refresh's finisher
    M._drawnS[n] = srcID
end

function providerMixin:RemoveAllData()
    M._drawnN = 0
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

local _seenQids = {}

-- m*1e8 + floor(x*1e4)*1e4 + floor(y*1e4). Gated on the table's presence, never a build number
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

-- First caller pays the deferred parse. See Compat.ClassicSpawns.
local function spawnPoints(questID, mapID)
    local spawns = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    local byMap = spawns and spawns[questID]
    return byMap and byMap[mapID]
end

-- Its own table, as the single-point one stores the objective and would pin a finished quest in the field
local function turnInMaps(questID)
    return ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
end

-- The slider's far right means draw them all, so it needs a number to sit at.
ns.MAPPOI_MAX_PINS = 250

-- Applied at read time so the table stays uncapped. Measured: zone coverage peaks at 0.015
local PIN_SEPARATION = 0.015

-- The canvas is half again as wide as it is tall, so a step in x covers more ground
local MAP_ASPECT = 1.5

-- A grid, since pairwise distance is quadratic and one quest can hold over a thousand points on one map
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

-- Nil for unlimited rather than a sentinel number a caller could forget
local function pinLimit()
    local DB = ns:GetSubsystem("DB")
    local n = DB and DB.db.profile.map and DB.db.profile.map.pinCap
    if type(n) ~= "number" then return 50 end
    if n >= ns.MAPPOI_MAX_PINS then return nil end
    return math.max(1, math.floor(n))
end

-- PointsFor's scratch, shared by both maps. Read it before the next call
M._ptX, M._ptY, M._ptKind, M._ptMask, M._ptSrc = {}, {}, {}, {}, {}

-- Generator kinds to the client's objective types, the one table the pins, plates and tooltips read
ns.QUEST_KIND_TYPE = { [1] = "monster", [2] = "object", [3] = "item" }

-- Added to a point's real kind inside an instance. The real kind survives, as the mask counts within it
ns.QUEST_KIND_ENTRANCE = 4
function ns.QuestRealKind(kind)
    if not kind then return nil end
    return kind > ns.QUEST_KIND_ENTRANCE and (kind - ns.QUEST_KIND_ENTRANCE) or kind
end
function ns.QuestIsEntrance(kind)
    return kind ~= nil and kind > ns.QUEST_KIND_ENTRANCE
end

-- By type in client order, so bit i of a mask indexes its bucket. Reused scratch
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

-- Fails open, as the client reports no objectives before the quest log loads
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

-- Owned pins only. isWatched is nil when nothing could answer, and nil SHOWS the pin
function ns.QuestPinTracked(q)
    local DB = ns:GetSubsystem("DB")
    if (DB and DB.db.profile.map and DB.db.profile.map.onlyTrackedPins) ~= true then
        return true
    end
    if q == nil or q.isWatched == nil then return true end
    return q.isWatched == true
end

-- For /eqsprobe mappoi. Counted in _DoRefresh, never in PointsFor, which the minimap also calls
M._untrackedHidden = 0

-- The third return names the source, so /eqsprobe can tell sources and refusals apart
function M:PointsFor(questID, mapID, q)
    local X, Y, K, MK, S = self._ptX, self._ptY, self._ptKind, self._ptMask, self._ptSrc
    local isComplete = q and q.isComplete

    if not ns.QuestPinTracked(q) then
        return 0, 0, "untracked"
    end

    -- A finished quest draws every finisher location, as some hand in on more than one map
    if isComplete then
        local byMap = turnInMaps(questID)
        if byMap then
            -- Authoritative for every map once it knows the quest, or 1787 marks its Elwynn field
            local turnIn = byMap[mapID]
            if not turnIn then return 0, 0, "none" end
            for i = 1, #turnIn do
                local v = turnIn[i]
                local rest = v % 1e8
                X[i], Y[i] = math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
                -- % 10, since srcID sits above the kind and would make every turn-in read as an entrance
                K[i], MK[i] = math.floor(v / 1e8) % 10, nil
                S[i] = math.floor(v / 1e9)
            end
            return #turnIn, 0, "turnin"
        end
    end

    local spawns = (not isComplete) and spawnPoints(questID, mapID)
    if not spawns then
        local x, y = waypointFor(questID, mapID)
        if not x then return 0, 0, "none" end
        X[1], Y[1], K[1], MK[1], S[1] = x, y, nil, nil, nil
        return 1, 0, "single"
    end

    bucketObjectives(q)
    local limit = pinLimit()
    local n, thinned = 0, 0
    -- Per quest, so two different quests may still pin the same spot
    spreadReset()
    -- Stored densest first, so a lower limit keeps the best locations. Never reorder here
    for i = 1, #spawns do
        if limit and n >= limit then break end
        local v = spawns[i]
        local mask = math.floor(v / 1e9)
        local kind = math.floor(v % 1e9 / 1e8)
        -- Before the separation grid, so a finished objective's point cannot take a wanted one's cell
        if maskWanted(mask, kind) then
            local rest = v % 1e8
            local x = math.floor(rest / 1e4) / 1e4
            local y = (rest % 1e4) / 1e4
            if spreadAccepts(x, y) then
                n = n + 1
                X[n], Y[n], K[n], MK[n], S[n] = x, y, kind, mask, nil
            else
                thinned = thinned + 1
            end
        end
    end
    return n, thinned, "spawn"
end

-- The single point never counts, because for most quests it is the turn-in fallback, not the objective.
local function classicDraws(questID, mapID, q)
    if not q or not (turnInMaps(questID) or spawnPoints(questID, mapID)) then return false end
    local n, _, source = M:PointsFor(questID, mapID, q)
    return n > 0 and (source == "spawn" or source == "turnin")
end

M._blizzardMarks = {}
M._blizzardStage = "never ran"

-- Mirrors QuestDataProvider:RefreshAllData around Blizzard's own gate by hand. Recheck when it changes
local function readBlizzardMarks(mapID, rows)
    local marks = wipe(M._blizzardMarks)
    if not ns.HAS_CLASSIC_SPAWNS then M._blizzardStage = "not this flavor" return marks end
    local dp = _G["QuestDataProviderMixin"]
    local gate = type(dp) == "table" and dp.ShouldShowQuest
    if type(gate) ~= "function" then M._blizzardStage = "no Blizzard quest provider" return marks end
    if not (GetCVarBool and GetCVarBool("questPOI")) then M._blizzardStage = "questPOI off" return marks end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local mapType = type(info) == "table" and info.mapType or nil
    if mapType == nil then M._blizzardStage = "no map type" return marks end
    local showsTask = C_TaskQuest and C_TaskQuest.DoesMapShowTaskQuestObjectives
                      and C_TaskQuest.DoesMapShowTaskQuestObjectives(mapID)

    local function ask(questID, isIndicator)
        local ok, shown = pcall(gate, dp, questID, mapType, showsTask, isIndicator)
        if ok and shown then marks[questID] = true end
    end
    if rows then
        for i = 1, #rows do
            local row = rows[i]
            if row and row.questID then ask(row.questID, row.isMapIndicatorQuest) end
        end
    end
    -- The routing pin Blizzard adds on top of the rows, for one quest only
    local focused = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
    local routed = focused or (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                               and C_SuperTrack.GetSuperTrackedQuestID())
    if type(routed) == "number" and routed > 0 and C_QuestLog.GetNextWaypointForMap then
        local x, y = C_QuestLog.GetNextWaypointForMap(routed, mapID)
        if x and y then ask(routed, false) end
    end
    M._blizzardStage = "asked"
    return marks
end

-- On retail EQ's pin at a Blizzard marker is there to ring it, so with the owned ring on that pin stays
local function ownedRingOn()
    return ns.QuestPinRingWanted ~= nil and ns.QuestPinRingWanted(false) == true
end

-- For /eqsprobe mappoi, since never called, found nothing and drew invisible pins all look alike
M._refreshes, M._pins, M._stage, M._mapID = 0, 0, "never ran", nil
M._spawnPins, M._spawnThinned, M._availPins, M._turnInPins = 0, 0, 0, 0
M._yielded = 0

function providerMixin:_DoRefresh()
    self:RemoveAllData()
    M._refreshes = M._refreshes + 1
    M._pins, M._mapID, M._spawnPins, M._spawnThinned = 0, nil, 0, 0
    M._availPins, M._turnInPins, M._untrackedHidden, M._yielded = 0, 0, 0, 0
    wipe(M._blizzardMarks)
    M._blizzardStage = "not reached"

    -- Owned pins only, so it must never return early past the available block below
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
    local marked = readBlizzardMarks(mapID, primary)
    local yields = not ownedRingOn()
    if primary then
        for i = 1, #primary do
            local info = primary[i]
            local qid  = info and info.questID
            local q    = qid and Cache:Get(qid)
            -- On Forever the Classic tables win where they draw, unless Blizzard's "?" marks this finished quest
            if qid and (not classicDraws(qid, mapID, q) or (marked[qid] and q and q.isComplete)) then
                local x, y = info.x, info.y
                if not x or not y then
                    x, y = waypointFor(qid, mapID)
                end
                if type(x) == "number" and type(y) == "number" then
                    _seenQids[qid] = true
                    -- This loop does not go through PointsFor, so the same gate is asked here
                    if q and not ns.QuestPinTracked(q) then
                        M._untrackedHidden = M._untrackedHidden + 1
                        q = nil
                    end
                    if q and marked[qid] and yields then
                        M._yielded = M._yielded + 1
                        q = nil
                    end
                    if q then
                        map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete, mapID)
                        record(qid, x, y)
                        M._pins = M._pins + 1
                    end
                end
            end
        end
    end

    -- Not gated on GetNextWaypointForMap, which Era and TBC lack
    if Cache and ownedWanted then
        for qid, q in pairs(Cache:All()) do
            if not _seenQids[qid] then
                local n, thinned, source = M:PointsFor(qid, mapID, q)
                if source == "untracked" then
                    M._untrackedHidden = M._untrackedHidden + 1
                elseif source == "single" and n > 0 and marked[qid] and yields then
                    -- Only Blizzard's routing pin reaches here, and waypointFor asked the same call
                    M._yielded = M._yielded + 1
                    n = 0
                end
                M._spawnThinned = M._spawnThinned + thinned
                for i = 1, n do
                    local x, y = M._ptX[i], M._ptY[i]
                    map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete, mapID,
                                   M._ptKind[i], M._ptMask[i], nil, M._ptSrc[i])
                    record(qid, x, y, M._ptKind[i], M._ptMask[i], nil, M._ptSrc[i])
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
            -- Keyed on the first quest for a stable id, with the whole list riding along
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

    -- A yield follows the focused quest, and focusing on the open map fires no game event to redraw on
    if not ns.HAS_CLASSIC_SPAWNS then return end
    for _, method in ipairs({ "SetFocusedQuestID", "ClearFocusedQuestID" }) do
        if type(WorldMapFrame[method]) == "function" then
            hooksecurefunc(WorldMapFrame, method, function()
                if self.provider and WorldMapFrame:IsShown() then self.provider:RefreshAllData() end
            end)
        end
    end
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
    -- Retail's only watch-change signal. On Classic EQOT owns the tracked set and TrackerBridge repaints
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)
    -- Blizzard's own markers come and go with these, and every yield depends on them
    if not ns.HAS_CLASSIC_SPAWNS then return end
    Events:On("QUEST_POI_UPDATE", refresh)
    Events:On("CVAR_UPDATE", function(_, cvar)
        if cvar == "questPOI" then refresh() end
    end)
end
