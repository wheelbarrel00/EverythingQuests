local _, ns = ...
local L = ns.L

local P = ns:RegisterSubsystem("WQPanel", {})

local PANEL_W     = 250
-- Clears the WQ side tab on the map's right edge (about 43 wide) so the docked panel does not overlap it
local LEFT_GAP    = 50
local TOP_INSET   = 4
local BOT_INSET   = 4
local PAD         = 6
local TITLE_H     = 24
local SUBHEADER_H = 18
local BAR_W       = 18
local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

local BG_COLOR   = { 0, 0, 0, 0.9 }
-- Gold, not EQ brand red, so the docked panel reads as part of the map chrome
local EDGE_COLOR = { 0.85, 0.65, 0.13, 0.95 }
local GOLD       = { 1.0, 0.82, 0.0 }

local function edge(f)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], EDGE_COLOR[4])
    return t
end

function P:Build()
    if self.frame then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Frame", "EQWorldQuestPanel", WorldMapFrame)
    f:SetWidth(PANEL_W)
    f:SetFrameStrata("HIGH")
    if WorldMapFrame.GetFrameLevel then
        f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    end
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4])

    local top = edge(f); top:SetHeight(1); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT")
    local bot = edge(f); bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    local lt  = edge(f); lt:SetWidth(1);   lt:SetPoint("TOPLEFT");     lt:SetPoint("BOTTOMLEFT")
    local rt  = edge(f); rt:SetWidth(1);   rt:SetPoint("TOPRIGHT");    rt:SetPoint("BOTTOMRIGHT")

    local titleBar = f:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_H)
    titleBar:SetColorTexture(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], 0.22)

    local titleLine = edge(f); titleLine:SetHeight(1)
    titleLine:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    titleLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    f.title:SetText("Everything Quests")
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    f.summaryHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.summaryHeader:SetText(L["World Quests"])
    f.summaryHeader:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.summaryHeader:SetJustifyH("LEFT")

    f.summaryRegion = CreateFrame("Frame", nil, f)

    f.divider = edge(f); f.divider:SetHeight(1)

    f.zoneHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.zoneHeader:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.zoneHeader:SetJustifyH("LEFT")
    f.zoneHeader:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", "EQWorldQuestPanelScroll", f, "UIPanelScrollFrameTemplate")
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(PANEL_W - 2 * PAD - BAR_W, 1)
    scroll:SetScrollChild(list)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local range = sf:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local new = (sf:GetVerticalScroll() or 0) - delta * 34
        if new < 0 then new = 0 elseif new > range then new = range end
        sf:SetVerticalScroll(new)
    end)
    f.scroll = scroll
    f.list   = list

    self.frame = f
end

-- The tab gates on this, not raw pin presence, so it can never invite-open onto an empty panel
function P:HasContent()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false) then return false end
    local wq = DB.db.profile.worldQuests

    if wq.showOnWorldMap then
        local Summary = ns:GetSubsystem("WQSummary")
        local counts = Summary and Summary.GetCounts and Summary:GetCounts()
        if counts and next(counts) then return true end
    end

    if wq.showOnZoneMap and WorldMapFrame and WorldMapFrame:IsShown() then
        local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        local mapInfo = mapID and mapID > 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
        if mapInfo and mapInfo.mapType == zoneType then
            local WQ = ns:GetSubsystem("WQWorldMap")
            if WQ and WQ.shadow and WQ.shadow.EnumeratePinsByTemplate then
                for _ in WQ.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
                    return true
                end
            end
        end
    end

    return false
end

function P:Refresh()
    self:Build()
    local f = self.frame
    if not f then return end

    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.popoutOpen
            and WorldMapFrame and WorldMapFrame:IsShown()) then
        f:Hide()
        return
    end

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT",    WorldMapFrame, "TOPRIGHT",    LEFT_GAP, -TOP_INSET)
    f:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", LEFT_GAP,  BOT_INSET)
    f:SetWidth(PANEL_W)

    local y = TITLE_H + 2

    local Summary = ns:GetSubsystem("WQSummary")
    local summaryH = (Summary and Summary.Render and Summary:Render(f.summaryRegion)) or 0
    if summaryH > 0 then
        f.summaryHeader:ClearAllPoints()
        f.summaryHeader:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
        f.summaryHeader:Show()
        y = y + SUBHEADER_H

        f.summaryRegion:ClearAllPoints()
        f.summaryRegion:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -y)
        f.summaryRegion:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        f.summaryRegion:SetHeight(summaryH)
        f.summaryRegion:Show()
        y = y + summaryH + 6
    else
        f.summaryHeader:Hide()
        f.summaryRegion:Hide()
    end

    local Zone = ns:GetSubsystem("WQZoneMap")
    local listH, headerText = 0, nil
    if Zone and Zone.Render then
        listH, headerText = Zone:Render(f.list)
    end

    if summaryH > 0 and headerText then
        f.divider:ClearAllPoints()
        f.divider:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -y)
        f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        f.divider:Show()
        y = y + 6
    else
        f.divider:Hide()
    end

    if headerText then
        f.zoneHeader:ClearAllPoints()
        f.zoneHeader:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -y)
        f.zoneHeader:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        f.zoneHeader:SetText(headerText)
        f.zoneHeader:Show()
        y = y + SUBHEADER_H

        f.scroll:ClearAllPoints()
        f.scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD,           -y)
        f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + BAR_W),  PAD)
        f.list:SetWidth(PANEL_W - 2 * PAD - BAR_W)
        f.list:SetHeight(math.max(1, listH))
        f.scroll:SetVerticalScroll(0)
        if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
        f.scroll:Show()
    else
        f.zoneHeader:Hide()
        f.scroll:Hide()
    end

    if summaryH <= 0 and not headerText then
        f:Hide()
    else
        f:Show()
    end
end
