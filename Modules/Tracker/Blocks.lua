local _, ns = ...

local Blocks = ns:RegisterSubsystem("TrackerBlocks", {})

Blocks.pool = {}
Blocks.active = {}
Blocks.byID = {}

local _subLines = {}

Blocks._fontGen     = 0
Blocks._renderGen   = 0
Blocks._fontFile    = nil
Blocks._fontSize    = nil
Blocks._fontOutline = nil

local _sweepScratch = {}

function Blocks:BeginRenderPass()
    local DB    = ns:GetSubsystem("DB")
    local t     = DB and DB.db.profile.tracker
    local dirty = false

    self._nowTs = time()

    local file, size, outline, titleDelta, shadow, shR, shG, shB, shA, shStr
    if t then
        local Media = ns:GetSubsystem("Media")
        file       = Media and Media.GetFontFile and Media:GetFontFile(t.font)
        size       = t.fontSize or 12
        outline    = t.fontOutline or ""
        titleDelta = t.titleSizeDelta or 0
        shadow     = t.textShadow and true or false
        local sc   = t.textShadowColor
        shR, shG, shB, shA = sc and sc.r or 0, sc and sc.g or 0, sc and sc.b or 0, sc and sc.a or 1
        shStr      = t.textShadowStrength or 2
    end
    -- Title offset + shadow feed the SAME change-gated SetFont/shadow pass as the
    -- font, so changing any of them bumps _fontGen and restyles all blocks. The
    -- shadow SIZE (textShadowStrength) must be in this gate too: pooled blocks
    -- only re-run ApplyTextShadow when _fontGen bumps, so without it dragging the
    -- Shadow Size slider would leave the Quests section stuck at its old offset
    -- while freshly-rendered sections (World Quests, etc.) update.
    if file ~= self._fontFile or size ~= self._fontSize or outline ~= self._fontOutline
       or titleDelta ~= self._titleSizeDelta or shadow ~= self._textShadow
       or shR ~= self._shR or shG ~= self._shG or shB ~= self._shB or shA ~= self._shA
       or shStr ~= self._shStr then
        self._fontFile, self._fontSize, self._fontOutline = file, size, outline
        self._titleSizeDelta = titleDelta
        self._textShadow = shadow
        self._shR, self._shG, self._shB, self._shA = shR, shG, shB, shA
        self._shStr = shStr
        self._fontGen = self._fontGen + 1
        dirty = true
    end

    local cL  = t and t.showLevelInTracker     and true or false
    local cQI = t and t.showQuestID            and true or false
    local cZT = (not t) or t.showZoneTag        ~= false
    local cON = (not t) or t.showObjectiveNumbers ~= false
    local cCB = (not t) or t.colorByDifficulty  ~= false
    local cOG = (not t) or t.overrideCompleteGreen ~= false
    local useClass = t and t.titleColorUseClass and true or false
    local tr, tg, tb
    if ns.Util and ns.Util.EffectiveTitleColor then tr, tg, tb = ns.Util.EffectiveTitleColor(t) end
    if cL ~= self._cL or cQI ~= self._cQI or cZT ~= self._cZT
       or cON ~= self._cON or cCB ~= self._cCB or cOG ~= self._cOG
       or tr ~= self._cTr or tg ~= self._cTg or tb ~= self._cTb
       or useClass ~= self._cUseClass then
        self._cL, self._cQI, self._cZT, self._cON, self._cCB = cL, cQI, cZT, cON, cCB
        self._cOG = cOG
        self._cTr, self._cTg, self._cTb = tr, tg, tb
        self._cUseClass = useClass
        dirty = true
    end

    -- Line/Header Spacing feed the change-gated SetSpacing/subGap/height pass, so a
    -- change must bump _renderGen or pooled Quests blocks stay frozen while freshly
    -- rebuilt sections update - the same trap the shadow-size note above describes.
    local lineSp   = t and t.lineSpacing   or 0
    local headerSp = t and t.headerSpacing or 0
    if lineSp ~= self._lineSpacing or headerSp ~= self._headerSpacing then
        self._lineSpacing, self._headerSpacing = lineSp, headerSp
        dirty = true
    end

    if dirty then self._renderGen = self._renderGen + 1 end

    for _, b in pairs(self.byID) do b._used = false end
    wipe(self.active)
end

local PAD_X, PAD_Y       = 6, 2
local TITLE_TO_CAT_GAP   = 1
local CAT_TO_SUB_GAP     = 2
local TITLE_TO_SUB_GAP   = 2
local ICON_SIZE          = 26
local ICON_TITLE_GAP     = 4
local CATEGORY_COLOR     = { 0.42, 0.69, 1.00 }

local NEW_WINDOW = 3600
local NEW_TAG    = "|cff6BAFFFNEW|r "

local _atlasOK = {}
local function atlasExists(atlas)
    if not atlas or atlas == "" then return false end
    local ok = _atlasOK[atlas]
    if ok == nil then
        ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
        _atlasOK[atlas] = ok
    end
    return ok
end

local function safeSetAtlas(tex, atlas, fallbackTexture, fallbackTexCoord)
    if atlasExists(atlas) then
        tex:SetAtlas(atlas, false)
        return true
    end
    tex:SetTexture(fallbackTexture or "Interface\\GossipFrame\\AvailableQuestIcon")
    if fallbackTexCoord then
        tex:SetTexCoord(unpack(fallbackTexCoord))
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    return false
end

local OUTER_GLOW = {}
local CENTER_FACE = {}
local CENTER_TURNIN = {}
do
    local QC = (Enum and Enum.QuestClassification) or {}
    local NORMAL = QC.Normal or -1

    OUTER_GLOW[NORMAL]                 = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Questline  or -2]    = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Campaign   or -3]    = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Calling    or -4]    = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Important  or -5]    = "UI-QuestPoiImportant-OuterGlow"
    OUTER_GLOW[QC.Legendary  or -6]    = "UI-QuestPoiLegendary-OuterGlow"
    OUTER_GLOW[QC.Recurring  or -7]    = "UI-QuestPoiRecurring-OuterGlow"
    OUTER_GLOW[QC.Meta       or -8]    = "UI-QuestPoiWrapper-OuterGlow"

    CENTER_FACE[NORMAL]                = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Questline or -2]    = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Campaign  or -3]    = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Calling   or -4]    = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Important or -5]    = "UI-QuestPoiImportant-QuestNumber"
    CENTER_FACE[QC.Legendary or -6]    = "UI-QuestPoiLegendary-QuestNumber"
    CENTER_FACE[QC.Recurring or -7]    = "UI-QuestPoiRecurring-QuestNumber"
    CENTER_FACE[QC.Meta      or -8]    = "UI-QuestPoiWrapper-QuestNumber"

    CENTER_TURNIN[NORMAL]              = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Questline or -2]  = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Campaign  or -3]  = "UI-QuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Calling   or -4]  = "UI-DailyQuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Important or -5]  = "UI-QuestPoiImportant-QuestBangTurnIn"
    CENTER_TURNIN[QC.Legendary or -6]  = "UI-QuestPoiLegendary-QuestBangTurnIn"
    CENTER_TURNIN[QC.Recurring or -7]  = "UI-QuestPoiRecurring-QuestBangTurnIn"
    CENTER_TURNIN[QC.Meta      or -8]  = "UI-QuestPoiWrapper-QuestBangTurnIn"
end

local function lookupClassification(table_, classification)
    local QC = (Enum and Enum.QuestClassification) or {}
    return table_[classification] or table_[QC.Normal or -1]
end

local function applyQuestIcon(iconGlow, icon, iconBang, q, focused)
    if not q then return end

    iconGlow:SetVertexColor(1, 1, 1)
    icon:SetVertexColor(1, 1, 1)
    iconBang:SetVertexColor(1, 1, 1)

    local glowAtlas = lookupClassification(OUTER_GLOW, q.classification)
    local faceAtlas = lookupClassification(CENTER_FACE, q.classification)
    if focused and faceAtlas then
        faceAtlas = faceAtlas .. "-SuperTracked"
    end

    local glowSet = safeSetAtlas(iconGlow, glowAtlas, "")
    if not glowSet then iconGlow:SetTexture(nil) end

    local faceSet = safeSetAtlas(icon, faceAtlas, "")
    if not faceSet then icon:SetTexture(nil) end

    if q.noBang then
        iconBang:SetTexture(nil)
        return
    end

    local bangAtlas
    if q.isComplete then
        bangAtlas = lookupClassification(CENTER_TURNIN, q.classification)
    else
        bangAtlas = "Quest-In-Progress-Icon-yellow"
    end
    local bangSet = safeSetAtlas(iconBang, bangAtlas, "")
    if not bangSet then iconBang:SetTexture(nil) end
end

function Blocks:ApplyQuestIcon(iconGlow, icon, iconBang, q, focused)
    applyQuestIcon(iconGlow, icon, iconBang, q, focused)
end

local colorizeProgress  = ns.Util.ColorizeProgress
local stripLeadingCount = ns.Util.StripLeadingCount

local function buildSubText(questData, simplifyMode, hideNumbers, completeHex)
    local done = "|cff" .. (completeHex or "44ff44")
    local objs = questData.objectives
    if not objs or #objs == 0 then
        local fb = questData.fallbackText
        if fb and fb ~= "" then
            if questData.isComplete then
                return "- " .. done .. fb .. "|r"
            end
            return "- " .. fb
        end
        return ""
    end

    if simplifyMode then
        for i = 1, #objs do
            if not objs[i].finished then
                local t = objs[i].text or ""
                if hideNumbers then t = stripLeadingCount(t) end
                return "- " .. colorizeProgress(t)
            end
        end
        local last = objs[#objs].text or ""
        if hideNumbers then last = stripLeadingCount(last) end
        return "|A:common-icon-checkmark:12:12|a " .. done .. last .. "|r"
    end

    local count = 0
    for i = 1, #objs do
        local o = objs[i]
        local txt = o.text or ""
        if hideNumbers then txt = stripLeadingCount(txt) end
        if o.finished then
            txt = "|A:common-icon-checkmark:12:12|a " .. done .. txt .. "|r"
        else
            txt = "- " .. colorizeProgress(txt)
        end
        count = count + 1
        _subLines[count] = txt
    end
    return table.concat(_subLines, "\n", 1, count)
end

local function buildBlock()
    local b = CreateFrame("Frame")

    b.iconHolder = CreateFrame("Frame", nil, b)
    b.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)

    b.iconGlow = b.iconHolder:CreateTexture(nil, "BACKGROUND")
    b.iconGlow:SetSize(50, 50)
    b.iconGlow:SetPoint("CENTER")
    b.iconGlow:SetBlendMode("ADD")
    -- Keep the classification glow but at half strength. ADD blend means
    -- alpha scales the added light, so 0.5 = ~50% less glow. Set once
    -- here; applyQuestIcon only touches the atlas + vertex color, never
    -- alpha, so this persists across pooled-block reuse.
    b.iconGlow:SetAlpha(0.5)

    b.icon = b.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    b.icon:SetSize(32, 32)
    b.icon:SetPoint("CENTER")

    b.iconBang = b.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    b.iconBang:SetSize(32, 32)
    b.iconBang:SetPoint("CENTER")

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(true)

    b.category = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.category:SetJustifyH("LEFT")
    b.category:SetWordWrap(false)
    b.category:SetTextColor(CATEGORY_COLOR[1], CATEGORY_COLOR[2], CATEGORY_COLOR[3])

    b.subText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.subText:SetJustifyH("LEFT")
    b.subText:SetWordWrap(true)
    b.subText:SetTextColor(0.85, 0.85, 0.85)

    b:EnableMouse(true)
    b:SetScript("OnMouseUp", function(self, button)
        local wasDragging = self._wasDragging
        self._wasDragging = nil
        if wasDragging or not self.questID then return end
        -- Combat-hide leaves the tracker shown at alpha 0 (Hide is protected), so
        -- ignore clicks on the invisible frame - otherwise they untrack/open menus.
        local T = ns:GetSubsystem("Tracker")
        if T and T.frame and T.frame._eqHidden then return end

        if button == "RightButton" then
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker and Tracker.ShowBlockMenu then
                Tracker:ShowBlockMenu(self, self.questID)
            end
            return
        end

        if button == "LeftButton" then
            local shiftPressed = IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE")
            if shiftPressed then
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker and Tracker.ToggleHidden then
                    Tracker:ToggleHidden(self.questID)
                end
                return
            end

            -- Optional Blizzard-style split (tracker.splitQuestClick): the
            -- left-side POI icon/circle focuses, the title opens the quest
            -- log. We hit-test by cursor X against the icon's right edge
            -- rather than giving the icon its own mouse handler, because the
            -- whole block is the drag-reorder target — a mouse-enabled child
            -- would swallow drags that start on the icon. GetCursorPosition
            -- is in raw pixels, so divide by the block's effective scale to
            -- compare against GetRight() (which is already in scaled coords).
            local DB  = ns:GetSubsystem("DB")
            local cfg = DB and DB.db.profile.tracker
            if cfg and cfg.splitQuestClick then
                local overIcon = false
                local ih = self.iconHolder
                if ih then
                    local mx = GetCursorPosition()
                    mx = mx / (self:GetEffectiveScale() or 1)
                    local iconRight = ih:GetRight()
                    if iconRight and mx <= iconRight then overIcon = true end
                end
                if overIcon then
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                        local Tracker = ns:GetSubsystem("Tracker")
                        if Tracker and Tracker.Refresh then Tracker:Refresh() end
                    end
                else
                    if C_AddOns and C_AddOns.LoadAddOn then
                        C_AddOns.LoadAddOn("Blizzard_QuestLog")
                    end
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(self.questID)
                    elseif ToggleQuestLog then
                        ToggleQuestLog()
                    end
                end
                return
            end

            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                local Tracker = ns:GetSubsystem("Tracker")
                if Tracker and Tracker.Refresh then Tracker:Refresh() end
            end
        end
    end)

    b:SetScript("OnEnter", function(self)
        if self._wasDragging or not self.questID then return end
        local RT = ns:GetSubsystem("TrackerRewardTooltip")
        if RT then RT:Show(self, self.questID) end
    end)
    b:SetScript("OnLeave", function()
        local RT = ns:GetSubsystem("TrackerRewardTooltip")
        if RT then RT:Hide() end
    end)

    local DD = ns:GetSubsystem("TrackerDragDrop")
    if DD and DD.WireBlock then DD:WireBlock(b) end

    b:HookScript("OnDragStart", function(self) self._wasDragging = true end)

    return b
end

function Blocks:AcquireFor(parent, questID)
    local b = self.byID[questID]
    if not b then
        b = tremove(self.pool) or buildBlock()
        b:SetParent(parent)
        b.iconHolder:ClearAllPoints()
        b.iconHolder:SetPoint("TOPLEFT", b, "TOPLEFT", PAD_X, -PAD_Y)
        b.title:ClearAllPoints()
        b.title:SetPoint("TOPLEFT",  b.iconHolder, "TOPRIGHT", ICON_TITLE_GAP, 1)
        b.title:SetPoint("TOPRIGHT", b, "TOPRIGHT", -PAD_X, -PAD_Y)
        b.category:ClearAllPoints()
        b.category:SetPoint("TOPLEFT",  b.title, "BOTTOMLEFT",  0, -TITLE_TO_CAT_GAP)
        b.category:SetPoint("TOPRIGHT", b.title, "BOTTOMRIGHT", 0, -TITLE_TO_CAT_GAP)
        self.byID[questID] = b
    elseif b:GetParent() ~= parent then
        b:SetParent(parent)
    end
    b.questID = questID
    b._used   = true
    b:Show()
    self.active[#self.active + 1] = b
    return b
end

function Blocks:Sweep()
    local s, n = _sweepScratch, 0
    for qid, b in pairs(self.byID) do
        if not b._used then
            n = n + 1
            s[n] = qid
        end
    end
    for i = 1, n do
        local qid = s[i]
        local b   = self.byID[qid]
        b:Hide()
        b:ClearAllPoints()
        b:SetParent(nil)
        b.questID = nil
        b._used   = false
        b._rID    = nil
        b._rGen   = nil
        b._rTitle = nil
        b._rDone  = nil
        b._rLevel = nil
        b._rClass = nil
        b._rZone  = nil
        b._rPin   = nil
        b._rNew   = nil
        b._rFoc   = nil
        b._rSimp  = nil
        b._rWidth = nil
        b._rObjN  = nil
        self.byID[qid] = nil
        self.pool[#self.pool + 1] = b
        s[i] = nil
    end
end

function Blocks:RenderQuest(block, questData, simplifyMode)
    local qid = questData.questID
    block.questID = qid

    local focused = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID() == qid) and true or false

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker or {}
    local isPinned = (DB and DB.char.pinned and DB.char.pinned[qid]) and true or false
    local isNew = (cfg.showRecentlyAddedTag and questData.firstSeen and questData.firstSeen > 0
                   and self._nowTs and (self._nowTs - questData.firstSeen) < NEW_WINDOW) and true or false

    local IB      = ns:GetSubsystem("TrackerItemButtons")
    local hasItem = (IB and IB.WantsButton and IB:WantsButton(qid)) and true or false
    local gutter  = (hasItem and IB.Gutter) and IB:Gutter() or 0

    local objs = questData.objectives
    local nObj = objs and #objs or 0
    local curW = block:GetWidth()
    local changed =
           block._rID    ~= qid
        or block._rGen   ~= self._renderGen
        or block._rTitle ~= questData.title
        or block._rDone  ~= (questData.isComplete and true or false)
        or block._rLevel ~= questData.level
        or block._rClass ~= questData.classification
        or block._rZone  ~= questData.zone
        or block._rPin   ~= isPinned
        or block._rNew   ~= isNew
        or block._rFoc   ~= focused
        or block._rSimp  ~= (simplifyMode and true or false)
        or block._rWidth ~= curW
        or block._rObjN  ~= nObj
        or block._rItem  ~= hasItem
    if not changed and nObj > 0 then
        local pt, pf = block._rObjT, block._rObjF
        for i = 1, nObj do
            local o = objs[i]
            if pt[i] ~= (o.text or "") or pf[i] ~= (o.finished and true or false) then
                changed = true
                break
            end
        end
    end
    if not changed then return end

    applyQuestIcon(block.iconGlow, block.icon, block.iconBang, questData, focused)

    -- Quests with a usable item reserve a left gutter so the item button sits directly
    -- left of the type icon; the icon (and the title anchored to it) shift right by gutter.
    block.iconHolder:ClearAllPoints()
    block.iconHolder:SetPoint("TOPLEFT", block, "TOPLEFT", PAD_X + gutter, -PAD_Y)

    local titleText = questData.title or ("Quest #" .. tostring(qid))
    if cfg.showLevelInTracker and questData.level and questData.level > 0 then
        titleText = ("[%d] %s"):format(questData.level, titleText)
    end
    if cfg.showQuestID and qid then
        titleText = titleText .. (" |cff666666(#%d)|r"):format(qid)
    end
    if isPinned then titleText = "|cffEBB706★|r " .. titleText end
    if isNew    then titleText = NEW_TAG .. titleText end
    block.title:SetText(titleText)

    local colorByDifficulty = cfg.colorByDifficulty ~= false
    local ovR, ovG, ovB = self._cTr, self._cTg, self._cTb
    local recolorComplete = (cfg.overrideCompleteGreen ~= false)
                            and ovR and true or false
    if questData.isComplete and not recolorComplete then
        block.title:SetTextColor(0.27, 0.85, 0.27)
    elseif ovR then
        block.title:SetTextColor(ovR, ovG, ovB)
    elseif colorByDifficulty and questData.level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(questData.level)
        block.title:SetTextColor(c.r, c.g, c.b)
    else
        block.title:SetTextColor(0.92, 0.72, 0.02)
    end

    local fontFile = self._fontFile
    if fontFile and block._fontGen ~= self._fontGen then
        local fontSize = self._fontSize
        local outline  = self._fontOutline
        block.title:SetFont(fontFile, math.max(8, fontSize + (self._titleSizeDelta or 0)), outline)
        block.subText:SetFont(fontFile, math.max(8, fontSize - 2), outline)
        block.category:SetFont(fontFile, math.max(8, fontSize - 3), outline)
        local Media = ns:GetSubsystem("Media")
        if Media and Media.ApplyTextShadow then
            Media:ApplyTextShadow(block.title)
            Media:ApplyTextShadow(block.subText)
            Media:ApplyTextShadow(block.category)
        end
        block._fontGen = self._fontGen
    end

    local categoryText = (cfg.showZoneTag ~= false) and questData.zone or nil
    local hasCategory = categoryText and categoryText ~= ""
    local subGap = math.max(0, (hasCategory and CAT_TO_SUB_GAP or TITLE_TO_SUB_GAP) + ns.Util.HeaderSpacing())
    block.subText:ClearAllPoints()
    if hasCategory then
        block.category:SetText(categoryText)
        block.category:Show()
        block.subText:SetPoint("TOPLEFT",  block.category, "BOTTOMLEFT",  0, -subGap)
        block.subText:SetPoint("TOPRIGHT", block.category, "BOTTOMRIGHT", 0, -subGap)
    else
        block.category:SetText("")
        block.category:Hide()
        block.subText:SetPoint("TOPLEFT",  block.title, "BOTTOMLEFT",  0, -subGap)
        block.subText:SetPoint("TOPRIGHT", block.title, "BOTTOMRIGHT", 0, -subGap)
    end

    local completeHex
    if recolorComplete then
        completeHex = ("%02x%02x%02x"):format(
            math.floor(ovR * 255 + 0.5),
            math.floor(ovG * 255 + 0.5),
            math.floor(ovB * 255 + 0.5))
    end
    local subText = buildSubText(questData, simplifyMode,
                                 cfg.showObjectiveNumbers == false, completeHex)
    block.subText:SetText(subText)

    -- Force a deterministic wrap width on the multi-line FontStrings.
    -- Without explicit SetWidth, GetStringHeight can return stale values
    -- on the first render after width changes, causing blocks to overlap.
    local blockW = curW
    if blockW and blockW > 0 then
        local titleW   = blockW - (ICON_SIZE + ICON_TITLE_GAP + PAD_X * 2 + gutter)
        local subTextW = titleW
        if titleW > 0 then
            block.title:SetWidth(titleW)
            block.subText:SetWidth(subTextW)
            if block.category:IsShown() then block.category:SetWidth(titleW) end
        end
    end

    block.subText:SetSpacing(ns.Util.LineSpacing())

    local titleH    = math.max(block.title:GetStringHeight(), ICON_SIZE)
    local categoryH = 0
    if block.category:IsShown() then
        categoryH = TITLE_TO_CAT_GAP + block.category:GetStringHeight()
    end
    local h = titleH + categoryH + subGap + block.subText:GetStringHeight() + PAD_Y * 2
    block:SetHeight(h)

    block._rID    = qid
    block._rGen   = self._renderGen
    block._rTitle = questData.title
    block._rDone  = questData.isComplete and true or false
    block._rLevel = questData.level
    block._rClass = questData.classification
    block._rZone  = questData.zone
    block._rPin   = isPinned
    block._rNew   = isNew
    block._rFoc   = focused
    block._rSimp  = simplifyMode and true or false
    block._rWidth = curW
    block._rObjN  = nObj
    block._rItem  = hasItem
    local pt = block._rObjT; if not pt then pt = {}; block._rObjT = pt end
    local pf = block._rObjF; if not pf then pf = {}; block._rObjF = pf end
    for i = 1, nObj do
        local o = objs[i]
        pt[i] = o.text or ""
        pf[i] = o.finished and true or false
    end
end
