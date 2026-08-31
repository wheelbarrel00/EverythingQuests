local _, ns = ...

local QL = ns:RegisterSubsystem("QuestLink", {})

local LINK_TYPE = "eqquest"
local QUEST_YELLOW = "|cffffff00"

-- CHAT_MSG_BN is not registered. The addon this wire form interoperates with does register it,
-- so a reference arriving there stays plain text for us and becomes a link for them.
local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

local function browserKnows(questID)
    local A = ns.CLASSIC_QUEST_AVAILABLE
    return (A and A.names and A.names[questID]) ~= nil
end

local function byte255(v)
    if type(v) ~= "number" then return nil end
    local n = math.floor(v * 255 + 0.5)
    -- Clamp before %02x, which does not: an out of range component overflows the eight hex
    -- digits the client reads, so it takes a wrong color and renders the rest as text
    if n < 0 then n = 0 elseif n > 255 then n = 255 end
    return n
end

local function levelColor(level)
    local f = _G["GetQuestDifficultyColor"]
    if type(f) == "function" and type(level) == "number" and level > 0 then
        local ok, c = pcall(f, level)
        if ok and type(c) == "table" then
            local r, g, b = byte255(c.r), byte255(c.g), byte255(c.b)
            if r and g and b then return ("|cff%02x%02x%02x"):format(r, g, b) end
        end
    end
    return QUEST_YELLOW
end

-- The display text drops the "(id)", so the other addon's blind gsub filter cannot wrap it twice.
local function hyperlink(questID, level, name)
    local shown = (level and ("[" .. level .. "] " .. name)) or name
    return ("%s|H%s:%d|h[%s]|h|r"):format(levelColor(tonumber(level)), LINK_TYPE, questID, shown)
end

-- A nearer "|H" before this one's "|h" restarts there, or a stray "|H" in front of a real link
-- would swallow it into one range and leave the reference after it unprotected.
local function linkRanges(msg)
    local out, i = {}, 1
    while true do
        local s = msg:find("|H", i, true)
        if not s then break end
        local mid = msg:find("|h", s + 2, true)
        if not mid then break end
        local e = msg:find("|h", mid + 2, true)
        if not e then break end
        local nested = msg:find("|H", s + 2, true)
        if nested and nested < mid then
            i = nested
        else
            out[#out + 1] = s
            out[#out + 1] = e + 1
            i = e + 2
        end
    end
    return out
end

local function inRange(ranges, s, e)
    for i = 1, #ranges, 2 do
        if s <= ranges[i + 1] and e >= ranges[i] then return true end
    end
    return false
end

-- The name class excludes brackets. With "." an earlier "[WTS]" or item link in the line
-- swallowed the match and the real quest was never linked.
-- Cost: TBC 2019 "[Not Used] Tools of the Trade" cannot round trip and stays plain text. It is
-- the only shipped title on either flavor containing a bracket.
local LEVELED = "%[%[(%d+)%] ([^%[%]]-) %((%d+)%)%]"
local BARE    = "%[([^%[%]]-) %((%d+)%)%]"

local function nextRef(msg, cursor)
    local s1, e1, level, name1, id1 = msg:find(LEVELED, cursor)
    local s2, e2, name2, id2 = msg:find(BARE, cursor)
    if s1 and (not s2 or s1 <= s2) then return s1, e1, level, name1, id1 end
    if s2 then return s2, e2, nil, name2, id2 end
end

function QL.Upgrade(msg)
    if type(msg) ~= "string" or not msg:find("(", 1, true) then return nil end

    local ranges = linkRanges(msg)
    local out, cursor, n = {}, 1, 0

    while true do
        local s, e, level, name, id = nextRef(msg, cursor)
        if not s then break end

        local questID = tonumber(id)
        if name ~= "" and questID and browserKnows(questID) and not inRange(ranges, s, e) then
            n = n + 1
            out[n] = msg:sub(cursor, s - 1)
            n = n + 1
            out[n] = hyperlink(questID, level, name)
        else
            n = n + 1
            out[n] = msg:sub(cursor, e)
        end
        cursor = e + 1
    end

    if n == 0 then return nil end
    out[n + 1] = msg:sub(cursor)
    local rebuilt = table.concat(out)
    if rebuilt == msg then return nil end
    return rebuilt
end

local function filter(_, _, msg, ...)
    local rebuilt = QL.Upgrade(msg)
    if not rebuilt then return end
    return false, rebuilt, ...
end

function QL:TextFor(questID)
    local A = ns:GetSubsystem("AvailableQuests")
    local title = A and A.Title and A:Title(questID)
    -- Title answers "Quest #123" for a quest it cannot name, which is not worth sharing
    if type(title) ~= "string" or title == "" or title:find("^Quest #%d+$") then
        title = ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(questID)
    end
    if type(title) ~= "string" or title == "" then return nil end
    return ns.Compat.QuestLinkText(questID, title, A and A.QuestLevel and A:QuestLevel(questID))
end

function QL:Share(questID)
    local active = _G["ChatEdit_GetActiveWindow"]
    local box = type(active) == "function" and active()
    if not box then return false end

    local text = self:TextFor(questID)
    if not text then return false end

    if ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return true end
    if box.Insert then box:Insert(text) return true end
    return false
end

function QL:WantsShare()
    if not IsModifiedClick or not IsModifiedClick("CHATLINK") then return false end
    local active = _G["ChatEdit_GetActiveWindow"]
    return (type(active) == "function" and active()) and true or false
end

local function onRef(link)
    local id = type(link) == "string" and link:match("^" .. LINK_TYPE .. ":(%d+)$")
    if not id then return end
    local questID = tonumber(id)
    -- A chat-link click on any other link type re-inserts it, so ours does too
    if QL:WantsShare() and QL:Share(questID) then return end
    local QB = ns:GetSubsystem("QuestBrowser")
    if QB and QB.Available and QB:Available() and QB.Open then QB:Open(questID) end
end

function QL:OnEnable()
    if not ns.CLASSIC_QUEST_AVAILABLE then return end

    local util = _G["ChatFrameUtil"]
    local add = (type(util) == "table" and util.AddMessageEventFilter)
             or _G["ChatFrame_AddMessageEventFilter"]
    if type(add) == "function" then
        for _, event in ipairs(CHAT_EVENTS) do add(event, filter) end
    end

    -- ChatFrame_OnHyperlinkShow routes every link to SetItemRef, which ignores an unknown type
    hooksecurefunc("SetItemRef", function(link) onRef(link) end)
end
