local _, ns = ...

local Card = ns:RegisterSubsystem("TrackerCard", {})

local PAD_DEFAULT     = 6
local BG_FALLBACK     = { r = 0.09, g = 0.10, b = 0.12, a = 0.73 }
local BORDER_FALLBACK = { r = 0, g = 0, b = 0, a = 0.45 }

-- Block spacing defaults to 2, at which adjacent card borders touch and read as one card
Card.MIN_GAP = 4

function Card:State(t)
    if not t then
        local DB = ns:GetSubsystem("DB")
        t = DB and DB.db.profile.tracker
    end
    if not (t and t.blockLayout == "card") then return false, 0, 0 end
    return true, t.cardPadding or PAD_DEFAULT, t.cardBorderSize or 1
end

function Card:Gap(base, enabled)
    if not enabled then return base end
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db.profile.tracker
    return math.max((t and t.blockSpacing) or base, self.MIN_GAP)
end

function Card:Colors(t)
    if not t then
        local DB = ns:GetSubsystem("DB")
        t = DB and DB.db.profile.tracker
    end
    return (t and t.cardColor) or BG_FALLBACK, (t and t.cardBorderColor) or BORDER_FALLBACK
end

-- Lowest BACKGROUND sublevels so a card can never draw over the row's own icons or text
function Card:Attach(f)
    if f.cardBorder then return end
    f.cardBorder = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.cardBorder:Hide()
    f.cardBg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.cardBg:Hide()
end

-- A nil height tracks `f`, a set height lets a header's card span its lines and exceed its frame
function Card:Draw(f, height, pad, borderSize, bg, border)
    self:Attach(f)
    bg     = bg     or BG_FALLBACK
    border = border or BORDER_FALLBACK
    local bs = borderSize or 1

    f.cardBorder:ClearAllPoints()
    f.cardBorder:SetPoint("TOPLEFT",  f, "TOPLEFT",  -pad, pad)
    f.cardBorder:SetPoint("TOPRIGHT", f, "TOPRIGHT",  pad, pad)
    if height then
        f.cardBorder:SetHeight(math.max(1, height))
    else
        f.cardBorder:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -pad, -pad)
    end
    f.cardBorder:SetColorTexture(border.r or 0, border.g or 0, border.b or 0, border.a or 1)
    f.cardBorder:Show()

    local fillH = height and (height - bs * 2)
    if fillH and fillH <= 0 then
        f.cardBg:Hide()
        return
    end

    f.cardBg:ClearAllPoints()
    f.cardBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  -pad + bs, pad - bs)
    f.cardBg:SetPoint("TOPRIGHT", f, "TOPRIGHT",  pad - bs, pad - bs)
    if fillH then
        f.cardBg:SetHeight(fillH)
    else
        f.cardBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -pad + bs, -pad + bs)
    end
    f.cardBg:SetColorTexture(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 1)
    f.cardBg:Show()
end

function Card:Clear(f)
    if f.cardBorder then f.cardBorder:Hide() end
    if f.cardBg     then f.cardBg:Hide()     end
end
