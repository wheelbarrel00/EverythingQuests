local _, ns = ...
local L = ns.L

EQChainPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQChainPinMixin

local ICON_QUEST  = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_DONE   = "Interface\\RaidFrame\\ReadyCheck-Ready"

local RING = {
    next     = { 1.00, 0.82, 0.00 },
    active   = { 0.30, 0.72, 1.00 },
    complete = { 0.27, 0.85, 0.27 },
    pending  = { 0.55, 0.55, 0.58 },
}
local STATUS_TEXT = {
    next     = L["Your next step"],
    active   = L["On this quest"],
    complete = L["Completed"],
    pending  = L["Comes later in the chain"],
}

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_PING")
    self:SetScalingLimits(1, 0.6, 1.4)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

function Pin:OnAcquired(questID, x, y, status, inLog)
    self.questID = questID
    self.status  = status
    self.inLog   = inLog
    self:SetPosition(x, y)

    local c = RING[status] or RING.pending
    if self.ring then
        self.ring:SetAtlas("worldquest-emissary-ring")
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
    if status == "complete" then
        self.icon:SetTexture(ICON_DONE)
    else
        self.icon:SetTexture(status == "active" and ICON_TURNIN or ICON_QUEST)
    end
    self.icon:SetVertexColor(1, 1, 1, status == "pending" and 0.7 or 1)
    self.numberText:SetText("")
    self:Show()
end

function Pin:OnReleased()
    self.questID, self.status, self.inLog = nil, nil, nil
    self.icon:SetTexture(nil)
    self.numberText:SetText("")
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local tip = ns.Util.PinTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local title = ns.Util.QuestTitle and ns.Util.QuestTitle(self.questID, true)
    tip:SetText(title or ("Quest #" .. tostring(self.questID)), 1.0, 0.82, 0.0, 1, true)
    local txt = STATUS_TEXT[self.status]
    if txt then
        local c = RING[self.status] or RING.pending
        tip:AddLine(txt, c[1], c[2], c[3])
    end
    tip:Show()
end

function Pin:OnMouseLeave()
    ns.Util.PinTooltip():Hide()
end

-- Required empty stub - do not remove (see Modules/MapPOI/Pin.lua)
function Pin:CheckMouseButtonPassthrough()
end

function Pin:OnClick(button)
    if not self.questID then return end
    if button == "RightButton" then
        if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_QuestLog") end
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(self.questID)
        elseif ToggleQuestLog then
            ToggleQuestLog()
        end
    elseif self.inLog and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(self.questID)
    end
end
