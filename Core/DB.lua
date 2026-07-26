local _, ns = ...

local DB = ns:RegisterSubsystem("DB", {})

DB.defaults = {
    profile = {
        general = {
            lockTracker      = false,
            hideInCombat     = false,
            hideInInstances  = false,
            hideOnMapOpen    = false,
            hideInMythicPlus = false,
            autoTrackAccepted = true,
            autoAcceptQuests = false,
            autoTurnInQuests = false,
            restoreSuperTrackOnLogin = true,
            npIconPlacement = "RIGHT",
            npIconSize      = 24,
            npIconTextSize  = 13,
            npIconOffsetX   = 0,
            npIconOffsetY   = 0,
        },
        tracker = {
            anchor = "TOPRIGHT",
            xOffset = -85,
            yOffset = -200,
            width = 305,
            maxHeight = 600,
            scale = 1.0,
            simplifyMode = false,
            simplifyAchievements = false,
            sortMode = "zone",
            manualOrder = {},
            showOnlyWatched = true,
            showBackground = false,
            backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 },
            showBorder = false,
            borderColor = { r = 0.635, g = 0.000, b = 0.039, a = 1 },
            borderSize  = 1,
            font = "GothamXNarrow Black",
            fontSize = 15,
            fontOutline = "OUTLINE",
            titleSizeDelta = 0,
            textShadow      = false,
            textShadowColor = { r = 0, g = 0, b = 0, a = 1 },
            textShadowStrength = 2,
            scenarioTextShadow      = true,
            scenarioTextShadowColor = { r = 0, g = 0, b = 0, a = 1 },
            scenarioTextShadowStrength = 1,
            scenarioTextAlign     = "CENTER",
            scenarioTextSizeDelta = 0,
            scenarioFontSize      = 13,
            colorByDifficulty = true,
            showItemButtons = true,
            showOptionsIcon    = true,
            showChainGuideIcon = true,
            questSoundEnabled = true,
            questCompleteSound = "EQ: Work Complete",
            showLevelInTracker   = false,
            showZoneTag          = false,
            showObjectiveNumbers = true,
            showQuestID          = false,
            showQuestTotal       = true,
            titleColorOverride   = nil,
            titleColorUseClass   = false,
            overrideCompleteGreen = true,
            headerColor          = { r = 0.93, g = 0.32, b = 0.10, a = 1 },
            headerColorUseClass  = false,
            headerDividerColor   = { r = 0.92, g = 0.72, b = 0.02, a = 0.85 },
            headerSizeDelta      = 4,
            headerBar            = false,
            headerBarColor       = { r = 0.80, g = 0.60, b = 0.20, a = 0.85 },
            headerBarHeight      = 22,
            headerBarStyle       = 1,
            headerBarSoftEdges   = false,
            headerBarSoftEdgeStrength = 10,
            blockSpacing         = 2,
            lineSpacing          = 0,
            headerSpacing        = 0,
            blockLayout          = "classic",
            cardColor            = { r = 0.09, g = 0.10, b = 0.12, a = 0.73 },
            cardBorderColor      = { r = 0.00, g = 0.00, b = 0.00, a = 0.45 },
            cardBorderSize       = 1,
            cardPadding          = 6,
            cardTintByType       = false,
            cardTintCampaign     = { r = 0.20, g = 0.14, b = 0.04, a = 0.80 },
            cardTintLegendary    = { r = 0.24, g = 0.12, b = 0.01, a = 0.80 },
            cardTintDungeon      = { r = 0.02, g = 0.11, b = 0.20, a = 0.80 },
            cardTintRaid         = { r = 0.02, g = 0.15, b = 0.03, a = 0.80 },
            scrollBarBg          = true,
            scrollBarBgColor     = { r = 0.60, g = 0.60, b = 0.65, a = 0.25 },
            hideScrollBar        = false,
            skinScrollBar        = false,
            scrollBarThumbColor  = { r = 0.60, g = 0.60, b = 0.65, a = 0.90 },
            scrollBarThumbWidth  = 8,
            hideScrollArrows     = false,
            showQuestPopups      = true,
            showRecentlyAddedTag = true,
            splitQuestClick      = false,
            filters = {
                showNormal      = true,
                showDaily       = true,
                showWeekly      = true,
                showCampaign    = true,
                showWorld       = true,
                onlyCurrentZone = false,
            },
            showProfessionSection = true,
            showAchievementsSection = true,
            showWorldQuestsSection = true,
            sectionOrder = { "zoneprogress", "campaign", "quests", "profession", "endeavors", "achievements" },
            worldQuestsPosition = "bottom",
            showZoneProgressBar = false,
            zoneProgressLocation = "floating",
            zoneProgressBar = {
                point = "CENTER", relPoint = "CENTER", x = 0, y = 220,
                scale = 1.0,
                locked = false,
                showBorder = true,
                showBackground = true,
            },
            scenarioBonusHUD = {
                enabled = false,
                point = "CENTER", relPoint = "CENTER", x = 0, y = -120,
                scale = 1.0,
                locked = false,
                showBorder = true,
                showBackground = true,
            },
            autoListZoneWorldQuests = false,
            worldQuestsPinnedMaxFraction = 0.40,
            worldQuestsHeightOverride = false,
            worldQuestsHeight = 120,
        },
        worldQuests = {
            enabled = true,
            showOnWorldMap = true,
            showOnZoneMap = true,
            popoutOpen = false,
            filters = {
                gold = true, gear = true, rep = true, resource = true,
                ap = true, profession = true, pvp = true, pet = true, other = true,
            },
            factionFilters = {},
            zoneListSort = "time",
            pinScale     = 1.0,
        },
        map = {
            showQuestPins = true,
        },
        history = {
            enabled   = true,
            retention = 5000,
        },
        chainGuide = {
            scale = 1.0,
            showOnLogin = false,
            width = 1160,
            height = 720,
            railCollapsed = false,
            zoneMapIDs = {},
            showUnroutedChains = false,
            showMapPins = true,
        },
        appearance = {
            optionsAlpha = 0.95,
        },
    },
    global = {
        whatsNewSeen = "",
        whatsNewAnnounced = "",
        whatsNewMode = "popup",
        optionsWindowScale = 1.0,
        zoneProgress = {
            qlQuests = {},
            zoneCat = {},
        },
    },
    char = {
        favorites = {},
        pinned = {},
        hidden = {},
        trackedWorldQuests = {},
        collapsedHeaders = {},
        trackerCollapsed = false,
        trackedChainID = nil,
        minimap = { hide = false, minimapPos = 220 },
        lastOptionsTab = "general",
        zoneProgress = {
            questlines = {},
        },
    },
}

local APPEARANCE_KEYS = {
    "font", "fontSize", "fontOutline", "titleSizeDelta",
    "textShadow", "textShadowColor", "textShadowStrength",
    "scenarioTextShadow", "scenarioTextShadowColor", "scenarioTextShadowStrength",
    "scenarioTextAlign", "scenarioTextSizeDelta", "scenarioFontSize",
    "colorByDifficulty", "titleColorOverride", "overrideCompleteGreen", "headerColor",
    "headerDividerColor", "headerSizeDelta",
    "titleColorUseClass", "headerColorUseClass",
    "headerBar", "headerBarColor", "headerBarHeight", "headerBarStyle",
    "headerBarSoftEdges", "headerBarSoftEdgeStrength",
    "blockSpacing", "lineSpacing", "headerSpacing", "scale",
    "blockLayout", "cardColor", "cardBorderColor", "cardBorderSize", "cardPadding",
    "cardTintByType", "cardTintCampaign", "cardTintLegendary", "cardTintDungeon", "cardTintRaid",
    "showBackground", "backgroundColor", "showBorder", "borderColor", "borderSize",
    "scrollBarBg", "scrollBarBgColor", "hideScrollBar", "skinScrollBar",
    "scrollBarThumbColor", "scrollBarThumbWidth", "hideScrollArrows",
}

-- Clearing a key lets AceDB re-apply its default - behavior keys and the zone bar's saved position are left alone by design
function DB:ResetTrackerAppearance()
    local prof = self.db and self.db.profile and self.db.profile.tracker
    if not prof then return end
    for _, k in ipairs(APPEARANCE_KEYS) do prof[k] = nil end
    local zb = prof.zoneProgressBar
    if zb then
        zb.showBackground, zb.showBorder, zb.scale = nil, nil, nil
        zb.borderColor, zb.headerColor, zb.countColor, zb.font = nil, nil, nil, nil
        zb.barTexture, zb.barColor = nil, nil
    end
end

function DB:OnInitialize()
    local AceDB = LibStub("AceDB-3.0")
    self.db = AceDB:New("EverythingQuestsDB", self.defaults, true)
    _G.EverythingQuestsCharDB = _G.EverythingQuestsCharDB or {}
    self.char = _G.EverythingQuestsCharDB
    for k, v in pairs(self.defaults.char) do
        if self.char[k] == nil then
            self.char[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    _G.EverythingQuestsChainCache = _G.EverythingQuestsChainCache or {}
    self.chainCache = _G.EverythingQuestsChainCache
    ns.db = self.db

    local Util = ns.Util
    local t = self.db and self.db.profile and self.db.profile.tracker
    if Util and Util.ReconcileOrder and t then
        t.manualOrder = Util.ReconcileOrder(t.manualOrder)
    end
end

local PRUNE_INTERVAL = 24 * 60 * 60
local RECORD_TTL     = 180 * 24 * 60 * 60
local COORD_TTL      = 90 * 24 * 60 * 60

function DB:MaybePruneChainCache(force)
    local cache = self.chainCache
    if not cache then return 0, 0 end
    local now = time()
    if not force and cache.lastPrune and (now - cache.lastPrune) < PRUNE_INTERVAL then
        return 0, 0
    end

    local nRec, nCoord = 0, 0
    local Chars = ns:GetSubsystem("ChainGuideCharacters")
    if Chars and Chars.PruneStaleRecords then nRec = Chars:PruneStaleRecords(now, RECORD_TTL) or 0 end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.PruneStaleCoords then nCoord = WP:PruneStaleCoords(now, COORD_TTL) or 0 end

    cache.lastPrune = now
    return nRec, nCoord
end

function DB:OnEnable()
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function() self:MaybePruneChainCache() end)
    else
        self:MaybePruneChainCache()
    end
end
