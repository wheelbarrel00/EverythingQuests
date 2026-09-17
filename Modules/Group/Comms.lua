local _, ns = ...

local Comms = ns:RegisterSubsystem("GroupComms", {})

--   <protocol>#P#<class token>#<quest>;<quest>...  a quest is <id>:<t>,<done>,<needed>,<fin>/...
--   <protocol>#R##<id>;<id>...                     quests that have left the sender's log
--   <protocol>#Q##                                 asks everyone to send their whole log
local PROTOCOL = 1

local PREFIX = "EQGroup"
local MSG_PROGRESS, MSG_REMOVE, MSG_REQUEST = "P", "R", "Q"

-- EQ writes only the log request here, because that addon sends a whole log only to whoever asked.
local PEER_PREFIX = "questie"

-- That addon registers this prefix late. Checking sooner means both ask and answers come twice.
local PEER_LOGIN_WAIT = 10
-- Their side answers every request in full with no cooldown of its own, so EQ keeps one.
local PEER_REQUEST_COOLDOWN = 30
-- Their reader takes a major version above this as their own addon. EQ's version is below it.
local PEER_MAJOR_FLOOR = 5

-- Matches that addon, whose broadcasts also stop above 15 members and in battlegrounds.
local MAX_GROUP = 15
-- Their own block cut, which leaves room for the header inside one addon message.
local BLOCK_BYTES = 200

-- AceComm reassembles a multipart message with no ceiling of its own.
local MAX_MESSAGE = 8192
local MAX_CHUNKS = 256

-- Per sender, or one member's reload loop drives a whole quest log onto the wire.
local REPLY_COOLDOWN = 10

local STAGGER_MAX = 3
local BLOCK_INTERVAL = 3

local SEND_DEBOUNCE = 1

-- GROUP_JOINED can fire while the invite is pending, so the join work polls for a real member.
local JOIN_POLL = 0.2
local JOIN_POLL_LIMIT = 50

local GROUP_DISTRIBUTIONS = {
    PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true,
}

local function cfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.group
end

local function data()
    return ns:GetSubsystem("GroupData")
end

-- LibStub is a table with __call, never a function, so a type check for one kills the feature.
local function aceComm()
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, "AceComm-3.0", true)
    return ok and lib or nil
end

function Comms:Transport()
    return aceComm()
end

-- Labeled, not named, because probe output is pasted into public bug reports.
function Comms:Prefixes()
    return {
        { label = "EQGroup", prefix = PREFIX },
        { label = "interop", prefix = PEER_PREFIX },
    }
end

-- Blizzard's own rule: the instance channel only when there is no home group.
local function distribution()
    local home, instance = _G["LE_PARTY_CATEGORY_HOME"], _G["LE_PARTY_CATEGORY_INSTANCE"]
    if home and instance and not IsInGroup(home) and IsInGroup(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    return "PARTY"
end

local function inBattleground()
    if type(UnitInBattleground) ~= "function" then return false end
    local ok, yes = pcall(UnitInBattleground, "player")
    return ok and yes and true or false
end

local function reachable()
    if not IsInGroup() then return false end
    if GetNumGroupMembers() > MAX_GROUP then return false end
    return not inBattleground()
end

local function canSend()
    local c = cfg()
    if not (c and c.partyProgress) then return false end
    return reachable()
end

-- IsInGroup is already true while an invite is pending, before anyone else is in the group.
local function hasMembers()
    return (UnitInParty("party1") or UnitInRaid("raid1")) and true or false
end

local function inRoster(name)
    return (UnitInParty(name) or UnitInRaid(name)) and true or false
end

local function classToken()
    if type(UnitClassBase) == "function" then
        local ok, token = pcall(UnitClassBase, "player")
        if ok and type(token) == "string" then return token end
    end
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, "player")
        if ok and type(token) == "string" then return token end
    end
    return ""
end

-- An unreadable type travels as a question mark, because the counts are still worth having.
local function typeChar(objective)
    local t = objective and objective.type
    if type(t) ~= "string" or t == "" then return "?" end
    t = t:sub(1, 1):lower()
    return t:match("^%l$") and t or "?"
end

local function packQuest(questID, objectives)
    local rows = {}
    for i = 1, #objectives do
        local o = objectives[i]
        -- The client's own flag, because some objectives report finished while their counts read short.
        rows[i] = ("%s,%d,%d,%d"):format(typeChar(o),
                                         tonumber(o.numFulfilled) or 0,
                                         tonumber(o.numRequired) or 0,
                                         o.finished and 1 or 0)
    end
    return ("%d:%s"):format(questID, table.concat(rows, "/"))
end

local function unpackQuest(chunk, into)
    local idText, body = chunk:match("^(%d+):(.*)$")
    local questID = tonumber(idText)
    if not questID or questID <= 0 then return false end

    local objectives = {}
    local n = 0
    if body ~= "" then
        for row in body:gmatch("[^/]+") do
            local t, done, needed, fin = row:match("^([%l?]),(%d+),(%d+),([01])$")
            if not t then return false end
            n = n + 1
            objectives[n] = {
                typeChar  = t ~= "?" and t or nil,
                fulfilled = tonumber(done),
                required  = tonumber(needed),
                finished  = fin == "1",
            }
        end
    end

    into[questID] = objectives
    return true
end

-- What the party was last told, per quest, so a sweep sends only what moved.
local _sent = {}

-- The stamp also stops a login-delayed ask repeating the one a newly joined group already got.
local _peerAskedAt
local _newcomerAskedAt = {}
-- [sender][questID] for rows last written over the other prefix, so its switch spares EQ rows.
local _peerRows = {}
local _eqSenders = {}

function Comms:Send(text, dist, target, priority, prefix)
    local lib = aceComm()
    if not lib then return false end
    -- Guarded, because SendCommMessage raises on a bad argument rather than returning a failure.
    local ok = pcall(lib.SendCommMessage, self, prefix or PREFIX, text, dist, target, priority)
    return ok
end

-- Only whispered replies stagger. A staggered broadcast lets an old block overwrite a newer tick.
function Comms:SendBlocks(blocks, target, priority)
    if #blocks == 0 then return end
    local dist = target and "WHISPER" or distribution()

    if not target or #blocks == 1 then
        for i = 1, #blocks do self:Send(blocks[i], dist, target, priority) end
        return
    end

    -- Checked per block, because sharing can be switched off or the asker can leave mid-reply.
    local function wanted() return canSend() and inRoster(target) end

    C_Timer.After(math.random() * STAGGER_MAX, function()
        if wanted() then self:Send(blocks[1], dist, target, priority) end
        local at = 1
        C_Timer.NewTicker(BLOCK_INTERVAL, function()
            at = at + 1
            local block = blocks[at]
            if block and wanted() then self:Send(block, dist, target, priority) end
        end, #blocks - 1)
    end)
end

local function blocksFor(header, chunks)
    local blocks, current, length = {}, {}, 0
    for i = 1, #chunks do
        local chunk = chunks[i]
        if length > 0 and length + 1 + #chunk > BLOCK_BYTES then
            blocks[#blocks + 1] = header .. table.concat(current, ";")
            current, length = {}, 0
        end
        current[#current + 1] = chunk
        length = length + #chunk + (length > 0 and 1 or 0)
    end
    if length > 0 then blocks[#blocks + 1] = header .. table.concat(current, ";") end
    return blocks
end

-- One priority for all, because the throttle interleaves priorities and a lower one lands late.
function Comms:SendProgress(chunks, target)
    local header = ("%d#%s#%s#"):format(PROTOCOL, MSG_PROGRESS, classToken())
    self:SendBlocks(blocksFor(header, chunks), target, "NORMAL")
end

function Comms:SendRemoval(questIDs)
    if #questIDs == 0 then return end
    local header = ("%d#%s##"):format(PROTOCOL, MSG_REMOVE)
    self:SendBlocks(blocksFor(header, questIDs), nil, "NORMAL")
end

-- Wipes first, because a full answer only adds and a quest dropped while unheard would never leave.
function Comms:SendRequest(atLogin, fromSwitch)
    if not canSend() then return false end
    local D = data()
    if D then D:Wipe() end
    self:Send(("%d#%s##"):format(PROTOCOL, MSG_REQUEST), distribution(), nil, "NORMAL")
    if atLogin then
        C_Timer.After(PEER_LOGIN_WAIT, function() self:SendPeerRequest() end)
    else
        self:SendPeerRequest(fromSwitch)
    end
    return true
end

-- Another listener on this prefix asks the group itself on joining, and its answers reach EQ too.
local function peerListenerPresent()
    local lib = aceComm()
    local registry = lib and rawget(lib, "callbacks")
    local events = type(registry) == "table" and rawget(registry, "events")
    local listeners = type(events) == "table" and rawget(events, PEER_PREFIX)
    if type(listeners) ~= "table" then return false end
    for owner in pairs(listeners) do
        if owner ~= Comms then return true end
    end
    return false
end

function Comms:PeerListenerPresent()
    return peerListenerPresent()
end

-- A switch asks past the listener and the cooldown, because a listener only asks on joining.
function Comms:SendPeerRequest(fromSwitch)
    local c = cfg()
    if not (c and c.readPeerAddons) or not ns.HAS_CLASSIC_SPAWNS then return false end
    if not canSend() or not hasMembers() then return false end
    local now = GetTime()
    if not fromSwitch then
        if peerListenerPresent() then return false end
        if _peerAskedAt and now - _peerAskedAt < PEER_REQUEST_COOLDOWN then return false end
    end
    _peerAskedAt = now
    return self:Send(ns.PeerFormat.Request(ns.VERSION), distribution(), nil, "NORMAL", PEER_PREFIX)
end

-- That addon never volunteers its log, so a newcomer is asked back. Parties only, it answers one by one.
function Comms:AskNewcomer(sender)
    if not canSend() or IsInRaid() then return false end
    local now = GetTime()
    local last = _newcomerAskedAt[sender]
    if last and now - last < PEER_REQUEST_COOLDOWN then return false end
    _newcomerAskedAt[sender] = now
    return self:Send(ns.PeerFormat.Request(ns.VERSION), "WHISPER", sender, "NORMAL", PEER_PREFIX)
end

-- Sharing switched off takes back what the party holds of us, or it stays frozen there.
function Comms:Withdraw()
    local D = data()
    if D then D:Wipe() end
    if not reachable() then return end
    local questIDs = {}
    for questID in pairs(_sent) do questIDs[#questIDs + 1] = tostring(questID) end
    self:SendRemoval(questIDs)
    -- The party holds nothing now, or sharing on while unreachable never resends an unchanged quest.
    wipe(_sent)
end

function Comms:DropPeerRows()
    local D = data()
    if D then
        for name, rows in pairs(_peerRows) do
            if _eqSenders[name] then
                for questID in pairs(rows) do D:RemoveQuest(name, questID) end
            else
                D:DropPlayer(name)
            end
        end
    end
    wipe(_peerRows)
end

function Comms:Sweep(full, target)
    if not canSend() then return 0, 0 end

    local Cache = ns:GetSubsystem("Cache")
    if not Cache then return 0, 0 end

    -- Through Cache, because a second log walk is one more place to misread CollectQuestLog's returns.
    local quests = Cache:All()

    -- A whispered reply must not touch _sent, which records what the whole party was told.
    local track = (target == nil)

    local changed, removed = {}, {}
    local seen = {}

    for questID, q in pairs(quests) do
        seen[questID] = true
        local chunk = packQuest(questID, q.objectives or {})
        if full or _sent[questID] ~= chunk then
            changed[#changed + 1] = chunk
            if track then _sent[questID] = chunk end
        end
    end

    if track then
        for questID in pairs(_sent) do
            if not seen[questID] then
                removed[#removed + 1] = tostring(questID)
                _sent[questID] = nil
            end
        end
    end

    if #removed > 0 then self:SendRemoval(removed) end
    if #changed > 0 then self:SendProgress(changed, target) end
    return #changed, #removed
end

function Comms:FullSweep(target)
    if not target then wipe(_sent) end
    return self:Sweep(true, target)
end

-- UnitInParty is true for you, so a missed self test stores your own packet as a member's.
local function isSelf(sender)
    if type(sender) ~= "string" then return false end
    local name, realm = sender:match("^([^%-]+)%-(.+)$")
    if not name then return sender == UnitName("player") end
    if name ~= UnitName("player") then return false end
    local ownRealm = _G["GetNormalizedRealmName"]
    ownRealm = type(ownRealm) == "function" and ownRealm() or nil
    return ownRealm == nil or realm == ownRealm
end

-- The distribution test refuses a member's message over a channel the group does not own.
local function acceptableSender(dist, sender)
    if type(sender) ~= "string" or sender == "" then return false end
    if not GROUP_DISTRIBUTIONS[dist] then return false end
    if isSelf(sender) then return false end
    if IsInRaid() and UnitInRaid(sender) then return true end
    return UnitInParty(sender) and true or false
end

local _answeredAt = {}

local function forgetPeerRow(sender, questID)
    local rows = _peerRows[sender]
    if rows then rows[questID] = nil end
end

function Comms:OnPacket(message, sender)
    local D = data()
    if not D then return false end

    local protocol, kind, class, body =
        message:match("^(%d+)#(%a)#(%u*)#(.*)$")
    if tonumber(protocol) ~= PROTOCOL then return false end

    if kind == MSG_REQUEST then
        local now = GetTime()
        local last = _answeredAt[sender]
        if last and now - last < REPLY_COOLDOWN then return false end
        _answeredAt[sender] = now
        self:FullSweep(sender)
        return true
    end

    if kind == MSG_REMOVE then
        local any = false
        for idText in body:gmatch("%d+") do
            local questID = tonumber(idText)
            if D:RemoveQuest(sender, questID) then any = true end
            forgetPeerRow(sender, questID)
        end
        return any
    end

    if kind ~= MSG_PROGRESS then return false end

    local quests = {}
    local chunks = 0
    for chunk in body:gmatch("[^;]+") do
        chunks = chunks + 1
        if chunks > MAX_CHUNKS then return false end
        if not unpackQuest(chunk, quests) then return false end
    end
    if next(quests) == nil then return false end

    -- Class only once the body parses, or a truncated packet leaves a member holding no quests.
    if #class <= 16 then D:SetClass(sender, class) end
    _eqSenders[sender] = true
    local now = GetTime()
    local any = false
    for questID, objectives in pairs(quests) do
        if D:SetQuest(sender, questID, objectives, now) then any = true end
        forgetPeerRow(sender, questID)
    end
    return any
end

-- A named quest is replaced outright, so a dropped quest leaves only through the request path's wipe.
function Comms:OnPeerPacket(message, sender, dist)
    local D = data()
    if not D then return false end

    local update = ns.PeerFormat.Read(message)
    if not update then return false end

    -- Never asked back for a whisper, which is how an ask-back arrives, or two EQ users could loop.
    if update.kind == "request" then
        if dist == "WHISPER" or (update.major or 0) <= PEER_MAJOR_FLOOR then return false end
        return self:AskNewcomer(sender)
    end

    if update.kind == "remove" then
        local any = false
        for questID in pairs(update.quests) do
            if D:RemoveQuest(sender, questID) then any = true end
            forgetPeerRow(sender, questID)
        end
        return any
    end

    -- Their class travels only on a message EQ does not read, so the roster supplies it.
    if type(UnitClassBase) == "function" and not D:Class(sender) then
        local ok, token = pcall(UnitClassBase, sender)
        if ok then D:SetClass(sender, token) end
    end

    local rows = _peerRows[sender]
    if not rows then rows = {}; _peerRows[sender] = rows end
    local now = GetTime()
    local any = false
    for questID, objectives in pairs(update.quests) do
        if D:SetQuest(sender, questID, objectives, now) then
            any = true
            rows[questID] = true
        end
    end
    return any
end

-- AceComm passes the prefix first, ahead of the documented message, distribution and sender.
local function receive(handler, wanted)
    return function(_, message, dist, sender)
        if type(message) ~= "string" or #message > MAX_MESSAGE then return end
        if not acceptableSender(dist, sender) then return end
        -- Read per message, so the switch answers without a reload.
        local c = cfg()
        if not (c and c.partyProgress) then return end
        if wanted and not c[wanted] then return end
        -- Guarded, so a malformed packet from another client never reaches the error frame.
        pcall(handler, Comms, message, sender, dist)
    end
end

local function scheduleSweep()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    Events:Debounce("eq-group-sweep", SEND_DEBOUNCE, function() Comms:Sweep(false) end)
end

-- One poll at a time, or a rejoin inside the poll window makes the group answer two requests.
local _joinTicker

local function stopJoinPoll()
    if _joinTicker then
        _joinTicker:Cancel()
        _joinTicker = nil
    end
end

function Comms:OnJoined(atLogin)
    stopJoinPoll()
    local polls = 0
    _joinTicker = C_Timer.NewTicker(JOIN_POLL, function()
        polls = polls + 1
        local settled = hasMembers()
        -- Canceled either way, so a pending invite that never completes cannot poll forever.
        if settled or not IsInGroup() or polls >= JOIN_POLL_LIMIT then
            stopJoinPoll()
            if not settled then return end
            -- Both halves, or everyone already here is blind to the joiner until an objective ticks.
            self:FullSweep()
            self:SendRequest(atLogin)
        end
    end)
end

function Comms:OnLeft()
    stopJoinPoll()
    local D = data()
    if D then
        D:Wipe()
        D:ResetRosterSnapshot()
    end
    wipe(_sent)
    wipe(_answeredAt)
    wipe(_newcomerAskedAt)
    wipe(_peerRows)
    wipe(_eqSenders)
    _peerAskedAt = nil
end

function Comms:OnSettingChanged(key)
    local c = cfg()
    if key == "partyProgress" then
        if c and c.partyProgress then
            -- Not FullSweep, which wipes _sent and so cannot remove a quest dropped while sharing was off.
            self:Sweep(true)
            self:SendRequest(false, true)
        else
            self:Withdraw()
        end
    elseif key == "readPeerAddons" then
        if c and c.readPeerAddons then self:SendPeerRequest(true) else self:DropPeerRows() end
    end
end

function Comms:OnRosterUpdate()
    local D = data()
    if not D then return end
    -- Every roster event, because a same-size swap leaves the member who left in the table.
    D:Prune()
    if D:RosterChanged() then D:Touch() end
    -- Someone who leaves and comes back is a newcomer again, and gets answered again.
    for name in pairs(_newcomerAskedAt) do
        if not inRoster(name) then _newcomerAskedAt[name] = nil end
    end
    for name in pairs(_answeredAt) do
        if not inRoster(name) then _answeredAt[name] = nil end
    end
end

function Comms:OnEnable()
    local lib = aceComm()
    if not lib then return end

    lib:Embed(self)

    local ok = pcall(lib.RegisterComm, self, PREFIX, receive(self.OnPacket))
    if not ok then return end

    pcall(lib.RegisterComm, self, PEER_PREFIX, receive(self.OnPeerPacket, "readPeerAddons"))

    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    Events:On("QUEST_LOG_UPDATE", scheduleSweep)
    Events:On("QUEST_REMOVED", scheduleSweep)
    Events:On("GROUP_JOINED", function() self:OnJoined() end)
    Events:On("GROUP_LEFT", function() self:OnLeft() end)
    Events:On("GROUP_ROSTER_UPDATE", function() self:OnRosterUpdate() end)

    -- GROUP_JOINED does not fire on a reload while already grouped.
    if IsInGroup() then self:OnJoined(true) end
end
