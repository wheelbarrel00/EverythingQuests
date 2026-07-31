local _, ns = ...

local E = ns:RegisterSubsystem("TrackerEndeavors", {})

local HEADER_H     = 18
local LINE_H       = 14
local ROW_GAP      = 2
local LABEL_PAD    = 6
local LINE_INDENT  = 14

local colorizeProgress = ns.Util.ColorizeProgress

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

    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ovR, ovG, ovB
    if ns.Util and ns.Util.EffectiveTitleColor then ovR, ovG, ovB = ns.Util.EffectiveTitleColor(t) end
    local doneHex = "40ff40"
    if t and t.overrideCompleteGreen ~= false and ovR then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ovR * 255 + 0.5),
            math.floor(ovG * 255 + 0.5),
            math.floor(ovB * 255 + 0.5))
    end

    local Card = ns:GetSubsystem("TrackerCard")
    local cardOn, pad, borderSize = false, 0, 0
    local cardBg, cardBorder
    if Card then
        cardOn, pad, borderSize = Card:State(t)
        cardBg, cardBorder = Card:Colors(t)
    end

    local y = yStart
    local shown = 0
    for i = 1, count do
        local info = C_PerksActivities and C_PerksActivities.GetPerksActivityInfo and C_PerksActivities.GetPerksActivityInfo(ids[i])
        if info then
            shown = shown + 1
            local groupTop = y
            if cardOn then y = y + pad end
            local row = acquireHeader(content)
            row:SetWidth(math.max(1, contentWidth - pad * 2))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
            row.title:SetText(info.activityName or ("Activity #" .. tostring(ids[i])))
            if ovR then
                row.title:SetTextColor(ovR, ovG, ovB)
            else
                row.title:SetTextColor(1.0, 0.82, 0.0)
            end
            if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
            local lastBottom = y + HEADER_H
            y = y + HEADER_H + ROW_GAP

            local reqs = info.requirementsList
            if reqs then
                for j = 1, #reqs do
                    local rq = reqs[j]
                    -- requirementText arrives pre-bulleted, so EQ's own dash doubled it to "- - 1 / 15"
                    local txt = (rq.requirementText or ""):gsub("^%s*%-%s+", "")
                    local line
                    if rq.completed then
                        line = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff" .. doneHex .. txt .. "|r"
                    elseif txt:find("%d+%s*/%s*%d+") then
                        line = "- " .. colorizeProgress(txt)
                    else
                        line = "|cff999999- " .. txt .. "|r"
                    end
                    -- Parented to the header row so the group card draws behind the text, anchored to content so placement is unchanged
                    local lr = acquireLine(row)
                    lr:SetWidth(math.max(1, contentWidth - pad * 2))
                    lr:ClearAllPoints()
                    lr:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
                    lr.text:SetText(line)
                    if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                    lastBottom = y + LINE_H
                    local advance = LINE_H + ROW_GAP + ns.Util.LineSpacing()
                    if cardOn then advance = math.max(advance, LINE_H) end
                    y = y + advance
                end
            end

            if cardOn then
                local groupBottom = lastBottom + pad
                Card:Draw(row, groupBottom - groupTop, pad, borderSize, cardBg, cardBorder)
                y = groupBottom + Card:Gap(ROW_GAP, true)
            elseif Card then
                Card:Clear(row)
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
