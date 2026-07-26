local _, ns = ...
local L = ns.L

ns:GetSubsystem("Options"):AddTab("appearance", L["Appearance"], function(content)
    local Options = ns:GetSubsystem("Options")

    local function alignSwatchTo(picker, ref)
        picker.button:ClearAllPoints()
        picker.button:SetPoint("TOP",  picker, "TOP", 0, -1)
        picker.button:SetPoint("LEFT", ref.button, "LEFT", 0, 0)
        picker.label:ClearAllPoints()
        picker.label:SetPoint("RIGHT", picker.button, "LEFT", -8, 0)
    end

    local function trackerSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.tracker[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.tracker[key] = value end
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker then Tracker:Refresh() end
                local ZP = ns:GetSubsystem("TrackerZoneProgress")
                if ZP and ZP.UpdateFrame then ZP:UpdateFrame() end
            end
    end

    local function scenarioSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.tracker[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.tracker[key] = value end
                local S = ns:GetSubsystem("TrackerScenario")
                if S and S.ApplyBannerShadow then S:ApplyBannerShadow() end
            end
    end

    -- The banner re-anchors and re-fonts only in TrackerScenario:Refresh - Tracker:Refresh never drives it
    local function scenarioRenderSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.tracker[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.tracker[key] = value end
                local S = ns:GetSubsystem("TrackerScenario")
                if S and S.Refresh then S:Refresh() end
            end
    end

    local function headerBarSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.tracker[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.tracker[key] = value end
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker and Tracker.ApplyHeaderBars then Tracker:ApplyHeaderBars() end
            end
    end

    local h = Options:CreateSectionHeader(content, L["Appearance"])
    h:SetPoint("TOPLEFT", 8, -8)

    local Media = ns:GetSubsystem("Media")
    local fontList = (Media and Media.GetFontList and Media:GetFontList()) or {}
    local fontGet, fontSet = trackerSetting("font")
    local fontDD = Options:CreateFontDropdown(content, L["Font"], fontList, fontGet, fontSet)
    fontDD:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)
    fontDD:SetWidth(280)

    local sizeGet, sizeSet = trackerSetting("fontSize")
    local sizeSlider = Options:CreateSlider(content, L["Font Size"], 8, 24, 0.5, sizeGet, sizeSet)
    sizeSlider:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 0, -16)
    sizeSlider:SetWidth(280)

    local titleSizeGet, titleSizeSet = trackerSetting("titleSizeDelta")
    local titleSizeSlider = Options:CreateSlider(content, L["Title Size Offset"], -6, 12, 0.5, titleSizeGet, titleSizeSet)
    titleSizeSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -16)
    titleSizeSlider:SetWidth(280)
    Options:AttachTooltip(titleSizeSlider, L["Title Size Offset"],
        L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."])

    local headerSizeGet, headerSizeSet = trackerSetting("headerSizeDelta")
    local headerSizeSlider = Options:CreateSlider(content, L["Header Size Offset"], -8, 12, 0.5, headerSizeGet, headerSizeSet)
    headerSizeSlider:SetPoint("TOPLEFT", titleSizeSlider, "BOTTOMLEFT", 0, -16)
    headerSizeSlider:SetWidth(280)
    Options:AttachTooltip(headerSizeSlider, L["Header Size Offset"],
        L["Sizes the section headers (Quests, Campaign, and so on) independently of the quest text. Added on top of the Font Size above: the default 4 keeps headers at their current size, lower shrinks them (handy on a low UI scale), higher enlarges them."])

    -- Passed straight to FontString:SetFont, which takes a comma-joined combo and ignores unknown tokens, so "" means no outline
    local OUTLINE_OPTIONS = {
        { value = "",                          label = L["None"] },
        { value = "OUTLINE",                   label = L["Outline"] },
        { value = "THICKOUTLINE",              label = L["Thick"] },
        { value = "MONOCHROME",                label = L["Mono"] },
        { value = "MONOCHROME, OUTLINE",       label = L["Mono Outline"] },
        { value = "MONOCHROME, THICKOUTLINE",  label = L["Mono Thick"] },
    }
    local outlineGet, outlineSet = trackerSetting("fontOutline")
    local outlineDD = Options:CreateDropdown(content, L["Font Outline"],
        OUTLINE_OPTIONS, outlineGet, outlineSet)
    outlineDD:SetPoint("TOPLEFT", headerSizeSlider, "BOTTOMLEFT", 0, -16)
    outlineDD:SetWidth(280)

    local shadowGet, shadowSet = trackerSetting("textShadow")
    local shadowCheck = Options:CreateCheckbox(content, L["Text Shadow"], shadowGet, shadowSet,
        L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."])
    shadowCheck:SetPoint("TOPLEFT", outlineDD, "BOTTOMLEFT", 0, -16)

    local function shadowColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.textShadowColor or { r = 0, g = 0, b = 0, a = 1 }
    end
    local function shadowColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.textShadowColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.UpdateFrame then ZP:UpdateFrame() end
    end
    local shadowPicker = Options:CreateColorPicker(content, L["Shadow Color"], shadowColorGet, shadowColorSet)
    shadowPicker:SetPoint("LEFT", shadowCheck, "RIGHT", 120, 0)

    local shStrengthGet, shStrengthSet = trackerSetting("textShadowStrength")
    local shadowSizeSlider = Options:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5, shStrengthGet, shStrengthSet)
    shadowSizeSlider:SetPoint("TOPLEFT", shadowCheck, "BOTTOMLEFT", 0, -14)
    shadowSizeSlider:SetWidth(280)
    Options:AttachTooltip(shadowSizeSlider, L["Shadow Size"],
        L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while Text Shadow is on."])

    local scenarioHeader = Options:CreateSectionHeader(content, L["Scenario"])
    scenarioHeader:SetPoint("TOPLEFT", shadowSizeSlider, "BOTTOMLEFT", 0, -16)

    local scShadowGet, scShadowSet = scenarioSetting("scenarioTextShadow")
    local scShadowCheck = Options:CreateCheckbox(content, L["Text Shadow"], scShadowGet, scShadowSet,
        L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text — the banner is styled on its own."])
    scShadowCheck:SetPoint("TOPLEFT", scenarioHeader, "BOTTOMLEFT", 0, -10)

    local function scShadowColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scenarioTextShadowColor or { r = 0, g = 0, b = 0, a = 1 }
    end
    local function scShadowColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scenarioTextShadowColor = c end
        local S = ns:GetSubsystem("TrackerScenario")
        if S and S.ApplyBannerShadow then S:ApplyBannerShadow() end
    end
    local scShadowPicker = Options:CreateColorPicker(content, L["Shadow Color"], scShadowColorGet, scShadowColorSet)
    scShadowPicker:SetPoint("LEFT", scShadowCheck, "RIGHT", 120, 0)

    local scStrGet, scStrSet = scenarioSetting("scenarioTextShadowStrength")
    local scShadowSizeSlider = Options:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5, scStrGet, scStrSet)
    scShadowSizeSlider:SetPoint("TOPLEFT", scShadowCheck, "BOTTOMLEFT", 0, -14)
    scShadowSizeSlider:SetWidth(280)
    Options:AttachTooltip(scShadowSizeSlider, L["Shadow Size"],
        L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while the Scenario Text Shadow above is on."])

    local SCENARIO_ALIGN_OPTIONS = {
        { value = "LEFT",   label = L["Left"] },
        { value = "CENTER", label = L["Center"] },
        { value = "RIGHT",  label = L["Right"] },
    }
    local scAlignGet, scAlignSet = scenarioRenderSetting("scenarioTextAlign")
    local scAlignDD = Options:CreateDropdown(content, L["Banner Alignment"],
        SCENARIO_ALIGN_OPTIONS, scAlignGet, scAlignSet)
    scAlignDD:SetPoint("TOPLEFT", scShadowSizeSlider, "BOTTOMLEFT", 0, -16)
    scAlignDD:SetWidth(280)
    Options:AttachTooltip(scAlignDD, L["Banner Alignment"],
        L["Positions the scenario / delve banner within the tracker. Left lines it up with the quest text, Center keeps it centered (the default), and Right pushes it to the tracker's right edge."])

    local scSizeGet, scSizeSet = scenarioRenderSetting("scenarioTextSizeDelta")
    local scSizeSlider = Options:CreateSlider(content, L["Banner Text Size"], -4, 6, 0.5, scSizeGet, scSizeSet)
    scSizeSlider:SetPoint("TOPLEFT", scAlignDD, "BOTTOMLEFT", 0, -16)
    scSizeSlider:SetWidth(280)
    Options:AttachTooltip(scSizeSlider, L["Banner Text Size"],
        L["Grows or shrinks the scenario / delve banner's Stage and name text. 0 is the default size. The banner artwork is a fixed size, so large values may overflow it."])

    local scCritSizeGet, scCritSizeSet = scenarioRenderSetting("scenarioFontSize")
    local scCritSizeSlider = Options:CreateSlider(content, L["Criteria Text Size"], 8, 24, 0.5, scCritSizeGet, scCritSizeSet)
    scCritSizeSlider:SetPoint("TOPLEFT", scSizeSlider, "BOTTOMLEFT", 0, -16)
    scCritSizeSlider:SetWidth(280)
    Options:AttachTooltip(scCritSizeSlider, L["Criteria Text Size"],
        L["Sizes the scenario / delve objective (criteria) lines shown under the banner, separately from the Banner Text Size above. Raise it if the criteria text looks small next to your quest and World Quest text."])

    local trackerHeader = Options:CreateSectionHeader(content, L["Tracker"])
    -- Anchored at the end of the builder, under a section built further down

    local bgGet, bgSet = trackerSetting("showBackground")
    local bgCheck = Options:CreateCheckbox(content, L["Background"], bgGet, bgSet)
    bgCheck:SetPoint("TOPLEFT", trackerHeader, "BOTTOMLEFT", 0, -10)

    local function bgColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.backgroundColor or { r = 0, g = 0, b = 0, a = 0.6 }
    end
    local function bgColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.backgroundColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local bgPicker = Options:CreateColorPicker(content, L["Background Color"], bgColorGet, bgColorSet)
    bgPicker:SetPoint("LEFT", bgCheck, "RIGHT", 120, 0)

    local borderGet, borderSet = trackerSetting("showBorder")
    local borderCheck = Options:CreateCheckbox(content, L["Border"], borderGet, borderSet)
    borderCheck:SetPoint("TOPLEFT", bgCheck, "BOTTOMLEFT", 0, -10)

    local function borderColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.borderColor or { r = 0.635, g = 0.000, b = 0.039, a = 1 }
    end
    local function borderColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.borderColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local borderPicker = Options:CreateColorPicker(content, L["Border Color"], borderColorGet, borderColorSet)
    borderPicker:SetPoint("TOPLEFT", bgPicker, "BOTTOMLEFT", 0, -8)
    alignSwatchTo(borderPicker, bgPicker)

    local bThickGet, bThickSet = trackerSetting("borderSize")
    local borderThickSlider = Options:CreateSlider(content, L["Border Thickness"], 1, 5, 0.5, bThickGet, bThickSet)
    borderThickSlider:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 0, -20)
    borderThickSlider:SetWidth(280)

    local hbBarHeader = Options:CreateSectionHeader(content, L["Header Bar"])
    hbBarHeader:SetPoint("TOPLEFT", borderThickSlider, "BOTTOMLEFT", 0, -20)

    local hbGet, hbSet = headerBarSetting("headerBar")
    local hbCheck = Options:CreateCheckbox(content, L["Header bar"], hbGet, hbSet,
        L["Draws a coloured gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to the default Blizzard tracker. Off by default."])
    hbCheck:SetPoint("TOPLEFT", hbBarHeader, "BOTTOMLEFT", 0, -10)

    local function hbColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.headerBarColor or { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }
    end
    local function hbColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.headerBarColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.ApplyHeaderBars then Tracker:ApplyHeaderBars() end
    end
    local hbPicker = Options:CreateColorPicker(content, L["Bar Color"], hbColorGet, hbColorSet)
    hbPicker:SetPoint("LEFT", hbCheck, "RIGHT", 120, 0)
    alignSwatchTo(hbPicker, bgPicker)

    local HB_STYLE_OPTIONS = {
        { value = 1, label = L["Header Bar 1"] },
        { value = 2, label = L["Header Bar 2"] },
    }
    local hbStyleGet, hbStyleSet = headerBarSetting("headerBarStyle")
    local hbStyleDD = Options:CreateDropdown(content, L["Bar Style"], HB_STYLE_OPTIONS, hbStyleGet, hbStyleSet)
    hbStyleDD:SetWidth(150)
    hbStyleDD:SetPoint("TOPLEFT", hbCheck, "BOTTOMLEFT", 0, -14)
    Options:AttachTooltip(hbStyleDD, L["Bar Style"],
        L["Header Bar 1 is a horizontal gradient (bright on the left, dark on the right). Header Bar 2 is a vertical gradient (bright at the top, dark at the bottom). Bar Color, Bar Height, and Soft edges all apply to whichever style you pick."])

    local hbSoftGet, hbSoftSet = headerBarSetting("headerBarSoftEdges")
    local hbSoftCheck = Options:CreateCheckbox(content, L["Soft edges"], hbSoftGet, hbSoftSet,
        L["Feathers the top, left, and right edges of the header bar so it blends into the UI instead of sitting in a hard box. The gradient colour is unchanged. Only applies while Header bar is on; off by default."])
    hbSoftCheck.label:ClearAllPoints()
    hbSoftCheck.label:SetPoint("RIGHT", hbSoftCheck, "LEFT", -4, 1)
    hbSoftCheck:SetPoint("LEFT", hbStyleDD.button, "RIGHT", 24 + (hbSoftCheck.label:GetStringWidth() or 70), 1)
    -- The label sits LEFT here, so flip the tooltip's right-extending hit rect to the left
    hbSoftCheck:SetHitRectInsets(-((hbSoftCheck.label:GetStringWidth() or 70) + 8), 0, 0, 0)

    local hbHeightGet, hbHeightSet = headerBarSetting("headerBarHeight")
    local hbHeightSlider = Options:CreateSlider(content, L["Bar Height"], 6, 26, 0.5, hbHeightGet, hbHeightSet)
    hbHeightSlider:SetPoint("TOPLEFT", hbStyleDD, "BOTTOMLEFT", 0, -14)
    hbHeightSlider:SetWidth(280)
    Options:AttachTooltip(hbHeightSlider, L["Bar Height"],
        L["How tall the section-header bar is. The bar is centred on the header row, so larger values fill more of it."])

    local hbSoftStrGet, hbSoftStrSet = headerBarSetting("headerBarSoftEdgeStrength")
    local hbSoftSlider = Options:CreateSlider(content, L["Edge Softness"], 1, 10, 0.5, hbSoftStrGet, hbSoftStrSet)
    hbSoftSlider:SetPoint("TOPLEFT", hbHeightSlider, "BOTTOMLEFT", 0, -14)
    hbSoftSlider:SetWidth(280)
    Options:AttachTooltip(hbSoftSlider, L["Edge Softness"],
        L["How soft the header bar's feathered edges are when Soft edges is on. Higher is softer; lower tightens toward a hard edge."])

    local skinsHeader = Options:CreateSectionHeader(content, L["Tracker Skins"])
    skinsHeader:SetPoint("TOPLEFT", scCritSizeSlider, "BOTTOMLEFT", 0, -16)

    local sbGet, sbSet = trackerSetting("scrollBarBg")
    local sbCheck = Options:CreateCheckbox(content, L["Scroll Bar Background"], sbGet, sbSet)
    sbCheck:SetPoint("TOPLEFT", skinsHeader, "BOTTOMLEFT", 0, -10)

    local function sbColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scrollBarBgColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
    end
    local function sbColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scrollBarBgColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local sbPicker = Options:CreateColorPicker(content, L["Scroll Bar Color"], sbColorGet, sbColorSet)
    sbPicker:SetPoint("LEFT", sbCheck, "RIGHT", 170, 0)

    local thumbSkinGet, thumbSkinSet = trackerSetting("skinScrollBar")
    local thumbSkinCheck = Options:CreateCheckbox(content, L["Solid color thumb"],
        thumbSkinGet, thumbSkinSet,
        L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-colour block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."])
    thumbSkinCheck:SetPoint("TOPLEFT", sbCheck, "BOTTOMLEFT", 0, -12)

    local function thumbColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scrollBarThumbColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.90 }
    end
    local function thumbColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scrollBarThumbColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local thumbColorPicker = Options:CreateColorPicker(content, L["Thumb Color"], thumbColorGet, thumbColorSet)
    thumbColorPicker:SetPoint("LEFT", thumbSkinCheck, "RIGHT", 170, 0)
    alignSwatchTo(thumbColorPicker, sbPicker)

    local twGet, twSet = trackerSetting("scrollBarThumbWidth")
    local thumbWidthSlider = Options:CreateSlider(content, L["Thumb Width"], 4, 16, 0.5, twGet, twSet)
    thumbWidthSlider:SetPoint("TOPLEFT", thumbSkinCheck, "BOTTOMLEFT", 0, -14)
    thumbWidthSlider:SetWidth(280)

    local hideArrowsGet, hideArrowsSet = trackerSetting("hideScrollArrows")
    local hideArrowsCheck = Options:CreateCheckbox(content, L["Hide scroll bar arrows"],
        hideArrowsGet, hideArrowsSet,
        L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."])
    hideArrowsCheck:SetPoint("TOPLEFT", thumbWidthSlider, "BOTTOMLEFT", 0, -14)

    local colorsHeader = Options:CreateSectionHeader(content, L["Colors & Dimensions"])
    colorsHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    local resetBtn = Options:CreateYellowButton(content, L["Reset to Defaults"], function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Reset all Appearance settings to defaults?"],
            button1 = L["Reset"],
            button2 = L["Cancel"],
            onAccept = function()
                local DB = ns:GetSubsystem("DB")
                if DB and DB.ResetTrackerAppearance then DB:ResetTrackerAppearance() end
                ReloadUI()
            end,
        })
    end)
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("LEFT", colorsHeader, "LEFT", 320, 0)

    local function titleColorGet()
        local DB = ns:GetSubsystem("DB")
        local c = DB and DB.db.profile.tracker.titleColorOverride
        return c or { r = 1, g = 0.82, b = 0, a = 1 }
    end
    local function titleColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.titleColorOverride = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local titlePicker
    local function clearTitleColor()
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.titleColorOverride = nil end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
        if titlePicker and titlePicker.paint then titlePicker.paint() end
    end
    titlePicker = Options:CreateColorPicker(content, L["Quest Title Color Override"], titleColorGet, titleColorSet)
    titlePicker:SetPoint("TOPLEFT", colorsHeader, "BOTTOMLEFT", 0, -16)

    local clearBtn = Options:CreateYellowButton(content, L["Clear"], clearTitleColor)
    clearBtn:SetSize(60, 18)
    clearBtn:SetPoint("LEFT", titlePicker, "RIGHT", 8, 0)

    Options:AttachTooltip(titlePicker, L["Quest Title Color Override"],
        L["When cleared, falls back to difficulty coloring or default yellow."])

    local titleClassGet, titleClassSet = trackerSetting("titleColorUseClass")
    local titleClassCheck = Options:CreateCheckbox(content, L["Use class color"],
        titleClassGet, titleClassSet,
        L["Colors quest, achievement, and endeavor titles with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."])
    titleClassCheck:SetPoint("TOPLEFT", titlePicker, "BOTTOMLEFT", 0, -10)

    local recolorGet, recolorSet = trackerSetting("overrideCompleteGreen")
    local recolorCheck = Options:CreateCheckbox(content,
        L["Use title color for completed quests"],
        recolorGet, recolorSet,
        L["Instead of green."])
    recolorCheck:SetPoint("TOPLEFT", titleClassCheck, "BOTTOMLEFT", 0, -8)

    local function headerColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.headerColor or { r = 0.93, g = 0.32, b = 0.10, a = 1 }
    end
    local function headerColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.headerColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local headerPicker = Options:CreateColorPicker(content, L["Section Header Color"], headerColorGet, headerColorSet)
    headerPicker:SetPoint("TOPLEFT", recolorCheck, "BOTTOMLEFT", 0, -16)
    alignSwatchTo(headerPicker, titlePicker)

    local headerClassGet, headerClassSet = trackerSetting("headerColorUseClass")
    local headerClassCheck = Options:CreateCheckbox(content, L["Use class color"],
        headerClassGet, headerClassSet,
        L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."])
    headerClassCheck:SetPoint("TOPLEFT", headerPicker, "BOTTOMLEFT", 0, -10)

    local function dividerColorGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.headerDividerColor or { r = 0.92, g = 0.72, b = 0.02, a = 0.85 }
    end
    local function dividerColorSet(c)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.headerDividerColor = c end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.ApplyHeaderDividers then Tracker:ApplyHeaderDividers() end
    end
    local dividerPicker = Options:CreateColorPicker(content, L["Divider Line Color"], dividerColorGet, dividerColorSet)
    dividerPicker:SetPoint("TOPLEFT", headerClassCheck, "BOTTOMLEFT", 0, -14)
    alignSwatchTo(dividerPicker, titlePicker)
    Options:AttachTooltip(dividerPicker, L["Divider Line Color"],
        L["Sets the color of the thin line under each section header. Defaults to the original gold."])

    local function scaleGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.scale or 1.0
    end
    local function scaleSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.scale = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if not Tracker then return end
        -- SetScale is protected once the tracker has secure item-button descendants, so in combat only save and let Render apply it at combat-end
        if not InCombatLockdown() and Tracker.frame then
            Tracker.frame:SetScale(value)
        elseif Tracker.Refresh then
            Tracker:Refresh()
        end
    end
    local scaleSlider = Options:CreateSlider(content, L["Tracker Scale"], 0.7, 1.5, 0.05, scaleGet, scaleSet)
    scaleSlider:SetPoint("TOPLEFT", dividerPicker, "BOTTOMLEFT", 0, -32)
    scaleSlider:SetWidth(280)

    local function spacingGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.blockSpacing or 4
    end
    local function spacingSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.blockSpacing = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local spacingSlider = Options:CreateSlider(content, L["Block Spacing"], 0, 12, 0.5, spacingGet, spacingSet)
    spacingSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -16)
    spacingSlider:SetWidth(280)

    local function lineSpacingGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.lineSpacing or 0
    end
    local function lineSpacingSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.lineSpacing = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local lineSpacingSlider = Options:CreateSlider(content, L["Line Spacing"], 0, 12, 1, lineSpacingGet, lineSpacingSet)
    lineSpacingSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -16)
    lineSpacingSlider:SetWidth(280)
    Options:AttachTooltip(lineSpacingSlider, L["Line Spacing"],
        L["Adds vertical space between a quest's objective lines, across the whole tracker. 0 keeps the default spacing."])

    local function headerSpacingGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.headerSpacing or 0
    end
    local function headerSpacingSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.headerSpacing = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local headerSpacingSlider = Options:CreateSlider(content, L["Header Spacing"], -2, 12, 1, headerSpacingGet, headerSpacingSet)
    headerSpacingSlider:SetPoint("TOPLEFT", lineSpacingSlider, "BOTTOMLEFT", 0, -16)
    headerSpacingSlider:SetWidth(280)
    Options:AttachTooltip(headerSpacingSlider, L["Header Spacing"],
        L["Adds or removes space around section headers and beneath each quest's title. 0 keeps the default spacing."])

    -- Scoped so these locals release at the end of the block - Lua caps a function at 200 active locals
    local cardTail
    do
    local cardHeader = Options:CreateSectionHeader(content, L["Quest Rows"])
    cardHeader:SetPoint("TOPLEFT", headerSpacingSlider, "BOTTOMLEFT", 0, -20)

    local LAYOUT_OPTIONS = {
        { value = "classic", label = L["Plain"] },
        { value = "card",    label = L["Card"] },
    }
    local layoutGet, layoutSet = trackerSetting("blockLayout")
    local layout = Options:CreateRadioGroup(content, L["Row Layout"],
        LAYOUT_OPTIONS, function() return layoutGet() or "classic" end, layoutSet, 300, 14,
        L["Row Layout"],
        L["How each quest is drawn in the tracker. |cffffffffPlain|r is the default look - text straight on the tracker background. |cffffffffCard|r gives every quest its own panel with a background and border, which makes long lists easier to read apart."])
    layout:SetPoint("TOPLEFT", cardHeader, "BOTTOMLEFT", 0, -8)

    local cardColorGet, cardColorSet = trackerSetting("cardColor")
    local cardColorPicker = Options:CreateColorPicker(content, L["Background Color"], cardColorGet, cardColorSet)
    cardColorPicker:SetPoint("TOPLEFT", layout, "BOTTOMLEFT", 0, -8)
    Options:AttachTooltip(cardColorPicker, L["Background Color"],
        L["Fill color behind each quest card. Only used while Row Layout is set to Card."])

    local cardBorderColorGet, cardBorderColorSet = trackerSetting("cardBorderColor")
    local cardBorderPicker = Options:CreateColorPicker(content, L["Border Color"], cardBorderColorGet, cardBorderColorSet)
    cardBorderPicker:SetPoint("TOPLEFT", cardColorPicker, "BOTTOMLEFT", 0, -10)
    alignSwatchTo(cardBorderPicker, cardColorPicker)
    Options:AttachTooltip(cardBorderPicker, L["Border Color"],
        L["Outline color around each quest card. Only used while Row Layout is set to Card."])

    local cardBorderSizeGet, cardBorderSizeSet = trackerSetting("cardBorderSize")
    local cardBorderSlider = Options:CreateSlider(content, L["Border Thickness"], 0, 4, 1,
        function() return cardBorderSizeGet() or 1 end, cardBorderSizeSet)
    cardBorderSlider:SetPoint("TOPLEFT", cardBorderPicker, "BOTTOMLEFT", 0, -20)
    cardBorderSlider:SetWidth(280)
    Options:AttachTooltip(cardBorderSlider, L["Border Thickness"],
        L["How thick the card outline is, in pixels. 0 hides the outline and leaves just the fill."])

    local cardPaddingGet, cardPaddingSet = trackerSetting("cardPadding")
    local cardPaddingSlider = Options:CreateSlider(content, L["Card Padding"], 2, 14, 1,
        function() return cardPaddingGet() or 6 end, cardPaddingSet)
    cardPaddingSlider:SetPoint("TOPLEFT", cardBorderSlider, "BOTTOMLEFT", 0, -16)
    cardPaddingSlider:SetWidth(280)
    Options:AttachTooltip(cardPaddingSlider, L["Card Padding"],
        L["Breathing room between a card's edge and the text inside it. Larger values make taller cards."])

    local tintGet, tintSet = trackerSetting("cardTintByType")
    local tintCheck = Options:CreateCheckbox(content, L["Tint cards by quest type"], tintGet, tintSet,
        L["Give campaign, legendary, dungeon and raid quests their own card color so you can tell them apart at a glance. Anything else uses the plain background color above."])
    tintCheck:SetPoint("TOPLEFT", cardPaddingSlider, "BOTTOMLEFT", 0, -16)

    local campaignTintGet, campaignTintSet = trackerSetting("cardTintCampaign")
    local campaignTint = Options:CreateColorPicker(content, L["Campaign"], campaignTintGet, campaignTintSet)
    campaignTint:SetPoint("TOPLEFT", tintCheck, "BOTTOMLEFT", 0, -10)
    Options:AttachTooltip(campaignTint, L["Campaign"],
        L["Card color for campaign quests. Needs Tint cards by quest type switched on."])

    local legendaryTintGet, legendaryTintSet = trackerSetting("cardTintLegendary")
    local legendaryTint = Options:CreateColorPicker(content, L["Legendary"], legendaryTintGet, legendaryTintSet)
    legendaryTint:SetPoint("TOPLEFT", campaignTint, "BOTTOMLEFT", 0, -10)
    alignSwatchTo(legendaryTint, campaignTint)
    Options:AttachTooltip(legendaryTint, L["Legendary"],
        L["Card color for legendary quests. Needs Tint cards by quest type switched on."])

    local dungeonTintGet, dungeonTintSet = trackerSetting("cardTintDungeon")
    local dungeonTint = Options:CreateColorPicker(content, L["Dungeon"], dungeonTintGet, dungeonTintSet)
    dungeonTint:SetPoint("TOPLEFT", legendaryTint, "BOTTOMLEFT", 0, -10)
    alignSwatchTo(dungeonTint, campaignTint)
    Options:AttachTooltip(dungeonTint, L["Dungeon"],
        L["Card color for dungeon quests. Needs Tint cards by quest type switched on."])

    local raidTintGet, raidTintSet = trackerSetting("cardTintRaid")
    local raidTint = Options:CreateColorPicker(content, L["Raid"], raidTintGet, raidTintSet)
    raidTint:SetPoint("TOPLEFT", dungeonTint, "BOTTOMLEFT", 0, -10)
    alignSwatchTo(raidTint, campaignTint)
    Options:AttachTooltip(raidTint, L["Raid"],
        L["Card color for raid quests. Needs Tint cards by quest type switched on."])

    cardTail = raidTint
    end

    local function zbScaleGet()
        local DB = ns:GetSubsystem("DB")
        local st = DB and DB.db.profile.tracker.zoneProgressBar
        return (st and st.scale) or 1.0
    end
    local function zbScaleSet(value)
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetScale then
            ZP:SetScale(value)
        else
            local DB = ns:GetSubsystem("DB")
            local st = DB and DB.db.profile.tracker.zoneProgressBar
            if st then st.scale = value end
        end
    end
    local zbScaleSlider = Options:CreateSlider(content, L["Zone Bar Scale"], 0.5, 2.0, 0.05, zbScaleGet, zbScaleSet)
    zbScaleSlider:SetPoint("TOPLEFT", cardTail, "BOTTOMLEFT", 0, -20)
    zbScaleSlider:SetWidth(280)

    local function zbState()
        local DB = ns:GetSubsystem("DB")
        local p = DB and DB.db.profile.tracker
        if not p then return nil end
        p.zoneProgressBar = p.zoneProgressBar or {}
        return p.zoneProgressBar
    end
    local function zbZP() return ns:GetSubsystem("TrackerZoneProgress") end

    local zbHeader = Options:CreateSectionHeader(content, L["Zone Bar Appearance"])
    zbHeader:SetPoint("TOPLEFT", zbScaleSlider, "BOTTOMLEFT", 0, -20)

    local zbBgGet = function() local st = zbState(); return not (st and st.showBackground == false) end
    local zbBgSet = function(v)
        local st = zbState(); if st then st.showBackground = v end
        local ZP = zbZP(); if ZP and ZP.SetShowBackground then ZP:SetShowBackground(v) end
    end
    local zbBgCheck = Options:CreateCheckbox(content, L["Background"], zbBgGet, zbBgSet)
    zbBgCheck:SetPoint("TOPLEFT", zbHeader, "BOTTOMLEFT", 0, -12)

    local zbBorderGet = function() local st = zbState(); return not (st and st.showBorder == false) end
    local zbBorderSet = function(v)
        local st = zbState(); if st then st.showBorder = v end
        local ZP = zbZP(); if ZP and ZP.SetShowBorder then ZP:SetShowBorder(v) end
    end
    local zbBorderCheck = Options:CreateCheckbox(content, L["Border"], zbBorderGet, zbBorderSet)
    zbBorderCheck:SetPoint("TOPLEFT", zbBgCheck, "BOTTOMLEFT", 0, -12)

    local function zbBorderColorGet()
        local st = zbState()
        return (st and st.borderColor) or { r = 0.635, g = 0.000, b = 0.039, a = 1 }
    end
    local function zbBorderColorSet(c)
        local st = zbState(); if st then st.borderColor = c end
        local ZP = zbZP(); if ZP and ZP.SetBorderColor then ZP:SetBorderColor(c) end
    end
    local zbBorderColorPicker = Options:CreateColorPicker(content, L["Border Color"], zbBorderColorGet, zbBorderColorSet)
    zbBorderColorPicker:SetPoint("LEFT", zbBorderCheck, "LEFT", 90, 0)

    local zbFontList = { { value = "", label = L["Same as tracker font"] } }
    do
        local base = (Media and Media.GetFontList and Media:GetFontList()) or {}
        for i = 1, #base do zbFontList[#zbFontList + 1] = base[i] end
    end
    local zbFontGet = function() local st = zbState(); return (st and st.font) or "" end
    local zbFontSet = function(v)
        local st = zbState(); if st then st.font = (v ~= "" and v) or nil end
        local ZP = zbZP(); if ZP and ZP.SetBarFont then ZP:SetBarFont(v) end
    end
    local zbFontDD = Options:CreateFontDropdown(content, L["Font"], zbFontList, zbFontGet, zbFontSet)
    zbFontDD:SetPoint("TOPLEFT", zbBorderCheck, "BOTTOMLEFT", 0, -14)
    zbFontDD:SetWidth(280)

    local zbTexList = (Media and Media.GetStatusBarList and Media:GetStatusBarList()) or {}
    local zbTexGet = function() local st = zbState(); return (st and st.barTexture) or "Blizzard" end
    local zbTexSet = function(v)
        local st = zbState(); if st then st.barTexture = (v ~= "" and v) or nil end
        local ZP = zbZP(); if ZP and ZP.SetBarTexture then ZP:SetBarTexture(v) end
    end
    local zbTexDD = Options:CreateStatusBarDropdown(content, L["Bar Texture"], zbTexList, zbTexGet, zbTexSet)
    zbTexDD:SetPoint("TOPLEFT", zbFontDD, "BOTTOMLEFT", 0, -14)
    zbTexDD:SetWidth(280)
    Options:AttachTooltip(zbTexDD, L["Bar Texture"],
        L["Sets the fill texture of the zone progress bar. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."])

    local function zbBarColorGet()
        local st = zbState()
        return (st and st.barColor) or { r = 0.26, g = 0.42, b = 1.0, a = 1 }
    end
    local function zbBarColorSet(c)
        local st = zbState(); if st then st.barColor = c end
        local ZP = zbZP(); if ZP and ZP.SetBarColor then ZP:SetBarColor(c) end
    end
    local zbBarColorPicker = Options:CreateColorPicker(content, L["Bar Color"], zbBarColorGet, zbBarColorSet)
    zbBarColorPicker:SetPoint("TOPLEFT", zbTexDD, "BOTTOMLEFT", 0, -16)

    local function zbHeaderColorGet()
        local st = zbState()
        return (st and st.headerColor) or { r = 0.93, g = 0.32, b = 0.10, a = 1 }
    end
    local function zbHeaderColorSet(c)
        local st = zbState(); if st then st.headerColor = c end
        local ZP = zbZP(); if ZP and ZP.SetHeaderColor then ZP:SetHeaderColor(c) end
    end
    local zbHeaderPicker = Options:CreateColorPicker(content, L["Header Color"], zbHeaderColorGet, zbHeaderColorSet)
    zbHeaderPicker:SetPoint("TOPLEFT", zbBarColorPicker, "BOTTOMLEFT", 0, -16)

    local function zbCountColorGet()
        local st = zbState()
        return (st and st.countColor) or { r = 0.92, g = 0.72, b = 0.02, a = 1 }
    end
    local function zbCountColorSet(c)
        local st = zbState(); if st then st.countColor = c end
        local ZP = zbZP(); if ZP and ZP.SetCountColor then ZP:SetCountColor(c) end
    end
    local zbCountPicker = Options:CreateColorPicker(content, L["Count Color"], zbCountColorGet, zbCountColorSet)
    zbCountPicker:SetPoint("TOPLEFT", zbHeaderPicker, "BOTTOMLEFT", 0, -12)
    alignSwatchTo(zbCountPicker, zbHeaderPicker)

    -- Anchored last because it re-homes the Tracker section built far above
    trackerHeader:SetPoint("TOPLEFT", hideArrowsCheck, "BOTTOMLEFT", 0, -20)
end)
