local _, ns = ...

local Util = ns:RegisterSubsystem("Util", {})

Util.color = {
    optionsBg     = { 0.00,  0.00,  0.00,  0.95 },
    tabActive     = { 0.635, 0.000, 0.039, 1.00 },
    tabInactive   = { 0.10,  0.10,  0.10,  0.85 },
    tabText       = { 1.00,  1.00,  1.00,  1.00 },
    brandRed      = { 0.635, 0.000, 0.039, 1.00 },
    headerRed     = { 0.635, 0.000, 0.039, 1.00 },
    buttonYellow  = { 0.92,  0.72,  0.02,  1.00 },
    statYellow    = { 0.92,  0.72,  0.02,  1.00 },
    muted         = { 0.70,  0.70,  0.70,  1.00 },
    dim           = { 0.50,  0.50,  0.50,  1.00 },
}

function Util.LineSpacing()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    return math.max(-8, math.min(24, (cfg and cfg.lineSpacing) or 0))
end

function Util.HeaderSpacing()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    return math.max(-8, math.min(24, (cfg and cfg.headerSpacing) or 0))
end

function Util.FmtDuration(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(secs)
end

function Util.WQTimeColor(mins)
    if not mins or mins <= 0 then return 1.00, 0.10, 0.10 end
    if mins < 30  then return 1.00, 0.25, 0.25 end
    if mins < 120 then return 1.00, 0.65, 0.10 end
    if mins < 720 then return 1.00, 1.00, 0.40 end
    return 0.50, 1.00, 0.50
end

function Util.WQTimeShort(mins)
    if not mins or mins <= 0 then return "" end
    if mins < 60   then return ("%dm"):format(mins) end
    if mins < 1440 then return ("%dh"):format(math.floor(mins / 60)) end
    return ("%dd"):format(math.floor(mins / 1440))
end

function Util.WQTimeLong(mins)
    if not mins or mins <= 0 then return ns.L["Expired"] end
    local h = math.floor(mins / 60)
    local m = mins - h * 60
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

local playerClassColor
function Util.GetPlayerClassColor()
    if playerClassColor == nil then
        local classFile = UnitClass and select(2, UnitClass("player"))
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        playerClassColor = c and { c.r, c.g, c.b } or false
    end
    if playerClassColor then
        return playerClassColor[1], playerClassColor[2], playerClassColor[3]
    end
end

function Util.EffectiveTitleColor(cfg)
    if cfg and cfg.titleColorUseClass then
        local r, g, b = Util.GetPlayerClassColor()
        if r then return r, g, b end
    end
    local ov = cfg and cfg.titleColorOverride
    if ov and ov.r then return ov.r, ov.g, ov.b end
end

function Util.ReconcileOrder(orderMap)
    if type(orderMap) ~= "table" then return {} end
    local list = {}
    for qid, ord in pairs(orderMap) do
        if type(qid) == "number" and type(ord) == "number" then
            list[#list + 1] = { qid, ord }
        end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    local clean = {}
    for i = 1, #list do clean[list[i][1]] = i end
    return clean
end

local function progressRepl(have, need)
    local h, n = tonumber(have), tonumber(need)
    if not (h and n) then return have .. "/" .. need end
    local color
    if h == 0    then color = "|cffff5050"
    elseif h < n then color = "|cffeeaa00"
    else              color = "|cff44ff44"
    end
    return color .. have .. "/" .. need .. "|r"
end

function Util.ColorizeProgress(text)
    if not text or text == "" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", progressRepl))
end

function Util.StripLeadingCount(text)
    return (text:gsub("^%s*%d+%s*/%s*%d+%s*", ""))
end

function Util.QuestTitle(questID, withNumberFallback)
    if questID then
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local t = C_QuestLog.GetTitleForQuestID(questID)
            if t and t ~= "" then return t end
        end
        if QuestUtils_GetQuestName then
            local n = QuestUtils_GetQuestName(questID)
            if n and n ~= "" then return n end
        end
        if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
            local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
            if t and t ~= "" then return t end
        end
        -- Curated names must stay last so a real localized title wins the moment it loads
        if ns.CURATED_QUEST_NAMES then
            local c = ns.CURATED_QUEST_NAMES[questID]
            if c then return c end
        end
    end
    if withNumberFallback then return "Quest #" .. tostring(questID) end
    return nil
end

function Util.AcquirePooled(pool, active, parent, factory)
    local f = tremove(pool)
    if not f then f = factory(parent) end
    f:SetParent(parent)
    f:Show()
    active[#active + 1] = f
    return f
end

-- Private tooltip - taint on the shared GameTooltip crashes the next AreaPOI hover under the secret-value system
local _pinTooltip
function Util.PinTooltip()
    if not _pinTooltip then
        _pinTooltip = CreateFrame("GameTooltip", "EQPinTooltip", UIParent, "GameTooltipTemplate")
    end
    return _pinTooltip
end

ns.Util = Util
