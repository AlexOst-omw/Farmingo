local ADDON_NAME, ns = ...
local State = ns.State

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

local function EnsureDB()
    FarmingoDB = FarmingoDB or {}

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

    local characterKey = ns.DB.GetCurrentCharacterKey()
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
    return State.runtimeSeenSources
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

    wipe(State.observedMobNamesByKey)
    wipe(State.pendingLootSlots)
    wipe(State.clearedSourcesThisWindow)
    wipe(State.sourceLootNumberThisWindow)
    wipe(State.attemptedLootSlots)
    wipe(State.runtimeSeenSources)
    wipe(State.pendingClosedLootWindows)
    State.lootHadInventoryFullError = false
    State.recentEncounterBoss = nil
    State.recentEncounterTime = 0
    wipe(State.bossChestLootCounted)

    State.currentLootWasAuto = false

    State.session = {
        mobs = {}
    }

    return true
end

ns.DB = {
    EnsureDB = EnsureDB,
    GetCurrentCharacterKey = GetCurrentCharacterKey,
    GetActiveProfileName = GetActiveProfileName,
    GetActiveProfile = GetActiveProfile,
    GetProfileMobs = GetProfileMobs,
    GetProfileSeenSources = GetProfileSeenSources,
    GetProfileMobNamesByKey = GetProfileMobNamesByKey,
    NormalizeProfileName = NormalizeProfileName,
    ProfileExists = ProfileExists,
    CreateProfile = CreateProfile,
    SetCharacterProfile = SetCharacterProfile,
    GetSortedProfileNames = GetSortedProfileNames,
    GetCharactersUsingProfile = GetCharactersUsingProfile,
    DeleteProfile = DeleteProfile,
}