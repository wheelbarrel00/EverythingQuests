local _, ns = ...

local TH = ns:RegisterSubsystem("TrackerTaxiHighlight", {})

local MAX_RETRIES   = 3                  -- pin pool may not be populated on the very first frame
local RETRY_DELAY_S = 0.10

local _glow

local _retriesLeft = 0
local _retryFn

local function ensureGlow()
    if _glow then return _glow end
    _glow = UIParent:CreateTexture(nil, "OVERLAY")
    _glow:SetSize(36, 36)
    local atlasName = "loottoast-glow"
    if C_Texture and C_Texture.GetAtlasInfo
       and C_Texture.GetAtlasInfo(atlasName) then
        _glow:SetAtlas(atlasName)
    else
        _glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        _glow:SetVertexColor(1, 0.85, 0, 0.45)
        _glow:SetBlendMode("ADD")
    end
    _glow:Hide()
    return _glow
end

local function detachGlow()
    if _glow then
        _glow:Hide()
        _glow:ClearAllPoints()
        _glow:SetParent(UIParent)
    end
end

local function attachGlow(pin)
    local g = ensureGlow()
    g:SetParent(pin)
    g:ClearAllPoints()
    g:SetPoint("CENTER", pin, "CENTER", 0, 0)
    g:Show()
end

local function questPosInContinent(continentMapID)
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
            and C_QuestLog and C_QuestLog.GetNextWaypoint
            and C_Map and C_Map.GetMapRectOnMap) then return nil end

    local qid = C_SuperTrack.GetSuperTrackedQuestID()
    if not qid or qid == 0 then return nil end

    local wm, wx, wy = C_QuestLog.GetNextWaypoint(qid)
    if not (wm and wx and wy) then return nil end

    -- GetMapRectOnMap returns four scalars (minX, maxX, minY, maxY), not a rect table.
    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(wm, continentMapID)
    if not (minX and maxX and minY and maxY) then return nil end
    return minX + wx * (maxX - minX), minY + wy * (maxY - minY)
end

local function findClosestNode(continentMapID, qcx, qcy)
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return nil end
    local nodes = C_TaxiMap.GetAllTaxiNodes(continentMapID)
    if not nodes or #nodes == 0 then return nil end

    local best, bestDist
    for i = 1, #nodes do
        local n = nodes[i]
        local pos = n and n.position
        if pos and pos.x and pos.y then
            local dx, dy = pos.x - qcx, pos.y - qcy
            local d = dx * dx + dy * dy
            if not bestDist or d < bestDist then
                bestDist = d
                best     = n
            end
        end
    end
    return best
end

local function attemptHighlight()
    if not (FlightMapFrame and FlightMapFrame.IsShown
            and FlightMapFrame:IsShown()) then return end

    local mapID = FlightMapFrame.GetMapID and FlightMapFrame:GetMapID()
    if not mapID then return end

    local qcx, qcy = questPosInContinent(mapID)
    if not qcx then return end

    local target = findClosestNode(mapID, qcx, qcy)
    if not target or not target.nodeID then return end

    if FlightMapFrame.EnumerateAllPins then
        for pin in FlightMapFrame:EnumerateAllPins() do
            local td = pin and pin.taxiNodeData
            if td and td.nodeID == target.nodeID then
                attachGlow(pin)
                return
            end
        end
    end
    if _retriesLeft > 0 then
        _retriesLeft = _retriesLeft - 1
        if not _retryFn then _retryFn = attemptHighlight end
        C_Timer.After(RETRY_DELAY_S, _retryFn)
    end
end

local function onTaxiOpened()
    detachGlow()
    _retriesLeft = MAX_RETRIES
    attemptHighlight()
end

local function onTaxiClosed()
    detachGlow()
    _retriesLeft = 0
end

function TH:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("TAXIMAP_OPENED", onTaxiOpened)
    Events:On("TAXIMAP_CLOSED", onTaxiClosed)
end
