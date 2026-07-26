local _, ns = ...
local L = ns.L

local WN = ns:RegisterSubsystem("WhatsNew", {})

local FEATURE_POPUP_VERSION = "1.35.0"
local POPUP_TITLE           = "What's New in Everything Quests v1.35.0"

local POPUP_BODY = [[
|cffEBB706Missed the last update?|r
If you skipped a version, every release's full notes live right inside the addon. Type |cffffffff/eqs|r, open the |cffffffffAbout|r tab, and read the changelog there. This popup only covers the latest release.

|cffEBB706Restyle the zone progress bar|r
Under |cffffffff/eqs|r > Appearance you can now change the zone progress bar's texture and fill color. Choose from seven bundled Everything Quests bar styles or any texture provided by SharedMedia and other addons, each shown with a live preview. Thanks to Da Warrior for the request.

|cffEBB706Space out the tracker your way|r
Two new sliders under |cffffffff/eqs|r > Appearance, |cffffffffLine Spacing|r and |cffffffffHeader Spacing|r, let you loosen or tighten the space between objective lines and around section headers to fit the tracker to your screen. Thanks to Rhinoplasty for the line-spacing idea.

|cffEBB706A class color button in the color picker|r
If you do not run ElvUI, the color picker now has a |cffffffffClass|r button that sets any Everything Quests color to your class color in one click.

|cffEBB706Thank you|r
Thanks to |cffffffffZox|r (French) and |cffffffffMalevi4|r (Russian) for keeping Everything Quests translated, and to everyone sending in reports and suggestions.

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

-- Custom chat hyperlink (|Haddon:EverythingQuests:whatsnew|h); the client ignores the
-- unknown link type, so we open the popup ourselves when ours is clicked.
hooksecurefunc("SetItemRef", function(link)
    if link == "addon:EverythingQuests:whatsnew" then
        WN:Show()
    end
end)

function WN:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQWhatsNewFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 480)
    f:SetPoint("CENTER")
    -- Above the Options window's DIALOG strata so the popup isn't hidden
    -- if the player opens Options before reading it.
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
        -- Remember the non-"none" mode so unchecking restores it (e.g. a chat-link
        -- user keeps "chat" instead of being silently reset to "popup").
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
        -- SetText arg 5 is alpha (not wrap); pass 1 or the line can render invisible.
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
