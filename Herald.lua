-- Herald: one funny line in guild or party chat. Formatting, channel rules,
-- throttling, instance queue, merge logic, whisper replies.
--
-- Rules:
--   * one line per feat, never multi-line; no URLs, the tag is the only branding
--   * at most one line per 60 seconds per channel; extras collapse into a summary
--   * Petty fines stay private unless the user opts in
--   * nothing is sent from inside an instance; lines queue until you leave
--   * say / yell / public channels are never automatic: the client refuses addon
--     messages there unless a key press or click triggered them, so those go
--     through /minus last or a click on the toast
local _, ns = ...
local H = {}
ns.Herald = H

local THROTTLE, MERGE_HOLD = 60, 3
local queues = { GUILD = {}, GROUP = {} }
local lastSent = { GUILD = -THROTTLE, GROUP = -THROTTLE }
local flushScheduled = {}

local function SendChat(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return pcall(send, msg, channel, nil, target)
end

local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function DisplayName(f, tier, name)
    -- Tier-ups use the feat's base name plus a numeral, as in "Hogger's Resume III".
    if tier > 1 then return f.name .. " " .. ns.Roman(tier) end
    return name
end

function H.Line(item)
    local who = ns.playerName
    if item.others and #item.others > 0 then
        local n = #item.others
        if n == 1 then who = who .. " and " .. item.others[1]
        else who = ("%s, %s and %d other%s"):format(who, item.others[1], n - 1, n - 1 == 1 and "" or "s") end
        return ("%s %s: %s"):format(ns.TAG, who, item.label)
    end
    if math.abs(item.fine) >= 500 then
        return ("%s THAT'S A %s DKP MINUS. %s: %s"):format(ns.TAG, ns.Comma(item.fine), who, item.label)
    end
    local line = ("%s %s: %s (%s DKP)"):format(ns.TAG, who, item.label, ns.FineText(item.fine))
    if item.tier > 1 then line = line .. ". Balance: " .. ns.BalanceText(ns.char.balance) end
    return line
end

local function Flush(key)
    flushScheduled[key] = nil
    local q = queues[key]
    if #q == 0 then return end
    local channel = key == "GUILD" and (IsInGuild() and "GUILD" or nil) or GroupChannel()
    if not channel or ns.settings.quiet then wipe(q) return end

    local wait = THROTTLE - (GetTime() - lastSent[key])
    if ns.Sync.Locked() then wait = math.max(wait, 10) end      -- still in an instance: try again later
    if wait > 0 then
        flushScheduled[key] = true
        C_Timer.After(wait + 0.1, function() Flush(key) end)
        return
    end

    local line
    if #q == 1 then
        local item = q[1]
        -- Merge: if other users just announced the same feat, the first name
        -- alphabetically speaks for everyone and the rest stay quiet.
        local peers = ns.Sync.recentFeats[item.id]
        if key == "GUILD" and peers then
            local others = {}
            for name, at in pairs(peers) do
                if name ~= ns.playerName and math.abs(at - item.at) <= 10 then others[#others + 1] = name end
            end
            table.sort(others)
            if others[1] and others[1] < ns.playerName then wipe(q) return end
            item.others = others
        end
        line = H.Line(item)
    else
        local total = 0
        for i = 1, #q do total = total + q[i].fine end
        line = ("%s %s earned %d feats (%s DKP)"):format(ns.TAG, ns.playerName, #q, ns.FineText(total))
    end
    wipe(q)
    lastSent[key] = GetTime()
    SendChat(line, channel)
end

local function Enqueue(key, item)
    local q = queues[key]
    q[#q + 1] = item
    if not flushScheduled[key] then
        flushScheduled[key] = true
        C_Timer.After(MERGE_HOLD, function() Flush(key) end)
    end
end

function H:Announce(f, tier, name, fine, wasGrouped)
    H.latest = { id = f.id, tier = tier, fine = fine, label = DisplayName(f, tier, name), at = GetTime() }
    local s = ns.settings
    if s.quiet or f.herald == "self" then return end
    local size = math.abs(fine)
    if size < 50 and not s.pettyPublic then return end
    if size < s.minTier and not (size < 50 and s.pettyPublic) then return end
    local function item() return { id = f.id, tier = tier, fine = fine, label = H.latest.label, at = H.latest.at } end
    if s.heraldGuild and IsInGuild() then Enqueue("GUILD", item()) end
    if s.heraldParty and wasGrouped then Enqueue("GROUP", item()) end
end

---------------------------------------------------------------------------
-- Manual sharing. These run from a slash command or a button click, which is
-- a hardware event, so say/yell are allowed here and only here.
---------------------------------------------------------------------------
function H.Summary()
    local char = ns.char
    local latest = char.log[1] and (" Latest: " .. char.log[1].name .. ".") or ""
    return ("%s %s owes %s DKP (%s).%s"):format(ns.TAG, ns.playerName, ns.Comma(-math.min(char.balance, 0)), ns.Rank(char.balance), latest)
end

-- Finds the numeric id of the zone's General channel (name is "General - <zone>").
local function GeneralChannel()
    if not GetChannelName then return nil end
    for i = 1, 10 do
        local id, name = GetChannelName(i)
        if id and id > 0 and type(name) == "string" and name:lower():find("general", 1, true) then return id end
    end
end

local PUBLIC_GAP = 30       -- seconds between manual say / General lines
local lastPublic = -PUBLIC_GAP

-- Announces one ledger entry (default: the latest) to the chosen share channel.
-- Must be called from a key press or click: the client only lets addons send
-- to say and to numbered channels in response to a hardware event.
function H:Reannounce(entry)
    local e = entry or ns.char.log[1]
    if not e then ns.Print("Nothing to announce. Suspicious.") return end
    local choice = ns.settings.shareChannel
    local channel, target = choice, nil
    if choice == "PARTY" then
        channel = GroupChannel()
    elseif choice == "GENERAL" then
        channel, target = "CHANNEL", GeneralChannel()
        if not target then ns.Print("You are not in a General channel here.") return end
    end
    if not channel or (channel == "GUILD" and not IsInGuild()) then ns.Print("No channel to announce to.") return end
    if ns.Sync.Locked() then ns.Print("Chat is locked in here. Try again outside.") return end
    if choice == "SAY" or choice == "GENERAL" then
        local wait = PUBLIC_GAP - (GetTime() - lastPublic)
        if wait > 0 then ns.Print(("Easy. Public announcements are limited; try again in %d seconds."):format(math.ceil(wait))) return end
        lastPublic = GetTime()
    end
    SendChat(("%s %s: %s (%s DKP)"):format(ns.TAG, ns.playerName, e.name, ns.FineText(e.fine)), channel, target)
    ns:Fire("REANNOUNCE")
end

StaticPopupDialogs.FIFTYDKPMINUS_SHARE = {
    text = "%s",
    button1 = "Guild", button2 = "Cancel", button3 = "Party",
    OnAccept = function() if IsInGuild() then SendChat(H.Summary(), "GUILD") end end,
    OnAlt = function() local c = GroupChannel(); if c then SendChat(H.Summary(), c) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function H:SharePrompt()
    StaticPopup_Show("FIFTYDKPMINUS_SHARE", "Preview:\n" .. H.Summary() .. "\n\nSend to:")
end

---------------------------------------------------------------------------
-- Whisper commands for people without the addon: "!dkp" and "!shame".
---------------------------------------------------------------------------
local lastReply = {}
ns:On("CHAT_MSG_WHISPER", function(text, sender)
    if not ns.ready or not ns.settings.whisper or ns.settings.quiet then return end
    text, sender = ns.safe(text), ns.safe(sender)
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    local cmd = text:lower():match("^%s*(!%a+)%s*$")
    if cmd ~= "!dkp" and cmd ~= "!shame" then return end
    local now = GetTime()
    if lastReply[sender] and now - lastReply[sender] < 60 then return end
    lastReply[sender] = now
    if ns.Sync.Locked() then return end

    local char = ns.char
    local reply
    if cmd == "!dkp" then
        reply = H.Summary()
        ns:Fire("DKP_WHISPER")
    else
        local name, fine = ns.Engine.Rarest()
        reply = name and ("%s %s's rarest: %s (%s DKP)."):format(ns.TAG, ns.playerName, name, ns.FineText(fine))
            or ("%s %s has a clean sheet. For now."):format(ns.TAG, ns.playerName)
    end
    SendChat(reply, "WHISPER", sender)
end)

---------------------------------------------------------------------------
-- Weekly leaderboard line: the first user to log in after the Tuesday reset
-- announces last week's "winner", unless someone already did.
---------------------------------------------------------------------------
ns.logins[#ns.logins + 1] = function()
    if not ns.newWeek then return end
    local lastWeek = ns.WeekId() - 1
    C_Timer.After(45, function()
        local s = ns.settings
        if s.quiet or not s.heraldGuild or not IsInGuild() or ns.Sync.weekAnnounced[lastWeek] or ns.Sync.Locked() then return end
        local best, bestName = ns.char.lastWeekly or 0, ns.playerName
        for name, g in pairs(ns.db.guild) do
            if g.weekId == lastWeek and (g.weekly or 0) < best then best, bestName = g.weekly, name end
        end
        if best >= 0 then return end
        pcall(C_ChatInfo.SendAddonMessage, "DKPM", "WEEK|" .. lastWeek, "GUILD")
        ns.Sync.weekAnnounced[lastWeek] = true
        SendChat(("%s Most in debt this week: %s (%s). Handle it."):format(ns.TAG, bestName, ns.BalanceText(best)), "GUILD")
    end)
end
