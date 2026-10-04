local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

-- The game's own icons carry a beveled border that looks heavy at 16 px beside a flat checkbox
local ICON_TRIM = { 0.08, 0.92, 0.08, 0.92 }
local EXPANSION_ROW = 32

local function refreshWQ()
    local WQ = ns:GetSubsystem("WQWorldMap")
    if WQ and WQ.Refresh then WQ:Refresh() end
end

local function wqSetting(key, after)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.worldQuests[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests[key] = value end
            refreshWQ()
            if after then after() end
        end
end

local function filterSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.worldQuests.filters[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests.filters[key] = value end
            refreshWQ()
        end
end

local FILTER_ROWS = {
    { key = "gold",       label = L["Gold"],                   icon = "Interface\\MoneyFrame\\UI-MoneyIcons", coords = { 0, 0.25, 0, 1 } },
    { key = "gear",       label = L["Gear / Items"],           icon = "Interface\\Icons\\INV_Helmet_06" },
    { key = "rep",        label = L["Reputation tokens"],      icon = "Interface\\Icons\\Achievement_Reputation_01" },
    { key = "resource",   label = L["Resources / Currencies"], icon = "Interface\\Icons\\Trade_Mining" },
    { key = "ap",         label = L["Artifact Power"],         icon = "Interface\\Icons\\INV_7XP_Inscription_TalentTome01" },
    { key = "profession", label = L["Profession quests"],      icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "pvp",        label = L["PvP"],                    icon = "Interface\\Icons\\Achievement_Bg_TopDmg" },
    { key = "pet",        label = L["Pet battles"],            icon = "Interface\\Icons\\INV_Pet_Achievement_CaptureAPet" },
    { key = "other",      label = L["Other / Uncategorized"],  icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

local EXPANSION_NAMES = {
    [0]  = L["Classic"],
    [1]  = L["The Burning Crusade"],
    [2]  = L["Wrath of the Lich King"],
    [3]  = L["Cataclysm"],
    [4]  = L["Mists of Pandaria"],
    [5]  = L["Warlords of Draenor"],
    [6]  = L["Legion"],
    [7]  = L["Battle for Azeroth"],
    [8]  = L["Shadowlands"],
    [9]  = L["Dragonflight"],
    [10] = L["The War Within"],
    [11] = L["Midnight"],
}

local SORT_OPTIONS = {
    { value = "time",    label = L["Time left"] },
    { value = "type",    label = L["Reward"]    },
    { value = "faction", label = L["Faction"]   },
    { value = "alpha",   label = L["A-Z"]       },
}

local function setAllFilters(value)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    for _, row in ipairs(FILTER_ROWS) do
        DB.db.profile.worldQuests.filters[row.key] = value
    end
    refreshWQ()
end

local function factionGet(fid)
    local DB = ns:GetSubsystem("DB")
    if not DB then return true end
    return DB.db.profile.worldQuests.factionFilters[fid] ~= false
end

local function factionSet(fid, value)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    if value then
        DB.db.profile.worldQuests.factionFilters[fid] = nil
    else
        DB.db.profile.worldQuests.factionFilters[fid] = false
    end
    refreshWQ()
end

local function listFactionsByExpansion()
    local groups = {}
    local groupByExp = {}
    if not (C_MajorFactions and C_MajorFactions.GetMajorFactionIDs) then return groups end

    local ids = C_MajorFactions.GetMajorFactionIDs() or {}
    for _, id in ipairs(ids) do
        local data = C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
        if data and data.isUnlocked then
            local exp = data.expansionID or -1
            local g = groupByExp[exp]
            if not g then
                g = { expansionID = exp, name = EXPANSION_NAMES[exp] or L["Other"], factions = {} }
                groupByExp[exp] = g
                groups[#groups + 1] = g
            end
            g.factions[#g.factions + 1] = data
        end
    end

    table.sort(groups, function(a, b) return (a.expansionID or 0) > (b.expansionID or 0) end)
    for _, g in ipairs(groups) do
        table.sort(g.factions, function(a, b) return (a.name or "") < (b.name or "") end)
    end

    return groups
end

-- Column-major, so an alphabetical list reads down the left column, then the right
local function twoColumns(self, card, boxes, into)
    local rows = math.ceil(#boxes / 2)
    for i = 1, rows do
        local row = card:Add(boxes[i])
        local right = boxes[i + rows]
        if right then
            right:ClearAllPoints()
            right:SetPoint("LEFT", row, "CENTER", self:Spacing("rowPadding"), 0)
        end
    end
    for _, box in ipairs(boxes) do into[#into + 1] = box end
end

local function worldQuestsCard(self, content, stack, w)
    local card = stack(self:CreateGroup(content, L["World Quests"]))

    w.masterOn = function()
        local DB = ns:GetSubsystem("DB")
        return not DB or DB.db.profile.worldQuests.enabled ~= false
    end
    card:Add(self:CreateCheckbox(content, L["Enable World Quests map features"], w.masterOn,
        function(v)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests.enabled = v and true or false end
            refreshWQ()
            w.sync()
        end,
        L["Off: Everything Quests stops putting World Quests on the map - no world-map pins, no reward summary box, no zone quest list. The boxes below do nothing while this is off. This switch is ONLY for World Quests. It does NOT remove the red \"!\" / \"?\" quest rings - those are your normal quests, and you turn them off on the Map tab. It also does NOT change the World Quests list in your tracker (that's on EQ Objective Tracker's Tracker tab)."]))

    local worldMapGet, worldMapSet = wqSetting("showOnWorldMap", w.sync)
    w.worldMapOn = worldMapGet
    w.worldMap = self:CreateCheckbox(content, L["Show world quest pins on the world map"], worldMapGet, worldMapSet)
    card:Add(w.worldMap, { dependent = true })

    local zoneListGet, zoneListSet = wqSetting("showOnZoneMap", w.sync)
    w.zoneListOn = zoneListGet
    w.zoneList = self:CreateCheckbox(content, L["Show zone quest list on zone maps"], zoneListGet, zoneListSet)
    card:Add(w.zoneList, { dependent = true })
end

local function filtersCard(self, content, stack, w)
    local card = stack(self:CreateGroup(content, L["Filters by reward type"]))

    local boxes = {}
    for _, row in ipairs(FILTER_ROWS) do
        local get, set = filterSetting(row.key)
        local cb = self:CreateCheckbox(content, row.label, get, set, nil, row.icon)
        local c = row.coords or ICON_TRIM
        cb.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        boxes[#boxes + 1] = cb
    end
    twoColumns(self, card, boxes, w.filters)

    local function setAll(value)
        setAllFilters(value)
        for _, cb in ipairs(boxes) do cb:Refresh() end
    end
    local all = self:CreateButton(content, L["Enable All"], nil, function() setAll(true) end)
    local none = self:CreateButton(content, L["Disable All"], nil, function() setAll(false) end)
    card:Add(all)
    none:SetPoint("LEFT", all, "RIGHT", self:Spacing("buttonGap"), 0)
    w.filters[#w.filters + 1] = all
    w.filters[#w.filters + 1] = none
end

local function factionCard(self, content, stack, w)
    local card = stack(self:CreateGroup(content, L["Filter by faction"]))
    self:AttachTooltip(card.label, L["Filter by faction"],
        L["Uncheck a faction to hide its world quests on the map."])

    local groups = listFactionsByExpansion()
    if #groups == 0 then
        card:Add(self:CreateText(content, L["No major factions unlocked on this character yet."], "hint"))
        return
    end
    for _, g in ipairs(groups) do
        local name = self:CreateText(content, g.name, "groupLabel")
        card:Add(name, { height = EXPANSION_ROW })
        w.filters[#w.filters + 1] = name

        local boxes = {}
        for _, data in ipairs(g.factions) do
            local fid = data.factionID
            local label = L["%s  |cffaaaaaa(Renown %d)|r"]:format(
                data.name or L["Faction %d"]:format(fid), data.renownLevel or 0)
            boxes[#boxes + 1] = self:CreateCheckbox(content, label,
                function() return factionGet(fid) end,
                function(v) factionSet(fid, v) end)
        end
        twoColumns(self, card, boxes, w.filters)
    end
end

local function displayCard(self, content, stack, w)
    local card = stack(self:CreateGroup(content, L["Display"]))
    self:AttachTooltip(card.label, L["Display"],
        L["Filters apply immediately when the world map is open."])

    local sortGet, sortSet = wqSetting("zoneListSort")
    w.sort = self:CreateDropdown(content, L["Sort zone quest list by"], SORT_OPTIONS, sortGet, sortSet)
    card:Add(w.sort)

    w.scale = self:CreateSlider(content, L["World map pin scale"], 0.5, 2.0, 0.05,
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.worldQuests.pinScale or 1.0
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.worldQuests.pinScale = value end
            refreshWQ()
        end)
    card:Add(w.scale)
end

Options:RegisterTab({
    id    = "worldQuests",
    title = L["World Quests"],
    order = 30,
    build = function(self, content)
        local stack = Options.CardStack(self)
        local w = { filters = {} }
        -- A row dims only while it does nothing: the filters feed both the pins and the zone list
        w.sync = function()
            local on = w.masterOn() and true or false
            local pins = on and w.worldMapOn() and true or false
            local list = on and w.zoneListOn() and true or false
            self:SetDependent(w.worldMap, on)
            self:SetDependent(w.zoneList, on)
            for _, c in ipairs(w.filters) do self:SetDependent(c, pins or list) end
            self:SetDependent(w.sort, list)
            self:SetDependent(w.scale, pins)
        end
        content._sync = w.sync

        worldQuestsCard(self, content, stack, w)
        filtersCard(self, content, stack, w)
        factionCard(self, content, stack, w)
        displayCard(self, content, stack, w)
        w.sync()
    end,
    refresh = function(_, content)
        if content._sync then content._sync() end
    end,
})
