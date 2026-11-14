-- Social signals: groups, ready checks, guild, AFK, levelling, kills by name, targets.
-- Signals: GROUP_JOIN, GROUP_LEAVE, READY_CHECK, READY_ANSWER, READY_TIMEOUT,
--          COMBAT_START, GUILD_JOIN, GUILD_LEAVE, GUILD_DAY, IGNORES, WHO, SUMMON_ACCEPT,
--          AFK_START, LEVEL_UP, KILL, TARGET, TRAINER_VISIT, FRIENDLESS
local _, ns = ...
local st = ns.state

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local inGroup, groupJoinedAt, groupZone = false, nil, nil
ns:On("GROUP_ROSTER_UPDATE", function()
    if not ns.ready then return end
    local now = IsInGroup() and true or false
    if now and IsInRaid() and not st.inInstance and GetNumGroupMembers() >= 40 then
        ns:Fire("RAID_FULL")
    end
    if now == inGroup then return end
    inGroup = now
    if now then
        groupJoinedAt, groupZone = GetTime(), st.zoneText
        ns:Fire("GROUP_JOIN")
    else
        ns:Fire("GROUP_LEAVE", {
            duration = groupJoinedAt and (GetTime() - groupJoinedAt) or 999,
            midDungeon = st.inInstance and st.instanceType == "party",
        })
        groupJoinedAt = nil
    end
end)
ns.logins[#ns.logins + 1] = function() inGroup = IsInGroup() and true or false end

-- "Late": still in the zone you were in 15 minutes after joining.
ns.tickers[#ns.tickers + 1] = function(now)
    if groupJoinedAt and groupZone and now - groupJoinedAt > 900 then
        if st.zoneText == groupZone and not st.inInstance then ns:Fire("GROUP_LATE") end
        groupZone = nil
    end
end

local readyAnswered = true
ns:On("READY_CHECK", function(initiator)
    if not ns.ready then return end
    local who = ns.safe(initiator)
    local mine = type(who) == "string" and who:match("^[^-]+") == ns.playerName
    readyAnswered = mine
    ns:Fire("READY_CHECK", { mine = mine })
end)
ns:On("READY_CHECK_CONFIRM", function(unit, ready)
    if not ns.ready then return end
    unit = ns.safe(unit)
    if not unit or not UnitIsUnit(unit, "player") then return end
    readyAnswered = true
    ns:Fire("READY_ANSWER", { isReady = ns.safe(ready) and true or false })
end)
ns:On("READY_CHECK_FINISHED", function()
    if not ns.ready then return end
    if not readyAnswered then ns:Fire("READY_TIMEOUT") end
    readyAnswered = true
end)

ns:On("PLAYER_REGEN_DISABLED", function()
    if not ns.ready then return end
    ns:Fire("COMBAT_START", { unarmed = GetInventoryItemID("player", 16) == nil })
end)

ns:On("CONFIRM_SUMMON", function() st.summonPending = true end)
if C_SummonInfo then
    ns.Hook(C_SummonInfo, "ConfirmSummon", function()
        if ns.ready and st.summonPending then ns:Fire("SUMMON_ACCEPT") end
        st.summonPending = false
    end)
end

---------------------------------------------------------------------------
-- Guild
---------------------------------------------------------------------------
local function GuildName() return ns.safe((GetGuildInfo("player"))) end

local function GuildCheck()
    if not ns.ready then return end
    local char = ns.char
    local name = IsInGuild() and GuildName() or nil
    if IsInGuild() and not name then return end      -- roster not loaded yet
    if name == char.guild then return end
    local old = char.guild
    char.guild = name
    if name then
        char.guildsJoined = (char.guildsJoined or 0) + 1
        char.guildSince, char.guildSpoke = time(), false
        ns:Fire("GUILD_JOIN", {
            guildsJoined = char.guildsJoined,
            rejoined = char.lastGuild == name and char.lastGuildLeft ~= nil and time() - char.lastGuildLeft < 86400,
        })
    elseif old then
        char.lastGuild, char.lastGuildLeft = old, time()
        ns:Fire("GUILD_LEAVE")
    end
end
ns:On("PLAYER_GUILD_UPDATE", function() C_Timer.After(2, GuildCheck) end)
ns.logins[#ns.logins + 1] = function()
    C_Timer.After(10, function()
        local char = ns.char
        if char.guild == nil and IsInGuild() then
            -- First sight of an existing guild: not a "join".
            char.guild = GuildName()
            char.guildSince = char.guildSince or time()
        else
            GuildCheck()
        end
        if char.guild and char.guildSince then
            ns:Fire("GUILD_DAY", {
                silentDays = char.guildSpoke and 0 or (time() - char.guildSince) / 86400,
            })
        end
        local friends = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 1
        if friends == 0 and not IsInGuild() then ns:Fire("FRIENDLESS") end
    end)
end

if C_FriendList then
    ns.Hook(C_FriendList, "SendWho", function() if ns.ready then ns:Fire("WHO") end end)
    ns:On("IGNORELIST_UPDATE", function()
        if not ns.ready or not C_FriendList.GetNumIgnores then return end
        ns:Fire("IGNORES", { ignores = C_FriendList.GetNumIgnores() })
    end)
end

---------------------------------------------------------------------------
-- AFK
---------------------------------------------------------------------------
local wasAFK = false
ns:On("PLAYER_FLAGS_CHANGED", function(unit)
    if ns.safe(unit) ~= "player" or not ns.ready then return end
    local afk = UnitIsAFK("player") and true or false
    if afk == wasAFK then return end
    wasAFK = afk
    st.afkSince = afk and GetTime() or nil
    if afk then ns:Fire("AFK_START") end
end)

---------------------------------------------------------------------------
-- Levelling, trainers
---------------------------------------------------------------------------
ns:On("TRAINER_SHOW", function()
    if not ns.ready then return end
    ns.char.levelsSinceTrainer = 0
    ns:Fire("TRAINER_VISIT")
end)

ns:On("PLAYER_LEVEL_UP", function(level)
    if not ns.ready then return end
    local char = ns.char
    level = ns.safe(level) or UnitLevel("player")
    st.level = level
    char.levelsSinceTrainer = (char.levelsSinceTrainer or 0) + 1
    local unspent = (GetUnspentTalentPoints and ns.try(GetUnspentTalentPoints)) or
        (UnitCharacterPoints and ns.try(UnitCharacterPoints, "player")) or 0
    if unspent > 0 then char.unspentLevels = (char.unspentLevels or 0) + 1 else char.unspentLevels = 0 end
    ns:Fire("LEVEL_UP", {
        newLevel = level, guildless = not IsInGuild(),
        levelsSinceTrainer = char.levelsSinceTrainer,
        unspentLevels = char.unspentLevels,
        copper = GetMoney(),
    })
end)

---------------------------------------------------------------------------
-- Kills by name, from the XP-gain chat line (never the combat log).
---------------------------------------------------------------------------
local XP_KILL = _G.COMBATLOG_XPGAIN_FIRSTPERSON      -- "%s dies, you gain %d experience."
local xpPattern = XP_KILL and ("^" .. XP_KILL:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d.*$", "")) or nil
ns:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    if not ns.ready or not xpPattern then return end
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local mob = msg:match(xpPattern)
    if mob then ns:Fire("KILL", { key = mob:lower(), mob = mob:lower() }) end
end)

---------------------------------------------------------------------------
-- Targets (names are Secret inside instances; outdoors only)
---------------------------------------------------------------------------
ns:On("PLAYER_TARGET_CHANGED", function()
    if not ns.ready or st.inInstance or not UnitExists("target") then return end
    local name = ns.try(UnitName, "target")
    if type(name) ~= "string" then return end
    ns:Fire("TARGET", { key = name:lower(), target = name:lower(), afkTarget = ns.try(UnitIsAFK, "target") and true or false })
end)
