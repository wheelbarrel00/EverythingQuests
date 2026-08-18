local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

local FEATURE_POPUP_VERSION = "1.43.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.43.0"

local POPUP_BODY = [[
|cffEBB706Quest information on the tooltips you already hover|r
Hover an item in your bags and it now tells you |cffffffffwhich quest wants it|r and how many you still need. On Classic, hovering an enemy tells you which quest it counts toward and what is left, which the game there never says at all.

Nothing is added to a tooltip that has nothing to say. On retail the enemy half is left alone, because the game already writes those lines itself.

|cffaaaaaaThe bag item half has been tested on Classic but not on retail. If it looks wrong there, please let me know.|r

|cffEBB706Coordinates, on the map and under the minimap|r
The world map now shows the spot your |cffffffffmouse|r is pointing at, and |cffffffffyour own position|r when you are looking at the zone you are standing in. There is a matching readout under the minimap, off by default, and a slider for how many decimals to show.

|cffEBB706Two ways to quiet a busy map|r
|cffffffffOnly show markers for quests you are tracking|r leaves out the markers for anything in your log you have untracked, so a crowded zone shows only what you are working on. |cffffffffFade markers that cover your position|r makes any marker sitting on top of your own arrow see-through so you can still find yourself. Both are off by default and both live under |cffffffff/eqs|r > General.

|cffEBB706Auto-accept picks the right quest|r
At a quest giver offering several, auto-accept now takes the first quest it can |cffffffffactually accept|r rather than whatever sits at the top of the list, and passes over a trivial grey quest when a real one is on offer.

|cffEBB706Traditional Chinese|r
Everything Quests now ships |cffffffffzhTW|r translations alongside French, Russian, Korean and Simplified Chinese.

|cffEBB706Thank you|r
Thanks to |cffffffffAIR|r for reporting that |cffffffffGet Directions|r could set no waypoint and say nothing about it, which is fixed in this release. Thanks to |cffffffffZox|r (French), |cffffffffMalevi4|r (Russian) and |cfffffffflabrie75|r (Korean) for keeping Everything Quests translated, to |cffffffffBNS333|r (Traditional Chinese) and |cffffffffKeriaovo|r (Simplified Chinese), and to everyone who sends reports and suggestions.

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

    -- The bottom of the window is three stacked rows, and the scroll region has to clear all of
    -- them. Derived from the row heights rather than written as one more independent number,
    -- because that is what let the checkbox drift on top of the last line of text.
    local BUTTON_ROW_Y  = 12
    local BUTTON_H      = 28
    local CHECK_H       = 22
    local ROW_GAP       = 6
    local CHECK_ROW_Y   = BUTTON_ROW_Y + BUTTON_H + ROW_GAP
    local SCROLL_BOTTOM = CHECK_ROW_Y + CHECK_H + ROW_GAP

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     14, -44)
    scroll:SetPoint("BOTTOMRIGHT", -34, SCROLL_BOTTOM)

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
    f.openBtn:SetSize(180, BUTTON_H)
    f.openBtn:SetPoint("BOTTOMLEFT", 16, BUTTON_ROW_Y)
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
    f.gotBtn:SetSize(120, BUTTON_H)
    f.gotBtn:SetPoint("BOTTOMRIGHT", -16, BUTTON_ROW_Y)
    local gotBg = f.gotBtn:CreateTexture(nil, "BACKGROUND")
    gotBg:SetAllPoints()
    gotBg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.95)
    f.gotBtn.text = f.gotBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gotBtn.text:SetPoint("CENTER")
    f.gotBtn.text:SetText(L["Got it"])
    f.gotBtn.text:SetTextColor(1, 1, 1)
    f.gotBtn:SetScript("OnClick", dismiss)

    f.discordBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.discordBtn:SetHeight(BUTTON_H)
    f.discordBtn:SetPoint("BOTTOM", 0, BUTTON_ROW_Y)
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
    f.dontShow:SetSize(CHECK_H, CHECK_H)
    f.dontShow:SetPoint("BOTTOMLEFT", 14, CHECK_ROW_Y)
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
