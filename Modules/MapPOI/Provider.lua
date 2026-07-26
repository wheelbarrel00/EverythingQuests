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

function providerMixin:_DoRefresh()
    self:RemoveAllData()

    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.map and DB.db.profile.map.showQuestPins == false then
        return
    end

    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local Cache = ns:GetSubsystem("Cache")
    wipe(_seenQids)

    local primary = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
    if primary then
        for i = 1, #primary do
            local info = primary[i]
            local qid  = info and info.questID
            if qid then
                local x, y = info.x, info.y
                if (not x or not y) and C_QuestLog.GetNextWaypointForMap then
                    x, y = C_QuestLog.GetNextWaypointForMap(qid, mapID)
                end
                if type(x) == "number" and type(y) == "number" then
                    _seenQids[qid] = true
                    local q = Cache:Get(qid)
                    if q then
                        map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
                    end
                end
            end
        end
    end

    if Cache and C_QuestLog.GetNextWaypointForMap then
        for qid, q in pairs(Cache:All()) do
            if not _seenQids[qid] then
                local x, y = C_QuestLog.GetNextWaypointForMap(qid, mapID)
                if type(x) == "number" and type(y) == "number" then
                    map:AcquirePin(PIN_TEMPLATE, qid, x, y, q.isComplete)
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
