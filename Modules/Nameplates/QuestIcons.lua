local _, ns = ...

local QI = ns:RegisterSubsystem("NameplateQuestIcons", {})

-- Defaults only - general.npIconSize and general.npIconTextSize override these
local ICON_SIZE    = 24
local DEFAULT_TEXT = 13
local SPACING      = 3

local function cfg()
    local DB = ns:GetSubsystem("DB")
    local g = (DB and DB.db.profile.general) or {}
    return (g.npIconSize or ICON_SIZE), (g.npIconTextSize or DEFAULT_TEXT), (g.npIconPlacement or "RIGHT"),
           (g.npIconOffsetX or 0), (g.npIconOffsetY or 0)
end

local PLACEMENT = {
    RIGHT  = { point = "LEFT",   rel = "RIGHT",  x = 4,  y = 0 },
    LEFT   = { point = "RIGHT",  rel = "LEFT",   x = -4, y = 0 },
    TOP    = { point = "BOTTOM", rel = "TOP",    x = 0,  y = 4 },
    BOTTOM = { point = "TOP",    rel = "BOTTOM", x = 0,  y = -4 },
}

local function anchorFrame(f, plate, placement, offX, offY)
    local p = PLACEMENT[placement] or PLACEMENT.RIGHT
    f:ClearAllPoints()
    f:SetPoint(p.point, plate, p.rel, p.x + (offX or 0), p.y + (offY or 0))
end

-- Numeric fallbacks: 17 = QuestTitle, 8 = QuestObjective (probed from live client).
local LT = Enum and Enum.TooltipDataLineType
local QUEST_TITLE     = (LT and LT.QuestTitle)     or 17
local QUEST_OBJECTIVE = (LT and LT.QuestObjective) or 8

-- Midnight restricted APIs can hand back secret values that error if indexed or compared
local _issecret = _G.issecretvalue
local function ok(v)
    if _issecret then return not _issecret(v) end
    return true
end

local KILL_WORDS = { "slain", "slay", "kill", "defeat", "destroy", "eliminat", "wound" }
local CHAT_WORDS = { "speak", "talk" }
local function objType(text, hasItem)
    if hasItem then return "ITEM" end
    if not text then return "DEFAULT" end
    local l = text:lower()
    for i = 1, #KILL_WORDS do if l:find(KILL_WORDS[i], 1, true) then return "KILL" end end
    for i = 1, #CHAT_WORDS do if l:find(CHAT_WORDS[i], 1, true) then return "CHAT" end end
    return "DEFAULT"
end

local function elvUILoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("ElvUI")) and true or false
end

local activeQuests = {}
local _logRows = {}

local function rebuildCache()
    wipe(activeQuests)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
        return
    end
    local rows, last = ns.Compat.CollectQuestLog(_logRows)
    for i = 1, last do
        local info = rows[i]
        if info and not info.isHeader and info.questID and info.title then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                local itemTexture
                if GetQuestLogSpecialItemInfo then
                    local _, tex = GetQuestLogSpecialItemInfo(i)
                    itemTexture = tex
                end
                local objMap
                for _, o in ipairs(objectives) do
                    local text = (not o.finished) and o.text
                    if text and text ~= "" then
                        local entry
                        if o.type == "progressbar" then
                            local p = tonumber(text:match("([%d%.]+)%%"))
                            if p and p <= 100 then
                                entry = { value = math.ceil(100 - p), isPercent = true }
                            end
                        else
                            local need, have = o.numRequired, o.numFulfilled
                            if need and have then
                                local diff = math.floor(need - have)
                                if diff > 0 then entry = { value = diff, isPercent = false } end
                            end
                        end
                        if entry then
                            entry.type        = objType(text, itemTexture)
                            entry.itemTexture = itemTexture
                            objMap = objMap or {}
                            objMap[text] = entry
                        end
                    end
                end
                if objMap then activeQuests[info.title] = objMap end
            end
        end
    end
end

local _scanSeen = {}
local function scanInto(unit, out)
    wipe(out)
    -- ⚠ Classic has no C_TooltipInfo.GetUnit, so this returns 0 and the icons never appear.
    -- The replacement is a GameTooltip:SetUnit plus TextLeft<i>:GetText() scrape, not written
    -- yet because whether a Classic unit tooltip carries quest lines at all is unmeasured.
    if not ns.Has.TooltipDataUnit then return 0 end
    local data = C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    if not lines then return 0 end

    -- Dedup by entry instead of filtering the QuestPlayer line - objMap only holds your own quests, so a party member's line can only echo one of yours
    wipe(_scanSeen)
    local count, objMap = 0, nil
    for i = 2, #lines do
        local line = lines[i]
        local text = line and line.leftText
        if ok(text) and text and text ~= "" then
            local lt = line.type
            if lt == QUEST_TITLE then
                objMap = activeQuests[text]
            elseif lt == QUEST_OBJECTIVE and objMap then
                local entry = objMap[text]
                if entry and not _scanSeen[entry] then
                    _scanSeen[entry] = true
                    count = count + 1
                    out[count] = entry
                end
            end
        end
    end
    return count
end

local EQ_LOGO = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\eq-logo-v3.tga"

local TEX = {
    DEFAULT = { tex  = EQ_LOGO },
    KILL    = { tex  = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\skull.tga" },
    CHAT    = { tex  = "Interface\\WorldMap\\ChatBubble_64.PNG", coord = { 0, 0.5, 0.5, 1 } },
    ITEM    = { item = true },
}

local function buildSlot(frame, iconSize, textSize)
    local ic = frame:CreateTexture(nil, "OVERLAY")
    ic:SetSize(iconSize, iconSize)
    ic:Hide()
    ic.text = frame:CreateFontString(nil, "OVERLAY")
    ic.text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    ic.text:SetTextColor(1, 0.94, 0.6)
    ic.text:SetPoint("LEFT", ic, "RIGHT", 2, 0)
    ic.text:Hide()
    return ic
end

local function getIconFrame(plate)
    local f = plate.EQQuestIcons
    if f then return f end
    local iconSize, textSize, placement, offX, offY = cfg()
    f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("HIGH")
    f:SetSize(iconSize, iconSize)
    anchorFrame(f, plate, placement, offX, offY)
    f.slots = { buildSlot(f, iconSize, textSize), buildSlot(f, iconSize, textSize),
                buildSlot(f, iconSize, textSize), buildSlot(f, iconSize, textSize) }
    plate.EQQuestIcons = f
    return f
end

local function hideFrame(plate)
    local f = plate and plate.EQQuestIcons
    if not f then return end
    for i = 1, #f.slots do f.slots[i]:Hide(); f.slots[i].text:SetText(""); f.slots[i].text:Hide() end
    f:Hide()
    f.guid = nil
end

local function render(plate, list, count, hostile)
    local f = getIconFrame(plate)
    -- Re-read size and placement every pass - Blizzard pools nameplates, so a frame recycled while off-screen carries stale option values
    local iconSize, textSize, placement, offX, offY = cfg()
    anchorFrame(f, plate, placement, offX, offY)
    f:SetHeight(iconSize)
    for i = 1, #f.slots do
        f.slots[i]:Hide()
        f.slots[i].text:SetText("")
        f.slots[i].text:Hide()
    end
    if not count or count == 0 then f:Hide(); return end

    local x, shown = 0, 0
    for i = 1, count do
        local q = list[i]
        if q and (q.isPercent or (q.value and q.value > 0)) then
            local ic = f.slots[shown + 1]
            if not ic then break end
            shown = shown + 1

            ic:SetSize(iconSize, iconSize)
            ic.text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")

            -- objType keywords only match on enUS, so treat an unclassified objective on an attackable unit as a kill
            local qtype = q.type
            if qtype == "DEFAULT" and hostile then qtype = "KILL" end
            local def = TEX[qtype] or TEX.DEFAULT
            if def.atlas then
                ic:SetAtlas(def.atlas); ic:SetTexCoord(0, 1, 0, 1)
            elseif def.item and q.itemTexture then
                ic:SetTexture(q.itemTexture); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif def.tex then
                ic:SetTexture(def.tex)
                if def.coord then ic:SetTexCoord(unpack(def.coord)) else ic:SetTexCoord(0, 1, 0, 1) end
            else
                ic:SetTexture(EQ_LOGO); ic:SetTexCoord(0, 1, 0, 1)
            end

            ic:ClearAllPoints()
            ic:SetPoint("LEFT", f, "LEFT", x, 0)
            ic:Show()

            local advance = iconSize
            if q.type ~= "CHAT" and (q.isPercent or (q.value and q.value > 1)) then
                ic.text:SetText(q.isPercent and (q.value .. "%") or q.value)
                ic.text:Show()
                advance = advance + 2 + math.ceil(ic.text:GetStringWidth())
            end
            x = x + advance + SPACING
        end
    end

    if shown > 0 then
        f:SetWidth(math.max(1, x - SPACING))
        f:Show()
    else
        f:Hide()
    end
end

local activePlates = {}

local function updatePlate(unit, event)
    if not (QI.enabled and unit) then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    if UnitIsPlayer(unit) then hideFrame(plate); return end

    local guid = UnitGUID(unit)
    if not ok(guid) then return end

    local f = getIconFrame(plate)
    f.list = f.list or {}
    local count
    if f.guid ~= guid then
        f.guid = guid
        count = scanInto(unit, f.list)
        f.count = count
    elseif event == "QUEST_LOG_UPDATE" then
        count = scanInto(unit, f.list)
        f.count = count
    else
        count = f.count
    end
    render(plate, f.list, count, UnitCanAttack("player", unit))
end

local function refreshAllPlates(event)
    for unit in pairs(activePlates) do updatePlate(unit, event) end
end

local function questLogRefresh()
    rebuildCache()
    refreshAllPlates("QUEST_LOG_UPDATE")
end

local function onPlateAdded(_, unit)
    if not unit then return end
    activePlates[unit] = true
    updatePlate(unit, "NAME_PLATE_UNIT_ADDED")
end
local function onPlateRemoved(_, unit)
    if not unit then return end
    activePlates[unit] = nil
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    hideFrame(plate)
end
local function onQuestLogUpdate()
    local Events = ns:GetSubsystem("Events")
    if Events and Events.Throttle then
        Events:Throttle("nameplateQuestIcons", 0.5, questLogRefresh)
    else
        questLogRefresh()
    end
end

local REGISTERED = {
    NAME_PLATE_UNIT_ADDED   = onPlateAdded,
    NAME_PLATE_UNIT_REMOVED = onPlateRemoved,
    QUEST_LOG_UPDATE        = onQuestLogUpdate,
    QUEST_ACCEPTED          = onQuestLogUpdate,
    QUEST_REMOVED           = onQuestLogUpdate,
}

function QI:IsEnabled()
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general.questNameplateIcons
    if v == nil then return not elvUILoaded() end
    return v and true or false
end

function QI:ApplyEnabled()
    local on = self:IsEnabled()
    if on == self.enabled then return end
    self.enabled = on

    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if on then
        for event, fn in pairs(REGISTERED) do Events:On(event, fn) end
        rebuildCache()
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unit = plate.namePlateUnitToken
                if unit then activePlates[unit] = true end
            end
        end
        refreshAllPlates("ENABLE")
    else
        for event, fn in pairs(REGISTERED) do Events:Off(event, fn) end
        for unit in pairs(activePlates) do
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
            hideFrame(plate)
        end
        wipe(activePlates)
    end
end

function QI:ApplyLayout()
    if not self.enabled then return end
    refreshAllPlates("LAYOUT")
end

function QI:OnEnable()
    self.enabled = false
    self:ApplyEnabled()

    -- Uses EQ's own Dialog (not Blizzard StaticPopup) to stay clear of the Quit/Logout taint.
    local DB = ns:GetSubsystem("DB")
    local g  = DB and DB.db.profile.general
    if g and g.questNameplateIcons == nil and not g.npConflictAsked and elvUILoaded() then
        g.npConflictAsked = true
        C_Timer.After(4, function()
            local Dialog = ns:GetSubsystem("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title = "Everything Quests",
                text = "EQ can show quest icons (the \"!\" + remaining count) on enemy nameplates.\n\nElvUI is installed and already offers this, so EQ's version is currently OFF to avoid showing two of each icon. Which would you like to use?",
                button1 = "Everything Quests",
                button2 = "Keep ElvUI's",
                onAccept = function()
                    g.questNameplateIcons = true
                    QI:ApplyEnabled()
                end,
                onCancel = function()
                    g.questNameplateIcons = false
                    QI:ApplyEnabled()
                end,
            })
        end)
    end
end
