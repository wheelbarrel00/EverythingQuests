local _, ns = ...

local M = ns:RegisterSubsystem("MinimapQuestPins", {})

-- HereBeDragons tracks icons per owner, so this string is what lets RemoveAllMinimapIcons drop
-- EQ's without touching another addon's.
local REF = "EverythingQuests"

local ICON_SIZE = 12

-- Gated on the library's own presence, never a build number. Only the flavor TOCs list
-- HereBeDragons, so this is inert on retail, where EQ stays off the real WorldMapFrame.
local function lib()
    return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local _pool, _active = {}, {}

local function acquire()
    local f = tremove(_pool)
    if not f then
        f = CreateFrame("Frame", nil, _G.Minimap)
        f:SetSize(ICON_SIZE, ICON_SIZE)
        -- Hover only. A mouse enabled frame over the minimap eats the click underneath it, which
        -- would cost the tracking menu and the ping wherever a pin sits. SetMouseClickEnabled
        -- keeps the tooltip and lets clicks through. Without it, take no mouse at all rather
        -- than break the minimap.
        if f.SetMouseClickEnabled then
            f:EnableMouse(true)
            f:SetMouseClickEnabled(false)
        end
        f.texture = f:CreateTexture(nil, "OVERLAY")
        f.texture:SetAllPoints()
        f:SetScript("OnEnter", function(self)
            if not self.questID then return end
            local Cache = ns:GetSubsystem("Cache")
            local q = Cache and Cache:Get(self.questID)
            if not q then return end
            local tip = ns.Util.PinTooltip()
            tip:SetOwner(self, "ANCHOR_LEFT")
            tip:SetText(q.title or ("Quest #" .. tostring(self.questID)), 1.0, 0.82, 0.0, 1, true)
            -- Shared with the world map pin, so the two never name a location differently
            ns.QuestPinObjectives(tip, q, self.kind, self.objMask)
            tip:Show()
        end)
        f:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)
    end
    _active[#_active + 1] = f
    return f
end

-- Read by /eqsprobe minimap. "Registered 0" and "registered 200 that HBD refused" look identical
-- from the minimap itself, and they have completely different causes.
M._registered, M._rejected, M._mapID, M._stage = 0, 0, nil, "never ran"

local function releaseAll()
    local HBDP = lib()
    if HBDP then HBDP:RemoveAllMinimapIcons(REF) end
    for i = #_active, 1, -1 do
        local f = _active[i]
        f.questID, f.kind, f.objMask = nil, nil, nil
        f:Hide()
        _active[i] = nil
        _pool[#_pool + 1] = f
    end
    M._registered, M._rejected = 0, 0
end

function M:Rebuild()
    releaseAll()

    local HBDP = lib()
    if not HBDP then M._stage = "HereBeDragons not loaded on this flavor" return end

    -- Compared against false, not tested for truthiness, so a profile that predates this default
    -- reads as ON - which is what the options checkbox shows for the same nil.
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.map and DB.db.profile.map.showMinimapPins == false then
        M._stage = "off in options"
        return
    end

    -- The player's zone, NOT the open world map. These two disagree the moment you scroll the
    -- map to somewhere else, and the minimap must follow the player.
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then M._stage = "no map for player" return end
    M._stage, M._mapID = "ran", mapID

    local Provider = ns:GetSubsystem("MapPOIProvider")
    local Cache = ns:GetSubsystem("Cache")
    if not (Provider and Provider.PointsFor and Cache) then
        M._stage = "MapPOI provider absent"
        return
    end

    for qid, q in pairs(Cache:All()) do
        local n = Provider:PointsFor(qid, mapID, q)
        for i = 1, n do
            local x, y = Provider._ptX[i], Provider._ptY[i]
            local f = acquire()
            f.questID, f.kind, f.objMask = qid, Provider._ptKind[i], Provider._ptMask[i]
            f.texture:SetTexture(ns.QuestPinTexture(q.isComplete, f.kind))
            f.texture:SetVertexColor(ns.QuestPinTint(f.kind))
            -- Answers false rather than raising when HereBeDragons has no world size for the
            -- map. Counted so the probe can tell that apart from "no quests here".
            if HBDP:AddMinimapIconMap(REF, f, mapID, x, y, false, false) then
                M._registered = M._registered + 1
            else
                M._rejected = M._rejected + 1
                f:Hide()
            end
        end
    end
end

function M:OnEnable()
    if not lib() then return end
    local Events = ns:GetSubsystem("Events")

    local function refresh()
        if self._pending then return end
        self._pending = true
        C_Timer.After(0.2, function()
            self._pending = false
            self:Rebuild()
        end)
    end

    Events:On("PLAYER_ENTERING_WORLD", refresh)
    Events:On("ZONE_CHANGED_NEW_AREA", refresh)
    Events:On("QUEST_LOG_UPDATE",      refresh)
    Events:On("QUEST_ACCEPTED",        refresh)
    Events:On("QUEST_REMOVED",         refresh)
    Events:On("QUEST_TURNED_IN",       refresh)
end
