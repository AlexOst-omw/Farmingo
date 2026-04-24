local ADDON_NAME, ns = ...

local Places = {}

local DungeonNameAliases = {
    ["Deadmines"] = "The Deadmines",
}

local PlaceAliases = {
    ["The Deadmines"] = {
        placeType = "dungeon",
        placeName = "The Deadmines",
        worldName = "Dungeons",
        continentName = "Dungeons",
    },
    ["New Tinkertown"] = {
        placeType = "zone",
        placeName = "Dun Morogh",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Scarlet Monastery Entrance"] = {
        placeType = "dungeon",
        placeName = "Scarlet Monastery",
        worldName = "Dungeons",
        continentName = "Dungeons",
    },
    ["The Master's Cellar"] = {
        placeType = "zone",
        placeName = "Deadwind Pass",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Blackrock Mountain"] = {
        placeType = "zone",
        placeName = "Blackrock Mountain",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Stranglethorn Vale"] = {
        placeType = "zone",
        placeName = "Stranglethorn Vale",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Northern Stranglethorn"] = {
        placeType = "zone",
        placeName = "Stranglethorn Vale - Northern",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["The Cape of Stranglethorn"] = {
        placeType = "zone",
        placeName = "Stranglethorn Vale - Cape",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Uldaman"] = {
        placeType = "dungeon",
        placeName = "Uldaman",
        worldName = "Dungeons",
        continentName = "Dungeons",
    },
    ["Wailing Caverns"] = {
        placeType = "dungeon",
        placeName = "Wailing Caverns",
        worldName = "Dungeons",
        continentName = "Dungeons",
    },
    ["Maraudon"] = {
        placeType = "dungeon",
        placeName = "Maraudon",
        worldName = "Dungeons",
        continentName = "Dungeons",
    },
    ["Dustwind Cave"] = {
        placeType = "zone",
        placeName = "Durotar - Dustwind Cave",
        worldName = "Azeroth",
        continentName = "Kalimdor",
    },
    ["Echo Isles"] = {
        placeType = "zone",
        placeName = "Durotar - Echo Isles",
        worldName = "Azeroth",
        continentName = "Kalimdor",
    },
    ["Valley of Trials"] = {
        placeType = "zone",
        placeName = "Durotar - Valley of Trials",
        worldName = "Azeroth",
        continentName = "Kalimdor",
    },
    ["Jasperlode Mine"] = {
        placeType = "zone",
        placeName = "Elwynn Forest - Jasperlode Mine",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
    ["Northshire"] = {
        placeType = "zone",
        placeName = "Elwynn Forest - Northshire",
        worldName = "Azeroth",
        continentName = "Eastern Kingdoms",
    },
}

local CosmicContinentWorldOverrides = {
    ["Quel'Thalas"] = "Azeroth",
}

local function NormalizeWorldName(continentName, rawWorldName)
    if continentName == "Kalimdor"
        or continentName == "Eastern Kingdoms"
        or continentName == "Northrend"
        or continentName == "Pandaria"
        or continentName == "Broken Isles"
        or continentName == "Kul Tiras"
        or continentName == "Zandalar"
        or continentName == "Dragon Isles"
        or continentName == "Khaz Algar" then
        return "Azeroth"
    end

    if continentName == "Outland" then
        return "Outland"
    end

    if continentName == "Draenor" then
        return "Draenor"
    end

    if continentName == "Shadowlands" then
        return "Shadowlands"
    end

    if rawWorldName == "Cosmic" then
        if continentName and CosmicContinentWorldOverrides[continentName] then
            return CosmicContinentWorldOverrides[continentName]
        end

        if continentName and continentName ~= "" and continentName ~= "Unknown Continent" then
            return continentName
        end
    end

    return rawWorldName or "Unknown World"
end

local function GetZoneHierarchy()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return "Unknown World", "Unknown Continent", "Unknown Zone", nil, {}
    end

    local chain = {}
    local visited = {}
    local currentID = mapID

    while currentID and not visited[currentID] and currentID ~= 0 do
        visited[currentID] = true

        local info = C_Map.GetMapInfo(currentID)
        if not info then
            break
        end

        table.insert(chain, {
            mapID = currentID,
            name = info.name or ("Map " .. tostring(currentID)),
            mapType = info.mapType,
            parentMapID = info.parentMapID,
        })

        currentID = info.parentMapID
    end

    local zoneName = "Unknown Zone"
    local continentName = "Unknown Continent"
    local worldName = "Unknown World"

    if #chain >= 1 then
        zoneName = chain[1].name or zoneName
    end

    if #chain >= 2 then
        continentName = chain[2].name or continentName
    end

    if #chain >= 1 then
        worldName = chain[#chain].name or worldName
    end

    worldName = NormalizeWorldName(continentName, worldName)

    return worldName, continentName, zoneName, mapID, chain
end

local function GetCurrentPlaceInfo()
    local zoneName = GetRealZoneText() or "Unknown Zone"
    local instanceName, instanceType = GetInstanceInfo()

    local placeType = "zone"
    local placeName = zoneName

    local worldName, continentName, autoZoneName, mapID, chain = GetZoneHierarchy()

    if instanceType == "party" then
        placeType = "dungeon"
        placeName = DungeonNameAliases[instanceName] or instanceName or autoZoneName or "Unknown Dungeon"
        worldName = "Dungeons"
        continentName = "Dungeons"
    elseif instanceType == "raid" then
        placeType = "raid"
        placeName = instanceName or autoZoneName or "Unknown Raid"
        worldName = "Raids"
        continentName = "Raids"
    else
        placeType = "zone"
        placeName = autoZoneName or zoneName
    end

    local alias = PlaceAliases[placeName]
    if alias then
        placeType = alias.placeType
        placeName = alias.placeName
        worldName = alias.worldName
        continentName = alias.continentName
    end

    local placeKey = worldName .. "|" .. continentName .. "|" .. placeType .. "|" .. placeName

    return {
        worldName = worldName,
        continentName = continentName,
        placeType = placeType,
        placeName = placeName,
        placeKey = placeKey,
        mapID = mapID,
        chain = chain,
    }
end

Places.NormalizeWorldName = NormalizeWorldName
Places.GetZoneHierarchy = GetZoneHierarchy
Places.GetCurrentPlaceInfo = GetCurrentPlaceInfo

ns.Places = Places