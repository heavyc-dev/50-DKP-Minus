-- Chat signals: the player's own messages, emotes, and system-message parsing.
-- Other people's chat is never inspected, except whispers that are exactly a
-- "!dkp" / "!shame" request (handled in Herald.lua).
-- Signals: CHAT_SELF, EMOTE, ROLL, DUEL_LOST, DRUNK, SHUTDOWN, GKICKED
local _, ns = ...
local st = ns.state

local CHANNELS = {
    CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL", CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "GUILD",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY", CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_WHISPER_INFORM = "WHISPER", CHAT_MSG_CHANNEL = "CHANNEL",
}
local PUBLIC = { SAY = true, YELL = true, GENERAL = true, TRADE = true, CHANNEL = true }

local textMarks = {}     -- keyword -> mark name, registered by feat packs
function ns:RegisterTextMarks(t)
    for mark, keyword in pairs(t) do textMarks[keyword] = "SAID:" .. mark end
end

local lastText, repeatCount = nil, 0

local function OnOwnMessage(channel, raw, target)
    local text = raw:lower()
    local links = 0
    for _ in raw:gmatch("|Hitem:") do links = links + 1 end
    local letters = raw:gsub("|c.-|r", ""):gsub("[^%a]", "")
    local caps = #letters >= 10 and letters == letters:upper() and #raw >= 20

    if PUBLIC[channel] and text == lastText then repeatCount = repeatCount + 1
    else repeatCount = 1 end
    lastText = PUBLIC[channel] and text or nil

    if channel == "GUILD" then ns.char.guildSpoke = true end
    for keyword, mark in pairs(textMarks) do
        if text:find(keyword, 1, true) then ns:Mark(mark) end
    end

    ns:Fire("CHAT_SELF", {
        key = channel, channel = channel, text = text, len = #raw,
        public = PUBLIC[channel] or false,
        grouped = channel == "PARTY" or channel == "RAID",
        links = links, n = 1, caps = caps, repeats = repeatCount,
        toSelf = channel == "WHISPER" and target ~= nil and target == ns.playerName,
        thunderfury = raw:find("Thunderfury", 1, true) ~= nil and links > 0,
    })
    if links > 0 then ns:Fire("ITEM_LINK", { n = links }) end
end

local myGUID
local function Handler(event)
    return function(text, sender, _, _, target, _, _, _, channelName, _, _, guid)
        if not ns.ready then return end
        -- Inside instances chat arrives as Secret Values: bail before touching it.
        text, guid = ns.safe(text), ns.safe(guid)
        if type(text) ~= "string" then return end
        local channel = CHANNELS[event]
        if event == "CHAT_MSG_WHISPER_INFORM" then
            local name = ns.safe(sender)
            target = type(name) == "string" and name:match("^[^-]+") or nil
        else
            myGUID = myGUID or UnitGUID("player")
            if not guid or guid ~= myGUID then return end
            if event == "CHAT_MSG_CHANNEL" then
                local base = (ns.safe(channelName) or ""):lower()
                if base:find("general", 1, true) then channel = "GENERAL"
                elseif base:find("trade", 1, true) then channel = "TRADE" end
            end
        end
        OnOwnMessage(channel, text, target)
    end
end
for event in pairs(CHANNELS) do ns:On(event, Handler(event)) end

---------------------------------------------------------------------------
-- Emotes
---------------------------------------------------------------------------
local function OnEmote(token)
    if not ns.ready or type(token) ~= "string" then return end
    token = token:upper()
    local targetName = ns.try(UnitName, "target")
    ns:Fire("EMOTE", {
        key = token, emote = token,
        target = type(targetName) == "string" and targetName:lower() or nil,
        targetPlayer = UnitExists("target") and ns.try(UnitIsPlayer, "target") and not UnitIsUnit("target", "player") or false,
        sunrise = (function()
            local h = GetGameTime()
            return h == 5 or h == 6
        end)(),
    })
end
if not ns.Hook("DoEmote", OnEmote) and C_ChatInfo then
    ns.Hook(C_ChatInfo, "PerformEmote", OnEmote)
end

---------------------------------------------------------------------------
-- System messages (rolls, duels, drunkenness, shutdowns, guild removal)
---------------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    -- Swap placeholders for control characters, escape the rest, swap back.
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

local ROLL = ToPattern(_G.RANDOM_ROLL_RESULT)                -- "%s rolls %d (%d-%d)"
local DUEL = ToPattern(_G.DUEL_WINNER_KNOCKOUT)              -- "%1$s has defeated %2$s in a duel"
local KICK = ToPattern(_G.ERR_GUILD_REMOVE_SS)               -- "%s has been kicked out of the guild by %s."
local DRUNK = {}
for i = 1, 4 do
    local s = _G["DRUNK_MESSAGE_SELF" .. i]
    if s then DRUNK[s] = i end
end

ns:On("CHAT_MSG_SYSTEM", function(msg)
    if not ns.ready then return end
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local me = ns.playerName

    if DRUNK[msg] then
        st.drunk = DRUNK[msg]      -- 1 = sober again ... 4 = completely smashed
        ns:Fire("DRUNK", { drunkLevel = DRUNK[msg] })
        return
    end
    if ROLL then
        local who, roll, lo, hi = msg:match(ROLL)
        if who == me then
            ns:Fire("ROLL", { roll = tonumber(roll), low = tonumber(lo), high = tonumber(hi), solo = not st.grouped })
            return
        end
    end
    if DUEL then
        local _, loser = msg:match(DUEL)
        if loser == me then ns:Fire("DUEL_LOST") return end
    end
    if KICK then
        local kicked = msg:match(KICK)
        if kicked == me then ns:Fire("GKICKED") return end
    end
    local lower = msg:lower()
    if lower:find("shutdown in", 1, true) or lower:find("restart in", 1, true) then
        ns:Fire("SHUTDOWN")
    end
end)
