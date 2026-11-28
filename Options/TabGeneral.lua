local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local function generalSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.general[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.general[key] = value end
        end
end

local function announceSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.announce and DB.db.profile.announce[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.announce = DB.db.profile.announce or {}
                DB.db.profile.announce[key] = value
            end
        end
end

local function groupSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.group and DB.db.profile.group[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.group = DB.db.profile.group or {}
                DB.db.profile.group[key] = value
            end
            local Comms = ns:GetSubsystem("GroupComms")
            if Comms and Comms.OnSettingChanged then Comms:OnSettingChanged(key) end
        end
end

-- One literal key per branch keeps each phrase visible to the locale scanner
local function pauseHint(QA)
    local key = QA:PauseKey()
    if key == "none" then return nil end
    if key == "shift" then return L["Hold Shift to pause."] end
    if key == "ctrl" then return L["Hold Ctrl to pause."] end
    return L["Hold Alt to pause."]
end

local PAUSE_KEY_OPTIONS = {
    -- The client's own key names, as its own modifier key settings show them in every language
    { value = "alt",   label = ALT_KEY or "ALT" },
    { value = "shift", label = SHIFT_KEY or "SHIFT" },
    { value = "ctrl",  label = CTRL_KEY or "CTRL" },
    { value = "none",  label = NONE_KEY or "None" },
}

local function autoCard(self, content, stack, deps)
    local QA = ns:GetSubsystem("QuestAuto")
    if not QA then return end
    local card = stack(self:CreateGroup(content, L["Auto-questing"]))

    -- Above the boxes it makes inert, so the explanation is read before they are checked
    if QA:ImmersionLoaded() then
        card:Add(self:CreateCheckbox(content, L["Let Immersion handle quest dialogs"],
            function() return QA:DeferToImmersion() end,
            function(v)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.general.deferToImmersion = v and true or false end
            end,
            L["Immersion replaces the quest and gossip windows so you can read them, so EQ leaves accepting and turning in to you while it is installed. Uncheck to accept and turn in automatically anyway."]))
    end

    -- Read on each hover, as the pause key and the Immersion box can change after the window is built
    local function tip(...)
        local parts = {}
        for i = 1, select("#", ...) do
            local p = select(i, ...)
            if p then parts[#parts + 1] = p end
        end
        if QA:DeferToImmersion() then
            parts[#parts + 1] = L["Immersion is handling quest windows, so this does nothing right now."]
        end
        return table.concat(parts, " ")
    end
    local function box(key, label, onWhenUnset, tipFn, dependsOn)
        local get, set = generalSetting(key)
        local cb = self:CreateCheckbox(content, label,
            function()
                if onWhenUnset then return get() ~= false end
                return get() == true
            end,
            function(v)
                set(v and true or false)
                deps.sync()
            end)
        cb:HookScript("OnEnter", function() self:ShowTooltip(cb, label, tipFn()) end)
        cb:HookScript("OnLeave", function() self:HideTooltip() end)
        if dependsOn then
            card:Add(cb, { dependent = true })
            deps[#deps + 1] = { control = cb, on = dependsOn }
        else
            card:Add(cb)
        end
        return get
    end

    local pvpNote = (QA.ReadsPvPFlag and QA:ReadsPvPFlag())
        and L["A quest that would flag you for PvP is left for you to accept, so the game can ask you to confirm it first."] or nil
    local acceptGet = box("autoAcceptQuests", L["Auto-accept quests"], false, function()
        return tip(pvpNote, pauseHint(QA))
    end)
    local function acceptOn() return acceptGet() == true end
    -- Classic clients read EQ's data for the quests the whole group takes, as Era and Forever have no escort tag
    local groupRule = ns.HAS_CLASSIC_SPAWNS
        and L["Leaves quests that the game also offers to the rest of your group when you take them, for you to accept by hand, so an escort does not start before you are ready. Besides escorts, they include some other quests, such as a hunter's Taming the Beast, some battleground quests and, on Burning Crusade Classic, some daily quests."]
        or L["Leaves quests the game marks as escorts for you to accept by hand, so an escort does not start before you are ready."]
    -- Forever's own quests carry none of the Classic data's flags
    local foreverNote = (ns.HAS_CLASSIC_SPAWNS and C_SuperTrack)
        and L["On WoW Forever this covers the quests it shares with Classic Era, not the ones new to WoW Forever."] or nil
    box("autoAcceptSkipGroup", L["Skip escort quests"], true, function()
        return tip(groupRule, foreverNote)
    end, acceptOn)
    box("autoAcceptSkipTrivial", L["Skip gray quests"], true, function()
        return tip(L["Leaves quests the game has grayed out because they are below your level, for you to accept by hand."])
    end, acceptOn)
    box("autoAcceptSkipRepeatable", L["Skip repeatable quests"], false, function()
        return tip(L["Leaves repeatable, daily and weekly quests for you to accept by hand."])
    end, acceptOn)
    box("autoAcceptSkipPvP", L["Skip PvP quests"], false, function()
        return tip(L["Leaves PvP quests, such as battleground quests, for you to accept by hand."])
    end, acceptOn)

    local turnInGet = box("autoTurnInQuests", L["Auto-turn-in quests"], false, function()
        return tip(L["Hands in finished quests for you. A quest that offers a choice of rewards is left for you to pick."], pauseHint(QA))
    end)
    box("autoTurnInSkipRepeatable", L["Skip repeatable turn-ins"], true, function()
        return tip(L["Leaves repeatable, daily and weekly quests for you to hand in yourself, so a stack of items, such as cloth for reputation, is not handed in for you one quest after another."])
    end, function() return turnInGet() == true end)

    box("declineBattlegroundShares", L["Decline quests shared in battlegrounds"], false, function()
        return tip(L["While you are in a battleground, declines a quest another player shares with you, and a line in your chat names it."], pauseHint(QA))
    end)

    -- No Immersion clause, because this popup is not a window Immersion replaces
    local confirmLabel = L["Join group quests automatically"]
    local confirmGet, confirmSet = generalSetting("autoConfirmGroupQuests")
    local confirm = self:CreateCheckbox(content, confirmLabel, confirmGet, confirmSet)
    confirm:HookScript("OnEnter", function()
        local body = L["When someone in your group starts an escort or another quest the game asks you to join, EQ answers yes for you. Only for people actually in your group - a stranger starting one beside you is left alone."]
        local hint = pauseHint(QA)
        self:ShowTooltip(confirm, confirmLabel, hint and (body .. " " .. hint) or body)
    end)
    confirm:HookScript("OnLeave", function() self:HideTooltip() end)
    card:Add(confirm)

    card:Add(self:CreateDropdown(content, L["Pause key"], PAUSE_KEY_OPTIONS,
        function() return QA:PauseKey() end,
        function(v)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.general.autoQuestPauseKey = v end
        end,
        L["While you hold this key, EQ does not accept, hand in, decline or join quests for you. Held as you start talking to someone, it keeps that whole conversation in your hands until its windows close."]))
end

local function generalCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["General"]))

    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail and ns.CLASSIC_QUEST_AVAILABLE and ns.CLASSIC_QUEST_AVAILABLE.leads then
        local warnGet, warnSet = generalSetting("warnSkippedBreadcrumbs")
        card:Add(self:CreateCheckbox(content, L["Warn when you skip a breadcrumb quest"],
            function() return warnGet() ~= false end,
            function(v) warnSet(v and true or false) end,
            L["A breadcrumb quest sends you to another quest giver, and the game stops offering it once you take the quest it leads to. If you take that quest while you could still have done the breadcrumb, a line in chat names the breadcrumb you skipped."]))
    end

    if ns:GetSubsystem("Minimap") then
        card:Add(self:CreateCheckbox(content, L["Show minimap button"],
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and not DB.char.minimap.hide
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if not DB then return end
                DB.char.minimap.hide = not value
                local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
                if LDBI then
                    if value then LDBI:Show("EverythingQuests") else LDBI:Hide("EverythingQuests") end
                end
            end))
    end

    local owScale = self:CreateSlider(content, L["Options Window Scale"], 0.7, 1.4, 0.05,
        function()
            local DB = ns:GetSubsystem("DB")
            return (DB and DB.db.global.optionsWindowScale) or 1.0
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB and type(value) == "number" and value > 0 then
                DB.db.global.optionsWindowScale = value
            end
        end,
        L["Resizes this Everything Quests options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."])
    card:Add(owScale)
    -- The slider sits inside the window it scales, so applying mid-drag fights the drag and snaps to the ends
    owScale.slider:HookScript("OnMouseUp", function() Options:ApplyWindowScale() end)

    if ns:GetSubsystem("WhatsNew") then
        local WHATSNEW_MODES = {
            { value = "popup", label = L["Popup window"] },
            { value = "chat",  label = L["Chat link"] },
            { value = "none",  label = L["None"] },
        }
        card:Add(self:CreateRadioGroup(content, L["After an update"], WHATSNEW_MODES,
            function()
                local DB = ns:GetSubsystem("DB")
                return (DB and DB.db.global.whatsNewMode) or "popup"
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then
                    DB.db.global.whatsNewMode = value
                    -- The mode the What's New window's own checkbox puts back
                    if value ~= "none" then DB.db.global.whatsNewModeBeforeOff = value end
                end
            end,
            nil, nil, L["After an update"],
            L["How Everything Quests tells you about new features: a Popup window, a quiet clickable Chat link in your chat frame, or None."]))
    end
end

local function announceCard(self, content, stack)
    if not ns:GetSubsystem("Announce") then return end
    local card = stack(self:CreateGroup(content, L["Quest announcements"]))

    -- Client globals, so channel names read correctly in every client language.
    local PARTY_NAME = _G["PARTY"] or "Party"
    local RAID_NAME  = _G["RAID"] or "Raid"
    local CHANNELS = {
        { value = "off",   label = _G["NONE"] or L["Nobody"] },
        { value = "party", label = PARTY_NAME },
        { value = "raid",  label = RAID_NAME },
        { value = "both",  label = PARTY_NAME .. " / " .. RAID_NAME },
    }
    local chanGet, chanSet = announceSetting("channel")
    card:Add(self:CreateDropdown(content, L["Announce to"], CHANNELS,
        function() return chanGet() or "off" end, chanSet,
        L["Which chat channel your quest updates are posted to. None sends nothing at all - the switches below then only decide what is printed to your own chat."]))

    local function box(key, label, tooltip)
        local get, set = announceSetting(key)
        card:Add(self:CreateCheckbox(content, label, get, set, tooltip))
    end
    box("toSelf", L["Also print to your own chat"],
        L["Prints each update to your own chat window as well. Nobody else sees these, so it is also how to watch what the switches below do before letting anything reach a group."])
    box("accepted", L["Announce quests you accept"],
        L["Posts a line as you pick each quest up, so the group can see what you are on."])
    box("objective", L["Announce objectives you finish"],
        L["Posts a line the moment an objective fills, so the group knows you are done with that part and can stop helping."])
    box("completed", L["Announce quests you hand in"],
        L["Posts a line as you turn each quest in."])
    box("abandoned", L["Announce quests you abandon"],
        L["Posts a line when you drop a quest. Off to begin with, because it is the one people rarely want broadcast."])
    box("hideIncoming", L["Hide announcements from other players"],
        L["Hides quest announcements other people in your group send, including the ones other quest addons post. Your own are always shown, so this does not silence anything you switched on above."])
end

local function partyCard(self, content, stack, deps)
    if not ns:GetSubsystem("GroupComms") then return end
    local card = stack(self:CreateGroup(content, L["Party quest progress"]))

    local shareGet, shareSet = groupSetting("partyProgress")
    card:Add(self:CreateCheckbox(content, L["Share quest progress with your group"], shareGet,
        function(v)
            shareSet(v)
            deps.sync()
        end,
        L["Your group sees how far along you are on each quest, and you see the same for them. This travels as hidden addon messages, so nothing is ever posted to anyone's chat. Switching it off stops both halves."]))

    -- Not built on retail, where no addon speaks that protocol and EQ never asks on it
    if ns.HAS_CLASSIC_SPAWNS then
        local peerGet, peerSet = groupSetting("readPeerAddons")
        local peer = self:CreateCheckbox(content, L["Read other quest addons as well"], peerGet, peerSet,
            L["Also reads the progress other quest addons share, so you see group members running them as well as the people running EQ. EQ asks their users for their quest logs when either of you joins the group. Your own progress is never sent on their channel."])
        card:Add(peer, { dependent = true })
        deps[#deps + 1] = { control = peer, on = shareGet }
    end
end

local function trackerCard(self, content, stack, deps)
    local Bridge = ns:GetSubsystem("TrackerBridge")
    if not Bridge then return end
    local card = stack(self:CreateGroup(content, L["Tracker"]))

    -- Saved in EQ Objective Tracker only on Yes, right before the reload it needs to apply.
    if Bridge:SupportsBlizzardTracker() then
        local blizz
        blizz = self:CreateCheckbox(content, L["Use Blizzard's quest tracker"],
            function() return Bridge:GetBlizzardTrackerSetting() end,
            function(value)
                local Dialog = ns:GetSubsystem("Dialog")
                if not Dialog then blizz:SetChecked(not value); return end
                Dialog:Show({
                    title    = "Everything Quests",
                    text     = value and L["Switch to Blizzard's quest tracker? The interface will reload."]
                        or L["Switch back to the EQ Objective Tracker window? The interface will reload."],
                    button1  = L["Yes"],
                    button2  = L["Cancel"],
                    onAccept = function()
                        if Bridge:SetBlizzardTrackerSetting(value) then
                            ReloadUI()
                            -- Expected to fire only if the client refused the reload. The choice is saved either way.
                            C_Timer.After(1, function()
                                DEFAULT_CHAT_FRAME:AddMessage("|cffEBB706Everything Quests|r "
                                    .. L["The interface did not reload. Type /reload to finish."])
                            end)
                        else
                            blizz:SetChecked(not value)
                        end
                    end,
                    onCancel = function() blizz:SetChecked(not value) end,
                })
            end,
            L["Turns off the EQ Objective Tracker window and brings back the game's own quest tracker. EQ Objective Tracker's other features, such as quest sounds, keep working. The interface reloads to switch."])
        card:Add(blizz)
    end

    -- Blizzard's tracker has no cogwheel to point at.
    card:Add(self:CreateButton(content, L["Open Tracker Settings"], nil,
        function() Bridge:OpenTrackerOptions() end,
        ns.Compat.BlizzardTrackerInUse()
            and L["The tracker is now EQ Objective Tracker, a separate addon that Everything Quests installs for you. Its own options panel holds everything: position and size, fonts, colors, sections, filters, sorting and visibility. You can also open it by typing /eqot."]
            or L["The tracker is now EQ Objective Tracker, a separate addon that Everything Quests installs for you. Its own options panel holds everything: position and size, fonts, colors, sections, filters, sorting and visibility. You can also open it by typing /eqot, or with the cogwheel at the top right of the tracker itself."]))

    -- Shown under Blizzard's tracker too, since EQ Objective Tracker still announces the followed quest then
    if Bridge:FocusArrowOffered() then
        local Arrow = ns:GetSubsystem("QuestArrow")
        local function hasTomTom() return Arrow and Arrow:Available() end
        -- Read on each hover, since another addon can take TomTom's place or give it back after the window is built
        local function arrowTip()
            local tip = ns.HAS_CLASSIC_SPAWNS
                and L["Points your TomTom arrow at the focused quest each time it changes, including a quest the game focuses as you accept it. Untick to leave that to the game's own arrow: quests are still focused, and Get Directions, the Quest Browser, the Chain Guide and a tracked chain still set a TomTom arrow."]
                or L["Points your TomTom arrow at the quest or world quest you follow each time that changes, including a quest the game follows as you accept it, and moves it on as you finish objectives. Off by default, as the game's own arrow already shows the quest you follow. Get Directions, the Chain Guide and a tracked chain set a TomTom arrow either way."]
            if not hasTomTom() then
                return tip .. " " .. L["Requires TomTom addon."]
            elseif Arrow:StandIn() then
                return tip .. " " .. L["TomTom is not loaded, but another addon is standing in for it, so these arrows go to that addon instead. It may show them in its own way, such as a journey to follow."]
            end
            return tip
        end
        local arrowLabel = L["TomTom arrow for the focused quest"]
        local _, arrowSet = generalSetting("focusArrow")
        local arrow = self:CreateCheckbox(content, arrowLabel,
            function() return Bridge:FocusArrowOn() end,
            function(value)
                arrowSet(value)
                Bridge:ApplyFocusArrowSetting()
            end)
        arrow:HookScript("OnEnter", function() self:ShowTooltip(arrow, arrowLabel, arrowTip()) end)
        arrow:HookScript("OnLeave", function() self:HideTooltip() end)
        card:Add(arrow)
        deps[#deps + 1] = { control = arrow, on = hasTomTom }
    end

    -- Both icons sit on the EQ Objective Tracker window, which Blizzard's tracker replaces.
    if not ns.Compat.BlizzardTrackerInUse() then
        local eqIconGet, eqIconSet = generalSetting("showEQIcon")
        card:Add(self:CreateCheckbox(content, L["Show Everything Quests icon on the tracker"], eqIconGet,
            function(value)
                eqIconSet(value)
                Bridge:ApplyEQIcon()
            end,
            L["Adds the Everything Quests logo at the top right of the tracker, which opens this options window. The tracker's own cogwheel opens the tracker's settings instead. You can also reach this window from the minimap button or by typing /eqs."]))

        if ns:GetSubsystem("ChainGuide") then
            local chainIconGet, chainIconSet = generalSetting("showChainGuideIcon")
            card:Add(self:CreateCheckbox(content, L["Show Chain Guide icon on the tracker"], chainIconGet,
                function(value)
                    chainIconSet(value)
                    Bridge:ApplyChainIcon()
                end,
                L["Adds a small chain icon beside the cogwheel at the top right of the tracker, which opens the Chain Guide."]))
        end
    end
end

local function profilesCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Profiles"]))
    self:AttachTooltip(card.label, L["Profiles"],
        L["Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot."])

    local function profileList()
        local DB = ns:GetSubsystem("DB")
        local out = {}
        if not (DB and DB.db and DB.db.GetProfiles) then return out end
        -- AceDB builds this list with pairs(), so it is sorted here or it reshuffles between sessions
        local names = DB.db:GetProfiles()
        table.sort(names)
        for _, name in ipairs(names) do
            out[#out + 1] = { value = name, label = name }
        end
        return out
    end
    local function currentProfile()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db and DB.db:GetCurrentProfile() or "Default"
    end
    local function setProfile(name)
        local DB = ns:GetSubsystem("DB")
        if DB and DB.db and DB.db.SetProfile then
            DB.db:SetProfile(name)
            ReloadUI()
        end
    end
    local function createProfileCopiedFromCurrent(name)
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.db) then return end
        local source = DB.db:GetCurrentProfile()
        DB.db:SetProfile(name)
        if source and source ~= name and DB.db.CopyProfile then
            DB.db:CopyProfile(source, true)
        end
        ReloadUI()
    end
    local function profileExists(name)
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.db and DB.db.GetProfiles) then return false end
        for _, p in ipairs(DB.db:GetProfiles()) do
            if p == name then return true end
        end
        return false
    end

    local profDD = self:CreateDropdown(content, L["Active profile"], profileList, currentProfile, setProfile)
    local row = card:Add(profDD)

    local function promptNewProfile()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title      = L["New Profile"],
            text       = L["Profile name:"],
            hasEditBox = true,
            maxLetters = 32,
            button1    = L["Create"],
            button2    = L["Cancel"],
            onAccept = function(text)
                local name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if name == "" then return end
                if name ~= currentProfile() and profileExists(name) then
                    Dialog:Show({
                        title    = L["Overwrite profile?"],
                        text     = (L["A profile named \"%s\" already exists. Overwrite it with a copy of your current settings?"]):format(name),
                        button1  = L["Overwrite"],
                        button2  = L["Cancel"],
                        onAccept = function() createProfileCopiedFromCurrent(name) end,
                    })
                else
                    createProfileCopiedFromCurrent(name)
                end
            end,
        })
    end

    local newProfile = self:CreateButton(content, L["New Profile"], nil, promptNewProfile)
    newProfile:SetPoint("RIGHT", row, "RIGHT", -self:Spacing("rowPadding"), 0)
    profDD:SetPoint("RIGHT", newProfile, "LEFT", -self:Spacing("buttonGap"), 0)
end

Options:RegisterTab({
    id    = "general",
    title = L["General"],
    order = 10,
    footer = function(self, bar)
        local reset = self:CreateButton(bar, L["Reset all settings"], nil, function()
            local Dialog = ns:GetSubsystem("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title   = "Everything Quests",
                text    = L["Reset every Everything Quests setting to defaults?"],
                button1 = L["Reset"],
                button2 = L["Cancel"],
                onAccept = function()
                    local DB = ns:GetSubsystem("DB")
                    if DB and DB.db then
                        if DB.db.ResetProfile then DB.db:ResetProfile() end
                        -- ResetProfile clears only the profile scope, so the global and character values are reset by hand
                        local g = DB.db.global
                        if g then
                            g.optionsWindowScale = DB.defaults.global.optionsWindowScale
                            g.optionsWindowPos   = nil
                            g.whatsNewMode       = DB.defaults.global.whatsNewMode
                            g.whatsNewModeBeforeOff = nil
                        end
                        if DB.char and DB.char.minimap then
                            DB.char.minimap.hide = DB.defaults.char.minimap.hide
                        end
                    end
                    ReloadUI()
                end,
            })
        end, nil, "danger")
        reset:SetPoint("RIGHT")
    end,
    build = function(self, content)
        local stack = Options.CardStack(self)
        local deps = {}
        deps.sync = function()
            for _, d in ipairs(deps) do self:SetDependent(d.control, d.on() and true or false) end
        end
        content._sync = deps.sync

        generalCard(self, content, stack)
        autoCard(self, content, stack, deps)
        announceCard(self, content, stack)
        partyCard(self, content, stack, deps)
        trackerCard(self, content, stack, deps)
        profilesCard(self, content, stack)
        deps.sync()
    end,
    refresh = function(_, content)
        if content._sync then content._sync() end
    end,
})
