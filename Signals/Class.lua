-- Class and profession signals, from the player's own successful casts and
-- form changes. Spell names are matched in English (lower-case); on other
-- locales these feats simply stay unearned.
-- Signals: CAST, SHAPESHIFT, STEALTH, GATHER, SKILL_UP, TALENT_RESET, PET_GONE
local _, ns = ...
local st = ns.state

local function SpellName(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then name = ns.try(C_Spell.GetSpellName, spellID)
    elseif GetSpellInfo then name = ns.try(GetSpellInfo, spellID) end
    return type(name) == "string" and name:lower() or nil
end

local GATHER = { ["mining"] = true, ["herb gathering"] = true, ["skinning"] = true, ["herbalism"] = true }

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    spellID = ns.safe(spellID)
    if not spellID then return end
    local name = SpellName(spellID)
    if not name then return end
    local blinkX, blinkY
    if name == "blink" then blinkX, blinkY = ns.Zones:Position() end
    ns:Fire("CAST", {
        key = name, spell = name, spellID = spellID,
        bandage = name:find("bandage", 1, true) ~= nil,
        conjure = name:find("conjure food", 1, true) ~= nil or name:find("conjure water", 1, true) ~= nil,
        portal = name:find("portal:", 1, true) ~= nil,
        totem = name:find("totem", 1, true) ~= nil,
        blessing = name:find("blessing of", 1, true) ~= nil,
        selfTarget = not UnitExists("target") or UnitIsUnit("target", "player"),
    })
    if GATHER[name] then ns:Fire("GATHER") end
    if blinkX then
        C_Timer.After(0.5, function()
            local x, y = ns.Zones:Position()
            if x and math.abs(x - blinkX) < 0.0005 and math.abs(y - blinkY) < 0.0005 then
                ns:Fire("BLINK_NOWHERE")
            end
        end)
    end
end)

ns:On("UNIT_SPELLCAST_START", function(unit, _, spellID)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    local name = SpellName(ns.safe(spellID))
    if name and GATHER[name] then
        ns:Mark("GATHER_START")
    end
end)

ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    local name = SpellName(ns.safe(spellID))
    if name == "fishing" then
        st.lastFishing = GetTime()
        st.fishingUntil = GetTime() + 22
        ns:Fire("FISH_CAST")
    end
end)

-- Forms, stances, stealth, eating
local function FormName()
    if not GetShapeshiftForm then return nil end
    local index = GetShapeshiftForm()
    if not index or index == 0 then return nil end
    local _, _, _, spellID = GetShapeshiftFormInfo(index)
    local name = spellID and SpellName(spellID) or ""
    if name:find("bear", 1, true) then return "BEAR" end
    if name:find("cat", 1, true) then return "CAT" end
    if name:find("ghost wolf", 1, true) then return "GHOSTWOLF" end
    return "OTHER"
end

ns:On("UPDATE_SHAPESHIFT_FORM", function()
    if not ns.ready then return end
    local form = FormName()
    if form == st.form then return end
    st.form = form
    ns:Fire("SHAPESHIFT", { key = form or "NONE" })
end)

local wasStealth = false
ns:On("UPDATE_STEALTH", function()
    if not ns.ready then return end
    local now = IsStealthed and IsStealthed() and true or false
    if now and not wasStealth then ns:Fire("STEALTH") end
    wasStealth = now
end)

local function HasAura(name)
    if not (AuraUtil and AuraUtil.FindAuraByName) then return false end
    local ok, found = pcall(AuraUtil.FindAuraByName, name, "player")
    return ok and found ~= nil
end

ns.tickers[#ns.tickers + 1] = function(now)
    st.fishing = st.fishingUntil ~= nil and now < st.fishingUntil
    -- Aura data is restricted in combat; nobody eats in combat anyway.
    if not st.combat then
        local eating = HasAura("Food") or HasAura("Drink") or HasAura("Food & Drink")
        if eating and not st.eating then ns:Fire("DRINK", { drinking = HasAura("Drink") }) end
        st.eating = eating
        st.ghostWolf = st.form == "GHOSTWOLF"
    end
end

-- Profession skill-ups
ns:On("CHAT_MSG_SKILL", function() if ns.ready then ns:Fire("SKILL_UP") end end)

-- Talent resets (API names differ by client; hook whichever exists)
local function TalentReset() if ns.ready then ns:Fire("TALENT_RESET") end end
if not ns.Hook("ConfirmTalentWipe", TalentReset) and C_ClassTalents then
    ns.Hook(C_ClassTalents, "ResetActiveConfig", TalentReset)
end

-- Hunter pet ran away / ammo (C-rated: unverified on Forever)
ns:On("UNIT_PET", function(unit)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    st.petOut = UnitExists("pet") and true or false
end)
ns:On("UNIT_INVENTORY_CHANGED", function(unit)
    if ns.safe(unit) ~= "player" or not ns.ready or st.class ~= "HUNTER" then return end
    local ammo = ns.try(GetInventoryItemCount, "player", 0)
    local hasAmmoItem = GetInventoryItemID("player", 0) ~= nil
    if st.hadAmmo and not hasAmmoItem and (ammo or 0) <= 1 then ns:Fire("OUT_OF_AMMO") end
    st.hadAmmo = hasAmmoItem
end)
