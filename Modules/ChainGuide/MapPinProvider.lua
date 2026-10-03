local _, ns = ...

local M = ns:RegisterSubsystem("ChainGuideMapPins", {})

local PIN_TEMPLATE = "EQChainPinTemplate"

local providerMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function providerMixin:OnAdded(mapCanvas)
    MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
    mapCanvas:SetPinTemplateType(PIN_TEMPLATE, "BUTTON")
end

function providerMixin:RemoveAllData()
    if self:GetMap() then
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
end

local _seen = {}

function providerMixin:_DoRefresh()
    self:RemoveAllData()

    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.chainGuide and DB.db.profile.chainGuide.showMapPins == false then
        return
    end

    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local CG = ns:GetSubsystem("ChainGuide")
    local chain = CG and CG.GetTrackedChain and CG:GetTrackedChain()
    if not chain then return end

    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local W          = ns:GetSubsystem("ChainGuideWaypoint")
    if not (Database and Characters and W) then return end

    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)
    local items = chain.items
    if not (items and #items > 0) then
        if not self._itemsRetry then
            self._itemsRetry = true
            C_Timer.After(0.4, function()
                self._itemsRetry = false
                self:RefreshAllData()
            end)
        end
        return
    end

    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local char = Database:CurrentCharacter()
    local CS = chain._generated and ns:GetSubsystem("ChainGuideClassicSource")
    local nextStep = W.NextActionableStep and W:NextActionableStep(chain)
    local nextID = nextStep and nextStep.id

    wipe(_seen)
    for i = 1, #items do
        local raw = items[i]
        if raw and raw.type ~= "chain" and not raw.breadcrumb then
            local item = Database:GetVariation(raw, char)
            local qid  = item and item.id
            -- A quest closed by a later step or another branch would be pinned as one still to come
            if qid and not _seen[qid] and not (CS and CS:IsClosed(qid)) then
                local rm, rx, ry, inLog = W:ResolveForPin(qid, chain)
                if rm == mapID and rx and ry then
                    _seen[qid] = true
                    local status
                    if qid == nextID then
                        status = "next"
                    elseif Characters:IsQuestCompleted(qid) then
                        status = "complete"
                    elseif inLog then
                        status = "active"
                    else
                        status = "pending"
                    end
                    map:AcquirePin(PIN_TEMPLATE, qid, rx, ry, status, inLog)
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

function M:Refresh()
    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
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
end
