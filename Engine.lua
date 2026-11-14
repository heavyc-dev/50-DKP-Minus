-- Engine: feat registry, counters, condition evaluation, tiers, cooldowns, awarding.
-- Feats are data (see Feats/*.lua). Signals/*.lua turn game events into named
-- signals; ns:Fire(signal, ctx) evaluates every feat listening on that signal.
--
-- Optional feat fields:
--   count    = N          needs N matching signals (default 1)
--   tiers    = {{n, name, fine}, ...}   repeat at thresholds
--   session  = true       counter resets each login session
--   streak   = true       counter resets whenever the conditions fail
--   window   = {n, secs}  n matching signals inside a sliding window
--   sameKey  = true|"field"  window is tracked per ctx.key or ctx[field] (same subzone, same NPC)
--   value    = "field"    compare ctx[field] to the thresholds instead of counting
--   distinct = "field"    count distinct values of ctx[field]
--   repeatable = true     with the optional module, fines again (max once an hour)
local _, ns = ...
local E = {}
ns.Engine = E

local feats, byId, bySignal = {}, {}, {}
ns.feats, ns.featById, ns.packOrder = feats, byId, {}
local packSeen = {}
local marks = {}          -- signal name (or "SIGNAL:key") -> GetTime() of last occurrence
ns.marks = marks
local stateMT = { __index = ns.state }

function ns:RegisterPack(pack, list)
    if not packSeen[pack] then
        packSeen[pack] = true
        ns.packOrder[#ns.packOrder + 1] = pack
    end
    for _, f in ipairs(list) do
        f.pack = pack
        f.rating = f.rating or "A"
        if not f.tiers then f.tiers = { { f.count or 1, f.name, f.fine } } end
        f.hidden = math.abs(f.tiers[1][3]) >= 500
        f.keyword = f.signal == "CHAT_SELF" and f.when ~= nil
            and (f.when.text ~= nil or f.when.exact ~= nil or f.when.starts ~= nil) and not f.window
        feats[#feats + 1] = f
        byId[f.id] = f
        local list2 = bySignal[f.signal]
        if not list2 then list2 = {}; bySignal[f.signal] = list2 end
        list2[#list2 + 1] = f
    end
end

---------------------------------------------------------------------------
-- Conditions
---------------------------------------------------------------------------
local function anyOf(v, want)
    if type(want) ~= "table" then return v == want end
    for i = 1, #want do if v == want[i] then return true end end
    return false
end

local function contains(hay, want)
    if type(hay) ~= "string" then return false end
    if type(want) ~= "table" then return hay:find(want, 1, true) ~= nil end
    for i = 1, #want do
        if hay:find(want[i], 1, true) then return true end
    end
    return false
end

local function generic(v, want)
    if want == true then return v and true or false end
    if want == false then return not v end
    if type(want) == "table" then
        if want.min or want.max then
            if type(v) ~= "number" then return false end
            return (not want.min or v >= want.min) and (not want.max or v <= want.max)
        end
        return anyOf(v, want)
    end
    return v == want
end

-- Substring matches are always plain-text finds, never Lua patterns.
local CONTAINS = { text = true, killer = true, mob = true, target = true, spell = true }
local lastChatHit = {}    -- anti-cheese: keyword feats count at most once every 10 seconds

local COND = {
    within = function(w)
        local t = marks[w[1]]
        return t ~= nil and (GetTime() - t) <= w[2]
    end,
    zone = function(w, ctx)
        local zones = ctx.zones
        if not zones then return false end
        if type(w) ~= "table" then return zones[w] == true end
        for i = 1, #w do if zones[w[i]] then return true end end
        return false
    end,
    notZone = function(w, ctx)
        local zones = ctx.zones
        return not (zones and zones[w])
    end,
    instance = function(w, ctx)
        if w == true then return ctx.inst ~= nil end
        if w == false then return ctx.inst == nil end
        return anyOf(ctx.inst, w)
    end,
    inBox = function(w)
        if type(w) ~= "table" then return ns.Zones:InBox(w) end
        for i = 1, #w do if ns.Zones:InBox(w[i]) then return true end end
        return false
    end,
    subzone = function(w, ctx) return anyOf(ctx.subzone, w) end,
    statistic = function(w)
        local v = tonumber((ns.try(_G.GetStatistic, w.id))) or 0
        return v >= (w.min or 1)
    end,
    exact = function(w, ctx) return anyOf(ctx.text, w) end,
    starts = function(w, ctx)
        local text = ctx.text
        if type(text) ~= "string" then return false end
        for i = 1, #w do if text:sub(1, #w[i]) == w[i] then return true end end
        return false
    end,
}

local function Matches(f, ctx)
    local when = f.when
    if not when then return true end
    for k, want in pairs(when) do
        local h = COND[k]
        local pass
        if h then pass = h(want, ctx, f)
        elseif CONTAINS[k] then pass = contains(ctx[k], want)
        else pass = generic(ctx[k], want) end
        if not pass then return false end
    end
    return true
end

-- false = never for this character; "off" = pack disabled; true = live.
local function Eligible(f)
    local st = ns.state
    if f.class and f.class ~= st.class then return false end
    if f.faction and f.faction ~= st.faction then return false end
    if f.race and f.race ~= st.race then return false end
    if f.ruleset and f.ruleset ~= st.ruleset then return false end
    if f.rating == "C" and not ns.settings.experimental then return false end
    if ns.settings.packsOff[f.pack] then return "off" end
    return true
end
E.Eligible = Eligible

---------------------------------------------------------------------------
-- Awarding
---------------------------------------------------------------------------
local function CountEarned()
    local n = 0
    for _ in pairs(ns.char.earned) do n = n + 1 end
    return n
end
E.CountEarned = CountEarned

local function ApplyFine(f, tier, name, fine, isRepeat)
    local char = ns.char
    char.balance = char.balance - fine
    char.weekly = char.weekly - fine
    local entry = { id = f.id, tier = tier, name = name, fine = fine, t = time(), z = ns.state.zoneText, rep = isRepeat or nil }
    table.insert(char.log, 1, entry)
    while #char.log > 50 do table.remove(char.log) end
    local me = ns.db.chars[ns.charKey]
    if me then me.balance = char.balance end
    return entry
end

local function AllGkickEarned()
    for i = 1, #feats do
        local f = feats[i]
        if f.hidden and f.id ~= "removed_by_popular_demand" and f.tiers[1][3] > 0
            and Eligible(f) == true and not ns.char.earned[f.id] then
            return false
        end
    end
    return true
end

function ns:Award(f, tier, ctx)
    local char = ns.char
    local t = f.tiers[tier]
    if not t then return end
    local name, fine = t[2] or f.name, t[3]
    local prevFeatT = char.lastFeatT
    char.earned[f.id] = { tier = tier, t = time(), z = ns.state.zoneText }
    char.lastFeatT = time()
    if tier >= #f.tiers and not f.repeatable then f.done = true end
    local entry = ApplyFine(f, tier, name, fine)

    local me = ns.db.chars[ns.charKey]
    local earnedCount = CountEarned()
    if me then me.feats = earnedCount end

    local grouped = IsInGroup and IsInGroup() or false
    if ns.Toast then ns.Toast:Show(f, tier, name, fine) end
    ns.Print(("|c%s%s|r (%s DKP) - %s"):format(ns.TierOf(fine).color, name, ns.FineText(fine), f.flavor or ""))
    if ns.Sync then ns.Sync:OnAward(f, tier, fine) end
    if ns.Herald then ns.Herald:Announce(f, tier, name, fine, grouped) end
    if ns.Ledger then ns.Ledger:Refresh() end

    -- Meta signal. Recursion is bounded: every feat tier can be awarded once.
    local today = date("*t")
    local dayKey = today.year * 10000 + today.month * 100 + today.day
    if not char.dayPacks or char.dayPacks.day ~= dayKey then char.dayPacks = { day = dayKey, packs = {} } end
    char.dayPacks.packs[f.pack] = true
    local factions, rulesets, nRules = {}, {}, 0
    for _, c in pairs(ns.db.chars) do
        if (c.feats or 0) > 0 then
            if c.faction then factions[c.faction] = true end
            if c.ruleset and not rulesets[c.ruleset] then rulesets[c.ruleset] = true; nRules = nRules + 1 end
        end
    end
    local peers = ns.Sync and ns.Sync.recentFeats[f.id]
    local peer = false
    if peers then
        for who, at in pairs(peers) do
            if who ~= ns.playerName and GetTime() - at <= 60 then peer = true end
        end
    end
    ns:Fire("FEAT_EARNED", {
        key = f.id, featPack = f.pack, fine = fine, standard = (fine == 50),
        feats = earnedCount, debt = -char.balance, quiet = ns.settings.quiet,
        month = today.month, day = today.day,
        idleDays = prevFeatT and (time() - prevFeatT) / 86400 or 0,
        charAge = time() - char.firstSeen,
        bothFactions = factions.Alliance and factions.Horde and true or false,
        rulesets = nRules,
        gkickAll = f.hidden and AllGkickEarned() or false,
        classicPlus = char.dayPacks.packs.Forever and char.dayPacks.packs.Nostalgia and true or false,
        unique = (next(ns.db.guild) ~= nil) and not (ns.db.guildFeats and ns.db.guildFeats[f.id]),
    })
    if peer then ns:Fire("PEER_FEAT") end
    return entry
end

-- Optional module: a fully earned repeatable feat fines again, at most once an hour.
local function RepeatFine(f)
    local char = ns.char
    char.rep = char.rep or {}
    local r = char.rep[f.id] or { t = 0, n = 0 }
    if time() - r.t < 3600 then return end
    r.t, r.n = time(), r.n + 1
    char.rep[f.id] = r
    local t = f.tiers[#f.tiers]
    ApplyFine(f, #f.tiers, t[2], t[3], true)
    ns.Print(("%s, again (%s DKP)."):format(t[2], ns.FineText(t[3])))
    if ns.Sync then ns.Sync:SendBalance() end
    if ns.Ledger then ns.Ledger:Refresh() end
    ns:Fire("REPEAT_FINE", { key = f.id, times = r.n })
end

local function Eval(f, ctx)
    local elig = Eligible(f)
    if not elig then return end
    local store = f.session and ns.session or ns.char
    if not Matches(f, ctx) then
        if f.streak then store.c[f.id] = nil end
        return
    end
    if elig == "off" then
        ns.char.shadow[f.pack] = true
        return
    end

    if f.keyword then
        local now = GetTime()
        local last = lastChatHit[f.id]
        if last and now - last < 10 and now >= last then return end
        lastChatHit[f.id] = now
    end

    local earned = ns.char.earned[f.id]
    local tier = earned and earned.tier or 0
    if tier >= #f.tiers then
        if f.repeatable and ns.settings.repeatable then RepeatFine(f) end
        return
    end

    local n
    if f.value then
        n = tonumber(ctx[f.value]) or 0
    elseif f.window then
        local id = f.id
        if f.sameKey == true then id = id .. ":" .. tostring(rawget(ctx, "key"))
        elseif f.sameKey then id = id .. ":" .. tostring(ctx[f.sameKey]) end
        local win = ns.char.win      -- wall-clock stamps, so windows survive relogs
        local list = win[id]
        if not list then list = {}; win[id] = list end
        local now = time()
        list[#list + 1] = now
        while list[1] and (now - list[1] > f.window[2] or list[1] > now) do table.remove(list, 1) end
        n = (#list >= f.window[1]) and f.tiers[1][1] or 0
    elseif f.distinct then
        local v = ctx[f.distinct]
        if v == nil then return end
        local sets = store.sets
        local set = sets[f.id]
        if not set then set = { n = 0 }; sets[f.id] = set end
        if not set[v] then set[v] = true; set.n = set.n + 1 end
        n = set.n
    else
        n = (store.c[f.id] or 0) + (rawget(ctx, "n") or 1)
        store.c[f.id] = n
    end

    for i = tier + 1, #f.tiers do
        if n >= f.tiers[i][1] then ns:Award(f, i, ctx) else break end
    end
end

function ns:Fire(signal, ctx)
    if not ns.ready then return end
    ctx = setmetatable(ctx or {}, stateMT)
    local list = bySignal[signal]
    if list then
        for i = 1, #list do
            local f = list[i]
            if not f.done then Eval(f, ctx) end
        end
    end
    local now = GetTime()
    marks[signal] = now
    local key = rawget(ctx, "key")
    if key ~= nil then marks[signal .. ":" .. tostring(key)] = now end
end

-- Records a named mark without firing a signal (chat keywords, emotes).
function ns:Mark(name) marks[name] = GetTime() end

---------------------------------------------------------------------------
-- Queries used by the UI and herald
---------------------------------------------------------------------------
function E.Hint()
    local pool = {}
    for i = 1, #feats do
        local f = feats[i]
        if not ns.char.earned[f.id] and not f.hidden and f.hint and Eligible(f) == true then
            pool[#pool + 1] = f
        end
    end
    if #pool == 0 then
        ns.Print("No hints left. That is not a compliment.")
    else
        ns.Print("Hint: " .. pool[math.random(#pool)].hint)
    end
    ns:Fire("HINT")
end

-- Name and fine of the tier a character currently holds for a feat.
function E.EarnedInfo(f)
    local e = ns.char.earned[f.id]
    if not e then return nil end
    local t = f.tiers[e.tier] or f.tiers[#f.tiers]
    return t[2] or f.name, t[3], e
end

function E.Rarest()
    local best, bestFine
    for id in pairs(ns.char.earned) do
        local f = byId[id]
        if f then
            local name, fine = E.EarnedInfo(f)
            if not best or math.abs(fine) > bestFine then best, bestFine = name, math.abs(fine) end
        end
    end
    return best, bestFine
end

function E.TopFive()
    local list = {}
    for id, e in pairs(ns.char.earned) do
        local f = byId[id]
        if f then list[#list + 1] = { id = id, tier = e.tier, fine = math.abs(f.tiers[e.tier][3]) } end
    end
    table.sort(list, function(a, b) if a.fine ~= b.fine then return a.fine > b.fine end return a.id < b.id end)
    while #list > 5 do table.remove(list) end
    return list
end

function E.SetPack(pack, enabled)
    ns.settings.packsOff[pack] = (not enabled) or nil
    if enabled then
        local had = ns.char.shadow[pack] and true or false
        ns.char.shadow[pack] = nil
        ns:Fire("PACK_ENABLE", { key = pack, shadow = had })
    end
end

function E.ResetCharacter()
    local char = ns.char
    char.earned, char.c, char.sets, char.shadow, char.log, char.rep, char.win = {}, {}, {}, {}, {}, {}, {}
    char.balance, char.weekly, char.lastFeatT, char.firstSeen = 0, 0, nil, time()
    ns.NewSession()
    for i = 1, #feats do feats[i].done = nil end
    local me = ns.db.chars[ns.charKey]
    if me then me.balance, me.feats = 0, 0 end
    if ns.Ledger then ns.Ledger:Refresh() end
end

ns.logins[#ns.logins + 1] = function()
    -- Drop window lists nobody has touched for a month.
    local now = time()
    for id, list in pairs(ns.char.win) do
        local last = list[#list]
        if not last or now - last > 2592000 then ns.char.win[id] = nil end
    end
    for i = 1, #feats do
        local f = feats[i]
        local e = ns.char.earned[f.id]
        f.done = (e and e.tier >= #f.tiers and not f.repeatable) or nil
    end
end
