local _, _ns = ...
local L = _ns.L

EQWorldQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQWorldQuestPinMixin

local RING_COLORS = {
    gold     = { 1.00, 0.82, 0.00 },
    gear     = { 0.00, 0.44, 0.87 },
    rep      = { 0.78, 0.40, 0.78 },
    resource = { 0.40, 0.85, 0.40 },
    ap       = { 0.90, 0.45, 0.10 },
    profession = { 0.65, 0.65, 0.40 },
    pvp      = { 0.85, 0.20, 0.20 },
    pet      = { 0.50, 0.85, 0.85 },
    other    = { 0.70, 0.70, 0.70 },
}

local Util = _ns.Util

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_PING")
    self:SetScalingLimits(1, 0.6, 1.4)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

-- Required empty stub - the canvas calls this on every pin and its absence trips the assert at MapCanvas.lua:280
function Pin:CheckMouseButtonPassthrough() end

function Pin:OnAcquired(questID, x, y, reward)
    self.questID = questID
    self.reward  = reward
    self:SetPosition(x, y)

    local DB = _ns:GetSubsystem("DB")
    if DB and DB.db.profile.worldQuests and DB.db.profile.worldQuests.pinScale then
        local s = math.max(0.5, math.min(2.0, DB.db.profile.worldQuests.pinScale))
        self:SetScale(s)
    end

    self.ring:SetAtlas("worldquest-emissary-ring")

    local Rewards = _ns:GetSubsystem("WQRewards")
    if Rewards and Rewards.ApplyToTexture then
        Rewards:ApplyToTexture(self.icon, reward)
    end

    local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                 and C_TaskQuest.GetQuestTimeLeftMinutes(questID)
    self.timeText:SetText(Util.WQTimeShort(mins))
    self.timeText:SetTextColor(Util.WQTimeColor(mins))

    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0
    self:UpdateSelectionVisual(questID == superID)

    self:Show()
end

function Pin:UpdateSelectionVisual(isSelected)
    self.isSelected = isSelected
    if isSelected then
        self:SetSize(42, 42)
        self.ring:SetSize(42, 42)
        self.icon:SetSize(28, 28)
        self.ring:SetVertexColor(1.00, 1.00, 0.30, 1)
    else
        self:SetSize(34, 34)
        self.ring:SetSize(34, 34)
        self.icon:SetSize(22, 22)
        local rc = (self.reward and RING_COLORS[self.reward.category]) or RING_COLORS.other
        self.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
    end
end

function Pin:OnReleased()
    self.questID, self.reward = nil, nil
    self.icon:SetTexture(nil)
    self.timeText:SetText("")
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local Tooltip = _ns:GetSubsystem("WQTooltip")
    if Tooltip and Tooltip.Show then
        Tooltip:Show(self, self.questID)
    end
end

function Pin:OnMouseLeave()
    local Tooltip = _ns:GetSubsystem("WQTooltip")
    if Tooltip and Tooltip.Hide then
        Tooltip:Hide()
    else
        GameTooltip:Hide()
    end
end

local function pinContextMenu(pin)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local questID = pin.questID
    local Watch = _ns:GetSubsystem("WQWatchPersist")
    local tracked = Watch and Watch.IsTracked and Watch:IsTracked(questID)
    if not tracked and C_QuestLog and C_QuestLog.GetQuestWatchType then
        tracked = C_QuestLog.GetQuestWatchType(questID) ~= nil
    end

    local title = (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
                   and C_TaskQuest.GetQuestInfoByQuestID(questID))
                  or (L["World Quest #"] .. tostring(questID))

    MenuUtil.CreateContextMenu(pin, function(_owner, root)
        root:CreateTitle(title)

        if tracked then
            root:CreateButton(L["Untrack Quest"], function()
                if Watch and Watch.Untrack then Watch:Untrack(questID) end
            end)
        else
            root:CreateButton(L["Track Quest"], function()
                if Watch and Watch.Track then Watch:Track(questID) end
            end)
        end

        root:CreateButton(L["Super-track (follow arrow)"], function()
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(questID)
            end
        end)

        root:CreateButton(L["Search on Wowhead"], function()
            _ns:ShowURL("https://www.wowhead.com/quest=" .. tostring(questID))
        end)

        root:CreateDivider()
        root:CreateButton(L["Cancel"], function() end)
    end)
end

function Pin:OnClick(button)
    if not self.questID then return end
    if button == "RightButton" then
        pinContextMenu(self)
    else
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
        end
        local Watch = _ns:GetSubsystem("WQWatchPersist")
        if Watch and Watch.Track then Watch:Track(self.questID) end
    end
end
