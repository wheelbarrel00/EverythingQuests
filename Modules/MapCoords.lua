local _, ns = ...
local L = ns.L

local M = ns:RegisterSubsystem("MapCoords", {})

-- Fast enough that the cursor readout tracks the mouse rather than trailing it. The player
-- readout costs one call and rides along.
local INTERVAL = 0.05

local FONT_SIZE = 12

local function cfg(key, fallback)
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.map and DB.db.profile.map[key]
    if v == nil then return fallback end
    return v
end

local function mapWanted()    return cfg("showMapCoords", true) == true end
local function minimapWanted() return cfg("showMinimapCoords", false) == true end

local function precision()
    local n = cfg("coordPrecision", 1)
    if type(n) ~= "number" then return 1 end
    return math.max(0, math.min(2, math.floor(n)))
end

-- Built per precision rather than per frame, so the common case is a table lookup
local FORMATS = {}
local function pairFormat()
    local p = precision()
    local f = FORMATS[p]
    if not f then
        f = ("%%.%df, %%.%df"):format(p, p)
        FORMATS[p] = f
    end
    return f
end

-- A font that does not take leaves the FontString BLANK, which is worse than the wrong font, so
-- the result is read back rather than trusting what SetFont returned.
local function applyFont(fs)
    if not (fs.SetFont and fs.GetFont) then return end
    pcall(fs.SetFont, fs, _G["STANDARD_TEXT_FONT"], FONT_SIZE, "OUTLINE")
    local path = fs:GetFont()
    if not path then
        pcall(fs.SetFontObject, fs, _G["GameFontHighlightSmall"])
    end
end

local function newReadout(parent, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameStrata(parent:GetFrameStrata())
    if level then f:SetFrameLevel(level) end
    f:SetSize(1, FONT_SIZE + 2)
    if type(f.CreateFontString) ~= "function" then return nil end
    f.text = f:CreateFontString(nil, "OVERLAY")
    applyFont(f.text)
    f.text:SetPoint("BOTTOMLEFT")
    f.text:SetTextColor(1, 0.82, 0)
    return f
end

local _mapFrame, _minimapFrame

-- Above the quest pins, which force their own level, or the readout draws underneath them.
local READOUT_LEVEL = 3000

local function ensureMapFrame()
    if _mapFrame then return _mapFrame end
    local wmf = _G["WorldMapFrame"]
    if not wmf then return nil end
    -- Parented to the map so it inherits its show state and its scale. This is a plain frame
    -- with no data provider and no script on the map itself - the taint the shadow canvas
    -- exists to avoid comes from AddDataProvider, not from owning a child frame.
    _mapFrame = newReadout(wmf, READOUT_LEVEL)
    if not _mapFrame then return nil end
    local anchor = wmf.ScrollContainer or wmf
    _mapFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 10, 10)
    return _mapFrame
end

local function ensureMinimapFrame()
    if _minimapFrame then return _minimapFrame end
    local mm = _G["Minimap"]
    if not mm then return nil end
    _minimapFrame = newReadout(mm, nil)
    if not _minimapFrame then return nil end
    _minimapFrame:SetPoint("TOP", mm, "BOTTOM", 0, -2)
    _minimapFrame.text:ClearAllPoints()
    _minimapFrame.text:SetPoint("CENTER")
    return _minimapFrame
end

local function playerPositionOn(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not (ok and pos and pos.GetXY) then return nil end
    local x, y = pos:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    -- An instance answers 0,0 rather than nil, and 0,0 is a real corner everywhere else
    if x == 0 and y == 0 then return nil end
    return x, y
end

-- Shared with Modules/MapPOI/Pin.lua's player fade. ONE implementation, because the 0,0 case
-- above is exactly what a second copy would leave out - a pin fade written against a raw
-- GetPlayerMapPosition would fade the top-left corner of every instance map.
-- Reached at RUNTIME by its consumers, so TOC order does not matter.
ns.PlayerPositionOn = playerPositionOn

-- The cursor is in SCREEN units and the canvas in its own, so each has to be divided by its own
-- effective scale before they can be compared. Comparing them raw is the mistake that has cost
-- this project a round before.
local function cursorPositionOn(canvas)
    if not (canvas and canvas.GetEffectiveScale and _G["GetCursorPosition"]) then return nil end
    local scale = canvas:GetEffectiveScale()
    if not scale or scale <= 0 then return nil end
    local cx, cy = _G["GetCursorPosition"]()
    if not (cx and cy) then return nil end
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not (left and top and w and h) or w <= 0 or h <= 0 then return nil end
    local x = ((cx / scale) - left) / w
    local y = (top - (cy / scale)) / h
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- Read by /eqsprobe ui. "Never updated" and "updated and found nothing" look identical on a
-- blank readout and have nothing in common.
M._mapUpdates, M._minimapUpdates, M._stage = 0, 0, "never ran"
M._lastMapText, M._lastMinimapText = nil, nil

local function updateMap()
    local f = _mapFrame
    if not f then return end
    local wmf = _G["WorldMapFrame"]
    if not (mapWanted() and wmf and wmf:IsShown()) then
        f:Hide()
        M._lastMapText = nil
        return
    end

    local mapID = wmf.GetMapID and wmf:GetMapID()
    local canvas = wmf.GetCanvas and wmf:GetCanvas()
    local fmt = pairFormat()
    local parts

    local cx, cy = cursorPositionOn(canvas)
    if cx then
        parts = L["Cursor"] .. " " .. fmt:format(cx * 100, cy * 100)
    end

    -- Only when the OPEN map is the one the player is standing on. The reference implementation
    -- prints the player's own position against whatever map you scrolled to, which reads as the
    -- player being in a zone they are not in.
    local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID and best == mapID then
        local px, py = playerPositionOn(mapID)
        if px then
            local label = (_G["PLAYER"] or L["Player"]) .. " " .. fmt:format(px * 100, py * 100)
            parts = parts and (parts .. "   " .. label) or label
        end
    end

    if not parts then
        f:Hide()
        M._lastMapText = nil
        return
    end
    -- Recorded so /eqsprobe and the offline harness can read what was RENDERED rather than
    -- re-deriving it, which would only prove the arithmetic agrees with itself.
    M._lastMapText = parts
    f.text:SetText(parts)
    f:SetWidth(math.max(1, f.text:GetStringWidth()))
    f:Show()
    M._mapUpdates = M._mapUpdates + 1
end

local function updateMinimap()
    local f = _minimapFrame
    if not f then return end
    local mm = _G["Minimap"]
    if not (minimapWanted() and mm and mm:IsVisible()) then
        f:Hide()
        M._lastMinimapText = nil
        return
    end
    local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local px, py = playerPositionOn(best)
    if not px then
        f:Hide()
        M._lastMinimapText = nil
        return
    end
    M._lastMinimapText = pairFormat():format(px * 100, py * 100)
    f.text:SetText(M._lastMinimapText)
    f:SetWidth(math.max(1, f.text:GetStringWidth()))
    f:Show()
    M._minimapUpdates = M._minimapUpdates + 1
end

local _elapsed = 0
local _driver

local function onUpdate(_, delta)
    _elapsed = _elapsed + delta
    if _elapsed < INTERVAL then return end
    _elapsed = 0
    updateMap()
    updateMinimap()
end

function M:ApplyEnabled()
    local on = mapWanted() or minimapWanted()
    if on then
        if mapWanted() then ensureMapFrame() end
        if minimapWanted() then ensureMinimapFrame() end
        if not _driver then
            _driver = CreateFrame("Frame")
        end
        _driver:SetScript("OnUpdate", onUpdate)
        M._stage = "running"
    else
        if _driver then _driver:SetScript("OnUpdate", nil) end
        M._stage = "off in options"
    end
    -- Hidden immediately rather than at the next tick, which never comes once the driver is off
    if _mapFrame and not mapWanted() then _mapFrame:Hide() end
    if _minimapFrame and not minimapWanted() then _minimapFrame:Hide() end
end

-- The precision slider changes the format, and nothing else would repaint until the next tick
function M:Refresh()
    wipe(FORMATS)
    updateMap()
    updateMinimap()
end

function M:OnEnable()
    self:ApplyEnabled()
end
