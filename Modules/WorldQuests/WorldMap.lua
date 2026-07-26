local _, ns = ...

local M = ns:RegisterSubsystem("WQWorldMap", {})

local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

-- Some WQs never return reward data, and without this cap one stuck quest keeps the retry re-walking every pin every 2s
local MAX_LOAD_ATTEMPTS = 3

local function getWorldQuests(mapID)
    if C_TaskQuest then
        if C_TaskQuest.GetQuestsOnMap          then return C_TaskQuest.GetQuestsOnMap(mapID)          end
        if C_TaskQuest.GetQuestsForPlayerByMapID then return C_TaskQuest.GetQuestsForPlayerByMapID(mapID) end
    end
    return nil
end

local function isExpiredWQ(questID)
    if not C_TaskQuest then return false end
    if C_TaskQuest.IsActive and not C_TaskQuest.IsActive(questID) then
        return true
    end
    -- Use seconds not minutes: a WQ with <60s left reports 0 minutes and would be culled wrongly.
    if C_TaskQuest.GetQuestTimeLeftSeconds then
        local s = C_TaskQuest.GetQuestTimeLeftSeconds(questID)
        if not s or s <= 0 then return true end
    elseif C_TaskQuest.GetQuestTimeLeftMinutes then
        local m = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        if not m or m <= 0 then return true end
    end
    return false
end

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

function providerMixin:_DoRefresh()
    self:RemoveAllData()
    self._pendingCount = 0

    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end

    self:_AcquirePins()

    -- Only rebuild the panel while open - the toggle already hid it, so refreshing it is wasted tainted work on the open map
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.worldQuests.popoutOpen then
        local Panel = ns:GetSubsystem("WQPanel")
        if Panel and Panel.Refresh then Panel:Refresh() end
    end
    -- Tab owns its own show/hide and content gate, so it refreshes every cycle
    local Tab = ns:GetSubsystem("WQTab")
    if Tab and Tab.Refresh then Tab:Refresh() end
end

function providerMixin:_AcquirePins()
    local map = self:GetMap()
    if not map then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnWorldMap) then return end

    local quests = getWorldQuests(mapID)
    if not quests then return end

    local Rewards = ns:GetSubsystem("WQRewards")
    local filters = DB.db.profile.worldQuests.filters
    local factionFilters = DB.db.profile.worldQuests.factionFilters or {}

    if self._loadAttemptsMapID ~= mapID then
        self._loadAttemptsMapID = mapID
        if self._loadAttempts then wipe(self._loadAttempts) else self._loadAttempts = {} end
    end
    local loadAttempts = self._loadAttempts

    for i = 1, #quests do
        local info = quests[i]
        local questID = info and (info.questID or info.questId)
        if questID and not isExpiredWQ(questID) then
            if HaveQuestRewardData and not HaveQuestRewardData(questID) then
                local n = (loadAttempts[questID] or 0) + 1
                loadAttempts[questID] = n
                if n <= MAX_LOAD_ATTEMPTS then
                    self._pendingCount = self._pendingCount + 1
                    if C_TaskQuest.RequestPreloadRewardData then
                        C_TaskQuest.RequestPreloadRewardData(questID)
                    end
                end
            elseif loadAttempts[questID] then
                loadAttempts[questID] = nil
            end

            local x, y = info.x, info.y
            if (not x or not y) and C_TaskQuest.GetQuestLocation then
                x, y = C_TaskQuest.GetQuestLocation(questID, mapID)
            end

            if type(x) == "number" and type(y) == "number" then
                local reward = Rewards:Classify(questID)
                local categoryAllowed = filters[reward.category] ~= false
                local factionAllowed  = true
                if categoryAllowed then
                    local fid = C_QuestLog and C_QuestLog.GetQuestFactionID
                                and C_QuestLog.GetQuestFactionID(questID)
                    if fid and fid > 0 and factionFilters[fid] == false then
                        factionAllowed = false
                    end
                    if factionAllowed and C_QuestLog and C_QuestLog.DoesQuestAwardReputationWithFaction then
                        for filterFid, val in pairs(factionFilters) do
                            if val == false and C_QuestLog.DoesQuestAwardReputationWithFaction(questID, filterFid) then
                                factionAllowed = false
                                break
                            end
                        end
                    end
                end
                if categoryAllowed and factionAllowed then
                    map:AcquirePin(PIN_TEMPLATE, questID, x, y, reward)
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

function M:UpdateSelections()
    if not (self.shadow and self.shadow.EnumeratePinsByTemplate) then return end
    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0
    for pin in self.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        if pin.UpdateSelectionVisual then
            pin:UpdateSelectionVisual(pin.questID == superID)
        end
    end
end

function M:Refresh()
    if not (self.provider and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    self.provider:RefreshAllData()
    if not self._retryPending then
        self._retryPending = true
        C_Timer.After(0.10, function()
            local pending = (self.provider and self.provider._pendingCount) or 0
            if pending > 0 then
                C_Timer.After(2.0, function()
                    self._retryPending = false
                    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
                        self.provider:RefreshAllData()
                    end
                end)
            else
                self._retryPending = false
            end
        end)
    end
end

function M:StartTicker()
    if self._ticker then return end
    self._ticker = C_Timer.NewTicker(60, function()
        if WorldMapFrame and WorldMapFrame:IsShown() then
            self:Refresh()
        end
    end)
end

function M:StopTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end
end

function M:OnEnable()
    local Events = ns:GetSubsystem("Events")

    -- _mapHooked guard: PLAYER_ENTERING_WORLD fires on every loading screen, so without it each entry appends another OnShow/OnHide closure to WorldMapFrame
    local function startTicker() self:StartTicker() end
    local function stopTicker()  self:StopTicker()  end
    Events:On("PLAYER_ENTERING_WORLD", function()
        attach(self)
        if WorldMapFrame then
            if not self._mapHooked then
                self._mapHooked = true
                WorldMapFrame:HookScript("OnShow", startTicker)
                WorldMapFrame:HookScript("OnHide", stopTicker)
            end
            if WorldMapFrame:IsShown() then self:StartTicker() end
        end
    end)

    local function refresh() self:Refresh() end
    Events:On("WORLD_QUEST_COMPLETED_BY_SPELL",        refresh)
    Events:On("QUEST_LOG_UPDATE",                      refresh)
    Events:On("QUEST_TURNED_IN",                       refresh)
    Events:On("TASK_PROGRESS_UPDATE",                  refresh)

    Events:On("SUPER_TRACKING_CHANGED", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then self:UpdateSelections() end
    end)

    -- Do NOT hooksecurefunc WorldMap_WorldQuestDataProviderMixin.RefreshAllData - it spreads EQ taint to every map refresh
    -- and gets EQ blamed for the systemic AreaPOI secret-value bug. The events above plus the ticker already cover all changes.
end
