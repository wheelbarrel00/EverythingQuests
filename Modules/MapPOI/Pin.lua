local _, ns = ...
local L = ns.L

EQQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQQuestPinMixin

local ICON_QUEST_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_QUEST_TURNIN    = "Interface\\GossipFrame\\ActiveQuestIcon"

function Pin:OnLoad()
    -- QUEST_PING is the highest standard pin tier - a lower tier puts our pins under Blizzard's and they never see a click
    self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_PING")
    self:SetScalingLimits(1, 0.6, 1.4)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

function Pin:OnAcquired(questID, x, y, isComplete)
    self.questID    = questID
    self.isComplete = isComplete
    self:SetPosition(x, y)

    if self.ring then
        self.ring:SetAtlas("worldquest-emissary-ring")
        self.ring:SetVertexColor(0.635, 0.0, 0.039, 1)           -- #a2000a
    end
    self.icon:SetTexture(isComplete and ICON_QUEST_TURNIN or ICON_QUEST_AVAILABLE)
    self.icon:SetVertexColor(1, 1, 1, 1)
    self.numberText:SetText("")

    -- AcquirePin does not auto-Show
    self:Show()
end

function Pin:OnReleased()
    self.questID, self.isComplete = nil, nil
    self.icon:SetTexture(nil)
    self.numberText:SetText("")
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache:Get(self.questID)
    if not q then return end

    -- Private tooltip, not GameTooltip - sharing GameTooltip seeds our taint onto it and the next AreaPOI tooltip crashes on it
    local tip = ns.Util.PinTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetText(q.title or ("Quest #" .. tostring(self.questID)),
                        1.0, 0.82, 0.0, 1, true)
    if q.zone   then tip:AddLine(q.zone, 0.7, 0.7, 0.7) end
    if q.isComplete then
        tip:AddLine(L["Ready to turn in"], 0.4, 0.85, 0.4)
    else
        local objs = q.objectives
        if objs then
            for i = 1, #objs do
                local o = objs[i]
                if not o.finished then
                    tip:AddLine("- " .. (o.text or ""), 0.95, 0.95, 0.95, true)
                end
            end
        end
    end
    tip:Show()
end

function Pin:OnMouseLeave()
    ns.Util.PinTooltip():Hide()
end

-- Required stub - MapCanvas calls this on every pin and asserts if the method is missing
function Pin:CheckMouseButtonPassthrough()
end

function Pin:OnClick(button)
    if not self.questID then return end
    if button == "RightButton" then
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_QuestLog")
        end
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(self.questID)
        elseif ToggleQuestLog then
            ToggleQuestLog()
        end
    else
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
        end
    end
end
