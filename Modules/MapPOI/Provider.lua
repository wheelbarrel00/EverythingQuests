local _, ns = ...

local M = ns:RegisterSubsystem("MapPOIProvider", {})

local PIN_TEMPLATE = "EQQuestPinTemplate"

local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

-- SetPinTemplateType only applies to the current canvas, so it has to be registered here in OnAdded
function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

function providerMixin:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

local _seenQids = {}

-- Classic has NO Blizzard coordinate source - GetQuestsOnMap answers an empty table forever
-- there and GetNextWaypointForMap does not exist - so a generated table is the only source on
-- that flavor. One packed number per quest: m*1e8 + floor(x*1e4)*1e4 + floor(y*1e4). The table
-- holds ONE point per quest, so a quest whose point is on another map gets no pin here.
--
-- ⛔ The GATE is the table's own presence, never a build number or a Has flag. Only the flavor
-- TOCs list the data file, so retail is untouched: this returns nil there and the Blizzard
-- path above is unchanged.
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

-- Read by /eqsprobe mappoi. Three failures look identical from outside - never called, called
-- and found nothing, called and drew pins that are not visible - and they share no fix.
M._refreshes, M._pins, M._stage, M._mapID = 0, 0, "never ran", nil

function providerMixin:_DoRefresh()
    self:RemoveAllData()
    M._refreshes = M._refreshes + 1
    M._pins, M._mapID = 0, nil

    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.map and DB.db.profile.map.showQuestPins == false then
        M._stage = "off in options"
        return
    end

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

    local primary = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
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
                        map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
                        M._pins = M._pins + 1
                    end
                end
            end
        end
    end

    -- ⛔ This loop used to be gated on GetNextWaypointForMap, which is what made it dead on
    -- Classic. waypointFor answers nil rather than raising when neither source has the quest,
    -- so the gate is no longer needed and retail behaves identically.
    if Cache then
        for qid, q in pairs(Cache:All()) do
            if not _seenQids[qid] then
                local x, y = waypointFor(qid, mapID)
                if x then
                    map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
                    M._pins = M._pins + 1
                end
            end
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
