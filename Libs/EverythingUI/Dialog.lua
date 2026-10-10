local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local DIALOG_WIDTH  = 420
local PADDING       = 20
local TEXT_GAP      = 10
local FIELD_GAP     = 14
local FIELD_INSET   = 8
local BUTTON_TOP    = 20
local BUTTON_BOTTOM = 16

local DIALOG_FIELDS = {
    title = "string", text = "string", button1 = "string", button2 = "string",
    onAccept = "function", onCancel = "function", hasEditBox = "boolean", maxLetters = "number",
    editBoxText = "string", highlightEditBox = "boolean", danger = "boolean",
}

local function finish(f, accepted)
    local opts = f.opts
    -- Guards a double fire - a button click and the escape key can both land.
    if not opts then return end
    f.opts = nil

    local text = f.edit:IsShown() and f.edit:GetText() or nil
    -- Hiding the frame releases the focus on its own, but only while this stays the sole
    -- path that hides it. An edit box that kept focus would swallow Enter game-wide.
    f.edit:ClearFocus()

    -- Callback first and hide after, the order Blizzard's StaticPopup uses. Hidden first, a
    -- ReloadUI from Yes was blocked as an addon action on retail 12.1. Run through xpcall so a
    -- raise cannot leave the dialog on screen with no callbacks left to close it.
    if accepted then
        if opts.onAccept then xpcall(function() opts.onAccept(text) end, geterrorhandler()) end
    elseif opts.onCancel then
        xpcall(opts.onCancel, geterrorhandler())
    end
    -- A callback that opened the next dialog keeps the frame up for it.
    if not f.opts then f:Hide() end
end

local function textHeight(fs, style)
    local h = fs:GetStringHeight()
    -- `<= 0` as well as nil, because 0 is truthy and an unmeasured title would put the body on it.
    if not h or h <= 0 then h = lib.tokens.typography[style].size end
    return h
end

local function layout(f)
    local sp = lib.tokens.spacing
    f.shownAccept:Fit()
    f.cancel:Fit()
    f:SetHeight(PADDING + textHeight(f.title, "title") + TEXT_GAP + textHeight(f.shownBody, "label")
                + (f.edit:IsShown() and (FIELD_GAP + sp.fieldHeight) or 0)
                + BUTTON_TOP + sp.buttonHeight + BUTTON_BOTTOM)
end

-- Its own frame rather than StaticPopup: that system recycles a small shared pool, so an insecure
-- handler here could taint the frame the logout or quit dialog later reuses. Deliberately unnamed:
-- a named frame can be read out of _G, which is the whole mechanism behind the UISpecialFrames
-- taint (see CloseOnEscape in Kit.lua).
local function build(ctx)
    local sp = lib.tokens.spacing
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(DIALOG_WIDTH)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    kit.Fill(ctx, f, "surface")
    kit.Edge(ctx, f, "surfaceBorder")

    -- SetPropagateKeyboardInput is protected, so the whole handler stands down in combat and
    -- Escape falls through to the default UI.
    f:EnableKeyboard(false)
    local function arm()
        if InCombatLockdown() or not f:IsShown() then return end
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
    end
    f:HookScript("OnShow", function()
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        -- Deferred rather than dropped. A dialog opened in combat stayed keyboard-dead for as
        -- long as it was shown, so Escape never closed it even once the fight was over.
        if InCombatLockdown() then
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        arm()
    end)
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- After a swallowed Enter the frame passes no key on, and its key handler stands
            -- down in combat, so nothing could turn that back on until the fight ended. The frame
            -- lets go of the keyboard instead and takes it again afterwards. A focused field keeps
            -- its own focus.
            f:EnableKeyboard(false)
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif event == "PLAYER_REGEN_ENABLED" then
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            arm()
        end
    end)
    f:HookScript("OnHide", function()
        f:EnableKeyboard(false)
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        f:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end)
    f:SetScript("OnKeyDown", function(_, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            finish(f, false)
        elseif (key == "ENTER" or key == "NUMPADENTER") and not f.edit:IsShown() then
            -- Swallowed, never bound to accept: most of the confirms that reach here reload
            -- the UI, so a stray keypress must not be able to trigger one. Without
            -- this it opens the chat box behind a dialog that looks modal.
            f:SetPropagateKeyboardInput(false)
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)

    f.title = kit.Text(ctx, f, "title")
    f.title:SetPoint("TOPLEFT", PADDING, -PADDING)
    f.title:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    f.title:SetWordWrap(true)
    f.body = kit.Text(ctx, f, "label")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -TEXT_GAP)
    f.body:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -TEXT_GAP)
    f.body:SetWordWrap(true)
    -- The text can carry player data, such as a profile name in any alphabet, so a second
    -- string in the client's own font object stands in when Barlow cannot draw it (decision 14).
    f.bodyData = kit.DataText(f)
    f.bodyData:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -TEXT_GAP)
    f.bodyData:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -TEXT_GAP)
    f.bodyData:SetWordWrap(true)
    f.bodyData:SetTextColor(ctx:Color("label"))

    -- What is typed can be a name in any alphabet, so the field draws in the client's own font
    -- object rather than the UI font (decision 14).
    local edit = CreateFrame("EditBox", nil, f)
    edit:SetHeight(sp.fieldHeight)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetTextInsets(FIELD_INSET, FIELD_INSET, 0, 0)
    kit.Fill(ctx, edit, "input")
    kit.Edge(ctx, edit, "inputBorder")
    edit:SetScript("OnEscapePressed", function() finish(f, false) end)
    edit:SetScript("OnEnterPressed", function() finish(f, true) end)
    edit:Hide()
    f.edit = edit

    f.accept = ctx:CreateButton(f, "", nil, function() finish(f, true) end, nil, "primary")
    f.accept:SetPoint("BOTTOMRIGHT", -PADDING, BUTTON_BOTTOM)
    f.acceptDanger = ctx:CreateButton(f, "", nil, function() finish(f, true) end, nil, "danger")
    f.acceptDanger:SetPoint("BOTTOMRIGHT", -PADDING, BUTTON_BOTTOM)
    f.cancel = ctx:CreateButton(f, "", nil, function() finish(f, false) end)
    return f
end

-- A confirm or a prompt: a surface card with a title, its text, an optional field, a primary button
-- (a danger one with danger set, for a confirm that erases something) and an optional secondary
-- one. Opening one over another cancels the first, so no callback is ever silently dropped. Each
-- context has its own dialog, in its own accent.
function Context:ShowDialog(opts)
    if type(opts) ~= "table" or type(opts.title) ~= "string" or type(opts.text) ~= "string"
            or type(opts.button1) ~= "string" then
        error("EverythingUI: ShowDialog needs title, text and button1", 2)
    end
    for key, v in pairs(opts) do
        if DIALOG_FIELDS[key] ~= type(v) then
            error(("EverythingUI: ShowDialog got a bad or unknown field %s"):format(tostring(key)), 2)
        end
    end
    local f = self._dialog
    if not f then
        f = build(self)
        self._dialog = f
    end
    -- Close a dialog still on screen so its callbacks are not silently dropped.
    if f.opts then finish(f, false) end
    f.opts = opts

    f.title:SetText(opts.title)
    local useData = kit.NeedsClientFont(opts.text)
    f.body:SetText(opts.text)
    f.bodyData:SetText(opts.text)
    f.body:SetShown(not useData)
    f.bodyData:SetShown(useData)
    f.shownBody = useData and f.bodyData or f.body
    local danger = opts.danger == true
    f.accept:SetShown(not danger)
    f.acceptDanger:SetShown(danger)
    f.shownAccept = danger and f.acceptDanger or f.accept
    f.shownAccept:SetText(opts.button1)
    f.cancel:ClearAllPoints()
    f.cancel:SetPoint("RIGHT", f.shownAccept, "LEFT", -lib.tokens.spacing.buttonGap, 0)
    if opts.button2 then
        f.cancel:SetText(opts.button2)
        f.cancel:Show()
    else
        f.cancel:Hide()
    end

    local edit = f.edit
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", f.shownBody, "BOTTOMLEFT", 0, -FIELD_GAP)
    edit:SetPoint("TOPRIGHT", f.shownBody, "BOTTOMRIGHT", 0, -FIELD_GAP)
    if opts.hasEditBox then
        edit:Show()
        edit:SetMaxLetters(opts.maxLetters or 0)
        edit:SetText(opts.editBoxText or "")
        edit:SetCursorPosition(0)
        edit:SetFocus()
        -- After SetFocus, which clears any selection of its own.
        if opts.highlightEditBox then edit:HighlightText() end
    else
        edit:Hide()
    end

    layout(f)
    f:Show()
    f:Raise()
    -- Text measured while a tab was built has come out short of the text as drawn, so the dialog
    -- is sized again a frame later, once it is on screen.
    C_Timer.After(0, function() if f:IsShown() then layout(f) end end)
end
