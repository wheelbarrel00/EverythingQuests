local _, ns = ...

local M = ns:RegisterSubsystem("MinimapQuestPins", {})

-- HereBeDragons tracks icons per owner, so RemoveAllMinimapIcons drops EQ's alone
local REF = "EverythingQuests"

local ICON_SIZE = 12

-- Retail never lists this file, as another addon's HereBeDragons would answer here and EQ stays off the real WorldMapFrame
local function lib()
    return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

-- The core library, for world coordinates in yards
local function core()
    return LibStub and LibStub("HereBeDragons-2.0", true)
end

local function mapCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.map
end

local function pinSize()
    local cfg = mapCfg()
    local s = cfg and cfg.minimapPinScale
    return ICON_SIZE * (type(s) == "number" and s or 1)
end

local function screenCenter(f)
    local x, y = f:GetCenter()
    if not (x and y) then return nil end
    local s = f:GetEffectiveScale()
    return x * s, y * s
end

local function setAlpha(f, a)
    if f._alpha ~= a then
        f._alpha = a
        f:SetAlpha(a)
    end
end

local _pool, _active = {}, {}

-- The world map's own numbers: one pin width of reach, and four neighbors before a count
local TOOLTIP_MAX_EXTRA = 4
local _nearF, _nearD, _nearAt = {}, {}, {}

-- A marker on the rim can stand for a place far away, so only one inside the minimap counts as near
local function listable(f)
    return not f.held and not f.hidden and (not f.edge or f.inside) and f:IsShown()
end

-- Other pins shown within one pin width, one per quest or giver spot, nearest first
local function nearbyPins(self)
    local hx, hy = screenCenter(self)
    if not hx then return 0 end
    local reach = (self:GetWidth() or 0) * self:GetEffectiveScale()
    if reach <= 0 then return 0 end
    local reachSq = reach * reach
    wipe(_nearAt)
    local hoveredKey = self.avail or self.questID
    local n = 0
    for i = 1, #_active do
        local f = _active[i]
        local key = f.avail or f.questID
        if key and key ~= hoveredKey and listable(f) then
            local x, y = screenCenter(f)
            if x then
                local dx, dy = x - hx, y - hy
                local d = dx * dx + dy * dy
                if d <= reachSq then
                    local at = _nearAt[key]
                    if not at then
                        n = n + 1
                        _nearF[n], _nearD[n], _nearAt[key] = f, d, n
                    elseif d < _nearD[at] then
                        _nearF[at], _nearD[at] = f, d
                    end
                end
            end
        end
    end
    for i = 2, n do
        local f, d, j = _nearF[i], _nearD[i], i - 1
        while j >= 1 and _nearD[j] > d do
            _nearF[j + 1], _nearD[j + 1] = _nearF[j], _nearD[j]
            j = j - 1
        end
        _nearF[j + 1], _nearD[j + 1] = f, d
    end
    return n
end

local function addNeighbors(tip, self, Cache)
    local n = nearbyPins(self)
    -- Counted over drawable neighbors only, so the overflow number stays true
    local total = 0
    for i = 1, n do
        local f = _nearF[i]
        if f.avail or Cache:Get(f.questID) then total = total + 1 end
    end
    local shown = 0
    for i = 1, n do
        local f = _nearF[i]
        local other = (not f.avail) and Cache:Get(f.questID) or nil
        if f.avail or other then
            tip:AddLine(" ")
            if shown >= TOOLTIP_MAX_EXTRA then
                tip:AddLine((ns.L["and %d more"]):format(total - shown), 0.6, 0.6, 0.6)
                break
            end
            if f.avail then
                ns.QuestPinAvailable(tip, f.avail)
            else
                tip:AddLine(ns.QuestPinTitle(other, f.questID), 1.0, 0.82, 0.0, true)
                ns.QuestPinOwned(tip, other, f.kind, f.objMask, f.srcID)
            end
            shown = shown + 1
        end
    end
end

local function onEnter(self)
    if not self.questID then return end
    local Cache = ns:GetSubsystem("Cache")
    if not Cache then return end
    local q = (not self.avail) and Cache:Get(self.questID) or nil
    if not (q or self.avail) then return end
    local tip = ns.Util.PinTooltip()
    tip:SetOwner(self, "ANCHOR_LEFT")
    if self.avail then
        ns.QuestPinAvailable(tip, self.avail, true)
    else
        tip:SetText(ns.QuestPinTitle(q, self.questID), 1.0, 0.82, 0.0, 1, true)
        ns.QuestPinOwned(tip, q, self.kind, self.objMask, self.srcID)
        ns.QuestPinParty(tip, self.questID, self.kind, self.objMask)
    end
    -- A marker on the rim lists only its own quest, as markers bunched there can stand for places far apart
    if not self.edge or self.inside then addNeighbors(tip, self, Cache) end
    tip:Show()
end

local function ownsTooltip(f)
    local tip = ns.Util.PinTooltip()
    return tip:IsShown() and tip:GetOwner() == f, tip
end

local function acquire(size)
    local f = tremove(_pool)
    if not f then
        f = CreateFrame("Frame", nil, _G.Minimap)
        -- A frame that takes the mouse eats the minimap click under it, so it takes hover only where it can
        if f.SetMouseClickEnabled then
            f:EnableMouse(true)
            f:SetMouseClickEnabled(false)
        end
        f.texture = f:CreateTexture(nil, "OVERLAY")
        f.texture:SetAllPoints()
        f:SetScript("OnEnter", onEnter)
        f:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)
    end
    f:SetSize(size, size)
    _active[#_active + 1] = f
    return f
end

-- Read by /eqsprobe minimap, where 0 registered and 200 refused by HereBeDragons look alike on the minimap
M._registered, M._rejected, M._mapID, M._stage = 0, 0, nil, "never ran"
M._yielded = 0
M._blizzardMarks, M._blizzardMarkAt = {}, {}

-- No Lua call lists the engine's own markers, so yield only for the narrowest set seen in game
local function readBlizzardMarks(mapID)
    local marks = M._blizzardMarks
    for _, at in pairs(M._blizzardMarkAt) do wipe(at) end
    local filters = Enum and Enum.MinimapTrackingFilter
    local filteredOut = C_Minimap and C_Minimap.IsFilteredOut
    if not (filters and filters.QuestPOIs and filteredOut) or filteredOut(filters.QuestPOIs) then
        return marks
    end
    if not (GetCVarBool and GetCVarBool("questPOI")) then return marks end
    local rows = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
    if type(rows) ~= "table" then return marks end
    for i = 1, #rows do
        local qid = rows[i] and rows[i].questID
        if qid and ns.Compat and ns.Compat.IsQuestWatched(qid) == true then
            marks[qid] = true
            local x, y = rows[i].x, rows[i].y
            if type(x) == "number" and type(y) == "number" then
                local at = M._blizzardMarkAt[qid] or {}
                M._blizzardMarkAt[qid] = at
                at[#at + 1], at[#at + 2] = x, y
            end
        end
    end
    return marks
end

-- Yards within which the engine marks a giver or finisher. A guess until /eqsprobe minimap measures it
local GIVER_RANGE = 100
M._giverRange = GIVER_RANGE
M._givers, M._giversHeld = {}, 0

local function engineDrawsGivers()
    return C_Minimap and C_Minimap.IsFilteredOut and C_Minimap.IsTrackingHiddenQuests and true or false
end

-- Blizzard's ShouldAddQuestOffer trivial and account gates, with EQ's own trivial floor beside IsQuestTrivial
local function engineMarks(questID, Avail, floor)
    local tracksHidden = C_Minimap.IsTrackingHiddenQuests
    if not (tracksHidden and tracksHidden()) then
        local level = Avail.QuestLevel and Avail:QuestLevel(questID)
        if level and floor and level < floor then return false end
        local ok, trivial = pcall(C_QuestLog.IsQuestTrivial, questID)
        if ok and trivial then return false end
    end
    local tracking = C_Minimap.IsTrackingAccountCompletedQuests
    if C_QuestLog.IsQuestFlaggedCompletedOnAccount and not (tracking and tracking()) then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompletedOnAccount, questID)
        if ok and done then
            local okKept, kept = pcall(C_QuestLog.QuestIgnoresAccountCompletedFiltering, questID)
            if not (okKept and kept) then return false end
        end
    end
    return true
end

-- HereBeDragons shows and hides the frame itself, so a held pin hides only its texture and mouse
local function setHeld(f, held)
    f.held = held
    f.texture:SetShown(not held)
    local tip = held and ns.Util.PinTooltip()
    if tip and tip:GetOwner() == f then tip:Hide() end
    if f.SetMouseClickEnabled then
        f:EnableMouse(not held)
        if not held then f:SetMouseClickEnabled(false) end
    end
end

local function giverDistance(HBDP, f)
    local ok, _, dist = pcall(HBDP.GetVectorToIcon, HBDP, f)
    if not (ok and type(dist) == "number") then return nil end
    if _G.issecretvalue and _G.issecretvalue(dist) then return nil end
    return dist
end

local function holdGivers()
    local HBDP = lib()
    local held = 0
    for i = 1, #M._givers do
        local f = M._givers[i]
        local dist = HBDP and giverDistance(HBDP, f)
        local hold = dist ~= nil and dist <= GIVER_RANGE
        if hold ~= f.held then setHeld(f, hold) end
        if hold then held = held + 1 end
    end
    M._giversHeld = held
end

-- The world map's own fade: within one and a half pin widths of your arrow, at 30%
local FADE_RADIUS_PINS, FADE_ALPHA = 1.5, 0.3
M._faded = 0
-- The spots faded at the last pass, so a pin rebuilt there keeps its fade until the library draws it
local _fadedKeys, _fadedNext = {}, {}

local function fadeWanted()
    local cfg = mapCfg()
    return (cfg and cfg.fadePinsOverPlayer) == true
end

-- The minimap's center is the player, so a pin within reach of it sits on your arrow
function M:ApplyFade()
    local on = fadeWanted()
    local mx, my
    if on and _G.Minimap then mx, my = screenCenter(_G.Minimap) end
    wipe(_fadedNext)
    local faded = 0
    for i = 1, #_active do
        local f = _active[i]
        local near = false
        if on and not f.hidden then
            local x, y
            if mx and f:IsShown() then x, y = screenCenter(f) end
            if x then
                local reach = (f:GetWidth() or 0) * f:GetEffectiveScale() * FADE_RADIUS_PINS
                local dx, dy = x - mx, y - my
                near = dx * dx + dy * dy <= reach * reach
            elseif f.fadeKey then
                near = _fadedKeys[f.fadeKey] == true
            end
        end
        f.underArrow = near
        if near and f.fadeKey then _fadedNext[f.fadeKey] = true end
        setAlpha(f, (f.edge and f.edgeAlpha or 1) * (near and FADE_ALPHA or 1))
        if near then faded = faded + 1 end
    end
    _fadedKeys, _fadedNext = _fadedNext, _fadedKeys
    M._faded = faded
end

-- Full strength within the first distance in yards, fading to the floor at the second
local EDGE_FULL_YARDS, EDGE_FAINT_YARDS, EDGE_MIN_ALPHA = 250, 1500, 0.4
-- The markers move every third tick, counted, as 0.15 added three times falls short of 0.45
local TICK, EDGE_EVERY = 0.15, 3

-- [questID] = the one marker that quest keeps, on the minimap's edge or, for a point on another map, inside it
M._edge, M._edgeShown = {}, 0
-- [questID] = its points in world yards, kept across rebuilds until what they were read from changes
local _cand, _maps, _mapInst, _sig = {}, {}, {}, {}

local function edgeWanted()
    local cfg = mapCfg()
    return not (cfg and cfg.minimapEdgePins == false)
end

local function edgeAlpha(yards)
    if yards <= EDGE_FULL_YARDS then return 1 end
    if yards >= EDGE_FAINT_YARDS then return EDGE_MIN_ALPHA end
    return 1 - (1 - EDGE_MIN_ALPHA) * (yards - EDGE_FULL_YARDS) / (EDGE_FAINT_YARDS - EDGE_FULL_YARDS)
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

-- Everything PointsFor reads, the game's own point on each map included, so an unchanged quest keeps the points it had
local function signature(qid, q, pinst)
    local cfg = mapCfg()
    wipe(_sig)
    _sig[1], _sig[2] = pinst, q.isComplete and 1 or 0
    _sig[3], _sig[4], _sig[5] = tostring(q.isWatched), tostring(cfg and cfg.pinCap), tostring(cfg and cfg.onlyTrackedPins)
    local objs = q.objectives
    for i = 1, objs and #objs or 0 do _sig[#_sig + 1] = objs[i].finished and 1 or 0 end
    local way = C_QuestLog.GetNextWaypointForMap
    for m = 1, #_maps do
        _sig[#_sig + 1] = _maps[m]
        if way then
            local x, y = way(qid, _maps[m])
            _sig[#_sig + 1] = tostring(x) .. "/" .. tostring(y)
        end
    end
    return table.concat(_sig, ",")
end

-- Every point the quest's pins take on its maps on your continent, in world yards, so the nearest can follow you
local function collect(HBD, Provider, qid, q, mapID, pinst)
    local c = _cand[qid]
    if not c then
        c = { wx = {}, wy = {}, map = {}, kind = {}, mask = {}, src = {}, n = 0 }
        _cand[qid] = c
    end
    Provider:MapsFor(qid, q, mapID, _maps)
    local sig = signature(qid, q, pinst)
    if c.sig == sig then return c.n end
    c.sig, c.inst, c.n = sig, pinst, 0
    for m = 1, #_maps do
        local map = _maps[m]
        if mapInstance(HBD, map) == pinst then
            local n = Provider:PointsFor(qid, map, q)
            for i = 1, n do
                local wx, wy = HBD:GetWorldCoordinatesFromZone(Provider._ptX[i], Provider._ptY[i], map)
                if wx and wy then
                    local k = c.n + 1
                    c.n = k
                    c.wx[k], c.wy[k], c.map[k] = wx, wy, map
                    c.kind[k], c.mask[k], c.src[k] = Provider._ptKind[i], Provider._ptMask[i], Provider._ptSrc[i]
                end
            end
        end
    end
    return c.n
end

-- Hidden markers take no mouse, or one would answer for its own pin underneath
local function setMarkerShown(f, on)
    if f.hidden == not on then return end
    f.hidden = not on
    f.texture:SetShown(on)
    if not on then
        local owns, tip = ownsTooltip(f)
        if owns then tip:Hide() end
    end
    if f.SetMouseClickEnabled then
        f:EnableMouse(on)
        if on then f:SetMouseClickEnabled(false) end
    end
end

local function placeEdges()
    local HBD, HBDP = core(), lib()
    local shown = 0
    local px, py, pinst, here
    if HBD and HBDP then
        px, py, pinst = HBD:GetPlayerWorldPosition()
        here = HBD:GetPlayerZone()
    end
    local holds = engineDrawsGivers()
    for qid, f in pairs(M._edge) do
        local c = _cand[qid]
        local best, bestD
        if px and py and c and c.inst == pinst then
            for k = 1, c.n do
                local dx, dy = c.wx[k] - px, c.wy[k] - py
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then best, bestD = k, d end
            end
        end
        if best then
            local moved = f.at ~= best
            if moved then
                f.at = best
                f.kind, f.objMask, f.srcID = c.kind[best], c.mask[best], c.src[best]
                f.texture:SetTexture(ns.QuestPinTexture(f.complete, f.kind))
                f.texture:SetVertexColor(ns.QuestPinTint(f.kind, f.complete))
                HBDP:AddMinimapIconWorld(REF, f, pinst, c.wx[best], c.wy[best], true)
            end
            local yards = math.sqrt(bestD)
            f.edgeAlpha = edgeAlpha(yards)
            setAlpha(f, f.edgeAlpha * (f.underArrow and FADE_ALPHA or 1))
            -- The library sets the edge flag only when it next draws, so a marker just placed keeps the last answer
            local onEdge = (not moved) and HBDP:IsMinimapIconOnEdge(f) == true
            local visible
            if holds and f.complete and f.kind == 1 and yards <= GIVER_RANGE then
                -- The engine puts its own "?" over a creature finisher it has loaded
                visible = false
            elseif c.map[best] ~= here or here ~= M._mapID then
                -- The pins show only while you stand in the map they were placed on, so elsewhere a marker stands in
                visible = true
            elseif moved then
                visible = c.shown == true
            else
                -- In range on your own map its pin already sits on that spot
                visible = onEdge
            end
            c.shown = visible
            f.inside = visible and not moved and not onEdge
            setMarkerShown(f, visible)
            if visible then
                shown = shown + 1
                if moved and ownsTooltip(f) then onEnter(f) end
            end
        elseif f.at then
            HBDP:RemoveMinimapIcon(REF, f)
            f.at, f.inside = nil, nil
        end
    end
    M._edgeShown = shown
end
M._placeEdges = placeEdges

local _sinceEdge = 0
local function tick()
    _sinceEdge = _sinceEdge + 1
    if _sinceEdge >= EDGE_EVERY then
        _sinceEdge = 0
        placeEdges()
    end
    if fadeWanted() then M:ApplyFade() end
end

local function releaseAll()
    local HBDP = lib()
    if HBDP then HBDP:RemoveAllMinimapIcons(REF) end
    if M._giverTicker then M._giverTicker:Cancel() end
    M._giverTicker = nil
    if M._ticker then M._ticker:Cancel() end
    M._ticker = nil
    wipe(M._givers)
    wipe(M._edge)
    M._giversHeld, M._edgeShown, M._faded = 0, 0, 0
    for i = #_active, 1, -1 do
        local f = _active[i]
        f.questID, f.kind, f.objMask, f.avail, f.srcID = nil, nil, nil, nil, nil
        if f.held then setHeld(f, false) end
        f.held = nil
        if f.edge then setMarkerShown(f, true) end
        f.edge, f.at, f.complete, f.inside, f.edgeAlpha = nil, nil, nil, nil, nil
        f.fadeKey, f.underArrow = nil, nil
        setAlpha(f, 1)
        f:Hide()
        _active[i] = nil
        _pool[#_pool + 1] = f
    end
    M._registered, M._rejected = 0, 0
end

-- Resizes the pins in place, as a slider drag would otherwise rebuild on every step
function M:ApplySize()
    local size = pinSize()
    for i = 1, #_active do _active[i]:SetSize(size, size) end
end

function M:Rebuild()
    releaseAll()
    M._yielded = 0
    wipe(M._blizzardMarks)

    local HBDP = lib()
    if not HBDP then M._stage = "HereBeDragons not loaded on this flavor" return end

    -- Compared against false, so a profile from before this default reads as on, as its checkbox shows
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.map and DB.db.profile.map.showMinimapPins == false then
        M._stage = "off in options"
        return
    end

    -- The player's zone, not the open world map, which can be scrolled anywhere
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then M._stage = "no map for player" return end
    M._stage, M._mapID = "ran", mapID

    local Provider = ns:GetSubsystem("MapPOIProvider")
    local Cache = ns:GetSubsystem("Cache")
    if not (Provider and Provider.PointsFor and Cache) then
        M._stage = "MapPOI provider absent"
        return
    end

    local marked = readBlizzardMarks(mapID)
    local engine = engineDrawsGivers()
    local size = pinSize()
    local HBD = edgeWanted() and Provider.MapsFor and core()
    local pinst
    if HBD then pinst = select(3, HBD:GetPlayerWorldPosition()) end
    for qid, q in pairs(Cache:All()) do
        local n, _, source = Provider:PointsFor(qid, mapID, q)
        -- Blizzard's marker is its turn-in or its one point, so the objective clusters stay
        if n > 0 and marked[qid] and (source == "turnin" or source == "single") then
            M._yielded = M._yielded + 1
            n = 0
        end
        local flagYield = false
        for i = 1, n do
            -- A flag Blizzard's own marker for the quest sits on yields to it, as the turn-in does
            if marked[qid] and ns.QuestRealKind(Provider._ptKind[i]) == 4
               and ns.QuestFlagAtMark(M._blizzardMarkAt[qid], Provider._ptX[i], Provider._ptY[i]) then
                flagYield = true
            else
                local x, y = Provider._ptX[i], Provider._ptY[i]
                local f = acquire(size)
                f.questID, f.kind, f.objMask = qid, Provider._ptKind[i], Provider._ptMask[i]
                f.srcID = Provider._ptSrc[i]
                f.fadeKey = qid .. ":" .. x .. ":" .. y
                f.texture:SetTexture(ns.QuestPinTexture(q.isComplete, f.kind))
                f.texture:SetVertexColor(ns.QuestPinTint(f.kind, q.isComplete))
                -- Answers false, not an error, when HereBeDragons has no world size for the map
                if HBDP:AddMinimapIconMap(REF, f, mapID, x, y, false, false) then
                    M._registered = M._registered + 1
                    -- The engine puts its own "?" over a creature finisher it has loaded, tracked or not
                    if engine and source == "turnin" and f.kind == 1 then
                        M._givers[#M._givers + 1] = f
                    end
                else
                    M._rejected = M._rejected + 1
                    f:Hide()
                end
            end
        end
        if flagYield then M._yielded = M._yielded + 1 end
        -- After the pins above, since collecting overwrites the provider's scratch
        if HBD and pinst and collect(HBD, Provider, qid, q, mapID, pinst) > 0 then
            local f = acquire(size)
            f.edge, f.questID, f.complete = true, qid, q.isComplete
            M._edge[qid] = f
        end
    end
    for qid in pairs(_cand) do
        if not M._edge[qid] then _cand[qid] = nil end
    end

    -- Same producer as the world map, so the two cannot silently diverge.
    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail and Avail.PointsFor then
        local n = Avail:PointsFor(mapID)
        local floor = engine and Avail.TrivialFloor and Avail:TrivialFloor()
        for i = 1, n do
            local quests = Avail._locQuests[i]
            local f = acquire(size)
            f.questID, f.kind, f.objMask, f.avail = quests[1], nil, nil, quests
            f.fadeKey = "!" .. Avail._locX[i] .. ":" .. Avail._locY[i]
            f.texture:SetTexture(ns.QUEST_PIN_AVAILABLE_ICON)
            f.texture:SetVertexColor(ns.QuestPinAvailableTint())
            if HBDP:AddMinimapIconMap(REF, f, mapID, Avail._locX[i], Avail._locY[i], false, false) then
                M._registered = M._registered + 1
                -- Per quest, since a creature's spot can hold an item start too. Objects and items are assumed unmarked
                if engine then
                    local kinds = quests.startKinds
                    for k = 1, #quests do
                        if kinds[k] == 1 and engineMarks(quests[k], Avail, floor) then
                            M._givers[#M._givers + 1] = f
                            break
                        end
                    end
                end
            else
                M._rejected = M._rejected + 1
                f:Hide()
            end
        end
    end

    -- The player walks into and out of the engine's sight, so the hold is judged again on a timer
    if #M._givers > 0 then
        holdGivers()
        M._giverTicker = C_Timer.NewTicker(0.5, holdGivers)
    end

    placeEdges()
    M:ApplyFade()
    if next(M._edge) or fadeWanted() then
        -- The first tick reads the edge flags the library has drawn by then
        _sinceEdge = EDGE_EVERY
        M._ticker = C_Timer.NewTicker(TICK, tick)
    end
end

function M:OnEnable()
    if not lib() then return end
    local Events = ns:GetSubsystem("Events")

    local function refresh()
        if self._pending then return end
        self._pending = true
        C_Timer.After(0.2, function()
            self._pending = false
            self:Rebuild()
        end)
    end

    Events:On("PLAYER_ENTERING_WORLD", refresh)
    Events:On("ZONE_CHANGED_NEW_AREA", refresh)
    Events:On("QUEST_LOG_UPDATE",      refresh)
    Events:On("QUEST_ACCEPTED",        refresh)
    Events:On("QUEST_REMOVED",         refresh)
    Events:On("QUEST_TURNED_IN",       refresh)
    -- Which markers yield to Blizzard's depends on its watch list and both quest marker settings
    if not (C_Minimap and C_Minimap.IsFilteredOut) then return end
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)
    Events:On("MINIMAP_UPDATE_TRACKING",  refresh)
    -- Blizzard's own quest map provider refreshes on this event, and the marks read the same rows
    Events:On("QUEST_POI_UPDATE",         refresh)
    Events:On("CVAR_UPDATE", function(_, cvar)
        if cvar == "questPOI" then refresh() end
    end)
end
