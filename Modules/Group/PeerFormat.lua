local _, ns = ...

local PeerFormat = {}
ns.PeerFormat = PeerFormat

-- string.byte(s, 1, -1) pushes one value per byte, and Lua 5.1.5 raises past 7997.
local MAX_MESSAGE = 4096

-- No bit library: doubles below 2^53 reproduce 32 bit math, so a stock Lua harness runs this unshimmed.
local floor = math.floor
local schar = string.char
local sbyte = string.byte

local function toSigned32(u)
    if u >= 2147483648 then return u - 4294967296 end
    return u
end

-- The writer's dictionary hash, signed because the writer stores it through a signed 32 bit path.
local function hashOf(str)
    if type(str) ~= "string" or str == "" then return 0 end
    local h = 5381
    for i = 1, #str do
        h = (31 * h + sbyte(str, i)) % 4294967296
    end
    return toSigned32(h)
end

local Stream = {}
Stream.__index = Stream

-- Zero travels as 238, and a literal 237 or 238 travels as 237 followed by 1 or 2.
local CONTROL, ZERO = 237, 238
local CONTROL_VALUE = { CONTROL, ZERO }

local function newStream(bytes)
    return setmetatable({ bin = bytes, pos = 1, len = #bytes }, Stream)
end

function Stream:raw()
    local p = self.pos
    if p > self.len then error("stream overrun", 0) end
    self.pos = p + 1
    return self.bin[p]
end

function Stream:Byte()
    local v = self:raw()
    if v == ZERO then return 0 end
    if v == CONTROL then
        local out = CONTROL_VALUE[self:raw()]
        if not out then error("bad escape", 0) end
        return out
    end
    return v
end

-- One byte per statement, because Lua leaves operand evaluation order unspecified.
function Stream:Short()
    local hi = self:Byte()
    local lo = self:Byte()
    return hi * 256 + lo
end

function Stream:Int()
    local a = self:Byte()
    local b = self:Byte()
    local c = self:Byte()
    local d = self:Byte()
    return toSigned32(((a * 256 + b) * 256 + c) * 256 + d)
end

function Stream:Long()
    local v = 0
    for _ = 1, 8 do v = v * 256 + self:Byte() end
    return v
end

function Stream:Float()
    local a = self:Byte()
    local b = self:Byte()
    local c = self:Byte()
    local d = self:Byte()
    local sign = (a > 127) and -1 or 1
    local expo = (a % 128) * 2 + floor(b / 128)
    local mant = ((b % 128) * 256 + c) * 256 + d
    if expo == 0 and mant == 0 then return sign * 0.0 end
    if expo == 255 then
        if mant == 0 then return sign * math.huge end
        return 0.0 / 0.0
    end
    return sign * math.ldexp(1.0 + mant / 8388608, expo - 127)
end

function Stream:TinyString()
    local len = self:Byte()
    local out = {}
    for i = 1, len do out[i] = schar(self:Byte()) end
    return table.concat(out)
end

function Stream:ShortString()
    local len = self:Short()
    local out = {}
    for i = 1, len do out[i] = schar(self:Byte()) end
    return table.concat(out)
end

local Reader

local function readObject(st, dict)
    local typ = st:Byte()
    -- Above 31 this is not a type at all: the byte carries a small positive number inline.
    if typ > 31 then return typ - 32 end
    local fn = Reader[typ]
    if not fn then error("unknown type " .. typ, 0) end
    return fn(st, dict)
end

-- A hash collision cannot replace a live entry, because only the first appearance is stored.
local function remember(dict, value)
    if type(value) == "string" then
        local h = hashOf(value)
        if dict[h] == nil then dict[h] = value end
    end
    return value
end

local function readTable(st, dict, count)
    local out = {}
    for _ = 1, count do
        local key = remember(dict, readObject(st, dict))
        local value = remember(dict, readObject(st, dict))
        if key ~= nil then out[key] = value end
    end
    return out
end

local function readArray(st, dict, count)
    local out = {}
    for i = 1, count do
        out[i] = remember(dict, readObject(st, dict))
    end
    return out
end

Reader = {
    [1]  = function() return nil end,
    [2]  = function(st) return st:Int() end,
    [3]  = function(st) return -st:Int() end,
    [4]  = function(st) return st:Long() end,
    [5]  = function(st) return -st:Long() end,
    [6]  = function(st) return st:Float() end,
    [7]  = function(st) return st:TinyString() end,
    [8]  = function(st) return st:ShortString() end,
    [9]  = function(st, dict) return dict[st:Int()] end,
    [10] = function(st, dict) local n = st:Byte()  return readTable(st, dict, n) end,
    [11] = function(st, dict) local n = st:Short() return readTable(st, dict, n) end,
    [12] = function(st) return st:Byte() end,
    [13] = function(st) return -st:Byte() end,
    [14] = function(st) return st:Short() end,
    [15] = function(st) return -st:Short() end,
    [16] = function() return false end,
    [17] = function() return true end,
    [18] = function() return nil end,
    [19] = function() return nil end,
    [20] = function(st, dict) local n = st:Byte()  return readArray(st, dict, n) end,
    [21] = function(st, dict) local n = st:Short() return readArray(st, dict, n) end,
    [22] = function(st, dict) local n = st:Int()   return readArray(st, dict, n) end,
}

function PeerFormat.Decode(message)
    if type(message) ~= "string" or message == "" or #message > MAX_MESSAGE then return nil end
    local ok, packet = pcall(function()
        local st = newStream({ sbyte(message, 1, -1) })
        -- The whole message is one key and one value, and that value is the packet.
        return readTable(st, {}, 1)[1]
    end)
    if not ok or type(packet) ~= "table" then return nil end
    return packet
end

-- Only the integer part is compared, as their reader does, so a minor revision still reads.
local MSG_VERSION = 5

local MSG_UPDATE, MSG_REMOVE = 1, 2
local MSG_FULL_LIST, MSG_REQUEST, MSG_FULL_LIST_FLAT, MSG_UPDATE_FLAT = 10, 11, 12, 14

-- Digits and dots only, and short, so no byte needs the escape and their version compare cannot raise.
local VERSION_BYTES = 32

local function inline(n) return schar(32 + n) end
local function tiny(s) return schar(7, #s) .. s end

function PeerFormat.Request(version)
    local ver = type(version) == "string" and version:match("^%d+%.%d+%.%d+") or nil
    if not ver or #ver > VERSION_BYTES then ver = "0.0.0" end
    -- Key 1 holding a table of three pairs, which is the shape their reader takes a packet from.
    return inline(1) .. schar(10, 3)
        .. tiny("ver") .. tiny(ver)
        .. tiny("msgId") .. inline(MSG_REQUEST)
        .. tiny("msgVer") .. inline(MSG_VERSION)
end

-- Message 13, the nearby broadcast, is deliberately not read. It describes strangers, not the group.

local function objective(typeChar, fulfilled, required, finished)
    return {
        typeChar  = typeChar,
        fulfilled = fulfilled,
        required  = required,
        finished  = finished,
    }
end

-- Printable only. string.char raises outside 0 to 255, and a control byte means the stride is off.
local function charOf(byte)
    if type(byte) ~= "number" or byte < 32 or byte > 126 then return nil end
    return schar(byte)
end

-- Lowercase letters only, so peer rows and EQ rows share one type alphabet.
local function normalChar(text)
    if type(text) ~= "string" or text == "" then return nil end
    local c = text:sub(1, 1):lower()
    return c:match("^%l$") and c or nil
end

-- An empty objective list still decodes, because knowing a member carries the quest is worth having.
local function fromDict(rows)
    if type(rows) ~= "table" then return nil end
    local out = {}
    for index, row in pairs(rows) do
        if type(index) ~= "number" or type(row) ~= "table" then return nil end
        local ful = tonumber(row.ful)
        local req = tonumber(row.req)
        if not (ful and req) then return nil end
        out[index] = objective(normalChar(row.typ), ful, req, row.fin and true or false)
    end
    return out
end

local function questFromDict(quest, into)
    if type(quest) ~= "table" then return false end
    local questID = tonumber(quest.id)
    if not questID or questID <= 0 then return false end
    local objectives = fromDict(quest.objectives)
    if not objectives then return false end
    into[questID] = objectives
    return true
end

-- Per objective: source id, type, fulfilled, required. A missing source id travels as 0 to keep the stride.
local function questFromFlat(flat, offset, into)
    local questID = tonumber(flat[offset])
    local count   = tonumber(flat[offset + 1])
    if not questID or questID <= 0 then return nil end
    if not count or count < 0 or count > 64 then return nil end

    local objectives = {}
    local at = offset + 2
    for i = 1, count do
        local typeChar = charOf(tonumber(flat[at + 1]))
        local ful      = tonumber(flat[at + 2])
        local req      = tonumber(flat[at + 3])
        if not (typeChar and ful and req) then return nil end
        objectives[i] = objective(normalChar(typeChar), ful, req, ful == req)
        at = at + 4
    end

    into[questID] = objectives
    return at
end

-- The caller still has to decide the sender is someone it wants to hear from.
function PeerFormat.Read(message)
    local packet = PeerFormat.Decode(message)
    if not packet then return nil end

    local ver = tonumber(packet.msgVer)
    if not ver or floor(ver) ~= MSG_VERSION then return nil end

    local id = tonumber(packet.msgId)
    local quests = {}

    if id == MSG_UPDATE then
        if not questFromDict(packet.quest, quests) then return nil end
        return { kind = "progress", quests = quests }
    end

    if id == MSG_REQUEST then
        local major = type(packet.ver) == "string" and packet.ver:match("^(%d+)") or nil
        return { kind = "request", major = tonumber(major) }
    end

    if id == MSG_REMOVE then
        local questID = tonumber(packet.id)
        if not questID or questID <= 0 then return nil end
        quests[questID] = true
        return { kind = "remove", quests = quests }
    end

    -- A bad quest is skipped rather than failing the message, as their own receiver does.
    if id == MSG_FULL_LIST then
        if type(packet.rawQuestList) ~= "table" then return nil end
        for _, quest in pairs(packet.rawQuestList) do
            questFromDict(quest, quests)
        end
        if next(quests) == nil then return nil end
        return { kind = "progress", quests = quests }
    end

    if id == MSG_FULL_LIST_FLAT or id == MSG_UPDATE_FLAT then
        local flat = packet[1]
        if type(flat) ~= "table" then return nil end
        -- The list form leads with how many quests follow. The single update form does not.
        local offset = 1
        local remaining = 1
        if id == MSG_FULL_LIST_FLAT then
            local count = tonumber(flat[1])
            if not count or count < 0 or count > 128 then return nil end
            remaining = count
            offset = 2
        end
        -- Their sender can count a quest it then writes nothing for, so a short list keeps what arrived.
        for _ = 1, remaining do
            local nextOffset = questFromFlat(flat, offset, quests)
            if not nextOffset then break end
            offset = nextOffset
        end
        if next(quests) == nil then return nil end
        return { kind = "progress", quests = quests }
    end

    return nil
end
