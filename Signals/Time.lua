-- Time signals: the one 1-second ticker, login/logout, /played, session clock.
-- Signals: TICK, MINUTE, LOGIN, RELOAD, LOGOUT, LOGOUT_CANCEL, PLAYED, PLAYED_CHECK
local _, ns = ...
local st = ns.state
ns.tickers = {}    -- other signal files add state updaters here

local lastX, lastY, stillFor, lastMinute = nil, nil, 0, nil

local function Tick()
    st.afk = UnitIsAFK("player") and true or false
    st.dead = UnitIsDeadOrGhost("player") and true or false
    st.ghost = UnitIsGhost("player") and true or false
    st.mounted = IsMounted() and true or false
    st.swimming = IsSwimming() and true or false
    st.falling = IsFalling() and true or false
    st.taxi = UnitOnTaxi("player") and true or false
    st.combat = UnitAffectingCombat("player") and true or false
    st.resting = IsResting() and true or false
    st.stealth = IsStealthed and IsStealthed() and true or false
    st.grouped = IsInGroup() and true or false
    st.guilded = IsInGuild() and true or false
    st.level = UnitLevel("player")

    local now = GetTime()
    if st.mounted then st.lastMounted = now end
    if st.falling then st.lastFalling = now end
    if st.stealth then st.lastStealth = now end

    -- Position bookkeeping (outdoors only; nil inside instances).
    local speed = ns.safe(GetUnitSpeed("player")) or 0
    local x, y = ns.Zones:Position()
    if x and lastX and math.abs(x - lastX) < 0.00005 and math.abs(y - lastY) < 0.00005 then
        stillFor = stillFor + 1
    else
        stillFor = 0
    end
    lastX, lastY = x, y
    st.hasPosition = x ~= nil
    st.still = x ~= nil and stillFor > 0
    st.wallRun = x ~= nil and stillFor > 0 and speed > 0 and not st.taxi   -- moving, going nowhere
    st.walking = speed > 0 and speed < 3 and not st.swimming and not st.stealth and not st.dead
    st.firstPerson = GetCameraZoom and (ns.safe(GetCameraZoom()) == 0) or false

    for i = 1, #ns.tickers do ns.tickers[i](now) end
    ns:Fire("TICK")

    local d = date("*t")
    if d.min ~= lastMinute then
        lastMinute = d.min
        st.hour = d.hour
        ns:Fire("MINUTE", { hour = d.hour, minute = d.min, month = d.month, day = d.day, wday = d.wday,
            dateKey = d.month * 100 + d.day })
        if ns.char.playedBase then
            ns:Fire("PLAYED", { days = (ns.char.playedBase + (time() - ns.char.playedAt)) / 86400 })
        end
    end
end

ns.logins[#ns.logins + 1] = function()
    ns.Zones:Refresh()
    C_Timer.NewTicker(1, Tick)
end

---------------------------------------------------------------------------
-- Login, reload, logout
---------------------------------------------------------------------------
local function CountAddons()
    local num = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or 0
    local enabled = 0
    for i = 1, num do
        local state = ns.try(C_AddOns.GetAddOnEnableState, i, ns.playerName)
        if state and state > 0 then enabled = enabled + 1 end
    end
    return enabled
end

local function SelfOutdated()
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
    local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, "FiftyDKPMinus")
    return ok and reason == "INTERFACE_VERSION"
end

ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not ns.ready then return end
    ns.Zones:Refresh()
    local char = ns.char
    if isLogin then
        ns.NewSession()
        local d = date("*t")
        local today = math.floor((time() + (d.isdst and 3600 or 0)) / 86400)
        local daysAway = char.lastLogin and (time() - char.lastLogin) / 86400 or 0
        if char.lastLoginDay == today - 1 then
            char.loginStreak = (char.loginStreak or 1) + 1
        elseif char.lastLoginDay ~= today then
            char.loginStreak = 1
        end
        char.lastLoginDay, char.lastLogin = today, time()
        -- Short delay so the toast is not lost behind the loading screen.
        C_Timer.After(5, function()
            ns:Fire("LOGIN", {
                month = d.month, day = d.day, wday = d.wday, hour = d.hour,
                daysAway = daysAway, loginStreak = char.loginStreak,
                addons = CountAddons(), outdated = SelfOutdated(),
            })
        end)
    elseif isReload then
        C_Timer.After(2, function() ns:Fire("RELOAD") end)
    end
end)

local camping = false
ns:On("PLAYER_CAMPING", function() camping = true end)
ns:On("PLAYER_QUITING", function() camping = true end)
ns:On("LOGOUT_CANCEL", function()
    if camping then ns:Fire("LOGOUT_CANCEL") end
    camping = false
end)
ns:On("PLAYER_LOGOUT", function()
    if not ns.ready then return end
    if ns.char.playedBase then
        ns.char.playedBase = ns.char.playedBase + (time() - ns.char.playedAt)
        ns.char.playedAt = time()
    end
    if camping then
        ns:Fire("LOGOUT", { afkFor = st.afkSince and (GetTime() - st.afkSince) or 0 })
    end
end)

---------------------------------------------------------------------------
-- /played. We never request it ourselves (it prints to chat); once the player
-- has checked once, the session clock keeps the total current.
---------------------------------------------------------------------------
local requested = false
ns.Hook("RequestTimePlayed", function() requested = true end)
ns:On("TIME_PLAYED_MSG", function(total)
    total = ns.safe(total)
    if not total then return end
    ns.char.playedBase, ns.char.playedAt = total, time()
    if requested then
        requested = false
        ns:Fire("PLAYED_CHECK")
    end
    ns:Fire("PLAYED", { days = total / 86400 })
end)
