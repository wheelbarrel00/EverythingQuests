local _, ns = ...

local E = ns:RegisterSubsystem("TrackerEndeavors", {})

local HEADER_H     = 18
local LINE_H       = 14
local ROW_GAP      = 2
local LABEL_PAD    = 6
local LINE_INDENT  = 14

E.headerPool   = {}
E.linePool     = {}
E.activeHeaders = {}
E.activeLines   = {}

local function buildHeader(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(HEADER_H)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)
    return r
end

local function buildLine(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(LINE_H)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", LINE_INDENT, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    return r
end

local function acquireHeader(parent)
    return ns.Util.AcquirePooled(E.headerPool, E.activeHeaders, parent, buildHeader)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(E.linePool, E.activeLines, parent, buildLine)
end

local function releaseAll()
    for i = #E.activeHeaders, 1, -1 do
        local r = E.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        E.headerPool[#E.headerPool + 1] = r
        E.activeHeaders[i] = nil
    end
    for i = #E.activeLines, 1, -1 do
        local r = E.activeLines[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        E.linePool[#E.linePool + 1] = r
        E.activeLines[i] = nil
    end
end

local function getTrackedActivities()
    if not (C_PerksActivities and C_PerksActivities.GetTrackedPerksActivities) then return {} end
    local out = {}
    local data = C_PerksActivities.GetTrackedPerksActivities()
    if data and data.trackedIDs then
        for i = 1, #data.trackedIDs do
            out[#out + 1] = data.trackedIDs[i]
        end
    end
    return out
end

function E:Render(content, contentWidth, yStart, collapsed)
    local ids = getTrackedActivities()
    local count = #ids

    releaseAll()

    if collapsed or count == 0 then return 0, count end

    local Media = ns:GetSubsystem("Media")
    local y = yStart
    local shown = 0
    for i = 1, count do
        local info = C_PerksActivities and C_PerksActivities.GetPerksActivityInfo and C_PerksActivities.GetPerksActivityInfo(ids[i])
        if info then
            shown = shown + 1
            local row = acquireHeader(content)
            row:SetWidth(contentWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row.title:SetText(info.activityName or ("Activity #" .. tostring(ids[i])))
            if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
            y = y + HEADER_H + ROW_GAP

            local reqs = info.requirementsList
            if reqs then
                for j = 1, #reqs do
                    local rq = reqs[j]
                    local txt = rq.requirementText or ""
                    local line = "- " .. txt
                    if rq.completed then
                        line = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff40ff40" .. txt .. "|r"
                    else
                        line = "|cff999999" .. line .. "|r"
                    end
                    local lr = acquireLine(content)
                    lr:SetWidth(contentWidth)
                    lr:ClearAllPoints()
                    lr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    lr.text:SetText(line)
                    if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                    y = y + LINE_H + ROW_GAP + ns.Util.LineSpacing()
                end
            end
        end
    end

    return y - yStart, shown
end

function E:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    Events:On("PERKS_ACTIVITY_COMPLETED",            refresh)
    Events:On("PERKS_ACTIVITIES_TRACKED_UPDATED",    refresh)
    Events:On("PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", refresh)
    Events:On("PLAYER_ENTERING_WORLD",               refresh)
end
