local _, ns = ...
local L = ns.L

local A = ns:RegisterSubsystem("TrackerAchievements", {})

local HEADER_H     = 18
local LINE_H       = 14
local ROW_GAP      = 2
local LABEL_PAD    = 6
local LINE_INDENT  = 14
local MAX_CRITERIA = 12

-- GetAchievementCriteriaInfo flags bit 0x1 (EVALUATION_TREE_FLAG_PROGRESS_BAR):
-- progress-bar criteria have an EMPTY criteriaString but real quantity/reqQuantity,
-- so they must be detected via this flag rather than by checking criteriaString.
local PROGRESS_BAR_FLAG = 0x1

A.headerPool    = {}
A.linePool      = {}
A.activeHeaders = {}
A.activeLines   = {}

local ACH_TYPE    = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement)
local STOP_MANUAL = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2

local function headerOnMouseUp(self, button)
    local id = self._achID
    if not id then return end
    if button == "RightButton" then
        if C_ContentTracking and C_ContentTracking.StopTracking and ACH_TYPE then
            C_ContentTracking.StopTracking(ACH_TYPE, id, STOP_MANUAL)
        elseif RemoveTrackedAchievement then
            RemoveTrackedAchievement(id)
        end
    elseif button == "LeftButton" then
        if OpenAchievementFrameToAchievement then
            OpenAchievementFrameToAchievement(id)
        end
    end
end

local function headerOnEnter(self)
    if not self._achID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self._achName then GameTooltip:AddLine(self._achName, 1, 0.82, 0) end
    GameTooltip:AddLine(L["Left-click to open, right-click to untrack."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function headerOnLeave()
    GameTooltip:Hide()
end

local function buildHeader(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(HEADER_H)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", headerOnMouseUp)
    r:SetScript("OnEnter",   headerOnEnter)
    r:SetScript("OnLeave",   headerOnLeave)
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
    return ns.Util.AcquirePooled(A.headerPool, A.activeHeaders, parent, buildHeader)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(A.linePool, A.activeLines, parent, buildLine)
end

local function releaseAll()
    for i = #A.activeHeaders, 1, -1 do
        local r = A.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        r._achID = nil
        r._achName = nil
        A.headerPool[#A.headerPool + 1] = r
        A.activeHeaders[i] = nil
    end
    for i = #A.activeLines, 1, -1 do
        local r = A.activeLines[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        A.linePool[#A.linePool + 1] = r
        A.activeLines[i] = nil
    end
end

local function getTrackedAchievements()
    local out = {}
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs and ACH_TYPE then
        local ids = C_ContentTracking.GetTrackedIDs(ACH_TYPE)
        if ids then
            for i = 1, #ids do
                if ids[i] then out[#out + 1] = ids[i] end
            end
        end
    end
    if #out == 0 and GetTrackedAchievements then
        local t = { GetTrackedAchievements() }
        for i = 1, #t do
            if t[i] and t[i] ~= 0 then out[#out + 1] = t[i] end
        end
    end
    return out
end

local colorizeProgress = ns.Util.ColorizeProgress

function A:Render(content, contentWidth, yStart, collapsed)
    local ids = getTrackedAchievements()
    local count = #ids

    releaseAll()

    if collapsed or count == 0 then return 0, count end
    if not GetAchievementInfo then return 0, 0 end

    local Media = ns:GetSubsystem("Media")

    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ovR, ovG, ovB
    if ns.Util and ns.Util.EffectiveTitleColor then ovR, ovG, ovB = ns.Util.EffectiveTitleColor(t) end
    local simplify = t and t.simplifyAchievements
    local doneHex = "44ff44"
    if t and t.overrideCompleteGreen ~= false and ovR then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ovR * 255 + 0.5),
            math.floor(ovG * 255 + 0.5),
            math.floor(ovB * 255 + 0.5))
    end

    local shownCount = 0
    local y = yStart
    for i = 1, count do
        local id = ids[i]
        local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
        if name then
            shownCount = shownCount + 1
            local row = acquireHeader(content)
            row:SetWidth(contentWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local label = name
            if icon then label = "|T" .. icon .. ":0|t " .. name end
            row.title:SetText(label)
            row._achID   = id
            row._achName = name
            if ovR then
                row.title:SetTextColor(ovR, ovG, ovB)
            else
                row.title:SetTextColor(1.0, 0.82, 0.0)
            end
            if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
            y = y + HEADER_H + ROW_GAP

            local num = (GetAchievementNumCriteria and GetAchievementNumCriteria(id)) or 0
            local shownCrit = 0
            for c = 1, num do
                if shownCrit >= MAX_CRITERIA then break end
                local critString, _, critDone, quantity, reqQuantity, _, critFlags =
                    GetAchievementCriteriaInfo(id, c)
                local hasText      = critString and critString ~= ""
                local isProgressBar = critFlags and bit.band(critFlags, PROGRESS_BAR_FLAG) ~= 0
                local hasMeter      = reqQuantity and reqQuantity > 1
                if (hasText or isProgressBar) and not (simplify and critDone) then
                    local line
                    if critDone then
                        local critLabel = (hasText and critString)
                                       or (hasMeter and (quantity .. "/" .. reqQuantity))
                        if critLabel then
                            line = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff"
                                   .. doneHex .. critLabel .. "|r"
                        end
                    elseif hasMeter then
                        local suffix = hasText and (" " .. critString) or ""
                        line = "- " .. colorizeProgress(quantity .. "/" .. reqQuantity .. suffix)
                    elseif hasText then
                        line = "|cff999999- " .. critString .. "|r"
                    end
                    if line then
                        local lr = acquireLine(content)
                        lr:SetWidth(contentWidth)
                        lr:ClearAllPoints()
                        lr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        lr.text:SetText(line)
                        if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                        shownCrit = shownCrit + 1
                        y = y + LINE_H + ROW_GAP + ns.Util.LineSpacing()
                    end
                end
            end
        end
    end

    return y - yStart, shownCount
end

function A:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    Events:On("TRACKED_ACHIEVEMENT_LIST_CHANGED", refresh)
    Events:On("TRACKED_ACHIEVEMENT_UPDATE",       refresh)
    Events:On("CONTENT_TRACKING_UPDATE",          refresh)
    Events:On("ACHIEVEMENT_EARNED",               refresh)
    Events:On("PLAYER_ENTERING_WORLD",            refresh)
end
