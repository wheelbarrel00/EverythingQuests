local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local function hex(s)
    return {
        tonumber(s:sub(1, 2), 16) / 255,
        tonumber(s:sub(3, 4), 16) / 255,
        tonumber(s:sub(5, 6), 16) / 255,
    }
end

-- Barlow has no Cyrillic or CJK glyphs, so these clients keep their own font for every weight.
local CLIENT_FONT_LOCALES = { ruRU = true, koKR = true, zhCN = true, zhTW = true }

local fonts
if CLIENT_FONT_LOCALES[GetLocale()] then
    local client = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fonts = { Regular = client, Medium = client, SemiBold = client }
else
    local dir = lib.media .. "Fonts\\"
    fonts = {
        Regular  = dir .. "Barlow-Regular.ttf",
        Medium   = dir .. "Barlow-Medium.ttf",
        SemiBold = dir .. "Barlow-SemiBold.ttf",
    }
end

lib.tokens = {
    colors = {
        bg            = hex("121418"),
        chrome        = hex("0E1013"),
        surface       = hex("171A1F"),
        surfaceBorder = hex("23272E"),
        divider       = hex("20242A"),
        input         = hex("0F1114"),
        inputBorder   = hex("2A2E35"),
        borderStrong  = hex("3A3F48"),
        track         = hex("2E323A"),
        text          = hex("E8EAED"),
        label         = hex("C4C8CE"),
        navText       = hex("A3A8B0"),
        muted         = hex("8B9098"),
        danger        = hex("FF5050"),
        hover         = { 1, 1, 1 },
    },

    alpha = {
        bg         = 0.97,
        accentSoft = 0.18,
        dangerSoft = 0.12,
        hover      = 0.06,
    },

    accentHiMix = 0.35,

    accents = {
        EQOT    = { accent = hex("C8373E"), accentText = { 1, 1, 1 } },
        EQ      = { accent = hex("C8373E"), accentText = { 1, 1, 1 } },
        ED      = { accent = hex("2A72AE"), accentText = { 1, 1, 1 } },
        CDM     = { accent = hex("D9A520"), accentText = hex("16181C") },
        LootPro = { accent = hex("27795A"), accentText = { 1, 1, 1 } },
    },

    fonts = fonts,
    fontFlags = "",
    shadowOffset = 0,

    typography = {
        title      = { size = 15, weight = "SemiBold", color = "text" },
        nav        = { size = 13, weight = "Medium",   color = "navText" },
        navActive  = { size = 13, weight = "SemiBold", color = "text" },
        label      = { size = 13, weight = "Regular",  color = "label" },
        value      = { size = 13, weight = "Medium",   color = "text" },
        groupLabel = { size = 12, weight = "SemiBold", color = "muted" },
        hint       = { size = 12, weight = "Regular",  color = "muted" },
        segment    = { size = 12, weight = "SemiBold", color = "navText" },
    },

    spacing = {
        windowWidth        = 1100,
        windowHeight       = 720,
        headerHeight       = 48,
        sidebarWidth       = 196,
        footerHeight       = 56,
        previewWidth       = 320,
        navItemHeight      = 36,
        navItemPadding     = 12,
        navItemGap         = 2,
        contentTop         = 20,
        contentSides       = 24,
        groupGap           = 22,
        groupLabelGap      = 8,
        rowHeight          = 44,
        dependentRowHeight = 40,
        listRowHeight      = 28,
        rowPadding         = 14,
        dependentIndent    = 40,
        labelColumn        = 150,
        valueColumn        = 44,
        checkbox           = 16,
        swatchWidth        = 34,
        swatchHeight       = 22,
        buttonHeight       = 32,
        segmentHeight      = 26,
        border             = 1,
        fieldHeight        = 30,
        controlGap         = 14,
        checkboxGap        = 10,
        buttonGap          = 10,
        trackHeight        = 3,
        thumbWidth         = 8,
        thumbHeight        = 15,
        chevron            = 12,
        segmentPadding     = 14,
        segmentGap         = 2,
        popupRowHeight     = 22,
        popupMaxRows       = 10,
        menuItemHeight     = 24,
    },
}
