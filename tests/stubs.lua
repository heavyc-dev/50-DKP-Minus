-- Minimal WoW API stand-in so the addon can be loaded and exercised outside
-- the game. Only what the addon touches; behaviour is driven through P and T.
unpack = unpack or table.unpack
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return unpack(out)
end

T = { now = 1000, epoch = 1794000000, timers = {}, widgets = {}, sent = {}, addon = {}, printed = {} }
P = {   -- player / world state the tests poke
    level = 30, afk = false, dead = false, ghost = false, mounted = false, swimming = false, falling = false,
    taxi = false, combat = false, resting = false, stealth = false, grouped = false, guild = "Testers",
    raid = false, zone = "Durotar", subzone = "Razor Hill", money = 123456, names = {}, speed = 0,
    instance = { "Kalimdor", "none", 0, "", 0, 0, false, 1 }, x = 0.5, y = 0.5,
}

time = function() return T.epoch + math.floor(T.now) end
date = function(fmt, t) return os.date(fmt, t or time()) end
GetTime = function() return T.now end
geterrorhandler = function() return error end
GetServerTime = time

local NIL_FIELDS = { TitleText = true, TitleContainer = true, Text = true, EditBox = true }
local function Widget()
    local w = { scripts = {}, shown = true }
    T.widgets[#T.widgets + 1] = w
    return setmetatable(w, { __index = function(_, k)
        if type(k) ~= "string" or NIL_FIELDS[k] or not k:match("^%u") then return nil end
        if k == "SetScript" or k == "HookScript" then return function(self, name, fn) self.scripts[name] = fn end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self)
            self.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end end
        if k == "Hide" then return function(self)
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end end
        if k == "GetParent" then return function() return Widget() end end
        if k:match("^Create") then return function() return Widget() end end
        if k:match("^Get") then return function() return 100, 100 end end
        if k:match("^Has") or k:match("^Is") then return function() return false end end
        return function() end
    end })
end
CreateFrame = function() return Widget() end
UIParent, Minimap, GameTooltip = Widget(), Widget(), Widget()
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
StaticPopup_Show = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) T.printed[#T.printed + 1] = msg end }

function T.event(event, ...)
    for _, w in ipairs(T.widgets) do
        if w.scripts.OnEvent then w.scripts.OnEvent(w, event, ...) end
    end
end

function T.advance(seconds)
    local target = T.now + seconds
    while true do
        local best
        for i, t in ipairs(T.timers) do
            if t.at <= target and (not best or t.at < T.timers[best].at) then best = i end
        end
        if not best then break end
        local t = T.timers[best]
        T.now = math.max(T.now, t.at)
        if t.every then t.at = t.at + t.every else table.remove(T.timers, best) end
        t.fn()
    end
    T.now = target
end

C_Timer = {
    After = function(d, fn) T.timers[#T.timers + 1] = { at = T.now + d, fn = fn } end,
    NewTicker = function(d, fn) T.timers[#T.timers + 1] = { at = T.now + d, fn = fn, every = d } end,
}

hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end

local function const(v) return function() return v end end
local function flag(k) return function() return P[k] end end

UnitFullName = function() return "Tester", "Realm" end
GetRealmName = const("Realm")
UnitName = function(unit) if unit == "player" then return "Tester" end return P.names[unit] end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitFactionGroup = const("Horde")
UnitRace = function() return "Orc", "Orc" end
UnitLevel = flag("level")
UnitGUID = const("Player-1-0001")
UnitIsAFK = function(unit) return unit == "player" and P.afk end
UnitIsDeadOrGhost = function(unit) return unit == "player" and (P.dead or P.ghost) end
UnitIsGhost = flag("ghost")
IsMounted, IsSwimming, IsFalling = flag("mounted"), flag("swimming"), flag("falling")
UnitOnTaxi, UnitAffectingCombat, IsResting, IsStealthed = flag("taxi"), flag("combat"), flag("resting"), flag("stealth")
IsInGroup, IsInRaid = flag("grouped"), flag("raid")
IsInGuild = function() return P.guild ~= nil end
GetGuildInfo = flag("guild")
GetNumGroupMembers = const(5)
GetUnitSpeed = flag("speed")
GetCameraZoom = const(10)
UnitExists = function(unit) return P.names[unit] ~= nil end
UnitIsUnit = function(a, b) return a == b end
UnitIsPlayer = const(false)
UnitXP, UnitXPMax = const(100), const(1000)
UnitPowerType, UnitPower, UnitPowerMax = const(1), const(0), const(100)
GetInventoryItemID = function(_, slot) return slot ~= 0 and 1000 + slot or nil end
GetInventoryItemDurability = const(50, 100)
GetInventoryItemDurability = function() return 50, 100 end
GetInventoryItemCount = const(0)
GetMoney = flag("money")
GetRealZoneText, GetSubZoneText = flag("zone"), flag("subzone")
GetInstanceInfo = function() return unpack(P.instance) end
GetGameTime = function() return 12, 0 end
HasAction = const(true)
GetNumMacros = function() return 3, 2 end
GetShapeshiftForm = const(0)
CanMerchantRepair, GetRepairAllCost = const(true), const(0)
GetInboxNumItems = const(0)
GetCursorPosition = function() return 0, 0 end
PlaySound = function() end
SOUNDKIT = { RAID_WARNING = 8959 }

for _, name in ipairs({ "DoEmote", "JumpOrAscendStart", "RequestTimePlayed", "BuyMerchantItem", "BuybackItem",
    "RepairAllItems", "DeleteCursorItem", "RollOnLoot", "ToggleAllBags", "ToggleBackpack", "ConfirmTalentWipe" }) do
    _G[name] = function() end
end

C_Map = {
    GetBestMapForUnit = const(1411),
    GetMapInfo = function() return { parentMapID = nil } end,
    GetPlayerMapPosition = function() return { GetXY = function() return P.x, P.y end } end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, msg, channel, target) T.addon[#T.addon + 1] = { msg = msg, channel = channel, target = target } end,
    SendChatMessage = function(msg, channel, _, target) T.sent[#T.sent + 1] = { msg = msg, channel = channel, target = target } end,
    InChatMessagingLockdown = const(false),
}
C_AddOns = {
    GetAddOnMetadata = const("0.0.0-test"), GetNumAddOns = const(12),
    GetAddOnEnableState = const(2), GetAddOnInfo = function() return "FiftyDKPMinus", "50 DKP Minus", "", true, nil end,
}
C_Container = {
    GetContainerNumSlots = const(4), GetContainerItemInfo = const(nil), GetContainerItemLink = const(nil),
    UseContainerItem = function() end,
}
C_Item = { GetItemInfo = function() return "Item", "link", 1 end, GetItemInfoInstant = function() return 1, "", "", "", 1, 2, 7 end }
C_FriendList = { SendWho = function() end, GetNumIgnores = const(0), GetNumFriends = const(3) }
C_QuestLog = { GetNumQuestLogEntries = function() return 5, 5 end, GetMaxNumQuestsCanAccept = const(25) }
C_UnitAuras = { GetPlayerAuraBySpellID = const(nil) }
C_Spell = { GetSpellName = function(id) return P.spells and P.spells[id] or ("Spell " .. tostring(id)) end }
C_SummonInfo = { ConfirmSummon = function() end }
AuraUtil = { FindAuraByName = const(nil) }

RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
DRUNK_MESSAGE_SELF1, DRUNK_MESSAGE_SELF2 = "You feel sober again.", "You feel tipsy. Whee!"
DRUNK_MESSAGE_SELF3, DRUNK_MESSAGE_SELF4 = "You feel drunk. Woah!", "You feel completely smashed."
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
LOOT_ITEM_SELF = "You receive loot: %s."
ERR_OUT_OF_RANGE, ERR_OUT_OF_RAGE = "Out of range.", "Not enough rage"
ERR_TRADE_COMPLETE, ERR_TRADE_CANCELLED = "Trade complete.", "Trade cancelled."
