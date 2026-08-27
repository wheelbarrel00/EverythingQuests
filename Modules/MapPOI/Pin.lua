local _, ns = ...
local L = ns.L

EQQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQQuestPinMixin

local ICON_QUEST_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_QUEST_TURNIN    = "Interface\\GossipFrame\\ActiveQuestIcon"

-- Named for the minimap so a missing kind cannot pass as a working available pin.
ns.QUEST_PIN_AVAILABLE_ICON = ICON_QUEST_AVAILABLE

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

function ns.QuestPinTexture(isComplete, kind)
    return (isComplete and ICON_QUEST_TURNIN)
           or (kind and KIND_ICON[ns.QuestRealKind and ns.QuestRealKind(kind) or kind])
           or ICON_QUEST_AVAILABLE
end

local AVAILABLE_RING = { 1.0, 0.82, 0.0 }
local OWNED_RING     = { 0.635, 0.0, 0.039 }

-- The minimap draws no ring, so without this an unaccepted quest and a carried one with no
-- spawn row are the same white exclamation mark on the same minimap.
function ns.QuestPinAvailableTint()
    return AVAILABLE_RING[1], AVAILABLE_RING[2], AVAILABLE_RING[3], 1
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

-- Smaller pins on the maps that cover more ground. Keyed on the map's TYPE, never on zoom: the
-- pin is deliberately a fixed size at every zoom level, and the continent map is where that
-- reads worst. Enum.UIMapType - 0 Cosmic, 1 World, 2 Continent. Anything else keeps full size.
local MAP_TYPE_SCALE = { [0] = 0.85, [1] = 0.85, [2] = 0.9 }

-- A map's type never changes, and this is asked once per pin acquired - 333 times on a busy
-- Westfall refresh.
local _typeScale = {}

local function mapTypeScale(mapID)
    if not mapID then return 1 end
    local cached = _typeScale[mapID]
    if cached then return cached end
    local s = 1
    -- GetMapInfo answers nil for a map id the client does not know, so full size is the safe miss.
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" then
            s = MAP_TYPE_SCALE[info.mapType] or 1
        end
    end
    _typeScale[mapID] = s
    return s
end

-- Read by /eqsprobe so it measures the real factor instead of reimplementing it.
ns.MapPinTypeScale = mapTypeScale

local function ringAtlas()
    if _ringAtlas == nil then
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RING_ATLAS)
        _ringAtlas = (info ~= nil) and RING_ATLAS or false
    end
    return _ringAtlas
end

-- Unset has to keep meaning ON or every retail user loses a ring they have always had. Classic
-- ships it off because a zone there draws hundreds of pins. Reads the FLAG, not the table: the
-- table is built on first use, so a nil test would answer retail on Classic until the first draw.
local function ownedRingDefault()
    return not ns.HAS_CLASSIC_SPAWNS
end

-- Read by Options/TabGeneral.lua too. One implementation, or the checkbox and the pin disagree
-- about an unset value while only one of them is on screen.
local function ringWanted(avail)
    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    if avail then
        return (map and map.showAvailableRing) == true
    end
    local v = map and map.showPinRing
    if v == nil then return ownedRingDefault() end
    return v == true
end

ns.QuestPinRingWanted = ringWanted

-- Classic has no Blizzard waypoint of any kind, so TomTom is the only arrow available there.
-- The waypoint slot lives in QuestArrow rather than here so this and the tracker's focused row
-- share one arrow instead of each keeping its own and stacking a second on top of the first.
local function tomtomFocus(pin)
    local Arrow = ns:GetSubsystem("QuestArrow")
    -- Asked before the cache lookup below, which can drive a full quest log refresh. Without
    -- it a player with no TomTom pays for that on every pin click and gets no arrow anyway.
    if not (Arrow and Arrow:Available()) then return false end

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(pin.questID)
    local title = q and q.title
    if not title and pin.avail then
        local Avail = ns:GetSubsystem("AvailableQuests")
        title = Avail and Avail:Title(pin.questID)
    end
    return Arrow:Set(pin.mapID, pin.mapX, pin.mapY, title)
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
    -- Identifies an EQ pin to /eqsprobe on every flavor. eqWantedLevel cannot do it: it is nil
    -- by design wherever EQ defers to the client, which is exactly retail.
    self.eqPin = true
    self:UseFrameLevelType(FRAME_LEVEL_PREFERENCE[1])
    self:SetScalingLimits(1, 1, 1)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

-- Pins sitting on top of the player arrow fade, so a busy zone does not bury where you are.
-- The radius is in PIN WIDTHS like the tooltip reach, not map coordinates - the pin divides out
-- canvas zoom, so this stays a constant SCREEN distance instead of swallowing the map zoomed out.
local FADE_RADIUS_PINS = 1.5
local FADE_ALPHA       = 0.3
local FADE_PERIOD      = 0.15
ns.MAPPOI_FADE_RADIUS_PINS = FADE_RADIUS_PINS

-- No ONE enumeration call works on both: Era has EnumerateAllPins and not ExecuteOnAllPins, retail
-- the reverse. Acquired pins record themselves instead, which needs neither.
local _live = {}
local _fadeTicker, _fadedN = nil, 0

local function fadeWanted()
    local DB = ns:GetSubsystem("DB")
    return (DB and DB.db.profile.map and DB.db.profile.map.fadePinsOverPlayer) == true
end

local function unfade(pin)
    if pin._eqFaded then
        pin:SetAlpha(1)
        pin._eqFaded = nil
    end
end

local function clearFade()
    for pin in pairs(_live) do unfade(pin) end
    _fadedN = 0
end

-- Every unreadable case restores FULL alpha rather than leaving pins dimmed. A pin stuck at 0.3
-- reads as broken art, and unlike a missing pin there is nothing on screen to explain it.
local function applyPlayerFade()
    if not fadeWanted() then clearFade() return 0 end

    local anyPin = next(_live)
    if not anyPin then _fadedN = 0 return 0 end

    local map    = anyPin.GetMap and anyPin:GetMap()
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if type(canvas) ~= "table" or type(canvas.GetWidth) ~= "function" then clearFade() return 0 end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not (cw and ch) or cw <= 0 or ch <= 0 then clearFade() return 0 end

    -- Asked against the map the PINS are drawn on, not C_Map.GetBestMapForUnit. Those disagree the
    -- moment the map is scrolled to another zone, and the player's own coordinates on a zone they
    -- are not standing in would fade an unrelated corner of it. GetPlayerMapPosition answers nil
    -- for a map the player is not on, which is what makes scrolling away simply stop fading.
    -- An if, not `local px, py = fn and fn(id)` - that truncates the pair to one value, so py is
    -- always nil and the fade never fires.
    if not ns.PlayerPositionOn then clearFade() return 0 end
    local px, py = ns.PlayerPositionOn(anyPin.mapID)
    if not (px and py) then clearFade() return 0 end

    local reach = (anyPin:GetWidth() or 0) * (anyPin:GetScale() or 1) * FADE_RADIUS_PINS
    if reach <= 0 then clearFade() return 0 end
    local reachSq = reach * reach

    local faded = 0
    for pin in pairs(_live) do
        local x, y = pin.mapX, pin.mapY
        local near = false
        if x and y then
            -- Canvas units per axis, so the reach is a circle on SCREEN. The canvas is about
            -- 1002x668, so the same coordinate delta is half again as much ground in x.
            local dx, dy = (x - px) * cw, (y - py) * ch
            near = (dx * dx + dy * dy) <= reachSq
        end
        if near then
            if not pin._eqFaded then
                pin:SetAlpha(FADE_ALPHA)
                pin._eqFaded = true
            end
            faded = faded + 1
        else
            unfade(pin)
        end
    end
    _fadedN = faded
    return faded
end

ns.QuestPinApplyFade = applyPlayerFade

-- Read by /eqsprobe mappoi. A fade that is switched off and one that found nothing under the
-- player draw the identical map.
function ns.QuestPinFadeState()
    local live = 0
    for _ in pairs(_live) do live = live + 1 end
    return fadeWanted(), _fadedN, live
end

local function startFadeTicker()
    if _fadeTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    _fadeTicker = C_Timer.NewTicker(FADE_PERIOD, function()
        -- Self-cancelling on an empty pool rather than hooked to the map's show and hide. Re-arming
        -- costs one acquire, and this cannot outlive the pins the way a hook can outlive a frame.
        if not next(_live) then
            if _fadeTicker then _fadeTicker:Cancel() end
            _fadeTicker = nil
            _fadedN = 0
            return
        end
        local wm = _G["WorldMapFrame"]
        if wm and wm.IsShown and not wm:IsShown() then return end
        applyPlayerFade()
    end)
end

function Pin:OnAcquired(questID, x, y, isComplete, mapID, kind, objMask, avail, srcID)
    self.questID    = questID
    self.isComplete = isComplete
    self.kind       = kind
    self.objMask    = objMask
    self.avail      = avail
    -- Only a turn-in point carries one. Assigned unconditionally rather than behind a test, or a
    -- POOLED pin reused for a spawn would keep the previous pin's finisher and name a stranger.
    self.srcID      = srcID
    self.mapX, self.mapY, self.mapID = x, y, mapID
    self:SetPosition(x, y)

    -- Both limits are the same value on purpose. ApplyCurrentScale lerps between them, so equal
    -- limits give a fixed size at every zoom. Set per acquire so a pooled pin sees a new setting,
    -- and so a pin reused on a different map picks up that map's type factor.
    local s = userScale() * mapTypeScale(mapID)
    self:SetScalingLimits(1, s, s)
    if self.ApplyCurrentScale then self:ApplyCurrentScale() end


    self:ApplyFrameLevel()
    if _levelType then self:UseFrameLevelType(_levelType) end

    if self.ring then
        local atlas = ringWanted(avail) and ringAtlas()
        if atlas then
            local c = avail and AVAILABLE_RING or OWNED_RING
            self.ring:SetAtlas(atlas)
            self.ring:SetVertexColor(c[1], c[2], c[3], 1)
            self.ring:Show()
        else
            self.ring:Hide()
        end
    end
    -- An available pin passes no kind, and QuestPinTexture's own fallback for a missing kind is
    -- this same icon, so the two cases would be indistinguishable. Asked for by name instead.
    if avail then
        self.icon:SetTexture(ICON_QUEST_AVAILABLE)
        self.icon:SetVertexColor(1, 1, 1, 1)
    else
        self.icon:SetTexture(ns.QuestPinTexture(isComplete, kind))
        self.icon:SetVertexColor(ns.QuestPinTint(kind))
    end
    self.numberText:SetText("")

    -- A POOLED pin carries the alpha its previous quest ended with, exactly as it carries a stale
    -- ring. Cleared per acquire so a reused pin never starts dimmed on a pin that is nowhere near
    -- the player, and re-evaluated by the ticker on its own schedule.
    unfade(self)
    _live[self] = true
    startFadeTicker()

    -- AcquirePin does not auto-Show
    self:Show()
end

function Pin:OnReleased()
    self.questID, self.isComplete, self.kind, self.objMask = nil, nil, nil, nil
    self.avail, self.srcID = nil, nil
    self.mapX, self.mapY, self.mapID = nil, nil, nil
    _live[self] = nil
    unfade(self)
    self.icon:SetTexture(nil)
    self.numberText:SetText("")
end

-- The tooltip's reach, in multiples of the pin's own width. Pin widths rather than map
-- coordinates because the pin counteracts canvas zoom, so this is a constant screen distance.
local TOOLTIP_RADIUS_PINS = 1.0
ns.MAPPOI_TOOLTIP_RADIUS_PINS = TOOLTIP_RADIUS_PINS

-- Beyond this many neighboring quests the tooltip is taller than it is useful.
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
    local Q, X, Y, A = Provider._drawnQ, Provider._drawnX, Provider._drawnY, Provider._drawnA
    -- An available pin stands for a LOCATION, not a quest, and it is recorded under only the
    -- first of the several quests offered there. Keying those by quest id would collapse two
    -- different givers that happen to share a quest, and silently drop the other givers' quests.
    -- The quest list table is its own identity, so it keys the location exactly.
    local hoveredKey = pin.avail or pin.questID
    for i = 1, Provider._drawnN do
        local key = A[i] or Q[i]
        if key and key ~= hoveredKey then
            local dx, dy = (X[i] - hx) * cw, (Y[i] - hy) * ch
            local d = dx * dx + dy * dy
            if d <= reachSq and (not _nearMin[key] or d < _nearMin[key]) then
                _nearMin[key] = d
                _nearAt[key] = i
            end
        end
    end

    -- Each key contributes at most one entry here, so this list is a handful of rows and never
    -- worth table.sort.
    local n = 0
    for key, d in pairs(_nearMin) do
        local pos = n + 1
        for i = 1, n do
            if d < _nearD[i] then pos = i break end
        end
        for i = n, pos, -1 do
            _nearQ[i + 1], _nearD[i + 1] = _nearQ[i], _nearD[i]
            _nearIdx[i + 1] = _nearIdx[i]
        end
        local at = _nearAt[key]
        _nearQ[pos], _nearD[pos], _nearIdx[pos] = Q[at], d, at
        n = n + 1
    end
    return n
end

-- Exposed so /eqsprobe calls the real aggregation rather than reimplementing it.
function Pin:NearbyQuestCount()
    return nearbyQuests(self)
end

-- The client can report every objective finished without flagging the quest complete, which left
-- the tooltip a bare title. A quest with none at all can only be judged by isComplete - a
-- delivery quest genuinely has zero for its whole life.
function ns.QuestIsDone(q)
    if q.isComplete then return true end
    local objs = q.objectives
    if not objs or #objs == 0 then return false end
    for i = 1, #objs do
        if not objs[i].finished then return false end
    end
    return true
end

function ns.QuestPinTitle(q, questID)
    local title = q and q.title or ("Quest #" .. tostring(questID))
    local level = q and q.level
    if type(level) == "number" and level > 0 then
        return ("[%d] %s"):format(level, title)
    end
    return title
end

function ns.QuestPinObjectives(tip, q, kind, mask)
    local isEntrance = ns.QuestIsEntrance and ns.QuestIsEntrance(kind)

    -- Read from the Cache, never asked for here: on Classic the reward call reports whatever
    -- quest log entry is SELECTED, so fetching it on hover would move the player's quest log.
    if type(q.rewardXP) == "number" and q.rewardXP > 0 then
        local n = BreakUpLargeNumbers and BreakUpLargeNumbers(q.rewardXP) or tostring(q.rewardXP)
        tip:AddLine((L["%s XP"]):format(n), 0.7, 0.7, 0.7)
    end

    if ns.QuestIsDone(q) then
        tip:AddLine(L["Ready to turn in"], 0.4, 0.85, 0.4)
        if isEntrance then tip:AddLine(L["Dungeon entrance"], 0.5, 0.75, 1.0) end
        return
    end
    local objs = q.objectives
    if not objs then return end

    if isEntrance then
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

-- One giver offers up to 27 quests and a faire ground 36, which uncapped is a tooltip taller
-- than the screen.
local TOOLTIP_MAX_AT_LOCATION = 5

-- The start-point kinds the generator emits: 1 an NPC offers it, 2 an object does, 3 an item that
-- starts it drops here. These are SOURCES of a quest, not the objective kinds in QUEST_KIND_TYPE.
local START_ITEM = 3

function ns.QuestPinAvailable(tip, quests, isFirstLine)
    local Avail = ns:GetSubsystem("AvailableQuests")
    if not (Avail and quests) then return end
    local n = #quests
    local shown = (n > TOOLTIP_MAX_AT_LOCATION) and TOOLTIP_MAX_AT_LOCATION or n
    for i = 1, shown do
        local qid = quests[i]
        local title = Avail:Title(qid)
        if i == 1 and isFirstLine then
            tip:SetText(title, 1.0, 0.82, 0.0, 1, true)
        else
            tip:AddLine(title, 1.0, 0.82, 0.0, true)
        end
        local level = Avail:QuestLevel(qid)
        local line = level and (L["Level %d"]):format(level) or L["Available quest"]
        if Avail:IsRepeatable(qid) then
            line = line .. " - " .. L["Repeatable quest"]
        end
        tip:AddLine(line, 0.6, 0.85, 0.6)
    end
    if n > shown then
        tip:AddLine((L["and %d more"]):format(n - shown), 0.6, 0.6, 0.6)
    end
    if quests.startKind == START_ITEM then
        tip:AddLine(L["Starts from an item that drops here"], 0.7, 0.7, 0.7)
    end
    -- Who is standing here. A bare name needs no manifest key and no translation - the pin has
    -- already said what this place is, and a proper noun reads the same in every language.
    -- startKind and startSrc are set together by the provider and must stay that way: the kind
    -- is what picks the id space this name is looked up in.
    local giver = ns.Compat.SourceName(quests.startKind, quests.startSrc)
    if giver then tip:AddLine(giver, 0.85, 0.85, 0.85) end
end

-- The body of an owned pin's tooltip. Shared by the world map, the minimap and a neighbor line,
-- because Provider:PointsFor is already shared so that those three cannot draw different pins -
-- and until this existed they could still describe the same pin differently.
-- The taker's name needs no manifest key: the pin is already the turn-in marker, and a bare
-- proper noun reads the same in every language. Nil on any pin that is not a turn-in.
function ns.QuestPinOwned(tip, q, kind, objMask, srcID)
    local taker = ns.Compat.SourceName(kind, srcID)
    if taker then tip:AddLine(taker, 0.85, 0.85, 0.85) end
    ns.QuestPinObjectives(tip, q, kind, objMask)
end

-- Deliberately NOT part of the builder above. That one is shared with the minimap, whose pins
-- are created click-through on purpose, and with an owned pin merely listing an available
-- neighbor - neither can honor a right-click, so only the caller that can may promise it.
local function addBrowserHint(tip)
    local QB = ns:GetSubsystem("QuestBrowser")
    if QB and QB.Available and QB:Available() then
        tip:AddLine(L["Right-click for quest details"], 0.5, 0.75, 1.0)
    end
end

function Pin:OnMouseEnter()
    if not self.questID then return end
    local Cache = ns:GetSubsystem("Cache")
    local q = (not self.avail) and Cache:Get(self.questID) or nil
    if not (q or self.avail) then return end

    -- Private tooltip, not GameTooltip - sharing GameTooltip seeds our taint onto it and the next AreaPOI tooltip crashes on it
    local tip = ns.Util.PinTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    if self.avail then
        ns.QuestPinAvailable(tip, self.avail, true)
        addBrowserHint(tip)
    else
        tip:SetText(ns.QuestPinTitle(q, self.questID), 1.0, 0.82, 0.0, 1, true)
        if q.zone   then tip:AddLine(q.zone, 0.7, 0.7, 0.7) end
        ns.QuestPinOwned(tip, q, self.kind, self.objMask, self.srcID)
    end

    local Provider = ns:GetSubsystem("MapPOIProvider")
    local n = nearbyQuests(self)

    -- Counted before anything is written, because the overflow line promises a number. Counting
    -- neighbors and then skipping the ones that cannot be rendered makes that number a lie.
    local total = 0
    for i = 1, n do
        local at = _nearIdx[i]
        if (at and Provider._drawnA[at]) or Cache:Get(_nearQ[i]) then total = total + 1 end
    end

    local shown = 0
    for i = 1, n do
        local at = _nearIdx[i]
        local availList = at and Provider._drawnA[at]
        local other = (not availList) and Cache:Get(_nearQ[i]) or nil
        if availList or other then
            if shown >= TOOLTIP_MAX_EXTRA then
                tip:AddLine(" ")
                tip:AddLine((L["and %d more"]):format(total - shown), 0.6, 0.6, 0.6)
                break
            end
            tip:AddLine(" ")
            if availList then
                ns.QuestPinAvailable(tip, availList)
            else
                tip:AddLine(ns.QuestPinTitle(other, _nearQ[i]), 1.0, 0.82, 0.0, true)
                ns.QuestPinOwned(tip, other, Provider._drawnK[at], Provider._drawnM[at],
                                 Provider._drawnS[at])
            end
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
        -- The quest log has no entry to open for a quest you have not accepted, so the browser
        -- takes that click instead - it is the only thing that can describe an unaccepted quest.
        if self.avail then
            local QB = ns:GetSubsystem("QuestBrowser")
            if QB and QB.Available and QB:Available() then QB:Open(self.questID) end
            return
        end
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
