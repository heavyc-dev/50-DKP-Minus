-- Death signals. Never reads the combat log; cause comes from the death recap
-- when the client exposes it, otherwise from what the player was doing.
-- Signals: DEATH, RELEASE, RESURRECT, CORPSE_RUN, BREATH, FATIGUE,
--          PARTY_DEATH, PARTY_WIPE, BOSS_END
local _, ns = ...
local st = ns.state

local timers = {}            -- active mirror timers: BREATH, EXHAUSTION
local diedAt, releasedAt, resRequested
local RES_SICKNESS = 15007

ns:On("MIRROR_TIMER_START", function(name)
    name = ns.safe(name)
    if not name then return end
    timers[name] = true
    if name == "EXHAUSTION" then
        ns:Fire("FATIGUE")
    elseif name == "BREATH" then
        ns:Fire("BREATH")
    end
end)
ns:On("MIRROR_TIMER_STOP", function(name)
    name = ns.safe(name)
    if name then timers[name] = nil end
end)

local ENV = { FALLING = "FALL", DROWNING = "DROWN", FATIGUE = "FATIGUE", FIRE = "FIRE", LAVA = "LAVA", SLIME = "SLIME" }

-- Last recap event, if the client lets us see it. Fields are undocumented on
-- Forever, so everything is optional and secret-checked.
local function ReadRecap()
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" then return nil end
    local ev = events[1]
    if type(ev) ~= "table" then return nil end
    -- Ignore a stale recap left over from an earlier death.
    local ts = ns.safe(ev.timestamp)
    if type(ts) == "number" and GetServerTime and math.abs(GetServerTime() - ts) > 20 then return nil end
    local cause, killer
    local env = ns.safe(ev.environmentalType)
    if type(env) == "string" then cause = ENV[env:upper()] end
    local src = ns.safe(ev.sourceName)
    if type(src) == "string" and src ~= "" then killer = src:lower() end
    local spell = ns.safe(ev.spellName)
    return cause, killer, type(spell) == "string" and spell:lower() or nil
end

local function Durability()
    local lowest, items, broken, armour = 1, 0, 0, 0
    for slot = 1, 18 do
        if GetInventoryItemID("player", slot) then
            if slot ~= 4 and slot ~= 11 and slot ~= 12 and slot ~= 13 and slot ~= 14 and slot < 16 then
                armour = armour + 1
            end
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                items = items + 1
                local pct = cur / max
                if pct < lowest then lowest = pct end
                if cur == 0 then broken = broken + 1 end
            end
        end
    end
    return lowest, items > 0 and broken == items, armour == 0
end

ns:On("PLAYER_DEAD", function()
    if not ns.ready then return end
    local now = GetTime()
    diedAt, releasedAt = now, nil
    local char = ns.char
    local lowest, allBroken, naked = Durability()
    local xpMax = UnitXPMax("player") or 0
    local power, powerMax
    if UnitPowerType("player") == 0 then
        power, powerMax = ns.try(UnitPower, "player", 0), ns.try(UnitPowerMax, "player", 0)
    end
    local ctx = {
        afk = st.afk,
        mounted = st.lastMounted ~= nil and now - st.lastMounted < 2.5,
        stealthed = st.lastStealth ~= nil and now - st.lastStealth < 2.5,
        fishing = st.lastFishing ~= nil and now - st.lastFishing < 25,
        eating = st.eating,
        wasInCombat = st.combat,
        naked = naked, allBroken = allBroken, lowDurability = lowest < 0.10,
        xpPct = xpMax > 0 and (UnitXP("player") / xpMax) or 0,
        noMana = power ~= nil and powerMax ~= nil and powerMax > 0 and power == 0,
        solo = not st.grouped,
        resSick = st.resSick,
        petOut = UnitExists("pet") and true or false,
        sameSubzone = st.subzone,
    }
    local heuristic
    if st.lastFalling and now - st.lastFalling < 1.5 and not st.combat then heuristic = "FALL"
    elseif timers.EXHAUSTION then heuristic = "FATIGUE"
    elseif timers.BREATH and st.swimming then heuristic = "DROWN" end
    ctx.fallInCombat = st.lastFalling ~= nil and now - st.lastFalling < 1.5 and st.combat

    -- The recap is filled a moment after the event.
    C_Timer.After(0.4, function()
        local cause, killer, spell = ReadRecap()
        ctx.cause = cause or heuristic
        ctx.killer = killer
        ctx.killSpell = spell
        ctx.key = ctx.cause
        char.deaths = (char.deaths or 0) + 1
        ctx.deaths = char.deaths
        ctx.first = char.deaths == 1
        if killer then
            char.killers = char.killers or {}
            char.killers[killer] = (char.killers[killer] or 0) + 1
            ctx.sameKiller = char.killers[killer]
        end
        ns:Fire("DEATH", ctx)
    end)
end)

-- PLAYER_ALIVE fires both on releasing (now a ghost) and on being resurrected.
ns:On("PLAYER_ALIVE", function()
    if not ns.ready then return end
    if UnitIsGhost("player") then
        releasedAt = GetTime()
        ns:Fire("RELEASE", { key = st.subzone })
    elseif diedAt then
        ns:Fire("RESURRECT", { byPlayer = resRequested and true or false, spiritHealer = false })
        diedAt, resRequested = nil, nil
    end
end)

ns:On("PLAYER_UNGHOST", function()
    if not ns.ready then return end
    local ghostTime = releasedAt and (GetTime() - releasedAt) or 0
    local byPlayer = resRequested and true or false
    diedAt, releasedAt, resRequested = nil, nil, nil
    -- Resurrection Sickness lands just after; it tells us it was a spirit healer.
    C_Timer.After(1, function()
        local sick = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and ns.try(C_UnitAuras.GetPlayerAuraBySpellID, RES_SICKNESS) ~= nil or false
        st.resSick = sick
        ns:Fire("RESURRECT", { byPlayer = byPlayer, spiritHealer = sick, ghostTime = ghostTime })
        if not sick and not byPlayer then
            ns:Fire("CORPSE_RUN", { duration = ghostTime })
        end
    end)
end)

ns:On("RESURRECT_REQUEST", function() resRequested = true end)

ns.tickers[#ns.tickers + 1] = function()
    if st.resSick and not (C_UnitAuras and ns.try(C_UnitAuras.GetPlayerAuraBySpellID, RES_SICKNESS)) then
        st.resSick = false
    end
end

---------------------------------------------------------------------------
-- Party deaths (outdoors only; unit state is restricted inside instances)
---------------------------------------------------------------------------
local partyDead = {}
ns.tickers[#ns.tickers + 1] = function()
    if not st.grouped or st.inInstance or IsInRaid() then
        if next(partyDead) then wipe(partyDead) end
        return
    end
    local members, dead = 0, 0
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            members = members + 1
            local isDead = ns.try(UnitIsDeadOrGhost, unit) and true or false
            if isDead then dead = dead + 1 end
            if isDead and not partyDead[i] then ns:Fire("PARTY_DEATH") end
            partyDead[i] = isDead
        else
            partyDead[i] = nil
        end
    end
    local wiped = members == 4 and dead == 4 and st.dead
    if wiped and not st.partyWiped then ns:Fire("PARTY_WIPE") end
    st.partyWiped = wiped
end

---------------------------------------------------------------------------
-- Boss encounters
---------------------------------------------------------------------------
ns:On("ENCOUNTER_START", function() st.encounter = true end)
ns:On("ENCOUNTER_END", function(_, _, _, _, success)
    st.encounter = false
    success = ns.safe(success)
    if success == nil then return end
    local won = success == 1 or success == true
    local dead = UnitIsDeadOrGhost("player") and true or false
    local session = ns.session
    if won then ns:Mark("BOSS_KILL") end
    if won and dead then session.deadKills = (session.deadKills or 0) + 1 end
    ns:Fire("BOSS_END", { success = won, wasDead = dead, deadKills = session.deadKills or 0 })
end)
