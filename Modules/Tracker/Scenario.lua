local _, ns = ...
local L = ns.L

local S = ns:RegisterSubsystem("TrackerScenario", {})

local SUBHEADER_H      = 26
local CAT_GAP          = 1
local BANNER_GAP       = 6
local CRITERIA_LINE_GAP = 4
local BAR_H            = 16
local BAR_W_RATIO      = 0.85

local HEADER_COLOR   = { 0.93, 0.32, 0.10 }
local CATEGORY_COLOR = { 0.78, 0.78, 0.78 }

S.criteriaPool   = {}
S.activeCriteria = {}

local TEXTURE_KIT_OFFSETS = {
    ["evergreen-scenario"]   = { nx = 0,  ny = 0, fx = -4, fy = 2 },
    ["thewarwithin-scenario"]= { nx = 0,  ny = 0, fx = 3,  fy = -2 },
    ["delves-scenario"]      = { nx = -2, ny = 1, fx = -2, fy = 1 },
}
local DEFAULT_OFFSETS = { nx = 0, ny = 0, fx = -10, fy = 3 }

local function pickAtlases(textureKit)
    local kit = textureKit or "evergreen-scenario"
    local normal = kit .. "-trackerheader"
    local final  = kit .. "-trackerheader-final-filigree"

    local hasNormal = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(normal)
    if not hasNormal then
        normal = "evergreen-scenario-trackerheader"
        final  = "evergreen-scenario-trackerheader-final-filigree"
        kit    = "evergreen-scenario"
    elseif not (C_Texture.GetAtlasInfo(final)) then
        final = nil
    end

    return normal, final, kit
end

local function categoryLabel(scenarioType, textureKit, scenarioName, instType, diffID)
    -- Ritual Sites reuse the Delve scenarioType 8 - only the texture kit separates them
    if scenarioType == 8 then
        if textureKit and textureKit ~= "" and not textureKit:lower():find("delve") then
            return "Ritual Site"
        end
        return "Delves"
    end
    if textureKit and textureKit:lower():find("delve") then return "Delves" end
    if scenarioType == 1 then return "Mythic+" end
    if scenarioType == 5 then return "Dungeon" end
    if scenarioType == 7 then return "Warfront" end
    if scenarioType == 2 then return "Proving Grounds" end

    -- Normal dungeons also report scenarioType 3 - only difficulty 205 means Follower Dungeon
    if diffID == 205 then return "Follower Dungeon" end

    if scenarioName then
        local n = scenarioName:lower()
        if n:find("void incursion") or n:find("void assault") then
            return "Void Incursion"
        end
    end

    if instType == "party"    then return "Dungeon"     end
    if instType == "raid"     then return "Raid"        end
    if instType == "pvp"      then return "Battleground" end
    if instType == "arena"    then return "Arena"       end

    if scenarioName and scenarioName ~= "" then return scenarioName end
    return "Scenario"
end

local function resolveName(scenarioName, instName, instType)
    if instName and instName ~= "" and instType and instType ~= "none" then
        return instName
    end
    if scenarioName and scenarioName ~= "" then return scenarioName end
    return nil
end

-- Unreleased steps can return an internal build string - real criteria never start with a version or carry "- Step NN"
local function looksInternal(s)
    if not s or s == "" then return false end
    if s:find("^%s*%d+%.%d+%.%d+") then return true end
    if s:find("%-%s*Step%s+%d+") then return true end
    if s:find("Scenario%s+%d%d") then return true end
    return false
end

local function buildCriteriaRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BAR_H + 14)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetTextColor(1, 0.82, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(BAR_H)
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(0.26, 0.42, 1.0)

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    row.bar.border = CreateFrame("Frame", nil, row.bar, "BackdropTemplate")
    row.bar.border:SetPoint("TOPLEFT", -1, 1)
    row.bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    row.bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    row.bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    row.bar.label = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bar.label:SetPoint("CENTER", row.bar, "CENTER", 0, 0)

    return row
end

local function acquireCriteria(parent)
    return ns.Util.AcquirePooled(S.criteriaPool, S.activeCriteria, parent, buildCriteriaRow)
end

local function releaseAllCriteria()
    for i = #S.activeCriteria, 1, -1 do
        local row = S.activeCriteria[i]
        row:Hide()
        row:ClearAllPoints()
        row.bar:Hide()
        row.icon:Hide()
        row.icon:ClearAllPoints()
        row.text:ClearAllPoints()
        row.text:SetText("")
        S.criteriaPool[#S.criteriaPool + 1] = row
        S.activeCriteria[i] = nil
    end
end

function S:Build()
    if self.banner then return end
    local Tracker = ns:GetSubsystem("Tracker")
    local container = Tracker and Tracker.frame and Tracker.frame.scenarioContainer
    if not container then return end
    self.frame = container

    local subHeader = CreateFrame("Frame", nil, container)
    subHeader:SetHeight(SUBHEADER_H)
    subHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    subHeader:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    subHeader.cat = subHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subHeader.cat:SetJustifyH("LEFT")
    subHeader.cat:SetTextColor(CATEGORY_COLOR[1], CATEGORY_COLOR[2], CATEGORY_COLOR[3])

    subHeader.text = subHeader:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
    if not subHeader.text:GetFont() then subHeader.text:SetFontObject("GameFontNormalLarge") end
    subHeader.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    local banner = CreateFrame("Frame", nil, container)
    banner:SetPoint("TOP", subHeader, "BOTTOM", 0, -BANNER_GAP)

    banner.NormalBG = banner:CreateTexture(nil, "BACKGROUND")
    banner.ThemeOverlay = banner:CreateTexture(nil, "BACKGROUND", nil, 1)
    banner.ThemeOverlay:SetBlendMode("ADD")
    banner.FinalBG = banner:CreateTexture(nil, "BORDER")

    banner.Stage = banner:CreateFontString(nil, "ARTWORK", "Game18Font")
    banner.Stage:SetSize(172, 18)
    banner.Stage:SetJustifyH("CENTER")
    banner.Stage:SetTextColor(1, 0.914, 0.682)
    -- Banner lines take the separate Scenario shadow settings, applied per-render in Refresh

    banner.Name = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    banner.Name:SetSize(172, 28)
    banner.Name:SetJustifyH("CENTER")
    banner.Name:SetJustifyV("TOP")
    banner.Name:SetSpacing(2)
    banner.Name:SetTextColor(1, 0.831, 0.380)
    banner.Name:SetPoint("TOP", banner.Stage, "BOTTOM", 0, -4)

    banner.Stage._baseFont = { banner.Stage:GetFont() }
    banner.Name._baseFont  = { banner.Name:GetFont() }

    banner.WidgetContainer = CreateFrame("Frame", nil, banner, "UIWidgetContainerTemplate")
    banner.WidgetContainer.verticalAnchorPoint     = "TOP"
    banner.WidgetContainer.verticalRelativePoint   = "TOP"
    banner.WidgetContainer:SetPoint("TOP", banner, "TOP")
    banner.WidgetContainer:Hide()

    self.subHeader = subHeader
    self.banner    = banner
end

function S:ApplyHeaderLabels(scenarioType, textureKit, scenarioName)
    local subHeader = self.subHeader
    local instName, instType, diffID
    if GetInstanceInfo then instName, instType, diffID = GetInstanceInfo() end

    if scenarioType == self._sType and textureKit == self._sKit
       and scenarioName == self._sName and instName == self._sInst then
        return
    end
    self._sType, self._sKit, self._sName, self._sInst =
        scenarioType, textureKit, scenarioName, instName

    local cat     = categoryLabel(scenarioType, textureKit, scenarioName, instType, diffID)
    local name    = resolveName(scenarioName, instName, instType)
    local twoTier = name ~= nil and name:lower() ~= cat:lower()
    local primary = name or cat

    local Media = ns:GetSubsystem("Media")
    subHeader.text:SetText(primary)
    -- +4 mirrors Frame.lua HEADER_FONT_DELTA so this sizes like the section headers
    if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(subHeader.text, 4) end

    if twoTier then
        subHeader.cat:SetText(cat)
        if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(subHeader.cat, -1) end
        subHeader.cat:Show()
        subHeader.cat:ClearAllPoints()
        subHeader.text:ClearAllPoints()
        subHeader.cat:SetPoint("TOPLEFT", subHeader, "TOPLEFT", 8, -1)
        subHeader.text:SetPoint("TOPLEFT", subHeader.cat, "BOTTOMLEFT", 0, -CAT_GAP)
        local h = subHeader.cat:GetStringHeight() + CAT_GAP + subHeader.text:GetStringHeight() + 6
        self.subHeaderH = h
        subHeader:SetHeight(h)
    else
        subHeader.cat:Hide()
        subHeader.text:ClearAllPoints()
        subHeader.text:SetPoint("LEFT", subHeader, "LEFT", 8, 0)
        self.subHeaderH = SUBHEADER_H
        subHeader:SetHeight(SUBHEADER_H)
    end
end

-- ApplyHeaderLabels memoizes on scenario identity, so the font must be re-applied every Refresh
function S:ApplyHeaderFont()
    local subHeader = self.subHeader
    if not subHeader then return end
    local Media = ns:GetSubsystem("Media")
    if not (Media and Media.ApplyTrackerFont) then return end
    Media:ApplyTrackerFont(subHeader.text, 4)
    local h
    if subHeader.cat and subHeader.cat:IsShown() then
        Media:ApplyTrackerFont(subHeader.cat, -1)
        h = subHeader.cat:GetStringHeight() + CAT_GAP + subHeader.text:GetStringHeight() + 6
    else
        h = SUBHEADER_H
    end
    -- Refresh reads subHeaderH for the banner anchor, so keep it in sync after a re-font
    if h ~= self.subHeaderH then
        self.subHeaderH = h
        subHeader:SetHeight(h)
    end
end

function S:ApplyBannerShadow()
    local banner = self.banner
    if not banner then return end
    local M = ns:GetSubsystem("Media")
    if M and M.ApplyScenarioShadow then
        M:ApplyScenarioShadow(banner.Stage)
        M:ApplyScenarioShadow(banner.Name)
    end
end

function S:ApplyBannerFont()
    local banner = self.banner
    if not banner then return end
    local M = ns:GetSubsystem("Media")
    if M and M.ApplyScenarioFont then
        M:ApplyScenarioFont(banner.Stage, banner.Stage._baseFont)
        M:ApplyScenarioFont(banner.Name,  banner.Name._baseFont)
    end
end

function S:_SetContainerHeight(h)
    local container = self.frame
    if not container then return end
    -- Resizing this container moves the secure item buttons anchored below it - blocked in combat
    local IB = ns:GetSubsystem("TrackerItemButtons")
    if InCombatLockdown() and IB and IB.HasSecureButtons and IB:HasSecureButtons() then
        local Ev = ns:GetSubsystem("Events")
        if Ev and Ev.RunWhenOutOfCombat then
            self._deferredRefresh = self._deferredRefresh or function() self:Refresh() end
            Ev:RunWhenOutOfCombat("scenarioRefresh", self._deferredRefresh)
        end
        return
    end
    container:SetHeight(math.max(1, h))
end

function S:Refresh()
    self:Build()
    local container = self.frame
    local banner    = self.banner
    local subHeader = self.subHeader
    if not (container and banner and subHeader) then return end

    local scenarioName, currentStage, numStages, scenarioType, textureKit
    if C_Scenario and C_Scenario.GetInfo then
        scenarioName, currentStage, numStages, _, _, _, _, _, _, scenarioType, _, textureKit = C_Scenario.GetInfo()
    end

    local inScenario = scenarioName and numStages and numStages > 0 and currentStage and currentStage > 0
    if not inScenario then
        releaseAllCriteria()
        subHeader:Hide()
        banner:Hide()
        if banner.WidgetContainer.UnregisterForWidgetSet then
            banner.WidgetContainer:UnregisterForWidgetSet()
        end
        self:_SetContainerHeight(1)
        self._sType, self._sKit, self._sName, self._sInst = nil, nil, nil, nil
        return
    end

    subHeader:Show()
    self:ApplyHeaderLabels(scenarioType, textureKit, scenarioName)
    self:ApplyHeaderFont()
    banner:Show()

    local stageName, numCriteria, widgetSetID
    if C_Scenario.GetStepInfo then
        stageName, _, numCriteria, _, _, _, _, _, _, _, _, widgetSetID = C_Scenario.GetStepInfo()
    end

    local normalAtlas, finalAtlas, resolvedKit = pickAtlases(textureKit)
    local offsets = TEXTURE_KIT_OFFSETS[resolvedKit] or DEFAULT_OFFSETS

    local bw, bh = 201, 83
    banner:SetSize(bw, bh)

    local DB = ns:GetSubsystem("DB")
    local align = (DB and DB.db.profile.tracker.scenarioTextAlign) or "CENTER"
    banner:ClearAllPoints()
    if align == "LEFT" then
        banner:SetPoint("TOPLEFT", subHeader, "BOTTOMLEFT", 0, -BANNER_GAP)
    elseif align == "RIGHT" then
        banner:SetPoint("TOPRIGHT", subHeader, "BOTTOMRIGHT", 0, -BANNER_GAP)
    else
        banner:SetPoint("TOP", subHeader, "BOTTOM", 0, -BANNER_GAP)
    end

    banner.NormalBG:SetAtlas(normalAtlas, true)
    banner.NormalBG:ClearAllPoints()
    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.nx, offsets.ny)
    banner.NormalBG:Show()

    if finalAtlas and currentStage == numStages and numStages > 1 then
        banner.FinalBG:SetAtlas(finalAtlas, true)
        banner.FinalBG:ClearAllPoints()
        banner.FinalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.fx, offsets.fy)
        banner.FinalBG:Show()
    else
        banner.FinalBG:Hide()
    end

    local displayInfo = C_ScenarioInfo and C_ScenarioInfo.GetDisplayInfo and C_ScenarioInfo.GetDisplayInfo()
    if displayInfo and displayInfo.themeColor then
        banner.ThemeOverlay:SetAtlas("themed-scenario-trackerheader-add", true)
        banner.ThemeOverlay:ClearAllPoints()
        banner.ThemeOverlay:SetPoint("BOTTOM", banner.NormalBG, "BOTTOM", 0, 0)
        local r, g, b = displayInfo.themeColor:GetRGB()
        banner.ThemeOverlay:SetVertexColor(r, g, b)
        banner.ThemeOverlay:Show()
    else
        banner.ThemeOverlay:Hide()
    end

    if widgetSetID and widgetSetID > 0 then
        banner.WidgetContainer:RegisterForWidgetSet(widgetSetID)
        banner.WidgetContainer:Show()
        banner.Name:Hide()
        banner.Stage:Hide()
        banner.NormalBG:Hide()
        banner.ThemeOverlay:Hide()
        banner.FinalBG:Hide()
    else
        if banner.WidgetContainer.UnregisterForWidgetSet then
            banner.WidgetContainer:UnregisterForWidgetSet()
        end
        banner.WidgetContainer:Hide()

        banner.Stage:ClearAllPoints()
        banner.Stage:SetPoint("TOP", banner, "TOP", 0, -10)
        if currentStage == numStages and numStages > 1 then
            banner.Stage:SetText(L["Final Stage"])
        elseif numStages > 1 then
            banner.Stage:SetFormattedText(L["Stage %d"], currentStage)
        else
            banner.Stage:SetText("")
        end
        banner.Stage:Show()
        banner.Name:SetText(stageName or "")
        banner.Name:Show()
        self:ApplyBannerFont()
        self:ApplyBannerShadow()
    end

    releaseAllCriteria()
    local Media = ns:GetSubsystem("Media")
    -- Criteria rows center on the container, not the banner - a side-aligned banner would push them off-centre
    local prev = nil
    local firstRowY = (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + bh + CRITERIA_LINE_GAP
    local barWidth = math.floor(container:GetWidth() * BAR_W_RATIO)
    local rowWidth = container:GetWidth() - 16
    for i = 1, (numCriteria or 0) do
        local info = C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo and C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local row = acquireCriteria(container)
            if Media and Media.ApplyScenarioCriteriaFont then
                Media:ApplyScenarioCriteriaFont(row.text)
                Media:ApplyScenarioCriteriaFont(row.bar.label)
            end
            row:ClearAllPoints()
            if prev then
                row:SetPoint("TOP", prev, "BOTTOM", 0, -CRITERIA_LINE_GAP)
            else
                row:SetPoint("TOP", container, "TOP", 0, -firstRowY)
            end

            if info.isWeightedProgress and not info.completed then
                row:SetWidth(barWidth)
                row.icon:Hide()

                local desc = info.description or ""
                local showText = desc ~= "" and not looksInternal(desc)

                local pct = math.max(0, math.min(100, info.quantity or 0))
                row.bar:Show()
                row.bar:ClearAllPoints()
                row.bar:SetWidth(barWidth)
                row.bar:SetValue(pct)
                row.bar.label:SetFormattedText("%d%%", pct)

                row.text:ClearAllPoints()
                if showText then
                    row.text:SetPoint("TOP", row, "TOP", 0, 0)
                    row.text:SetJustifyH("CENTER")
                    row.text:SetText(desc)
                    row.text:SetTextColor(1, 0.82, 0)
                    row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, -2)
                    row:SetHeight(row.text:GetStringHeight() + 2 + BAR_H)
                else
                    row.text:SetText("")
                    row.bar:SetPoint("TOP", row, "TOP", 0, 0)
                    row:SetHeight(BAR_H)
                end
            else
                row:SetWidth(rowWidth)
                row.bar:Hide()

                row.icon:Show()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
                if info.completed then
                    row.icon:SetAtlas("ui-questtracker-tracker-check", false)
                else
                    row.icon:SetAtlas("ui-questtracker-objective-nub", false)
                end

                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.text:SetJustifyH("LEFT")

                local desc = info.description or ""
                local label = desc
                -- Completed criteria drop the X/Y prefix, matching the default tracker
                if not info.isFormatted and not info.completed
                   and info.totalQuantity and info.totalQuantity > 0 then
                    label = ("%d/%d %s"):format(info.quantity or 0, info.totalQuantity, desc)
                end
                row.text:SetText(label)
                if info.completed then
                    row.text:SetTextColor(0.27, 1.0, 0.27)
                else
                    row.text:SetTextColor(0.85, 0.85, 0.85)
                end
                row:SetHeight(math.max(row.text:GetStringHeight(), 14))
            end

            if Media and Media.ApplyTextShadow then
                Media:ApplyTextShadow(row.text)
                Media:ApplyTextShadow(row.bar.label)
            end

            prev = row
        end
    end

    local h = (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + bh
    for i = 1, #self.activeCriteria do
        h = h + CRITERIA_LINE_GAP + self.activeCriteria[i]:GetHeight()
    end
    h = h + 6
    self:_SetContainerHeight(h)
end

local REFRESH_DEBOUNCE = 0.1

function S:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh() self:Refresh() end
    local function queue() Events:Debounce("eq.scenario.refresh", REFRESH_DEBOUNCE, refresh) end

    Events:On("SCENARIO_UPDATE",                  queue)
    Events:On("SCENARIO_CRITERIA_UPDATE",         queue)
    Events:On("SCENARIO_SPELL_UPDATE",            queue)
    Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", queue)
    Events:On("SCENARIO_COMPLETED",               queue)
    Events:On("ACTIVE_DELVE_DATA_UPDATE",         queue)
    Events:On("PLAYER_ENTERING_WORLD",            queue)

    self:Refresh()
end
