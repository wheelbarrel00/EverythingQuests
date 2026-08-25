local _, ns = ...

-- Whether a world event is running right now, so the map can stop pinning holiday quests while
-- their event is not on. Nothing in the base gate data marks a holiday: the flag that
-- looked like it did turned out to mark exploration and escort quests, and gating on it hid 191
-- ordinary ones instead.
--
-- The dates live here rather than in Data/ because the lunar new year moves, and this is the file
-- someone has to edit for it. Everything else is fixed or derived.

local M = ns:RegisterSubsystem("QuestHolidays", {})

local function stamp(day, month, hour, minute)
    return month * 1000000 + day * 10000 + hour * 100 + minute
end

local function parseRange(from, to)
    local d1, m1, h1, i1 = from:match("^(%d+)/(%d+) (%d+):(%d+)$")
    local d2, m2, h2, i2 = to:match("^(%d+)/(%d+) (%d+):(%d+)$")
    if not (d1 and d2) then return nil end
    return stamp(tonumber(d1), tonumber(m1), tonumber(h1), tonumber(i1)),
           stamp(tonumber(d2), tonumber(m2), tonumber(h2), tonumber(i2))
end

-- Indices match ns.EQ_HOLIDAY_NAMES. An end earlier than its start wraps the new year, which
-- Winter Veil does. 3 Darkmoon Faire and 8 Lunar Festival are deliberately absent: the faire is
-- derived from the calendar month, and the festival moves.
local EVENTS = {
    [1]  = { "20/9 10:00",  "6/10 10:00"  },
    [2]  = { "27/4 10:00",  "4/5 10:00"   },
    [4]  = { "1/11 10:00",  "3/11 10:00"  },
    [5]  = { "18/10 10:00", "1/11 11:00"  },
    [6]  = { "21/9 00:01",  "27/9 23:59"  },
    [7]  = { "11/2 10:00",  "15/2 10:00"  },
    [9]  = { "21/6 04:00",  "5/7 04:00"   },
    [10] = { "5/4 00:01",   "11/4 23:59"  },
    [11] = { "24/11 01:00", "30/11 23:59" },
    [12] = { "15/12 10:00", "2/1 10:00"   },
}

-- The only thing in this file that needs an edit each year. A year that is not listed shows its
-- quests rather than hiding them, so running off the end of this table costs surplus pins and
-- never a missing one. /eqsprobe available prints the coverage so it cannot rot silently.
local LUNAR = {
    [2026] = { "16/2 06:00", "9/3 06:00"  },
    [2027] = { "5/2 06:00",  "19/2 06:00" },
    [2028] = { "24/1 06:00", "14/2 06:00" },
}

local RANGE, LUNAR_RANGE = {}, {}
for idx, r in pairs(EVENTS) do
    local a, b = parseRange(r[1], r[2])
    if a then RANGE[idx] = { a, b } end
end
for year, r in pairs(LUNAR) do
    local a, b = parseRange(r[1], r[2])
    if a then LUNAR_RANGE[year] = { a, b } end
end

M.DARKMOON, M.LUNAR_FESTIVAL = 3, 8

-- One time read and at most twelve date compares per pass. Without this the gate asks the client
-- for the time once per holiday quest it REACHES, bounded by the 181 in the Era table and the 352
-- in the TBC one. Fewer in practice, because race, class and level reject most of them first.
local _snap, _active = nil, {}

-- Server time where the client offers it. An event flips on realm time rather than on whatever
-- the player's own machine reads, and the two can be a day apart at a boundary.
-- The HOUR is required, not defaulted. Substituting 0 for a missing hour reads as 00:00, which is
-- before every event's start hour, so it would hide an event's quests on its own opening day -
-- the one way this file could fail closed. A clock without an hour is treated as no clock.
local function now()
    local t
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, v = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok then t = v end
    end
    if t and t.month and t.monthDay and type(t.hour) == "number" then
        return stamp(t.monthDay, t.month, t.hour, t.minute or 0),
               t.year, t.monthDay, t.weekday, t.hour
    end
    local d = date and date("*t")
    if not (d and d.month and d.day and type(d.hour) == "number") then return nil end
    return stamp(d.day, d.month, d.hour, d.min or 0), d.year, d.day, d.wday, d.hour
end

local function within(current, from, to)
    if not (current and from and to) then return true end
    if from <= to then return current >= from and current <= to end
    return current >= from or current <= to
end

-- The faire opens on the first Monday falling on or after the 4th and runs seven days from 03:00.
-- That is NOT "the first Monday of the month" and NOT "the Monday of the first full week": both
-- differ from it by a whole week in 3 of the 7 month shapes. Derived from the date, so it never
-- needs an edit. The RULE itself is inherited rather than measured, and has never been checked
-- against the game: a month starting on a Saturday, Sunday or Monday would tell them apart.
local function darkmoonRunning(day, weekday, hour)
    if not (day and weekday) then return true end
    local firstWeekday = (weekday - 1 - (day - 1)) % 7 + 1
    local startDay = (3 - firstWeekday - 4) % 7 + 4
    if day == startDay then return (hour or 0) >= 3 end
    if day == startDay + 7 then return (hour or 0) < 3 end
    return day > startDay and day < startDay + 7
end

local function snapshot()
    if not _snap then
        local current, year, day, weekday, hour = now()
        _snap = { current = current, year = year, day = day, weekday = weekday, hour = hour }
    end
    return _snap
end

-- Called at the top of a pass so a rebuild that spans midnight, or a session left running over
-- one, cannot answer from yesterday.
function M:BeginPass()
    _snap = nil
    for idx in pairs(_active) do _active[idx] = nil end
end

function M:IsEventActive(idx)
    local cached = _active[idx]
    if cached ~= nil then return cached end
    local t = snapshot()
    local answer
    if not t.current then
        answer = true
    elseif idx == M.DARKMOON then
        answer = darkmoonRunning(t.day, t.weekday, t.hour)
    else
        local r = (idx == M.LUNAR_FESTIVAL) and LUNAR_RANGE[t.year] or RANGE[idx]
        answer = (not r) or within(t.current, r[1], r[2])
    end
    _active[idx] = answer
    return answer
end

-- True only for a quest this table knows to be a holiday quest whose event is not running.
-- Everything unreadable answers false, so a surplus pin is the failure rather than a missing one.
function M:IsOutOfSeason(questID)
    local D = ns.CLASSIC_QUEST_HOLIDAY
    if not D or not D.event then return false end
    local idx = D.event[questID]
    if not idx then return false end
    if not self:IsEventActive(idx) then return true end

    -- A few Winter Veil quests open on their own days inside the event rather than with it.
    local w = D.window and D.window[questID]
    if w then
        local d1, m1, d2, m2 = w:match("^(%d+)/(%d+)%-(%d+)/(%d+)$")
        if d1 then
            local current = snapshot().current
            return not within(current,
                stamp(tonumber(d1), tonumber(m1), 0, 0),
                stamp(tonumber(d2), tonumber(m2), 23, 59))
        end
    end
    return false
end

function M:EventName(idx)
    local names = ns.EQ_HOLIDAY_NAMES
    return names and names[idx] or ("event " .. tostring(idx))
end

-- Read by /eqsprobe available. Which events are running, and whether the moving one is covered
-- for this year at all, is the difference between "correctly hidden" and "the table ran out".
function M:ProbeLines()
    self:BeginPass()
    local D = ns.CLASSIC_QUEST_HOLIDAY
    if not D or not D.event then return { "holidays: no table on this flavor" } end
    local n, windows = 0, 0
    for _ in pairs(D.event) do n = n + 1 end
    for _ in pairs(D.window or {}) do windows = windows + 1 end
    local t = snapshot()
    -- Every event fails open on an unreadable clock, so listing them would print all twelve as
    -- running. That is not a thing that can happen, and it means the gate is off, not that the
    -- season is busy. Say which one it is.
    if not t.current then
        return {
            ("holidays: %d quests, %d with their own window"):format(n, windows),
            "  the clock could not be read, so no quest is being hidden",
        }
    end
    local active = {}
    for idx = 1, #(ns.EQ_HOLIDAY_NAMES or {}) do
        if self:IsEventActive(idx) then active[#active + 1] = self:EventName(idx) end
    end
    local lunar = LUNAR_RANGE[t.year or 0] and "covered" or "NOT COVERED, its quests are shown"
    return {
        ("holidays: %d quests, %d with their own window"):format(n, windows),
        ("  lunar festival %s for %s"):format(lunar, tostring(t.year)),
        ("  running now: %s"):format(#active > 0 and table.concat(active, ", ") or "nothing"),
    }
end
