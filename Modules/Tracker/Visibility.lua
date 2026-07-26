local _, ns = ...

local V = ns:RegisterSubsystem("TrackerVisibility", {})

local function getCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general or nil
end

local function shouldHide()
    local cfg = getCfg()
    if not cfg then return false end
    -- PLAYER_REGEN_DISABLED fires just before InCombatLockdown() reports true, so the regen-tracked flag has to count too
    if cfg.hideInCombat and ((InCombatLockdown and InCombatLockdown()) or V._inCombat) then return true end
    if cfg.hideInInstances and IsInInstance and (IsInInstance()) then return true end
    if cfg.hideInMythicPlus and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then return true end
    if cfg.hideOnMapOpen and WorldMapFrame and WorldMapFrame:IsShown() then return true end
    return false
end

-- Show/Hide is protected here (the tracker owns secure item-button descendants) and silently no-ops even out of combat, so alpha is the only reliable hide
local function setVisible(frame, visible)
    frame:SetAlpha(visible and 1 or 0)
    frame._eqHidden = (not visible) or nil
    if not (InCombatLockdown and InCombatLockdown()) then
        if visible then frame:Show() else frame:Hide() end
    end
end

function V:Apply()
    local hide = shouldHide()
    local Tracker = ns:GetSubsystem("Tracker")
    if not (Tracker and Tracker.frame) then return end
    local visible = not hide
    setVisible(Tracker.frame, visible)
    if visible and Tracker.frame._pendingRender then
        Tracker.frame._pendingRender = nil
        if Tracker.Refresh then Tracker:Refresh() end
    end
end

function V:DebugState()
    local cfg = getCfg() or {}
    local Tracker = ns:GetSubsystem("Tracker")
    local f = Tracker and Tracker.frame
    print(("|cffEBB706EQ Visibility|r: shouldHide=%s"):format(tostring(shouldHide())))
    print(("  cfg: combat=%s inst=%s m+=%s mapOpen=%s"):format(
        tostring(cfg.hideInCombat), tostring(cfg.hideInInstances),
        tostring(cfg.hideInMythicPlus), tostring(cfg.hideOnMapOpen)))
    print(("  conds: inCombat=%s inInstance=%s m+active=%s mapShown=%s"):format(
        tostring(InCombatLockdown()),
        tostring(IsInInstance and IsInInstance() or false),
        tostring(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                 and C_ChallengeMode.IsChallengeModeActive() or false),
        tostring(WorldMapFrame and WorldMapFrame:IsShown() or false)))
    if f then
        print(("  frame: shown=%s alpha=%.2f eqHidden=%s pending=%s"):format(
            tostring(f:IsShown()), f:GetAlpha() or -1,
            tostring(f._eqHidden and true or false),
            tostring(f._pendingRender and true or false)))
    else
        print("  frame: not built")
    end
end

function V:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function apply() self:Apply() end

    Events:On("PLAYER_REGEN_DISABLED", function()
        V._inCombat = true
        V:Apply()
    end)
    Events:On("PLAYER_REGEN_ENABLED", function()
        V._inCombat = false
        V:Apply()
    end)
    Events:On("PLAYER_ENTERING_WORLD", apply)
    Events:On("CHALLENGE_MODE_START",     apply)
    Events:On("CHALLENGE_MODE_COMPLETED", apply)

    Events:On("QUEST_ACCEPTED", function(_, questID)
        local cfg = getCfg()
        if not (cfg and questID and C_QuestLog) then return end

        if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
            return
        end

        if cfg.autoTrackAccepted == false then
            local watched = C_QuestLog.GetQuestWatchType
                             and C_QuestLog.GetQuestWatchType(questID) ~= nil
            if watched and C_QuestLog.RemoveQuestWatch then
                C_QuestLog.RemoveQuestWatch(questID)
            end
        else
            -- AddQuestWatch with no type adds an AUTOMATIC watch, which the engine silently evicts past its small cap.
            -- Force MANUAL on every accept, including quests the autoQuestWatch CVar already watched automatically.
            if C_QuestLog.AddQuestWatch then
                local manual = Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual
                C_QuestLog.AddQuestWatch(questID, manual)
            end
        end
    end)

    Events:On("PLAYER_ENTERING_WORLD", function()
        if WorldMapFrame and not V._mapHooked then
            V._mapHooked = true
            WorldMapFrame:HookScript("OnShow", apply)
            WorldMapFrame:HookScript("OnHide", apply)
        end
        apply()
    end)
end
