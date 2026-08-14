local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

local FEATURE_POPUP_VERSION = "1.41.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.41.0"

local POPUP_BODY = [[
|cffEBB706Everything Quests now runs on Burning Crusade Classic|r
Everything that works on |cffffffffClassic Era|r works on |cffffffffTBC|r as well, with its own quest database covering |cffffffffOutland|r and the |cffffffffBlood Elf|r and |cffffffffDraenei|r starting zones as well as the old world. The Chain Guide, the World Quests panel and Quest History stay retail-only, exactly as they do on Era.

|cffEBB706Classic: markers for quests you can pick up|r
Every quest giver holding something for you now gets a gold |cffffffff!|r on the map, filtered by your level, race, class and the quests you have already finished. One marker covers a whole quest giver, so hovering it lists everything that giver offers rather than stacking a marker per quest.

|cffEBB706Classic: a finished quest points at who takes it|r
Turning a quest in used to send you back to the field you farmed it in. Everything Quests now marks the person who actually takes it, on every map where it can be handed in. This was wrong for |cffffffff475|r quests that hand in somewhere other than where their objective is.

Items you |cffffffffbuy|r are also marked now, at the merchants who sell them, which gives 21 quests their first useful marker.

|cffEBB706Classic: the tracker's focused quest gets an arrow|r
Clicking a quest's icon in |cffffffffEQ Objective Tracker|r drops a TomTom arrow on it, and clicking it again clears it. Classic has no in-game waypoint of its own, so the tracker announces the focus and Everything Quests places the arrow from its own database. Map markers and the tracker share one arrow, so using both retargets instead of leaving two behind.

|cffEBB706A Map section in the options|r
|cffffffff/eqs|r > General has a new Map section holding the marker ring toggles, plus filters that leave dungeon and raid quests, repeatable quests or profession quests off the map. Those filters only touch quests you have |cffffffffnot|r picked up yet, because hiding one you are already carrying would make the map lie about what you still have to do.

|cffEBB706One change worth knowing about|r
On both Classic versions the red ring behind quest markers now starts |cffffffffswitched off|r. A single zone there can draw hundreds of markers and the rings crowd each other, and the icons still tell the states apart on their own. Retail is unchanged. If you want the ring back, it is a checkbox under |cffffffff/eqs|r > General > Map.

|cffEBB706Everywhere|r
Countdown timers now use your own language's abbreviations, taken from the game client rather than hardcoded English. Quest markers show the quest level and its experience reward in the tooltip. The options window opens at the left edge of the screen instead of landing on top of the tracker's own options window.

|cffEBB706Thank you|r
Thanks to |cffffffffZox|r (French), |cffffffffMalevi4|r (Russian) and |cfffffffflabrie75|r (Korean) for keeping Everything Quests translated, and to everyone who sends reports and suggestions.

|cffEBB706Want to see this again?|r Type |cffffffff/eqs whatsnew|r anytime to reopen this summary.
]]

local YELLOW     = ns.Util.color.buttonYellow
local HEADER_RED = ns.Util.color.brandRed
local MUTED      = ns.Util.color.muted

local function currentMode()
    local m = ns.db and ns.db.global and ns.db.global.whatsNewMode
    return m or "popup"
end

local function alreadySeen()
    return ns.db and ns.db.global and ns.db.global.whatsNewSeen == FEATURE_POPUP_VERSION
end

local function markSeen()
    if ns.db and ns.db.global then
        ns.db.global.whatsNewSeen = FEATURE_POPUP_VERSION
    end
end

local function alreadyAnnounced()
    return ns.db and ns.db.global and ns.db.global.whatsNewAnnounced == FEATURE_POPUP_VERSION
end

local function markAnnounced()
    if ns.db and ns.db.global then
        ns.db.global.whatsNewAnnounced = FEATURE_POPUP_VERSION
    end
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

function WN:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQWhatsNewFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 480)
    f:SetPoint("CENTER")
    -- Above the Options window's DIALOG strata so the popup is not hidden behind it
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
    f:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText(POPUP_TITLE)
    f.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     14, -44)
    scroll:SetPoint("BOTTOMRIGHT", -34, 50)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(scroll:GetWidth(), 1)
    scroll:SetScrollChild(body)

    f.body = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, 0)
    f.body:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(3)
    f.body:SetText(POPUP_BODY)
    body:SetHeight(f.body:GetStringHeight() + 12)

    local function dismiss()
        markSeen()
        f:Hide()
    end

    f.openBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.openBtn:SetSize(180, 28)
    f.openBtn:SetPoint("BOTTOMLEFT", 16, 12)
    local openBg = f.openBtn:CreateTexture(nil, "BACKGROUND")
    openBg:SetAllPoints()
    openBg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    f.openBtn.text = f.openBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.openBtn.text:SetPoint("CENTER")
    f.openBtn.text:SetText(L["Open Options"])
    f.openBtn.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    f.openBtn:SetScript("OnClick", function()
        dismiss()
        local O = ns:GetSubsystem("Options")
        if O and O.Show then O:Show() end
    end)

    f.gotBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.gotBtn:SetSize(120, 28)
    f.gotBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    local gotBg = f.gotBtn:CreateTexture(nil, "BACKGROUND")
    gotBg:SetAllPoints()
    gotBg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.95)
    f.gotBtn.text = f.gotBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gotBtn.text:SetPoint("CENTER")
    f.gotBtn.text:SetText(L["Got it"])
    f.gotBtn.text:SetTextColor(1, 1, 1)
    f.gotBtn:SetScript("OnClick", dismiss)

    f.discordBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.discordBtn:SetHeight(28)
    f.discordBtn:SetPoint("BOTTOM", 0, 12)
    local dBg = f.discordBtn:CreateTexture(nil, "BACKGROUND")
    dBg:SetAllPoints()
    dBg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    f.discordBtn.icon = f.discordBtn:CreateTexture(nil, "OVERLAY")
    f.discordBtn.icon:SetSize(16, 16)
    f.discordBtn.icon:SetPoint("LEFT", 10, 0)
    f.discordBtn.icon:SetTexture("Interface\\AddOns\\EverythingQuests\\Media\\Textures\\discord.tga")
    f.discordBtn.text = f.discordBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.discordBtn.text:SetPoint("LEFT", f.discordBtn.icon, "RIGHT", 6, 0)
    f.discordBtn.text:SetText(L["Join our Discord!"])
    f.discordBtn.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    f.discordBtn:SetWidth(10 + 16 + 6 + f.discordBtn.text:GetStringWidth() + 12)
    f.discordBtn:SetScript("OnClick", function() ns:ShowDiscord() end)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", dismiss)

    f.dontShow = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.dontShow:SetSize(22, 22)
    f.dontShow:SetPoint("BOTTOMLEFT", 14, 44)
    f.dontShow.text = f.dontShow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.dontShow.text:SetPoint("LEFT", f.dontShow, "RIGHT", 2, 0)
    f.dontShow.text:SetText(L["Don't show these again"])
    f.dontShow.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    f.dontShow:SetScript("OnShow", function(self2)
        local m = currentMode()
        -- Remember the non-none mode so unchecking restores it instead of resetting a chat-link user to popup
        if m ~= "none" then self2._prevMode = m end
        self2:SetChecked(m == "none")
    end)
    f.dontShow:SetScript("OnClick", function(self2)
        if not (ns.db and ns.db.global) then return end
        if self2:GetChecked() then
            ns.db.global.whatsNewMode = "none"
        else
            ns.db.global.whatsNewMode =
                (self2._prevMode and self2._prevMode ~= "none" and self2._prevMode) or "popup"
        end
    end)
    f.dontShow:SetScript("OnEnter", function(self2)
        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
        -- SetText arg 5 is alpha, not wrap - pass 1 or the line can render invisible
        GameTooltip:SetText(L["Stops What's New notices entirely. You can turn them back on in /eqs > General."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.dontShow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.frame = f
    return f
end

function WN:Show()
    self:Build()
    self.frame:Show()
end

function WN:PrintChatLink()
    announceChat()
end

function WN:OnEnable()
    local mode = currentMode()
    if mode == "none" then return end
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
