local _, ns = ...

local QT = ns:RegisterSubsystem("QuestTooltips", {})

-- The nameplates' MAX_ICON_SLOTS, so a mob never lists more of your objectives than its plate shows
local MAX_QUESTS = 4

local TITLE_R, TITLE_G, TITLE_B = 1.00, 0.82, 0.00
local OBJ_R,   OBJ_G,   OBJ_B   = 0.85, 0.85, 0.85

local _entries    = {}
local _seenTitles = {}

-- Read by /eqsprobe tooltip. A route that installed and never fires reads exactly like a route
-- that was never installed, and the two have nothing in common to fix.
QT.route     = "none"
QT.unitCalls, QT.unitLines = 0, 0
QT.itemCalls, QT.itemLines = 0, 0
QT.partyLines = 0

local function wanted()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.questTooltips ~= false
end

-- The nameplate module owns the quest objective cache and its creature inversion. Asking it
-- rather than building a second one is what keeps a mob's plate and its tooltip agreeing.
local function objectiveCache()
    return ns:GetSubsystem("NameplateQuestIcons")
end

local function groupData()
    local D = ns:GetSubsystem("GroupData")
    return D and D.Progress and D or nil
end

local _slot, _shown = {}, {}

local function objectiveKey(questID, otype, slot)
    return ("%s:%s:%s"):format(tostring(questID), tostring(otype), tostring(slot))
end

-- A mob or an item answers "who still needs this", so a member who has finished it is left out.
local function partyLines(tooltip, D, questID, otype, slot, onFirst)
    if not (D and questID and otype and slot) then return 0 end
    wipe(_slot)
    _slot[slot] = true
    local rows, n = D:Progress(questID, otype:sub(1, 1), _slot)
    return ns.Util.AddPartyLines(tooltip, rows, n, false, onFirst)
end

-- Nothing is written until a line is certain, so a quest with nothing outstanding leaves no stray spacer
local function addLines(tooltip, n, D)
    wipe(_seenTitles)
    wipe(_shown)
    local added, party = 0, 0
    for i = 1, n do
        local e = _entries[i]
        if e and e.title and e.text then
            if added == 0 then tooltip:AddLine(" ") end
            if not _seenTitles[e.title] then
                _seenTitles[e.title] = true
                tooltip:AddLine(e.title, TITLE_R, TITLE_G, TITLE_B)
            end
            tooltip:AddLine("- " .. e.text, OBJ_R, OBJ_G, OBJ_B)
            added = added + 1
            _shown[objectiveKey(e.questID, e.otype, e.slot)] = true
            party = party + partyLines(tooltip, D, e.questID, e.otype, e.slot)
            if added >= MAX_QUESTS then break end
        end
    end
    return added, party
end

-- [creatureID] = { questID, packed, ... } over group members' quests. The plates' copy covers only your log
local _partyMobs, _partyRevision = {}, nil

local function partyMobs(D)
    if _partyRevision == D.revision then return _partyMobs end
    -- Emptied rather than dropped, because the store moves on every update a group member sends
    for _, rows in pairs(_partyMobs) do wipe(rows) end
    local mobsByQuest = ns.CLASSIC_QUEST_NPCS
    local ids, n = D:Quests()
    for i = 1, n do
        local list = mobsByQuest and mobsByQuest[ids[i]]
        if list then
            for k = 1, #list do
                local creatureID = list[k] % 10000000
                local rows = _partyMobs[creatureID]
                if not rows then rows = {}; _partyMobs[creatureID] = rows end
                rows[#rows + 1] = ids[i]
                rows[#rows + 1] = list[k]
            end
        end
    end
    _partyRevision = D.revision
    return _partyMobs
end

-- Read off your own quest log in client order, the numbering the mob table's slots use
local function youFinished(q, otype, slot)
    local objs = q and q.objectives
    if not objs then return false end
    local seen = 0
    for i = 1, #objs do
        if objs[i].type == otype then
            if seen == slot then return objs[i].finished == true end
            seen = seen + 1
        end
    end
    return false
end

-- Objectives you finished that members still need, which have no line of yours to sit under
local function addPartyOnly(tooltip, unit, D, blocks, anyLine)
    local QI = objectiveCache()
    local Cache = ns:GetSubsystem("Cache")
    local creatureID = D and Cache and QI and QI.CreatureID and QI:CreatureID(unit)
    local rows = creatureID and partyMobs(D)[creatureID]
    if not rows then return 0 end
    local lines = 0
    for k = 1, #rows, 2 do
        if blocks >= MAX_QUESTS then break end
        local questID, v = rows[k], rows[k + 1]
        local slot = math.floor(v / 100000000)
        local otype = ns.QUEST_KIND_TYPE and ns.QUEST_KIND_TYPE[math.floor((v % 100000000) / 10000000)]
        local key = objectiveKey(questID, otype, slot)
        local q = Cache:Get(questID)
        if otype and not _shown[key] and youFinished(q, otype, slot) then
            _shown[key] = true
            local header = 0
            local added = partyLines(tooltip, D, questID, otype, slot, function()
                if not anyLine then tooltip:AddLine(" "); anyLine = true; header = header + 1 end
                local title = (q and q.title) or ns.Util.QuestTitle(questID, true)
                if not _seenTitles[title] then
                    _seenTitles[title] = true
                    tooltip:AddLine(title, TITLE_R, TITLE_G, TITLE_B)
                    header = header + 1
                end
            end)
            if added > 0 then
                lines = lines + header + added
                blocks = blocks + 1
            end
        end
    end
    return lines
end

-- OnTooltipSetItem can fire twice for one render, which would print the same lines twice. The
-- tooltip's own line count settles it: a genuine second render has cleared what the first pass
-- added, so the count is back below where that pass ended.
local function alreadyAdded(tooltip, key)
    if tooltip.eqTooltipKey ~= key then return false end
    local n = (type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
    return n >= (tooltip.eqTooltipLines or 0)
end

local function stamp(tooltip, key)
    tooltip.eqTooltipKey   = key
    tooltip.eqTooltipLines = (type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
end

local function onUnit(tooltip)
    QT.unitCalls = QT.unitCalls + 1
    if not (tooltip and wanted()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    -- Retail's own unit tooltip already carries these lines, so EQ would print a second copy of
    -- every one. The gate is the Classic mob table's presence, never a build number - only the
    -- flavor TOCs list that file.
    if not ns.CLASSIC_QUEST_NPCS then return end
    local QI = objectiveCache()
    if not (QI and QI.UnitObjectives) then return end
    if type(tooltip.GetUnit) ~= "function" then return end

    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok then return end
    -- GetUnit answers a name with no token for a plain world mouseover, which is the common
    -- case here rather than an edge one.
    if not unit and UnitExists and UnitExists("mouseover") then unit = "mouseover" end
    if not unit then return end

    local guid = UnitGUID and UnitGUID(unit)
    if not guid then return end
    if alreadyAdded(tooltip, guid) then return end

    local D = groupData()
    local n = QI:UnitObjectives(unit, _entries)
    local added, party = addLines(tooltip, n, D)
    party = party + addPartyOnly(tooltip, unit, D, added, added > 0)
    QT.unitLines = QT.unitLines + added
    QT.partyLines = QT.partyLines + party
    -- Never stamp a zero-add pass. It records the base count, and every later render of this unit is refused
    if added + party > 0 then stamp(tooltip, guid) end
end

local function onItem(tooltip)
    QT.itemCalls = QT.itemCalls + 1
    if not (tooltip and wanted()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local QI = objectiveCache()
    if not (QI and QI.ItemObjectives) then return end
    if type(tooltip.GetItem) ~= "function" then return end

    local ok, name = pcall(tooltip.GetItem, tooltip)
    if not (ok and type(name) == "string" and name ~= "") then return end
    if alreadyAdded(tooltip, name) then return end

    local n = QI:ItemObjectives(name, _entries)
    local added, party = addLines(tooltip, n, groupData())
    QT.itemLines = QT.itemLines + added
    QT.partyLines = QT.partyLines + party
    if added + party > 0 then stamp(tooltip, name) end
end

-- Blizzard removed the OnTooltipSetUnit and OnTooltipSetItem scripts in the 10.0.2 tooltip
-- rewrite and replaced them with TooltipDataProcessor. Classic kept the scripts and has neither
-- TooltipDataProcessor nor C_TooltipInfo, which is why Core/Compat.lua feature-detects
-- there, so presence decides the route rather than a build number.
local function installModern()
    local P = _G["TooltipDataProcessor"]
    local T = _G["Enum"] and _G["Enum"].TooltipDataType
    if type(P) ~= "table" or type(P.AddTooltipPostCall) ~= "function" then return false end
    if not (T and T.Unit and T.Item) then return false end
    -- Committed once the surface exists. Installing one half and then falling back would hook
    -- the other surface twice and double its lines.
    QT.route = "TooltipDataProcessor"
    pcall(P.AddTooltipPostCall, T.Unit, onUnit)
    pcall(P.AddTooltipPostCall, T.Item, onItem)
    return true
end

-- Recorded per hook rather than as one flag. HookScript raises on a script the frame does not
-- have, so a partial install is a real outcome, and one that reads exactly like a full one.
QT.hooks = {}

local function installLegacy()
    local any = false
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tip = _G[name]
        if tip and type(tip.HookScript) == "function" then
            for script, fn in pairs({ OnTooltipSetUnit = onUnit, OnTooltipSetItem = onItem }) do
                local ok = pcall(tip.HookScript, tip, script, fn)
                QT.hooks[name .. ":" .. script] = ok
                if ok then any = true end
            end
        end
    end
    if any then QT.route = "OnTooltipSet scripts" end
    return any
end

function QT:ApplyEnabled()
    local on = wanted()
    local QI = objectiveCache()
    if QI and QI.HoldCache then QI:HoldCache("tooltips", on) end
    -- HookScript cannot be undone, so the hooks go in once and the option is read per tooltip
    -- rather than being wired to the installation.
    if on and self.route == "none" then
        if not installModern() then installLegacy() end
    end
end

function QT:OnEnable()
    self:ApplyEnabled()
end
