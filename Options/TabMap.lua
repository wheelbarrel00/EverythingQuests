local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local function readMap(key)
    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    return map and map[key]
end

local function writeMap(key, value)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.db.profile.map = DB.db.profile.map or {}
    DB.db.profile.map[key] = value
end

local function refreshPins()
    local P = ns:GetSubsystem("MapPOIProvider")
    if P and P.provider and P.provider.RefreshAllData then
        P.provider:RefreshAllData()
    end
end

local function rebuildMinimap()
    local MM = ns:GetSubsystem("MinimapQuestPins")
    if MM then MM:Rebuild() end
end

local function rebuildAvailable()
    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail then Avail:Invalidate() end
    refreshPins()
    rebuildMinimap()
end

local function mapBox(self, content, key, tickedWhenUnset, label, tooltip, after)
    return self:CreateCheckbox(content, label,
        function()
            if tickedWhenUnset then return readMap(key) ~= false end
            return readMap(key) == true
        end,
        function(v)
            writeMap(key, v and true or false)
            if after then after() end
        end,
        tooltip)
end

local function pinRows(self, content, card)
    card:Add(mapBox(self, content, "showQuestPins", true, L["Show quest pins on the world map"],
        L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Uncheck this box and all of EQ's red markers go away. Quests you have not accepted yet are controlled separately."],
        refreshPins))

    card:Add(self:CreateSlider(content, L["World map pin scale"], 0.5, 2.0, 0.05,
        function()
            local s = readMap("pinScale")
            return type(s) == "number" and s or 1.0
        end,
        function(value)
            writeMap("pinScale", value)
            refreshPins()
        end,
        L["Quest pins are drawn at a fixed size no matter how far the map is zoomed, and this sets that size. Raise it if the pins are hard to pick out on a large or high-resolution display."]))

    local MAX_PINS = ns.MAPPOI_MAX_PINS or 250
    card:Add(self:CreateSlider(content, L["Objective pins per quest"], 25, MAX_PINS, 25,
        function()
            local n = readMap("pinCap")
            return type(n) == "number" and n or 50
        end,
        function(value)
            writeMap("pinCap", value)
            refreshPins()
            -- The minimap reads the same pinCap, and nothing else rebuilds it when the cap changes
            rebuildMinimap()
        end,
        L["How many places to mark for a single quest on one map. The busiest locations are kept first, so a lower number still points you somewhere useful. Slide all the way right for no limit at all - a few gathering quests can then put hundreds of markers on one map."],
        function(v) return v >= MAX_PINS and L["No limit"] or ("%d"):format(v) end))

    -- Asks the pin's own resolver, because unset means ON on retail and OFF on Classic
    card:Add(self:CreateCheckbox(content, L["Show a ring around quest pins"],
        function() return ns.QuestPinRingWanted and ns.QuestPinRingWanted(false) or false end,
        function(v)
            writeMap("showPinRing", v and true or false)
            refreshPins()
        end,
        L["Draws the red circle behind every world map marker for a quest in your log, both the ones you are still working on and the ones that are ready to turn in. Turn it off for plain icons and a much quieter map when a zone is busy."]))

    card:Add(mapBox(self, content, "onlyTrackedPins", false, L["Only show markers for quests you are tracking"],
        L["Leaves out the markers for any quest in your log that you have untracked, so a busy zone shows only what you are actually working on. Off by default. Quests you have not picked up yet are not affected, because there is nothing to have tracked."],
        function()
            refreshPins()
            rebuildMinimap()
        end))

    card:Add(mapBox(self, content, "fadePinsOverPlayer", false, L["Fade markers that cover your position"],
        L["Makes any marker sitting on top of your own arrow see-through, so you can still find yourself on a zone that is drawing hundreds of them. Off by default. The markers are still there and still answer the mouse, they are only dimmed while you are standing under them."],
        -- Applied at once rather than on the next fade tick, so the box and the map agree
        function() if ns.QuestPinApplyFade then ns.QuestPinApplyFade() end end))
end

local function availableRows(self, content, card, w)
    local master = mapBox(self, content, "showAvailableQuests", true, L["Show quests you can pick up"],
        L["Marks every quest giver who has something for you but is not in your quest log yet, with a gold ring around the exclamation mark so it reads apart from the quests you are already carrying. One marker covers a whole quest giver, and hovering it lists everything that giver offers. Quests are filtered by your level, race, class and the quests you have already finished, and holiday quests are shown only while their world event is running."],
        function()
            rebuildAvailable()
            w.sync()
        end)
    card:Add(master)
    w.availOn = function() return readMap("showAvailableQuests") ~= false end

    if ns:GetSubsystem("MapPOIProvider") then
        local ring = mapBox(self, content, "showAvailableRing", false, L["Show a ring around quests you can pick up"],
            L["Draws the gold circle behind the exclamation mark of every quest giver who has something for you. Off by default. The mark itself still tells these apart from the quests you are already carrying, because those use their own objective art or the turn-in mark instead."],
            function()
                refreshPins()
                rebuildMinimap()
            end)
        card:Add(ring, { dependent = true })
        w.avail[#w.avail + 1] = ring
    end
    -- Indented under the master but never dimmed, because the Quest Browser applies them too
    local function filter(control) card:Add(control, { dependent = true }) end
    filter(mapBox(self, content, "hideLowLevelQuests", true, L["Hide quests below your level"],
        L["Leaves out quests the game has already grayed out for you, using the game's own threshold rather than a fixed number of levels. On by default. Turn it off to see everything a quest giver has, including the quests you have outleveled."],
        rebuildAvailable))
    filter(mapBox(self, content, "hideOutOfSeasonQuests", true, L["Hide holiday quests out of season"],
        L["Leaves out quests belonging to a world event that is not running, such as the Lunar Festival in July. On by default. Turn it off to see every holiday quest all year, which is how the map behaved before."],
        rebuildAvailable))
    filter(mapBox(self, content, "hideHighLevelQuests", false, L["Hide quests above your level"],
        L["Leaves out quests the game colors red for you, using its own threshold rather than a fixed number of levels. Off by default, because a red quest is still worth knowing about if you are coming back later."],
        rebuildAvailable))
end

local function mapCard(self, content, stack, w)
    local Provider = ns:GetSubsystem("MapPOIProvider")
    local MinimapPins = ns:GetSubsystem("MinimapQuestPins")
    local Avail = ns:GetSubsystem("AvailableQuests")
    if not (Provider or MinimapPins or Avail) then return end
    local card = stack(self:CreateGroup(content, L["Map"]))

    if Provider then pinRows(self, content, card) end
    if MinimapPins then
        card:Add(mapBox(self, content, "showMinimapPins", true, L["Show objective pins on the minimap"],
            L["Puts the same objective markers on the minimap as on the world map, for the zone you are standing in. They use the per-quest limit above. Hover one for the quest name and what it still needs."],
            function() MinimapPins:Rebuild() end))
    end
    if Avail then availableRows(self, content, card, w) end
end

local function categoryCard(self, content, stack)
    if not (ns:GetSubsystem("AvailableQuests") and ns.CLASSIC_QUEST_CATEGORY) then return end
    local card = stack(self:CreateGroup(content, L["Hide these quests on the map"]))
    self:AttachTooltip(card.label, L["Hide these quests on the map"],
        L["These only affect the markers for quests you have NOT picked up yet. A quest already in your log always keeps its markers, because hiding something you are carrying would make the map lie about what you still have to do."])

    -- Each box HIDES its category, so nil reads as show it and older profiles are unchanged
    local function category(key, label, tooltip)
        card:Add(mapBox(self, content, key, false, label, tooltip, rebuildAvailable))
    end
    category("hideDungeonQuests", L["Dungeon and raid quests"],
        L["Leaves out quests that are sorted into a dungeon or a raid. Most are picked up inside the instance or from a quest giver at its door, so they clutter the outdoor map without helping you while you are questing in the world."])
    category("hideRepeatableQuests", L["Repeatable quests"],
        L["Leaves out the quests you can hand in over and over, usually a turn-in for reputation or a common trade good. They never stop being offered, so they stay on the map forever once you can see them."])
    category("hideProfessionQuests", L["Profession quests"],
        L["Leaves out quests that require a trade skill, such as a Blacksmithing or Alchemy specialization. Everything Quests cannot read your skill levels on this version of the game, so these are offered even when you have not trained the profession they need."])
end

local function coordinatesCard(self, content, stack, w)
    local MC = ns:GetSubsystem("MapCoords")
    if not MC then return end
    local card = stack(self:CreateGroup(content, L["Coordinates"]))

    local function coordSetting(key, default)
        return
            function()
                local v = readMap(key)
                if v == nil then return default end
                return v == true
            end,
            function(value)
                writeMap(key, value and true or false)
                local M = ns:GetSubsystem("MapCoords")
                if M then M:ApplyEnabled() end
                w.sync()
            end
    end

    local mapGet, mapSet = coordSetting("showMapCoords", true)
    card:Add(self:CreateCheckbox(content, L["Show coordinates on the world map"], mapGet, mapSet,
        L["Puts a small readout in the bottom left of the world map with the position your mouse is pointing at, and your own position when you are looking at the zone you are standing in. Turn it off if another addon already shows coordinates there."]))

    local mmGet, mmSet = coordSetting("showMinimapCoords", false)
    card:Add(self:CreateCheckbox(content, L["Show coordinates under the minimap"], mmGet, mmSet,
        L["Puts your own position just below the minimap so it is readable without opening the map. Off by default, because many interface addons already put something there."]))

    local prec = self:CreateSlider(content, L["Coordinate decimals"], 0, 2, 1,
        function()
            local n = readMap("coordPrecision")
            return type(n) == "number" and n or 1
        end,
        function(value)
            writeMap("coordPrecision", value)
            local M = ns:GetSubsystem("MapCoords")
            if M then M:Refresh() end
        end,
        L["How precise the numbers are. Zero is whole numbers, which is enough to find a spot on the map. Two is what most quest guides quote."])
    card:Add(prec, { dependent = true })
    w.prec = prec
    w.coordOn = function() return mapGet() or mmGet() end
end

local function tooltipsCard(self, content, stack)
    if not ns:GetSubsystem("QuestTooltips") then return end
    local card = stack(self:CreateGroup(content, L["Tooltips"]))
    card:Add(self:CreateCheckbox(content, L["Show quest progress on tooltips"],
        function()
            local DB = ns:GetSubsystem("DB")
            return not DB or DB.db.profile.general.questTooltips ~= false
        end,
        function(v)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.general.questTooltips = v and true or false end
            local QT = ns:GetSubsystem("QuestTooltips")
            if QT then QT:ApplyEnabled() end
        end,
        L["Adds the quest name and what it still needs to the tooltips you already see in the game. Hovering an item in your bags tells you which quest wants it and how many are still missing. On Classic, hovering an enemy also tells you which quest it counts toward, which the game itself never says there. Only quests already in your log are listed, and nothing is added to a tooltip that has nothing to say."]))
end

local function nameplateCard(self, content, stack, w)
    if not ns:GetSubsystem("NameplateQuestIcons") then return end
    local card = stack(self:CreateGroup(content, L["Nameplate Quest Icons"]))

    local function npLayoutSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.general[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.general[key] = value end
                local QI = ns:GetSubsystem("NameplateQuestIcons")
                if QI and QI.ApplyLayout then QI:ApplyLayout() end
            end
    end

    local function npGet()
        local QI = ns:GetSubsystem("NameplateQuestIcons")
        return QI and QI.IsEnabled and QI:IsEnabled()
    end
    card:Add(self:CreateCheckbox(content, L["Quest icons on nameplates"], npGet,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.general.questNameplateIcons = value and true or false end
            local QI = ns:GetSubsystem("NameplateQuestIcons")
            if QI and QI.ApplyEnabled then QI:ApplyEnabled() end
            w.sync()
        end,
        L["Shows the \"!\" + count on objective mobs."]))
    w.npOn = npGet

    local function dependent(control)
        card:Add(control, { dependent = true })
        w.np[#w.np + 1] = control
    end
    local NP_PLACEMENT = {
        { value = "LEFT",   label = L["Left"] },
        { value = "RIGHT",  label = L["Right"] },
        { value = "TOP",    label = L["Above"] },
        { value = "BOTTOM", label = L["Below"] },
    }
    local placeGet, placeSet = npLayoutSetting("npIconPlacement")
    dependent(self:CreateRadioGroup(content, L["Position"], NP_PLACEMENT, placeGet, placeSet, nil, nil,
        L["Position"],
        L["Where the quest icon + count sits relative to the enemy nameplate. Move it closer to the health bar to taste."]))

    local szGet, szSet = npLayoutSetting("npIconSize")
    dependent(self:CreateSlider(content, L["Icon size"], 12, 48, 0.5, szGet, szSet))
    local txtGet, txtSet = npLayoutSetting("npIconTextSize")
    dependent(self:CreateSlider(content, L["Count text size"], 8, 24, 0.5, txtGet, txtSet))
    local offXGet, offXSet = npLayoutSetting("npIconOffsetX")
    dependent(self:CreateSlider(content, L["X offset"], -50, 50, 1, offXGet, offXSet,
        L["Nudges the icon and count together left or right from the Position above, so you can slide them right up against the health bar."]))
    local offYGet, offYSet = npLayoutSetting("npIconOffsetY")
    dependent(self:CreateSlider(content, L["Y offset"], -50, 50, 1, offYGet, offYSet,
        L["Nudges the icon and count together up or down from the Position above (positive moves them up)."]))
end

Options:RegisterTab({
    id    = "map",
    title = L["Map"],
    order = 20,
    build = function(self, content)
        local stack = Options.CardStack(self)
        local w = { avail = {}, np = {} }
        w.sync = function()
            local availOn = w.availOn and w.availOn() and true or false
            for _, c in ipairs(w.avail) do self:SetDependent(c, availOn) end
            if w.prec then self:SetDependent(w.prec, w.coordOn() and true or false) end
            local npOn = w.npOn and w.npOn() and true or false
            for _, c in ipairs(w.np) do self:SetDependent(c, npOn) end
        end
        content._sync = w.sync

        mapCard(self, content, stack, w)
        categoryCard(self, content, stack)
        coordinatesCard(self, content, stack, w)
        tooltipsCard(self, content, stack)
        nameplateCard(self, content, stack, w)
        w.sync()
    end,
    refresh = function(_, content)
        if content._sync then content._sync() end
    end,
})
