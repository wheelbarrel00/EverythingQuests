local _, ns = ...

local C = ns:RegisterSubsystem("ChainGuideCharacters", {})

local function charKey()
    local name  = UnitName  and UnitName("player")  or "?"
    local realm = GetRealmName and GetRealmName()   or "?"
    return name .. "-" .. realm
end

function C:OnInitialize()
    local DB = ns:GetSubsystem("DB")
    self.cache = DB.chainCache
    self.charKey = charKey()
    -- Keep this two-step - wrapping UnitClass in parens or an "or" truncates it to its first return and the locale-independent classFile ends up nil
    local _, classFile
    if UnitClass then _, classFile = UnitClass("player") end
    local rec = self.cache[self.charKey]
    if not rec then
        rec = {
            name      = UnitName and UnitName("player"),
            class     = classFile,
            faction   = UnitFactionGroup and UnitFactionGroup("player"),
            completed = {},
        }
        self.cache[self.charKey] = rec
    elseif not rec.class then
        rec.class = classFile
    end
    rec.lastSeen = time()              -- stamp the current char each login so PruneStaleRecords spares it
    self.char = rec
end

function C:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_TURNED_IN", function(_, questID)
        if questID and self.char then
            self.char.completed[questID] = true
        end
    end)
end

function C:PruneStaleRecords(now, ttl)
    if not self.cache then return 0 end
    local removed = 0
    for k, v in pairs(self.cache) do
        if type(v) == "table" and v.completed ~= nil and k ~= self.charKey then
            if not v.lastSeen then
                v.lastSeen = now
            elseif now - v.lastSeen > ttl then
                self.cache[k] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

function C:IsQuestCompleted(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return true
    end
    return self.char and self.char.completed and self.char.completed[questID] == true
end

function C:IsQuestActive(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then
        return false
    end
    return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

function C:IsChainComplete(chain)
    if not chain or not chain.items or #chain.items == 0 then return false end
    local DB = ns:GetSubsystem("ChainGuideDatabase")
    for i = #chain.items, 1, -1 do
        local raw = chain.items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = DB:GetVariation(raw)
            return self:IsQuestCompleted(item.id)
        end
    end
    return false
end

-- Faction-paired steps share one overlay cell - counting both would inflate the denominator and block 100%
local _cpStatus = {}
local _cpKeys   = {}
function C:ChainProgress(chain)
    if not chain then return 0, 0, 0 end
    local DB = ns:GetSubsystem("ChainGuideDatabase")
    DB:NormalizeChain(chain)
    local items = chain.items
    if not items or #items == 0 then return 0, 0, 0 end
    local char = DB:CurrentCharacter()
    local complete, active, total = 0, 0, 0
    wipe(_cpStatus)
    local nKeys = 0
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = DB:GetVariation(raw, char)
            local s = self:IsQuestCompleted(item.id) and 2
                      or (self:IsQuestActive(item.id) and 1 or 0)
            local key = (raw.x and raw.y) and (raw.y * 4096 + raw.x) or nil
            if key then
                local prev = _cpStatus[key]
                if prev == nil then
                    nKeys = nKeys + 1
                    _cpKeys[nKeys] = key
                    _cpStatus[key] = s
                elseif s > prev then
                    _cpStatus[key] = s
                end
            else
                total = total + 1
                if s == 2 then complete = complete + 1
                elseif s == 1 then active = active + 1 end
            end
        end
    end
    for k = 1, nKeys do
        total = total + 1
        local s = _cpStatus[_cpKeys[k]]
        if s == 2 then complete = complete + 1
        elseif s == 1 then active = active + 1 end
    end
    return complete, active, total
end
