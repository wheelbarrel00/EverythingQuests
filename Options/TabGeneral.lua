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

local function generalCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["General"]))

    local QA = ns:GetSubsystem("QuestAuto")
    if QA then
        -- Above the two boxes it makes inert, so the explanation is read before they are ticked
        if QA:ImmersionLoaded() then
            card:Add(self:CreateCheckbox(content, L["Let Immersion handle quest dialogs"],
                function() return QA:DeferToImmersion() end,
                function(v)
                    local DB = ns:GetSubsystem("DB")
                    if DB then DB.db.profile.general.deferToImmersion = v and true or false end
                end,
                L["Immersion replaces the quest and gossip windows so you can read them, so EQ leaves accepting and turning in to you while it is installed. Uncheck to accept and turn in automatically anyway."]))
        end

        -- Appended rather than reworded, because a reword would retire six translations
        local altHint    = L["Hold Alt to pause."]
        local rewardHint = L["Skips reward-choice screens."]
        if QA:DeferToImmersion() then
            local inert = L["Immersion is handling quest windows, so this does nothing right now."]
            altHint    = altHint .. " " .. inert
            rewardHint = rewardHint .. " " .. inert
        end

        local autoAccGet, autoAccSet = generalSetting("autoAcceptQuests")
        card:Add(self:CreateCheckbox(content, L["Auto-accept quests"], autoAccGet, autoAccSet, altHint))

        local autoTIGet, autoTISet = generalSetting("autoTurnInQuests")
        card:Add(self:CreateCheckbox(content, L["Auto-turn-in quests"], autoTIGet, autoTISet, rewardHint))

        -- No Immersion clause, because this popup is not a window Immersion replaces.
        local confirmGet, confirmSet = generalSetting("autoConfirmGroupQuests")
        card:Add(self:CreateCheckbox(content, L["Join group quests automatically"], confirmGet, confirmSet,
            L["When someone in your group starts an escort or another quest the game asks you to join, EQ answers yes for you. Only for people actually in your group - a stranger starting one beside you is left alone."]
                .. " " .. L["Hold Alt to pause."]))
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
                if DB then DB.db.global.whatsNewMode = value end
            end,
            nil, nil, L["After an update"],
            L["How Everything Quests tells you about new features: a Popup window, a quiet clickable Chat link in your chat frame, or None. New features always ship off until you turn them on."]))
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

local function browserCard(self, content, stack)
    local QB = ns:GetSubsystem("QuestBrowser")
    if not (QB and QB.Available and QB:Available()) then return end
    local card = stack(self:CreateGroup(content, L["Quest Browser"]))

    local open = self:CreateButton(content, L["Open Quest Browser"], nil, function()
        local B = ns:GetSubsystem("QuestBrowser")
        if B then B:Open() end
    end)
    self:AttachTooltip(open, L["Quest Browser"],
        L["Look up almost any quest in the game, including ones you have never picked up. Shows the level and race and class requirements, where it starts and turns in, what has to be finished first, and why you cannot take it yet. Also on /eqs quests, or right-click a gold quest marker on the map."])
    card:Add(open)
end

local function trackerCard(self, content, stack)
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
                        -- ResetProfile clears only the profile scope, so this tab's global and character settings are reset by hand
                        local g = DB.db.global
                        if g then
                            g.optionsWindowScale = DB.defaults.global.optionsWindowScale
                            g.whatsNewMode       = DB.defaults.global.whatsNewMode
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
        announceCard(self, content, stack)
        partyCard(self, content, stack, deps)
        browserCard(self, content, stack)
        trackerCard(self, content, stack)
        profilesCard(self, content, stack)
        deps.sync()
    end,
    refresh = function(_, content)
        if content._sync then content._sync() end
    end,
})
