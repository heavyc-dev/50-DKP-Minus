-- Quest and NPC-dialog signals.
-- Signals: QUEST_ACCEPT, QUEST_ABANDON, QUEST_TURNIN, QUEST_DIALOG_CLOSE,
--          QUEST_LOG, NPC_TALK, NPC_DIALOG_CLOSE
local _, ns = ...
local st = ns.state

local detailAt, dialogNpc
local acceptedAt = {}     -- questID -> GetTime()
local turnedIn = {}       -- questID -> true, so QUEST_REMOVED is not read as an abandon

local function NpcName()
    local name = ns.try(UnitName, "npc")
    return type(name) == "string" and name:lower() or nil
end

ns:On("QUEST_DETAIL", function()
    detailAt, dialogNpc = GetTime(), NpcName()
end)
ns:On("QUEST_FINISHED", function()
    if not ns.ready or not detailAt then return end
    ns:Fire("QUEST_DIALOG_CLOSE", { duration = GetTime() - detailAt })
    detailAt = nil
end)

local function LogFull()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return false end
    local _, quests = C_QuestLog.GetNumQuestLogEntries()
    local max = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 25
    return (quests or 0) >= max
end

ns:On("QUEST_ACCEPTED", function(a, b)
    if not ns.ready then return end
    local questID = b or a      -- (questLogIndex, questID) on older clients, (questID) on newer
    acceptedAt[questID] = GetTime()
    ns:Fire("QUEST_ACCEPT", {
        key = dialogNpc,
        dialogAge = detailAt and (GetTime() - detailAt) or 999,
    })
    if LogFull() then ns:Fire("QUEST_LOG", { logFull = true }) end
end)

ns:On("QUEST_TURNED_IN", function(questID, xp, money)
    if not ns.ready then return end
    turnedIn[questID] = true
    local trivial = C_QuestLog and C_QuestLog.IsQuestTrivial and ns.try(C_QuestLog.IsQuestTrivial, questID) or false
    ns:Fire("QUEST_TURNIN", {
        noReward = (ns.safe(money) or 0) == 0 and (GetNumQuestRewards and GetNumQuestRewards() or 0) == 0
            and (GetNumQuestChoices and GetNumQuestChoices() or 0) == 0,
        trivial = trivial and true or false,
    })
end)

ns:On("QUEST_REMOVED", function(questID)
    if not ns.ready then return end
    local at = acceptedAt[questID]
    acceptedAt[questID] = nil
    -- QUEST_TURNED_IN can arrive just after; decide a moment later.
    C_Timer.After(1, function()
        if turnedIn[questID] then turnedIn[questID] = nil return end
        ns:Fire("QUEST_ABANDON", { age = at and (GetTime() - at) or 999 })
    end)
end)

-- Gossip windows
local gossipAt
ns:On("GOSSIP_SHOW", function()
    if not ns.ready then return end
    gossipAt = GetTime()
    st.npcDialog = true
    ns:Fire("NPC_TALK", { key = NpcName() or "?" })
end)
ns:On("GOSSIP_CLOSED", function()
    if not ns.ready or not gossipAt then return end
    st.npcDialog = false
    ns:Fire("NPC_DIALOG_CLOSE", { duration = GetTime() - gossipAt })
    gossipAt = nil
end)
