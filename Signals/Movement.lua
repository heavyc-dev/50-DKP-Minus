-- Movement and travel signals.
-- Signals: JUMP, MOUNT, DISMOUNT, FLIGHT_END, ZONE_ENTER, SUBZONE_ENTER,
--          INSTANCE_ENTER, INSTANCE_LEAVE, CONTINENT, HEARTH_ARRIVE, LOADING_END
local _, ns = ...
local st = ns.state

-- Jumps. The hook fires on the key press, so it also counts swimming upward;
-- that is fine for a spacebar counter.
local jumpX, jumpY
ns.Hook("JumpOrAscendStart", function()
    if not ns.ready or st.taxi or st.dead then return end
    local x, y = ns.Zones:Position()
    local inPlace = x ~= nil and jumpX ~= nil and math.abs(x - jumpX) < 0.0002 and math.abs(y - jumpY) < 0.0002
    jumpX, jumpY = x, y
    st.lastJump = GetTime()
    ns:Fire("JUMP", { inPlace = inPlace })
end)

-- Mount, dismount and flights are edge-detected on the shared ticker.
local wasMounted, wasTaxi, taxiStart = false, false, nil
ns.tickers[#ns.tickers + 1] = function(now)
    if st.mounted ~= wasMounted then
        wasMounted = st.mounted
        if not st.taxi then ns:Fire(st.mounted and "MOUNT" or "DISMOUNT") end
    end
    if st.taxi ~= wasTaxi then
        wasTaxi = st.taxi
        if st.taxi then
            taxiStart = now
        elseif taxiStart then
            ns:Fire("FLIGHT_END", { duration = now - taxiStart })
            taxiStart = nil
        end
    end
end

---------------------------------------------------------------------------
-- Zones and instances
---------------------------------------------------------------------------
local lastInst, instEnteredAt, lastContinent

local function ZoneChanged(isNewZone)
    if not ns.ready then return end
    local prevSub = st.subzone
    ns.Zones:Refresh()
    if isNewZone then ns:Fire("ZONE_ENTER", { key = st.zoneText }) end
    if st.subzone ~= "" and st.subzone ~= prevSub then
        ns:Fire("SUBZONE_ENTER", { key = st.subzone })
    end
end
ns:On("ZONE_CHANGED_NEW_AREA", function() ZoneChanged(true) end)
ns:On("ZONE_CHANGED", function() ZoneChanged(false) end)
ns:On("ZONE_CHANGED_INDOORS", function() ZoneChanged(false) end)

local hearthFrom
ns:On("PLAYER_ENTERING_WORLD", function()
    if not ns.ready then return end
    ns.Zones:Refresh()
    local inst = st.inst
    if inst ~= lastInst then
        if lastInst and instEnteredAt then
            ns:Fire("INSTANCE_LEAVE", { key = lastInst, left = lastInst, duration = GetTime() - instEnteredAt })
        end
        if inst then
            instEnteredAt = GetTime()
            ns:Fire("INSTANCE_ENTER", { key = inst, instanceType = st.instanceType })
        end
        lastInst = inst
    end
    if not st.inInstance and st.continent and lastContinent and st.continent ~= lastContinent then
        ns:Fire("CONTINENT", { key = st.continent })
    end
    if not st.inInstance then lastContinent = st.continent end
end)

ns:On("LOADING_SCREEN_DISABLED", function()
    if not ns.ready then return end
    ns:Fire("LOADING_END")
end)

---------------------------------------------------------------------------
-- Hearthstone: remember where the cast finished, compare where it landed.
---------------------------------------------------------------------------
local HEARTHSTONE = 8690
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    spellID = ns.safe(spellID)
    if spellID ~= HEARTHSTONE then return end
    hearthFrom = st.zoneText
    C_Timer.After(8, function()
        ns.Zones:Refresh()
        ns:Fire("HEARTH_ARRIVE", { sameZone = hearthFrom ~= nil and hearthFrom == st.zoneText })
        hearthFrom = nil
    end)
end)
