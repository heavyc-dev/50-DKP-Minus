-- Theme: shared look for the ledger and toast. A guild officer's ledger:
-- dark leather cover, gilt edge, aged parchment, red ink, blackletter headings.
-- Everything here is drawn from colours, gradients and fonts that ship with
-- the client, plus the addon's own icon as a wax seal, so nothing can go
-- missing. Custom art can replace any piece by setting a path in Theme.ART.
local _, ns = ...
local Th = {}
ns.Theme = Th

Th.INK    = { 0.17, 0.10, 0.04 }
Th.FADED  = { 0.42, 0.33, 0.22 }
Th.RED    = { 0.60, 0.05, 0.04 }
Th.GOLD   = { 0.93, 0.77, 0.36 }
Th.LEATHER = { 0.09, 0.06, 0.04 }
Th.PAPER_TOP, Th.PAPER_BOTTOM = { 0.90, 0.82, 0.62 }, { 0.78, 0.67, 0.46 }

-- Optional custom textures (nil = draw procedurally). See Media/.
Th.ART = { parchment = nil, cover = nil }

-- Tier colours tuned to read on parchment (the chat colours are too bright).
local TIER_INK = {
    [5] = { 0.45, 0.42, 0.38 }, [50] = { 0.16, 0.42, 0.10 }, [100] = { 0.10, 0.28, 0.60 },
    [250] = { 0.42, 0.16, 0.58 }, [500] = { 0.78, 0.36, 0.02 },
}
function Th.TierInk(fine)
    local c = TIER_INK[ns.TierOf(fine).fine]
    return c[1], c[2], c[3]
end

-- Morpheus has no Cyrillic or CJK glyphs; those locales keep the stock font.
local locale = GetLocale and GetLocale() or "enUS"
local fancy = not (locale == "ruRU" or locale == "koKR" or locale == "zhCN" or locale == "zhTW")
local HEAD = fancy and "Fonts\\MORPHEUS.TTF" or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
local BODY = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- kind: "head" (blackletter) or "body". colour defaults to ink.
function Th.Text(parent, kind, size, colour, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    fs:SetFont(kind == "head" and HEAD or BODY, size or 12, "")
    fs:SetShadowOffset(0, 0)
    local c = colour or Th.INK
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

local function Gradient(tex, top, bottom)
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1), CreateColor(top[1], top[2], top[3], top[4] or 1))
        if ok then return end
    end
    tex:SetColorTexture(top[1], top[2], top[3], top[4] or 1)
end

-- A thin ink rule.
function Th.Rule(parent, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(Th.INK[1], Th.INK[2], Th.INK[3], alpha or 0.35)
    t:SetHeight(1)
    return t
end

-- Fills `frame` with aged parchment: warm gradient, darkened edges, double ink border.
function Th.Parchment(frame)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    base:SetAllPoints()
    if Th.ART.parchment then
        base:SetTexture(Th.ART.parchment)
    else
        Gradient(base, Th.PAPER_TOP, Th.PAPER_BOTTOM)
        -- Burnt edges: four soft shadows fading inward.
        local burn = { 0.30, 0.17, 0.05 }
        local function Edge(p1, p2, w, h, horizontal, flip)
            local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetPoint(p1) t:SetPoint(p2)
            if w then t:SetWidth(w) else t:SetHeight(h) end
            t:SetColorTexture(1, 1, 1, 1)
            if CreateColor and t.SetGradient then
                local dark, clear = CreateColor(burn[1], burn[2], burn[3], 0.38), CreateColor(burn[1], burn[2], burn[3], 0)
                pcall(t.SetGradient, t, horizontal and "HORIZONTAL" or "VERTICAL", flip and clear or dark, flip and dark or clear)
            else
                t:SetColorTexture(burn[1], burn[2], burn[3], 0.08)
            end
        end
        Edge("TOPLEFT", "BOTTOMLEFT", 46, nil, true, false)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 46, nil, true, true)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 46, false, false)
        Edge("TOPLEFT", "TOPRIGHT", nil, 46, false, true)
    end
    for i, inset in ipairs({ 5, 8 }) do
        local a = i == 1 and 0.45 or 0.22
        local top, bottom = Th.Rule(frame, a), Th.Rule(frame, a)
        top:SetPoint("TOPLEFT", inset, -inset) top:SetPoint("TOPRIGHT", -inset, -inset)
        bottom:SetPoint("BOTTOMLEFT", inset, inset) bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
        local left, right = Th.Rule(frame, a), Th.Rule(frame, a)
        left:SetWidth(1) right:SetWidth(1)
        left:SetPoint("TOPLEFT", inset, -inset) left:SetPoint("BOTTOMLEFT", inset, inset)
        right:SetPoint("TOPRIGHT", -inset, -inset) right:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
end

-- Dark leather cover with a gilt border.
function Th.Cover(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = Th.ART.cover or "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 26, insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    if Th.ART.cover then frame:SetBackdropColor(1, 1, 1, 1)
    else frame:SetBackdropColor(Th.LEATHER[1], Th.LEATHER[2], Th.LEATHER[3], 0.97) end
end

-- The addon icon as a wax seal, tilted.
function Th.Seal(parent, size, degrees)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    t:SetTexture(ns.ICON)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)      -- trim the artwork's dark margin
    if t.SetRotation and degrees then t:SetRotation(math.rad(degrees)) end
    return t
end

-- Leather button with gilt lettering.
function Th.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, 24)
    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        b:SetBackdropColor(0.20, 0.12, 0.06, 0.95)
        b:SetBackdropBorderColor(Th.GOLD[1], Th.GOLD[2], Th.GOLD[3], 0.9)
    end
    b.label = Th.Text(b, "head", 13, Th.GOLD)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(text)
    b.SetText = function(self, t) self.label:SetText(t) end
    b:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.34, 0.20, 0.09, 1) end
        self.label:SetTextColor(1, 0.93, 0.62)
    end)
    b:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.20, 0.12, 0.06, 0.95) end
        self.label:SetTextColor(Th.GOLD[1], Th.GOLD[2], Th.GOLD[3])
    end)
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end
