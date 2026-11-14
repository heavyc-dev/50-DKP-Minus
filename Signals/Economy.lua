-- Economy signals: vendors, repairs, money, mail, auction house, bank, trade, bags, loot.
-- Signals: VENDOR_CLOSE, BUYBACK, VENDOR_SELL, DESTROY, REPAIR, REPAIR_BROKE,
--          MONEY, MAIL_OPEN, MAIL_CLOSE, TRADE_CANCEL, TRADE_DONE, BAGS, LOOT,
--          LOOT_ROLL, BANK_SLOT
local _, ns = ...
local st = ns.state

local function ItemQuality(link)
    if not link or not C_Item or not C_Item.GetItemInfo then return nil end
    local _, _, quality = ns.try(C_Item.GetItemInfo, link)
    return quality
end

---------------------------------------------------------------------------
-- Vendors and repairs
---------------------------------------------------------------------------
local bought, repairCost = false, 0

ns:On("MERCHANT_SHOW", function()
    if not ns.ready then return end
    bought = false
    st.MERCHANT_open = true
    repairCost = 0
    if CanMerchantRepair and CanMerchantRepair() then
        repairCost = GetRepairAllCost() or 0
        if repairCost > 0 and repairCost > GetMoney() then ns:Fire("REPAIR_BROKE") end
    end
end)
ns:On("MERCHANT_CLOSED", function()
    if not ns.ready or not st.MERCHANT_open then return end
    st.MERCHANT_open = false
    ns:Fire("VENDOR_CLOSE", { bought = bought })
end)
ns.Hook("BuyMerchantItem", function() bought = true end)
ns.Hook("BuybackItem", function() if ns.ready then ns:Fire("BUYBACK") end end)
ns.Hook("RepairAllItems", function()
    if not ns.ready or repairCost <= 0 then return end
    ns:Fire("REPAIR", { gold = repairCost / 10000 })
    repairCost = 0
end)

-- Selling: right-clicking a bag item while a vendor is open.
if C_Container then
    ns.Hook(C_Container, "UseContainerItem", function(bag, slot)
        if not ns.ready or not st.MERCHANT_open then return end
        -- The sale is confirmed by the server later, so the item is still readable here.
        local link = ns.try(C_Container.GetContainerItemLink, bag, slot)
        local quality = ItemQuality(link)
        if quality then ns:Fire("VENDOR_SELL", { quality = quality }) end
    end)
end

-- Remember the quality of whatever was last picked up or locked, so sell and
-- destroy hooks (which run after the item is gone) know what it was.
ns:On("ITEM_LOCK_CHANGED", function(bag, slot)
    if not slot or not C_Container or not C_Container.GetContainerItemLink then return end
    local link = ns.try(C_Container.GetContainerItemLink, bag, slot)
    if link then st.lastLockedQuality = ItemQuality(link) end
end)

ns.Hook("DeleteCursorItem", function()
    if not ns.ready then return end
    ns:Fire("DESTROY", { quality = st.lastLockedQuality or 0 })
    st.lastLockedQuality = nil
end)

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
local function Money()
    if not ns.ready then return end
    local copper = GetMoney()
    ns:Fire("MONEY", { copper = copper, tail = copper % 10000 })
end
ns:On("PLAYER_MONEY", Money)
ns.logins[#ns.logins + 1] = function() C_Timer.After(15, Money) end

---------------------------------------------------------------------------
-- Mail, auction house, bank
---------------------------------------------------------------------------
ns:On("MAIL_SHOW", function()
    if not ns.ready then return end
    st.mailOpen = true
    C_Timer.After(1.5, function()
        if not st.mailOpen then return end
        local n = GetInboxNumItems and GetInboxNumItems() or 0
        ns:Fire("MAIL_OPEN", { empty = n == 0 })
    end)
end)
ns:On("MAIL_CLOSED", function()
    if not ns.ready or not st.mailOpen then return end
    st.mailOpen = false
    ns:Fire("MAIL_CLOSE")
end)

ns:On("AUCTION_HOUSE_SHOW", function() st.ahOpen = true end)
ns:On("AUCTION_HOUSE_CLOSED", function() st.ahOpen = false end)
ns:On("BANKFRAME_OPENED", function() st.bankOpen = true end)
ns:On("BANKFRAME_CLOSED", function() st.bankOpen = false end)
ns:On("PLAYER_BANKBAGSLOTS_CHANGED", function() if ns.ready then ns:Fire("BANK_SLOT") end end)

---------------------------------------------------------------------------
-- Trade
---------------------------------------------------------------------------
local tradeOpen, gaveGold, gotAnything, gaveItem = false, false, false, false

local function TradeSnapshot()
    if not tradeOpen then return end
    local mine = tonumber(GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
    local theirs = tonumber(GetTargetTradeMoney and GetTargetTradeMoney()) or 0
    gaveGold = mine > 0
    gaveItem, gotAnything = false, theirs > 0
    for i = 1, 6 do
        if GetTradePlayerItemInfo and GetTradePlayerItemInfo(i) then gaveItem = true end
        if GetTradeTargetItemInfo and GetTradeTargetItemInfo(i) then gotAnything = true end
    end
end
ns:On("TRADE_SHOW", function() tradeOpen, gaveGold, gotAnything, gaveItem = true, false, false, false end)
ns:On("TRADE_ACCEPT_UPDATE", TradeSnapshot)
ns:On("TRADE_MONEY_CHANGED", TradeSnapshot)
ns:On("UI_INFO_MESSAGE", function(_, msg)
    if not ns.ready or not tradeOpen then return end
    msg = ns.safe(msg)
    if msg == ERR_TRADE_COMPLETE then
        tradeOpen = false
        ns:Fire("TRADE_DONE", {
            gaveGoldOnly = gaveGold and not gotAnything,
            gaveItemOnly = gaveItem and not gotAnything,
        })
    elseif msg == ERR_TRADE_CANCELLED then
        tradeOpen = false
        ns:Fire("TRADE_CANCEL")
    end
end)
ns:On("TRADE_CLOSED", function()
    -- Fires before the completion message; give that a moment to arrive.
    C_Timer.After(0.5, function() tradeOpen = false end)
end)

---------------------------------------------------------------------------
-- Bags: scanned at most once every few seconds, never in combat.
---------------------------------------------------------------------------
local LINEN, scanQueued = 2589, false
local LOCKBOX = { [4632] = true, [4633] = true, [4634] = true, [4636] = true, [4637] = true, [4638] = true,
    [5758] = true, [5759] = true, [5760] = true, [16882] = true, [16883] = true, [16884] = true, [16885] = true }

local function ScanBags()
    scanQueued = false
    if not ns.ready or not C_Container or not C_Container.GetContainerNumSlots then return end
    local greys, linen, free, total, lockbox = 0, 0, 0, 0, false
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        total = total + slots
        for slot = 1, slots do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" then
                if info.quality == 0 then greys = greys + 1 end
                if info.itemID == LINEN then linen = linen + (info.stackCount or 1) end
                if LOCKBOX[info.itemID] then lockbox = true end
            else
                free = free + 1
            end
        end
    end
    local char = ns.char
    st.bagsFull = total > 0 and free == 0
    if lockbox then char.lockboxSince = char.lockboxSince or time() else char.lockboxSince = nil end
    ns:Fire("BAGS", {
        greys = greys, linen = linen, bagsFull = st.bagsFull,
        lockboxDays = char.lockboxSince and (time() - char.lockboxSince) / 86400 or 0,
    })
end
ns:On("BAG_UPDATE_DELAYED", function()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(3, ScanBags)
end)

---------------------------------------------------------------------------
-- Loot and rolls
---------------------------------------------------------------------------
local LOOT_SELF = _G.LOOT_ITEM_SELF and _G.LOOT_ITEM_SELF:gsub("%%s", "(.+)"):gsub("%.$", "") or nil
ns:On("CHAT_MSG_LOOT", function(msg)
    if not ns.ready or not LOOT_SELF then return end
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local link = msg:match(LOOT_SELF)
    if not link then return end
    local id = tonumber(link:match("|Hitem:(%d+)"))
    if id then ns:Fire("LOOT", { key = id, itemID = id, quality = ItemQuality(link) }) end
end)

local RANGED = { [2] = true, [3] = true, [16] = true, [18] = true, [19] = true, [20] = true }
ns.Hook("RollOnLoot", function(rollID, rollType)
    if not ns.ready then return end
    local melee = false
    local link = ns.try(GetLootRollItemLink, rollID)
    if link and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
        melee = ok and classID == 2 and not RANGED[subClassID]
    end
    ns:Fire("LOOT_ROLL", { need = rollType == 1, meleeWeapon = melee })
end)
