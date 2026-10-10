local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

local FEATURE_POPUP_VERSION = "2.3.0"

-- In English, as the changelog is: each section a heading and its paragraph.
local POPUP_SECTIONS = {
    { "Quest History on WoW Forever", "Every turn-in across your characters, with the Quests, Chain Timeline and Stats pages, and each character's past quests added the first time it logs in. The Type filter uses the Quest Browser's groups, and hovering a quest in the Chain Guide shows the date this character finished it.", classic = true, sub = "HistoryFrame" },
    { "A tab and a key for the Quest Browser", "The Quest Browser has its own tab in the options window, and a Toggle Quest Browser key you can set in the game's Key Bindings.", sub = "QuestBrowser" },
    { "History and the Chain Guide", "Hovering a quest in the Chain Guide shows the date this character finished it, History's reward total counts only quests that earned XP or gold, and its name and Type sorts are quicker on a long history.", retail = true, sub = "HistoryFrame" },
    { "Only what applies to your version", "What's New and the About tab's changelog now leave out what your version of the game does not have, a command or key your version lacks says so, and Everything Quests' keys sit together under one heading in Key Bindings. The scroll bars also stop short of the resize grip." },
}

local TRANSLATORS = { "Zox", "Malevi4", "labrie75", "BNS333", "Keriaovo", "Stonetwist" }

local WIDTH, HEIGHT = 600, 560
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 24
local HEAD_GAP, SECTION_GAP, CLOSING_GAP, CLOSING_PAD = 4, 16, 20, 14
local FOOTER_H, BUTTON_GAP, BAR_ROOM = 56, 10, 10

local function global()
    return ns.db and ns.db.global
end

local function currentMode()
    local g = global()
    return (g and g.whatsNewMode) or "popup"
end

local function alreadySeen()
    local g = global()
    return g and g.whatsNewSeen == FEATURE_POPUP_VERSION
end

local function markSeen()
    local g = global()
    if g then g.whatsNewSeen = FEATURE_POPUP_VERSION end
end

local function alreadyAnnounced()
    local g = global()
    return g and g.whatsNewAnnounced == FEATURE_POPUP_VERSION
end

local function markAnnounced()
    local g = global()
    if g then g.whatsNewAnnounced = FEATURE_POPUP_VERSION end
end

local function announceChat()
    local link = "|Haddon:EverythingQuests:whatsnew|h|cffEBB706[" .. L["See what's new"] .. "]|r|h"
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffEBB706Everything Quests|r " .. L["updated to"] .. " "
        .. FEATURE_POPUP_VERSION .. " \226\128\148 " .. link)
end

-- The client ignores our custom addon link type, so the popup has to be opened here. Guarded
-- because this runs at file scope - an absent hook takes the whole popup down with the file.
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

local function sectionsForThisClient()
    local out = {}
    for _, s in ipairs(POPUP_SECTIONS) do
        if ns.Util.ForThisClient(s) then out[#out + 1] = s end
    end
    return out
end

local function buildNotes(ctx, content)
    local notes = ctx:CreateTextBlock(content)
    notes:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -PAD_TOP)
    notes:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -PAD_TOP)
    -- Opened by hand on a client none of the sections are for, it shows the whole release rather than nothing
    local sections = sectionsForThisClient()
    if #sections == 0 then sections = POPUP_SECTIONS end
    for i, s in ipairs(sections) do
        notes:AddLine(s[1], "title", { gap = (i > 1) and SECTION_GAP or nil })
        notes:AddLine(s[2], "label", { gap = HEAD_GAP })
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

    local f = ctx:CreateWindow({ name = "EQWhatsNewFrame", title = L["What's New"], width = WIDTH, height = HEIGHT })
    f:SetSection("Everything Quests " .. FEATURE_POPUP_VERSION)
    f:AddHeaderButton("icon-discord", L["Join our Discord"], L["Click to copy the invite link."],
        function() ns:ShowDiscord() end)
    -- Closing it any way at all, Escape included, counts as having seen it.
    f:HookScript("OnHide", markSeen)

    local area = ctx:CreateScrollArea(f.body, {})
    area:SetPoint("TOPLEFT", f.body, "TOPLEFT")
    area:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, FOOTER_H)
    local notes, lines = buildNotes(ctx, area.content)

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
    -- Above the options window, which the About tab and /eqs open it over.
    self.frame:Raise()
end

function WN:PrintChatLink()
    announceChat()
end

function WN:OnEnable()
    local mode = currentMode()
    if mode == "none" then return end
    -- A release with nothing for this client neither pops up nor posts its chat link here
    if #sectionsForThisClient() == 0 then
        markSeen()
        markAnnounced()
        return
    end
    local isChat = (mode == "chat")
    if (isChat and alreadyAnnounced()) or (not isChat and alreadySeen()) then return end
    C_Timer.After(2, function()
        local cur = currentMode()
        if cur == "none" then return end
        if cur == "chat" then
            if not alreadyAnnounced() then
                announceChat()
                markAnnounced()
            end
        elseif not alreadySeen() then
            self:Show()
        end
    end)
end
