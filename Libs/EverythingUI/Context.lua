local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

-- Created by the first copy and reused by every later one, so a context made by an older copy
-- reaches the newest copy's methods.
lib.Context = lib.Context or {}
lib.contextMeta = lib.contextMeta or { __index = lib.Context }

local Context = lib.Context

local OPTS = {
    id         = { kind = "string",   required = true },
    title      = { kind = "string",   required = true },
    version    = { kind = "string",   required = true },
    accent     = { kind = "rgb",      required = true },
    L          = { kind = "table",    required = true },
    tooltip    = { kind = "function", required = true },
    accentText = { kind = "rgb" },
    discord    = { kind = "function" },
    labels     = { kind = "table" },
    getLastTab = { kind = "function" },
    setLastTab = { kind = "function" },
    getWindowScale = { kind = "function" },
    setWindowScale = { kind = "function" },
}

local LABELS = {
    discord         = true,
    discordTipTitle = true,
    discordTip      = true,
    testSound       = true,
    clear           = true,
}

local function isRGB(v)
    if type(v) ~= "table" then return false end
    for i = 1, 3 do
        local c = v[i]
        if type(c) ~= "number" or c < 0 or c > 1 then return false end
    end
    return true
end

local function copyRGB(v)
    return { v[1], v[2], v[3] }
end

function lib:NewContext(opts)
    if type(opts) ~= "table" then
        error("EverythingUI: NewContext expects an opts table", 2)
    end
    for key in pairs(opts) do
        if not OPTS[key] then
            error(("EverythingUI: NewContext got unknown opts.%s"):format(tostring(key)), 2)
        end
    end
    for key, spec in pairs(OPTS) do
        local v = opts[key]
        if v == nil then
            if spec.required then
                error(("EverythingUI: NewContext needs opts.%s"):format(key), 2)
            end
        elseif spec.kind == "rgb" then
            if not isRGB(v) then
                error(("EverythingUI: opts.%s must be { r, g, b } in 0-1"):format(key), 2)
            end
        elseif type(v) ~= spec.kind then
            error(("EverythingUI: opts.%s must be a %s"):format(key, spec.kind), 2)
        end
    end
    if (opts.getLastTab == nil) ~= (opts.setLastTab == nil) then
        error("EverythingUI: opts.getLastTab and opts.setLastTab come as a pair", 2)
    end
    if (opts.getWindowScale == nil) ~= (opts.setWindowScale == nil) then
        error("EverythingUI: opts.getWindowScale and opts.setWindowScale come as a pair", 2)
    end
    local labels = {}
    for key, v in pairs(opts.labels or {}) do
        if not LABELS[key] then
            error(("EverythingUI: NewContext got unknown opts.labels.%s"):format(tostring(key)), 2)
        end
        if type(v) ~= "string" then
            error(("EverythingUI: opts.labels.%s must be a string"):format(key), 2)
        end
        labels[key] = v
    end
    if opts.discord and not labels.discord then
        error("EverythingUI: opts.discord needs opts.labels.discord", 2)
    end

    local kept = {}
    for key, v in pairs(opts) do kept[key] = v end
    kept.accent = copyRGB(opts.accent)
    kept.accentText = opts.accentText and copyRGB(opts.accentText) or { 1, 1, 1 }
    kept.labels = labels

    return setmetatable({ opts = kept }, lib.contextMeta)
end

function Context:Color(name)
    local tokens = lib.tokens
    local alpha = tokens.alpha[name] or 1
    local c
    if name == "accent" or name == "accentSoft" then
        c = self.opts.accent
    elseif name == "dangerSoft" then
        c = tokens.colors.danger
    elseif name == "accentHi" then
        local a, mix = self.opts.accent, tokens.accentHiMix
        return a[1] + (1 - a[1]) * mix, a[2] + (1 - a[2]) * mix, a[3] + (1 - a[3]) * mix, alpha
    elseif name == "accentText" then
        c = self.opts.accentText
    else
        c = tokens.colors[name]
    end
    if not c then
        error(("EverythingUI: no color named %s"):format(tostring(name)), 2)
    end
    return c[1], c[2], c[3], alpha
end

function Context:Texture(name)
    return lib.media .. "Textures\\" .. name
end

function Context:Font(name)
    local tokens = lib.tokens
    local t = tokens.typography[name]
    if not t then
        error(("EverythingUI: no type style named %s"):format(tostring(name)), 2)
    end
    return tokens.fonts[t.weight], t.size, tokens.fontFlags
end
