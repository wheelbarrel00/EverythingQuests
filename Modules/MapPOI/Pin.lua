local _, ns = ...
local L = ns.L

EQQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = EQQuestPinMixin

local ICON_QUEST_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_QUEST_TURNIN    = "Interface\\GossipFrame\\ActiveQuestIcon"

-- Named for the minimap so a missing kind cannot pass as a working available pin.
ns.QUEST_PIN_AVAILABLE_ICON = ICON_QUEST_AVAILABLE

-- EQ's own art, as SetTexture fails silently on a path a flavor lacks. skull.tga stays the nameplate's alone
local MEDIA = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\"
local KIND_ICON = {
    [1] = MEDIA .. "slay.tga",
    [2] = MEDIA .. "object.tga",
    [3] = MEDIA .. "loot.tga",
}
local ICON_ENTRANCE = MEDIA .. "entrance.tga"

-- SetAtlas raises on an unknown name and would cost the whole pin, so the atlas is checked once
local RING_ATLAS = "worldquest-emissary-ring"
local _ringAtlas

function ns.QuestPinTexture(isComplete, kind)
    if isComplete then return ICON_QUEST_TURNIN end
    if kind and ns.QuestIsEntrance and ns.QuestIsEntrance(kind) then return ICON_ENTRANCE end
    return (kind and KIND_ICON[ns.QuestRealKind and ns.QuestRealKind(kind) or kind])
           or ICON_QUEST_AVAILABLE
end

local AVAILABLE_RING = { 1.0, 0.82, 0.0 }
local OWNED_RING     = { 0.635, 0.0, 0.039 }

-- The minimap draws no ring, so only this tint tells an available "!" from a carried quest's fallback "!"
function ns.QuestPinAvailableTint()
    return AVAILABLE_RING[1], AVAILABLE_RING[2], AVAILABLE_RING[3], 1
end

-- Blue only for a finished quest handed in inside an instance. The white resets a pooled minimap texture
local ENTRANCE_TINT = { 0.45, 0.7, 1.0 }
function ns.QuestPinTint(kind, isComplete)
    if isComplete and ns.QuestIsEntrance and ns.QuestIsEntrance(kind) then
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

-- By Enum.UIMapType (0 Cosmic, 1 World, 2 Continent), never zoom, as the pin is one size at every zoom
local MAP_TYPE_SCALE = { [0] = 0.85, [1] = 0.85, [2] = 0.9 }

-- Cached per map, because a map's type never changes and this runs for every pin acquired
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

-- Unset is ON on retail and OFF on Classic's crowded maps. Read off the flag, as the spawn table is built lazily
local function ownedRingDefault()
    return not ns.HAS_CLASSIC_SPAWNS
end

-- The options checkbox asks this too, so the box and the pin cannot disagree about an unset value
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

-- Only reached without C_SuperTrack. QuestArrow owns the one TomTom slot the tracker's focus shares
local function tomtomFocus(pin)
    local Arrow = ns:GetSubsystem("QuestArrow")
    -- Before the cache lookup, which can force a full quest log refresh for an arrow that cannot be drawn
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

-- Era lacks QUEST_PING and answers 2000 for it, under its own map layers, so the level is resolved per client
local FRAME_LEVEL_PREFERENCE = {
    "PIN_FRAME_LEVEL_QUEST_PING",
    "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST",
    "PIN_FRAME_LEVEL_ACTIVE_QUEST",
    "PIN_FRAME_LEVEL_AREA_POI",
}

local _levelType, _level, _resolved

-- On WorldMapFrame, not the GetCanvas() child, where it reads nil on every flavor
local function frameLevelManager(map)
    if type(map) ~= "table" then return nil end
    local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
                or map.pinFrameLevelsManager
    if type(mgr) ~= "table" or type(mgr.GetValidFrameLevel) ~= "function" then return nil end
    return mgr
end

-- Defers on the first preference only. Era defines SUPER_TRACKED_QUEST at 2750, under AREA_POI_BANNER at 2757
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

    -- One above the highest defined level, the lowest that clears every layer
    local highest
    for name in pairs(defined) do
        local ok, lvl = pcall(mgr.GetValidFrameLevel, mgr, name)
        if ok and type(lvl) == "number" and (not highest or lvl > highest) then
            highest = lvl
        end
    end
    return chosen, highest and (highest + 1) or nil, false
end

-- Only when the manager cannot be read at all, and above Era's highest definition
local FALLBACK_LEVEL = 2800
ns.MAPPOI_FALLBACK_LEVEL = FALLBACK_LEVEL

-- Overridden, as AcquirePin calls this after OnAcquired and would undo a level set there
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
    -- Read back by /eqsprobe to tell an override that never ran from one that was overwritten
    self.eqWantedLevel = _level
    self:SetFrameLevel(_level)
end

function Pin:OnLoad()
    -- Marks an EQ pin for /eqsprobe, since eqWantedLevel is nil wherever EQ defers the level
    self.eqPin = true
    self:UseFrameLevelType(FRAME_LEVEL_PREFERENCE[1])
    self:SetScalingLimits(1, 1, 1)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

-- In pin widths, not map units, so the fade reach stays one screen distance at any zoom
local FADE_RADIUS_PINS = 1.5
local FADE_ALPHA       = 0.3
local FADE_PERIOD      = 0.15
ns.MAPPOI_FADE_RADIUS_PINS = FADE_RADIUS_PINS

-- Pins record themselves, as Era has only EnumerateAllPins and retail only ExecuteOnAllPins
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

-- Every unreadable case restores full alpha, because a pin stuck dimmed reads as broken art
local function applyPlayerFade()
    if not fadeWanted() then clearFade() return 0 end

    local anyPin = next(_live)
    if not anyPin then _fadedN = 0 return 0 end

    local map    = anyPin.GetMap and anyPin:GetMap()
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if type(canvas) ~= "table" or type(canvas.GetWidth) ~= "function" then clearFade() return 0 end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not (cw and ch) or cw <= 0 or ch <= 0 then clearFade() return 0 end

    -- The pins' own map, which answers nil once scrolled away. An if, as `fn and fn(id)` would drop py
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
            -- Canvas units per axis, so the reach is a circle on screen
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

-- For /eqsprobe mappoi, since a fade switched off and one that found nothing draw the same map
function ns.QuestPinFadeState()
    local live = 0
    for _ in pairs(_live) do live = live + 1 end
    return fadeWanted(), _fadedN, live
end

local function startFadeTicker()
    if _fadeTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    _fadeTicker = C_Timer.NewTicker(FADE_PERIOD, function()
        -- Cancels itself on an empty pool rather than hooking the map, so it cannot outlive the pins
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
    self.srcID      = srcID
    self.mapX, self.mapY, self.mapID = x, y, mapID
    self:SetPosition(x, y)

    -- Equal limits on purpose, as ApplyCurrentScale lerps between them. Set per acquire for pooled pins
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
    if avail then
        self.icon:SetTexture(ICON_QUEST_AVAILABLE)
        self.icon:SetVertexColor(1, 1, 1, 1)
    else
        self.icon:SetTexture(ns.QuestPinTexture(isComplete, kind))
        self.icon:SetVertexColor(ns.QuestPinTint(kind, isComplete))
    end
    self.numberText:SetText("")

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

-- In pin widths, so the tooltip reach stays one screen distance at any zoom
local TOOLTIP_RADIUS_PINS = 1.0
ns.MAPPOI_TOOLTIP_RADIUS_PINS = TOOLTIP_RADIUS_PINS

-- Beyond this many neighboring quests the tooltip is taller than it is useful.
local TOOLTIP_MAX_EXTRA = 4

local _nearQ, _nearD, _nearMin, _nearAt, _nearIdx = {}, {}, {}, {}, {}

-- Compared in canvas units, because the canvas is wider than it is tall
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
    -- An available pin is keyed by its quest list, since two givers can share a first quest
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

    -- One entry per key, a handful of rows, so sorted by insertion rather than table.sort
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

-- The client can finish every objective without flagging the quest, and a delivery has none to judge
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

    -- From the Cache only, as Classic's reward call reads the selected log entry and a hover must not move it
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

-- A single giver can offer over twenty quests, which uncapped outgrows the screen
local TOOLTIP_MAX_AT_LOCATION = 5

-- A start source kind (1 NPC, 2 object, 3 item), not an objective kind from QUEST_KIND_TYPE
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
    -- A bare proper noun needs no key. startKind picks the id space, so it must travel with startSrc
    local giver = ns.Compat.SourceName(quests.startKind, quests.startSrc)
    if giver then tip:AddLine(giver, 0.85, 0.85, 0.85) end
end

-- Shared by both maps and neighbor lines, so one pin is always described the same way
function ns.QuestPinOwned(tip, q, kind, objMask, srcID)
    local taker = ns.Compat.SourceName(kind, srcID)
    if taker then tip:AddLine(taker, 0.85, 0.85, 0.85) end
    ns.QuestPinObjectives(tip, q, kind, objMask)
end

local _partySlots = {}
-- Called for the hovered quest only, since neighbors' lines would outgrow the screen in a full group
function ns.QuestPinParty(tip, questID, kind, objMask)
    local D = ns:GetSubsystem("GroupData")
    if not (D and D.Progress and questID) then return 0 end
    local typeChar, slots
    local t = kind and objMask and objMask > 0 and ns.QUEST_KIND_TYPE
              and ns.QUEST_KIND_TYPE[ns.QuestRealKind(kind)]
    if t then
        typeChar = t:sub(1, 1)
        wipe(_partySlots)
        local rest, i = objMask, 0
        while rest > 0 do
            if rest % 2 == 1 then _partySlots[i] = true end
            rest, i = math.floor(rest / 2), i + 1
        end
        slots = _partySlots
    end
    local rows, n = D:Progress(questID, typeChar, slots)
    return ns.Util.AddPartyLines(tip, rows, n, typeChar == nil)
end

-- Kept out of the shared builders, as a minimap pin or a neighbor line cannot take the right-click
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
        ns.QuestPinParty(tip, self.questID, self.kind, self.objMask)
    end

    local Provider = ns:GetSubsystem("MapPOIProvider")
    local n = nearbyQuests(self)

    -- Counted up front over drawable neighbors only, so the overflow number stays true
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
    if button ~= "RightButton" then
        local QLink = ns:GetSubsystem("QuestLink")
        if QLink and QLink:WantsShare() and QLink:Share(self.questID) then return end
    end
    if button == "RightButton" then
        -- A quest you have not accepted has no log entry, so the browser takes the click
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
