-- Map IDs, zone names and coordinate boxes for place-based feats.
-- Zones match by uiMapID *or* by English zone name, because Forever's map IDs
-- are not yet verified in game. Names are compared lower-case.
local _, ns = ...
local Z = {}
ns.Zones = Z

Z.zones = {
    BARRENS        = { ids = { 1413 }, names = { "the barrens", "northern barrens", "southern barrens" } },
    STRANGLETHORN  = { ids = { 1434 }, names = { "stranglethorn vale", "northern stranglethorn", "the cape of stranglethorn" } },
    THOUSAND_NEEDLES = { ids = { 1441 }, names = { "thousand needles" } },
    UNGORO         = { ids = { 1449 }, names = { "un'goro crater" } },
    WETLANDS       = { ids = { 1437 }, names = { "wetlands" } },
    ELWYNN         = { ids = { 1429 }, names = { "elwynn forest" }, start = true },
    DUN_MOROGH     = { ids = { 1426 }, names = { "dun morogh" }, start = true },
    TELDRASSIL     = { ids = { 1438 }, names = { "teldrassil" }, start = true },
    DUROTAR        = { ids = { 1411 }, names = { "durotar" }, start = true },
    MULGORE        = { ids = { 1412 }, names = { "mulgore" }, start = true },
    TIRISFAL       = { ids = { 1420 }, names = { "tirisfal glades" }, start = true },
    RIVERGLADES    = { ids = {}, names = { "riverglades", "the riverglades" } },
    ZEPHRAS        = { ids = {}, names = { "zephras isle" } },
    ORGRIMMAR      = { ids = { 1454 }, names = { "orgrimmar" }, capital = "Horde" },
    THUNDER_BLUFF  = { ids = { 1456 }, names = { "thunder bluff" }, capital = "Horde" },
    UNDERCITY      = { ids = { 1458 }, names = { "undercity" }, capital = "Horde" },
    STORMWIND      = { ids = { 1453 }, names = { "stormwind city", "stormwind" }, capital = "Alliance" },
    IRONFORGE      = { ids = { 1455 }, names = { "ironforge" }, capital = "Alliance" },
    DARNASSUS      = { ids = { 1457 }, names = { "darnassus" }, capital = "Alliance" },
}

-- Instances match by instance map ID (8th return of GetInstanceInfo) or name.
Z.instances = {
    ONYXIA      = { ids = { 249 }, names = { "onyxia's lair" } },
    MOLTEN_CORE = { ids = { 409 }, names = { "molten core" } },
    BRS         = { ids = { 229 }, names = { "blackrock spire", "lower blackrock spire", "upper blackrock spire" } },
    BRD         = { ids = { 230 }, names = { "blackrock depths" } },
    GNOMEREGAN  = { ids = { 90 },  names = { "gnomeregan" } },
    WAILING     = { ids = { 43 },  names = { "wailing caverns" } },
    TRAM        = { ids = { 369 }, names = { "deeprun tram" } },
}

-- Boxes: a zone plus an optional coordinate rectangle (0-1 map units) and/or
-- a subzone list. Coordinates are rough and need tuning in game.
Z.boxes = {
    UC_ELEVATORS = { zone = "UNDERCITY" },
    UC_RUINS     = { zone = "TIRISFAL", subzones = { "ruins of lordaeron" } },
    TB_LIFTS     = { zone = "THUNDER_BLUFF" },
    TB_BASE      = { zone = "MULGORE", x1 = 0.30, y1 = 0.15, x2 = 0.48, y2 = 0.40 },
    MENETHIL     = { zone = "WETLANDS", subzones = { "menethil harbor" } },
    BOOTY_BAY    = { zone = "STRANGLETHORN", subzones = { "booty bay" } },
    LIONS_PRIDE  = { zone = "ELWYNN", subzones = { "lion's pride inn" } },
    STARTING_VILLAGES = { subzones = {
        "northshire valley", "northshire abbey", "coldridge valley", "anvilmar", "shadowglen",
        "aldrassil", "valley of trials", "camp narache", "red cloud mesa", "deathknell",
    } },
    ZEPPELIN_TOWERS = { subzones = { "zeppelin tower", "orgrimmar zeppelin tower", "grom'gol base camp", "brill" } },
    DOCKS = { subzones = { "menethil harbor", "ratchet", "booty bay", "auberdine", "theramore isle", "rut'theran village" } },
    MINES = { subzones = {
        "fargodeep mine", "jasperlode mine", "echo ridge mine", "gol'bolar quarry", "jangolode mine",
        "gold coast quarry", "the deadmines", "venture co. mine", "burning blade coven", "skull rock",
    } },
}

local lowerNames = {}   -- zone name -> key
local idToKey = {}
for key, z in pairs(Z.zones) do
    for _, n in ipairs(z.names) do lowerNames[n] = key end
    for _, id in ipairs(z.ids) do idToKey[id] = key end
end

-- Recomputes ns.state zone fields. Called on zone changes and at login.
function Z:Refresh()
    local st = ns.state
    local keys = {}
    local zoneText = ns.safe(GetRealZoneText()) or ""
    local sub = ns.safe(GetSubZoneText()) or ""
    st.zoneText, st.subzone = zoneText, sub:lower()

    local key = lowerNames[zoneText:lower()]
    if key then keys[key] = true end

    local mapID = C_Map and ns.try(C_Map.GetBestMapForUnit, "player")
    st.mapID = mapID
    local guard = 0
    while mapID and guard < 6 do
        if idToKey[mapID] then keys[idToKey[mapID]] = true end
        local info = ns.try(C_Map.GetMapInfo, mapID)
        mapID = type(info) == "table" and info.parentMapID or nil
        guard = guard + 1
    end

    st.zones = keys
    st.capital, st.startZone = nil, false
    for k in pairs(keys) do
        local z = Z.zones[k]
        if z.capital then st.capital = z.capital end
        if z.start then st.startZone = true end
    end
    st.enemyCapital = st.capital ~= nil and st.faction ~= nil and st.capital ~= st.faction

    local name, instType, _, _, _, _, _, instID = GetInstanceInfo()
    name, instType, instID = ns.safe(name), ns.safe(instType), ns.safe(instID)
    st.inInstance = instType ~= nil and instType ~= "none"
    st.instanceType = instType
    st.instanceName = name
    st.continent = (not st.inInstance) and instID or st.continent
    st.inst = nil
    if st.inInstance or instID == 369 then
        local lname = (name or ""):lower()
        for k, inst in pairs(Z.instances) do
            for _, id in ipairs(inst.ids) do if id == instID then st.inst = k end end
            for _, n in ipairs(inst.names) do if n == lname then st.inst = k end end
        end
        st.inst = st.inst or "OTHER"
    end
    st.outdoors = not st.inInstance
end

-- Player position on the current zone map, or nil (always nil inside instances).
function Z:Position()
    local mapID = ns.state.mapID
    if not mapID or not C_Map or not C_Map.GetPlayerMapPosition then return nil end
    local pos = ns.try(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos or not pos.GetXY then return nil end
    local x, y = pos:GetXY()
    x, y = ns.safe(x), ns.safe(y)
    if not x or (x == 0 and y == 0) then return nil end
    return x, y
end

function Z:InBox(name)
    local box = Z.boxes[name]
    if not box then return false end
    local st = ns.state
    if box.zone and not (st.zones and st.zones[box.zone]) then return false end
    if box.subzones then
        local hit = false
        for i = 1, #box.subzones do
            if box.subzones[i] == st.subzone then hit = true break end
        end
        if not hit then return false end
    end
    if box.x1 then
        local x, y = Z:Position()
        if not x or x < box.x1 or x > box.x2 or y < box.y1 or y > box.y2 then return false end
    end
    return true
end
