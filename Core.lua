-- 50 DKP Minus: event frame, saved variables, slash commands, shared helpers.
-- Not a real DKP addon. Nothing here reads combat data.
local ADDON, ns = ...
_G.FiftyDKPMinus = ns

ns.TAG = "[50 DKP Minus]"
ns.REPO = "https://github.com/heavyc-dev/50-DKP-Minus"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon.png"
ns.SEAL = "Interface\\AddOns\\" .. ADDON .. "\\Media\\seal.png"     -- same art, transparent background
ns.state = {}      -- live, non-combat player state; every signal context falls back to it
ns.inits = {}      -- run once saved variables exist
ns.logins = {}     -- run at PLAYER_LOGIN

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.version = (getMeta and getMeta(ADDON, "Version")) or "dev"
if ns.version:find("@", 1, true) then ns.version = "dev" end

ns.CHANGELOG = {
    "1.0.0 - First public release. The ledger is open to the whole guild.",
    "0.1.0 - First ledger opened. Engine, signals, herald, sync, ledger and toast.",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = _G.issecretvalue

-- Returns nil for Secret Values so callers never compare or store them.
function ns.safe(v)
    if v ~= nil and issecret and issecret(v) then return nil end
    return v
end

-- Calls a possibly-missing, possibly-restricted API. Returns nil on any failure.
function ns.try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return ns.safe(a), ns.safe(b), ns.safe(c), ns.safe(d)
end

-- hooksecurefunc that tolerates missing functions.
function ns.Hook(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
    if type(tbl) == "table" and type(tbl[name]) == "function" then
        hooksecurefunc(tbl, name, fn)
        return true
    end
end

function ns.Comma(n)
    local s = tostring(math.floor(math.abs(n) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end

-- A fine of 50 prints as "-50"; a credit (negative fine) prints as "+50".
function ns.FineText(fine)
    return (fine < 0 and "+" or "-") .. ns.Comma(fine)
end

function ns.BalanceText(balance)
    return (balance > 0 and "+" or (balance < 0 and "-" or "")) .. ns.Comma(balance)
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI" }
function ns.Roman(n) return ROMAN[n] or tostring(n) end

ns.TIERS = {
    { fine = 5,   name = "Petty",         color = "ff9d9d9d" },
    { fine = 50,  name = "Standard",      color = "ff1eff00" },
    { fine = 100, name = "Severe",        color = "ff0070dd" },
    { fine = 250, name = "Whelps",        color = "ffa335ee" },
    { fine = 500, name = "/gkick Worthy", color = "ffff8000" },
}
function ns.TierOf(fine)
    fine = math.abs(fine)
    local best = ns.TIERS[1]
    for i = 1, #ns.TIERS do
        if fine >= ns.TIERS[i].fine then best = ns.TIERS[i] end
    end
    return best
end

local RANKS = {
    { 25000, "Benched Forever" }, { 10000, "Officer's Headache" }, { 5000, "Whelp Handler" },
    { 2500, "Raid Risk" }, { 1000, "Liability" }, { 250, "Slightly Embarrassed" }, { 0, "Solvent" },
}
function ns.Rank(balance)
    local debt = -balance
    for i = 1, #RANKS do
        if debt >= RANKS[i][1] then return RANKS[i][2] end
    end
    return "Solvent"
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc2222" .. ns.TAG .. "|r " .. tostring(msg))
end

-- Weekly reset: Tuesday 15:00 UTC.
function ns.WeekId()
    local now = (GetServerTime and GetServerTime()) or time()
    return math.floor((now - (5 * 86400 + 15 * 3600)) / 604800)
end

---------------------------------------------------------------------------
-- Event multiplexer
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    local list = handlers[event]
    if not list then
        -- Unknown events raise an error on some clients; treat them as absent.
        if not pcall(frame.RegisterEvent, frame, event) then return false end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        -- One failing handler must not starve the rest; the error is still reported.
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
    heraldGuild = true, heraldParty = true, minTier = 50, pettyPublic = false,
    toast = true, sound = true, quiet = false, whisper = true,
    tooltip = true, ownTooltip = false, repeatable = false, experimental = false,
    shareChannel = "SAY", minimapAngle = 215, minimapHide = false,
}

local function InitDB()
    FiftyDKPMinusDB = FiftyDKPMinusDB or {}
    local db = FiftyDKPMinusDB
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.settings.packsOff = db.settings.packsOff or {}
    db.chars = db.chars or {}
    db.guild = db.guild or {}

    FiftyDKPMinusCharDB = FiftyDKPMinusCharDB or {}
    local char = FiftyDKPMinusCharDB
    char.earned = char.earned or {}
    char.c = char.c or {}
    char.sets = char.sets or {}
    char.shadow = char.shadow or {}
    char.log = char.log or {}
    char.win = char.win or {}
    char.balance = char.balance or 0
    char.weekly = char.weekly or 0
    char.weekId = char.weekId or ns.WeekId()
    char.firstSeen = char.firstSeen or time()
    char.session = char.session or { c = {}, sets = {}, start = time() }

    ns.db, ns.char, ns.settings, ns.session = db, char, db.settings, char.session
end

function ns.NewSession()
    ns.char.session = { c = {}, sets = {}, start = time() }
    ns.session = ns.char.session
end

function ns.AccountTotal()
    local total = 0
    for _, c in pairs(ns.db.chars) do total = total + (c.balance or 0) end
    return total
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    InitDB()
    for i = 1, #ns.inits do ns.inits[i]() end
end)

ns:On("PLAYER_LOGIN", function()
    local name, realm = UnitFullName("player")
    ns.playerName = name
    ns.charKey = name .. "-" .. (realm or GetRealmName() or "")
    local _, class = UnitClass("player")
    local st = ns.state
    st.class = class
    st.faction = UnitFactionGroup("player")
    st.race = select(2, UnitRace("player"))
    st.level = UnitLevel("player")
    st.hardcore = false
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule and Enum.GameRule.HardcoreRuleset then
        st.hardcore = ns.try(C_GameRules.IsGameRuleActive, Enum.GameRule.HardcoreRuleset) and true or false
    end
    st.ruleset = st.hardcore and "HARDCORE" or "NORMAL"

    local me = ns.db.chars[ns.charKey] or {}
    me.balance, me.faction, me.class, me.ruleset = ns.char.balance, st.faction, class, st.ruleset
    ns.db.chars[ns.charKey] = me

    if ns.char.weekId ~= ns.WeekId() then
        ns.char.lastWeekly, ns.char.weekly, ns.char.weekId = ns.char.weekly, 0, ns.WeekId()
        ns.newWeek = true
    end

    ns.ready = true
    for i = 1, #ns.logins do ns.logins[i]() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_FIFTYDKPMINUS1 = "/dkp50"
SLASH_FIFTYDKPMINUS2 = "/minus"
SlashCmdList.FIFTYDKPMINUS = function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Ledger:Toggle()
    elseif cmd == "share" then
        ns.Herald:SharePrompt()
    elseif cmd == "last" then
        ns.Herald:Reannounce()
    elseif cmd == "quiet" then
        ns.settings.quiet = not ns.settings.quiet
        ns.Print(ns.settings.quiet and "Quiet mode on. Your shame stays private." or "Quiet mode off. The guild will hear about this.")
    elseif cmd == "hint" then
        ns.Engine.Hint()
    elseif cmd == "changelog" then
        for i = 1, #ns.CHANGELOG do ns.Print(ns.CHANGELOG[i]) end
        ns:Fire("CHANGELOG")
    elseif cmd == "debug" and rest ~= "" then
        -- /minus debug <featId>: award a feat by id, for testing heralds and toasts.
        local f = ns.featById[rest]
        if f then ns:Award(f, 1, {}) else ns.Print("No such feat: " .. rest) end
    else
        ns.Print("/minus - ledger | share | last | quiet | hint | changelog")
    end
end

function FiftyDKPMinus_OnCompartmentClick() ns.Ledger:Toggle() end
