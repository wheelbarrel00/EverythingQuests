local _, ns = ...
local L = ns.L

local S = ns:RegisterSubsystem("WQSummary", {})

local ROW_H      = 18
local ICON_SIZE  = 14
local PIN_TEMPLATE = "EQWorldQuestPinTemplate"

S.rowPool   = {}
S.activeRows = {}

local CATEGORY_DISPLAY = {
    gold       = { label = L["Gold"],           icon = "Interface\\MoneyFrame\\UI-MoneyIcons", iconCoords = { 0, 0.25, 0, 1 } },
    gear       = { label = L["Gear"],           icon = "Interface\\Icons\\INV_Helmet_06" },
    rep        = { label = L["Reputation"],     icon = "Interface\\Icons\\Achievement_Reputation_01" },
    resource   = { label = L["Resources"],      icon = "Interface\\Icons\\Trade_Mining" },
    ap         = { label = L["Artifact Power"], icon = "Interface\\Icons\\INV_7XP_Inscription_TalentTome01" },
    profession = { label = L["Professions"],    icon = "Interface\\Icons\\Trade_Engineering" },
    pvp        = { label = L["PvP"],            icon = "Interface\\Icons\\Achievement_Bg_TopDmg" },
    pet        = { label = L["Pet Battles"],    icon = "Interface\\Icons\\INV_Pet_Achievement_CaptureAPet" },
    other      = { label = L["Other"],          icon = "Interface\\Icons\\INV_Misc_Gift_01" },
}

local CATEGORY_ORDER = {
    "gear", "gold", "rep", "ap", "resource", "profession", "pvp", "pet", "other",
}

local function buildRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", 0, 0)

    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.count:SetPoint("RIGHT", 0, 0)
    r.count:SetJustifyH("RIGHT")
    r.count:SetTextColor(0.92, 0.72, 0.02)

    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT",  r.icon, "RIGHT", 6, 0)
    r.label:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.label:SetTextColor(0.9, 0.9, 0.9)

    return r
end

local function acquireRow(parent)
    return ns.Util.AcquirePooled(S.rowPool, S.activeRows, parent, buildRow)
end

local function releaseAllRows()
    for i = #S.activeRows, 1, -1 do
        local r = S.activeRows[i]
        r:Hide()
        r:ClearAllPoints()
        S.rowPool[#S.rowPool + 1] = r
        S.activeRows[i] = nil
    end
end

function S:GetCounts()
    local WQ = ns:GetSubsystem("WQWorldMap")
    if not (WQ and WQ.shadow and WQ.shadow.EnumeratePinsByTemplate) then return nil end

    local counts = {}
    for pin in WQ.shadow:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        local cat = pin.reward and pin.reward.category
        if cat then counts[cat] = (counts[cat] or 0) + 1 end
    end
    return counts
end

function S:Render(parent)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnWorldMap) then
        releaseAllRows()
        return 0
    end

    local counts = self:GetCounts()
    if not counts then releaseAllRows(); return 0 end

    local total = 0
    for _, c in pairs(counts) do total = total + c end
    if total == 0 then releaseAllRows(); return 0 end

    releaseAllRows()
    local y = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        local count = counts[cat] or 0
        if count > 0 then
            local display = CATEGORY_DISPLAY[cat] or CATEGORY_DISPLAY.other
            local row = acquireRow(parent)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)

            row.icon:SetTexture(display.icon)
            if display.iconCoords then
                row.icon:SetTexCoord(display.iconCoords[1], display.iconCoords[2],
                                     display.iconCoords[3], display.iconCoords[4])
            else
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.count:SetText(tostring(count))
            row.label:SetText(display.label)
            row:Show()

            y = y + ROW_H + 2
        end
    end
    return y
end
