local ADDON_NAME, ns = ...
local State = ns.State
local DB = ns.DB

local Places = ns.Places or {}

local ProcessClearedLootSlot
local ProcessClearedLootSlotFromWindow

local function MarkDataChanged()
    State.dataRevision = (State.dataRevision or 0) + 1
end

local function EnsureMobEntry(mobKey, displayName)
    DB.EnsureDB()

    if not mobKey then
        mobKey = "unknown"
    end

    local mobs = DB.GetProfileMobs()

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

    State.session = State.session or { mobs = {} }
    State.session.mobs = State.session.mobs or {}

    if not mobKey then
        mobKey = "unknown"
    end

    if not State.session.mobs[mobKey] then
        State.session.mobs[mobKey] = {
            displayName = displayName or "Unknown Mob",
            lootCount = 0,
            gold = 0,
            items = {}
        }
    elseif displayName and displayName ~= "" then
        State.session.mobs[mobKey].displayName = displayName
    end

    return State.session.mobs[mobKey]
end

local function IncrementLootCount(mobKey, displayName)
    local entry = EnsureMobEntry(mobKey, displayName)
    entry.lootCount = (entry.lootCount or 0) + 1
    MarkDataChanged()
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
    MarkDataChanged()
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
    MarkDataChanged()
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
    MarkDataChanged()
end

local function GetSourceTypeFromGUID(guid)
    if not guid then return nil end
    return strsplit("-", guid)
end

local function IsMobGUID(guid)
    local sourceType = GetSourceTypeFromGUID(guid)
    return sourceType == "Creature" or sourceType == "Vehicle"
end

local function GetMobKeyFromUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local ok, unitType, npcID = pcall(function()
        return select(1, strsplit("-", guid)), select(6, strsplit("-", guid))
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

    local ok, unitType, npcID = pcall(function()
        return select(1, strsplit("-", sourceGUID)), select(6, strsplit("-", sourceGUID))
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

    if not name then
        return
    end

    if not IsSafeDisplayString(name) then
        return
    end

    if name == "" or name == "Unknown" then
        return
    end

    State.observedMobNamesByKey[mobKey] = name

    local mobNamesByKey = DB.GetProfileMobNamesByKey()
    mobNamesByKey[mobKey] = name

    local mobs = DB.GetProfileMobs()
    if mobs[mobKey] then
        mobs[mobKey].displayName = name
    end
end

local function RememberMob(unit)
    if not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    if UnitIsFriend("player", unit) then return end
    if not UnitCanAttack("player", unit) then return end

    local okName, name = pcall(UnitName, unit)
    if not okName or not name then
        return
    end

    local mobKey = GetMobKeyFromUnit(unit)
    if not mobKey then
        return
    end

    RememberMobNameByKey(mobKey, name)
end

local function GetDisplayNameForSource(sourceGUID)
    local mobKey = GetMobKeyFromSourceGUID(sourceGUID)
    if not mobKey or mobKey == "unknown" then
        return nil
    end

    if State.observedMobNamesByKey[mobKey] then
        return State.observedMobNamesByKey[mobKey]
    end

    local mobNamesByKey = DB.GetProfileMobNamesByKey()
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
    local preferredIsUseful =
        IsSafeDisplayString(preferredName)
        and preferredName ~= ""
        and preferredName ~= "Unknown"
        and preferredName ~= "Unknown Mob"
        and not preferredName:find("^Unknown Mob %(")
        and not preferredName:find("^Unknown Vehicle %(")

    if preferredIsUseful then
        return preferredName
    end

    local mobNamesByKey = DB.GetProfileMobNamesByKey()
    if mobNamesByKey[mobKey] and mobNamesByKey[mobKey] ~= "" then
        return mobNamesByKey[mobKey]
    end

    local npcID = GetMobIDFromKey(mobKey)

    local manualName = npcID and ns.NPCNames and ns.NPCNames[tonumber(npcID)]
    if manualName then
        return manualName
    end

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

    for mobKey, data in pairs(DB.GetProfileMobs()) do
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

local function CaptureEncounterBoss(encounterID, encounterName)
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then
        return
    end

    if not encounterID or not encounterName or encounterName == "" then
        return
    end

    State.recentEncounterBoss = {
        mobKey = "Encounter:" .. tostring(encounterID),
        displayName = encounterName,
        mapID = C_Map.GetBestMapForUnit("player"),
    }
    State.recentEncounterTime = GetTime() or 0

    State.bossChestLootCounted[State.recentEncounterBoss.mobKey] = nil
end

local function GetRecentEncounterBoss()
    if not State.recentEncounterBoss then
        return nil
    end

    local now = GetTime() or 0
    if now - (State.recentEncounterTime or 0) > 30 then
        return nil
    end

    local currentMapID = C_Map.GetBestMapForUnit("player")
    if State.recentEncounterBoss.mapID and currentMapID and State.recentEncounterBoss.mapID ~= currentMapID then
        return nil
    end

    return State.recentEncounterBoss.mobKey, State.recentEncounterBoss.displayName
end

local function MarkSourceSeen(sourceGUID)
    local seenSources = DB.GetProfileSeenSources()
    if sourceGUID then
        seenSources[sourceGUID] = true
    end
end

local function HasSeenSource(sourceGUID)
    local seenSources = DB.GetProfileSeenSources()
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

local function CopyKeyTable(source)
    local copy = {}
    if not source then return copy end
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function CopyArrayTable(source)
    local copy = {}
    if not source then return copy end
    for i = 1, #source do
        copy[i] = source[i]
    end
    return copy
end

local function CopyPendingLootSlots(source)
    local copy = {}
    if not source then return copy end

    for slot, slotData in pairs(source) do
        copy[slot] = {
            slotType = slotData.slotType,
            lootName = slotData.lootName,
            lootQuantity = slotData.lootQuantity,
            itemLink = slotData.itemLink,
            sources = CopyArrayTable(slotData.sources),
        }
    end

    return copy
end

local function CreateRecentEncounterSnapshot()
    if not State.recentEncounterBoss then
        return nil
    end

    return {
        mobKey = State.recentEncounterBoss.mobKey,
        displayName = State.recentEncounterBoss.displayName,
        mapID = State.recentEncounterBoss.mapID,
    }
end

local function CreateClosedLootWindowSnapshot()
    return {
        pendingLootSlots = CopyPendingLootSlots(State.pendingLootSlots),
        attemptedLootSlots = CopyKeyTable(State.attemptedLootSlots),
        clearedSourcesThisWindow = CopyKeyTable(State.clearedSourcesThisWindow),
        sourceLootNumberThisWindow = CopyKeyTable(State.sourceLootNumberThisWindow),
        bossChestLootCounted = CopyKeyTable(State.bossChestLootCounted),
        recentEncounterBoss = CreateRecentEncounterSnapshot(),
        recentEncounterTime = State.recentEncounterTime,
        wasAuto = State.currentLootWasAuto,
        hadInventoryFullError = State.lootHadInventoryFullError,
    }
end

local function GetRecentEncounterBossFromWindow(lootWindow)
    local boss = lootWindow.recentEncounterBoss
    if not boss then
        return nil
    end

    local now = GetTime() or 0
    if now - (lootWindow.recentEncounterTime or 0) > 30 then
        return nil
    end

    local currentMapID = C_Map.GetBestMapForUnit("player")
    if boss.mapID and currentMapID and boss.mapID ~= currentMapID then
        return nil
    end

    return boss.mobKey, boss.displayName
end

local function BuildPendingLoot()
    wipe(State.attemptedLootSlots)

    State.pendingLootSlots = {}
    State.clearedSourcesThisWindow = {}
    State.sourceLootNumberThisWindow = {}

    local numItems = GetNumLootItems()

    for slot = 1, numItems do
        local slotType = GetLootSlotType(slot)
        local _, lootName, lootQuantity = GetLootSlotInfo(slot)
        local itemLink = GetLootSlotLink(slot)
        local sources = { GetLootSourceInfo(slot) }

        State.pendingLootSlots[slot] = {
            slotType = slotType,
            lootName = lootName,
            lootQuantity = lootQuantity or 1,
            itemLink = itemLink,
            sources = sources,
        }
    end
end

local function ClearPendingLoot()
    State.pendingLootSlots = {}
    State.clearedSourcesThisWindow = {}
    State.sourceLootNumberThisWindow = {}
    wipe(State.attemptedLootSlots)
    wipe(State.bossChestLootCounted)
    State.recentEncounterBoss = nil
    State.recentEncounterTime = 0
end

local function ProcessAttemptedPendingLootSlotsFromWindow(lootWindow)
    for slot in pairs(lootWindow.attemptedLootSlots) do
        local slotData = lootWindow.pendingLootSlots[slot]

        if slotData then
            if not (lootWindow.hadInventoryFullError and slotData.slotType == Enum.LootSlotType.Item) then
                ProcessClearedLootSlotFromWindow(lootWindow, slot)
            end
        end
    end
end

local function ProcessAllPendingLootSlotsFromWindow(lootWindow)
    for slot, slotData in pairs(lootWindow.pendingLootSlots) do
        if not (lootWindow.hadInventoryFullError and slotData.slotType == Enum.LootSlotType.Item) then
            ProcessClearedLootSlotFromWindow(lootWindow, slot)
        end
    end
end

local function HandleClosedLootWindow(lootWindow)
    if next(lootWindow.attemptedLootSlots) then
        ProcessAttemptedPendingLootSlotsFromWindow(lootWindow)
    elseif lootWindow.wasAuto and next(lootWindow.pendingLootSlots) then
        ProcessAllPendingLootSlotsFromWindow(lootWindow)
    end
end

hooksecurefunc("LootSlot", function(slot)
    if State.pendingLootSlots and State.pendingLootSlots[slot] then
        State.attemptedLootSlots[slot] = true
    end
end)

ProcessClearedLootSlotFromWindow = function(lootWindow, slot)
    DB.EnsureDB()

    local slotData = lootWindow.pendingLootSlots[slot]
    if not slotData then
        return
    end

    local slotType = slotData.slotType
    local lootName = slotData.lootName
    local quantity = slotData.lootQuantity or 1
    local itemLink = slotData.itemLink
    local sources = slotData.sources or {}

    local placeInfo = Places.GetCurrentPlaceInfo()
    local placeKey = placeInfo.placeKey
    local sourceToMobName = {}
    local recentBossMobKey, recentBossDisplayName = GetRecentEncounterBossFromWindow(lootWindow)

    for i = 1, #sources, 2 do
        local sourceGUID = sources[i]

        if sourceGUID and IsMobGUID(sourceGUID) then
            if not sourceToMobName[sourceGUID] then
                sourceToMobName[sourceGUID] = GetDisplayNameForSource(sourceGUID)
            end
        end
    end

    for i = 1, math.max(#sources, 1), 2 do
        local sourceGUID = sources[i]
        local sourceQuantity = tonumber(sources[i + 1]) or quantity or 1

        if sourceGUID and IsMobGUID(sourceGUID) then
            local mobKey = GetMobKeyFromSourceGUID(sourceGUID)
            local rawDisplayName = sourceToMobName[sourceGUID]
            local displayName = GetSafeDisplayName(mobKey, rawDisplayName)

            local entry = EnsureMobEntry(mobKey, displayName)

            if not lootWindow.sourceLootNumberThisWindow[sourceGUID] then
                local lootNumber = entry.lootCount or 0

                if not HasSeenSource(sourceGUID) then
                    lootNumber = lootNumber + 1
                end

                lootWindow.sourceLootNumberThisWindow[sourceGUID] = lootNumber
            end

            local firstDropLootCount = lootWindow.sourceLootNumberThisWindow[sourceGUID]

            if slotType == Enum.LootSlotType.Item and lootName then
                AddLootToMob(mobKey, displayName, lootName, sourceQuantity, itemLink, firstDropLootCount)
                AddLootToSession(mobKey, displayName, lootName, sourceQuantity)
            elseif slotType == Enum.LootSlotType.Money and lootName then
                local copper = tonumber(sources[i + 1]) or ParseMoneyTextToCopper(lootName)

                AddGoldToMob(mobKey, displayName, copper)
                AddGoldToSession(mobKey, displayName, copper)
            end

            if not lootWindow.clearedSourcesThisWindow[sourceGUID] and not HasSeenSource(sourceGUID) then
                IncrementLootCount(mobKey, displayName)
                IncrementSessionLootCount(mobKey, displayName)
                MarkSourceSeen(sourceGUID)
                lootWindow.clearedSourcesThisWindow[sourceGUID] = true
                AddPlaceToMob(mobKey, displayName, placeKey)
            end

        elseif (not sourceGUID or not IsMobGUID(sourceGUID)) and recentBossMobKey and recentBossDisplayName then
            if not lootWindow.bossChestLootCounted[recentBossMobKey] then
                IncrementLootCount(recentBossMobKey, recentBossDisplayName)
                IncrementSessionLootCount(recentBossMobKey, recentBossDisplayName)
                AddPlaceToMob(recentBossMobKey, recentBossDisplayName, placeKey)
                lootWindow.bossChestLootCounted[recentBossMobKey] = true
            end

            if slotType == Enum.LootSlotType.Item and lootName then
                AddLootToMob(recentBossMobKey, recentBossDisplayName, lootName, sourceQuantity, itemLink, nil)
                AddLootToSession(recentBossMobKey, recentBossDisplayName, lootName, sourceQuantity)
            elseif slotType == Enum.LootSlotType.Money and lootName then
                local copper = ParseMoneyTextToCopper(lootName)
                AddGoldToMob(recentBossMobKey, recentBossDisplayName, copper)
                AddGoldToSession(recentBossMobKey, recentBossDisplayName, copper)
            end

            break
        end
    end

    lootWindow.pendingLootSlots[slot] = nil
    if ns.UI then
        if ns.UI.RequestUpdateDisplay then
            ns.UI.RequestUpdateDisplay()
        elseif ns.UI.UpdateDisplay then
            ns.UI.UpdateDisplay()
        end
    end
end

ProcessClearedLootSlot = function(slot)
    ProcessClearedLootSlotFromWindow({
        pendingLootSlots = State.pendingLootSlots,
        attemptedLootSlots = State.attemptedLootSlots,
        clearedSourcesThisWindow = State.clearedSourcesThisWindow,
        sourceLootNumberThisWindow = State.sourceLootNumberThisWindow,
        bossChestLootCounted = State.bossChestLootCounted,
        recentEncounterBoss = State.recentEncounterBoss,
        recentEncounterTime = State.recentEncounterTime,
        wasAuto = State.currentLootWasAuto,
        hadInventoryFullError = State.lootHadInventoryFullError,
    }, slot)
end

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

local tooltipIndex = nil
local tooltipIndexRevision = -1

local function GetFirstDropLootCountForItem(itemLink, itemID)
    local targetItemID = itemID or GetItemIDFromLink(itemLink)
    if not targetItemID then
        return nil
    end

    if tooltipIndex == nil or tooltipIndexRevision ~= State.dataRevision then
        tooltipIndex = DB.RebuildTooltipIndex()
        tooltipIndexRevision = State.dataRevision
    end

    return tooltipIndex[targetItemID]
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
    if not State.searchQuery or State.searchQuery == "" then
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

    return safeText:find(State.searchQuery, 1, true) ~= nil
end

local function HighlightSearchMatch(text)
    if not text then
        return text
    end

    if not State.searchQuery or State.searchQuery == "" then
        return text
    end

    local lowerText = text:lower()
    local startPos = lowerText:find(State.searchQuery, 1, true)

    if not startPos then
        return text
    end

    local endPos = startPos + #State.searchQuery - 1

    local before = text:sub(1, startPos - 1)
    local matchText = text:sub(startPos, endPos)
    local after = text:sub(endPos + 1)

    return before .. "|cffff8800" .. matchText .. "|r" .. after
end

local function MobMatchesSearch(mobKey, data)
    if not State.searchQuery or State.searchQuery == "" then
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

ns.Loot = {
    EnsureMobEntry = EnsureMobEntry,
    EnsureSessionMobEntry = EnsureSessionMobEntry,
    IncrementLootCount = IncrementLootCount,
    IncrementSessionLootCount = IncrementSessionLootCount,
    AddLootToMob = AddLootToMob,
    AddLootToSession = AddLootToSession,
    AddGoldToMob = AddGoldToMob,
    AddGoldToSession = AddGoldToSession,
    AddPlaceToMob = AddPlaceToMob,
    GetSourceTypeFromGUID = GetSourceTypeFromGUID,
    IsMobGUID = IsMobGUID,
    GetMobKeyFromUnit = GetMobKeyFromUnit,
    GetMobKeyFromSourceGUID = GetMobKeyFromSourceGUID,
    IsSafeDisplayString = IsSafeDisplayString,
    RememberMobNameByKey = RememberMobNameByKey,
    RememberMob = RememberMob,
    GetDisplayNameForSource = GetDisplayNameForSource,
    GetFallbackDisplayNameFromKey = GetFallbackDisplayNameFromKey,
    GetMobIDFromKey = GetMobIDFromKey,
    GetSafeDisplayName = GetSafeDisplayName,
    BuildDuplicateMobNameMap = BuildDuplicateMobNameMap,
    GetDisplayNameWithDuplicateSuffix = GetDisplayNameWithDuplicateSuffix,
    IsFallbackMobName = IsFallbackMobName,
    CaptureEncounterBoss = CaptureEncounterBoss,
    GetRecentEncounterBoss = GetRecentEncounterBoss,
    MarkSourceSeen = MarkSourceSeen,
    HasSeenSource = HasSeenSource,
    ParseMoneyTextToCopper = ParseMoneyTextToCopper,
    BuildPendingLoot = BuildPendingLoot,
    ClearPendingLoot = ClearPendingLoot,
    CreateClosedLootWindowSnapshot = CreateClosedLootWindowSnapshot,
    HandleClosedLootWindow = HandleClosedLootWindow,
    ProcessClearedLootSlot = ProcessClearedLootSlot,
    ProcessClearedLootSlotFromWindow = ProcessClearedLootSlotFromWindow,
    FormatMoney = FormatMoney,
    GetItemIDFromLink = GetItemIDFromLink,
    GetFirstDropLootCountForItem = GetFirstDropLootCountForItem,
    AddFarmingoTooltipLine = AddFarmingoTooltipLine,
    StringMatchesSearch = StringMatchesSearch,
    HighlightSearchMatch = HighlightSearchMatch,
    MobMatchesSearch = MobMatchesSearch,
}