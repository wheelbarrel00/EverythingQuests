local _, ns = ...

local QT = ns:RegisterSubsystem("QuestTooltips", {})
local L = ns.L

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
QT.giverLines = 0

local function wanted()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.questTooltips ~= false
end

-- Only where the availability gate loads, so retail never reaches the quest giver lines
local function giversWanted()
    local Avail = ns:GetSubsystem("AvailableQuests")
    if not (Avail and Avail.QuestsStartedBy) then return false end
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.npcQuestTooltips ~= false
end

-- Midnight restricted APIs can hand back secret values that error if compared
local _issecret = _G.issecretvalue
local function readable(v)
    if _issecret then return not _issecret(v) end
    return true
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

local LT = Enum and Enum.TooltipDataLineType
local QUEST_OBJECTIVE = (LT and LT.QuestObjective) or 8
local QUEST_TITLE     = (LT and LT.QuestTitle)     or 17
local QUEST_PLAYER    = (LT and LT.QuestPlayer)    or 18

-- Blizzard's UI hides no quest line of its tooltip data, so data naming a quest is already on screen
local function drawsQuestLines(data)
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" then return false end
    for i = 1, #lines do
        local t = lines[i] and lines[i].type
        if t == QUEST_OBJECTIVE or t == QUEST_TITLE or t == QUEST_PLAYER then return true end
    end
    return false
end

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
    -- Row tables are reused, because the store moves on every update a group member sends
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
    for creatureID, rows in pairs(_partyMobs) do
        if #rows == 0 then _partyMobs[creatureID] = nil end
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

-- The option's tooltip promises five, so change its text with this
local GIVER_MAX = 5

-- The kind both the start and the turn-in tables give a creature, the only source that is a unit
local SOURCE_NPC = 1

-- The game's dialog icons. Its in-progress "?" is an atlas on WoW Forever and a file on Era and TBC, though Era's own dialogs never draw that file
local ICON_OFFER = "|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t "
local ICON_READY = "|TInterface\\GossipFrame\\ActiveQuestIcon:14:14|t "
local WIP_ATLAS  = "SideInProgressquesticon"
local _iconWip

local function wipIcon()
    if not _iconWip then
        local T = _G.C_Texture
        local okA, info = false, nil
        if T and type(T.GetAtlasInfo) == "function" then okA, info = pcall(T.GetAtlasInfo, WIP_ATLAS) end
        _iconWip = (okA and type(info) == "table") and ("|A:" .. WIP_ATLAS .. ":14:14|a ")
                   or "|TInterface\\GossipFrame\\IncompleteQuestIcon:14:14|t "
    end
    return _iconWip
end

local RANK_READY, RANK_WIP, RANK_OFFER = 1, 2, 3
local REPEAT_R, REPEAT_G, REPEAT_B = 0.6, 0.85, 0.6
local MORE_R, MORE_G, MORE_B = 0.6, 0.6, 0.6

local _givers, _giverN, _sorted = {}, 0, {}
local _playerLevel = 0

local function addGiver(rank, questID, level, title, repeatable)
    _giverN = _giverN + 1
    local e = _givers[_giverN]
    if not e then e = {}; _givers[_giverN] = e end
    e.rank, e.questID, e.level, e.title, e.repeatable = rank, questID, level, title, repeatable
end

local function gap(e)
    if not (e.level and e.level > 0) then return math.huge end
    return math.abs(e.level - _playerLevel)
end

-- Nearest your level first, so at the level cap a battlemaster's own quests lead the old brackets Era's and TBC's data leave uncapped
local function giverOrder(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    local ga, gb = gap(a), gap(b)
    if ga ~= gb then return ga < gb end
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    if a.title ~= b.title then return (a.title or "") < (b.title or "") end
    return a.questID < b.questID
end

-- A live answer, or nil where the client has no such call or hides the value
local function liveFlag(fn, questID)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, questID)
    if ok and readable(v) and type(v) == "boolean" then return v end
    return nil
end

-- WoW Forever's cache never reads a failed flag and can keep an untracked quest's complete flag from its last full rebuild, so both are asked live
local function handInRank(questID, q, Avail)
    local CQ = C_QuestLog
    -- A failed quest cannot be handed in
    if q.isFailed or liveFlag(CQ and CQ.IsFailed, questID) then return nil end
    local done = liveFlag(CQ and CQ.IsComplete, questID)
    -- WoW Forever flags a quest with no objectives complete too (measured), so a live answer is final
    if done ~= nil then return done and RANK_READY or RANK_WIP end
    if q.isComplete then return RANK_READY end
    local objs = q.objectives
    if not objs or #objs == 0 then
        -- A quest finished by exploring or a script can have no objective too, and reads complete only once it is done
        if Avail:IsExplorationOrScripted(questID) then return RANK_WIP end
        -- A delivery has no objective to finish, so the hand-in is all that is left
        return RANK_READY
    end
    for i = 1, #objs do
        if not objs[i].finished then return RANK_WIP end
    end
    return RANK_READY
end

local function takesIn(questID, npcID)
    local byMap = ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
    if not byMap then return false end
    for _, list in pairs(byMap) do
        for i = 1, #list do
            local v = list[i]
            if math.floor(v / 1e9) == npcID and math.floor(v / 1e8) % 10 == SOURCE_NPC then return true end
        end
    end
    return false
end

-- The color Era's and TBC's quest log give that level. WoW Forever's log grades each quest through C_PlayerInfo, so it can differ there
local function levelColor(level)
    local f = _G.GetQuestDifficultyColor
    if level and level > 0 and type(f) == "function" then
        local ok, c = pcall(f, level)
        if ok and type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    end
    return TITLE_R, TITLE_G, TITLE_B
end

-- Enemies only, as a neutral NPC you could attack, such as a Booty Bay goblin, still offers quests
local function hostile(unit)
    local f = _G.UnitIsEnemy
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f, "player", unit)
    return ok and readable(v) and v == true
end

local function giverLines(tooltip, unit)
    local Avail = ns:GetSubsystem("AvailableQuests")
    local QI = objectiveCache()
    local npcID = QI and QI.CreatureID and QI:CreatureID(unit)
    if not (Avail and npcID) or hostile(unit) then return 0 end

    _giverN = 0
    local Cache = ns:GetSubsystem("Cache")
    local quests = Cache and Cache:All()
    if quests then
        for questID, q in pairs(quests) do
            local rank = takesIn(questID, npcID) and handInRank(questID, q, Avail)
            if rank then addGiver(rank, questID, q.level, q.title or Avail:Title(questID)) end
        end
    end
    local offers = Avail:QuestsStartedBy(npcID)
    if offers then
        for i = 1, #offers do
            local questID = offers[i]
            if Avail:Offers(questID) then
                addGiver(RANK_OFFER, questID, Avail:QuestLevel(questID), Avail:Title(questID),
                         Avail:IsRepeatable(questID))
            end
        end
    end
    if _giverN == 0 then return 0 end

    _playerLevel = UnitLevel and UnitLevel("player") or 0
    wipe(_sorted)
    for i = 1, _giverN do _sorted[i] = _givers[i] end
    table.sort(_sorted, giverOrder)

    tooltip:AddLine(" ")
    local shown = math.min(_giverN, GIVER_MAX)
    for i = 1, shown do
        local e = _sorted[i]
        local icon = (e.rank == RANK_READY and ICON_READY) or (e.rank == RANK_WIP and wipIcon()) or ICON_OFFER
        local level = (e.level and e.level > 0) and ("[%d] "):format(e.level) or ""
        local r, g, b = levelColor(e.level)
        if e.rank == RANK_OFFER and e.repeatable then
            tooltip:AddDoubleLine(icon .. level .. (e.title or ""), L["Repeatable quest"], r, g, b,
                                  REPEAT_R, REPEAT_G, REPEAT_B)
        else
            tooltip:AddLine(icon .. level .. (e.title or ""), r, g, b)
        end
    end
    local lines = shown + 1
    if _giverN > shown then
        tooltip:AddLine((L["and %d more"]):format(_giverN - shown), MORE_R, MORE_G, MORE_B)
        lines = lines + 1
    end
    return lines
end

local function onUnit(tooltip)
    QT.unitCalls = QT.unitCalls + 1
    if not tooltip then return end
    -- Retail and Forever draw a mob's objective lines from the tooltip data, so EQ adds none of those
    local objectives = wanted() and not ns.Has.TooltipDataUnit
    local givers = giversWanted()
    if not (objectives or givers) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local QI = objectiveCache()
    if objectives and not (QI and QI.UnitObjectives) then objectives = false end
    if not (objectives or givers) then return end
    if type(tooltip.GetUnit) ~= "function" then return end

    local ok, _, unit, tipGUID = pcall(tooltip.GetUnit, tooltip)
    if not ok then return end
    -- GetUnit can answer a name with no unit token for a world mouseover. WoW Forever's names the GUID, so the mouseover stands in only for that unit
    if not unit and UnitExists and UnitExists("mouseover") then
        if type(tipGUID) ~= "string" then
            unit = "mouseover"
        elseif readable(tipGUID) then
            local over = UnitGUID and UnitGUID("mouseover")
            if over and readable(over) and over == tipGUID then unit = "mouseover" end
        end
    end
    -- WoW Forever's token can be secret where it restricts the unit's identity, and UnitGUID refuses it from an addon
    if not (unit and readable(unit)) then return end

    local guid = UnitGUID and UnitGUID(unit)
    if not (guid and readable(guid)) then return end
    -- A post-call follows a fresh build of the tooltip, so only the script hooks can fire twice on one render
    local guarded = QT.route ~= "TooltipDataProcessor"
    if guarded and alreadyAdded(tooltip, guid) then return end

    local added, party = 0, 0
    if objectives then
        local D = groupData()
        local n = QI:UnitObjectives(unit, _entries)
        added, party = addLines(tooltip, n, D)
        party = party + addPartyOnly(tooltip, unit, D, added, added > 0)
        QT.unitLines = QT.unitLines + added
        QT.partyLines = QT.partyLines + party
    end
    local giver = givers and giverLines(tooltip, unit) or 0
    QT.giverLines = QT.giverLines + giver
    -- Never stamp a zero-add pass. It records the base count, and every later render of this unit is refused
    if guarded and added + party + giver > 0 then stamp(tooltip, guid) end
end

local function onItem(tooltip, data)
    QT.itemCalls = QT.itemCalls + 1
    if not (tooltip and wanted()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if drawsQuestLines(data) then return end
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

-- TBC defines TooltipDataProcessor too, but only a tooltip with ProcessInfo ever runs its post-calls
local function installModern()
    local P = _G["TooltipDataProcessor"]
    local T = _G["Enum"] and _G["Enum"].TooltipDataType
    local GT = _G["GameTooltip"]
    if type(P) ~= "table" or type(P.AddTooltipPostCall) ~= "function" then return false end
    if not (T and T.Unit and T.Item) then return false end
    if not (GT and type(GT.ProcessInfo) == "function") then return false end
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
    -- Neither route can be undone, so the hooks go in once and both options are read per tooltip
    if (on or giversWanted()) and self.route == "none" then
        if not installModern() then installLegacy() end
    end
end

function QT:OnEnable()
    self:ApplyEnabled()
end
