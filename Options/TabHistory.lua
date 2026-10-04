local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local function historySetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.history[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.history[key] = value end
        end
end

local function retentionGet()
    local DB = ns:GetSubsystem("DB")
    return (DB and DB.db.profile.history.retention) or 5000
end

local function retentionSet(value)
    local DB = ns:GetSubsystem("DB")
    if DB then DB.db.profile.history.retention = value end
end

local function renderHistory()
    local HF = ns:GetSubsystem("HistoryFrame")
    if HF and HF.Render then HF:Render() end
end

local function backfill()
    local R = ns:GetSubsystem("History")
    if not (R and R.Backfill) then return end
    local added = R:Backfill()
    local name = R.CurrentCharacter and R:CurrentCharacter() or L["this character"]
    print(L["|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."]:format(
        added, added == 1 and "" or "s", name))
end

local function rescan()
    local R = ns:GetSubsystem("History")
    if not R then return end
    local queued = R:RequestMissingTitles() or 0
    if queued > 0 then
        print(L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."]:format(
            queued, queued == 1 and "" or "s"))
    else
        print(L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."])
    end
end

local function restore()
    local R = ns:GetSubsystem("History")
    if not (R and R.BackupInfo) then return end
    local info = R:BackupInfo()
    if not info then
        print(L["|cffEBB706EQ History:|r no backup yet — one is saved automatically each time you log out."])
        return
    end
    local Dialog = ns:GetSubsystem("Dialog")
    if not Dialog then return end
    Dialog:Show({
        title   = "Everything Quests",
        text    = L["Restore quest history from the backup taken %s (%d entries)? This replaces the current history."]:format(
                    date("%Y-%m-%d %H:%M", info.ts), info.count),
        button1 = L["Restore"],
        button2 = L["Cancel"],
        onAccept = function()
            local n = R:RestoreFromBackup()
            renderHistory()
            print(L["|cffEBB706EQ History:|r restored %d entr%s from backup."]:format(n, n == 1 and "y" or "ies"))
        end,
    })
end

local function wipeHistory()
    local Dialog = ns:GetSubsystem("Dialog")
    if not Dialog then return end
    Dialog:Show({
        title   = "Everything Quests",
        text    = L["Delete ALL recorded quest history (every character)? This cannot be undone."],
        button1 = L["Wipe"],
        button2 = L["Cancel"],
        onAccept = function()
            local R = ns:GetSubsystem("History")
            if R and R.Wipe then R:Wipe() end
            renderHistory()
            print(L["|cffEBB706EQ History:|r wiped."])
        end,
    })
end

Options:RegisterTab({
    id    = "history",
    title = L["History"],
    order = 50,
    footer = function(self, bar)
        local wipe = self:CreateButton(bar, L["Wipe history"], nil, wipeHistory, nil, "danger")
        wipe:SetPoint("RIGHT")
    end,
    build = function(self, content)
        local card = Options.CardStack(self)(self:CreateGroup(content, L["Quest History"]))

        card:Add(self:CreateButton(content, L["Open Quest History"], nil, function()
            local HF = ns:GetSubsystem("HistoryFrame")
            if HF and HF.Open then HF:Open() end
        end))

        local enaGet, enaSet = historySetting("enabled")
        card:Add(self:CreateCheckbox(content, L["Record completed quests"], enaGet, enaSet,
            L["When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character."]))

        -- Not dimmed under Record: the cap also limits what Populate from past completions may add
        card:Add(self:CreateSlider(content, L["Maximum entries kept"], 200, 10000, 200, retentionGet, retentionSet,
            L["When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing."]))

        card:Add(self:CreateButton(content, L["Populate from past completions"], nil, backfill,
            L["One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened."]))
        card:Add(self:CreateButton(content, L["Re-scan for quest names"], nil, rescan,
            L["Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder."]))
        card:Add(self:CreateButton(content, L["Restore history from backup"], nil, restore,
            L["Everything Quests saves a rolling backup of your history when you log out, and automatically restores it if your history is ever found empty or missing a character on load. Use this button to restore manually."]))
    end,
})
