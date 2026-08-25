local _, ns = ...

local DB = ns:RegisterSubsystem("DB", {})

DB.defaults = {
    profile = {
        general = {
            autoAcceptQuests = false,
            autoTurnInQuests = false,
            -- EQ Objective Tracker draws these icons, but EQ owns whether they appear, so
            -- TrackerBridge adds and removes the registration from here.
            showChainGuideIcon = true,
            showEQIcon = true,
            npIconPlacement = "RIGHT",
            npIconSize      = 24,
            npIconTextSize  = 13,
            npIconOffsetX   = 0,
            npIconOffsetY   = 0,
            questTooltips   = true,
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
            showQuestPins    = true,
            showMinimapPins  = true,
            pinScale         = 1.0,
            pinCap           = 50,
            showAvailableQuests = true,
            hideLowLevelQuests  = true,
            -- showPinRing is deliberately absent. AceDB answers the default for an unset key, so
            -- listing one here would hide the nil that Modules/MapPOI/Pin.lua needs to tell
            -- "never chosen" apart from "switched off", and retail would lose its ring.
            showAvailableRing   = false,
            hideOutOfSeasonQuests = true,
            hideHighLevelQuests  = false,
            hideDungeonQuests    = false,
            hideRepeatableQuests = false,
            hideProfessionQuests = false,
            onlyTrackedPins      = false,
            fadePinsOverPlayer   = false,
            showMapCoords        = true,
            showMinimapCoords    = false,
            coordPrecision       = 1,
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
    -- pinned, hidden, collapsedHeaders, trackerCollapsed and zoneProgress are dropped from the
    -- defaults but must stay in the saved variable - EQOT's one-time import still reads them.
    char = {
        trackedWorldQuests = {},
        trackedChainID = nil,
        minimap = { hide = false, minimapPos = 220 },
        lastOptionsTab = "general",
    },
}


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

    -- showChainGuideIcon moved from profile.tracker to profile.general when the tracker left.
    -- Carried across by hand, or anyone who had turned the icon off gets it back silently.
    local p = self.db and self.db.profile
    if p and p.tracker and p.tracker.showChainGuideIcon ~= nil
       and p.general.showChainGuideIcon == nil then
        p.general.showChainGuideIcon = p.tracker.showChainGuideIcon
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
