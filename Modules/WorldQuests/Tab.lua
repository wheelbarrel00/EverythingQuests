local _, ns = ...
local L = ns.L

local T = ns:RegisterSubsystem("WQTab", {})

-- Native quest-map side-tab dimensions, from Blizzard's LargeSideTabButtonTemplate
local TAB_W, TAB_H = 43, 55
-- Lower-middle of the map's right edge, clear of Blizzard's own button column up top
local TAB_Y = -110
local PANEL_EDGE_X = 28

-- Copy the Map Legend tab's own stacking anchor so gap and x match exactly - reading a Blizzard frame's point is taint-free
local function anchorTab(f)
    f:ClearAllPoints()
    local mlt = QuestMapFrame and QuestMapFrame.MapLegendTab
    if mlt and mlt.GetNumPoints and mlt:GetNumPoints() > 0 then
        local point, _, relPoint, x, y = mlt:GetPoint(1)
        if point then
            f:SetPoint(point, mlt, relPoint, x or 0, y or 0)
            local w, h = mlt:GetSize()
            if w and w > 0 and h and h > 0 then f:SetSize(w, h) end
            return
        end
    end
    f:SetPoint("RIGHT", WorldMapFrame, "RIGHT", PANEL_EDGE_X, TAB_Y)
end

-- Gate on the native tab's actual backdrop, not just the reskin addon being loaded, so we stay Blizzard-styled when its quest skin is off
local function applyElvUISkin(f)
    if f._elvui then return true end
    local mlt = QuestMapFrame and QuestMapFrame.MapLegendTab
    if not (_G.ElvUI and mlt and mlt.backdrop and f.CreateBackdrop) then return false end

    if f.bg       then f.bg:Hide()       end
    if f.selected then f.selected:Hide() end
    if f.hl       then f.hl:Hide()       end

    local ok = pcall(function() if not f.backdrop then f:CreateBackdrop() end end)
    if not (ok and f.backdrop) then return false end

    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT",     f, "TOPLEFT",      4, -4)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,  4)

    f._elvui = true
    return true
end

function T:Build()
    if self.tab then return end
    if not WorldMapFrame then return end

    local f = CreateFrame("Button", "EQWorldQuestTab", WorldMapFrame)
    f:SetSize(TAB_W, TAB_H)
    anchorTab(f)
    f:SetFrameStrata("HIGH")
    if WorldMapFrame.GetFrameLevel then
        f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    end

    -- Replicate the native side-tab art rather than inherit LargeSideTabButtonTemplate - its SidePanelTabButtonMixin tab-group coupling breaks on a map-parented frame
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAtlas("questlog-tab-side", true)
    f.bg:SetPoint("CENTER")

    f.selected = f:CreateTexture(nil, "OVERLAY")
    f.selected:SetAtlas("QuestLog-Tab-side-Glow-select", true)
    f.selected:SetPoint("CENTER")
    f.selected:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(26, 26)
    f.icon:SetAtlas("Worldquest-icon")
    f.icon:SetPoint("CENTER", -2, 0)

    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAtlas("QuestLog-Tab-side-Glow-hover", true)
    f.hl:SetPoint("CENTER")

    applyElvUISkin(f)

    f:SetScript("OnClick", function() T:Toggle() end)
    -- Private tooltip, not the shared GameTooltip: drawing on the singleton from a map-parented frame leaves taint that trips the next AreaPOI hover
    f:SetScript("OnEnter", function(s)
        local tip = ns.Util.PinTooltip()
        tip:SetOwner(s, "ANCHOR_LEFT")
        local DB = ns:GetSubsystem("DB")
        local open = DB and DB.db.profile.worldQuests.popoutOpen
        tip:SetText(L["World Quests"], 1, 0.82, 0)
        tip:AddLine(open and L["Click to hide the World Quests list."]
                          or L["Click to show the World Quests list."], 0.82, 0.82, 0.82, true)
        tip:Show()
    end)
    f:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)

    self.tab = f
    self:UpdateVisual()
end

function T:UpdateVisual()
    local f = self.tab
    if not f then return end
    local DB = ns:GetSubsystem("DB")
    local open = DB and DB.db.profile.worldQuests.popoutOpen
    if f._elvui and f.backdrop then
        if open then
            f.backdrop:SetBackdropBorderColor(0.92, 0.72, 0.02)
        else
            local E = _G.ElvUI and _G.ElvUI[1]
            local bc = E and E.media and E.media.bordercolor
            if bc then
                f.backdrop:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
            else
                f.backdrop:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    elseif f.selected then
        f.selected:SetShown(open and true or false)
    end
end

function T:Toggle()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local wq = DB.db.profile.worldQuests
    wq.popoutOpen = not wq.popoutOpen

    local Panel = ns:GetSubsystem("WQPanel")
    if Panel and Panel.Refresh then Panel:Refresh() end
    self:UpdateVisual()
end

function T:Refresh()
    self:Build()
    if not self.tab then return end

    local DB = ns:GetSubsystem("DB")
    local wq = DB and DB.db.profile.worldQuests
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local Panel = ns:GetSubsystem("WQPanel")
    local hasContent = Panel and Panel.HasContent and Panel:HasContent()
    if not (wq and wq.enabled ~= false and mapOpen and hasContent) then
        self.tab:Hide()
        return
    end
    self.tab:Show()
    anchorTab(self.tab)
    applyElvUISkin(self.tab)
    self:UpdateVisual()
end
