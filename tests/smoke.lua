-- Smoke test: loads the addon against tests/stubs.lua and drives a few
-- signals end to end. Run with `node tests/run.js`.
local ns = ...
local failures = 0
local function check(cond, what)
    if cond then print("  ok    " .. what) else failures = failures + 1; print("  FAIL  " .. what) end
end
local function earned(id) return ns.char.earned[id] ~= nil end

T.event("ADDON_LOADED", "FiftyDKPMinus")
T.event("PLAYER_LOGIN")
T.event("PLAYER_ENTERING_WORLD", true, false)
T.advance(120)     -- past the "died within a minute of logging in" window

print("catalog")
local ids, n, badFlavor, noHint = {}, 0, {}, {}
for _, f in ipairs(ns.feats) do
    n = n + 1
    check(not ids[f.id], "unique id " .. f.id)
    ids[f.id] = true
    if f.flavor and #f.flavor >= 60 then badFlavor[#badFlavor + 1] = f.id end
    if not f.hidden and not f.hint then noHint[#noHint + 1] = f.id end
end
print("  feats: " .. n)
check(n >= 250, "at least 250 feats registered")
check(#badFlavor == 0, "flavor lines under 60 characters " .. table.concat(badFlavor, ","))
check(#noHint == 0, "every visible feat has a hint " .. table.concat(noHint, ","))
check(ns.char.balance == 0, "balance starts at zero")

print("death by falling")
P.falling = true
T.advance(2)
P.falling, P.dead = false, true
T.event("PLAYER_DEAD")
T.advance(1)
check(earned("gravity_works"), "Gravity Works awarded")
check(earned("first_offence"), "First Offence awarded (meta)")
check(earned("hardcore_would_have_ended_here"), "first death feat awarded")
check(ns.char.balance == -15, "balance is -15, got " .. ns.char.balance)
check(ns.char.log[1] ~= nil and #ns.char.log == 3, "three ledger lines")
P.dead = false

print("chat keyword and herald")
T.event("CHAT_MSG_GUILD", "more dots", "Tester-Realm", "", "", "", "", 0, 0, "", 0, 0, "Player-1-0001")
check(earned("more_dots"), "More Dots awarded")
check(earned("fifty_dkp_minus"), "50 DKP Minus awarded on first Standard fine")
check(earned("fun_detected"), "Fun Detected awarded (five feats in five minutes)")
check(ns.char.balance == -215, "balance is -215, got " .. ns.char.balance)
T.event("CHAT_MSG_GUILD", "more dots", "Someone-Realm", "", "", "", "", 0, 0, "", 0, 0, "Player-2-0002")
check(ns.char.c.more_dots == 1, "other players' chat is ignored")
T.advance(5)
local guildLines = 0
for _, m in ipairs(T.sent) do if m.channel == "GUILD" then guildLines = guildLines + 1; print("  > " .. m.msg) end end
check(guildLines == 1, "exactly one guild line inside the throttle window, got " .. guildLines)
check(T.sent[1] and T.sent[1].msg:find("earned 3 feats (-200 DKP)", 1, true), "burst collapses into a summary line")
check(not (T.sent[1] and T.sent[1].msg:find("http", 1, true)), "no URL in herald line")

print("anti-cheese")
for _ = 1, 30 do
    T.event("CHAT_MSG_GUILD", "more dots", "Tester-Realm", "", "", "", "", 0, 0, "", 0, 0, "Player-1-0001")
end
check(ns.char.c.more_dots <= 2, "keyword spam inside the cooldown does not count, got " .. ns.char.c.more_dots)

print("window feat")
for _ = 1, 10 do P.mounted = true; T.advance(2); P.mounted = false; T.advance(2) end
check(earned("mount_up_mount_down"), "Mount Up, Mount Down awarded")

print("system messages")
T.event("CHAT_MSG_SYSTEM", "Tester rolls 1 (1-100)")
check(earned("natural_1"), "Natural 1 awarded")
T.event("CHAT_MSG_SYSTEM", "Brakk has defeated Tester in a duel")
check(ns.char.c.duel_me_bro == 1, "duel loss counted")
T.event("CHAT_MSG_SYSTEM", "You feel completely smashed.")
check(earned("completely_smashed"), "Completely Smashed awarded")
T.event("UI_ERROR_MESSAGE", 1, "Out of range.")
check(ns.char.c.out_of_range == 1, "error message counted")
T.event("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 12 experience.")
check(ns.char.c.you_no_take_candle == 1, "kill by name counted")

print("secret values and class filters")
issecretvalue = function(v) return v == "SECRET" end
local before = ns.char.c.chatterbox
T.event("CHAT_MSG_PARTY", "SECRET", "SECRET", "", "", "", "", 0, 0, "", 0, 0, "SECRET")
check(ns.char.c.chatterbox == before, "secret chat is not read")
check(not earned("teechs_u_2_play") and ns.Engine.Eligible(ns.featById.teechs_u_2_play) == false, "class feats filtered")
check(ns.Engine.Eligible(ns.featById.out_of_mana) == false, "C-rated feats are off by default")

print("whisper commands")
local sentBefore = #T.sent
T.event("CHAT_MSG_WHISPER", "!dkp", "Stranger-Realm")
T.event("CHAT_MSG_WHISPER", "!dkp", "Stranger-Realm")
check(#T.sent == sentBefore + 1, "!dkp answered once per sender per minute")
print("  > " .. T.sent[#T.sent].msg)
check(T.sent[#T.sent].channel == "WHISPER", "reply is a whisper")

print("instance lockdown")
P.instance = { "Onyxia's Lair", "raid", 0, "", 40, 0, false, 249 }
T.event("PLAYER_ENTERING_WORLD", false, false)
local sent, addon = #T.sent, #T.addon
P.dead = true
T.event("PLAYER_DEAD")
T.advance(30)
check(earned("many_whelps"), "Many Whelps awarded in Onyxia's Lair")
check(#T.sent == sent and #T.addon == addon, "nothing is sent from inside an instance")
P.dead = false
P.instance = { "Kalimdor", "none", 0, "", 0, 0, false, 1 }
T.event("PLAYER_ENTERING_WORLD", false, false)
T.advance(120)
check(#T.sent == sent + 1, "queued herald flushes after leaving")
print("  > " .. T.sent[#T.sent].msg)

print("sync")
T.event("CHAT_MSG_ADDON", "DKPM", "BAL|-1240|-300|Liability|Mind the Gap", "GUILD", "Brakk-Realm")
check(ns.db.guild.Brakk and ns.db.guild.Brakk.total == -1240, "guildmate balance cached")
check(ns.Sync:Leaderboard()[1].name == "Brakk", "leaderboard sorts most in debt first")

print("ui")
ns.Ledger:Toggle()
check(ns.Ledger.frame ~= nil, "ledger builds")
for _, tab in ipairs({ "Offences", "Guild", "Settings", "Statement" }) do
    ns.Ledger.buttons[tab].scripts.OnClick()
end
check(true, "all tabs render")
SlashCmdList.FIFTYDKPMINUS("hint")
SlashCmdList.FIFTYDKPMINUS("quiet")
SlashCmdList.FIFTYDKPMINUS("last")
T.advance(3700)
check(ns.Rank(-3415) == "Raid Risk" and ns.Rank(0) == "Solvent", "rank titles")
check(ns.Comma(3415) == "3,415" and ns.FineText(-50) == "+50", "number formatting")

print(("balance %s, %d feats earned"):format(ns.BalanceText(ns.char.balance), ns.Engine.CountEarned()))
return failures
