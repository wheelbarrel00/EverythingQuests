local _, ns = ...
local L = ns.L

local QA = ns:RegisterSubsystem("QuestAuto", {})

local DECLINE_LOCKOUT_S = 10
local _declineLockUntil = 0

local function autoAcceptOn()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general.autoAcceptQuests == true
end
local function autoTurnInOn()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general.autoTurnInQuests == true
end
local function immersionLoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("Immersion")) and true or false
end

function QA:ImmersionLoaded()
    return immersionLoaded()
end

-- The one implementation of the rule, so the checkbox and the handlers cannot disagree about an
-- unset value. The key is deliberately absent from DB.defaults, because AceDB answers the default
-- for an unset key and that would hide the nil this needs.
function QA:DeferToImmersion()
    if not immersionLoaded() then return false end
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general.deferToImmersion
    if v == nil then return true end
    return v and true or false
end

local function paused()
    if IsAltKeyDown and IsAltKeyDown() then return true end
    -- Gate on the addon being LOADED, not on its frame being shown: handler order between addons
    -- is undefined, and Immersion leaves its frame hidden for some events it handles anyway, so a
    -- visibility test could accept the quest before Immersion has drawn.
    if QA:DeferToImmersion() then return true end
    return GetTime() < _declineLockUntil
end

-- Reading avail[1] ALONE meant one unusable first row blocked auto-accept entirely while good rows
-- sat behind it, so this walks. A trivial quest is deferred to a real one but still accepted when
-- it is the only offer, and a client carrying no isTrivial field reads every row as non-trivial
-- and degrades to the first usable index.
local function firstOffer(avail)
    local fallback
    for i = 1, #avail do
        local q = avail[i]
        local id = q and q.questID
        if id then
            if not q.isTrivial then return id end
            fallback = fallback or id
        end
    end
    return fallback
end

local function onGossipShow()
    if paused() then return end
    if not C_GossipInfo then return end

    if autoTurnInOn() and C_GossipInfo.GetActiveQuests then
        local active = C_GossipInfo.GetActiveQuests()
        if active then
            for i = 1, #active do
                local q = active[i]
                if q and q.isComplete and q.questID then
                    C_GossipInfo.SelectActiveQuest(q.questID)
                    return
                end
            end
        end
    end

    if autoAcceptOn() and C_GossipInfo.GetAvailableQuests then
        local avail = C_GossipInfo.GetAvailableQuests()
        local pick = avail and firstOffer(avail)
        if pick then C_GossipInfo.SelectAvailableQuest(pick) end
    end
end

local function onQuestGreeting()
    if paused() then return end

    if autoTurnInOn() and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        local n = GetNumActiveQuests() or 0
        for i = 1, n do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if autoAcceptOn() and GetNumAvailableQuests and SelectAvailableQuest then
        local n = GetNumAvailableQuests() or 0
        -- No trivial flag is read here. GetAvailableQuestInfo's positional return has not been
        -- MEASURED on this client, and guessing a signature is how flatRow nearly shipped wrong.
        -- Walking past rows the client cannot name is the part that needs no signature.
        for i = 1, n do
            local title = GetAvailableTitle and GetAvailableTitle(i)
            if title and title ~= "" then
                SelectAvailableQuest(i)
                return
            end
        end
        if n >= 1 then SelectAvailableQuest(1) end
    end
end

local function onQuestDetail()
    if paused() then return end
    if autoAcceptOn() and AcceptQuest then AcceptQuest() end
end

local function onQuestProgress()
    if paused() then return end
    if not autoTurnInOn() then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function onQuestComplete()
    if paused() then return end
    if not autoTurnInOn() then return end
    if not GetQuestReward then return end

    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n <= 1 then
        -- GetQuestReward index 0 finishes a quest with no reward choice, 1 takes the single option
        GetQuestReward(n == 1 and 1 or 0)
    end
end

function QA:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("GOSSIP_SHOW",    onGossipShow)
    Events:On("QUEST_GREETING", onQuestGreeting)
    Events:On("QUEST_DETAIL",   onQuestDetail)
    Events:On("QUEST_PROGRESS", onQuestProgress)
    Events:On("QUEST_COMPLETE", onQuestComplete)

    if hooksecurefunc and _G.DeclineQuest then
        hooksecurefunc("DeclineQuest", function()
            _declineLockUntil = GetTime() + DECLINE_LOCKOUT_S
        end)
    end

    self:_askAboutImmersion()
end

-- Only the players this silently changes are asked: Immersion present, no answer stored, and
-- auto-questing actually switched on. Everyone else sees nothing.
function QA:_askAboutImmersion()
    local DB = ns:GetSubsystem("DB")
    local g = DB and DB.db.profile.general
    if not g or g.deferToImmersion ~= nil or g.immConflictAsked then return end
    if not immersionLoaded() then return end
    if g.autoAcceptQuests ~= true and g.autoTurnInQuests ~= true then return end

    g.immConflictAsked = true
    C_Timer.After(4, function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Immersion is installed. It replaces the quest and gossip windows so you can read them, and EQ's auto-accept and auto-turn-in would click straight past it. Which would you like?"],
            button1 = L["Keep auto-questing"],
            button2 = L["Let Immersion handle it"],
            onAccept = function() g.deferToImmersion = false end,
            onCancel = function() g.deferToImmersion = true end,
        })
    end)
end
