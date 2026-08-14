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

-- The client ships its own localized one-letter time abbreviations, so these need no locale key
-- and come out right in every client language rather than only the four EQ ships. Korean renders
-- them as a full word, which is why a hardcoded "d" was unreadable there.
-- Decimal 30 is octal 36 and hex 1e, so a string that mangles the conversion cannot reproduce
-- these digits. Checking the caller's own number instead would pass "1005ff" for 5, because
-- octal and decimal agree below 8.
local ABBR_CONTROL = 30
local abbrUsable = {}

local function timeAbbr(globalName, fallback, n)
    local fmt = _G[globalName]
    if type(fmt) == "string" then
        local usable = abbrUsable[globalName]
        if usable == nil then
            -- pcall only catches a RAISE, and a locale carrying a stray percent formats without
            -- raising - "100% off" reads its "% o" as an octal conversion and turns 30 into 10036ff.
            local ok, probe = pcall(string.format, fmt, ABBR_CONTROL)
            usable = ok and type(probe) == "string"
                     and probe:find(tostring(ABBR_CONTROL), 1, true) ~= nil
            abbrUsable[globalName] = usable
        end
        if usable then
            local ok, s = pcall(string.format, fmt, n)
            if ok and type(s) == "string" then return s end
        end
    end
    return fallback:format(n)
end

-- English ships "%d d", so without stripping the space between number and unit EQ's "30m"
-- silently became "30 m".
local function timeAbbrTight(globalName, fallback, n)
    return (timeAbbr(globalName, fallback, n):gsub("(%d)%s+(%a)", "%1%2"))
end

function Util.FmtDuration(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return timeAbbrTight("HOUR_ONELETTER_ABBR", "%dh", h) .. " "
               .. timeAbbrTight("MINUTE_ONELETTER_ABBR", "%dm", m)
    end
    if m > 0 then return timeAbbrTight("MINUTE_ONELETTER_ABBR", "%dm", m) end
    return timeAbbrTight("SECOND_ONELETTER_ABBR", "%ds", secs)
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
    if mins < 60   then return timeAbbrTight("MINUTE_ONELETTER_ABBR", "%dm", mins) end
    if mins < 1440 then return timeAbbrTight("HOUR_ONELETTER_ABBR", "%dh", math.floor(mins / 60)) end
    return timeAbbrTight("DAY_ONELETTER_ABBR", "%dd", math.floor(mins / 1440))
end

function Util.WQTimeLong(mins)
    if not mins or mins <= 0 then return ns.L["Expired"] end
    local h = math.floor(mins / 60)
    local m = mins - h * 60
    if h > 0 then
        return timeAbbrTight("HOUR_ONELETTER_ABBR", "%dh", h) .. " "
               .. timeAbbrTight("MINUTE_ONELETTER_ABBR", "%dm", m)
    end
    return timeAbbrTight("MINUTE_ONELETTER_ABBR", "%dm", m)
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
