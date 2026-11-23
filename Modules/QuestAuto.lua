local _, ns = ...
local L = ns.L

local QA = ns:RegisterSubsystem("QuestAuto", {})

local DECLINE_LOCKOUT_S = 10
local _declineLockUntil = 0
local _ownDecline = false

-- The client's quest tag ids. Era and Forever have no escort tag, so EQ's own data stands in there
local TAG_PVP, TAG_ESCORT = 41, 84

local function general()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general
end

local function autoAcceptOn()
    local g = general()
    return g and g.autoAcceptQuests == true
end
local function autoTurnInOn()
    local g = general()
    return g and g.autoTurnInQuests == true
end
local function autoConfirmOn()
    local g = general()
    return g and g.autoConfirmGroupQuests == true
end

local function ruleOn(key, default)
    local g = general()
    local v = g and g[key]
    if v == nil then return default end
    return v == true
end

local PAUSE_KEYS = {
    alt   = function() return IsAltKeyDown and IsAltKeyDown() end,
    shift = function() return IsShiftKeyDown and IsShiftKeyDown() end,
    ctrl  = function() return IsControlKeyDown and IsControlKeyDown() end,
}

function QA:PauseKey()
    local g = general()
    local key = g and g.autoQuestPauseKey
    if key == "none" or PAUSE_KEYS[key] then return key end
    return "alt"
end

local function keyHeld()
    local test = PAUSE_KEYS[QA:PauseKey()]
    return (test and test()) and true or false
end

-- Nil for an answer the client will not give, a secret one included
local function readUnit(fn, unit)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, unit)
    local secret = _G.issecretvalue
    if not ok or (secret and secret(v)) then return nil end
    return v
end

local function validID(id)
    return type(id) == "number" and id > 0
end

local function avail()
    return ns:GetSubsystem("AvailableQuests")
end

-- Retail and Forever, whose quest log is C_QuestLog's and whose own windows read the calls Era and TBC lack
local function modernClient()
    return C_QuestLog ~= nil and C_QuestLog.GetInfo ~= nil
end

local function questTag(questID)
    if not validID(questID) then return nil end
    local C = C_QuestLog
    if C and C.GetQuestTagInfo then
        local ok, info = pcall(C.GetQuestTagInfo, questID)
        local id = ok and type(info) == "table" and info.tagID or nil
        return type(id) == "number" and id or nil
    end
    local f = _G.GetQuestTagInfo
    if type(f) ~= "function" then return nil end
    local ok, id = pcall(f, questID)
    return (ok and type(id) == "number") and id or nil
end

-- Daily and weekly quests carry a frequency apart from the repeatable flag, and the accept window brings no list row, so a list's answer is kept for the session
local _repeats = {}

local function rowRepeats(row)
    return row ~= nil and (row.repeatable == true or (type(row.frequency) == "number" and row.frequency > 0))
end

local function noteRepeats(row)
    if row and validID(row.questID) and rowRepeats(row) then _repeats[row.questID] = true end
end

-- Blizzard's own quest icons read Recurring as repeatable, dailies and weeklies among them, on retail and Forever
local function recurring(questID)
    local S, E = C_QuestInfoSystem, _G.Enum
    local want = E and E.QuestClassification and E.QuestClassification.Recurring
    if not (S and S.GetQuestClassification and want) then return false end
    local ok, c = pcall(S.GetQuestClassification, questID)
    return (ok and c == want) and true or false
end

-- The client's word first (a list row, the log's frequency, the Recurring class), else EQ's data where it knows the quest, else IsRepeatableQuest
local function isRepeatable(questID)
    if not validID(questID) then return false end
    if _repeats[questID] then return true end
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache.Get and Cache:Get(questID)
    if q and type(q.frequency) == "number" and q.frequency > 0 then return true end
    if recurring(questID) then return true end
    local A = avail()
    local D = A and A.Data and A:Data()
    if D and D.gates[questID] then
        return (A:IsRepeatable(questID) or (D.daily and D.daily[questID] ~= nil)) and true or false
    end
    local C = C_QuestLog
    if C and C.IsRepeatableQuest then
        local ok, v = pcall(C.IsRepeatableQuest, questID)
        return (ok and v == true) and true or false
    end
    return false
end

-- The client's answer where it has one, which the map's own offer markers use, else EQ's gray floor
local function isTrivial(questID)
    if not validID(questID) then return false end
    local C = C_QuestLog
    if C and C.IsQuestTrivial then
        local ok, v = pcall(C.IsQuestTrivial, questID)
        if ok and type(v) == "boolean" then return v end
    end
    local A = avail()
    local level = A and A.QuestLevel and A:QuestLevel(questID)
    local floor = A and A.TrivialFloor and A:TrivialFloor()
    return (level and floor and level < floor) and true or false
end

local function grayOffer(questID, row)
    return (row and row.isTrivial) and true or isTrivial(questID)
end

-- Offered to the whole group as one player takes it, escorts among them, so accepting it can start an escort at once
local function groupStart(questID, row)
    if row and row.questInfoID == TAG_ESCORT then return true end
    if questTag(questID) == TAG_ESCORT then return true end
    local A = avail()
    return (A and A.StartsForGroup and A:StartsForGroup(questID)) and true or false
end

-- The accept window's own PvP flag, which Blizzard's accept button reads on retail and Forever before it flags you
local function pvpFlagShown()
    local f = _G.QuestFlagsPVP
    if not modernClient() or type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    return (ok and v) and true or false
end

function QA:ReadsPvPFlag()
    return modernClient() and type(_G.QuestFlagsPVP) == "function"
end

-- EQ's data knows battleground and world PvP quests, as the dump carries no PvP flag
local function pvpQuest(questID, row)
    if row and row.questInfoID == TAG_PVP then return true end
    if questTag(questID) == TAG_PVP then return true end
    local A = avail()
    return (A and A.IsPvPQuest and A:IsPvPQuest(questID)) and true or false
end

-- Why a quest is left to the player to accept, or nil. On retail and Forever a quest the accept window flags for PvP is always left to the player, so the game can ask first
local function acceptRule(questID, row, atWindow)
    if ruleOn("autoAcceptSkipGroup", true) and groupStart(questID, row) then return "group" end
    if atWindow and pvpFlagShown() then return "pvp flag" end
    if ruleOn("autoAcceptSkipPvP", false) and pvpQuest(questID, row) then return "pvp" end
    if ruleOn("autoAcceptSkipRepeatable", false) and (rowRepeats(row) or isRepeatable(questID)) then
        return "repeatable"
    end
    if ruleOn("autoAcceptSkipTrivial", true) and grayOffer(questID, row) then return "trivial" end
    return nil
end

local function turnInRule(questID, row)
    if ruleOn("autoTurnInSkipRepeatable", true) and (rowRepeats(row) or isRepeatable(questID)) then
        return "repeatable"
    end
    return nil
end

local function immersionLoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("Immersion")) and true or false
end

function QA:ImmersionLoaded()
    return immersionLoaded()
end

-- One rule for the box and the handlers, the key kept out of DB.defaults so an unset value reads as nil
function QA:DeferToImmersion()
    if not immersionLoaded() then return false end
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general.deferToImmersion
    if v == nil then return true end
    return v and true or false
end

-- One conversation runs from its first quest or gossip window, with one NPC, until none has been open for a moment
local TALK_GAP_S = 1
local _talking, _manualTalk, _talkWith, _talkGen = false, false, nil, 0
local _open = { gossip = false, quest = false }

local function beginTalk(window)
    _talkGen = _talkGen + 1
    _open[window] = true
    local guid = readUnit(_G.UnitGUID, "npc")
    if _talking and not (guid and _talkWith and guid ~= _talkWith) then
        _talkWith = _talkWith or guid
        return
    end
    _talking, _talkWith = true, guid
    _manualTalk = keyHeld()
end

-- The windows' own open and close events, not their frames, which a dialog addon can keep hidden
local function windowClosed(window)
    _open[window] = false
    local gen = _talkGen
    C_Timer.After(TALK_GAP_S, function()
        if gen ~= _talkGen or _open.gossip or _open.quest then return end
        _talking, _manualTalk, _talkWith = false, false, nil
    end)
end

local function gossipClosed() windowClosed("gossip") end
local function questClosed() windowClosed("quest") end

-- The game closes an item's offer, and on retail and Forever an area's quest or any window it cannot show, and its close can reach EQ first
local _closedAt

local function closedByGame(itemID)
    if type(itemID) == "number" and itemID ~= 0 then return true end
    if _closedAt == nil or _closedAt ~= GetTime() then return false end
    -- The quest frame calls CloseQuest on every hide too, so a window the game showed again in this frame is open
    local f = _G.QuestFrame
    return not (f and f.IsShown and f:IsShown())
end

-- The pause key and the lockout after declining, with no bearing on which window is being replaced
local function heldBack()
    if keyHeld() then return true end
    return GetTime() < _declineLockUntil
end

local function paused()
    if _manualTalk or heldBack() then return true end
    -- Immersion loaded, not shown, as it keeps its frame hidden for some events it handles
    if QA:DeferToImmersion() then return true end
    return false
end

-- Walks every row, as reading the first alone once blocked auto-accept. A gray quest is the fallback while gray quests are allowed
local function pickOffer(n, rowAt)
    local fallback
    for i = 1, n do
        local row = rowAt(i)
        if row then
            noteRepeats(row)
            if not acceptRule(row.questID, row) then
                if not grayOffer(row.questID, row) then return i end
                fallback = fallback or i
            end
        end
    end
    return fallback
end

local function onGossipShow()
    beginTalk("gossip")
    if paused() then return end
    if not C_GossipInfo then return end

    if autoTurnInOn() and C_GossipInfo.GetActiveQuests then
        local active = C_GossipInfo.GetActiveQuests()
        if active then
            for i = 1, #active do
                local q = active[i]
                noteRepeats(q)
                if q and q.isComplete and q.questID and not turnInRule(q.questID, q) then
                    C_GossipInfo.SelectActiveQuest(q.questID)
                    return
                end
            end
        end
    end

    if autoAcceptOn() and C_GossipInfo.GetAvailableQuests then
        local rows = C_GossipInfo.GetAvailableQuests()
        local pick = rows and pickOffer(#rows, function(i)
            local row = rows[i]
            return (row and row.questID) and row or nil
        end)
        if pick then C_GossipInfo.SelectAvailableQuest(rows[pick].questID) end
    end
end

-- A quest log or giver list can hold two quests of one name, and then the title names neither
local function onlyMatch(title, ids, nameOf)
    if type(title) ~= "string" or title == "" or not ids then return nil end
    local found
    for _, id in ipairs(ids) do
        if nameOf(id) == title then
            if found then return nil end
            found = id
        end
    end
    return found
end

local function npcID()
    local guid = readUnit(_G.UnitGUID, "npc")
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Era and TBC name a greeting's finished quests by title alone, so the title is looked up in the log
local function activeQuestID(i, title)
    local f = _G.GetActiveQuestID
    if modernClient() and type(f) == "function" then
        local ok, id = pcall(f, i)
        if ok and validID(id) then return id end
    end
    local Cache = ns:GetSubsystem("Cache")
    local quests = Cache and Cache.All and Cache:All()
    if not quests then return nil end
    local ids = {}
    for id in pairs(quests) do ids[#ids + 1] = id end
    return onlyMatch(title, ids, function(id) return quests[id].title end)
end

-- Blizzard's own greeting window reads GetAvailableQuestInfo's flags on TBC and later, never on Era
local function classicGreetingFlags()
    local f, tbc = _G.ClassicExpansionAtLeast, _G.LE_EXPANSION_BURNING_CRUSADE
    if type(f) ~= "function" or tbc == nil then return false end
    local ok, v = pcall(f, tbc)
    return (ok and v) and true or false
end

local function greetingOffer(i, npcQuests)
    local title = GetAvailableTitle and GetAvailableTitle(i)
    if type(title) ~= "string" or title == "" then return nil end
    local row = {}
    local info = _G.GetAvailableQuestInfo
    if type(info) == "function" and modernClient() then
        local ok, trivial, frequency, repeatable, _, questID, _, _, questInfoID = pcall(info, i)
        if ok then
            row.isTrivial, row.frequency, row.repeatable = trivial and true or false, frequency, repeatable and true or false
            row.questID = validID(questID) and questID or nil
            row.questInfoID = questInfoID
        end
    elseif type(info) == "function" and classicGreetingFlags() then
        local ok, trivial, daily, repeatable = pcall(info, i)
        if ok then row.isTrivial, row.repeatable = trivial and true or false, (daily or repeatable) and true or false end
    end
    if not row.questID and npcQuests then
        local A = avail()
        row.questID = onlyMatch(title, npcQuests, function(id) return A:Title(id) end)
    end
    return row
end

local function onQuestGreeting()
    beginTalk("quest")
    if closedByGame() then questClosed() end
    if paused() then return end

    if autoTurnInOn() and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        local n = GetNumActiveQuests() or 0
        for i = 1, n do
            local title, isComplete = GetActiveTitle(i)
            if isComplete and not turnInRule(activeQuestID(i, title)) then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if autoAcceptOn() and GetNumAvailableQuests and SelectAvailableQuest then
        local n = GetNumAvailableQuests() or 0
        local A = avail()
        local giver = npcID()
        local npcQuests = (A and A.QuestsStartedBy and giver) and A:QuestsStartedBy(giver) or nil
        local named = false
        local pick = pickOffer(n, function(i)
            local row = greetingOffer(i, npcQuests)
            named = named or row ~= nil
            return row
        end)
        if pick then
            SelectAvailableQuest(pick)
        elseif not named and n >= 1 then
            -- A list the client names nothing in is opened at its first quest, and the accept window applies the rules
            SelectAvailableQuest(1)
        end
    end
end

local function shownQuestID()
    local f = _G.GetQuestID
    local id = type(f) == "function" and f() or nil
    return type(id) == "number" and id or nil
end

-- The quest window another player opened by sharing a quest, while you are in a battleground
local function battlegroundShare()
    if not ruleOn("declineBattlegroundShares", false) then return false end
    if not readUnit(_G.UnitInBattleground, "player") then return false end
    return readUnit(_G.UnitIsPlayer, "questnpc") == true
end

local function onQuestDetail(_, itemID)
    beginTalk("quest")
    if closedByGame(itemID) then questClosed() end
    if paused() then return end
    if battlegroundShare() then
        local decline = _G.DeclineQuest
        if type(decline) ~= "function" then return end
        local title = _G.GetTitleText and _G.GetTitleText()
        _ownDecline = true
        local ok = pcall(decline)
        _ownDecline = false
        if ok then
            print((L["|cffEBB706EQ|r: declined %s, which another player shared with you in a battleground."])
                :format(title or "?"))
        end
        return
    end
    if not autoAcceptOn() then return end
    if acceptRule(shownQuestID(), nil, true) then return end
    if AcceptQuest then AcceptQuest() end
end

local function onQuestProgress()
    beginTalk("quest")
    if closedByGame() then questClosed() end
    if paused() then return end
    if not autoTurnInOn() then return end
    if turnInRule(shownQuestID()) then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function onQuestComplete()
    beginTalk("quest")
    if closedByGame() then questClosed() end
    if paused() then return end
    if not autoTurnInOn() then return end
    if turnInRule(shownQuestID()) then return end
    if not GetQuestReward then return end

    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n <= 1 then
        -- GetQuestReward index 0 finishes a quest with no reward choice, 1 takes the single option
        GetQuestReward(n == 1 and 1 or 0)
    end
end

-- Immersion is deliberately not consulted. It replaces the quest and gossip windows, and this popup is neither.
local function fromGroupMember(who)
    -- A payload naming nobody falls through to the switch, so a differently shaped payload cannot kill this.
    if type(who) ~= "string" or who == "" then return true end
    return (UnitInParty(who) or UnitInRaid(who)) and true or false
end

-- ConfirmAcceptQuest leaves the popup up, and a full quest log raises the LOG_FULL variant instead.
local ACCEPT_POPUPS = { "QUEST_ACCEPT", "QUEST_ACCEPT_LOG_FULL" }

local function onQuestAcceptConfirm(_, who)
    if heldBack() then return end
    if not autoConfirmOn() then return end
    if not fromGroupMember(who) then return end
    local confirm = _G["ConfirmAcceptQuest"]
    if type(confirm) ~= "function" then return end
    confirm()
    local hide = _G["StaticPopup_Hide"]
    if type(hide) ~= "function" then return end
    for _, name in ipairs(ACCEPT_POPUPS) do pcall(hide, name) end
end

function QA:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("GOSSIP_SHOW",    onGossipShow)
    Events:On("QUEST_GREETING", onQuestGreeting)
    Events:On("QUEST_DETAIL",   onQuestDetail)
    Events:On("QUEST_PROGRESS", onQuestProgress)
    Events:On("QUEST_COMPLETE", onQuestComplete)
    Events:On("QUEST_ACCEPT_CONFIRM", onQuestAcceptConfirm)
    Events:On("GOSSIP_CLOSED",  gossipClosed)
    Events:On("QUEST_FINISHED", questClosed)

    -- Blizzard's own window handlers call CloseQuest before EQ's run, so EQ reads this stamp in the same frame
    if hooksecurefunc and _G.CloseQuest then
        hooksecurefunc("CloseQuest", function() _closedAt = GetTime() end)
    end
    if hooksecurefunc and _G.DeclineQuest then
        hooksecurefunc("DeclineQuest", function()
            -- EQ's own decline of a battleground share is not the player saying no
            if _ownDecline then return end
            _declineLockUntil = GetTime() + DECLINE_LOCKOUT_S
        end)
    end

    self:_askAboutImmersion()
end

-- Asked only of players it changes: Immersion loaded, no answer stored, and auto-questing on
function QA:_askAboutImmersion()
    local DB = ns:GetSubsystem("DB")
    local g = DB and DB.db.profile.general
    if not g or g.deferToImmersion ~= nil or g.immConflictAsked then return end
    if not immersionLoaded() then return end
    if g.autoAcceptQuests ~= true and g.autoTurnInQuests ~= true then return end

    g.immConflictAsked = true
    C_Timer.After(4, function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Immersion is installed. It replaces the quest and gossip windows so you can read them, and EQ's auto-accept and auto-turn-in would click straight past it. Which would you like?"],
            button1 = L["Keep auto-questing"],
            button2 = L["Let Immersion handle it"],
            onAccept = function() g.deferToImmersion = false end,
            onCancel = function() g.deferToImmersion = true end,
        })
    end)
end
