-- Interface-habit signals: window opens, bag fidgeting, error messages.
-- Signals: UI_OPEN, UI_CLOSE, BAG_FIDGET, UI_ERROR, SCREENSHOT, MACROS, ACTIONBARS
local _, ns = ...
local st = ns.state

---------------------------------------------------------------------------
-- Frame open/close hooks. Many Blizzard frames load on demand, so pending
-- hooks are retried whenever another addon loads.
---------------------------------------------------------------------------
local pending = {
    CHARACTER = { "CharacterFrame" },
    SPELLBOOK = { "SpellBookFrame", "PlayerSpellsFrame" },
    TALENTS   = { "PlayerTalentFrame", "ClassTalentFrame", "TalentFrame" },
    MAP       = { "WorldMapFrame" },
    SETTINGS  = { "SettingsPanel" },
    MACROS    = { "MacroFrame" },
    LEGACY    = { "LegacyFrame", "LegacyPanel" },
}
local openedAt = {}

local function HookFrames()
    for key, names in pairs(pending) do
        for i = #names, 1, -1 do
            local frame = _G[names[i]]
            if type(frame) == "table" and frame.HookScript then
                table.remove(names, i)
                frame:HookScript("OnShow", function()
                    openedAt[key] = GetTime()
                    st[key .. "_open"] = true
                    ns:Fire("UI_OPEN", { key = key, ui = key })
                end)
                frame:HookScript("OnHide", function()
                    st[key .. "_open"] = false
                    local t = openedAt[key]
                    ns:Fire("UI_CLOSE", { key = key, ui = key, duration = t and (GetTime() - t) or 0 })
                end)
            end
        end
    end
end
ns.logins[#ns.logins + 1] = HookFrames
ns:On("ADDON_LOADED", function() if ns.ready then HookFrames() end end)

---------------------------------------------------------------------------
-- Bags: opened, touched nothing, closed.
---------------------------------------------------------------------------
local bagsOpen, bagsTouched = false, false

local function BagsOpened()
    if bagsOpen then return end
    bagsOpen, bagsTouched = true, false
end
local function BagsClosed()
    if not bagsOpen then return end
    bagsOpen = false
    if not bagsTouched and not st.MERCHANT_open and not st.bankOpen and not st.mailOpen then
        ns:Fire("BAG_FIDGET")
    end
end
local function Touch() bagsTouched = true end
ns:On("ITEM_LOCK_CHANGED", Touch)
ns:On("BAG_UPDATE", Touch)

ns.logins[#ns.logins + 1] = function()
    local hooked = false
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local frame = _G[name]
        if type(frame) == "table" and frame.HookScript then
            frame:HookScript("OnShow", BagsOpened)
            frame:HookScript("OnHide", BagsClosed)
            hooked = true
        end
    end
    -- Bag-replacement addons hide the stock frames; fall back to the toggle call.
    local function Toggled()
        C_Timer.After(0, function()
            local stock = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
                or (ContainerFrame1 and ContainerFrame1:IsShown())
            if hooked and stock then return end
            if bagsOpen then BagsClosed() else BagsOpened() end
        end)
    end
    ns.Hook("ToggleAllBags", Toggled)
    ns.Hook("ToggleBackpack", Toggled)
end

---------------------------------------------------------------------------
-- Error messages. Matched by exact global string through a lookup table.
---------------------------------------------------------------------------
local ERRORS = {
    OUT_OF_RANGE = { "ERR_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE" },
    FACING       = { "ERR_BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT", "SPELL_FAILED_NOT_INFRONT" },
    NO_MANA      = { "ERR_OUT_OF_MANA", "SPELL_FAILED_NO_POWER" },
    NO_RAGE      = { "ERR_OUT_OF_RAGE" },
    NOT_READY    = { "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "SPELL_FAILED_NOT_READY", "ERR_ITEM_COOLDOWN" },
    MOVING       = { "SPELL_FAILED_MOVING" },
    IN_PROGRESS  = { "SPELL_FAILED_SPELL_IN_PROGRESS", "ERR_SPELL_IN_PROGRESS" },
    NO_TARGET    = { "ERR_GENERIC_NO_TARGET", "SPELL_FAILED_BAD_TARGETS", "ERR_NO_ATTACK_TARGET" },
    INV_FULL     = { "ERR_INV_FULL", "INVENTORY_FULL" },
    NO_MONEY     = { "ERR_NOT_ENOUGH_MONEY" },
    NO_MOUNT     = { "SPELL_FAILED_NO_MOUNTS_ALLOWED", "ERR_MOUNT_NOT_ALLOWED", "SPELL_FAILED_ONLY_OUTDOORS" },
    FISH_ESCAPED = { "ERR_FISH_ESCAPED", "ERR_FISH_NOT_HOOKED" },
    NOT_FISHABLE = { "SPELL_FAILED_NOT_FISHABLE", "SPELL_FAILED_FISHING_TOO_LOW" },
    TOO_CLOSE    = { "SPELL_FAILED_TOO_CLOSE" },
    SHAPESHIFTED = { "SPELL_FAILED_NOT_SHAPESHIFT", "ERR_CANT_INTERACT_SHAPESHIFTED", "ERR_NOT_WHILE_SHAPESHIFTED" },
    FORBEARANCE  = { "SPELL_FAILED_FORBEARANCE" },
    BUSY         = { "ERR_OBJECT_IS_BUSY", "SPELL_FAILED_CHEST_IN_USE" },
    SKILL_LOW    = { "SPELL_FAILED_LOW_CASTLEVEL", "ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI" },
    NEED_TOOL    = { "SPELL_FAILED_TOTEMS", "SPELL_FAILED_EQUIPPED_ITEM", "SPELL_FAILED_TOTEM_CATEGORY" },
    LOCKOUT      = { "ERR_TOO_MANY_INSTANCES", "INSTANCE_LOCKOUT_ERROR" },
}
local errorKey = {}
for key, names in pairs(ERRORS) do
    for _, g in ipairs(names) do
        local s = _G[g]
        if type(s) == "string" and not errorKey[s] then errorKey[s] = key end
    end
end

ns:On("UI_ERROR_MESSAGE", function(_, msg)
    if not ns.ready then return end
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local seen = ns.session.errors
    if not seen then seen = { n = 0 }; ns.session.errors = seen end
    if not seen[msg] then seen[msg] = true; seen.n = seen.n + 1 end
    local key = errorKey[msg] or "OTHER"
    ns:Fire("UI_ERROR", { key = key, err = key, distinctErrors = seen.n })
end)

---------------------------------------------------------------------------
-- Odds and ends
---------------------------------------------------------------------------
ns:On("SCREENSHOT_SUCCEEDED", function() ns:Fire("SCREENSHOT") end)

ns:On("UPDATE_MACROS", function()
    if not ns.ready or not GetNumMacros then return end
    local account, character = GetNumMacros()
    local full = account >= (MAX_ACCOUNT_MACROS or 120) and character >= (MAX_CHARACTER_MACROS or 18)
    ns:Fire("MACROS", { macrosFull = full })
end)

ns.logins[#ns.logins + 1] = function()
    C_Timer.After(10, function()
        if not HasAction then return end
        local empty = 0
        for slot = 1, 48 do
            if not HasAction(slot) then empty = empty + 1 end
        end
        ns:Fire("ACTIONBARS", { emptySlots = empty })
    end)
end
