-- ============================================================================
-- 1. SavedVariables defaults and runtime state
-- ============================================================================

FarmingoDB = FarmingoDB or {
    profiles = {
        ["Default"] = {
            mobs = {},
            mobNamesByKey = {},
        },
    },
    characterProfile = {},
    ui = {
        locked = false,
        settingsOpen = false,
        width = 360,
        height = 320,
        minimap = {
            hide = false,
        }
    }
}

local ADDON_NAME = ...

local observedMobNamesByKey = {}
local pendingReset = false
local FarmingoSession = {
    mobs = {}
}
local PendingLootSlots = {}
local AttemptedLootSlots = {}
local RuntimeSeenSources = {}
local currentViewMode = "mob"
local ClearedSourcesThisWindow = {}
local SourceLootNumberThisWindow = {}
local CurrentLootWasAuto = false
local isSearchOpen = false
local searchQuery = ""
local SEARCH_PLACEHOLDER = "Search info..."

local COLOR_WORLD = "|cffd8b25d"
local COLOR_CONTINENT = "|cffffb347"
local COLOR_PLACE = "|cffffff99"
local COLOR_MOB = "|cffffff00"   
local COLOR_RESET = "|r"

-- ============================================================================
-- 2. Forward declarations
-- ============================================================================

local EnsureDB
local RefreshSettingsUI
local RefreshFooterLayout
local ProcessClearedLootSlot
local UpdateToggleAllButton
local UpdateFooterTotals
local RenderPlaceView
local RenderMobView
local UpdateDisplay

-- ============================================================================
-- 3. Profile / database helpers
-- ============================================================================

local function GetCurrentCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
end

local function GetActiveProfileName()
    EnsureDB()

    local characterKey = GetCurrentCharacterKey()
    local profileName = FarmingoDB.characterProfile[characterKey]

    if not profileName or profileName == "" then
        profileName = "Default"
        FarmingoDB.characterProfile[characterKey] = profileName
    end

    if not FarmingoDB.profiles[profileName] then
        FarmingoDB.profiles[profileName] = {
            mobs = {},
            mobNamesByKey = {},
        }
    end

    return profileName
end

local function GetActiveProfile()
    EnsureDB()

    local profileName = GetActiveProfileName()
    local profile = FarmingoDB.profiles[profileName]

    if not profile then
        profile = {
            mobs = {},
            mobNamesByKey = {},
        }
        FarmingoDB.profiles[profileName] = profile
    end

    profile.mobs = profile.mobs or {}
    profile.mobNamesByKey = profile.mobNamesByKey or {}

    return profile
end

local function GetProfileMobs()
    return GetActiveProfile().mobs
end

local function GetProfileSeenSources()
    return RuntimeSeenSources
end

local function GetProfileMobNamesByKey()
    return GetActiveProfile().mobNamesByKey
end

local function NormalizeProfileName(profileName)
    if not profileName then
        return nil
    end

    profileName = strtrim(profileName)
    if profileName == "" then
        return nil
    end

    return profileName
end

local function ProfileExists(profileName)
    profileName = NormalizeProfileName(profileName)
    if not profileName then
        return false
    end

    EnsureDB()
    return FarmingoDB.profiles[profileName] ~= nil
end

local function CreateProfile(profileName)
    profileName = NormalizeProfileName(profileName)
    if not profileName then
        return false, "Invalid profile name."
    end

    EnsureDB()

    if FarmingoDB.profiles[profileName] then
        return false, "Profile already exists."
    end

    FarmingoDB.profiles[profileName] = {
        mobs = {},
        mobNamesByKey = {},
    }

    return true
end

local function SetCharacterProfile(profileName)
    profileName = NormalizeProfileName(profileName)
    if not profileName then
        return false, "Invalid profile name."
    end

    EnsureDB()

    if not FarmingoDB.profiles[profileName] then
        return false, "Profile does not exist."
    end

    local characterKey = GetCurrentCharacterKey()
    FarmingoDB.characterProfile[characterKey] = profileName

    wipe(observedMobNamesByKey)
    wipe(PendingLootSlots)
    wipe(ClearedSourcesThisWindow)
    wipe(SourceLootNumberThisWindow)
    wipe(AttemptedLootSlots)
    wipe(RuntimeSeenSources)

    CurrentLootWasAuto = false

    FarmingoSession = {
        mobs = {}
    }

    return true
end

local function GetSortedProfileNames()
    EnsureDB()

    local names = {}
    for profileName in pairs(FarmingoDB.profiles) do
        table.insert(names, profileName)
    end

    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)

    return names
end

local function GetCharactersUsingProfile(profileName)
    EnsureDB()

    local characters = {}

    for characterKey, assignedProfile in pairs(FarmingoDB.characterProfile or {}) do
        if assignedProfile == profileName then
            table.insert(characters, characterKey)
        end
    end

    table.sort(characters)
    return characters
end

local function DeleteProfile(profileName)
    profileName = NormalizeProfileName(profileName)
    if not profileName then
        return false, "Invalid profile name."
    end

    EnsureDB()

    if profileName == "Default" then
        return false, "Default profile cannot be deleted."
    end

    if not FarmingoDB.profiles[profileName] then
        return false, "Profile does not exist."
    end

    if GetActiveProfileName() == profileName then
        return false, "You cannot delete the currently active profile."
    end

    local characters = GetCharactersUsingProfile(profileName)
    if #characters > 0 then
        return false, "Profile is still assigned to: " .. table.concat(characters, ", ")
    end

    FarmingoDB.profiles[profileName] = nil
    return true
end

function EnsureDB()
    FarmingoDB = FarmingoDB or {}

    FarmingoDB.debugPlaces = FarmingoDB.debugPlaces or {}

    FarmingoDB.ui = FarmingoDB.ui or {}
    if FarmingoDB.ui.locked == nil then
        FarmingoDB.ui.locked = false
    end
    if FarmingoDB.ui.settingsOpen == nil then
        FarmingoDB.ui.settingsOpen = false
    end
    if not FarmingoDB.ui.width then
        FarmingoDB.ui.width = 360
    end
    if not FarmingoDB.ui.height then
        FarmingoDB.ui.height = 320
    end
    if FarmingoDB.ui.footerHidden == nil then
        FarmingoDB.ui.footerHidden = false
    end

    if FarmingoDB.ui.tooltipEnabled == nil then
        FarmingoDB.ui.tooltipEnabled = true
    end

    FarmingoDB.ui.minimap = FarmingoDB.ui.minimap or {}
    if FarmingoDB.ui.minimap.hide == nil then
        FarmingoDB.ui.minimap.hide = false
    end

    FarmingoDB.ui.expandedMobs = FarmingoDB.ui.expandedMobs or {}
    FarmingoDB.ui.expandedPlaces = FarmingoDB.ui.expandedPlaces or {}
    FarmingoDB.ui.expandedContinents = FarmingoDB.ui.expandedContinents or {}
    FarmingoDB.ui.expandedWorlds = FarmingoDB.ui.expandedWorlds or {}

    FarmingoDB.profiles = FarmingoDB.profiles or {}
    FarmingoDB.characterProfile = FarmingoDB.characterProfile or {}

    FarmingoDB.profiles["Default"] = FarmingoDB.profiles["Default"] or {
        mobs = {},
        mobNamesByKey = {},
    }

    local hasOldFlatData =
        FarmingoDB.mobs ~= nil
        or FarmingoDB.mobNamesByKey ~= nil

    if hasOldFlatData then
        local defaultProfile = FarmingoDB.profiles["Default"]

        if FarmingoDB.mobs and next(FarmingoDB.mobs) and not next(defaultProfile.mobs) then
            defaultProfile.mobs = FarmingoDB.mobs
        end

        if FarmingoDB.mobNamesByKey and next(FarmingoDB.mobNamesByKey) and not next(defaultProfile.mobNamesByKey) then
            defaultProfile.mobNamesByKey = FarmingoDB.mobNamesByKey
        end

        FarmingoDB.mobs = nil
        FarmingoDB.mobNamesByKey = nil
    end

    local characterKey = GetCurrentCharacterKey()
    if not FarmingoDB.characterProfile[characterKey] or FarmingoDB.characterProfile[characterKey] == "" then
        FarmingoDB.characterProfile[characterKey] = "Default"
    end

    local activeProfileName = FarmingoDB.characterProfile[characterKey]
    FarmingoDB.profiles[activeProfileName] = FarmingoDB.profiles[activeProfileName] or {
        mobs = {},
        mobNamesByKey = {},
    }

    local activeProfile = FarmingoDB.profiles[activeProfileName]
    activeProfile.mobs = activeProfile.mobs or {}
    activeProfile.mobNamesByKey = activeProfile.mobNamesByKey or {}
end

-- ============================================================================
-- 4. Data entry / session mutation helpers
-- ============================================================================

local function EnsureMobEntry(mobKey, displayName)
    EnsureDB()

    if not mobKey then
        mobKey = "unknown"
    end

    local mobs = GetProfileMobs()

    if not mobs[mobKey] then
        mobs[mobKey] = {
            displayName = displayName or "Unknown Mob",
            lootCount = 0,
            gold = 0,
            items = {},
            places = {}
        }
    elseif displayName and displayName ~= "" then
        local currentName = mobs[mobKey].displayName
        if not currentName
            or currentName == "Unknown Mob"
            or currentName:find("^Unknown Mob %(")
            or currentName:find("^Unknown Vehicle %(") then
            mobs[mobKey].displayName = displayName
        end
    end

    mobs[mobKey].places = mobs[mobKey].places or {}

    return mobs[mobKey]
end

local function EnsureSessionMobEntry(mobKey, displayName)
    if not mobKey then
        mobKey = "unknown"
    end

    if not FarmingoSession.mobs[mobKey] then
        FarmingoSession.mobs[mobKey] = {
            displayName = displayName or "Unknown Mob",
            lootCount = 0,
            gold = 0,
            items = {}
        }
    elseif displayName then
        FarmingoSession.mobs[mobKey].displayName = displayName
    end

    return FarmingoSession.mobs[mobKey]
end

local function IncrementLootCount(mobKey, displayName)
    local entry = EnsureMobEntry(mobKey, displayName)
    entry.lootCount = (entry.lootCount or 0) + 1
end

local function IncrementSessionLootCount(mobKey, displayName)
    local entry = EnsureSessionMobEntry(mobKey, displayName)
    entry.lootCount = (entry.lootCount or 0) + 1
end

local function AddLootToMob(mobKey, displayName, itemName, quantity, itemLink, firstDropLootCount)
    if not itemName then
        return
    end

    if not quantity or quantity < 1 then
        quantity = 1
    end

    local entry = EnsureMobEntry(mobKey, displayName)

    if not entry.items[itemName] then
        entry.items[itemName] = {
            count = 0,
            link = itemLink,
            firstDropLootCount = firstDropLootCount or (entry.lootCount or 0) + 1,
        }
    end

    entry.items[itemName].count = (entry.items[itemName].count or 0) + quantity

    if itemLink then
        entry.items[itemName].link = itemLink
    end
end

local function AddLootToSession(mobKey, displayName, itemName, quantity)
    if not itemName then
        return
    end

    if not quantity or quantity < 1 then
        quantity = 1
    end

    local entry = EnsureSessionMobEntry(mobKey, displayName)

    if not entry.items[itemName] then
        entry.items[itemName] = {
            count = 0,
        }
    end

    entry.items[itemName].count = (entry.items[itemName].count or 0) + quantity
end

local function AddGoldToMob(mobKey, displayName, copper)
    if not copper or copper <= 0 then
        return
    end

    local entry = EnsureMobEntry(mobKey, displayName)
    entry.gold = (entry.gold or 0) + copper
end

local function AddGoldToSession(mobKey, displayName, copper)
    if not copper or copper <= 0 then
        return
    end

    local entry = EnsureSessionMobEntry(mobKey, displayName)
    entry.gold = (entry.gold or 0) + copper
end

local function AddPlaceToMob(mobKey, displayName, placeKey)
    if not placeKey then
        return
    end

    local entry = EnsureMobEntry(mobKey, displayName)
    entry.places = entry.places or {}
    entry.places[placeKey] = (entry.places[placeKey] or 0) + 1
end

-- ============================================================================
-- 5. GUID / source / mob-name helpers
-- ============================================================================

local function GetSourceTypeFromGUID(guid)
    if not guid then return nil end
    return strsplit("-", guid)
end

local function IsMobGUID(guid)
    local sourceType = GetSourceTypeFromGUID(guid)
    return sourceType == "Creature" or sourceType == "Vehicle"
end

local function IsObjectGUID(guid)
    local sourceType = GetSourceTypeFromGUID(guid)
    return sourceType == "GameObject"
end

local function GetMobKeyFromUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local unitType, npcID

    local ok = pcall(function()
        local t, _, _, _, _, id = strsplit("-", guid)
        unitType = t
        npcID = id
    end)

    if not ok then
        return nil
    end

    if (unitType == "Creature" or unitType == "Vehicle") and npcID and npcID ~= "" then
        return unitType .. ":" .. npcID
    end

    return nil
end

local function GetMobKeyFromSourceGUID(sourceGUID)
    if not sourceGUID then
        return "unknown"
    end

    local unitType, npcID

    local ok = pcall(function()
        local t, _, _, _, _, id = strsplit("-", sourceGUID)
        unitType = t
        npcID = id
    end)

    if not ok then
        return "unknown"
    end

    if (unitType == "Creature" or unitType == "Vehicle") and npcID and npcID ~= "" then
        return unitType .. ":" .. npcID
    end

    return "unknown"
end

local function IsSafeDisplayString(value)
    if not value then
        return false
    end

    return pcall(function()
        local _ = value .. ""
    end)
end

local function RememberMobNameByKey(mobKey, name)
    if not mobKey or mobKey == "unknown" then
        return
    end

    if not name or name == "Unknown" then
        return
    end

    if not IsSafeDisplayString(name) then
        return
    end

    observedMobNamesByKey[mobKey] = name

    local mobNamesByKey = GetProfileMobNamesByKey()
    mobNamesByKey[mobKey] = name

    local mobs = GetProfileMobs()
    if mobs[mobKey] then
        mobs[mobKey].displayName = name
    end
end

local function RememberMob(unit)
    if not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    if UnitIsFriend("player", unit) then return end
    if not UnitCanAttack("player", unit) then return end

    local name = UnitName(unit)
    local mobKey = GetMobKeyFromUnit(unit)

    if not name or not mobKey then
        return
    end

    RememberMobNameByKey(mobKey, name)
end

local function GetDisplayNameForSource(sourceGUID)
    local mobKey = GetMobKeyFromSourceGUID(sourceGUID)
    if not mobKey or mobKey == "unknown" then
        return nil
    end

    if observedMobNamesByKey[mobKey] then
        return observedMobNamesByKey[mobKey]
    end

    local mobNamesByKey = GetProfileMobNamesByKey()
    if mobNamesByKey[mobKey] then
        return mobNamesByKey[mobKey]
    end

    return nil
end

local function GetFallbackDisplayNameFromKey(mobKey)
    if not mobKey then
        return "Unknown Mob"
    end

    local unitType, npcID = mobKey:match("^([^:]+):(.+)$")
    if npcID then
        if unitType == "Creature" then
            return "Unknown Mob (" .. npcID .. ")"
        elseif unitType == "Vehicle" then
            return "Unknown Vehicle (" .. npcID .. ")"
        end
    end

    return "Unknown Mob"
end

local function GetMobIDFromKey(mobKey)
    if not mobKey then
        return nil
    end

    local _, npcID = mobKey:match("^([^:]+):(.+)$")
    return npcID
end

local function GetSafeDisplayName(mobKey, preferredName)
    if IsSafeDisplayString(preferredName) then
        return preferredName
    end

    local mobNamesByKey = GetProfileMobNamesByKey()
    if mobNamesByKey[mobKey] and mobNamesByKey[mobKey] ~= "" then
        return mobNamesByKey[mobKey]
    end

    local npcID = GetMobIDFromKey(mobKey)
    if npcID then
        local ok, creatureName = pcall(function()
            if C_CreatureInfo and C_CreatureInfo.GetCreatureName then
                return C_CreatureInfo.GetCreatureName(tonumber(npcID))
            end
            return nil
        end)

        if ok and creatureName and creatureName ~= "" then
            return creatureName
        end
    end

    return GetFallbackDisplayNameFromKey(mobKey)
end

local function BuildDuplicateMobNameMap()
    local nameCounts = {}

    for mobKey, data in pairs(GetProfileMobs()) do
        local displayName = GetSafeDisplayName(mobKey, data.displayName)
        nameCounts[displayName] = (nameCounts[displayName] or 0) + 1
    end

    return nameCounts
end

local function GetDisplayNameWithDuplicateSuffix(mobKey, preferredName, duplicateNameMap)
    local displayName = GetSafeDisplayName(mobKey, preferredName)

    if duplicateNameMap and duplicateNameMap[displayName] and duplicateNameMap[displayName] > 1 then
        local npcID = GetMobIDFromKey(mobKey)
        if npcID then
            return displayName .. " [" .. npcID .. "]"
        end
    end

    return displayName
end

local function IsFallbackMobName(name)
    if not name then
        return false
    end

    return name:find("^Unknown Mob %(") or name:find("^Unknown Vehicle %(")
end

-- ============================================================================
-- 6. Place / map / zone helpers
-- ============================================================================

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
    -- debug
    local debugEntry = {
        zoneName = zoneName,
        autoZoneName = autoZoneName,
        worldName = worldName,
        continentName = continentName,
        placeType = placeType,
        placeName = placeName,
        mapID = mapID,
    }

    local key = (placeName or "Unknown") .. "|" .. tostring(mapID)

    if worldName == "Cosmic" then
    FarmingoDB.debugPlaces[key] = debugEntry
    end
    -- debug
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

-- ============================================================================
-- 7. Loot tracking helpers
-- ============================================================================

local function MarkSourceSeen(sourceGUID)
    local seenSources = GetProfileSeenSources()
    if sourceGUID then
        seenSources[sourceGUID] = true
    end
end

local function HasSeenSource(sourceGUID)
    local seenSources = GetProfileSeenSources()
    return sourceGUID and seenSources[sourceGUID]
end

local function ParseMoneyTextToCopper(text)
    if not text or text == "" then
        return 0
    end

    text = text:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")

    local total = 0

    local gold = text:match("(%d+)%s*[Gg]")
    local silver = text:match("(%d+)%s*[Ss]")
    local copper = text:match("(%d+)%s*[Cc]")

    if gold then
        total = total + tonumber(gold) * 10000
    end
    if silver then
        total = total + tonumber(silver) * 100
    end
    if copper then
        total = total + tonumber(copper)
    end

    return total
end

local function BuildPendingLoot()

    wipe(AttemptedLootSlots)

    PendingLootSlots = {}
    ClearedSourcesThisWindow = {}
    SourceLootNumberThisWindow = {}

    local numItems = GetNumLootItems()

    for slot = 1, numItems do
        local slotType = GetLootSlotType(slot)
        local texture, lootName, lootQuantity, quality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(slot)
        local itemLink = GetLootSlotLink(slot)
        local sources = { GetLootSourceInfo(slot) }

        PendingLootSlots[slot] = {
            slotType = slotType,
            lootName = lootName,
            lootQuantity = lootQuantity or 1,
            itemLink = itemLink,
            sources = sources,
        }
    end
end

local function ClearPendingLoot()
    PendingLootSlots = {}
    ClearedSourcesThisWindow = {}
    SourceLootNumberThisWindow = {}
    wipe(AttemptedLootSlots)
end

local function ProcessAttemptedPendingLootSlots()
    for slot in pairs(AttemptedLootSlots) do
        if PendingLootSlots[slot] then
            ProcessClearedLootSlot(slot)
        end
    end
end

local function ProcessAllPendingLootSlots()
    for slot in pairs(PendingLootSlots) do
        ProcessClearedLootSlot(slot)
    end
end

hooksecurefunc("LootSlot", function(slot)
    if PendingLootSlots and PendingLootSlots[slot] then
        AttemptedLootSlots[slot] = true
    end
end)

ProcessClearedLootSlot = function(slot)
    EnsureDB()

    local slotData = PendingLootSlots[slot]
    if not slotData then
        return
    end

    local slotType = slotData.slotType
    local lootName = slotData.lootName
    local quantity = slotData.lootQuantity or 1
    local itemLink = slotData.itemLink
    local sources = slotData.sources or {}

    local placeInfo = GetCurrentPlaceInfo()
    local placeKey = placeInfo.placeKey
    local sourceToMobName = {}

    for i = 1, #sources, 2 do
        local sourceGUID = sources[i]

        if sourceGUID and IsMobGUID(sourceGUID) then
            if not sourceToMobName[sourceGUID] then
                sourceToMobName[sourceGUID] = GetDisplayNameForSource(sourceGUID)
            end
        end
    end

    for i = 1, #sources, 2 do
        local sourceGUID = sources[i]
        local sourceQuantity = tonumber(sources[i + 1]) or quantity or 1

        if sourceGUID and IsMobGUID(sourceGUID) then
            local mobKey = GetMobKeyFromSourceGUID(sourceGUID)
            local rawDisplayName = sourceToMobName[sourceGUID]
            local displayName = GetSafeDisplayName(mobKey, rawDisplayName)

            local entry = EnsureMobEntry(mobKey, displayName)

            if not SourceLootNumberThisWindow[sourceGUID] then
                local lootNumber = entry.lootCount or 0

                if not HasSeenSource(sourceGUID) then
                    lootNumber = lootNumber + 1
                end

                SourceLootNumberThisWindow[sourceGUID] = lootNumber
            end

            local firstDropLootCount = SourceLootNumberThisWindow[sourceGUID]

            if slotType == Enum.LootSlotType.Item and lootName then
                AddLootToMob(mobKey, displayName, lootName, sourceQuantity, itemLink, firstDropLootCount)
                AddLootToSession(mobKey, displayName, lootName, sourceQuantity)
            elseif slotType == Enum.LootSlotType.Money and lootName then
                local copper = ParseMoneyTextToCopper(lootName)
                AddGoldToMob(mobKey, displayName, copper)
                AddGoldToSession(mobKey, displayName, copper)
            end

            if not ClearedSourcesThisWindow[sourceGUID] and not HasSeenSource(sourceGUID) then
                IncrementLootCount(mobKey, displayName)
                IncrementSessionLootCount(mobKey, displayName)
                MarkSourceSeen(sourceGUID)
                ClearedSourcesThisWindow[sourceGUID] = true
                AddPlaceToMob(mobKey, displayName, placeKey)
            end
        end
    end

    PendingLootSlots[slot] = nil
    UpdateDisplay()
end

-- ============================================================================
-- 8. Tooltip / formatting / search helpers
-- ============================================================================

local function FormatMoney(copper)
    copper = tonumber(copper) or 0

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100

    local goldIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"
    local silverIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:0:0|t"
    local copperIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:0:0|t"

    local parts = {}

    if gold > 0 then
        table.insert(parts, gold .. goldIcon)
    end
    if silver > 0 or gold > 0 then
        table.insert(parts, silver .. silverIcon)
    end
    table.insert(parts, copperOnly .. copperIcon)

    return table.concat(parts, " ")
end

local function GetItemIDFromLink(itemLink)
    if not itemLink then
        return nil
    end

    local itemID = itemLink:match("item:(%d+)")
    if itemID then
        return tonumber(itemID)
    end

    local instantID = select(1, GetItemInfoInstant(itemLink))
    if instantID then
        return instantID
    end

    return nil
end

local function GetFirstDropLootCountForItem(itemLink, itemID)
    EnsureDB()

    local targetItemID = itemID or GetItemIDFromLink(itemLink)
    if not targetItemID then
        return nil
    end

    for _, mobData in pairs(GetProfileMobs()) do
        for _, itemData in pairs(mobData.items or {}) do
            local storedItemID = GetItemIDFromLink(itemData.link)

            if storedItemID == targetItemID and itemData.firstDropLootCount then
                return itemData.firstDropLootCount
            end
        end
    end

    return nil
end

local function AddFarmingoTooltipLine(tooltip, itemLink, itemID)
    if not tooltip then
        return
    end

    for i = 1, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local text = line:GetText()
            if text == "No Farmingo drop data" or (text and text:find("^Dropped after ")) then
                return
            end
        end
    end

    local firstDropLootCount = GetFirstDropLootCountForItem(itemLink, itemID)

    if firstDropLootCount then
        local lootWord = (firstDropLootCount == 1) and "loot" or "loots"
        tooltip:AddLine("Dropped after " .. firstDropLootCount .. " " .. lootWord, 0.4, 0.7, 1)
    else
        tooltip:AddLine("No Farmingo drop data", 0.5, 0.5, 0.5)
    end
end

local function StringMatchesSearch(text)
    if not searchQuery or searchQuery == "" then
        return true
    end

    if not text then
        return false
    end

    local ok, safeText = pcall(function()
        return tostring(text):lower()
    end)

    if not ok or not safeText then
        return false
    end

    return safeText:find(searchQuery, 1, true) ~= nil
end

local function HighlightSearchMatch(text)
    if not text then
        return text
    end

    if not searchQuery or searchQuery == "" then
        return text
    end

    local lowerText = text:lower()
    local startPos = lowerText:find(searchQuery, 1, true)

    if not startPos then
        return text
    end

    local endPos = startPos + #searchQuery - 1

    local before = text:sub(1, startPos - 1)
    local matchText = text:sub(startPos, endPos)
    local after = text:sub(endPos + 1)

    return before .. "|cffff8800" .. matchText .. "|r" .. after
end

local function MobMatchesSearch(mobKey, data)
    if not searchQuery or searchQuery == "" then
        return true
    end

    local displayName = GetSafeDisplayName(mobKey, data.displayName)

    if StringMatchesSearch(displayName) then
        return true
    end

    if StringMatchesSearch(mobKey) then
        return true
    end

    for itemName, itemData in pairs(data.items or {}) do
        if StringMatchesSearch(itemName) then
            return true
        end

        if itemData.link and StringMatchesSearch(itemData.link) then
            return true
        end
    end

    return false
end

-- ============================================================================
-- 8.5 Place total helpers
-- ============================================================================

local function GetPlaceLootTotal(profileMobs, placeKey)
    local total = 0

    for _, data in pairs(profileMobs) do
        if data.places and data.places[placeKey] then
            total = total + data.places[placeKey]
        end
    end

    return total
end

local function GetPlaceGoldTotal(profileMobs, placeKey)
    local total = 0

    for _, data in pairs(profileMobs) do
        if data.places and data.places[placeKey] then
            total = total + (data.gold or 0)
        end
    end

    return total
end

local function GetGroupedLootTotal(groupedPlaces)
    local total = 0

    for placeKey, mobs in pairs(groupedPlaces) do
        for _, mobData in pairs(mobs) do
            if mobData.places and mobData.places[placeKey] then
                total = total + mobData.places[placeKey]
            end
        end
    end

    return total
end

local function GetGroupedGoldTotal(groupedPlaces)
    local total = 0

    for placeKey, mobs in pairs(groupedPlaces) do
        for _, mobData in pairs(mobs) do
            if mobData.places and mobData.places[placeKey] then
                total = total + (mobData.gold or 0)
            end
        end
    end

    return total
end

local function GetNestedGroupedLootTotal(nestedGroups)
    local total = 0

    for _, groupedPlaces in pairs(nestedGroups) do
        total = total + GetGroupedLootTotal(groupedPlaces)
    end

    return total
end

local function GetNestedGroupedGoldTotal(nestedGroups)
    local total = 0

    for _, groupedPlaces in pairs(nestedGroups) do
        total = total + GetGroupedGoldTotal(groupedPlaces)
    end

    return total
end

local function GetPlaceNameFromKey(placeKey)
    local _, _, _, placeName = strsplit("|", placeKey)
    return placeName or placeKey
end

local function SortKeysByLootTotal(keys, getTotal, getTieName)
    table.sort(keys, function(a, b)
        local totalA = getTotal(a)
        local totalB = getTotal(b)

        if totalA == totalB then
            return getTieName(a) < getTieName(b)
        end

        return totalA > totalB
    end)
end

-- ============================================================================
-- 9. UI creation
-- ============================================================================

local frame = CreateFrame("Frame", "FarmingoFrame", UIParent, "BackdropTemplate")
EnsureDB()
frame:SetSize(FarmingoDB.ui.width, FarmingoDB.ui.height)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetResizable(true)
frame:SetResizeBounds(260, 180)

local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("Farmingo", {
    type = "data source",
    text = "Farmingo",
    icon = "Interface\\Icons\\INV_Box_02",

    OnClick = function(_, button)
        if button == "LeftButton" then
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Farmingo")
        tooltip:AddLine("Left-click: show/hide window", 1, 1, 1)
    end,
})

local icon = LibStub("LibDBIcon-1.0")
local minimapRegistered = false

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local settingsButton = CreateFrame("Button", nil, frame)
settingsButton:SetSize(18, 18)
settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)

local searchButton = CreateFrame("Button", nil, frame)
searchButton:SetSize(18, 18)
searchButton:SetPoint("RIGHT", settingsButton, "LEFT", -2, 0)

searchButton.icon = searchButton:CreateTexture(nil, "ARTWORK")
searchButton.icon:SetAllPoints()
searchButton.icon:SetTexture("Interface\\ICONS\\INV_Misc_Spyglass_03")
searchButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

searchButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local topDivider = frame:CreateTexture(nil, "ARTWORK")
topDivider:SetHeight(1)
topDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
topDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -28)
topDivider:SetColorTexture(1, 1, 1, 0.05)

settingsButton.icon = settingsButton:CreateTexture(nil, "ARTWORK")
settingsButton.icon:SetAllPoints()
settingsButton.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")

settingsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
searchBox:SetSize(130, 18)
searchBox:ClearAllPoints()
searchBox:SetPoint("RIGHT", searchButton, "LEFT", -4, 0)
searchBox:SetTextInsets(6, 6, 0, 0)
searchBox:SetAutoFocus(false)
searchBox:SetText(SEARCH_PLACEHOLDER)
searchBox:SetTextColor(0.6, 0.6, 0.6)
searchBox:Hide()

searchBox:SetFrameStrata("DIALOG")
searchBox:SetFrameLevel(searchButton:GetFrameLevel() + 10)

if searchBox.Left then searchBox.Left:SetDrawLayer("OVERLAY") end
if searchBox.Middle then searchBox.Middle:SetDrawLayer("OVERLAY") end
if searchBox.Right then searchBox.Right:SetDrawLayer("OVERLAY") end

local searchBoxBG = CreateFrame("Frame", nil, frame, "BackdropTemplate")
searchBoxBG:SetPoint("TOPLEFT", searchBox, "TOPLEFT", -3, 0)
searchBoxBG:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", 3, 0)

searchBoxBG:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
searchBoxBG:SetBackdropColor(0, 0, 0, 1)
searchBoxBG:SetFrameStrata(searchBox:GetFrameStrata())
searchBoxBG:SetFrameLevel(searchBox:GetFrameLevel() - 1)
searchBoxBG:Hide()

local resizeButton = CreateFrame("Button", nil, frame)
resizeButton:SetSize(16, 16)
resizeButton:SetPoint("BOTTOMRIGHT")

resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0, 0, 0, 0.85)

local scrollFrame = CreateFrame("ScrollFrame", "FarmingoScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -34)
scrollFrame:SetPoint("BOTTOMLEFT", 12, 100)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 100)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1)
scrollFrame:SetScrollChild(content)

local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
footer:SetPoint("BOTTOMLEFT", 12, 12)
footer:SetPoint("BOTTOMRIGHT", -12, 12)
footer:SetHeight(66)

footer:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
footer:SetBackdropColor(0.06, 0.06, 0.06, 0.95)

local totalLootsLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalLootsLabel:SetPoint("TOPLEFT", 8, -10)
totalLootsLabel:SetText("|cffd8b25dTotal loots:|r")

local totalLootsValue = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
totalLootsValue:SetPoint("TOPRIGHT", -8, -10)
totalLootsValue:SetText("0")

local totalGoldLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalGoldLabel:SetPoint("TOPLEFT", totalLootsLabel, "BOTTOMLEFT", 0, -6)
totalGoldLabel:SetText("|cffd8b25dTotal gold:|r")

local totalGoldValue = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
totalGoldValue:SetPoint("TOPRIGHT", totalLootsValue, "BOTTOMRIGHT", 0, -6)
totalGoldValue:SetText("0c")

local sessionLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sessionLabel:SetPoint("TOPLEFT", totalGoldLabel, "BOTTOMLEFT", 0, -6)
sessionLabel:SetText("|cff66ccffThis session total loots:|r")

local sessionValue = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sessionValue:SetPoint("TOPRIGHT", totalGoldValue, "BOTTOMRIGHT", 0, -6)
sessionValue:SetText("0")

local sessionGoldLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sessionGoldLabel:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -6)
sessionGoldLabel:SetText("|cff66ccffThis session gold:|r")

local sessionGoldValue = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sessionGoldValue:SetPoint("TOPRIGHT", sessionValue, "BOTTOMRIGHT", 0, -6)
sessionGoldValue:SetText("0c")

local footerToggleButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
footerToggleButton:SetSize(22, 14)
footerToggleButton:SetPoint("TOP", footer, "TOP", -3, -2)
footerToggleButton:SetText("-")

local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
settingsPanel:ClearAllPoints()
settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -42)
settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 12)
settingsPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
settingsPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
settingsPanel:Hide()

local settingsScrollFrame = CreateFrame("ScrollFrame", nil, settingsPanel, "UIPanelScrollFrameTemplate")
settingsScrollFrame:SetPoint("TOPLEFT", 8, -8)
settingsScrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

local settingsContent = CreateFrame("Frame", nil, settingsScrollFrame)
settingsContent:SetSize(1, 1)
settingsScrollFrame:SetScrollChild(settingsContent)

local profileLabel = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
profileLabel:SetPoint("TOPLEFT", 14, -14)
profileLabel:SetText("|cff66ccffActive Profile:|r")

local profileValue = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
profileValue:SetPoint("LEFT", profileLabel, "RIGHT", 8, 0)
profileValue:SetText(GetActiveProfileName())

local function InitializeProfileDropdown(self, level)
    local profiles = GetSortedProfileNames()
    local activeProfile = GetActiveProfileName()

    for _, name in ipairs(profiles) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (name == activeProfile)

        info.func = function()
            local ok, err = SetCharacterProfile(name)
            if ok then
                RefreshSettingsUI()
                RefreshFooterLayout()
                UpdateDisplay()
                print("Farmingo: active profile set to " .. name)
            else
                print("Farmingo: " .. err)
            end
        end

        UIDropDownMenu_AddButton(info)
    end
end

local profileDropdown = CreateFrame("Frame", "FarmingoProfileDropdown", settingsContent, "UIDropDownMenuTemplate")
profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(profileDropdown, 150)
UIDropDownMenu_Initialize(profileDropdown, InitializeProfileDropdown)
UIDropDownMenu_SetText(profileDropdown, GetActiveProfileName())

local createButton = CreateFrame("Button", nil, settingsContent, "UIPanelButtonTemplate")
createButton:SetSize(150, 22)
createButton:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 16, -8)
createButton:SetText("New Profile")

local profileHelpText = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
profileHelpText:SetPoint("TOPLEFT", createButton, "BOTTOMLEFT", 2, -8)
profileHelpText:SetWidth(260)
profileHelpText:SetJustifyH("LEFT")
profileHelpText:SetText("Profiles store your farming data.")

local profileDivider = settingsContent:CreateTexture(nil, "ARTWORK")
profileDivider:SetHeight(1)
profileDivider:SetPoint("TOPLEFT", profileHelpText, "BOTTOMLEFT", -2, -10)
profileDivider:SetPoint("RIGHT", settingsContent, "RIGHT", -12, 0)
profileDivider:SetColorTexture(1, 1, 1, 0.08)

local lockCheck = CreateFrame("CheckButton", nil, settingsContent, "UICheckButtonTemplate")
lockCheck:SetPoint("TOPLEFT", profileDivider, "BOTTOMLEFT", 0, -10)

local lockText = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockText:SetPoint("LEFT", lockCheck, "RIGHT", 4, 0)
lockText:SetText("Lock window")

local tooltipCheck = CreateFrame("CheckButton", nil, settingsContent, "UICheckButtonTemplate")
tooltipCheck:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -8)

local tooltipText = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tooltipText:SetPoint("LEFT", tooltipCheck, "RIGHT", 4, 0)
tooltipText:SetText("Enable tooltip drop info")

local commandsDivider = settingsContent:CreateTexture(nil, "ARTWORK")
commandsDivider:SetHeight(1)
commandsDivider:SetPoint("TOPLEFT", tooltipCheck, "BOTTOMLEFT", 0, -12)
commandsDivider:SetPoint("RIGHT", settingsContent, "RIGHT", -12, 0)
commandsDivider:SetColorTexture(1, 1, 1, 0.06)

local commandsTitle = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
commandsTitle:SetPoint("TOPLEFT", commandsDivider, "BOTTOMLEFT", 0, -10)
commandsTitle:SetText("|cff888888Commands|r")

local commandsLeft = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
commandsLeft:SetPoint("TOPLEFT", commandsTitle, "BOTTOMLEFT", 0, -6)
commandsLeft:SetWidth(122)
commandsLeft:SetJustifyH("LEFT")
commandsLeft:SetJustifyV("TOP")
commandsLeft:SetText(
    "|cffbfbfbf/ft show|r - show window\n" ..
    "|cffbfbfbf/ft hide|r - hide window\n" ..
    "|cffbfbfbf/ft reset|r - request data reset\n" ..
    "|cffbfbfbf/ft confirmreset|r - confirm data reset\n" ..
    "|cffbfbfbf/ft profile|r - show current profile"
)

local commandsRight = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
commandsRight:SetPoint("TOPLEFT", commandsLeft, "TOPRIGHT", 10, 0)
commandsRight:SetWidth(122)
commandsRight:SetJustifyH("LEFT")
commandsRight:SetJustifyV("TOP")
commandsRight:SetText(
    "|cffbfbfbf/ft profiles|r - list all\n" ..
    "|cffbfbfbf/ft profile create NAME|r\n" ..
    "  create\n" ..
    "|cffbfbfbf/ft profile use NAME|r\n" ..
    "  switch\n" ..
    "|cffbfbfbf/ft profile delete NAME|r\n" ..
    "  delete unused"
)

local toggleAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
toggleAllButton:SetSize(55, 18)
toggleAllButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
toggleAllButton:SetText("All")

local viewModeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
viewModeButton:SetSize(70, 18)
viewModeButton:SetPoint("LEFT", toggleAllButton, "RIGHT", 6, 0)
viewModeButton:SetText("Mob")

local rows = {}
local ROW_HEIGHT = 20

-- ============================================================================
-- 10. UI layout / row helpers / rendering
-- ============================================================================

local function GetRow(index)
    if rows[index] then
        return rows[index]
    end

    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.countText:SetPoint("RIGHT", -8, 0)
    row.countText:SetJustifyH("RIGHT")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    if index % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.04)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row.separator = row:CreateTexture(nil, "ARTWORK")
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
    row.separator:SetColorTexture(1, 1, 1, 0.05)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    rows[index] = row
    return row
end

local function AreAnyMobsExpanded()
    EnsureDB()

    for _, expanded in pairs(FarmingoDB.ui.expandedMobs) do
        if expanded then
            return true
        end
    end

    return false
end

function RefreshFooterLayout()
    EnsureDB()

    scrollFrame:ClearAllPoints()

    if FarmingoDB.ui.footerHidden then
        footer:SetHeight(26)

        scrollFrame:SetPoint("TOPLEFT", 12, -34)
        scrollFrame:SetPoint("BOTTOMLEFT", 12, 42)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 42)

        totalLootsLabel:Hide()
        totalLootsValue:Hide()
        totalGoldLabel:Hide()
        totalGoldValue:Hide()
        sessionLabel:Hide()
        sessionValue:Hide()
        sessionGoldLabel:Hide()
        sessionGoldValue:Hide()

        footerToggleButton:SetText("+")
    else
        footer:SetHeight(84)

        scrollFrame:SetPoint("TOPLEFT", 12, -34)
        scrollFrame:SetPoint("BOTTOMLEFT", 12, 100)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 100)

        totalLootsLabel:Show()
        totalLootsValue:Show()
        totalGoldLabel:Show()
        totalGoldValue:Show()
        sessionLabel:Show()
        sessionValue:Show()
        sessionGoldLabel:Show()
        sessionGoldValue:Show()

        footerToggleButton:SetText("-")
    end
end

function RefreshSettingsUI()
    EnsureDB()

    lockCheck:SetChecked(FarmingoDB.ui.locked)
    resizeButton:SetShown(not FarmingoDB.ui.locked)

    tooltipCheck:SetChecked(FarmingoDB.ui.tooltipEnabled)

    profileValue:SetText(GetActiveProfileName())
    UIDropDownMenu_SetText(profileDropdown, GetActiveProfileName())

    settingsContent:SetWidth(settingsScrollFrame:GetWidth())
    settingsContent:SetHeight(420)

    if FarmingoDB.ui.settingsOpen then
        settingsPanel:Show()
        scrollFrame:Hide()
        footer:Hide()
    else
        settingsPanel:Hide()
        scrollFrame:Show()
        footer:Show()
    end

    if isSearchOpen and not FarmingoDB.ui.settingsOpen then
        searchBox:Show()
    else
        searchBox:Hide()
    end
end

settingsButton:SetScript("OnClick", function()
    EnsureDB()
    FarmingoDB.ui.settingsOpen = not FarmingoDB.ui.settingsOpen
    RefreshSettingsUI()
end)

lockCheck:SetScript("OnClick", function(self)
    EnsureDB()
    frame:StopMovingOrSizing()
    FarmingoDB.ui.locked = self:GetChecked() and true or false
    RefreshSettingsUI()
end)

tooltipCheck:SetScript("OnClick", function(self)
    EnsureDB()
    FarmingoDB.ui.tooltipEnabled = self:GetChecked() and true or false
end)

viewModeButton:SetScript("OnClick", function()
    if currentViewMode == "mob" then
        currentViewMode = "place"
        viewModeButton:SetText("Place")
    else
        currentViewMode = "mob"
        viewModeButton:SetText("Mob")
    end

    UpdateDisplay()
end)

toggleAllButton:SetScript("OnClick", function()

    EnsureDB()
    local profileMobs = GetProfileMobs()

    if currentViewMode == "place" then
        local anyExpanded = false

        for _, expanded in pairs(FarmingoDB.ui.expandedWorlds) do
            if expanded then
                anyExpanded = true
                break
            end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedContinents) do
                if expanded then
                    anyExpanded = true
                    break
                end
            end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedPlaces) do
                if expanded then
                    anyExpanded = true
                    break
                end
            end
        end

        if anyExpanded then
            FarmingoDB.ui.expandedWorlds = {}
            FarmingoDB.ui.expandedContinents = {}
            FarmingoDB.ui.expandedPlaces = {}
        else
            for _, data in pairs(profileMobs) do
                for placeKey in pairs(data.places or {}) do
                    local worldName, continentName, placeType = strsplit("|", placeKey)

                    if placeType == "zone" then
                        FarmingoDB.ui.expandedWorlds[worldName] = true
                        FarmingoDB.ui.expandedContinents[continentName] = true
                    elseif placeType == "dungeon" then
                        FarmingoDB.ui.expandedWorlds["Dungeons"] = true
                    elseif placeType == "raid" then
                        FarmingoDB.ui.expandedWorlds["Raids"] = true
                    end

                    FarmingoDB.ui.expandedPlaces[placeKey] = true
                end
            end
        end
    else
        if AreAnyMobsExpanded() then
            FarmingoDB.ui.expandedMobs = {}
        else
            for mobKey in pairs(profileMobs) do
                FarmingoDB.ui.expandedMobs[mobKey] = true
            end
        end
    end

    UpdateDisplay()
end)

searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:SetText(SEARCH_PLACEHOLDER)
    self:SetTextColor(0.6, 0.6, 0.6)
    searchQuery = ""
    isSearchOpen = false
    self:Hide()
    searchBoxBG:Hide()
    UpdateDisplay()
end)

searchBox:SetScript("OnEditFocusGained", function(self)
    if self:GetText() == SEARCH_PLACEHOLDER then
        self:SetText("")
        self:SetTextColor(1, 1, 1)
    end
end)

searchBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""

    if text == SEARCH_PLACEHOLDER then
        searchQuery = ""
        return
    end

    searchQuery = text:lower()
    UpdateDisplay()
end)

searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)

searchBox:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()

    if text == "" then
        self:SetText(SEARCH_PLACEHOLDER)
        self:SetTextColor(0.6, 0.6, 0.6)
    end
end)

searchButton:SetScript("OnClick", function()
    isSearchOpen = not isSearchOpen

    if isSearchOpen then
        searchBox:Show()
        searchBoxBG:Show()
        if searchBox:GetText() == SEARCH_PLACEHOLDER then
            searchBox:SetText("")
            searchBox:SetTextColor(1, 1, 1)
        end
        searchBox:SetFocus()
    else
        searchBox:ClearFocus()
        searchBox:SetText(SEARCH_PLACEHOLDER)
        searchBox:SetTextColor(0.6, 0.6, 0.6)
        searchQuery = ""
        searchBox:Hide()
        searchBoxBG:Hide()
    end

    UpdateDisplay()
end)

resizeButton:SetScript("OnMouseDown", function(self, button)
    EnsureDB()

    if button == "LeftButton" and not FarmingoDB.ui.locked then
        frame:StartSizing("BOTTOMRIGHT", true)
    end
end)

resizeButton:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()

    EnsureDB()
    FarmingoDB.ui.width = frame:GetWidth()
    FarmingoDB.ui.height = frame:GetHeight()

    UpdateDisplay()
end)

footerToggleButton:SetScript("OnClick", function()
    EnsureDB()
    FarmingoDB.ui.footerHidden = not FarmingoDB.ui.footerHidden
    RefreshFooterLayout()
    UpdateDisplay()
end)

createButton:SetScript("OnClick", function()
    StaticPopupDialogs["FARMINGO_CREATE_PROFILE"] = {
        text = "Enter profile name:",
        button1 = "Create",
        button2 = "Cancel",
        hasEditBox = true,
        maxLetters = 20,
        OnAccept = function(self)
            local text = self.EditBox:GetText()
            local ok, err = CreateProfile(text)
            if ok then
                SetCharacterProfile(text)
                RefreshSettingsUI()
                RefreshFooterLayout()
                UpdateDisplay()
                print("Farmingo: profile created and activated - " .. text)
            else
                print("Farmingo: " .. err)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopup_Show("FARMINGO_CREATE_PROFILE")
end)

UpdateToggleAllButton = function(profileMobs)
    if currentViewMode == "place" then
        local anyExpanded = false

        for _, expanded in pairs(FarmingoDB.ui.expandedWorlds or {}) do
            if expanded then
                anyExpanded = true
                break
            end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedContinents or {}) do
                if expanded then
                    anyExpanded = true
                    break
                end
            end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedPlaces or {}) do
                if expanded then
                    anyExpanded = true
                    break
                end
            end
        end

        if anyExpanded then
            toggleAllButton:SetText("Hide")
        else
            toggleAllButton:SetText("All")
        end
    else
        if AreAnyMobsExpanded() then
            toggleAllButton:SetText("Hide")
        else
            toggleAllButton:SetText("All")
        end
    end
end

UpdateFooterTotals = function(profileMobs)
    local totalGold = 0
    local totalLoots = 0
    local sessionTotalLoots = 0
    local sessionTotalGold = 0

    for mobKey, data in pairs(profileMobs) do
        totalGold = totalGold + (data.gold or 0)
        totalLoots = totalLoots + (data.lootCount or 0)

        local sessionData = FarmingoSession.mobs[mobKey]
        if sessionData then
            sessionTotalLoots = sessionTotalLoots + (sessionData.lootCount or 0)
            sessionTotalGold = sessionTotalGold + (sessionData.gold or 0)
        end
    end

    sessionValue:SetText(sessionTotalLoots)
    sessionGoldValue:SetText(FormatMoney(sessionTotalGold))
    totalLootsValue:SetText(totalLoots)
    totalGoldValue:SetText(FormatMoney(totalGold))
end

local function AddInfoRow(rowIndex, leftText, rightText)
    local row = GetRow(rowIndex)
    row:Show()
    row.isMobRow = false
    row.mobKey = nil
    row.itemLink = nil
    row.text:SetText(leftText or "")
    row.countText:SetText(rightText or "")
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    return rowIndex + 1
end

local function AddNoItemsRow(rowIndex, leftText)
    local row = GetRow(rowIndex)
    row:Show()
    row.isMobRow = false
    row.mobKey = nil
    row.itemLink = nil
    row.text:SetText(leftText or "|cff888888No items recorded|r")
    row.countText:SetText("")
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    return rowIndex + 1
end

local function AddItemRow(rowIndex, leftText, itemLink, firstDropLootCount, countText)
    local row = GetRow(rowIndex)
    row:Show()
    row.isMobRow = false
    row.mobKey = nil
    row.itemLink = itemLink
    row.firstDropLootCount = firstDropLootCount
    row.text:SetText(leftText or "")
    row.countText:SetText(countText or "")
    row:SetScript("OnClick", nil)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()

        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.highlight:Hide()
    end)

    return rowIndex + 1
end

RenderPlaceView = function(profileMobs, duplicateNameMap)
    local placeData = {
        zones = {},
        dungeons = {},
        raids = {},
    }

    for mobKey, data in pairs(profileMobs) do
        if MobMatchesSearch(mobKey, data) then
            for placeKey in pairs(data.places or {}) do
                local worldName, continentName, placeType, placeName = strsplit("|", placeKey)

                if placeType == "zone" then
                    placeData.zones[worldName] = placeData.zones[worldName] or {}

                    if worldName == continentName then
                        placeData.zones[worldName]["__FLAT__"] = placeData.zones[worldName]["__FLAT__"] or {}
                        placeData.zones[worldName]["__FLAT__"][placeKey] = placeData.zones[worldName]["__FLAT__"][placeKey] or {}
                        placeData.zones[worldName]["__FLAT__"][placeKey][mobKey] = data
                    else
                        placeData.zones[worldName][continentName] = placeData.zones[worldName][continentName] or {}
                        placeData.zones[worldName][continentName][placeKey] = placeData.zones[worldName][continentName][placeKey] or {}
                        placeData.zones[worldName][continentName][placeKey][mobKey] = data
                    end

                elseif placeType == "dungeon" then
                    placeData.dungeons[placeKey] = placeData.dungeons[placeKey] or {}
                    placeData.dungeons[placeKey][mobKey] = data

                elseif placeType == "raid" then
                    placeData.raids[placeKey] = placeData.raids[placeKey] or {}
                    placeData.raids[placeKey][mobKey] = data
                end
            end
        end
    end

    local worldKeys = {}
    for worldName in pairs(placeData.zones) do
        table.insert(worldKeys, worldName)
    end

    SortKeysByLootTotal(
        worldKeys,
        function(worldName)
            return GetNestedGroupedLootTotal(placeData.zones[worldName])
        end,
        function(worldName)
            return worldName
        end
    )

    local rowIndex = 1

    for _, worldName in ipairs(worldKeys) do
        local expandedWorld = FarmingoDB.ui.expandedWorlds[worldName]

        local worldTotalLoots = GetNestedGroupedLootTotal(placeData.zones[worldName])

        local worldRow = GetRow(rowIndex)
        worldRow:Show()
        worldRow.isMobRow = false
        worldRow.mobKey = nil
        worldRow.itemLink = nil
        worldRow.worldName = worldName
        worldRow.text:SetText((expandedWorld and "[-] " or "[+] ") .. COLOR_WORLD .. worldName .. COLOR_RESET)
        local lootWord = (worldTotalLoots == 1) and "loot" or "loots"
        worldRow.countText:SetText(worldTotalLoots .. " " .. lootWord)
        worldRow:SetScript("OnClick", function(self)
            EnsureDB()
            local key = self.worldName
            FarmingoDB.ui.expandedWorlds[key] = not FarmingoDB.ui.expandedWorlds[key]
            UpdateDisplay()
        end)
        worldRow:SetScript("OnEnter", function(self)
            self.highlight:Show()
        end)
        worldRow:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)

        rowIndex = rowIndex + 1

        if expandedWorld then
            local worldTotalGold = GetNestedGroupedGoldTotal(placeData.zones[worldName])

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(worldTotalGold))

            if placeData.zones[worldName]["__FLAT__"] then
                local placeKeys = {}
                for placeKey in pairs(placeData.zones[worldName]["__FLAT__"]) do
                    table.insert(placeKeys, placeKey)
                end

                SortKeysByLootTotal(
                    placeKeys,
                    function(placeKey)
                        return GetPlaceLootTotal(profileMobs, placeKey)
                    end,
                    function(placeKey)
                        return GetPlaceNameFromKey(placeKey)
                    end
                )

                for _, placeKey in ipairs(placeKeys) do
                    local _, _, placeType, placeName = strsplit("|", placeKey)
                    local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                    local placeTotalLoots = GetPlaceLootTotal(profileMobs, placeKey)

                    local placeRow = GetRow(rowIndex)
                    placeRow:Show()
                    placeRow.isMobRow = false
                    placeRow.mobKey = nil
                    placeRow.itemLink = nil
                    placeRow.placeKey = placeKey
                    placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                    placeRow.countText:SetText(placeTotalLoots .. " loots")
                    placeRow:SetScript("OnClick", function(self)
                        EnsureDB()
                        local key = self.placeKey
                        FarmingoDB.ui.expandedPlaces[key] = not FarmingoDB.ui.expandedPlaces[key]
                        UpdateDisplay()
                    end)
                    placeRow:SetScript("OnEnter", function(self)
                        self.highlight:Show()
                    end)
                    placeRow:SetScript("OnLeave", function(self)
                        self.highlight:Hide()
                    end)

                    rowIndex = rowIndex + 1

                    if expandedPlace then

                        local placeTotalGold = GetPlaceGoldTotal(profileMobs, placeKey)

                        rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(placeTotalGold))

                        local mobList = {}

                        for mobKey, mobData in pairs(placeData.zones[worldName]["__FLAT__"][placeKey]) do
                            local placeLootCount = 0
                            if mobData.places and mobData.places[placeKey] then
                                placeLootCount = mobData.places[placeKey]
                            end

                            table.insert(mobList, {
                                key = mobKey,
                                data = mobData,
                                count = placeLootCount
                            })
                        end

                        table.sort(mobList, function(a, b)
                            if a.count == b.count then
                                local nameA = GetSafeDisplayName(a.key, a.data.displayName)
                                local nameB = GetSafeDisplayName(b.key, b.data.displayName)
                                return nameA < nameB
                            end
                            return a.count > b.count
                        end)

                        for _, mob in ipairs(mobList) do
                            local mobKey = mob.key
                            local mobData = mob.data
                            local placeLootCount = mob.count

                            local mobRow = GetRow(rowIndex)
                            mobRow:Show()
                            mobRow.isMobRow = false
                            mobRow.mobKey = mobKey
                            mobRow.itemLink = nil

                            local expandedMob = FarmingoDB.ui.expandedMobs[mobKey]
                            local prefix = expandedMob and "        [-] " or "        [+] "
                            local mobDisplayName = GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                            if searchQuery ~= "" then
                                mobDisplayName = HighlightSearchMatch(mobDisplayName)
                            end

                            if IsFallbackMobName(mobDisplayName) then
                                mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                            else
                                mobRow.text:SetText(prefix .. mobDisplayName)
                            end

                            local lootWord = (placeLootCount == 1) and "loot" or "loots"
                            mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                            mobRow:SetScript("OnClick", function(self)
                                EnsureDB()
                                local key = self.mobKey
                                FarmingoDB.ui.expandedMobs[key] = not FarmingoDB.ui.expandedMobs[key]
                                UpdateDisplay()
                            end)
                            mobRow:SetScript("OnEnter", function(self)
                                self.highlight:Show()
                            end)
                            mobRow:SetScript("OnLeave", function(self)
                                self.highlight:Hide()
                            end)

                            rowIndex = rowIndex + 1

                            if expandedMob then
                                local itemNames = {}

                                for itemName in pairs(mobData.items or {}) do
                                    table.insert(itemNames, itemName)
                                end

                                table.sort(itemNames)

                                if #itemNames == 0 then
                                    rowIndex = AddNoItemsRow(rowIndex, "    |cff888888No items recorded|r")
                                else
                                    for _, itemName in ipairs(itemNames) do
                                        local itemData = mobData.items[itemName]

                                        local itemText = itemData.link or itemName
                                        if searchQuery ~= "" and not itemData.link then
                                            itemText = HighlightSearchMatch(itemText)
                                        end

                                        rowIndex = AddItemRow(
                                            rowIndex,
                                            "                " .. itemText,
                                            itemData.link,
                                            itemData.firstDropLootCount,
                                            "x" .. tostring(itemData.count or 0)
                                        )
                                    end
                                end

                                local mobGold = mobData.gold or 0
                                if mobGold > 0 then
                                    rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(mobGold))
                                end

                                local sessionData = FarmingoSession.mobs[mobKey]
                                local sessionLootCount = 0
                                local sessionGold = 0

                                if sessionData then
                                    sessionLootCount = sessionData.lootCount or 0
                                    sessionGold = sessionData.gold or 0
                                end

                                local sessionRow = GetRow(rowIndex)
                                sessionRow:Show()
                                sessionRow.isMobRow = false
                                sessionRow.mobKey = nil
                                sessionRow.itemLink = nil
                                sessionRow.text:SetText("    |cff66ccffThis session loots:|r")
                                sessionRow.countText:SetText("|cff66ccff" .. sessionLootCount .. " loots|r")
                                sessionRow:SetScript("OnClick", nil)
                                sessionRow:SetScript("OnEnter", nil)
                                sessionRow:SetScript("OnLeave", function(self)
                                    self.highlight:Hide()
                                end)

                                rowIndex = rowIndex + 1

                                if sessionGold > 0 then
                                    local sessionGoldRow = GetRow(rowIndex)
                                    sessionGoldRow:Show()
                                    sessionGoldRow.isMobRow = false
                                    sessionGoldRow.mobKey = nil
                                    sessionGoldRow.itemLink = nil
                                    sessionGoldRow.text:SetText("    |cff66ccffThis session gold:|r")
                                    sessionGoldRow.countText:SetText("|cffffffff" .. FormatMoney(sessionGold) .. "|r")
                                    sessionGoldRow:SetScript("OnClick", nil)
                                    sessionGoldRow:SetScript("OnEnter", nil)
                                    sessionGoldRow:SetScript("OnLeave", function(self)
                                        self.highlight:Hide()
                                    end)

                                    rowIndex = rowIndex + 1
                                end
                            end
                        end
                    end
                end
            end
            local continentKeys = {}
            for continentName in pairs(placeData.zones[worldName]) do
                if continentName ~= "__FLAT__" then
                    table.insert(continentKeys, continentName)
                end
            end

            SortKeysByLootTotal(
                continentKeys,
                function(continentName)
                    return GetGroupedLootTotal(placeData.zones[worldName][continentName])
                end,
                function(continentName)
                    return continentName
                end
            )

            for _, continentName in ipairs(continentKeys) do
                local expandedContinent = FarmingoDB.ui.expandedContinents[continentName]

                local continentTotalLoots = GetGroupedLootTotal(placeData.zones[worldName][continentName])

                local continentRow = GetRow(rowIndex)
                continentRow:Show()
                continentRow.isMobRow = false
                continentRow.mobKey = nil
                continentRow.itemLink = nil
                continentRow.continentName = continentName
                continentRow.text:SetText("    " .. (expandedContinent and "[-] " or "[+] ") .. COLOR_CONTINENT .. continentName .. COLOR_RESET)
                continentRow.countText:SetText(continentTotalLoots .. " loots")
                continentRow:SetScript("OnClick", function(self)
                    EnsureDB()
                    local key = self.continentName
                    FarmingoDB.ui.expandedContinents[key] = not FarmingoDB.ui.expandedContinents[key]
                    UpdateDisplay()
                end)
                continentRow:SetScript("OnEnter", function(self)
                    self.highlight:Show()
                end)
                continentRow:SetScript("OnLeave", function(self)
                    self.highlight:Hide()
                end)

                rowIndex = rowIndex + 1

                if expandedContinent then

                    local continentTotalGold = GetGroupedGoldTotal(placeData.zones[worldName][continentName])

                    rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(continentTotalGold))

                    local placeKeys = {}
                    for placeKey in pairs(placeData.zones[worldName][continentName]) do
                        table.insert(placeKeys, placeKey)
                    end

                    SortKeysByLootTotal(
                        placeKeys,
                        function(placeKey)
                            return GetPlaceLootTotal(profileMobs, placeKey)
                        end,
                        function(placeKey)
                            return GetPlaceNameFromKey(placeKey)
                        end
                    )

                    for _, placeKey in ipairs(placeKeys) do
                        local _, _, placeType, placeName = strsplit("|", placeKey)
                        local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                        local placeTotalLoots = GetPlaceLootTotal(profileMobs, placeKey)

                        local placeRow = GetRow(rowIndex)
                        placeRow:Show()
                        placeRow.isMobRow = false
                        placeRow.mobKey = nil
                        placeRow.itemLink = nil
                        placeRow.placeKey = placeKey
                        placeRow.text:SetText("        " .. (expandedPlace and "[-] " or "[+] ") .. COLOR_PLACE .. (placeName or placeKey) .. COLOR_RESET)
                        placeRow.countText:SetText(placeTotalLoots .. " loots")
                        placeRow:SetScript("OnClick", function(self)
                            EnsureDB()
                            local key = self.placeKey
                            FarmingoDB.ui.expandedPlaces[key] = not FarmingoDB.ui.expandedPlaces[key]
                            UpdateDisplay()
                        end)
                        placeRow:SetScript("OnEnter", function(self)
                            self.highlight:Show()
                        end)
                        placeRow:SetScript("OnLeave", function(self)
                            self.highlight:Hide()
                        end)

                        rowIndex = rowIndex + 1

                        if expandedPlace then

                            local placeTotalGold = GetPlaceGoldTotal(profileMobs, placeKey)

                            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(placeTotalGold))

                            local mobList = {}
                            for mobKey, mobData in pairs(placeData.zones[worldName][continentName][placeKey]) do
                                local placeLootCount = 0
                                if mobData.places and mobData.places[placeKey] then
                                    placeLootCount = mobData.places[placeKey]
                                end

                                table.insert(mobList, {
                                    key = mobKey,
                                    data = mobData,
                                    count = placeLootCount
                                })
                            end

                            table.sort(mobList, function(a, b)
                                if a.count == b.count then
                                    local nameA = GetSafeDisplayName(a.key, a.data.displayName)
                                    local nameB = GetSafeDisplayName(b.key, b.data.displayName)
                                    return nameA < nameB
                                end
                                return a.count > b.count
                            end)

                            for _, mob in ipairs(mobList) do
                                local mobKey = mob.key
                                local mobData = mob.data
                                local placeLootCount = mob.count

                                local mobRow = GetRow(rowIndex)
                                mobRow:Show()
                                mobRow.isMobRow = false
                                mobRow.mobKey = mobKey
                                mobRow.itemLink = nil

                                local expandedMob = FarmingoDB.ui.expandedMobs[mobKey]
                                local prefix = expandedMob and "            [-] " or "            [+] "
                                local mobDisplayName = GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                                if searchQuery ~= "" then
                                    mobDisplayName = HighlightSearchMatch(mobDisplayName)
                                end

                                if IsFallbackMobName(mobDisplayName) then
                                    mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                                else
                                    mobRow.text:SetText(prefix .. COLOR_MOB .. mobDisplayName .. COLOR_RESET)
                                end

                                local lootWord = (placeLootCount == 1) and "loot" or "loots"
                                mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                                mobRow:SetScript("OnClick", function(self)
                                    EnsureDB()
                                    local key = self.mobKey
                                    FarmingoDB.ui.expandedMobs[key] = not FarmingoDB.ui.expandedMobs[key]
                                    UpdateDisplay()
                                end)
                                mobRow:SetScript("OnEnter", function(self)
                                    self.highlight:Show()
                                end)
                                mobRow:SetScript("OnLeave", function(self)
                                    self.highlight:Hide()
                                end)

                                rowIndex = rowIndex + 1

                                if expandedMob then
                                    local itemNames = {}

                                    for itemName in pairs(mobData.items or {}) do
                                        table.insert(itemNames, itemName)
                                    end

                                    table.sort(itemNames)

                                    if #itemNames == 0 then
                                        rowIndex = AddNoItemsRow(rowIndex, "    |cff888888No items recorded|r")
                                    else
                                        for _, itemName in ipairs(itemNames) do
                                            local itemData = mobData.items[itemName]

                                            local itemText = itemData.link or itemName
                                            if searchQuery ~= "" and not itemData.link then
                                                itemText = HighlightSearchMatch(itemText)
                                            end

                                            rowIndex = AddItemRow(
                                                rowIndex,
                                                "                " .. itemText,
                                                itemData.link,
                                                itemData.firstDropLootCount,
                                                "x" .. tostring(itemData.count or 0)
                                            )
                                        end
                                    end

                                    local mobGold = mobData.gold or 0
                                    if mobGold > 0 then
                                        rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(mobGold))
                                    end

                                    local sessionData = FarmingoSession.mobs[mobKey]
                                    local sessionLootCount = 0
                                    local sessionGold = 0

                                    if sessionData then
                                        sessionLootCount = sessionData.lootCount or 0
                                        sessionGold = sessionData.gold or 0
                                    end

                                    local sessionRow = GetRow(rowIndex)
                                    sessionRow:Show()
                                    sessionRow.isMobRow = false
                                    sessionRow.mobKey = nil
                                    sessionRow.itemLink = nil
                                    sessionRow.text:SetText("    |cff66ccffThis session loots:|r")
                                    sessionRow.countText:SetText("|cff66ccff" .. sessionLootCount .. " loots|r")
                                    sessionRow:SetScript("OnClick", nil)
                                    sessionRow:SetScript("OnEnter", nil)
                                    sessionRow:SetScript("OnLeave", function(self)
                                        self.highlight:Hide()
                                    end)

                                    rowIndex = rowIndex + 1

                                    if sessionGold > 0 then
                                        local sessionGoldRow = GetRow(rowIndex)
                                        sessionGoldRow:Show()
                                        sessionGoldRow.isMobRow = false
                                        sessionGoldRow.mobKey = nil
                                        sessionGoldRow.itemLink = nil
                                        sessionGoldRow.text:SetText("    |cff66ccffThis session gold:|r")
                                        sessionGoldRow.countText:SetText("|cffffffff" .. FormatMoney(sessionGold) .. "|r")
                                        sessionGoldRow:SetScript("OnClick", nil)
                                        sessionGoldRow:SetScript("OnEnter", nil)
                                        sessionGoldRow:SetScript("OnLeave", function(self)
                                            self.highlight:Hide()
                                        end)

                                        rowIndex = rowIndex + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local dungeonKeys = {}
    for placeKey in pairs(placeData.dungeons) do
        table.insert(dungeonKeys, placeKey)
    end

    SortKeysByLootTotal(
        dungeonKeys,
        function(placeKey)
            return GetGroupedLootTotal({
                [placeKey] = placeData.dungeons[placeKey]
            })
        end,
        function(placeKey)
            return GetPlaceNameFromKey(placeKey)
        end
    )

    if #dungeonKeys > 0 then
        local expandedDungeons = FarmingoDB.ui.expandedWorlds["Dungeons"]

        local dungeonsTotalLoots = 0
        for _, placeKey in ipairs(dungeonKeys) do
            dungeonsTotalLoots = dungeonsTotalLoots + GetGroupedLootTotal({
                [placeKey] = placeData.dungeons[placeKey]
            })
        end

        local dungeonsRow = GetRow(rowIndex)
        dungeonsRow:Show()
        dungeonsRow.isMobRow = false
        dungeonsRow.mobKey = nil
        dungeonsRow.itemLink = nil
        dungeonsRow.worldName = "Dungeons"
        dungeonsRow.text:SetText((expandedDungeons and "[-] " or "[+] ") .. "Dungeons")
        dungeonsRow.countText:SetText(dungeonsTotalLoots .. " loots")
        dungeonsRow:SetScript("OnClick", function(self)
            EnsureDB()
            FarmingoDB.ui.expandedWorlds["Dungeons"] = not FarmingoDB.ui.expandedWorlds["Dungeons"]
            UpdateDisplay()
        end)
        dungeonsRow:SetScript("OnEnter", function(self)
            self.highlight:Show()
        end)
        dungeonsRow:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)

        rowIndex = rowIndex + 1

        if expandedDungeons then

            local dungeonsTotalGold = 0
            for _, placeKey in ipairs(dungeonKeys) do
                dungeonsTotalGold = dungeonsTotalGold + GetGroupedGoldTotal({
                    [placeKey] = placeData.dungeons[placeKey]
                })
            end

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(dungeonsTotalGold))

            for _, placeKey in ipairs(dungeonKeys) do
                local _, _, _, placeName = strsplit("|", placeKey)
                local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                local placeTotalLoots = GetPlaceLootTotal(profileMobs, placeKey)

                local placeRow = GetRow(rowIndex)
                placeRow:Show()
                placeRow.isMobRow = false
                placeRow.mobKey = nil
                placeRow.itemLink = nil
                placeRow.placeKey = placeKey
                placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                placeRow.countText:SetText(placeTotalLoots .. " loots")
                placeRow:SetScript("OnClick", function(self)
                    EnsureDB()
                    FarmingoDB.ui.expandedPlaces[self.placeKey] = not FarmingoDB.ui.expandedPlaces[self.placeKey]
                    UpdateDisplay()
                end)
                placeRow:SetScript("OnEnter", function(self)
                    self.highlight:Show()
                end)
                placeRow:SetScript("OnLeave", function(self)
                    self.highlight:Hide()
                end)

                rowIndex = rowIndex + 1

                if expandedPlace then

                    local placeTotalGold = GetPlaceGoldTotal(profileMobs, placeKey)

                    rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(placeTotalGold))

                    local mobList = {}

                    for mobKey, mobData in pairs(placeData.dungeons[placeKey]) do
                        local placeLootCount = 0
                        if mobData.places and mobData.places[placeKey] then
                            placeLootCount = mobData.places[placeKey]
                        end

                        table.insert(mobList, {
                            key = mobKey,
                            data = mobData,
                            count = placeLootCount
                        })
                    end

                    table.sort(mobList, function(a, b)
                        if a.count == b.count then
                            local nameA = GetSafeDisplayName(a.key, a.data.displayName)
                            local nameB = GetSafeDisplayName(b.key, b.data.displayName)
                            return nameA < nameB
                        end
                        return a.count > b.count
                    end)

                    for _, mob in ipairs(mobList) do
                        local mobKey = mob.key
                        local mobData = mob.data
                        local placeLootCount = mob.count

                        local mobRow = GetRow(rowIndex)
                        mobRow:Show()
                        mobRow.isMobRow = false
                        mobRow.mobKey = mobKey
                        mobRow.itemLink = nil

                        local expandedMob = FarmingoDB.ui.expandedMobs[mobKey]
                        local prefix = expandedMob and "        [-] " or "        [+] "
                        local mobDisplayName = GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                        if searchQuery ~= "" then
                            mobDisplayName = HighlightSearchMatch(mobDisplayName)
                        end

                        if IsFallbackMobName(mobDisplayName) then
                            mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                        else
                            mobRow.text:SetText(prefix .. mobDisplayName)
                        end

                        local lootWord = (placeLootCount == 1) and "loot" or "loots"
                        mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                        mobRow:SetScript("OnClick", function(self)
                            EnsureDB()
                            FarmingoDB.ui.expandedMobs[self.mobKey] = not FarmingoDB.ui.expandedMobs[self.mobKey]
                            UpdateDisplay()
                        end)
                        mobRow:SetScript("OnEnter", function(self)
                            self.highlight:Show()
                        end)
                        mobRow:SetScript("OnLeave", function(self)
                            self.highlight:Hide()
                        end)

                        rowIndex = rowIndex + 1

                        if expandedMob then
                            local itemNames = {}

                            for itemName in pairs(mobData.items or {}) do
                                table.insert(itemNames, itemName)
                            end

                            table.sort(itemNames)

                            if #itemNames == 0 then
                                rowIndex = AddNoItemsRow(rowIndex, "    |cff888888No items recorded|r")
                            else
                                for _, itemName in ipairs(itemNames) do
                                    local itemData = mobData.items[itemName]

                                    local itemText = itemData.link or itemName
                                    if searchQuery ~= "" and not itemData.link then
                                        itemText = HighlightSearchMatch(itemText)
                                    end

                                    rowIndex = AddItemRow(
                                        rowIndex,
                                        "            " .. itemText,
                                        itemData.link,
                                        itemData.firstDropLootCount,
                                        "x" .. tostring(itemData.count or 0)
                                    )
                                end
                            end

                            local mobGold = mobData.gold or 0
                            if mobGold > 0 then
                                rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(mobGold))
                            end

                            local sessionData = FarmingoSession.mobs[mobKey]
                            local sessionLootCount = 0
                            local sessionGold = 0

                            if sessionData then
                                sessionLootCount = sessionData.lootCount or 0
                                sessionGold = sessionData.gold or 0
                            end

                            local sessionRow = GetRow(rowIndex)
                            sessionRow:Show()
                            sessionRow.isMobRow = false
                            sessionRow.mobKey = nil
                            sessionRow.itemLink = nil
                            sessionRow.text:SetText("    |cff66ccffThis session loots:|r")
                            sessionRow.countText:SetText("|cff66ccff" .. sessionLootCount .. " loots|r")
                            sessionRow:SetScript("OnClick", nil)
                            sessionRow:SetScript("OnEnter", nil)
                            sessionRow:SetScript("OnLeave", function(self)
                                self.highlight:Hide()
                            end)

                            rowIndex = rowIndex + 1

                            if sessionGold > 0 then
                                local sessionGoldRow = GetRow(rowIndex)
                                sessionGoldRow:Show()
                                sessionGoldRow.isMobRow = false
                                sessionGoldRow.mobKey = nil
                                sessionGoldRow.itemLink = nil
                                sessionGoldRow.text:SetText("    |cff66ccffThis session gold:|r")
                                sessionGoldRow.countText:SetText("|cffffffff" .. FormatMoney(sessionGold) .. "|r")
                                sessionGoldRow:SetScript("OnClick", nil)
                                sessionGoldRow:SetScript("OnEnter", nil)
                                sessionGoldRow:SetScript("OnLeave", function(self)
                                    self.highlight:Hide()
                                end)

                                rowIndex = rowIndex + 1
                            end
                        end
                    end
                end
            end
        end
    end

    local raidKeys = {}
    for placeKey in pairs(placeData.raids) do
        table.insert(raidKeys, placeKey)
    end

    SortKeysByLootTotal(
        raidKeys,
        function(placeKey)
            return GetGroupedLootTotal({
                [placeKey] = placeData.raids[placeKey]
            })
        end,
        function(placeKey)
            return GetPlaceNameFromKey(placeKey)
        end
    )

    if #raidKeys > 0 then
        local expandedRaids = FarmingoDB.ui.expandedWorlds["Raids"]

        local raidsTotalLoots = 0
        for _, placeKey in ipairs(raidKeys) do
            raidsTotalLoots = raidsTotalLoots + GetGroupedLootTotal({
                [placeKey] = placeData.raids[placeKey]
            })
        end

        local raidsRow = GetRow(rowIndex)
        raidsRow:Show()
        raidsRow.isMobRow = false
        raidsRow.mobKey = nil
        raidsRow.itemLink = nil
        raidsRow.worldName = "Raids"
        raidsRow.text:SetText((expandedRaids and "[-] " or "[+] ") .. "Raids")
        raidsRow.countText:SetText(raidsTotalLoots .. " loots")
        raidsRow:SetScript("OnClick", function(self)
            EnsureDB()
            FarmingoDB.ui.expandedWorlds["Raids"] = not FarmingoDB.ui.expandedWorlds["Raids"]
            UpdateDisplay()
        end)
        raidsRow:SetScript("OnEnter", function(self)
            self.highlight:Show()
        end)
        raidsRow:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)

        rowIndex = rowIndex + 1

        if expandedRaids then

            local raidsTotalGold = 0
            for _, placeKey in ipairs(raidKeys) do
                raidsTotalGold = raidsTotalGold + GetGroupedGoldTotal({
                    [placeKey] = placeData.raids[placeKey]
                })
            end

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(raidsTotalGold))

            for _, placeKey in ipairs(raidKeys) do
                local _, _, _, placeName = strsplit("|", placeKey)
                local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                local placeTotalLoots = GetPlaceLootTotal(profileMobs, placeKey)

                local placeRow = GetRow(rowIndex)
                placeRow:Show()
                placeRow.isMobRow = false
                placeRow.mobKey = nil
                placeRow.itemLink = nil
                placeRow.placeKey = placeKey
                placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                placeRow.countText:SetText(placeTotalLoots .. " loots")
                placeRow:SetScript("OnClick", function(self)
                    EnsureDB()
                    FarmingoDB.ui.expandedPlaces[self.placeKey] = not FarmingoDB.ui.expandedPlaces[self.placeKey]
                    UpdateDisplay()
                end)
                placeRow:SetScript("OnEnter", function(self)
                    self.highlight:Show()
                end)
                placeRow:SetScript("OnLeave", function(self)
                    self.highlight:Hide()
                end)

                rowIndex = rowIndex + 1

                if expandedPlace then

                    local placeTotalGold = GetPlaceGoldTotal(profileMobs, placeKey)

                    rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(placeTotalGold))

                    local mobList = {}

                    for mobKey, mobData in pairs(placeData.raids[placeKey]) do
                        local placeLootCount = 0
                        if mobData.places and mobData.places[placeKey] then
                            placeLootCount = mobData.places[placeKey]
                        end

                        table.insert(mobList, {
                            key = mobKey,
                            data = mobData,
                            count = placeLootCount
                        })
                    end

                    table.sort(mobList, function(a, b)
                        if a.count == b.count then
                            local nameA = GetSafeDisplayName(a.key, a.data.displayName)
                            local nameB = GetSafeDisplayName(b.key, b.data.displayName)
                            return nameA < nameB
                        end
                        return a.count > b.count
                    end)

                    for _, mob in ipairs(mobList) do
                        local mobKey = mob.key
                        local mobData = mob.data
                        local placeLootCount = mob.count

                        local mobRow = GetRow(rowIndex)
                        mobRow:Show()
                        mobRow.isMobRow = false
                        mobRow.mobKey = mobKey
                        mobRow.itemLink = nil

                        local expandedMob = FarmingoDB.ui.expandedMobs[mobKey]
                        local prefix = expandedMob and "        [-] " or "        [+] "
                        local mobDisplayName = GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                        if searchQuery ~= "" then
                            mobDisplayName = HighlightSearchMatch(mobDisplayName)
                        end

                        if IsFallbackMobName(mobDisplayName) then
                            mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                        else
                            mobRow.text:SetText(prefix .. mobDisplayName)
                        end

                        local lootWord = (placeLootCount == 1) and "loot" or "loots"
                        mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                        mobRow:SetScript("OnClick", function(self)
                            EnsureDB()
                            FarmingoDB.ui.expandedMobs[self.mobKey] = not FarmingoDB.ui.expandedMobs[self.mobKey]
                            UpdateDisplay()
                        end)
                        mobRow:SetScript("OnEnter", function(self)
                            self.highlight:Show()
                        end)
                        mobRow:SetScript("OnLeave", function(self)
                            self.highlight:Hide()
                        end)

                        rowIndex = rowIndex + 1

                        if expandedMob then
                            local itemNames = {}

                            for itemName in pairs(mobData.items or {}) do
                                table.insert(itemNames, itemName)
                            end

                            table.sort(itemNames)

                            if #itemNames == 0 then
                                rowIndex = AddNoItemsRow(rowIndex, "    |cff888888No items recorded|r")
                            else
                                for _, itemName in ipairs(itemNames) do
                                    local itemData = mobData.items[itemName]

                                    local itemText = itemData.link or itemName
                                    if searchQuery ~= "" and not itemData.link then
                                        itemText = HighlightSearchMatch(itemText)
                                    end

                                    rowIndex = AddItemRow(
                                        rowIndex,
                                        "            " .. itemText,
                                        itemData.link,
                                        itemData.firstDropLootCount,
                                        "x" .. tostring(itemData.count or 0)
                                    )
                                end
                            end

                            local mobGold = mobData.gold or 0
                            if mobGold > 0 then
                                rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(mobGold))
                            end

                            local sessionData = FarmingoSession.mobs[mobKey]
                            local sessionLootCount = 0
                            local sessionGold = 0

                            if sessionData then
                                sessionLootCount = sessionData.lootCount or 0
                                sessionGold = sessionData.gold or 0
                            end

                            local sessionRow = GetRow(rowIndex)
                            sessionRow:Show()
                            sessionRow.isMobRow = false
                            sessionRow.mobKey = nil
                            sessionRow.itemLink = nil
                            sessionRow.text:SetText("    |cff66ccffThis session loots:|r")
                            sessionRow.countText:SetText("|cff66ccff" .. sessionLootCount .. " loots|r")
                            sessionRow:SetScript("OnClick", nil)
                            sessionRow:SetScript("OnEnter", nil)
                            sessionRow:SetScript("OnLeave", function(self)
                                self.highlight:Hide()
                            end)

                            rowIndex = rowIndex + 1

                            if sessionGold > 0 then
                                local sessionGoldRow = GetRow(rowIndex)
                                sessionGoldRow:Show()
                                sessionGoldRow.isMobRow = false
                                sessionGoldRow.mobKey = nil
                                sessionGoldRow.itemLink = nil
                                sessionGoldRow.text:SetText("    |cff66ccffThis session gold:|r")
                                sessionGoldRow.countText:SetText("|cffffffff" .. FormatMoney(sessionGold) .. "|r")
                                sessionGoldRow:SetScript("OnClick", nil)
                                sessionGoldRow:SetScript("OnEnter", nil)
                                sessionGoldRow:SetScript("OnLeave", function(self)
                                    self.highlight:Hide()
                                end)

                                rowIndex = rowIndex + 1
                            end
                        end
                    end
                end
            end
        end
    end

    for i = rowIndex, #rows do
        rows[i]:Hide()
        rows[i]:SetScript("OnClick", nil)
    end

    local totalHeight = math.max((rowIndex - 1) * ROW_HEIGHT, 1)
    content:SetWidth(frame:GetWidth() - 40)
    content:SetSize(frame:GetWidth() - 40, totalHeight)

    return
end

RenderMobView = function(profileMobs, duplicateNameMap)
    local mobList = {}
    for mobKey, data in pairs(profileMobs) do
        if MobMatchesSearch(mobKey, data) then
            table.insert(mobList, {
                key = mobKey,
                data = data,
                count = data.lootCount or 0
            })
        end
    end

    table.sort(mobList, function(a, b)
        if a.count == b.count then
            local nameA = GetSafeDisplayName(a.key, a.data.displayName)
            local nameB = GetSafeDisplayName(b.key, b.data.displayName)
            return nameA < nameB
        end
        return a.count > b.count
    end)

    local rowIndex = 1

    if #mobList == 0 then
        local row = GetRow(rowIndex)
        row:Show()
        row.isMobRow = false
        row.mobName = nil
        row.text:SetText("No loot recorded yet.")
        row.countText:SetText("")
        row:SetScript("OnClick", nil)
            row.itemLink = nil
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)
        rowIndex = rowIndex + 1
    else
        for _, mob in ipairs(mobList) do
            local mobKey = mob.key
            local data = mob.data
            local displayName = GetDisplayNameWithDuplicateSuffix(mobKey, data.displayName, duplicateNameMap)
            local lootCount = data.lootCount or 0
            local expanded = FarmingoDB.ui.expandedMobs[mobKey]

            local mobRow = GetRow(rowIndex)
            mobRow:Show()
            mobRow.isMobRow = true
            mobRow.mobKey = mobKey
            local rowName = displayName

            if searchQuery ~= "" then
                rowName = HighlightSearchMatch(rowName)
            end

            if IsFallbackMobName(displayName) then
                rowName = "|cff999999" .. rowName .. "|r"
            end

            mobRow.text:SetText((expanded and "[-] " or "[+] ") .. rowName)
            mobRow.countText:SetText(lootCount .. " loots")
            mobRow.itemLink = nil
            mobRow:SetScript("OnEnter", function(self)
                self.highlight:Show()
            end)
            mobRow:SetScript("OnLeave", function(self)
                self.highlight:Hide()
            end)

            mobRow:SetScript("OnClick", function(self)
                EnsureDB()
                local key = self.mobKey
                FarmingoDB.ui.expandedMobs[key] = not FarmingoDB.ui.expandedMobs[key]
                UpdateDisplay()
            end)

            rowIndex = rowIndex + 1

            if expanded then

                local itemNames = {}
                for itemName in pairs(data.items or {}) do
                    table.insert(itemNames, itemName)
                end
                table.sort(itemNames)

                if #itemNames == 0 then
                    rowIndex = AddNoItemsRow(rowIndex, "      |cff888888No items recorded|r")
                else
                    for _, itemName in ipairs(itemNames) do
                        local itemData = data.items[itemName]

                        local itemText = itemData.link or itemName
                        if searchQuery ~= "" and not itemData.link then
                            itemText = HighlightSearchMatch(itemText)
                        end

                        rowIndex = AddItemRow(
                            rowIndex,
                            "      " .. itemText,
                            itemData.link,
                            itemData.firstDropLootCount,
                            "x" .. tostring(itemData.count or 0)
                        )
                    end
                end

                    local mobGold = data.gold or 0
                    if mobGold > 0 then
                        rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", FormatMoney(mobGold))
                    end

                    local sessionData = FarmingoSession.mobs[mobKey]
                    local sessionLootCount = 0
                    local sessionGold = 0

                    if sessionData then
                        sessionLootCount = sessionData.lootCount or 0
                        sessionGold = sessionData.gold or 0
                    end

                    local sessionRow = GetRow(rowIndex)
                    sessionRow:Show()
                    sessionRow.isMobRow = false
                    sessionRow.mobName = nil
                    sessionRow.itemLink = nil
                    sessionRow.text:SetText("    |cff66ccffThis session loots:|r")
                    sessionRow.countText:SetText("|cff66ccff" .. sessionLootCount .. " loots|r")
                    sessionRow:SetScript("OnClick", nil)
                    sessionRow:SetScript("OnEnter", nil)
                    sessionRow:SetScript("OnLeave", function(self)
                        self.highlight:Hide()
                    end)
                    rowIndex = rowIndex + 1

                    if sessionGold > 0 then
                        local sessionGoldRow = GetRow(rowIndex)
                        sessionGoldRow:Show()
                        sessionGoldRow.isMobRow = false
                        sessionGoldRow.mobName = nil
                        sessionGoldRow.itemLink = nil
                        sessionGoldRow.text:SetText("    |cff66ccffThis session gold:|r")
                        sessionGoldRow.countText:SetText("|cffffffff" .. FormatMoney(sessionGold) .. "|r")
                        sessionGoldRow:SetScript("OnClick", nil)
                        sessionGoldRow:SetScript("OnEnter", nil)
                        sessionGoldRow:SetScript("OnLeave", function(self)
                            self.highlight:Hide()
                        end)
                        rowIndex = rowIndex + 1
                    end
                    local places = data.places or {}
                    local topPlaceKey = nil
                    local topPlaceCount = 0

                    for placeKey, count in pairs(places) do
                        if count > topPlaceCount then
                            topPlaceKey = placeKey
                            topPlaceCount = count
                        end
                    end

                    if topPlaceKey then
                        local worldName, continentName, placeType, placeName = strsplit("|", topPlaceKey)

                        local placeLabel = placeName or topPlaceKey

                        local placeRow = GetRow(rowIndex)
                        placeRow:Show()
                        placeRow.isMobRow = false
                        placeRow.mobKey = nil
                        placeRow.itemLink = nil
                        placeRow.text:SetText("    |cff88ccffSeen in:|r " .. placeLabel)
                        placeRow.countText:SetText(topPlaceCount)
                        placeRow:SetScript("OnClick", nil)
                        placeRow:SetScript("OnEnter", nil)
                        placeRow:SetScript("OnLeave", function(self)
                            self.highlight:Hide()
                        end)

                        rowIndex = rowIndex + 1
                    end
                end
            end
        end

    for i = rowIndex, #rows do
        rows[i]:Hide()
        rows[i]:SetScript("OnClick", nil)
    end

    local totalHeight = math.max((rowIndex - 1) * ROW_HEIGHT, 1)
    content:SetWidth(frame:GetWidth() - 40)
    content:SetSize(frame:GetWidth() - 40, totalHeight)
end

UpdateDisplay = function()
    EnsureDB()

    local duplicateNameMap = BuildDuplicateMobNameMap()
    local profileMobs = GetProfileMobs()

    UpdateToggleAllButton(profileMobs)
    UpdateFooterTotals(profileMobs)

    if currentViewMode == "place" then
        RenderPlaceView(profileMobs, duplicateNameMap)
    else
        RenderMobView(profileMobs, duplicateNameMap)
    end
end

-- ============================================================================
-- 11. Event registration and event handler
-- ============================================================================

frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_SLOT_CLEARED")
frame:RegisterEvent("LOOT_CLOSED")

frame:SetScript("OnDragStart", function(self)
    EnsureDB()
    if not FarmingoDB.ui.locked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == ADDON_NAME then
            EnsureDB()
            FarmingoSession = {
                mobs = {}
            }

            if not minimapRegistered then
                icon:Register("Farmingo", ldb, FarmingoDB.ui.minimap)
                minimapRegistered = true
            end

            if FarmingoDB.ui.minimap.hide then
                icon:Hide("Farmingo")
            else
                icon:Show("Farmingo")
            end

            RefreshSettingsUI()
            RefreshFooterLayout()
            UpdateDisplay()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        RememberMob("target")

    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        RememberMob("mouseover")
    
    elseif event == "NAME_PLATE_UNIT_ADDED" then
    local unit = ...
    RememberMob(unit)

    elseif event == "LOOT_OPENED" then
        local autoLoot = ...
        CurrentLootWasAuto = autoLoot and true or false
        BuildPendingLoot()

    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        ProcessClearedLootSlot(slot)

    elseif event == "LOOT_CLOSED" then
        if next(AttemptedLootSlots) then
            ProcessAttemptedPendingLootSlots()
        elseif CurrentLootWasAuto and next(PendingLootSlots) then
            ProcessAllPendingLootSlots()
        end

        ClearPendingLoot()
        CurrentLootWasAuto = false
    end
end)

-- ============================================================================
-- 12. Tooltip hook
-- ============================================================================

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not tooltip or not data then
        return
    end
        
    EnsureDB()
    if not FarmingoDB.ui.tooltipEnabled then
        return
    end

    local itemID = data.id
    local itemLink = data.hyperlink

    AddFarmingoTooltipLine(tooltip, itemLink, itemID)
    tooltip:Show()
end)

-- ============================================================================
-- 13. Slash commands
-- ============================================================================

SLASH_FARMINGO1 = "/ft"

SLASH_FARMDEBUG1 = "/farmdebug"
SlashCmdList["FARMDEBUG"] = function()
    EnsureDB()

    print("---- Farmingo Debug Places ----")

    for key, data in pairs(FarmingoDB.debugPlaces or {}) do
        print(
            key,
            "| Zone:", data.zoneName,
            "| Auto:", data.autoZoneName,
            "| World:", data.worldName,
            "| Continent:", data.continentName,
            "| Type:", data.placeType
        )
    end
end

SlashCmdList["FARMINGO"] = function(msg)
    msg = msg or ""
    local trimmedMsg = strtrim(msg)
    local lowerMsg = trimmedMsg:lower()

    if lowerMsg ~= "reset" and lowerMsg ~= "confirmreset" then
        pendingReset = false
    end

    if lowerMsg == "profile" then
        print("Farmingo current profile: " .. GetActiveProfileName())
        return
    end

    if lowerMsg == "profiles" then
        local names = GetSortedProfileNames()
        print("Farmingo profiles: " .. table.concat(names, ", "))
        return
    end

    local createName = trimmedMsg:match("^profile%s+create%s+(.+)$")
    if createName then
        local ok, err = CreateProfile(createName)
        if ok then
            print("Farmingo: profile created - " .. createName)
        else
            print("Farmingo: " .. err)
        end
        return
    end

    local deleteName = trimmedMsg:match("^profile%s+delete%s+(.+)$")
    if deleteName then
        local ok, err = DeleteProfile(deleteName)
        if ok then
            RefreshSettingsUI()
            print("Farmingo: profile deleted - " .. deleteName)
        else
            print("Farmingo: " .. err)
        end
        return
    end

    local useName = trimmedMsg:match("^profile%s+use%s+(.+)$")
    if useName then
        local ok, err = SetCharacterProfile(useName)
        if ok then
            RefreshSettingsUI()
            RefreshFooterLayout()
            UpdateDisplay()
            print("Farmingo: active profile set to " .. useName)
        else
            print("Farmingo: " .. err)
        end
        return
    end

    if lowerMsg == "show" then
        frame:Show()
        print("Farmingo: shown.")
    elseif lowerMsg == "hide" then
        frame:Hide()
        print("Farmingo: hidden.")
    elseif lowerMsg == "reset" then
        pendingReset = true
        print("Farmingo: type /ft confirmreset to delete ALL saved data. OR /ft show to cancel")

    elseif lowerMsg == "confirmreset" then
        if pendingReset then
            local oldUI = FarmingoDB.ui or {}
            FarmingoDB = {
                profiles = {
                    ["Default"] = {
                        mobs = {},
                        mobNamesByKey = {},
                    },
                },
                characterProfile = {},
                debugPlaces = {},
                ui = {
                    locked = oldUI.locked or false,
                    settingsOpen = oldUI.settingsOpen or false,
                    width = oldUI.width or 360,
                    height = oldUI.height or 320,
                    footerHidden = oldUI.footerHidden or false,
                    minimap = oldUI.minimap or {
                        hide = false,
                    },
                    expandedMobs = {},
                    expandedPlaces = {},
                    expandedContinents = {},
                    expandedWorlds = {},
                }
            }

            FarmingoDB.characterProfile[GetCurrentCharacterKey()] = "Default"

            FarmingoSession = {
                mobs = {}
            }
            pendingReset = false
            RefreshSettingsUI()
            RefreshFooterLayout()
            UpdateDisplay()
            print("Farmingo: all saved data deleted.")
        else
            print("Farmingo: type /ft reset first, then /ft confirmreset.")
        end
    else
        print("Farmingo commands:")
        print("/ft show - show window")
        print("/ft hide - hide window")
        print("/ft reset - request full data reset")
        print("/ft confirmreset - confirm full data reset")
        print("/ft profile - show current profile")
        print("/ft profiles - list all profiles")
        print("/ft profile create NAME - create profile")
        print("/ft profile use NAME - switch this character to profile")
        print("/ft profile delete NAME - delete unused profile")
    end
end