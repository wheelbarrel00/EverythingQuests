local _, ns = ...

local Session = ns:RegisterSubsystem("Session", {})

local function store()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.char) then return nil end
    DB.char.session = DB.char.session or {}
    return DB.char.session
end

local function now()
    return (GetServerTime and GetServerTime()) or time()
end

function Session:Start()
    local s = store()
    if not s then return end
    s.startTime  = now()
    s.startLevel = (UnitLevel and UnitLevel("player")) or 0
    s.quests     = 0
    s.xp         = 0
    s.gold       = 0
end

function Session:OnInitialize()
    local s = store()
    if s and not s.startTime then self:Start() end
end

function Session:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        if isInitialLogin then self:Start() end
    end)

    Events:On("QUEST_TURNED_IN", function(_, _questID, xpReward, moneyReward)
        local s = store()
        if not s then return end
        s.quests = (s.quests or 0) + 1
        if xpReward    and xpReward    > 0 then s.xp   = (s.xp   or 0) + xpReward    end
        if moneyReward and moneyReward > 0 then s.gold = (s.gold or 0) + moneyReward end
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.frame and HF.frame:IsShown() and HF._activeTab == "session" then
            HF:Render()
        end
    end)
end

function Session:Summary()
    local s = store() or {}
    local startTime  = s.startTime or now()
    local played     = math.max(0, now() - startTime)
    local quests     = s.quests or 0
    local startLevel = s.startLevel or (UnitLevel and UnitLevel("player")) or 0
    local curLevel   = (UnitLevel and UnitLevel("player")) or startLevel

    local abandoned, recording = 0, true
    -- R.sv is assigned in OnInitialize, which Core/Init.lua xpcalls - a raise there leaves the
    -- subsystem present with every method defined and no storage behind them
    local R = ns:GetSubsystem("History")
    if R and R.sv and R.AbandonedFor and R.CurrentCharacter then
        local list = R:AbandonedFor(R:CurrentCharacter())
        for i = 1, #list do
            if (list[i].t or 0) >= startTime then abandoned = abandoned + 1 end
        end
        recording = R:IsRecording()
    end

    return {
        played     = played,
        quests     = quests,
        xp         = s.xp or 0,
        gold       = s.gold or 0,
        abandoned  = abandoned,
        recording  = recording,
        startLevel = startLevel,
        curLevel   = curLevel,
        -- A subtraction because this one must be right even for levels gained while History
        -- was off. sv.levels feeds the journal, not this number.
        levelUps   = math.max(0, curLevel - startLevel),
        perHour    = (played >= 60) and (quests / (played / 3600)) or nil,
    }
end

function Session:Print()
    local sm = self:Summary()
    local Y, W, R = "|cffEBB706", "|cffffffff", "|r"
    local function bignum(n)
        return (BreakUpLargeNumbers and BreakUpLargeNumbers(n)) or tostring(n)
    end
    local function money(c)
        return (GetCoinTextureString and GetCoinTextureString(c or 0)) or (tostring(c or 0) .. "c")
    end
    local perHour = sm.perHour and ("%.1f / hr"):format(sm.perHour) or "\226\128\148"

    print(Y .. "Everything Quests \226\128\148 This Session" .. R)
    print(("  Played:      " .. W .. "%s" .. R):format(ns.Util.FmtDuration(sm.played)))
    print(("  Quests done: " .. W .. "%d" .. R .. "  (%s)"):format(sm.quests, perHour))
    if sm.xp > 0 then
        print(("  Quest XP:    " .. W .. "%s" .. R):format(bignum(sm.xp)))
    end
    if sm.gold > 0 then
        print("  Quest gold:  " .. money(sm.gold))
    end
    if sm.abandoned > 0 then
        print(("  Abandoned:   " .. W .. "%d" .. R):format(sm.abandoned))
    end
    if sm.levelUps > 0 then
        print(("  Level-ups:   " .. W .. "%d" .. R .. "  (%d to %d)"):format(
            sm.levelUps, sm.startLevel, sm.curLevel))
    end
end
