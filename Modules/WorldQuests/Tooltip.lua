local _, ns = ...
local L = ns.L

local T = ns:RegisterSubsystem("WQTooltip", {})

local Util = ns.Util

local function questTitle(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if t and t ~= "" then return t end
    end
    if QuestUtils_GetQuestName then
        local n = QuestUtils_GetQuestName(questID)
        if n and n ~= "" then return n end
    end
    return L["World Quest"]
end

local function factionName(questID)
    local id
    if C_QuestLog and C_QuestLog.GetQuestFactionID then
        id = C_QuestLog.GetQuestFactionID(questID)
    end
    if not id then return nil end
    if C_FactionInfo and C_FactionInfo.GetFactionDataByID then
        local data = C_FactionInfo.GetFactionDataByID(id)
        return data and data.name or nil
    end
    return nil
end

function T:Show(owner, questID)
    if not (owner and questID) then return end
    -- Private tooltip, not the shared GameTooltip: a pin hover leaves taint the next AreaPOI tooltip inherits and crashes on
    local tip = Util.PinTooltip()
    if not tip then return end

    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    tip:SetOwner(owner, "ANCHOR_RIGHT")

    tip:SetText(questTitle(questID), 1.0, 0.82, 0.0, 1, true)

    local fname = factionName(questID)
    if fname then
        tip:AddLine(fname, 0.7, 0.7, 0.7)
    end

    local QR = ns:GetSubsystem("QuestRewards")
    if QR then
        QR:RenderObjectives(tip, questID)
        if QR:RenderRewards(tip, questID) then
            tip:AddLine(" ")
        end
    end

    local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                 and C_TaskQuest.GetQuestTimeLeftMinutes(questID)
    if mins and mins > 0 then
        local r, g, b = Util.WQTimeColor(mins)
        tip:AddLine(L["Time Left: "] .. Util.WQTimeLong(mins), r, g, b)
    end

    tip:Show()
end

function T:Hide()
    local tip = Util.PinTooltip()
    if tip then tip:Hide() end
end
