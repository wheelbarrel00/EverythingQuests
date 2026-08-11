local _, ns = ...
local L = ns.L

EQQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQQuestPinMixin

local ICON_QUEST_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_QUEST_TURNIN    = "Interface\\GossipFrame\\ActiveQuestIcon"

-- SetTexture fails silently on a missing path, so EQ ships its own art rather than depending on
-- a client texture per flavor. Keys are the generator's kind values, 1=slay 2=object 3=loot.
local MEDIA = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\"
local KIND_ICON = {
    [1] = MEDIA .. "skull.tga",
    [2] = MEDIA .. "object.tga",
    [3] = MEDIA .. "loot.tga",
}

-- SetAtlas raises on a name the client does not know, which would cost the whole pin, so this
-- world quest atlas is resolved through GetAtlasInfo once.
local RING_ATLAS = "worldquest-emissary-ring"
local _ringAtlas

-- Shared with the minimap pins, so a symbol never means one thing on the world map and
-- another on the minimap.
function ns.QuestPinTexture(isComplete, kind)
    return (isComplete and ICON_QUEST_TURNIN)
           or (kind and KIND_ICON[ns.QuestRealKind and ns.QuestRealKind(kind) or kind])
           or ICON_QUEST_AVAILABLE
end

-- An entrance pin keeps the objective's own icon but is tinted, so it cannot be read as "the
-- mob is right here".
local ENTRANCE_TINT = { 0.45, 0.7, 1.0 }
function ns.QuestPinTint(kind)
    if ns.QuestIsEntrance and ns.QuestIsEntrance(kind) then
        return ENTRANCE_TINT[1], ENTRANCE_TINT[2], ENTRANCE_TINT[3], 1
    end
    return 1, 1, 1, 1
end

local SCALE_MIN, SCALE_MAX = 0.5, 2.0

local function userScale()
    local DB = ns:GetSubsystem("DB")
    local s = DB and DB.db.profile.map and DB.db.profile.map.pinScale
    if type(s) ~= "number" then return 1 end
    return math.max(SCALE_MIN, math.min(SCALE_MAX, s))
end

local function ringAtlas()
    if _ringAtlas == nil then
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RING_ATLAS)
        _ringAtlas = (info ~= nil) and RING_ATLAS or false
    end
    return _ringAtlas
end

local _lastWaypoint

-- Classic has no Blizzard waypoint of any kind, so TomTom is the only arrow available there.
-- Every call is pcall'd because this reaches into another addon whose API can move.
local function tomtomFocus(pin)
    local TomTom = _G.TomTom
    if not (TomTom and TomTom.AddWaypoint and pin.mapID and pin.mapX and pin.mapY) then
        return false
    end

    -- One at a time, so a click retargets instead of stacking arrows.
    if _lastWaypoint and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, _lastWaypoint)
        _lastWaypoint = nil
    end

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(pin.questID)
    -- persistent, minimap and world are left unset so TomTom's own profile decides them.
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, pin.mapID, pin.mapX, pin.mapY, {
        title = q and q.title or nil,
        from  = "Everything Quests",
        crazy = true,
    })
    if ok then _lastWaypoint = uid end
    return ok
end

-- PIN_FRAME_LEVEL_QUEST_PING is undefined on Era, where GetValidFrameLevel answers 2000 for it
-- and 32 defined types sit above that, so pins draw under the map's own layers. The name is
-- resolved against what the client actually defines instead.
local FRAME_LEVEL_PREFERENCE = {
    "PIN_FRAME_LEVEL_QUEST_PING",
    "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST",
    "PIN_FRAME_LEVEL_ACTIVE_QUEST",
    "PIN_FRAME_LEVEL_AREA_POI",
}

local _levelType, _level, _resolved

-- The manager lives on WorldMapFrame, not on the canvas child GetCanvas() returns, so it is
-- reached through the shadow canvas accessor. Reading canvas.pinFrameLevelsManager finds nil on
-- every flavor and silently disables everything below it.
local function frameLevelManager(map)
    if type(map) ~= "table" then return nil end
    local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
                or map.pinFrameLevelsManager
    if type(mgr) ~= "table" or type(mgr.GetValidFrameLevel) ~= "function" then return nil end
    return mgr
end

-- Returns the chosen type, a level to force, and whether to leave the level to Blizzard.
--
-- Deferral keys on the FIRST preference only, the type Blizzard's own quest pins use. Accepting
-- any defined preference defers on Era, which defines SUPER_TRACKED_QUEST at 2750 while
-- AREA_POI_BANNER sits at 2757 - straight back under the layers that buried the pins.
local function resolveFrameLevel(map)
    local mgr = frameLevelManager(map)
    if not mgr then return FRAME_LEVEL_PREFERENCE[1], nil, false end

    local defined = {}
    local defs = mgr.definitions
    if type(defs) == "table" then
        for k, v in pairs(defs) do
            local name = type(v) == "table" and (v.pinFrameLevelType or v.name) or k
            if name ~= nil then defined[tostring(name)] = true end
        end
    end

    if defined[FRAME_LEVEL_PREFERENCE[1]] then
        return FRAME_LEVEL_PREFERENCE[1], nil, true
    end

    local chosen = FRAME_LEVEL_PREFERENCE[1]
    for i = 2, #FRAME_LEVEL_PREFERENCE do
        if defined[FRAME_LEVEL_PREFERENCE[i]] then chosen = FRAME_LEVEL_PREFERENCE[i] break end
    end

    -- Era defines none of the preferred types, and the fallback its manager returns for an
    -- unknown name is 2000, below 32 of its own 33 definitions. One above the highest is the
    -- only number that clears them all.
    local highest
    for name in pairs(defined) do
        local ok, lvl = pcall(mgr.GetValidFrameLevel, mgr, name)
        if ok and type(lvl) == "number" and (not highest or lvl > highest) then
            highest = lvl
        end
    end
    return chosen, highest and (highest + 1) or nil, false
end

-- Used only when the manager cannot be read at all. One above Era's highest definition.
local FALLBACK_LEVEL = 2800
ns.MAPPOI_FALLBACK_LEVEL = FALLBACK_LEVEL

-- Overrides MapCanvasPinMixin because AcquirePin calls ApplyFrameLevel after OnAcquired returns,
-- which re-derives the level from the type and undoes anything set there.
function Pin:ApplyFrameLevel()
    if not _resolved then
        local forced, typeIsDefined
        _levelType, forced, typeIsDefined = resolveFrameLevel(self.GetMap and self:GetMap())
        _levelType = _levelType or false
        _level = (not typeIsDefined) and (forced or FALLBACK_LEVEL) or nil
        _resolved = true
    end
    -- Nothing to force means the client defines our type and places it correctly itself
    if _level == nil then
        if MapCanvasPinMixin.ApplyFrameLevel then
            MapCanvasPinMixin.ApplyFrameLevel(self)
        end
        self.eqWantedLevel = nil
        return
    end
    -- read back by /eqsprobe, so "our code never ran" and "our value was overwritten" stay
    -- distinguishable instead of both looking like the fallback
    self.eqWantedLevel = _level
    self:SetFrameLevel(_level)
end

function Pin:OnLoad()
    self:UseFrameLevelType(FRAME_LEVEL_PREFERENCE[1])
    self:SetScalingLimits(1, 1, 1)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

function Pin:OnAcquired(questID, x, y, isComplete, mapID, kind, objMask)
    self.questID    = questID
    self.isComplete = isComplete
    self.kind       = kind
    self.objMask    = objMask
    self.mapX, self.mapY, self.mapID = x, y, mapID
    self:SetPosition(x, y)

    -- Both limits are the same value on purpose. ApplyCurrentScale lerps between them, so equal
    -- limits give a fixed size at every zoom. Set per acquire so a pooled pin sees a new setting.
    local s = userScale()
    self:SetScalingLimits(1, s, s)
    if self.ApplyCurrentScale then self:ApplyCurrentScale() end


    self:ApplyFrameLevel()
    if _levelType then self:UseFrameLevelType(_levelType) end

    if self.ring then
        local atlas = ringAtlas()
        if atlas then
            self.ring:SetAtlas(atlas)
            self.ring:SetVertexColor(0.635, 0.0, 0.039, 1)       -- #a2000a
            self.ring:Show()
        else
            self.ring:Hide()
        end
    end
    self.icon:SetTexture(ns.QuestPinTexture(isComplete, kind))
    self.icon:SetVertexColor(ns.QuestPinTint(kind))
    self.numberText:SetText("")

    -- AcquirePin does not auto-Show
    self:Show()
end

function Pin:OnReleased()
    self.questID, self.isComplete, self.kind, self.objMask = nil, nil, nil, nil
    self.mapX, self.mapY, self.mapID = nil, nil, nil
    self.icon:SetTexture(nil)
    self.numberText:SetText("")
end

-- The tooltip's reach, in multiples of the pin's own width. Pin widths rather than map
-- coordinates because the pin counteracts canvas zoom, so this is a constant screen distance.
local TOOLTIP_RADIUS_PINS = 1.0
ns.MAPPOI_TOOLTIP_RADIUS_PINS = TOOLTIP_RADIUS_PINS

-- Beyond this many neighbouring quests the tooltip is taller than it is useful.
local TOOLTIP_MAX_EXTRA = 4

local _nearQ, _nearD, _nearMin, _nearAt, _nearIdx = {}, {}, {}, {}, {}

-- Distances are compared in canvas units, not map coordinates - the canvas is about 1002x668,
-- so the same coordinate delta is half again as much ground in x as in y.
local function nearbyQuests(pin)
    local Provider = ns:GetSubsystem("MapPOIProvider")
    if not (Provider and Provider._drawnN and Provider._drawnN > 0) then return 0 end

    local map    = pin.GetMap and pin:GetMap()
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if type(canvas) ~= "table" or type(canvas.GetWidth) ~= "function" then return 0 end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not (cw and ch) or cw <= 0 or ch <= 0 then return 0 end

    local hx, hy = pin.mapX, pin.mapY
    if not (hx and hy) then return 0 end

    local reach = (pin:GetWidth() or 0) * (pin:GetScale() or 1) * TOOLTIP_RADIUS_PINS
    if reach <= 0 then return 0 end
    local reachSq = reach * reach

    wipe(_nearMin)
    wipe(_nearAt)
    local Q, X, Y = Provider._drawnQ, Provider._drawnX, Provider._drawnY
    for i = 1, Provider._drawnN do
        local qid = Q[i]
        if qid and qid ~= pin.questID then
            local dx, dy = (X[i] - hx) * cw, (Y[i] - hy) * ch
            local d = dx * dx + dy * dy
            if d <= reachSq and (not _nearMin[qid] or d < _nearMin[qid]) then
                _nearMin[qid] = d
                -- which pin won, so its own kind and mask can name the objectives
                _nearAt[qid] = i
            end
        end
    end

    -- A quest contributes at most one entry here, so this list is a handful of rows and never
    -- worth table.sort.
    local n = 0
    for qid, d in pairs(_nearMin) do
        local pos = n + 1
        for i = 1, n do
            if d < _nearD[i] then pos = i break end
        end
        for i = n, pos, -1 do
            _nearQ[i + 1], _nearD[i + 1] = _nearQ[i], _nearD[i]
            _nearIdx[i + 1] = _nearIdx[i]
        end
        _nearQ[pos], _nearD[pos], _nearIdx[pos] = qid, d, _nearAt[qid]
        n = n + 1
    end
    return n
end

-- Exposed so /eqsprobe calls the real aggregation rather than reimplementing it.
function Pin:NearbyQuestCount()
    return nearbyQuests(self)
end

-- A pin names the objectives its own location serves, per the mask, not every unfinished
-- objective on the quest. No mask means fall back to all of them, which is the retail path.
function ns.QuestPinObjectives(tip, q, kind, mask)
    if q.isComplete then
        tip:AddLine(L["Ready to turn in"], 0.4, 0.85, 0.4)
        return
    end
    local objs = q.objectives
    if not objs then return end

    if ns.QuestIsEntrance and ns.QuestIsEntrance(kind) then
        tip:AddLine(L["Dungeon entrance"], 0.5, 0.75, 1.0)
    end

    local wanted
    if mask and mask > 0 and kind then
        local want = ns.QUEST_KIND_TYPE and ns.QUEST_KIND_TYPE[ns.QuestRealKind(kind)]
        local seen = 0
        for i = 1, #objs do
            if objs[i].type == want then
                local bit = 2 ^ seen
                if math.floor(mask / bit) % 2 == 1 then
                    wanted = wanted or {}
                    wanted[i] = true
                end
                seen = seen + 1
            end
        end
    end

    for i = 1, #objs do
        local o = objs[i]
        if not o.finished and (not wanted or wanted[i]) then
            tip:AddLine("- " .. (o.text or ""), 0.95, 0.95, 0.95, true)
        end
    end
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache:Get(self.questID)
    if not q then return end

    -- Private tooltip, not GameTooltip - sharing GameTooltip seeds our taint onto it and the next AreaPOI tooltip crashes on it
    local tip = ns.Util.PinTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetText(q.title or ("Quest #" .. tostring(self.questID)),
                        1.0, 0.82, 0.0, 1, true)
    if q.zone   then tip:AddLine(q.zone, 0.7, 0.7, 0.7) end
    ns.QuestPinObjectives(tip, q, self.kind, self.objMask)

    local Provider = ns:GetSubsystem("MapPOIProvider")
    local n = nearbyQuests(self)
    local shown = 0
    for i = 1, n do
        local other = Cache:Get(_nearQ[i])
        if other then
            if shown >= TOOLTIP_MAX_EXTRA then
                tip:AddLine(" ")
                tip:AddLine((L["and %d more"]):format(n - shown), 0.6, 0.6, 0.6)
                break
            end
            tip:AddLine(" ")
            tip:AddLine(other.title or ("Quest #" .. tostring(_nearQ[i])), 1.0, 0.82, 0.0, true)
            local at = _nearIdx[i]
            ns.QuestPinObjectives(tip, other,
                                  at and Provider._drawnK[at], at and Provider._drawnM[at])
            shown = shown + 1
        end
    end
    tip:Show()
end

function Pin:OnMouseLeave()
    ns.Util.PinTooltip():Hide()
end

-- Required stub - MapCanvas calls this on every pin and asserts if the method is missing
function Pin:CheckMouseButtonPassthrough()
end

function Pin:OnClick(button)
    if not self.questID then return end
    if button == "RightButton" then
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_QuestLog")
        end
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(self.questID)
        elseif ToggleQuestLog then
            ToggleQuestLog()
        end
    else
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
        else
            tomtomFocus(self)
        end
    end
end
