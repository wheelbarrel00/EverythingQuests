local _, ns = ...

local Dialog = ns:RegisterSubsystem("Dialog", {})

-- The library's own frame, never StaticPopup, whose pooled frames our handlers could taint for logout
function Dialog:Show(opts)
    local Options = ns:GetSubsystem("Options")
    if not (Options and Options.ui) then return end
    -- Only the fields the library knows go on, because an unknown one raises there
    Options.ui:ShowDialog({
        title            = opts.title or "Everything Quests",
        text             = opts.text or "",
        button1          = opts.button1 or OKAY or "OK",
        button2          = opts.button2,
        onAccept         = opts.onAccept,
        onCancel         = opts.onCancel,
        hasEditBox       = opts.hasEditBox and true or nil,
        maxLetters       = opts.maxLetters,
        editBoxText      = opts.editBoxText,
        highlightEditBox = opts.highlightEditBox and true or nil,
    })
end
