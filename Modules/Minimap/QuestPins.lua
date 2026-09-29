local _, ns = ...

local M = ns:RegisterSubsystem("MinimapQuestPins", {})

-- HereBeDragons tracks icons per owner, so this string is what lets RemoveAllMinimapIcons drop
-- EQ's without touching another addon's.
local REF = "EverythingQuests"

local ICON_SIZE = 12

-- Gated on the library's own presence, never a build number. Only the flavor TOCs list
-- HereBeDragons, so this is inert on retail, where EQ stays off the real WorldMapFrame.
local function lib()
    return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local _pool, _active = {}, {}

local function acquire()
    local f = tremove(_pool)
    if not f then
        f = CreateFrame("Frame", nil, _G.Minimap)
        f:SetSize(ICON_SIZE, ICON_SIZE)
        -- A mouse enabled frame over the minimap eats the click underneath it, costing the
        -- tracking menu and the ping wherever a pin sits, so take no mouse where the setter
        -- is absent.
        if f.SetMouseClickEnabled then
            f:EnableMouse(true)
            f:SetMouseClickEnabled(false)
        end
        f.texture = f:CreateTexture(nil, "OVERLAY")
        f.texture:SetAllPoints()
        f:SetScript("OnEnter", function(self)
            if not self.questID then return end
            local tip = ns.Util.PinTooltip()
            if self.avail then
                tip:SetOwner(self, "ANCHOR_LEFT")
                ns.QuestPinAvailable(tip, self.avail, true)
                tip:Show()
                return
            end
            local Cache = ns:GetSubsystem("Cache")
            local q = Cache and Cache:Get(self.questID)
            if not q then return end
            tip:SetOwner(self, "ANCHOR_LEFT")
            tip:SetText(ns.QuestPinTitle(q, self.questID), 1.0, 0.82, 0.0, 1, true)
            ns.QuestPinOwned(tip, q, self.kind, self.objMask, self.srcID)
            ns.QuestPinParty(tip, self.questID, self.kind, self.objMask)
            tip:Show()
        end)
        f:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)
    end
    _active[#_active + 1] = f
    return f
end

-- Read by /eqsprobe minimap. "Registered 0" and "registered 200 that HBD refused" look identical
-- from the minimap itself, and they have completely different causes.
M._registered, M._rejected, M._mapID, M._stage = 0, 0, nil, "never ran"
M._yielded = 0
M._blizzardMarks = {}

-- No Lua call lists the engine's own markers, so yield only for the narrowest set seen in game
local function readBlizzardMarks(mapID)
    local marks = M._blizzardMarks
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
        if qid and ns.Compat and ns.Compat.IsQuestWatched(qid) == true then marks[qid] = true end
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

local function releaseAll()
    local HBDP = lib()
    if HBDP then HBDP:RemoveAllMinimapIcons(REF) end
    if M._giverTicker then M._giverTicker:Cancel() end
    M._giverTicker = nil
    wipe(M._givers)
    M._giversHeld = 0
    for i = #_active, 1, -1 do
        local f = _active[i]
        f.questID, f.kind, f.objMask, f.avail, f.srcID = nil, nil, nil, nil, nil
        if f.held then setHeld(f, false) end
        f.held = nil
        f:Hide()
        _active[i] = nil
        _pool[#_pool + 1] = f
    end
    M._registered, M._rejected = 0, 0
end

function M:Rebuild()
    releaseAll()
    M._yielded = 0
    wipe(M._blizzardMarks)

    local HBDP = lib()
    if not HBDP then M._stage = "HereBeDragons not loaded on this flavor" return end

    -- Compared against false, not tested for truthiness, so a profile that predates this default
    -- reads as ON - which is what the options checkbox shows for the same nil.
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.map and DB.db.profile.map.showMinimapPins == false then
        M._stage = "off in options"
        return
    end

    -- The player's zone, NOT the open world map. These two disagree the moment you scroll the
    -- map to somewhere else, and the minimap must follow the player.
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
    for qid, q in pairs(Cache:All()) do
        local n, _, source = Provider:PointsFor(qid, mapID, q)
        -- Blizzard's marker is its turn-in or its one point, so the objective clusters stay
        if n > 0 and marked[qid] and (source == "turnin" or source == "single") then
            M._yielded = M._yielded + 1
            n = 0
        end
        for i = 1, n do
            local x, y = Provider._ptX[i], Provider._ptY[i]
            local f = acquire()
            f.questID, f.kind, f.objMask = qid, Provider._ptKind[i], Provider._ptMask[i]
            f.srcID = Provider._ptSrc[i]
            f.texture:SetTexture(ns.QuestPinTexture(q.isComplete, f.kind))
            f.texture:SetVertexColor(ns.QuestPinTint(f.kind, q.isComplete))
            -- AddMinimapIconMap answers false rather than raising when HereBeDragons has no
            -- world size for the map.
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

    -- Same producer as the world map, so the two cannot silently diverge.
    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail and Avail.PointsFor then
        local n = Avail:PointsFor(mapID)
        local floor = engine and Avail.TrivialFloor and Avail:TrivialFloor()
        for i = 1, n do
            local quests = Avail._locQuests[i]
            local f = acquire()
            f.questID, f.kind, f.objMask, f.avail = quests[1], nil, nil, quests
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
