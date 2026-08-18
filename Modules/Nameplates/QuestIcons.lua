local _, ns = ...

local QI = ns:RegisterSubsystem("NameplateQuestIcons", {})

-- Defaults only - general.npIconSize and general.npIconTextSize override these
local ICON_SIZE    = 24
local DEFAULT_TEXT = 13
local SPACING      = 3
-- Slots built per plate, and the point past which scanning a unit stops paying for itself
local MAX_ICON_SLOTS = 4

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

local activeQuests = {}   -- quest title -> objective text -> entry, for the tooltip path
local questObjList = {}   -- questID -> { entry, ... } in quest log order
local questObjSlot = {}   -- questID -> objective type -> index within that type -> entry
local npcQuests    = {}   -- creature id -> { { quest, slot, otype }, ... }
local itemQuests   = {}   -- lowercased item name -> { entry, ... }
local _logRows = {}

-- Trailing separators, compared whole rather than through a character class. A class would
-- split the multi byte full width colon into three bytes and could eat the tail of a real
-- character in any language that uses one.
local NAME_SEPARATORS = { ":", "\239\188\154" }

-- An item objective's text is the item's own name followed by its count, in the client's own
-- language, so the name is taken from the text rather than from a shipped table. The count is
-- stripped first and the separator second, because the separator is the part that varies by
-- language while "n/n" does not. The whole name has to match and not a substring, or "Okra"
-- would claim every tooltip whose item merely contains it.
local function objectiveItemName(text)
    local name, found = text:gsub("%s*%d+%s*/%s*%d+%s*$", "")
    if found == 0 then return text end
    name = name:gsub("%s+$", "")
    for i = 1, #NAME_SEPARATORS do
        local sep = NAME_SEPARATORS[i]
        if name:sub(-#sep) == sep then
            name = name:sub(1, -#sep - 1):gsub("%s+$", "")
            break
        end
    end
    if name == "" then return text end
    return name
end

local function indexItem(text, entry)
    local key = objectiveItemName(text):lower()
    local list = itemQuests[key]
    if not list then list = {}; itemQuests[key] = list end
    list[#list + 1] = entry
end

-- The shipped kind maps onto the client's own objective type, which is what makes the index
-- meaningful: "the 2nd item objective" rather than "the 2nd objective".
-- Defined in Modules/MapPOI/Provider.lua and read HERE AT RUNTIME, not cached at file scope -
-- the map pins index the same way off the same numbers, and a second copy could drift silently.
-- Reading it late is what keeps the two files free of a load-order dependency.
local function kindType(k) return ns.QUEST_KIND_TYPE and ns.QUEST_KIND_TYPE[k] end

local function rebuildCache()
    wipe(activeQuests)
    wipe(questObjList)
    wipe(questObjSlot)
    wipe(npcQuests)
    wipe(itemQuests)
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
                local objMap, objList, objSlot
                local typeSeen = {}
                for _, o in ipairs(objectives) do
                    -- The slot counts EVERY objective of its type, finished ones included.
                    -- Numbering only the incomplete ones would renumber the rest the moment one
                    -- completed, and the mob table's index would point at the wrong objective.
                    local otype = o.type
                    local slot
                    if otype then
                        slot = typeSeen[otype] or 0
                        typeSeen[otype] = slot + 1
                    end
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
                            -- Carried for the tooltip, which names the objective off this entry
                            entry.text        = text
                            entry.title       = info.title
                            objMap = objMap or {}
                            objMap[text] = entry
                            objList = objList or {}
                            objList[#objList + 1] = entry
                            if otype == "item" then indexItem(text, entry) end
                        end
                    end
                    -- Recorded for EVERY objective, complete ones as false. A finished
                    -- objective has to be a known blank rather than a gap, or a mob whose
                    -- objective is already done falls through to the quest's first incomplete
                    -- one and advertises something it does not drop.
                    if slot then
                        objSlot = objSlot or {}
                        local byIdx = objSlot[otype]
                        if not byIdx then byIdx = {}; objSlot[otype] = byIdx end
                        byIdx[slot] = (text and text ~= "" and objMap and objMap[text]) or false
                    end
                end
                if objMap then
                    activeQuests[info.title] = objMap
                    questObjList[info.questID] = objList
                    questObjSlot[info.questID] = objSlot
                end
            end
        end
    end

    -- The mob table is inverted HERE, over the quest log only, never searched during play.
    -- Shipped it is questID -> mobs, 5011 rows. A 25-quest log inverts to a few hundred
    -- entries. Absent on retail, where the tooltip carries the mapping itself.
    local mobsByQuest = ns.CLASSIC_QUEST_NPCS
    if not mobsByQuest then return end
    for questID in pairs(questObjList) do
        local list = mobsByQuest[questID]
        if list then
            for i = 1, #list do
                local v = list[i]
                local creatureID = v % 10000000
                local t = npcQuests[creatureID]
                if not t then t = {}; npcQuests[creatureID] = t end
                t[#t + 1] = {
                    quest = questID,
                    slot  = math.floor(v / 100000000),
                    otype = kindType(math.floor((v % 100000000) / 10000000)),
                }
            end
        end
    end
end

local _scanSeen = {}

-- Field 6 of a unit GUID is the creature id. Vehicles share that id space and can carry
-- objectives, so both prefixes are accepted and everything else - players, pets - is refused.
local function creatureIDFromUnit(unit)
    local guid = UnitGUID(unit)
    if not (guid and ok(guid)) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Each row names the ONE objective that mob serves, so a mob dropping one of four quest items
-- claims one icon rather than four. The fallback matters: the client's objective order is only
-- assumed to match the dataset's within a type, so where it does not line up this shows the
-- quest's first incomplete objective instead of every one of them.
local function scanByCreature(unit, out)
    local creatureID = creatureIDFromUnit(unit)
    local rows = creatureID and npcQuests[creatureID]
    if not rows then return 0 end
    wipe(_scanSeen)
    local count = 0
    for i = 1, #rows do
        local row = rows[i]
        local byType = row.otype and questObjSlot[row.quest]
        local byIdx  = byType and byType[row.otype]
        local entry
        if byIdx then
            -- false means that objective is already complete and this mob has nothing left to
            -- offer here. Nil means the index ran past what the client reported. Both show
            -- nothing, because guessing another objective is how a mob ends up advertising an
            -- item it does not drop.
            entry = byIdx[row.slot] or nil
        else
            -- The client reported no objectives of this type at all, so the index cannot be
            -- lined up. The mob is still known to serve this quest, so show its first
            -- incomplete objective rather than nothing.
            local list = questObjList[row.quest]
            entry = list and list[1]
        end
        if entry and not _scanSeen[entry] then
            _scanSeen[entry] = true
            count = count + 1
            out[count] = entry
            if count >= MAX_ICON_SLOTS then return count end
        end
    end
    return count
end

local function scanInto(unit, out)
    wipe(out)
    -- A Classic unit tooltip carries NO quest lines at all - measured on a live client against
    -- a mob with an active kill objective in progress, which returned only the name and level.
    -- There is nothing to scrape, so the creature id is the route there. Retail keeps the
    -- tooltip path, which needs no shipped table.
    if not ns.Has.TooltipDataUnit then return scanByCreature(unit, out) end
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
    f.slots = {}
    for i = 1, MAX_ICON_SLOTS do f.slots[i] = buildSlot(f, iconSize, textSize) end
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

-- Split because the cache outlived its first consumer. The nameplate icons and the tooltip
-- lines both read it, and either one can be switched off while the other is on.
local CACHE_EVENTS = {
    QUEST_LOG_UPDATE = onQuestLogUpdate,
    QUEST_ACCEPTED   = onQuestLogUpdate,
    QUEST_REMOVED    = onQuestLogUpdate,
}
local PLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED   = onPlateAdded,
    NAME_PLATE_UNIT_REMOVED = onPlateRemoved,
}

-- ONE cache serves both consumers. A second copy would let a mob's nameplate and its tooltip
-- describe the same objective differently, with each looking correct on its own.
local _holders, _holderCount = {}, 0

function QI:HoldCache(id, want)
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    want = want and true or false
    -- This early return is what makes a repeated call safe, not the counter below it. Removing it
    -- lets one consumer asking twice register the events once and release them twice.
    if (_holders[id] and true or false) == want then return end
    _holders[id] = want or nil
    _holderCount = _holderCount + (want and 1 or -1)

    if want and _holderCount == 1 then
        for event, fn in pairs(CACHE_EVENTS) do Events:On(event, fn) end
        rebuildCache()
    elseif (not want) and _holderCount == 0 then
        for event, fn in pairs(CACHE_EVENTS) do Events:Off(event, fn) end
        wipe(activeQuests)
        wipe(questObjList)
        wipe(questObjSlot)
        wipe(npcQuests)
        wipe(itemQuests)
    end
end

-- The same scan the plates run, so the tooltip names the objective the icon is counting.
function QI:UnitObjectives(unit, out)
    if not unit then wipe(out); return 0 end
    return scanInto(unit, out)
end

-- Every quest waiting on this item, matched on the client's own objective text so it is right
-- in every language without a shipped name table.
function QI:ItemObjectives(itemName, out)
    wipe(out)
    if type(itemName) ~= "string" or itemName == "" then return 0 end
    local list = itemQuests[itemName:lower()]
    if not list then return 0 end
    for i = 1, #list do out[i] = list[i] end
    return #list
end

-- Read by /eqsprobe tooltip. An empty index and an unheld cache look identical from outside.
function QI:CacheHeld()
    return _holderCount > 0
end
function QI:IndexedItemNames()
    local n = 0
    for _ in pairs(itemQuests) do n = n + 1 end
    return n
end

-- The objective text rather than the index key, because the key is lowercased for matching and
-- /eqsprobe has to name an item the player can actually go and look for.
function QI:WantedItems(out, max)
    local n = 0
    for _, list in pairs(itemQuests) do
        local e = list[1]
        if e and e.text then
            n = n + 1
            out[n] = e.text
            if max and n >= max then return n end
        end
    end
    return n
end

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

    self:HoldCache("nameplates", on)

    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if on then
        for event, fn in pairs(PLATE_EVENTS) do Events:On(event, fn) end
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unit = plate.namePlateUnitToken
                if unit then activePlates[unit] = true end
            end
        end
        refreshAllPlates("ENABLE")
    else
        for event, fn in pairs(PLATE_EVENTS) do Events:Off(event, fn) end
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
