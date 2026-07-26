local _, ns = ...

local Q = ns:RegisterSubsystem("TrackerQuestSound", {})

-- Midnight can hand back "secret values" that error when indexed by tainted addon code, even though they still report type "string"
local _issecret = _G.issecretvalue

Q.lastComplete = {}
Q.armed = false

local DEDUP_WINDOW_S = 2
local _recentTitles = {}

local function isRecent(title)
    if not title or title == "" then return false end
    local exp = _recentTitles[title]
    if not exp then return false end
    if exp > GetTime() then return true end
    _recentTitles[title] = nil
    return false
end

local function recordRecent(title)
    if not (title and title ~= "") then return end
    local now = GetTime()
    for k, exp in pairs(_recentTitles) do
        if exp <= now then _recentTitles[k] = nil end
    end
    _recentTitles[title] = now + DEDUP_WINDOW_S
end

local function shouldPlay()
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    return DB.db.profile.tracker.questSoundEnabled ~= false
end

local function chosenSound()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.tracker.questCompleteSound or "EQ: Work Complete"
end

local function playSound()
    if not (shouldPlay() and PlaySoundFile) then return end
    local Media = ns:GetSubsystem("Media")
    local file = Media and Media.GetSoundFile and Media:GetSoundFile(chosenSound())
    if file then PlaySoundFile(file, "Master") end
end

local _readyTitles = {}

local function detectTransitions()
    local Cache = ns:GetSubsystem("Cache")
    if not (Cache and Cache.All) then return end
    local quests = Cache:All()

    -- Skip the first pass after login or every already-complete quest fires a sound
    if not Q.armed then
        for id, q in pairs(quests) do
            Q.lastComplete[id] = q.isComplete or false
        end
        Q.armed = true
        return
    end

    local n = 0
    for id, q in pairs(quests) do
        local was = Q.lastComplete[id]
        local now = q.isComplete and true or false
        -- was==false (not `not was`): a first-seen already-complete quest is nil here and must not fire (cold-login false positive).
        if now and was == false then
            local title = q.title or ""
            -- Already played by the instant chat path, so skip it or the debounced pass double-plays
            if not isRecent(title) then
                n = n + 1
                _readyTitles[n] = title
            end
        end
        Q.lastComplete[id] = now
    end
    for id in pairs(Q.lastComplete) do
        if not quests[id] then Q.lastComplete[id] = nil end
    end

    if n > 0 then
        for i = 1, n do
            recordRecent(_readyTitles[i])
            _readyTitles[i] = nil
        end
        playSound()
    end
end

local _completePattern
local function getCompletePattern()
    if _completePattern then return _completePattern end
    local fmt = ERR_QUEST_COMPLETE_S
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local SENTINEL = "\1"
    _completePattern = "^" .. fmt
        :gsub("%%s", SENTINEL)
        :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub(SENTINEL, "(.+)")
        .. "$"
    return _completePattern
end

local function onSystemChat(_, msg)
    -- msg:match on a secret value throws, and the Cache-diff path still catches those quests
    if _issecret and _issecret(msg) then return end
    if type(msg) ~= "string" then return end
    local p = getCompletePattern()
    if not p then return end
    local title = msg:match(p)
    if not title or title == "" then return end
    if isRecent(title) then return end
    recordRecent(title)
    playSound()
end

function Q:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("QUEST_LOG_UPDATE", function()
        Events:Debounce("eq.questsound", 0.2, detectTransitions)
    end)
    Events:On("CHAT_MSG_SYSTEM",  onSystemChat)
end
