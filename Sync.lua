-- Sync: guild addon messages (balance, weekly total, latest feat, version),
-- the leaderboard cache, and the unit-tooltip line.
-- Trust model: none. It is a joke. Displayed values are clamped.
--
-- Prefix DKPM. Messages:
--   HELLO|version            BAL|total|weekly|rank|latestFeatName
--   FEAT|featId|tier|fine    REQ|name   (reply by whisper: TOP|id:tier,id:tier,...)
--   WEEK|weekId              (someone has already announced this week's leaderboard)
local _, ns = ...
local S = { recentFeats = {}, weekAnnounced = {} }
ns.Sync = S

local PREFIX = "DKPM"
local lastBal = 0

local function Locked()
    if ns.state.inInstance then return true end
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end
S.Locked = Locked

-- Trial and veteran accounts cannot send addon messages: fail silently.
local function Send(msg, channel, target)
    if Locked() then return false end
    if channel == "GUILD" and not IsInGuild() then return false end
    return pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
end

local function Clamp(n) return math.max(-9999999, math.min(9999999, tonumber(n) or 0)) end

function S:SendBalance(force)
    local now = GetTime()
    if not force and now - lastBal < 300 then return end
    lastBal = now
    local char = ns.char
    local latest = char.log[1] and char.log[1].name or ""
    Send(("BAL|%d|%d|%s|%s"):format(char.balance, char.weekly, ns.Rank(char.balance), latest), "GUILD")
end

function S:OnAward(f, tier, fine)
    Send(("FEAT|%s|%d|%d"):format(f.id, tier, fine), "GUILD")
    lastBal = 0
    S:SendBalance(true)
    S.recentFeats[f.id] = S.recentFeats[f.id] or {}
    S.recentFeats[f.id][ns.playerName] = GetTime()
end

function S:Request(name)
    Send("REQ|" .. name, "GUILD")
end

-- Guildmates with exactly the median debt (needs at least three known ledgers).
local function CheckMedian()
    local list = { ns.char.balance }
    for name, g in pairs(ns.db.guild) do
        if name ~= ns.playerName then list[#list + 1] = g.total or 0 end
    end
    if #list < 3 or #list % 2 == 0 then return end
    table.sort(list)
    local median = list[(#list + 1) / 2]
    if median ~= 0 and median == ns.char.balance then ns:Fire("GUILD_MEDIAN") end
end

local function OnMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not ns.ready then return end
    msg, sender = ns.safe(msg), ns.safe(sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    local name = sender:match("^[^-]+")
    local cmd, a, b, c, d = strsplit("|", msg)
    local guild = ns.db.guild

    if cmd == "TOP" and channel == "WHISPER" then
        if ns.Ledger then ns.Ledger:ShowTopFive(name, a or "") end
        return
    end
    if channel ~= "GUILD" then return end

    if cmd == "REQ" then
        if a == ns.playerName and name ~= ns.playerName then
            local parts = {}
            for _, e in ipairs(ns.Engine.TopFive()) do parts[#parts + 1] = e.id .. ":" .. e.tier end
            Send("TOP|" .. table.concat(parts, ","), "WHISPER", sender)
            ns:Fire("AUDITED")
        end
        return
    end
    if cmd == "WEEK" then
        S.weekAnnounced[tonumber(a) or 0] = true
        return
    end
    if name == ns.playerName then return end

    local g = guild[name] or {}
    guild[name] = g
    g.seen = time()
    if cmd == "HELLO" then
        g.version = a
        S:SendBalance(true)
    elseif cmd == "BAL" then
        g.total, g.weekly, g.latest = Clamp(a), Clamp(b), (d or ""):sub(1, 60)
        g.weekId = ns.WeekId()
        CheckMedian()
        if ns.Ledger then ns.Ledger:Refresh() end
    elseif cmd == "FEAT" and a and ns.featById[a] then
        ns.db.guildFeats = ns.db.guildFeats or {}
        ns.db.guildFeats[a] = true
        S.recentFeats[a] = S.recentFeats[a] or {}
        S.recentFeats[a][name] = GetTime()
        local mine = ns.char.earned[a]
        if mine and time() - mine.t <= 60 then
            ns:Fire("PEER_FEAT")
        end
    end
end

ns:On("CHAT_MSG_ADDON", OnMessage)
ns:On("PLAYER_ENTERING_WORLD", function()
    -- Catch up after leaving an instance, where sending is blocked.
    if ns.ready then C_Timer.After(5, function() S:SendBalance() end) end
end)

ns.logins[#ns.logins + 1] = function()
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    C_Timer.After(12, function()
        Send("HELLO|" .. ns.version, "GUILD")
        S:SendBalance(true)
    end)
    -- Forget guildmates not seen for 60 days.
    for name, g in pairs(ns.db.guild) do
        if not g.seen or time() - g.seen > 60 * 86400 then ns.db.guild[name] = nil end
    end
end

-- Leaderboard rows: known guildmates plus yourself, most in debt first.
function S:Leaderboard(weekly)
    local rows = { { name = ns.playerName, total = ns.char.balance, weekly = ns.char.weekly, latest = ns.char.log[1] and ns.char.log[1].name or "", me = true } }
    local week = ns.WeekId()
    for name, g in pairs(ns.db.guild) do
        rows[#rows + 1] = { name = name, total = g.total or 0, weekly = (g.weekId == week) and (g.weekly or 0) or 0, latest = g.latest or "" }
    end
    local key = weekly and "weekly" or "total"
    table.sort(rows, function(x, y) if x[key] ~= y[key] then return x[key] < y[key] end return x.name < y.name end)
    return rows
end

---------------------------------------------------------------------------
-- Tooltip line for other users (from the cache), optionally for yourself.
---------------------------------------------------------------------------
local function OnTooltipUnit(tooltip)
    if not ns.ready or not ns.settings.tooltip or tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and ns.safe(unit) or nil
    if not unit or not ns.try(UnitIsPlayer, unit) then return end
    local name = ns.try(UnitName, unit)
    if type(name) ~= "string" then return end
    local balance
    if name == ns.playerName then
        if not ns.settings.ownTooltip then return end
        balance = ns.char.balance
    else
        local g = ns.db.guild[name]
        if not g or not g.total then return end
        balance = g.total
    end
    tooltip:AddLine(("50 DKP Minus: %s (%s)"):format(ns.BalanceText(balance), ns.Rank(balance)), 0.8, 0.13, 0.13)
end

ns.logins[#ns.logins + 1] = function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
    elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
    end
end
