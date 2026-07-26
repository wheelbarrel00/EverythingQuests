local _, ns = ...

local Profiler = ns:RegisterSubsystem("Profiler", {})

Profiler.stats   = {}
Profiler.memMode = false

local _active = {}

local function getActive(tag)
    local a = _active[tag]
    if not a then a = {}; _active[tag] = a end
    return a
end

local function getStats(tag)
    local s = Profiler.stats[tag]
    if not s then
        s = { cpuTotal = 0, cpuCount = 0, cpuMax = 0,
              memTotal = 0, memCount = 0, memMax = 0 }
        Profiler.stats[tag] = s
    end
    return s
end

function Profiler:SetMemoryMode(on)
    self.memMode = on and true or false
end

function Profiler:Start(tag)
    local a = getActive(tag)
    if self.memMode then
        collectgarbage("collect")
        a.mem = collectgarbage("count")
    else
        a.mem = nil
    end
    a.cpu = debugprofilestop()
end

function Profiler:Stop(tag)
    local a = _active[tag]
    if not (a and a.cpu) then return end
    local cpuDelta = debugprofilestop() - a.cpu
    local memDelta
    if a.mem then
        collectgarbage("collect")
        memDelta = collectgarbage("count") - a.mem
    end
    a.cpu = nil
    a.mem = nil

    local s = getStats(tag)
    s.cpuTotal = s.cpuTotal + cpuDelta
    s.cpuCount = s.cpuCount + 1
    if cpuDelta > s.cpuMax then s.cpuMax = cpuDelta end
    if memDelta then
        s.memTotal = s.memTotal + memDelta
        s.memCount = s.memCount + 1
        if math.abs(memDelta) > math.abs(s.memMax) then s.memMax = memDelta end
    end
end

function Profiler:Reset()
    wipe(self.stats)
    -- Do not wipe _active - an in-flight Start/Stop pair would lose its start sample and be dropped
end

Profiler._wrapped = {}

local function tableHasMethod(tbl, name)
    return tbl and type(tbl[name]) == "function"
end

function Profiler:Wrap(subsystemName, methodName)
    local tbl = ns:GetSubsystem(subsystemName)
    if not tableHasMethod(tbl, methodName) then return false end

    local key = subsystemName .. "." .. methodName
    if self._wrapped[key] then return true end

    local original = tbl[methodName]
    local tag      = subsystemName .. ":" .. methodName
    local prof     = self
    tbl[methodName] = function(...)
        prof:Start(tag)
        local function done(...) prof:Stop(tag); return ... end
        return done(original(...))
    end
    self._wrapped[key] = { tbl = tbl, method = methodName, original = original }
    return true
end

function Profiler:Unwrap(subsystemName, methodName)
    local key = subsystemName .. "." .. methodName
    local rec = self._wrapped[key]
    if not rec then return false end
    rec.tbl[rec.method] = rec.original
    self._wrapped[key]  = nil
    return true
end

Profiler.HOT_PATHS = {
    { "Tracker",         "Render"        },
    { "Tracker",         "Refresh"       },
    { "TrackerBlocks",   "RenderQuest"   },
    { "TrackerBlocks",   "Sweep"         },
    { "TrackerScenario", "Refresh"       },
    { "WQPanel",         "Refresh"       },
    { "WQSummary",       "Render"        },
    { "WQWorldMap",      "Refresh"       },
    { "WQZoneMap",       "Render"        },
    { "ChainGuide",      "RenderCurrent" },
    { "ChainGuideView",  "Render"        },
    { "HistoryFrame",    "Render"        },
    { "History",         "Query"         },
    { "History",         "Totals"        },
}

function Profiler:AutoInstrument(on)
    if on then
        local wrapped, missing = 0, 0
        for _, p in ipairs(self.HOT_PATHS) do
            if self:Wrap(p[1], p[2]) then wrapped = wrapped + 1 else missing = missing + 1 end
        end
        return wrapped, missing
    else
        local unwrapped = 0
        local keys = {}
        for k in pairs(self._wrapped) do keys[#keys + 1] = k end
        for _, k in ipairs(keys) do
            local rec = self._wrapped[k]
            if rec then
                rec.tbl[rec.method] = rec.original
                self._wrapped[k]    = nil
                unwrapped = unwrapped + 1
            end
        end
        return unwrapped, 0
    end
end

function Profiler:IsAutoInstrumented()
    return next(self._wrapped) ~= nil
end

function Profiler:ListWrapped()
    local out = {}
    for k in pairs(self._wrapped) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function Profiler:Show()
    local title = "|cffEBB706Everything Quests Profile|r"
    print(title .. (self.memMode and " (memory mode ON)" or ""))

    local keys = {}
    for tag in pairs(self.stats) do keys[#keys + 1] = tag end
    if #keys == 0 then
        print("  (no samples — wrap code with Profiler:Start/Stop, then run this again)")
        return
    end
    table.sort(keys, function(a, b)
        return self.stats[a].cpuTotal > self.stats[b].cpuTotal
    end)

    for _, tag in ipairs(keys) do
        local s = self.stats[tag]
        local avgCpu = s.cpuCount > 0 and (s.cpuTotal / s.cpuCount) or 0
        local line = ("  %s — n=%d cpu avg=%.2fms max=%.2fms total=%.2fms"):format(
            tag, s.cpuCount, avgCpu, s.cpuMax, s.cpuTotal)
        if s.memCount > 0 then
            local avgMem = s.memTotal / s.memCount
            line = line .. ("  | mem avg=%+.2fKB max=%+.2fKB"):format(avgMem, s.memMax)
        end
        print(line)
    end
end

local MEMHOG_INTERVAL_S = 1.0
local MEMHOG_BUFFER_N   = 5

Profiler.memhog = {
    active      = false,
    frame       = nil,
    label       = nil,
    lastMem     = 0,
    lastTime    = 0,
    accumulated = 0,
    buf         = {},
    bufHead     = 1,
    bufLen      = 0,
}

local _UpdateMem = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
local _GetMem    = (C_AddOns and C_AddOns.GetAddOnMemoryUsage)    or GetAddOnMemoryUsage

local function memhogTick(_, elapsed)
    local mh = Profiler.memhog
    mh.accumulated = mh.accumulated + elapsed
    if mh.accumulated < MEMHOG_INTERVAL_S then return end
    mh.accumulated = 0

    if not (_UpdateMem and _GetMem and mh.label) then return end
    _UpdateMem()
    local mem = _GetMem("EverythingQuests") or 0
    local now = GetTime()
    local dt  = now - mh.lastTime
    if mh.lastTime > 0 and dt > 0 then
        local rate = (mem - mh.lastMem) / dt
        mh.buf[mh.bufHead] = rate
        mh.bufHead = (mh.bufHead % MEMHOG_BUFFER_N) + 1
        if mh.bufLen < MEMHOG_BUFFER_N then mh.bufLen = mh.bufLen + 1 end

        local sum = 0
        for i = 1, mh.bufLen do sum = sum + (mh.buf[i] or 0) end
        local avg = sum / mh.bufLen
        local label = mh.label
        if mem >= 1024 then
            label:SetText(("EQ %+.1f kB/s | %.2f MB"):format(avg, mem / 1024))
        else
            label:SetText(("EQ %+.1f kB/s | %.0f KB"):format(avg, mem))
        end
    end
    mh.lastMem  = mem
    mh.lastTime = now
end

local function ensureMemHogFrame()
    local mh = Profiler.memhog
    if mh.frame then return mh.frame end

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(190, 26)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.80)

    mh.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mh.label:SetPoint("CENTER")
    mh.label:SetText("EQ memhog: starting...")

    f:SetScript("OnUpdate", memhogTick)
    mh.frame = f
    return f
end

function Profiler:StartMemHog()
    if self.memhog.active then return end
    local f = ensureMemHogFrame()
    if not f then return end
    if _UpdateMem and _GetMem then
        _UpdateMem()
        self.memhog.lastMem = _GetMem("EverythingQuests") or 0
    end
    self.memhog.lastTime    = GetTime()
    self.memhog.accumulated = 0
    self.memhog.bufLen      = 0
    self.memhog.bufHead     = 1
    f:Show()
    self.memhog.active = true
end

function Profiler:StopMemHog()
    if not self.memhog.active then return end
    local f = self.memhog.frame
    if f then f:Hide() end
    self.memhog.active = false
end

function Profiler:ToggleMemHog()
    if self.memhog.active then self:StopMemHog() else self:StartMemHog() end
end
