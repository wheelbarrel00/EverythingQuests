local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

-- One entry per feature release and none for a patch, in English as the changelog is: each section a heading and its paragraph.
local RELEASES = {
    { version = "2.5.0", sections = {
        { "Open the Chain Guide from the tracker", "Right-click a quest on the tracker and pick Open Chain Guide to see its chain, with the quest highlighted. The menu offers it only for quests the Chain Guide lists.", sub = "ChainGuide" },
    } },
    { version = "2.4.0", sections = {
        { "The Promise of Tomorrow", "Patch 12.1.5's campaign has its own place in the Chain Guide with its chapters in order, the quests that take you into the Labyrinth of Kindo'jan are listed under Eversong Woods, and the Catalyst's Voidcore and Venomstone quests under Voidstorm. Following a chain now pins each step that is not in your quest log wherever the game gives its starting point on the map you are looking at.", retail = true },
        { "The game's own coordinates come first", "Everything Quests' coordinates under the minimap and on the world map now leave out whatever the game's own coordinates already show. The game turns those on by default. To keep Everything Quests' readouts, for example for two decimals, turn the game's off in its options under Map Coordinates.", sub = "ChainGuide" },
    } },
    { version = "2.3.0", sections = {
        { "Quest History on WoW Forever", "Every turn-in across your characters, with the Quests, Chain Timeline and Stats pages, and each character's past quests added the first time it logs in. The Type filter uses the Quest Browser's groups, and hovering a quest in the Chain Guide shows the date this character finished it.", classic = true, sub = "HistoryFrame" },
        { "A tab and a key for the Quest Browser", "The Quest Browser has its own tab in the options window, and a Toggle Quest Browser key you can set in the game's Key Bindings.", sub = "QuestBrowser" },
        { "History and the Chain Guide", "Hovering a quest in the Chain Guide shows the date this character finished it, History's reward total counts only quests that earned XP or gold, and its name and Type sorts are quicker on a long history.", retail = true, sub = "HistoryFrame" },
        { "Only what applies to your version", "What's New and the About tab's changelog now leave out what your version of the game does not have, a command or key your version lacks says so, and Everything Quests' keys sit together under one heading in Key Bindings. The scroll bars also stop short of the resize grip." },
    } },
}

local MAX_LISTED = 3

local TRANSLATORS = { "Zox", "Malevi4", "labrie75", "BNS333", "Keriaovo", "Stonetwist" }

local WIDTH, HEIGHT = 600, 560
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 24
local HEAD_GAP, SECTION_GAP, CLOSING_GAP, CLOSING_PAD = 4, 16, 20, 14
local VERSION_GAP, RELEASE_GAP = 8, 24
local FOOTER_H, BUTTON_GAP, BAR_ROOM = 56, 10, 10

local function parts(version)
    local out = {}
    for n in tostring(version or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

local function newer(a, b)
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

table.sort(RELEASES, function(a, b) return newer(a.version, b.version) end)

local function global()
    return ns.db and ns.db.global
end

local function saved(key)
    local g = global()
    return (g and g[key]) or ""
end

local function currentMode()
    local g = global()
    return (g and g.whatsNewMode) or "popup"
end

local function markSeen()
    local g = global()
    if g then g.whatsNewSeen = RELEASES[1].version end
end

local function markAnnounced()
    local g = global()
    if g then g.whatsNewAnnounced = RELEASES[1].version end
end

local function sectionsHere(release)
    local out = {}
    for _, s in ipairs(release.sections) do
        if ns.Util.ForThisClient(s) then out[#out + 1] = s end
    end
    return out
end

local function missedSince(since)
    local out = {}
    for _, r in ipairs(RELEASES) do
        if #out == MAX_LISTED or not newer(r.version, since) then break end
        local sections = sectionsHere(r)
        if #sections > 0 then out[#out + 1] = { version = r.version, sections = sections } end
    end
    return out
end

local function releasesToShow()
    local list = missedSince(saved("whatsNewSeen"))
    if #list > 0 then return list end
    for _, r in ipairs(RELEASES) do
        local sections = sectionsHere(r)
        if #sections > 0 then return { { version = r.version, sections = sections } } end
    end
    -- With nothing in any release for this client, the newest is shown whole rather than an empty window
    return { RELEASES[1] }
end

-- A chat line is owed only for a release newer than both the last one read and the last one announced
local function unannounced()
    local seen, announced = saved("whatsNewSeen"), saved("whatsNewAnnounced")
    return missedSince(newer(seen, announced) and seen or announced)
end

local function announceChat(version)
    local link = "|Haddon:EverythingQuests:whatsnew|h|cffEBB706[" .. L["See what's new"] .. "]|r|h"
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffEBB706Everything Quests|r " .. L["updated to"] .. " "
        .. version .. " \226\128\148 " .. link)
end

-- The default UI opens nothing for an addon link, and a raise at file scope would stop the rest of this file, hence the guard
if type(hooksecurefunc) == "function" and type(_G.SetItemRef) == "function" then
    hooksecurefunc("SetItemRef", function(link)
        if link == "addon:EverythingQuests:whatsnew" then
            WN:Show()
        end
    end)
end

local function colorCode(ctx, name)
    local r, g, b = ctx:Color(name)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                       math.floor(b * 255 + 0.5))
end

local function dateOf(version)
    for _, entry in ipairs(ns.Changelog or {}) do
        if entry.version == version then return entry.date or "" end
    end
    return ""
end

local function buildNotes(ctx, content, releases)
    local notes = ctx:CreateTextBlock(content)
    notes:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -PAD_TOP)
    notes:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -PAD_TOP)
    local several = #releases > 1
    local muted = colorCode(ctx, "muted")
    for r, release in ipairs(releases) do
        if several then
            notes:AddLine(release.version .. "   " .. muted .. dateOf(release.version) .. "|r", "value",
                { gap = (r > 1) and RELEASE_GAP or nil })
        end
        for i, s in ipairs(release.sections) do
            notes:AddLine(s[1], "title", { gap = (i > 1) and SECTION_GAP or (several and VERSION_GAP) or nil })
            notes:AddLine(s[2], "label", { gap = HEAD_GAP })
        end
    end

    local closing = CreateFrame("Frame", nil, content)
    closing:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -CLOSING_GAP)
    closing:SetPoint("TOPRIGHT", notes, "BOTTOMRIGHT", 0, -CLOSING_GAP)
    closing:SetHeight(1)
    ctx:Paint(closing, nil, "divider", "T")
    local lines = ctx:CreateTextBlock(closing)
    lines:SetPoint("TOPLEFT", closing, "TOPLEFT", 0, -CLOSING_PAD)
    lines:SetPoint("TOPRIGHT", closing, "TOPRIGHT", 0, -CLOSING_PAD)
    local bright = colorCode(ctx, "text")
    lines:AddLine(L["Translated by %s. Thanks to them and to everyone who sends reports and suggestions."]:format(
        bright .. table.concat(TRANSLATORS, ", ") .. "|r"), "hint")
    lines:AddLine(L["Type %s anytime to see this again."]:format(bright .. "/eqs whatsnew|r"), "hint")
    return notes, lines
end

function WN:Build()
    if self.frame then return self.frame end
    local Options = ns:GetSubsystem("Options")
    local ctx = Options.ui
    -- Decided once, because a text block cannot be emptied, so a reopen in the same session shows the same notes
    local releases = releasesToShow()

    local f = ctx:CreateWindow({ name = "EQWhatsNewFrame", title = L["What's New"], width = WIDTH, height = HEIGHT })
    f:SetSection("Everything Quests" .. (#releases == 1 and (" " .. releases[1].version) or ""))
    f:AddHeaderButton("icon-discord", L["Join our Discord"], L["Click to copy the invite link."],
        function() ns:ShowDiscord() end)
    f:HookScript("OnHide", markSeen)

    local area = ctx:CreateScrollArea(f.body, {})
    area:SetPoint("TOPLEFT", f.body, "TOPLEFT")
    area:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, FOOTER_H)
    local notes, lines = buildNotes(ctx, area.content, releases)

    local footer = CreateFrame("Frame", nil, f.body)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    footer._controls = {}
    ctx:Paint(footer, "chrome", "divider", "T")

    f.dontShow = ctx:CreateCheckbox(footer, L["Don't show these again"],
        function() return currentMode() == "none" end,
        function(on)
            local g = global()
            if not g then return end
            -- Unticking puts back the mode in use before, kept across sessions, so a chat link user is not reset to the popup
            if on then
                if currentMode() ~= "none" then g.whatsNewModeBeforeOff = currentMode() end
                g.whatsNewMode = "none"
            else
                local before = g.whatsNewModeBeforeOff
                g.whatsNewMode = (before and before ~= "none") and before or "popup"
            end
        end,
        L["Stops What's New notices entirely. You can turn them back on in /eqs > General."])
    f.dontShow:SetPoint("LEFT", footer, "LEFT", PAD_SIDE, 0)

    f.gotIt = ctx:CreateButton(footer, L["Got it"], nil, function() f:Hide() end, nil, "primary")
    f.gotIt:SetPoint("RIGHT", footer, "RIGHT", -PAD_SIDE, 0)
    f.openOptions = ctx:CreateButton(footer, L["Open Options"], nil, function()
        f:Hide()
        Options:Show()
    end)
    f.openOptions:SetPoint("RIGHT", f.gotIt, "LEFT", -BUTTON_GAP, 0)

    -- Text measured while hidden can be short of the text as drawn, so it is measured again once shown.
    local function layout()
        local h = PAD_TOP + notes:Measure() + CLOSING_GAP + CLOSING_PAD + lines:Measure() + PAD_BOTTOM
        -- The scroll frame's own width, which leaves room for the bars, so the notes never scroll sideways
        local w = area.scroll:GetWidth() or 0
        if w <= 0 then w = WIDTH - BAR_ROOM end
        area:SetContentSize(w, h)
        f.gotIt:Fit()
        f.openOptions:Fit()
    end
    layout()
    f:HookScript("OnShow", function()
        f.dontShow:Refresh()
        C_Timer.After(0, layout)
    end)

    self.frame = f
    return f
end

function WN:Show()
    local Options = ns:GetSubsystem("Options")
    if not (Options and Options.ui) then return end
    self:Build()
    self.frame:Show()
    -- Above the options window, whose About tab opens it
    self.frame:Raise()
end

function WN:PrintChatLink()
    announceChat(releasesToShow()[1].version)
end

function WN:OnEnable()
    -- A first install opens nothing and counts every release so far as read
    if saved("whatsNewSeen") == "" and saved("whatsNewAnnounced") == "" then
        markSeen()
        markAnnounced()
        return
    end
    local mode = currentMode()
    if mode == "none" then return end
    local isChat = (mode == "chat")
    if #(isChat and unannounced() or missedSince(saved("whatsNewSeen"))) == 0 then return end
    C_Timer.After(2, function()
        local cur = currentMode()
        if cur == "none" then return end
        if cur == "chat" then
            local missed = unannounced()
            if #missed > 0 then
                announceChat(missed[1].version)
                markAnnounced()
            end
        elseif #missedSince(saved("whatsNewSeen")) > 0 then
            self:Show()
        end
    end)
end
