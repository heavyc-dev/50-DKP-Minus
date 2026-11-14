-- Ledger window: a guild officer's DKP ledger. Leather cover, parchment pages,
-- red ink. Tabs: Statement, Offences, Guild, Settings (built in Options.lua).
local _, ns = ...
local L = {}
ns.Ledger = L
local Th = ns.Theme

local ROW_H = 38

local function Scroll(panel, bottom)
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, bottom or 6)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(520, 10)
    sf:SetScrollChild(child)
    child.rows = {}
    return child
end

local function Row(child, i)
    local row = child.rows[i]
    if not row then
        row = CreateFrame("Button", nil, child)
        row:SetSize(520, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT", 2, -5)
        row.bar:SetPoint("BOTTOMLEFT", 2, 5)
        row.bar:SetWidth(3)
        row.left = Th.Text(row, "head", 15)
        row.left:SetPoint("TOPLEFT", 12, -4)
        row.right = Th.Text(row, "head", 15, Th.RED)
        row.right:SetPoint("TOPRIGHT", -6, -4)
        row.right:SetJustifyH("RIGHT")
        row.sub = Th.Text(row, "body", 11, Th.FADED)
        row.sub:SetPoint("TOPLEFT", 12, -21)
        row.sub:SetPoint("RIGHT", -6, 0)
        row.sub:SetWordWrap(false)
        row.rule = Th.Rule(row, 0.16)
        row.rule:SetPoint("BOTTOMLEFT", 8, 0)
        row.rule:SetPoint("BOTTOMRIGHT", -4, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(Th.INK[1], Th.INK[2], Th.INK[3], 0.07)
        child.rows[i] = row
    end
    row:SetScript("OnClick", nil)
    row.bar:Hide()
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", 12, -4)
    row:Show()
    return row
end

local function Finish(child, used)
    for i = used + 1, #child.rows do child.rows[i]:Hide() end
    child:SetHeight(math.max(10, used * ROW_H))
end

local function InkHex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function RefreshStatement(p)
    local char = ns.char
    p.balance:SetText(ns.BalanceText(char.balance))
    p.rank:SetText(ns.Rank(char.balance))
    p.detail:SetText(("This week  %s%s|r        Account  %s%s|r"):format(
        InkHex(Th.RED), ns.BalanceText(char.weekly), InkHex(Th.RED), ns.BalanceText(ns.AccountTotal())))
    p.count:SetText(("%d of %d offences on file"):format(ns.Engine.CountEarned(), #ns.feats))
    for i = 1, 5 do
        local e = char.log[i]
        local line = p.lines[i]
        if e then
            line.left:SetText(("%s   %s"):format(date("%d %b", e.t), e.name))
            line.right:SetText(ns.FineText(e.fine))
            line.where:SetText(e.z or "")
        else
            line.left:SetText(i == 1 and "No fines on record. This will not last." or "")
            line.right:SetText("")
            line.where:SetText("")
        end
    end
end

local function RefreshOffences(p)
    local child, n = p.child, 0
    for _, pack in ipairs(ns.packOrder) do
        local header = false
        for _, f in ipairs(ns.feats) do
            if f.pack == pack and ns.Engine.Eligible(f) ~= false then
                local name, fine, e = ns.Engine.EarnedInfo(f)
                -- /gkick Worthy feats show nothing at all until earned.
                if e or not f.hidden then
                    if not header then
                        header = true
                        n = n + 1
                        local h = Row(child, n)
                        h.left:ClearAllPoints()
                        h.left:SetPoint("TOPLEFT", 4, -14)
                        h.left:SetText(InkHex(Th.RED) .. pack .. (ns.settings.packsOff[pack] and "  (off)" or "") .. "|r")
                        h.right:SetText("")
                        h.sub:SetText("")
                    end
                    n = n + 1
                    local row = Row(child, n)
                    if e then
                        row.bar:SetColorTexture(Th.TierInk(fine))
                        row.bar:Show()
                        row.left:SetText(name)
                        row.right:SetText(ns.FineText(fine))
                        row.sub:SetText(("%s   -   %s"):format(f.flavor or "", date("%d %b %Y", e.t)))
                    else
                        row.left:SetText(InkHex(Th.FADED) .. "? ? ?|r")
                        row.right:SetText("")
                        row.sub:SetText(f.hint or "")
                    end
                end
            end
        end
    end
    Finish(child, n)
end

local function RefreshGuild(p)
    local child = p.child
    local rows = ns.Sync:Leaderboard(p.weekly)
    for i, r in ipairs(rows) do
        local row = Row(child, i)
        row.left:SetText(("%d.  %s%s"):format(i, r.name, r.me and "  (you)" or ""))
        row.right:SetText(ns.BalanceText(p.weekly and r.weekly or r.total))
        row.sub:SetText((p.weekly and ("All time " .. ns.BalanceText(r.total)) or ("This week " .. ns.BalanceText(r.weekly)))
            .. (r.latest ~= "" and ("     Latest: " .. r.latest) or ""))
        if not r.me then
            row:SetScript("OnClick", function()
                ns.Sync:Request(r.name)
                p.status:SetText("Requested " .. r.name .. "'s file...")
            end)
        end
    end
    Finish(child, #rows)
    if #rows == 1 then p.status:SetText("No guildmates with a ledger seen yet. Yours is the worst by default.") end
end

function L:ShowTopFive(name, payload)
    local parts = {}
    for id, tier in payload:gmatch("([%w_]+):(%d+)") do
        local f = ns.featById[id]
        local t = f and f.tiers[tonumber(tier)]
        if t then parts[#parts + 1] = ("%s (%s)"):format(t[2] or f.name, ns.FineText(t[3])) end
    end
    local msg = name .. "'s worst: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing on file")
    ns.Print(msg)
    if L.frame and L.panels.Guild.status then L.panels.Guild.status:SetText(msg) end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local TABS = { "Statement", "Offences", "Guild", "Settings" }

local function StyleTab(button, selected)
    local c = selected and Th.RED or Th.FADED
    button.label:SetTextColor(c[1], c[2], c[3])
    if selected then button.underline:Show() else button.underline:Hide() end
end

local function Select(name)
    L.tab = name
    for tab, panel in pairs(L.panels) do
        if tab == name then panel:Show() else panel:Hide() end
    end
    for tab, button in pairs(L.buttons) do StyleTab(button, tab == name) end
    L:Refresh()
end

local function Build()
    local f = CreateFrame("Frame", "FiftyDKPMinusLedger", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    L.frame = f
    f:SetSize(620, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FiftyDKPMinusLedger")
    Th.Cover(f)

    -- Cover: gilt title, small print, close button.
    local title = Th.Text(f, "head", 22, Th.GOLD)
    title:SetPoint("TOPLEFT", 26, -16)
    title:SetText("50 DKP Minus")
    L.title = Th.Text(f, "body", 11, { 0.66, 0.55, 0.36 })
    L.title:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 12, 3)
    L.title:SetText("Officer's Ledger")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", 16, -46)
    page:SetPoint("BOTTOMRIGHT", -16, 16)
    Th.Parchment(page)

    -- Section tabs, written across the top of the page.
    L.panels, L.buttons = {}, {}
    local x = 22
    for _, name in ipairs(TABS) do
        local b = CreateFrame("Button", nil, page)
        b.label = Th.Text(b, "head", 17, Th.FADED)
        b.label:SetPoint("CENTER")
        b.label:SetText(name)
        b:SetSize(104, 28)
        b:SetPoint("TOPLEFT", x, -12)
        x = x + 112
        b.underline = b:CreateTexture(nil, "ARTWORK")
        b.underline:SetColorTexture(Th.RED[1], Th.RED[2], Th.RED[3], 0.85)
        b.underline:SetHeight(2)
        b.underline:SetPoint("BOTTOMLEFT", 10, 1)
        b.underline:SetPoint("BOTTOMRIGHT", -10, 1)
        b:SetScript("OnClick", function() Select(name) end)
        b:SetScript("OnEnter", function(self) self.label:SetTextColor(Th.INK[1], Th.INK[2], Th.INK[3]) end)
        b:SetScript("OnLeave", function(self) StyleTab(self, L.tab == name) end)
        L.buttons[name] = b

        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 12, -46)
        p:SetPoint("BOTTOMRIGHT", -12, 12)
        p:Hide()
        L.panels[name] = p
    end
    local tabRule = Th.Rule(page, 0.4)
    tabRule:SetPoint("TOPLEFT", 16, -42)
    tabRule:SetPoint("TOPRIGHT", -16, -42)

    -- Statement
    local s = L.panels.Statement
    local head = Th.Text(s, "head", 20)
    head:SetPoint("TOPLEFT", 16, -14)
    head:SetText("Statement of Account")
    s.balance = Th.Text(s, "head", 46, Th.RED)
    s.balance:SetPoint("TOPLEFT", 16, -42)
    local unit = Th.Text(s, "head", 18, Th.RED)
    unit:SetPoint("BOTTOMLEFT", s.balance, "BOTTOMRIGHT", 8, 6)
    unit:SetText("DKP")
    local standing = Th.Text(s, "body", 10, Th.FADED)
    standing:SetPoint("TOPLEFT", 18, -98)
    standing:SetText("STANDING")
    s.rank = Th.Text(s, "head", 20)
    s.rank:SetPoint("TOPLEFT", 16, -110)
    s.detail = Th.Text(s, "body", 12)
    s.detail:SetPoint("TOPLEFT", 18, -138)
    s.count = Th.Text(s, "body", 11, Th.FADED)
    s.count:SetPoint("TOPLEFT", 18, -156)
    local seal = Th.Seal(s, 104, -11)
    seal:SetPoint("TOPRIGHT", -26, -22)

    local recent = Th.Text(s, "head", 17)
    recent:SetPoint("TOPLEFT", 16, -188)
    recent:SetText("Most Recent Fines")
    local rule = Th.Rule(s, 0.4)
    rule:SetPoint("TOPLEFT", 16, -210)
    rule:SetPoint("TOPRIGHT", -16, -210)
    s.lines = {}
    for i = 1, 5 do
        local y = -188 - i * 30
        local line = {}
        line.left = Th.Text(s, "head", 14)
        line.left:SetPoint("TOPLEFT", 18, y)
        line.right = Th.Text(s, "head", 14, Th.RED)
        line.right:SetPoint("TOPRIGHT", -18, y)
        line.right:SetJustifyH("RIGHT")
        line.where = Th.Text(s, "body", 10, Th.FADED)
        line.where:SetPoint("TOPLEFT", 18, y - 15)
        s.lines[i] = line
    end
    local share = Th.Button(s, "Share", 100, function() ns.Herald:SharePrompt() end)
    share:SetPoint("BOTTOMLEFT", 14, 8)
    local hint = Th.Button(s, "Hint", 100, function() ns.Engine.Hint() end)
    hint:SetPoint("LEFT", share, "RIGHT", 8, 0)
    local note = Th.Text(s, "body", 10, Th.FADED)
    note:SetPoint("LEFT", hint, "RIGHT", 14, 0)
    note:SetPoint("RIGHT", -14, 0)
    note:SetText("All fines are final. Appeals may be directed to your raid leader.")

    -- Offences
    L.panels.Offences.child = Scroll(L.panels.Offences)

    -- Guild
    local g = L.panels.Guild
    g.child = Scroll(g, 38)
    g.status = Th.Text(g, "body", 11, Th.FADED)
    g.status:SetPoint("BOTTOMLEFT", 130, 14)
    g.status:SetPoint("RIGHT", -10, 0)
    g.status:SetWordWrap(false)
    g.status:SetText("Click a name to request their five worst.")
    local toggle
    toggle = Th.Button(g, "All time", 110, function()
        g.weekly = not g.weekly
        toggle:SetText(g.weekly and "This week" or "All time")
        RefreshGuild(g)
    end)
    toggle:SetPoint("BOTTOMLEFT", 10, 8)

    if ns.Options then ns.Options.Build(L.panels.Settings) end
    Select("Statement")
end

function L:Refresh()
    if not L.frame or not L.frame:IsShown() then return end
    if L.tab == "Statement" then RefreshStatement(L.panels.Statement)
    elseif L.tab == "Offences" then RefreshOffences(L.panels.Offences)
    elseif L.tab == "Guild" then RefreshGuild(L.panels.Guild) end
end

function L:Toggle()
    if not ns.ready then return end
    if not L.frame then Build() L.frame:Hide() end
    if L.frame:IsShown() then
        L.frame:Hide()
        return
    end
    L.frame:Show()
    L:Refresh()
    local char = ns.char
    local latest = char.lastFeatT or 0
    local stale = char.ledgerSeenT == latest
    char.ledgerSeenT = latest
    ns:Fire("LEDGER_OPEN", { stale = stale })
end
