local _, ns = ...

local AN = ns:RegisterSubsystem("Announce", {})
local L = ns.L

-- Plain text: outgoing chat refuses a texture escape, and a raid target token has no English form on ruRU.
local MARK = "[EQ] "
local LOGO = "|TInterface\\AddOns\\EverythingQuests\\Media\\Textures\\eq-logo-v3:0|t "

local GROUP_CHAT_EVENTS = {
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- Until armed the sweep only records baselines, so a quest log still streaming in is not read as progress.
local ARM_DELAY = 10
local SWEEP_DELAY = 0.3
-- QUEST_REMOVED can arrive ahead of QUEST_TURNED_IN, so a removal waits this long before it is an abandon.
local ABANDON_WAIT = 1

local function cfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.announce
end

local function isSelf(author)
    if type(author) ~= "string" then return false end
    return (author:match("^([^%-]+)") or author) == UnitName("player")
end

local function wantsGroup()
    local c = cfg()
    local mode = c and c.channel or "off"
    if mode == "off"   then return false end
    if mode == "raid"  then return IsInRaid() end
    if mode == "party" then return IsInGroup() and not IsInRaid() end
    return IsInGroup()
end

-- Blizzard's own rule: instance chat only with no home group, and RAID only for a home raid.
local function channel()
    local home, instance = _G["LE_PARTY_CATEGORY_HOME"], _G["LE_PARTY_CATEGORY_INSTANCE"]
    if home and instance and not IsInGroup(home) and IsInGroup(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid(home) then return "RAID" end
    return "PARTY"
end

-- World quests and bonus objectives come and go with the area, which is neither an accept nor an abandon.
local function transientQuest(questID)
    if ns.HAS_CLASSIC_SPAWNS then return false end
    local ql = _G["C_QuestLog"]
    if ql and ql.IsQuestTask then
        local ok, isTask = pcall(ql.IsQuestTask, questID)
        if ok and isTask then return true end
    end
    local isWorldQuest = _G["QuestUtils_IsQuestWorldQuest"]
    if isWorldQuest then
        local ok, yes = pcall(isWorldQuest, questID)
        if ok and yes then return true end
    end
    return false
end

-- Cached while the quest is live, because a link can stop resolving once the quest leaves the log.
local _linkText = {}

local function linkFor(questID)
    local QL = ns:GetSubsystem("QuestLink")
    local text = QL and QL.TextFor and QL:TextFor(questID)
    if text then
        _linkText[questID] = text
        return text
    end
    return _linkText[questID]
end

-- A nil answer is not cached, so a title that was not ready is asked for again next sweep.
local function prime(questID)
    if _linkText[questID] == nil then linkFor(questID) end
end

local function sendChat(text, chatType)
    local chatInfo = _G["C_ChatInfo"]
    -- Addons may not message other players during an encounter, a keystone run or a PvP match.
    if chatInfo and chatInfo.InChatMessagingLockdown and chatInfo.InChatMessagingLockdown() then return end
    -- The bare global is only a deprecation fallback, which a client setting leaves undefined.
    local fn = (chatInfo and chatInfo.SendChatMessage) or _G["SendChatMessage"]
    if type(fn) == "function" then pcall(fn, text, chatType) end
end

local function send(body)
    if not body then return end
    local c = cfg()

    if c and c.toSelf then
        print("|cffEBB706Everything Quests:|r " .. body)
    end
    if not wantsGroup() then return end
    sendChat(MARK .. body, channel())
end

local function announceQuest(questID, pattern)
    local link = linkFor(questID)
    if not link then return end
    send(pattern:format(link))
end

-- QUEST_ACCEPTED can fire twice for one accept.
local _announcedAccept = {}
local _turnedIn = {}
local _pendingRemoval = {}
-- Declared above OnTurnedIn, which writes it. Declared lower, that write would make a global.
local _turnInEventSeen = false

-- Highest count seen per objective. An objective already full when first seen announces nothing.
local _seen = {}

-- Until QUEST_TURNED_IN has fired once the completed flag stands in, or a hand-in reads as an abandon.
local function wasHandedIn(questID)
    if _turnedIn[questID] then return true end
    if _turnInEventSeen then return false end
    local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    return type(flagged) == "function" and flagged(questID) or false
end

local function settleRemoval(questID)
    if not _pendingRemoval[questID] then return end
    _pendingRemoval[questID] = nil

    local handedIn = wasHandedIn(questID)
    _turnedIn[questID] = nil

    if not handedIn and not transientQuest(questID) then
        local c = cfg()
        if c and c.abandoned then
            announceQuest(questID, L["Abandoned %s"])
        end
    end
    _linkText[questID] = nil
end

function AN:OnAccepted(questID)
    if not questID then return end
    -- A re-accept settles the removal now, because a hand-in's QUEST_TURNED_IN would already be in.
    settleRemoval(questID)
    _turnedIn[questID] = nil
    if _announcedAccept[questID] then return end
    _announcedAccept[questID] = true
    prime(questID)
    local c = cfg()
    if c and c.accepted and not transientQuest(questID) then
        announceQuest(questID, L["Accepted %s"])
    end
end

function AN:OnTurnedIn(questID)
    if not questID then return end
    _turnedIn[questID] = true
    _turnInEventSeen = true
    local c = cfg()
    if c and c.completed then
        announceQuest(questID, L["Completed %s"])
    end
end

function AN:OnRemoved(questID)
    if not questID then return end
    _seen[questID] = nil
    _announcedAccept[questID] = nil
    _pendingRemoval[questID] = true
    C_Timer.After(ABANDON_WAIT, function() settleRemoval(questID) end)
end

function AN:Sweep()
    local c = cfg()
    -- Nothing can be sent, so the log is not read. Baselines rebuild silently once something can be.
    if not (c and (c.toSelf or (c.channel or "off") ~= "off")) then
        wipe(_seen)
        return
    end

    local Cache = ns:GetSubsystem("Cache")
    if not Cache then return end

    local quests = Cache:All()
    local wanted = self._armed and c.objective

    for questID, q in pairs(quests) do
        prime(questID)
        local seen = _seen[questID]
        if not seen then seen = {}; _seen[questID] = seen end

        local objectives = q.objectives
        for i = 1, #objectives do
            local o = objectives[i]
            local required = tonumber(o.numRequired) or 0
            local fulfilled = tonumber(o.numFulfilled) or 0
            local was = seen[i]

            -- Recorded before sending and never lowered, so neither a failed send nor a stale count re-announces.
            if was == nil or fulfilled > was then seen[i] = fulfilled end

            if wanted and was and was < required and fulfilled >= required then
                local link = linkFor(questID)
                if link and o.text and o.text ~= "" then
                    send(L["%1$s for %2$s"]:format(o.text, link))
                end
            end
        end
    end

    for questID in pairs(_seen) do
        if not quests[questID] then _seen[questID] = nil end
    end
end

function AN:ScheduleSweep()
    if self._sweepPending then return end
    self._sweepPending = true
    C_Timer.After(SWEEP_DELAY, function()
        self._sweepPending = false
        self:Sweep()
    end)
end

-- Matched by shape rather than name: a leading {token} with a label and colon, or a leading icon.
local FOREIGN_MARKERS = {
    "^{[^}]+}%s+[^%s:]+%s?:%s",
    "^|T[^|]+|t%s",
}

-- A player can type a marker too, so a quest reference is required. Item links alone never count.
local function hasQuestReference(msg)
    if msg:find("%(%d+%)%]") then return true end
    if msg:find("|Hquest", 1, true) then return true end
    return msg:find("|Heqquest", 1, true) ~= nil
end

local function isForeignAnnouncement(msg)
    local shaped = false
    for i = 1, #FOREIGN_MARKERS do
        if msg:find(FOREIGN_MARKERS[i]) then shaped = true break end
    end
    if not shaped then return false end
    return hasQuestReference(msg)
end

-- One filter, because the logo swap rewrites the line a separate mute filter would then miss.
local function filter(_, _, msg, author, ...)
    if type(msg) ~= "string" then return end
    local c = cfg()
    -- Your own lines are never hidden, or switching announcements on would look broken.
    local hide = c and c.hideIncoming and not isSelf(author)

    if msg:sub(1, #MARK) == MARK then
        if hide then return true end
        return false, LOGO .. msg:sub(#MARK + 1), author, ...
    end

    if hide and isForeignAnnouncement(msg) then return true end
end

function AN:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    Events:On("QUEST_ACCEPTED", function(_, a, b)
        -- Classic passes questLogIndex first and retail passes the id alone, so the id is last on both
        self:OnAccepted(b or a)
    end)
    Events:On("QUEST_TURNED_IN", function(_, questID) self:OnTurnedIn(questID) end)
    Events:On("QUEST_REMOVED",   function(_, questID) self:OnRemoved(questID) end)
    Events:On("QUEST_LOG_UPDATE", function() self:ScheduleSweep() end)

    C_Timer.After(ARM_DELAY, function() self._armed = true end)

    local util = _G["ChatFrameUtil"]
    local add = (type(util) == "table" and util.AddMessageEventFilter)
             or _G["ChatFrame_AddMessageEventFilter"]
    if type(add) == "function" then
        for _, event in ipairs(GROUP_CHAT_EVENTS) do add(event, filter) end
    end
end
