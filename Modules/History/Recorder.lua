local _, ns = ...
local L = ns.L

local R = ns:RegisterSubsystem("History", {})

local _charKey
local function charKey()
    if _charKey then return _charKey end
    local name  = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    _charKey = name .. "-" .. realm
    return _charKey
end

local function ensureSV()
    _G.EverythingQuestsHistory = _G.EverythingQuestsHistory or {}
    local sv = _G.EverythingQuestsHistory
    sv.entries        = sv.entries        or {}
    sv.charBackfilled = sv.charBackfilled or {}
    sv.goldDaily      = sv.goldDaily      or {}
    sv.accepted       = sv.accepted       or {}
    sv.abandoned      = sv.abandoned      or {}
    sv.abandonCount   = sv.abandonCount   or {}
    sv.levels         = sv.levels         or {}
    return sv
end

-- Stored timestamps are UTC epoch, so a shifted local day must be rendered back with date("!...") or it shifts twice
-- Forcing isdst=false on both broken-down times cancels the standard-time error so the offset stays DST-correct
local function tzOffset()
    local now = time()
    local u, l = date("!*t", now), date("*t", now)
    u.isdst, l.isdst = false, false
    return time(l) - time(u)
end
local function localDay(t, off)
    return math.floor((t + (off or tzOffset())) / 86400)
end

local MAX_SNAPSHOTS = 3
local function ensureBackupSV()
    _G.EverythingQuestsHistoryBackups = _G.EverythingQuestsHistoryBackups or {}
    local b = _G.EverythingQuestsHistoryBackups
    b.snapshots      = b.snapshots      or {}
    b.lastKnownCount = b.lastKnownCount or 0
    b.lastCounts     = b.lastCounts     or {}
    return b
end

-- Every stored field must be listed here. This copy is what a backup restore writes back over
-- sv.entries, so an omitted field survives normal play and is erased by the restore.
local function copyEntries(src)
    local out = {}
    for i = 1, #src do
        local e = src[i]
        out[i] = { q = e.q, t = e.t, n = e.n, c = e.c, z = e.z, k = e.k,
                   xp = e.xp, m = e.m, d = e.d }
    end
    return out
end

local function copyCharLedger(src)
    local out = {}
    if not src then return out end
    for key, inner in pairs(src) do
        local t = {}
        for k, v in pairs(inner) do
            if type(v) == "table" then
                local row = {}
                for rk, rv in pairs(v) do row[rk] = rv end
                t[k] = row
            else
                t[k] = v
            end
        end
        out[key] = t
    end
    return out
end

local function copySet(src)
    local out = {}
    if src then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function charTable(parent, key)
    local t = parent[key]
    if not t then t = {}; parent[key] = t end
    return t
end

local function countForChar(entries, key)
    local n = 0
    for i = 1, #entries do
        if entries[i].c == key then n = n + 1 end
    end
    return n
end

local function enabled()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.history.enabled ~= false
end

local function retention()
    local DB = ns:GetSubsystem("DB")
    local n = DB and DB.db.profile.history.retention
    return tonumber(n) or 5000
end

function R:OnInitialize()
    self.sv = ensureSV()
    self.backups = ensureBackupSV()
    -- Core/Init.lua xpcalls this and enables the subsystem regardless, so anything the event
    -- handlers touch has to exist before the first line that can raise
    self._giveUp = {}
    self._turnedIn = {}

    self._loadNotice = self:_guardOnLoad()

    self._completion = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        self:_updateCompletion(entries[i].q, entries[i].t or 0)
    end
end

local function resolveTitle(qid)
    return ns.Util.QuestTitle(qid)
end
R._resolveTitle = resolveTitle

function R:_updateCompletion(qid, t)
    if not qid then return end
    local cur = self._completion[qid]
    if not cur or (t > 0 and t > cur) or (cur == 0 and t > 0) then
        self._completion[qid] = t
    end
end

function R:GetCompletionTime(questID)
    return self._completion and self._completion[questID]
end

function R:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    Events:On("QUEST_TURNED_IN", function(_, questID, xpReward, moneyReward)
        self:MarkTurnedIn(questID)
        if not enabled() then return end
        self:Record(questID, xpReward, moneyReward)
    end)

    -- Classic passes questLogIndex first and retail passes the id alone, so the id is last on both
    Events:On("QUEST_ACCEPTED", function(_, a, b)
        self:RecordAccept(b or a)
    end)
    Events:On("QUEST_REMOVED", function(_, questID)
        self:RecordAbandon(questID)
    end)
    Events:On("PLAYER_LEVEL_UP", function(_, level)
        self:RecordLevel(level)
    end)

    self._moneyBaseline = (GetMoney and GetMoney()) or 0
    Events:On("PLAYER_MONEY", function()
        self:RecordMoney()
    end)
    Events:On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
        if success then
            self:_fillTitle(questID)
        elseif questID then
            self._giveUp[questID] = true
        end
    end)

    Events:On("PLAYER_LOGOUT", function()
        self:_snapshotToBackup()
    end)

    if self._loadNotice then
        local msg = self._loadNotice
        self._loadNotice = nil
        C_Timer.After(5, function()
            print("|cffEBB706EQ History:|r " .. msg)
        end)
    end

    C_Timer.After(8, function()
        if not enabled() then return end
        self:PruneAccepts()
        local key = charKey()
        if self.sv.charBackfilled[key] then return end
        if countForChar(self.sv.entries, key) > 0 then
            self.sv.charBackfilled[key] = true
            return
        end
        local added = self:Backfill()
        if added > 0 then
            self:RequestMissingTitles()
            print("|cffEBB706EQ History:|r " .. (L["first time seeing |cffffffff%s|r - added %d past completion%s (no dates; future turn-ins are dated)."]):format(
                key, added, added == 1 and "" or "s"))
        end
    end)
end

function R:_bestSnapshot()
    local snaps = self.backups and self.backups.snapshots
    if not snaps then return nil end
    local best
    for i = 1, #snaps do
        local s = snaps[i]
        if s and s.entries and #s.entries > 0
           and (not best or #s.entries > #best.entries) then
            best = s
        end
    end
    return best
end

local function applySnapshot(self, snap)
    self.sv.entries        = copyEntries(snap.entries)
    self.sv.charBackfilled = copySet(snap.charBackfilled)
    self.sv.accepted       = copyCharLedger(snap.accepted)
    self.sv.abandoned      = copyCharLedger(snap.abandoned)
    self.sv.levels         = copyCharLedger(snap.levels)
    self.sv.abandonCount   = copySet(snap.abandonCount)
    self._completion = {}
    self._pendingTitles = nil
    local entries = self.sv.entries
    for i = 1, #entries do
        self:_updateCompletion(entries[i].q, entries[i].t or 0)
    end
    return #entries
end

function R:_guardOnLoad()
    local b = self.backups
    local entries = self.sv.entries
    local loaded = #entries
    local best = self:_bestSnapshot()
    if not best then return nil end

    if (b.lastKnownCount or 0) > 0 and loaded == 0 then
        local n = applySnapshot(self, best)
        return (L["Quest history loaded empty; restored a backup from %s (%d entries)."]):format(
            date("%Y-%m-%d %H:%M", best.ts or 0), n)
    end

    local key = charKey()
    local hadBefore = (b.lastCounts and b.lastCounts[key]) or 0
    if hadBefore > 0
       and countForChar(entries, key) == 0
       and countForChar(best.entries, key) > 0 then
        local n = applySnapshot(self, best)
        return (L["Quest history for %s was missing; restored a backup from %s (%d entries)."]):format(
            key, date("%Y-%m-%d %H:%M", best.ts or 0), n)
    end

    return nil
end

function R:_snapshotToBackup()
    local b = self.backups
    if not b then return end
    local entries = self.sv.entries
    local n = #entries
    if n == 0 then return end

    b.lastKnownCount = n
    local counts = {}
    for i = 1, n do
        local c = entries[i].c
        if c then counts[c] = (counts[c] or 0) + 1 end
    end
    b.lastCounts = counts

    tinsert(b.snapshots, 1, {
        ts             = (GetServerTime and GetServerTime()) or time(),
        count          = n,
        entries        = copyEntries(entries),
        charBackfilled = copySet(self.sv.charBackfilled),
        accepted       = copyCharLedger(self.sv.accepted),
        abandoned      = copyCharLedger(self.sv.abandoned),
        levels         = copyCharLedger(self.sv.levels),
        abandonCount   = copySet(self.sv.abandonCount),
    })
    for i = #b.snapshots, MAX_SNAPSHOTS + 1, -1 do
        b.snapshots[i] = nil
    end
end

function R:RestoreFromBackup()
    local best = self:_bestSnapshot()
    if not best then return 0 end
    return applySnapshot(self, best)
end

function R:BackupInfo()
    local best = self:_bestSnapshot()
    if not best then return nil end
    return { count = #best.entries, ts = best.ts or 0 }
end

-- Cache of quest IDs still missing a title - any mutation of sv.entries must set _pendingTitles nil to invalidate it
local function ensurePendingTitles(self)
    if self._pendingTitles then return self._pendingTitles end
    local set = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.q and (not e.n or e.n == "") then set[e.q] = true end
    end
    self._pendingTitles = set
    return set
end

function R:_fillTitle(questID)
    local pending = ensurePendingTitles(self)
    if not pending[questID] then return end
    local title = resolveTitle(questID)
    if not title then return end
    local touched = false
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.q == questID and (not e.n or e.n == "") then
            e.n = title
            touched = true
        end
    end
    pending[questID] = nil
    if touched then
        local Events = ns:GetSubsystem("Events")
        if Events and Events.Debounce then
            local thunk = self._rerenderThunk
            if not thunk then
                thunk = function()
                    local HF = ns:GetSubsystem("HistoryFrame")
                    if HF and HF.Render then HF:Render() end
                end
                self._rerenderThunk = thunk
            end
            Events:Debounce("eq.history.fillrender", 0.5, thunk)
        end
    end
end

function R:SweepTitles()
    local entries = self.sv.entries
    local touched = false
    for i = 1, #entries do
        local e = entries[i]
        if e.q and (not e.n or e.n == "") then
            local t = resolveTitle(e.q)
            if t then e.n = t; touched = true end
        end
    end
    if touched then
        self._pendingTitles = nil
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Render then HF:Render() end
    end
    return touched
end

local _titleQueue = {}
local _titleTimer

function R:RequestMissingTitles()
    -- The sweep runs first even where the round trip cannot, being the only path that
    -- re-resolves titles on rows already written. On Classic it rests entirely on
    -- QuestUtils_GetQuestName - measured PRESENT on Era, though whether it returns a name
    -- there is still open - because the rung below it in Util.QuestTitle is curated Midnight
    -- data that no Classic TOC lists.
    self:SweepTitles()
    if not ns.Has.QuestDataRequest then return 0 end
    wipe(_titleQueue)
    local seen = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.q and (not e.n or e.n == "")
           and not seen[e.q] and not self._giveUp[e.q] then
            seen[e.q] = true
            _titleQueue[#_titleQueue + 1] = e.q
        end
    end
    local n = #_titleQueue
    if n > 0 then self:_pumpTitles() end
    return n
end

function R:_pumpTitles()
    if not ns.Has.QuestDataRequest then return end
    local BATCH = 10
    local fired = 0
    while #_titleQueue > 0 and fired < BATCH do
        local qid = tremove(_titleQueue)
        C_QuestLog.RequestLoadQuestByID(qid)
        fired = fired + 1
    end
    if #_titleQueue > 0 then
        if not _titleTimer then
            _titleTimer = C_Timer.NewTimer(0.3, function()
                _titleTimer = nil
                self:_pumpTitles()
            end)
        end
    else
        C_Timer.After(3, function() self:SweepTitles() end)
    end
end

function R:_takeAccept(questID)
    local mine = self.sv.accepted[charKey()]
    if not mine then return nil end
    local at = mine[questID]
    mine[questID] = nil
    return at
end

function R:AcceptedAt(questID)
    local mine = self.sv.accepted[charKey()]
    return mine and mine[questID]
end

-- A task, bonus objective or world quest enters and leaves the quest log on its own with no
-- turn-in, so an accept recorded for one would later be read as an abandon nobody made.
local function transientQuest(questID)
    local ql = _G["C_QuestLog"]
    if ql and ql.IsQuestTask then
        local ok, isTask = pcall(ql.IsQuestTask, questID)
        if ok and isTask then return true end
    end
    local isWQ = _G["QuestUtils_IsQuestWorldQuest"]
    if isWQ then
        local ok, yes = pcall(isWQ, questID)
        if ok and yes then return true end
    end
    return false
end

-- The record is cleared even when recording is off. Leaving an older one in place is worse than
-- having none, because the next hand-in then measures a duration from the wrong day.
function R:RecordAccept(questID)
    if not questID then return end
    self._turnedIn[questID] = nil
    local mine = charTable(self.sv.accepted, charKey())
    if not enabled() or transientQuest(questID) then
        mine[questID] = nil
        return
    end
    mine[questID] = (GetServerTime and GetServerTime()) or time()
end

-- QUEST_TURNED_IN always precedes QUEST_REMOVED for a hand-in, so the marker is the only thing
-- separating the two. It is set even when recording is off, or toggling History mid-quest would
-- log a completed quest as abandoned.
function R:MarkTurnedIn(questID)
    if questID then self._turnedIn[questID] = true end
end

local MAX_ABANDONED = 250

function R:RecordAbandon(questID)
    if not questID then return end
    local at = self:_takeAccept(questID)
    if self._turnedIn[questID] then
        self._turnedIn[questID] = nil
        return
    end
    -- Only a quest this addon watched being accepted can be one the player abandoned. Anything
    -- else arriving here is a task, a bonus objective, or a quest that predates recording.
    if not at or not enabled() then return end

    local now = (GetServerTime and GetServerTime()) or time()
    local key = charKey()
    local list = charTable(self.sv.abandoned, key)
    list[#list + 1] = {
        q = questID,
        t = now,
        n = resolveTitle(questID),
        h = math.max(0, now - at),
    }
    while #list > MAX_ABANDONED do table.remove(list, 1) end
    -- The list above is a capped detail buffer, so the total is counted separately or the figure
    -- on the Totals pane silently stops growing at the cap and still reads as a lifetime number.
    self.sv.abandonCount[key] = (self.sv.abandonCount[key] or 0) + 1
end

-- Recorded for the quest journal, which has no surface yet. Nothing reads it back, so it can
-- only ever be missing data rather than a wrong number on a pane.
function R:RecordLevel(level)
    level = tonumber(level)
    if not level or level <= 0 or not enabled() then return end
    local list = charTable(self.sv.levels, charKey())
    local last = list[#list]
    -- A reconnect can replay PLAYER_LEVEL_UP for a level already recorded
    if last and last.l == level then return end
    list[#list + 1] = { l = level, t = (GetServerTime and GetServerTime()) or time() }
end

-- Pruning against an EMPTY log would discard every pending duration, so a log that reports
-- nothing is left alone.
function R:PruneAccepts()
    local mine = self.sv.accepted[charKey()]
    if not mine or not next(mine) then return 0 end

    local rows = {}
    -- CollectQuestLog returns the table FIRST and the highest index filled second
    local _, last = ns.Compat.CollectQuestLog(rows)
    local live, seen = {}, 0
    for i = 1, (last or 0) do
        local info = rows[i]
        if info and info.questID and not info.isHeader then
            live[info.questID] = true
            seen = seen + 1
        end
    end
    if seen == 0 then return 0 end

    local dropped = 0
    for questID in pairs(mine) do
        if not live[questID] then
            mine[questID] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

function R:IsRecording()
    return enabled()
end

function R:AbandonedCount(charFilter)
    local ledger = self.sv.abandonCount
    if not ledger then return 0 end
    if charFilter and charFilter ~= "all" and charFilter ~= "" then
        return ledger[charFilter] or 0
    end
    local n = 0
    for _, v in pairs(ledger) do n = n + (v or 0) end
    return n
end

function R:AbandonedFor(charFilter)
    local out = {}
    local ledger = self.sv.abandoned
    if not ledger then return out end
    if charFilter and charFilter ~= "all" and charFilter ~= "" then
        local list = ledger[charFilter]
        if list then for i = 1, #list do out[#out + 1] = list[i] end end
        return out
    end
    for _, list in pairs(ledger) do
        for i = 1, #list do out[#out + 1] = list[i] end
    end
    return out
end

function R:LevelUpsSince(since, charFilter)
    local ledger = self.sv.levels
    if not ledger then return 0, nil, nil end
    local n, lo, hi = 0, nil, nil
    for ckey, list in pairs(ledger) do
        if not charFilter or charFilter == "all" or charFilter == "" or ckey == charFilter then
            for i = 1, #list do
                local e = list[i]
                if e.l and (not since or (e.t or 0) >= since) then
                    n = n + 1
                    if not lo or e.l < lo then lo = e.l end
                    if not hi or e.l > hi then hi = e.l end
                end
            end
        end
    end
    return n, lo, hi
end

function R:Record(questID, xpReward, moneyReward)
    if not questID then return end
    local now = (GetServerTime and GetServerTime()) or time()
    local entry = {
        q = questID,
        t = now,
        n = resolveTitle(questID),
        c = charKey(),
        z = (GetZoneText and GetZoneText()) or nil,
        k = (C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
             and C_QuestInfoSystem.GetQuestClassification(questID))
            or (C_QuestLog and C_QuestLog.GetQuestClassification
                and C_QuestLog.GetQuestClassification(questID)) or nil,
    }
    if xpReward    and xpReward    > 0 then entry.xp = xpReward    end
    if moneyReward and moneyReward > 0 then entry.m  = moneyReward end

    local acceptedAt = self:_takeAccept(questID)
    if acceptedAt then entry.d = math.max(0, now - acceptedAt) end

    local entries = self.sv.entries
    entries[#entries + 1] = entry
    self._pendingTitles = nil
    self:_updateCompletion(entry.q, entry.t)
    self:_enforceRetention()
end

local GOLD_RETENTION_DAYS = 400

function R:RecordMoney()
    if not GetMoney then return end
    local cur   = GetMoney()
    local delta = cur - (self._moneyBaseline or cur)
    self._moneyBaseline = cur
    if not enabled() then return end
    if delta <= 0 then return end

    local key   = charKey()
    local today = localDay((GetServerTime and GetServerTime()) or time())
    local ledger = self.sv.goldDaily
    local days = ledger[key]
    if not days then days = {}; ledger[key] = days end

    local isNewDay = days[today] == nil
    days[today] = (days[today] or 0) + delta

    if isNewDay then
        local cutoff = today - GOLD_RETENTION_DAYS
        for d in pairs(days) do
            if d < cutoff then days[d] = nil end
        end
    end

    local HF = ns:GetSubsystem("HistoryFrame")
    if HF and HF.frame and HF.frame:IsShown()
       and HF._activeTab == "totals" and HF._statsView == "trends" then
        HF:Render()
    end
end

function R:_enforceRetention()
    local cap = retention()
    if cap <= 0 then return end
    local entries = self.sv.entries
    local n = #entries
    if n <= cap then return end
    local drop = n - cap

    -- Evict undated backfill stubs before dated turn-ins - stubs land at the newest slots, so a plain front-trim would discard real history first
    local stubDrop = 0
    for i = 1, n do
        if (entries[i].t or 0) == 0 then stubDrop = stubDrop + 1 end
    end
    if stubDrop > drop then stubDrop = drop end
    local datedDrop = drop - stubDrop

    local w = 0
    for i = 1, n do
        local e = entries[i]
        local keep = true
        if (e.t or 0) == 0 then
            if stubDrop > 0 then stubDrop = stubDrop - 1; keep = false end
        elseif datedDrop > 0 then
            datedDrop = datedDrop - 1; keep = false
        end
        if keep then
            w = w + 1
            entries[w] = e
        end
    end
    for i = w + 1, n do
        entries[i] = nil
    end
end

local _completedIDs = {}

function R:Backfill()
    local key = charKey()
    local got, total = ns.Compat.CompletedQuestIDs(_completedIDs)
    if total == 0 then return 0 end

    local seen = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local e = entries[i]
        if e.c == key then seen[e.q] = true end
    end

    -- Cap stubs to the room left under retention so a huge backfill cannot push out real dated history
    local cap = retention()
    local room = (cap > 0) and (cap - #entries) or math.huge
    local added = 0
    for i = 1, total do
        if room <= 0 then break end
        local qid = got[i]
        if not seen[qid] then
            entries[#entries + 1] = {
                q = qid,
                t = 0,
                n = resolveTitle(qid),
                c = key,
            }
            self:_updateCompletion(qid, 0)
            added = added + 1
            room = room - 1
        end
    end
    self.sv.charBackfilled[key] = true
    self._pendingTitles = nil
    self:_enforceRetention()
    return added
end

function R:IsBackfilled()
    return self.sv.charBackfilled[charKey()] == true
end

function R:Wipe()
    self.sv.entries        = {}
    self.sv.charBackfilled = {}
    self._completion       = {}
    self._pendingTitles    = nil
    self.sv.goldDaily      = {}
    self.sv.accepted       = {}
    self.sv.abandoned      = {}
    self.sv.abandonCount   = {}
    self.sv.levels         = {}
    self._giveUp           = {}
    self._turnedIn         = {}
    if self.backups then
        self.backups.snapshots      = {}
        self.backups.lastKnownCount = 0
        self.backups.lastCounts     = {}
    end
end

function R:CurrentCharacter()
    return charKey()
end

function R:GetCharacters()
    local set = {}
    local entries = self.sv.entries
    for i = 1, #entries do set[entries[i].c] = true end
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    return list
end

local CLASS_BUCKET = {}
do
    local QC = Enum and Enum.QuestClassification or {}
    if QC.Campaign   then CLASS_BUCKET[QC.Campaign]   = "campaign"   end
    if QC.Questline  then CLASS_BUCKET[QC.Questline]  = "questline"  end
    if QC.Calling    then CLASS_BUCKET[QC.Calling]    = "calling"    end
    if QC.Recurring  then CLASS_BUCKET[QC.Recurring]  = "recurring"  end
    if QC.WorldQuest then CLASS_BUCKET[QC.WorldQuest] = "worldquest" end
end
local function bucketOf(k)
    return (k and CLASS_BUCKET[k]) or "other"
end

local SORT_BUCKET_ORDER = {
    campaign = 1, questline = 2, calling = 3,
    recurring = 4, worldquest = 5, other = 6,
}
function R:Query(filter)
    local entries = self.sv.entries
    local out = {}

    local search = filter and filter.search
    if search and search ~= "" then search = search:lower() else search = nil end
    local wantChar = filter and filter.char
    if wantChar == "all" or wantChar == "" then wantChar = nil end
    local hideBackfilled = filter and filter.hideBackfilled and true or false
    local wantClass = filter and filter.classification
    if wantClass == "all" or wantClass == "" or wantClass == nil then wantClass = nil end

    local minTime = 0
    local dateRange = filter and filter.dateRange
    if dateRange and dateRange ~= "all" then
        local now = (GetServerTime and GetServerTime()) or time()
        if dateRange == "today" then
            local off = tzOffset()
            minTime = localDay(now, off) * 86400 - off
        elseif dateRange == "7d" then
            minTime = now - 7  * 86400
        elseif dateRange == "30d" then
            minTime = now - 30 * 86400
        end
    end

    for i = #entries, 1, -1 do
        local e = entries[i]
        local ok = true
        if wantChar and e.c ~= wantChar then ok = false end
        if ok and search then
            local n = e.n
            if not (n and n:lower():find(search, 1, true)) then ok = false end
        end
        if ok and hideBackfilled and (not e.t or e.t == 0) then ok = false end
        if ok and minTime > 0 then
            if not e.t or e.t < minTime then ok = false end
        end
        if ok and wantClass then
            if bucketOf(e.k) ~= wantClass then ok = false end
        end
        if ok then out[#out + 1] = e end
    end

    local asc    = filter and filter.sortDir == "asc"
    local sortBy = filter and filter.sortBy or "date"
    if sortBy == "name" then
        table.sort(out, function(a, b)
            local na, nb = (a.n or ""):lower(), (b.n or ""):lower()
            if na ~= nb then
                if asc then return na < nb else return na > nb end
            end
            return (a.q or 0) < (b.q or 0)
        end)
    elseif sortBy == "type" then
        table.sort(out, function(a, b)
            local ba = SORT_BUCKET_ORDER[bucketOf(a.k)] or 99
            local bb = SORT_BUCKET_ORDER[bucketOf(b.k)] or 99
            if ba ~= bb then
                if asc then return ba < bb else return ba > bb end
            end
            local ta, tb = a.t or 0, b.t or 0
            if (ta == 0) ~= (tb == 0) then return tb == 0 end
            if ta ~= tb then return ta > tb end
            return (a.q or 0) < (b.q or 0)
        end)
    else
        table.sort(out, function(a, b)
            local ta, tb = a.t or 0, b.t or 0
            if (ta == 0) ~= (tb == 0) then return tb == 0 end
            if ta ~= tb then
                if asc then return ta < tb else return ta > tb end
            end
            return (a.q or 0) < (b.q or 0)
        end)
    end
    return out
end

function R:Streak()
    local entries = self.sv.entries
    if #entries == 0 then return { current = 0, best = 0, total = 0 } end

    local off = tzOffset()
    local days = {}
    local datedCount = 0
    for i = 1, #entries do
        local t = entries[i].t
        if t and t > 0 then
            local d = localDay(t, off)
            if not days[d] then days[d] = true end
            datedCount = datedCount + 1
        end
    end

    local list = {}
    for d in pairs(days) do list[#list + 1] = d end
    table.sort(list, function(a, b) return a > b end)
    if #list == 0 then return { current = 0, best = 0, total = datedCount } end

    local today = localDay((GetServerTime and GetServerTime()) or time())

    local current = 0
    if list[1] == today or list[1] == today - 1 then
        current = 1
        local prev = list[1]
        for i = 2, #list do
            if list[i] == prev - 1 then
                current = current + 1
                prev = list[i]
            else
                break
            end
        end
    end

    local best, run = 0, 1
    for i = 2, #list do
        if list[i] == list[i - 1] - 1 then
            run = run + 1
        else
            if run > best then best = run end
            run = 1
        end
    end
    if run > best then best = run end
    if current > best then best = current end

    return { current = current, best = best, total = datedCount }
end

function R:CompletionMap()
    return self._completion
end

function R:EntryCount()
    return #self.sv.entries
end

function R:Totals()
    local entries = self.sv.entries
    local totalCount, totalXP, totalMoney = 0, 0, 0
    local totalHeld, heldCount = 0, 0
    local byChar = {}
    local topGold, topXP

    for i = 1, #entries do
        local e = entries[i]
        totalCount = totalCount + 1

        if e.d and e.d > 0 then
            totalHeld = totalHeld + e.d
            heldCount = heldCount + 1
        end

        local c = e.c or "?"
        local rec = byChar[c]
        if not rec then
            rec = { count = 0, xp = 0, money = 0 }
            byChar[c] = rec
        end
        rec.count = rec.count + 1

        local xp = e.xp
        if xp and xp > 0 then
            totalXP = totalXP + xp
            rec.xp  = rec.xp  + xp
            if not topXP or xp > (topXP.xp or 0) then topXP = e end
        end
        local m = e.m
        if m and m > 0 then
            totalMoney = totalMoney + m
            rec.money  = rec.money  + m
            if not topGold or m > (topGold.m or 0) then topGold = e end
        end
    end

    return {
        totalCount = totalCount,
        totalXP    = totalXP,
        totalMoney = totalMoney,
        byChar     = byChar,
        topGold    = topGold,
        topXP      = topXP,
        abandoned  = self:AbandonedCount(nil),
        heldCount  = heldCount,
        avgHeld    = (heldCount > 0) and (totalHeld / heldCount) or nil,
        recording  = enabled(),
    }
end

function R:DayCounts(daysBack)
    daysBack = daysBack or 90
    local off = tzOffset()
    local now = (GetServerTime and GetServerTime()) or time()
    local today = localDay(now, off)
    local minDay = today - daysBack + 1
    local counts = {}
    local entries = self.sv.entries
    for i = 1, #entries do
        local t = entries[i].t
        if t and t > 0 then
            local d = localDay(t, off)
            if d >= minDay and d <= today then
                counts[d] = (counts[d] or 0) + 1
            end
        end
    end
    return counts, today, minDay
end

function R:Trends(granularity, charFilter)
    local weekly   = (granularity == "weekly")
    local wantChar = charFilter
    if wantChar == "all" or wantChar == "" then wantChar = nil end
    local off      = tzOffset()
    local now      = (GetServerTime and GetServerTime()) or time()
    local today    = localDay(now, off)
    local nBuckets = weekly and 12 or 30
    local span     = weekly and 7 or 1

    local periods = {}
    for i = 1, nBuckets do
        local hiDay = today - span * (nBuckets - i)
        periods[i] = { day0 = hiDay - span + 1, day1 = hiDay, xp = 0, gold = 0, count = 0 }
    end
    local oldestDay = periods[1].day0

    local function bucketIndex(day)
        if day < oldestDay or day > today then return nil end
        if weekly then return nBuckets - math.floor((today - day) / 7) end
        return nBuckets - (today - day)
    end

    local entries = self.sv.entries
    for k = 1, #entries do
        local e = entries[k]
        local t = e.t
        if t and t > 0 and (not wantChar or e.c == wantChar) then
            local idx = bucketIndex(localDay(t, off))
            if idx then
                local p = periods[idx]
                p.count = p.count + 1
                if e.xp and e.xp > 0 then p.xp = p.xp + e.xp end
            end
        end
    end

    local ledger = self.sv.goldDaily
    if ledger then
        for ckey, days in pairs(ledger) do
            if not wantChar or ckey == wantChar then
                for day, copper in pairs(days) do
                    if copper and copper > 0 then
                        local idx = bucketIndex(day)
                        if idx then periods[idx].gold = periods[idx].gold + copper end
                    end
                end
            end
        end
    end

    local maxXP, maxGold, maxCount = 0, 0, 0
    for i = 1, nBuckets do
        local p = periods[i]
        if p.xp    > maxXP    then maxXP    = p.xp    end
        if p.gold  > maxGold  then maxGold  = p.gold  end
        if p.count > maxCount then maxCount = p.count end
        p.label = date("!%b %d", p.day0 * 86400)
    end

    return {
        periods     = periods,
        maxXP       = maxXP,
        maxGold     = maxGold,
        maxCount    = maxCount,
        granularity = weekly and "weekly" or "daily",
    }
end
