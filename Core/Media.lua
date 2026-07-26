local _, ns = ...

local Media = ns:RegisterSubsystem("Media", {})

local SOUNDS = {
    { name = "EQ: Work Complete",   file = 558132 },   -- PeonBuildingComplete1.ogg
    { name = "EQ: BloodElf (M)",    file = 539400 },
    { name = "EQ: BloodElf (F)",    file = 539175 },
    { name = "EQ: Draenei (M)",     file = 539661 },
    { name = "EQ: Draenei (F)",     file = 539676 },
    { name = "EQ: Dwarf (M)",       file = 540042 },
    { name = "EQ: Dwarf (F)",       file = 539981 },
    { name = "EQ: Gnome (M)",       file = 540512 },
    { name = "EQ: Gnome (F)",       file = 540432 },
    { name = "EQ: Goblin (M)",      file = 542005 },
    { name = "EQ: Goblin (F)",      file = 541735 },
    { name = "EQ: Human (M)",       file = 540703 },
    { name = "EQ: Human (F)",       file = 540654 },
    { name = "EQ: NightElf (M)",    file = 541085 },
    { name = "EQ: NightElf (F)",    file = 541031 },
    { name = "EQ: Orc (M)",         file = 541401 },
    { name = "EQ: Orc (F)",         file = 541317 },
    { name = "EQ: Pandaren (M)",    file = 630070 },
    { name = "EQ: Pandaren (F)",    file = 636419 },
    { name = "EQ: Tauren (M)",      file = 561484 },
    { name = "EQ: Tauren (F)",      file = 542997 },
    { name = "EQ: Troll (M)",       file = 543307 },
    { name = "EQ: Troll (F)",       file = 543273 },
    { name = "EQ: Undead (M)",      file = 542775 },
    { name = "EQ: Undead (F)",      file = 542684 },
    { name = "EQ: Worgen (M)",      file = 542228 },
    { name = "EQ: Worgen (F)",      file = 542028 },
}

local FONT_PATH = [[Interface\AddOns\EverythingQuests\Media\Fonts\]]
local FONTS = {
    { name = "GothamXNarrow Black",      file = FONT_PATH .. "GothamXNarrow-Black.ttf" },  -- DB default
    { name = "Avquest",                  file = FONT_PATH .. "Avquest.ttf" },
    { name = "Barlow Condensed",         file = FONT_PATH .. "BarlowCondensed-Regular.ttf" },
    { name = "Barlow Condensed Medium",  file = FONT_PATH .. "BarlowCondensed-Medium.ttf" },
    { name = "Barlow Condensed SemiBold",file = FONT_PATH .. "BarlowCondensed-SemiBold.ttf" },
    { name = "Barlow Condensed Bold",    file = FONT_PATH .. "BarlowCondensed-Bold.ttf" },
    { name = "Beep",                     file = FONT_PATH .. "Beep-Regular.otf" },
    { name = "Beep Medium",              file = FONT_PATH .. "Beep-Medium.otf" },
    { name = "Beep Bold",                file = FONT_PATH .. "Beep-Bold.otf" },
    { name = "Exo 2 ExtraBold",          file = FONT_PATH .. "Exo2-ExtraBold.ttf" },
    { name = "GoodBrush",                file = FONT_PATH .. "GoodBrush.ttf" },
    { name = "Gotham Narrow Black",      file = FONT_PATH .. "GothamNarrowBlack.ttf" },
    { name = "Inter",                    file = FONT_PATH .. "Inter-Regular.ttf" },
    { name = "Inter SemiBold",           file = FONT_PATH .. "Inter-SemiBold.ttf" },
    { name = "Inter Bold",               file = FONT_PATH .. "Inter-Bold.ttf" },
    { name = "Josefin Sans Bold",        file = FONT_PATH .. "JosefinSans-Bold.ttf" },
    { name = "Kimberley",                file = FONT_PATH .. "Kimberley.ttf" },
    { name = "Lemon",                    file = FONT_PATH .. "Lemon-Regular.ttf" },
    { name = "Metal Lord",               file = FONT_PATH .. "Metal-Lord.ttf" },
    { name = "Montserrat",               file = FONT_PATH .. "Montserrat-Regular.ttf" },
    { name = "Montserrat Medium",        file = FONT_PATH .. "Montserrat-Medium.ttf" },
    { name = "Montserrat SemiBold",      file = FONT_PATH .. "Montserrat-SemiBold.ttf" },
    { name = "Montserrat Bold",          file = FONT_PATH .. "Montserrat-Bold.ttf" },
    { name = "Neuropol X",               file = FONT_PATH .. "neuropolxrg.ttf" },
    { name = "Noto Sans",                file = FONT_PATH .. "NotoSans-Regular.ttf" },
    { name = "Noto Sans SemiBold",       file = FONT_PATH .. "NotoSans-SemiBold.ttf" },
    { name = "Noto Sans Bold",           file = FONT_PATH .. "NotoSans-Bold.ttf" },
    { name = "Optimus Princeps",         file = FONT_PATH .. "OptimusPrinceps.ttf" },
    { name = "Oswald Light",             file = FONT_PATH .. "Oswald-Light.ttf" },
    { name = "Oswald",                   file = FONT_PATH .. "Oswald-Regular.ttf" },
    { name = "Oswald Bold",              file = FONT_PATH .. "Oswald-Bold.ttf" },
    { name = "Pepsi",                    file = FONT_PATH .. "Pepsi-Cyr-Lat.ttf" },
    { name = "Pricedown",                file = FONT_PATH .. "pricedown.ttf" },
    { name = "Reckoner",                 file = FONT_PATH .. "Reckoner.ttf" },
    { name = "Reckoner Bold",            file = FONT_PATH .. "Reckoner_Bold.ttf" },
    { name = "RingLink Medium",          file = FONT_PATH .. "RingLink-Medium.otf" },
    { name = "RingLink Bold",            file = FONT_PATH .. "RingLink-Bold.otf" },
    { name = "Roboto Bold",              file = FONT_PATH .. "Roboto-Bold.ttf" },
    { name = "Simply Sans",              file = FONT_PATH .. "SimplySans-Book.ttf" },
    { name = "Simply Sans Bold",         file = FONT_PATH .. "SimplySans-Bold.ttf" },
    { name = "Ubuntu Medium",            file = FONT_PATH .. "Ubuntu-Medium.ttf" },
    { name = "Ubuntu Bold",              file = FONT_PATH .. "Ubuntu-Bold.ttf" },
}

local WOW_FONTS = {
    { name = "WoW Default (Friz Quadrata)", file = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]] },
    { name = "WoW Arial Narrow",            file = [[Fonts\ARIALN.TTF]] },
    { name = "WoW Morpheus",                file = [[Fonts\MORPHEUS.TTF]] },
}

local STATUSBAR_PATH = [[Interface\AddOns\EverythingQuests\Media\Statusbars\]]
local STATUSBARS = {
    { name = "EQ Smooth",   file = STATUSBAR_PATH .. "EQ-Smooth.tga" },
    { name = "EQ Glaze",    file = STATUSBAR_PATH .. "EQ-Glaze.tga" },
    { name = "EQ Gradient", file = STATUSBAR_PATH .. "EQ-Gradient.tga" },
    { name = "EQ Bevel",    file = STATUSBAR_PATH .. "EQ-Bevel.tga" },
    { name = "EQ Glow",     file = STATUSBAR_PATH .. "EQ-Glow.tga" },
    { name = "EQ Gloss",    file = STATUSBAR_PATH .. "EQ-Gloss.tga" },
    { name = "EQ Steel",    file = STATUSBAR_PATH .. "EQ-Steel.tga" },
}

-- LSM's built-in "Blizzard" statusbar. Also EQ's fallback when LSM is absent.
local DEFAULT_STATUSBAR = [[Interface\TargetingFrame\UI-StatusBar]]

function Media:OnInitialize()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    for _, s in ipairs(SOUNDS) do
        LSM:Register("sound", s.name, s.file)
    end
    for _, f in ipairs(FONTS) do
        LSM:Register("font", f.name, f.file)
    end
    for _, f in ipairs(WOW_FONTS) do
        LSM:Register("font", f.name, f.file)
    end
    for _, s in ipairs(STATUSBARS) do
        LSM:Register("statusbar", s.name, s.file)
    end
    self.LSM = LSM
end

function Media:GetSoundList()
    local out = { { value = "NONE", label = "None" } }
    for _, s in ipairs(SOUNDS) do
        out[#out + 1] = { value = s.name, label = s.name:gsub("^EQ: ", "") }
    end
    return out
end

function Media:GetSoundFile(name)
    if name == "NONE" then return nil end
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("sound", name)
        if f then return f end
    end
    for _, s in ipairs(SOUNDS) do
        if s.name == name then return s.file end
    end
    return SOUNDS[1].file
end

function Media:GetFontList()
    local out = {}
    local LSM = self.LSM
    local names = LSM and LSM:List("font")
    if names and #names > 0 then
        for _, name in ipairs(names) do
            out[#out + 1] = { value = name, label = name }
        end
        return out
    end
    for _, f in ipairs(WOW_FONTS) do
        out[#out + 1] = { value = f.name, label = f.name }
    end
    for _, f in ipairs(FONTS) do
        out[#out + 1] = { value = f.name, label = f.name }
    end
    return out
end

function Media:GetFontFile(name)
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("font", name or "Friz Quadrata TT")
        if f then return f end
    end
    for _, f in ipairs(WOW_FONTS) do
        if f.name == name then return f.file end
    end
    return STANDARD_TEXT_FONT
end

function Media:GetStatusBarList()
    local out = {}
    local LSM = self.LSM
    local names = LSM and LSM:List("statusbar")
    if names and #names > 0 then
        for _, name in ipairs(names) do
            out[#out + 1] = { value = name, label = name }
        end
        return out
    end
    for _, s in ipairs(STATUSBARS) do
        out[#out + 1] = { value = s.name, label = s.name }
    end
    return out
end

function Media:GetStatusBarFile(name)
    local LSM = self.LSM
    if LSM then
        local f = LSM:Fetch("statusbar", name or "Blizzard")
        if f then return f end
    end
    for _, s in ipairs(STATUSBARS) do
        if s.name == name then return s.file end
    end
    return DEFAULT_STATUSBAR
end

local function setShadow(fontstring, enabled, color, strength)
    if enabled then
        fontstring:SetShadowColor(color and color.r or 0, color and color.g or 0, color and color.b or 0, color and color.a or 1)
        local d = strength or 2
        fontstring:SetShadowOffset(d, -d)
    else
        fontstring:SetShadowColor(0, 0, 0, 0)
        fontstring:SetShadowOffset(0, 0)
    end
end

local function applyShadow(cfg, fontstring)
    setShadow(fontstring, cfg and cfg.textShadow, cfg and cfg.textShadowColor,
              cfg and cfg.textShadowStrength)
end

function Media:ApplyTrackerFont(fontstring, sizeDelta, fontOverride)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    local file = self:GetFontFile(fontOverride or cfg.font)
    local size = math.max(8, (cfg.fontSize or 12) + (sizeDelta or 0))
    local outline = cfg.fontOutline or ""
    if file then fontstring:SetFont(file, size, outline) end
    applyShadow(cfg, fontstring)
end

function Media:ApplyTrackerTitleFont(fontstring, fontOverride)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    self:ApplyTrackerFont(fontstring, cfg.titleSizeDelta or 0, fontOverride)
end

function Media:ApplyTextShadow(fontstring)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    applyShadow(DB.db.profile.tracker, fontstring)
end

function Media:ApplyScenarioShadow(fontstring)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    setShadow(fontstring, cfg and cfg.scenarioTextShadow, cfg and cfg.scenarioTextShadowColor,
              (cfg and cfg.scenarioTextShadowStrength) or 1)
end

-- base must be captured before the first SetFont - GetFont() after a resize feeds the scaled size back in
function Media:ApplyScenarioFont(fontstring, base)
    if not (fontstring and base and base[1] and base[2]) then return end
    local DB = ns:GetSubsystem("DB")
    local delta = (DB and DB.db.profile.tracker.scenarioTextSizeDelta) or 0
    fontstring:SetFont(base[1], math.max(6, base[2] + delta), base[3] or "")
end

function Media:ApplyScenarioCriteriaFont(fontstring)
    if not fontstring then return end
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local cfg = DB.db.profile.tracker
    local file = self:GetFontFile(cfg.font)
    local size = math.max(8, cfg.scenarioFontSize or 13)
    if file then fontstring:SetFont(file, size, cfg.fontOutline or "") end
end
