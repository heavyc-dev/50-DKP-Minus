-- Ledger window: a parody of a raid officer's DKP ledger. Parchment, red ink.
-- Tabs: Statement, Offences, Guild, Settings (Settings is built in Options.lua).
local _, ns = ...
local L = {}
ns.Ledger = L

local INK, RED, FADED = { 0.20, 0.12, 0.05 }, { 0.72, 0.05, 0.05 }, { 0.45, 0.38, 0.28 }
local ROW_H = 34
L.INK, L.RED = INK, RED

local function Text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetTextColor(r or INK[1], g or INK[2], b or INK[3])
    fs:SetJustifyH("LEFT")
    return fs
end
L.Text = Text

local function Scroll(panel)
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(540, 10)
    sf:SetScrollChild(child)
    child.rows = {}
    return child
end

local function Row(child, i)
    local row = child.rows[i]
    if not row then
        row = CreateFrame("Button", nil, child)
        row:SetSize(540, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.left = Text(row, "GameFontNormal")
        row.left:SetPoint("TOPLEFT", 4, -3)
        row.right = Text(row, "GameFontNormal", RED[1], RED[2], RED[3])
        row.right:SetPoint("TOPRIGHT", -4, -3)
        row.right:SetJustifyH("RIGHT")
        row.sub = Text(row, "GameFontHighlightSmall", FADED[1], FADED[2], FADED[3])
        row.sub:SetPoint("TOPLEFT", 4, -18)
        row.sub:SetPoint("RIGHT", -4, 0)
        row.sub:SetWordWrap(false)
        child.rows[i] = row
    end
    row:SetScript("OnClick", nil)
    row:Show()
    return row
end

local function Finish(child, used)
    for i = used + 1, #child.rows do child.rows[i]:Hide() end
    child:SetHeight(math.max(10, used * ROW_H))
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function RefreshStatement(p)
    local char = ns.char
    p.balance:SetText(ns.BalanceText(char.balance) .. " DKP")
    p.rank:SetText(("Standing: %s      This week: %s      Account: %s"):format(
        ns.Rank(char.balance), ns.BalanceText(char.weekly), ns.BalanceText(ns.AccountTotal())))
    p.count:SetText(("%d of %d offences on file."):format(ns.Engine.CountEarned(), #ns.feats))
    for i = 1, 5 do
        local e = char.log[i]
        local line = p.lines[i]
        if e then
            line:SetText(("%s   %s   |cffb80d0d%s|r   %s"):format(date("%d %b", e.t), e.name, ns.FineText(e.fine), e.z or ""))
        else
            line:SetText(i == 1 and "No fines on record. This will not last." or "")
        end
    end
end

local function RefreshOffences(p)
    local child, n = p.child, 0
    local char = ns.char
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
                        h.left:SetText("|cffb80d0d" .. pack:upper() .. (ns.settings.packsOff[pack] and "  (off)" or "") .. "|r")
                        h.right:SetText("")
                        h.sub:SetText("")
                    end
                    n = n + 1
                    local row = Row(child, n)
                    if e then
                        row.left:SetText(("|c%s%s|r"):format(ns.TierOf(fine).color, name))
                        row.right:SetText(ns.FineText(fine))
                        row.sub:SetText(("%s  -  %s"):format(f.flavor or "", date("%d %b %Y", e.t)))
                    else
                        row.left:SetText("|cff8a7a60???|r")
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
        row.left:SetText(("%d. %s%s"):format(i, r.name, r.me and " (you)" or ""))
        row.right:SetText(("%s  |cff73614a(week %s)|r"):format(ns.BalanceText(r.total), ns.BalanceText(r.weekly)))
        row.sub:SetText(r.latest ~= "" and ("Latest: " .. r.latest) or "")
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

local function Select(name)
    L.tab = name
    for tab, panel in pairs(L.panels) do
        if tab == name then panel:Show() else panel:Hide() end
    end
    for tab, button in pairs(L.buttons) do
        if tab == name then button:LockHighlight() else button:UnlockHighlight() end
    end
    L:Refresh()
end

local function Build()
    local f = CreateFrame("Frame", "FiftyDKPMinusLedger", UIParent, "BasicFrameTemplateWithInset")
    L.frame = f
    f:SetSize(600, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FiftyDKPMinusLedger")
    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    L.title = title

    -- Parchment sits on its own frame so the template's inset cannot cover it.
    local level = f:GetFrameLevel()
    local paperFrame = CreateFrame("Frame", nil, f)
    paperFrame:SetPoint("TOPLEFT", 8, -58)
    paperFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    paperFrame:SetFrameLevel(level + 2)
    local paper = paperFrame:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetColorTexture(0.91, 0.85, 0.69, 1)

    L.panels, L.buttons = {}, {}
    for i, name in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(120, 22)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 124, -30)
        b:SetText(name)
        b:SetScript("OnClick", function() Select(name) end)
        L.buttons[name] = b

        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 10, -60)
        p:SetPoint("BOTTOMRIGHT", -10, 10)
        p:SetFrameLevel(level + 3)
        p:Hide()
        L.panels[name] = p
    end

    -- Statement
    local s = L.panels.Statement
    local head = Text(s, "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 20, -18)
    head:SetText("Statement of account")
    s.balance = Text(s, "GameFontNormalHuge", RED[1], RED[2], RED[3])
    s.balance:SetPoint("TOPLEFT", 20, -48)
    s.rank = Text(s, "GameFontHighlight")
    s.rank:SetPoint("TOPLEFT", 20, -84)
    s.count = Text(s, "GameFontHighlightSmall", FADED[1], FADED[2], FADED[3])
    s.count:SetPoint("TOPLEFT", 20, -104)
    local recent = Text(s, "GameFontNormal")
    recent:SetPoint("TOPLEFT", 20, -140)
    recent:SetText("Most recent fines")
    s.lines = {}
    for i = 1, 5 do
        s.lines[i] = Text(s, "GameFontHighlight")
        s.lines[i]:SetPoint("TOPLEFT", 20, -144 - i * 22)
        s.lines[i]:SetPoint("RIGHT", -20, 0)
        s.lines[i]:SetWordWrap(false)
    end
    local note = Text(s, "GameFontHighlightSmall", FADED[1], FADED[2], FADED[3])
    note:SetPoint("BOTTOMLEFT", 20, 44)
    note:SetText("Balances only go down. There is no way to earn DKP back. This is not a loot system.")
    local share = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    share:SetSize(110, 22)
    share:SetPoint("BOTTOMLEFT", 18, 14)
    share:SetText("Share")
    share:SetScript("OnClick", function() ns.Herald:SharePrompt() end)
    local hint = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    hint:SetSize(110, 22)
    hint:SetPoint("LEFT", share, "RIGHT", 8, 0)
    hint:SetText("Hint")
    hint:SetScript("OnClick", function() ns.Engine.Hint() end)

    -- Offences
    L.panels.Offences.child = Scroll(L.panels.Offences)

    -- Guild
    local g = L.panels.Guild
    g.child = Scroll(g)
    g.child:GetParent():SetPoint("BOTTOMRIGHT", -28, 34)
    g.status = Text(g, "GameFontHighlightSmall", FADED[1], FADED[2], FADED[3])
    g.status:SetPoint("BOTTOMLEFT", 130, 14)
    g.status:SetPoint("RIGHT", -10, 0)
    g.status:SetWordWrap(false)
    g.status:SetText("Click a name to request their five worst.")
    local toggle = CreateFrame("Button", nil, g, "UIPanelButtonTemplate")
    toggle:SetSize(110, 22)
    toggle:SetPoint("BOTTOMLEFT", 10, 8)
    toggle:SetText("All time")
    toggle:SetScript("OnClick", function()
        g.weekly = not g.weekly
        toggle:SetText(g.weekly and "This week" or "All time")
        RefreshGuild(g)
    end)

    if ns.Options then ns.Options.Build(L.panels.Settings) end
    Select("Statement")
end

function L:Refresh()
    if not L.frame or not L.frame:IsShown() then return end
    if L.title then
        L.title:SetText("50 DKP Minus - not a real DKP addon - Account: " .. ns.BalanceText(ns.AccountTotal()))
    end
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
