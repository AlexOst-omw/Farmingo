local ADDON_NAME, ns = ...
local DB = ns.DB
local Loot = ns.Loot
local State = ns.State
local UI = ns.UI

local frame = UI.frame
local content = UI.content
local rows = UI.rows
local ROW_HEIGHT = UI.ROW_HEIGHT

local toggleAllButton = UI.toggleAllButton
local totalLootsValue = UI.totalLootsValue
local totalGoldValue = UI.totalGoldValue
local sessionValue = UI.sessionValue
local sessionGoldValue = UI.sessionGoldValue

local UpdateDisplay

local updateQueued = false

local cachedDuplicateNameMap = nil
local cachedDuplicateNameRevision = -1

local cachedFooterRevision = -1

local function RequestUpdateDisplay()
    if updateQueued then
        return
    end

    updateQueued = true

    C_Timer.After(0.05, function()
        updateQueued = false

        if UpdateDisplay then
            UpdateDisplay()
        end
    end)
end

local COLOR_WORLD = "|cffd8b25d"
local COLOR_CONTINENT = "|cffffb347"
local COLOR_PLACE = "|cffffff99"
local COLOR_MOB = "|cffffff00"
local COLOR_RESET = "|r"

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

local function GetRow(index)
    local rows = UI.rows
    if rows[index] then
        return rows[index]
    end

    local content = UI.content
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
    DB.EnsureDB()

    for _, expanded in pairs(FarmingoDB.ui.expandedMobs) do
        if expanded then
            return true
        end
    end

    return false
end

local UpdateToggleAllButton = function(profileMobs)
    if State.currentViewMode == "place" then
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

local UpdateFooterTotals = function(profileMobs)
    local totalGold = 0
    local totalLoots = 0
    local sessionTotalLoots = 0
    local sessionTotalGold = 0

    for mobKey, data in pairs(profileMobs) do
        totalGold = totalGold + (data.gold or 0)
        totalLoots = totalLoots + (data.lootCount or 0)

        local sessionData = State.session.mobs[mobKey]
        if sessionData then
            sessionTotalLoots = sessionTotalLoots + (sessionData.lootCount or 0)
            sessionTotalGold = sessionTotalGold + (sessionData.gold or 0)
        end
    end

    sessionValue:SetText(sessionTotalLoots)
    sessionGoldValue:SetText(Loot.FormatMoney(sessionTotalGold))
    totalLootsValue:SetText(totalLoots)
    totalGoldValue:SetText(Loot.FormatMoney(totalGold))
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

local RenderPlaceView = function(profileMobs, duplicateNameMap)
    local placeData = {
        zones = {},
        dungeons = {},
        raids = {},
        scenarios = {},
    }

    local placeLootTotals = {}
    local placeGoldTotals = {}

    local worldLootTotals = {}
    local worldGoldTotals = {}

    local continentLootTotals = {}
    local continentGoldTotals = {}

    local dungeonLootTotal = 0
    local dungeonGoldTotal = 0

    local raidLootTotal = 0
    local raidGoldTotal = 0

    local scenarioLootTotal = 0
    local scenarioGoldTotal = 0

    for mobKey, data in pairs(profileMobs) do
        if Loot.MobMatchesSearch(mobKey, data) then
            for placeKey, placeLootCount in pairs(data.places or {}) do
                local lootCount = placeLootCount or 0
                local goldCount = data.gold or 0

                placeLootTotals[placeKey] = (placeLootTotals[placeKey] or 0) + lootCount
                placeGoldTotals[placeKey] = (placeGoldTotals[placeKey] or 0) + goldCount

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

                elseif placeType == "scenario" then
                    placeData.scenarios[placeKey] = placeData.scenarios[placeKey] or {}
                    placeData.scenarios[placeKey][mobKey] = data
                end

                if placeType == "zone" then
                    worldLootTotals[worldName] = (worldLootTotals[worldName] or 0) + lootCount
                    worldGoldTotals[worldName] = (worldGoldTotals[worldName] or 0) + goldCount

                    local continentKey = worldName .. "|" .. continentName
                    continentLootTotals[continentKey] = (continentLootTotals[continentKey] or 0) + lootCount
                    continentGoldTotals[continentKey] = (continentGoldTotals[continentKey] or 0) + goldCount

                elseif placeType == "dungeon" then
                    dungeonLootTotal = dungeonLootTotal + lootCount
                    dungeonGoldTotal = dungeonGoldTotal + goldCount

                elseif placeType == "raid" then
                    raidLootTotal = raidLootTotal + lootCount
                    raidGoldTotal = raidGoldTotal + goldCount

                elseif placeType == "scenario" then
                    scenarioLootTotal = scenarioLootTotal + lootCount
                    scenarioGoldTotal = scenarioGoldTotal + goldCount
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
            return worldLootTotals[worldName] or 0
        end,
        function(worldName)
            return worldName
        end
    )

    local rowIndex = 1

    for _, worldName in ipairs(worldKeys) do
        local expandedWorld = FarmingoDB.ui.expandedWorlds[worldName]

        local worldTotalLoots = worldLootTotals[worldName] or 0

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
            DB.EnsureDB()
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
            local worldTotalGold = worldGoldTotals[worldName] or 0

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", Loot.FormatMoney(worldTotalGold))

            if placeData.zones[worldName]["__FLAT__"] then
                local placeKeys = {}
                for placeKey in pairs(placeData.zones[worldName]["__FLAT__"]) do
                    table.insert(placeKeys, placeKey)
                end

                SortKeysByLootTotal(
                    placeKeys,
                    function(placeKey)
                        return placeLootTotals[placeKey] or 0
                    end,
                    function(placeKey)
                        return GetPlaceNameFromKey(placeKey)
                    end
                )

                for _, placeKey in ipairs(placeKeys) do
                    local _, _, placeType, placeName = strsplit("|", placeKey)
                    local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                    local placeTotalLoots = placeLootTotals[placeKey] or 0

                    local placeRow = GetRow(rowIndex)
                    placeRow:Show()
                    placeRow.isMobRow = false
                    placeRow.mobKey = nil
                    placeRow.itemLink = nil
                    placeRow.placeKey = placeKey
                    placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                    placeRow.countText:SetText(placeTotalLoots .. " loots")
                    placeRow:SetScript("OnClick", function(self)
                        DB.EnsureDB()
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

                        local placeTotalGold = placeGoldTotals[placeKey] or 0

                        rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(placeTotalGold))

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
                                local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
                                local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
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
                            local mobDisplayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                            if State.searchQuery ~= "" then
                                mobDisplayName = Loot.HighlightSearchMatch(mobDisplayName)
                            end

                            if Loot.IsFallbackMobName(mobDisplayName) then
                                mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                            else
                                mobRow.text:SetText(prefix .. mobDisplayName)
                            end

                            local lootWord = (placeLootCount == 1) and "loot" or "loots"
                            mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                            mobRow:SetScript("OnClick", function(self)
                                DB.EnsureDB()
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
                                    rowIndex = AddNoItemsRow(rowIndex, "        |cff888888No items recorded|r")
                                else
                                    for _, itemName in ipairs(itemNames) do
                                        local itemData = mobData.items[itemName]

                                        local itemText = itemData.link or itemName
                                        if State.searchQuery ~= "" and not itemData.link then
                                            itemText = Loot.HighlightSearchMatch(itemText)
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
                                    rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                                end

                                local sessionData = State.session.mobs[mobKey]
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
                                sessionRow.text:SetText("        |cff66ccffThis session loots:|r")
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
                                    sessionGoldRow.text:SetText("        |cff66ccffThis session gold:|r")
                                    sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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
                    return continentLootTotals[worldName .. "|" .. continentName] or 0
                end,
                function(continentName)
                    return continentName
                end
            )

            for _, continentName in ipairs(continentKeys) do
                local expandedContinent = FarmingoDB.ui.expandedContinents[continentName]

                local continentTotalLoots = continentLootTotals[worldName .. "|" .. continentName] or 0

                local continentRow = GetRow(rowIndex)
                continentRow:Show()
                continentRow.isMobRow = false
                continentRow.mobKey = nil
                continentRow.itemLink = nil
                continentRow.continentName = continentName
                continentRow.text:SetText("    " .. (expandedContinent and "[-] " or "[+] ") .. COLOR_CONTINENT .. continentName .. COLOR_RESET)
                continentRow.countText:SetText(continentTotalLoots .. " loots")
                continentRow:SetScript("OnClick", function(self)
                    DB.EnsureDB()
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

                    local continentTotalGold = continentGoldTotals[worldName .. "|" .. continentName] or 0

                    rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(continentTotalGold))

                    local placeKeys = {}
                    for placeKey in pairs(placeData.zones[worldName][continentName]) do
                        table.insert(placeKeys, placeKey)
                    end

                    SortKeysByLootTotal(
                        placeKeys,
                        function(placeKey)
                            return placeLootTotals[placeKey] or 0
                        end,
                        function(placeKey)
                            return GetPlaceNameFromKey(placeKey)
                        end
                    )

                    for _, placeKey in ipairs(placeKeys) do
                        local _, _, placeType, placeName = strsplit("|", placeKey)
                        local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                        local placeTotalLoots = placeLootTotals[placeKey] or 0

                        local placeRow = GetRow(rowIndex)
                        placeRow:Show()
                        placeRow.isMobRow = false
                        placeRow.mobKey = nil
                        placeRow.itemLink = nil
                        placeRow.placeKey = placeKey
                        placeRow.text:SetText("        " .. (expandedPlace and "[-] " or "[+] ") .. COLOR_PLACE .. (placeName or placeKey) .. COLOR_RESET)
                        placeRow.countText:SetText(placeTotalLoots .. " loots")
                        placeRow:SetScript("OnClick", function(self)
                            DB.EnsureDB()
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

                            local placeTotalGold = placeGoldTotals[placeKey] or 0

                            rowIndex = AddInfoRow(rowIndex, "            |cffd8b25dTotal gold:|r", Loot.FormatMoney(placeTotalGold))

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
                                    local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
                                    local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
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
                                local mobDisplayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                                if State.searchQuery ~= "" then
                                    mobDisplayName = Loot.HighlightSearchMatch(mobDisplayName)
                                end

                                if Loot.IsFallbackMobName(mobDisplayName) then
                                    mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                                else
                                    mobRow.text:SetText(prefix .. COLOR_MOB .. mobDisplayName .. COLOR_RESET)
                                end

                                local lootWord = (placeLootCount == 1) and "loot" or "loots"
                                mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                                mobRow:SetScript("OnClick", function(self)
                                    DB.EnsureDB()
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
                                        rowIndex = AddNoItemsRow(rowIndex, "              |cff888888No items recorded|r")
                                    else
                                        for _, itemName in ipairs(itemNames) do
                                            local itemData = mobData.items[itemName]

                                            local itemText = itemData.link or itemName
                                            if State.searchQuery ~= "" and not itemData.link then
                                                itemText = Loot.HighlightSearchMatch(itemText)
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
                                        rowIndex = AddInfoRow(rowIndex, "              |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                                    end

                                    local sessionData = State.session.mobs[mobKey]
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
                                    sessionRow.text:SetText("              |cff66ccffThis session loots:|r")
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
                                        sessionGoldRow.text:SetText("              |cff66ccffThis session gold:|r")
                                        sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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
            return placeLootTotals[placeKey] or 0
        end,
        function(placeKey)
            return GetPlaceNameFromKey(placeKey)
        end
    )

    if #dungeonKeys > 0 then
        local expandedDungeons = FarmingoDB.ui.expandedWorlds["Dungeons"]

        local dungeonsTotalLoots = dungeonLootTotal

        local dungeonsRow = GetRow(rowIndex)
        dungeonsRow:Show()
        dungeonsRow.isMobRow = false
        dungeonsRow.mobKey = nil
        dungeonsRow.itemLink = nil
        dungeonsRow.worldName = "Dungeons"
        dungeonsRow.text:SetText((expandedDungeons and "[-] " or "[+] ") .. "Dungeons")
        dungeonsRow.countText:SetText(dungeonsTotalLoots .. " loots")
        dungeonsRow:SetScript("OnClick", function(self)
            DB.EnsureDB()
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

            local dungeonsTotalGold = dungeonGoldTotal

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", Loot.FormatMoney(dungeonsTotalGold))

            for _, placeKey in ipairs(dungeonKeys) do
                local _, _, _, placeName = strsplit("|", placeKey)
                local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                local placeTotalLoots = placeLootTotals[placeKey] or 0

                local placeRow = GetRow(rowIndex)
                placeRow:Show()
                placeRow.isMobRow = false
                placeRow.mobKey = nil
                placeRow.itemLink = nil
                placeRow.placeKey = placeKey
                placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                placeRow.countText:SetText(placeTotalLoots .. " loots")
                placeRow:SetScript("OnClick", function(self)
                    DB.EnsureDB()
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

                    local placeTotalGold = placeGoldTotals[placeKey] or 0

                    rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(placeTotalGold))

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
                            local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
                            local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
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
                        local mobDisplayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                        if State.searchQuery ~= "" then
                            mobDisplayName = Loot.HighlightSearchMatch(mobDisplayName)
                        end

                        if Loot.IsFallbackMobName(mobDisplayName) then
                            mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                        else
                            mobRow.text:SetText(prefix .. mobDisplayName)
                        end

                        local lootWord = (placeLootCount == 1) and "loot" or "loots"
                        mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                        mobRow:SetScript("OnClick", function(self)
                            DB.EnsureDB()
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
                                rowIndex = AddNoItemsRow(rowIndex, "          |cff888888No items recorded|r")
                            else
                                for _, itemName in ipairs(itemNames) do
                                    local itemData = mobData.items[itemName]

                                    local itemText = itemData.link or itemName
                                    if State.searchQuery ~= "" and not itemData.link then
                                        itemText = Loot.HighlightSearchMatch(itemText)
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
                                rowIndex = AddInfoRow(rowIndex, "          |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                            end

                            local sessionData = State.session.mobs[mobKey]
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
                            sessionRow.text:SetText("          |cff66ccffThis session loots:|r")
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
                                sessionGoldRow.text:SetText("          |cff66ccffThis session gold:|r")
                                sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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
            return placeLootTotals[placeKey] or 0
        end,
        function(placeKey)
            return GetPlaceNameFromKey(placeKey)
        end
    )

    if #raidKeys > 0 then
        local expandedRaids = FarmingoDB.ui.expandedWorlds["Raids"]

        local raidsTotalLoots = raidLootTotal

        local raidsRow = GetRow(rowIndex)
        raidsRow:Show()
        raidsRow.isMobRow = false
        raidsRow.mobKey = nil
        raidsRow.itemLink = nil
        raidsRow.worldName = "Raids"
        raidsRow.text:SetText((expandedRaids and "[-] " or "[+] ") .. "Raids")
        raidsRow.countText:SetText(raidsTotalLoots .. " loots")
        raidsRow:SetScript("OnClick", function(self)
            DB.EnsureDB()
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

            local raidsTotalGold = raidGoldTotal

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", Loot.FormatMoney(raidsTotalGold))

            for _, placeKey in ipairs(raidKeys) do
                local _, _, _, placeName = strsplit("|", placeKey)
                local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                local placeTotalLoots = placeLootTotals[placeKey] or 0

                local placeRow = GetRow(rowIndex)
                placeRow:Show()
                placeRow.isMobRow = false
                placeRow.mobKey = nil
                placeRow.itemLink = nil
                placeRow.placeKey = placeKey
                placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                placeRow.countText:SetText(placeTotalLoots .. " loots")
                placeRow:SetScript("OnClick", function(self)
                    DB.EnsureDB()
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

                    local placeTotalGold = placeGoldTotals[placeKey] or 0

                    rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(placeTotalGold))

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
                            local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
                            local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
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
                        local mobDisplayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                        if State.searchQuery ~= "" then
                            mobDisplayName = Loot.HighlightSearchMatch(mobDisplayName)
                        end

                        if Loot.IsFallbackMobName(mobDisplayName) then
                            mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                        else
                            mobRow.text:SetText(prefix .. mobDisplayName)
                        end

                        local lootWord = (placeLootCount == 1) and "loot" or "loots"
                        mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                        mobRow:SetScript("OnClick", function(self)
                            DB.EnsureDB()
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
                                rowIndex = AddNoItemsRow(rowIndex, "        |cff888888No items recorded|r")
                            else
                                for _, itemName in ipairs(itemNames) do
                                    local itemData = mobData.items[itemName]

                                    local itemText = itemData.link or itemName
                                    if State.searchQuery ~= "" and not itemData.link then
                                        itemText = Loot.HighlightSearchMatch(itemText)
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
                                rowIndex = AddInfoRow(rowIndex, "          |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                            end

                            local sessionData = State.session.mobs[mobKey]
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
                            sessionRow.text:SetText("          |cff66ccffThis session loots:|r")
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
                                sessionGoldRow.text:SetText("          |cff66ccffThis session gold:|r")
                                sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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

    local scenarioKeys = {}
    for placeKey in pairs(placeData.scenarios) do
        table.insert(scenarioKeys, placeKey)
    end

    SortKeysByLootTotal(
        scenarioKeys,
        function(placeKey)
            return placeLootTotals[placeKey] or 0
        end,
        function(placeKey)
            return GetPlaceNameFromKey(placeKey)
        end
    )

    if #scenarioKeys > 0 then
        local expandedScenarios = FarmingoDB.ui.expandedWorlds["Scenarios"]

        local scenariosTotalLoots = scenarioLootTotal

        local scenariosRow = GetRow(rowIndex)
        scenariosRow:Show()
        scenariosRow.isMobRow = false
        scenariosRow.mobKey = nil
        scenariosRow.itemLink = nil
        scenariosRow.worldName = "Scenarios"
        scenariosRow.text:SetText((expandedScenarios and "[-] " or "[+] ") .. "Scenarios")
        scenariosRow.countText:SetText(scenariosTotalLoots .. " loots")
        scenariosRow:SetScript("OnClick", function(self)
            DB.EnsureDB()
            FarmingoDB.ui.expandedWorlds["Scenarios"] = not FarmingoDB.ui.expandedWorlds["Scenarios"]
            UpdateDisplay()
        end)
        scenariosRow:SetScript("OnEnter", function(self)
            self.highlight:Show()
        end)
        scenariosRow:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)

        rowIndex = rowIndex + 1

        if expandedScenarios then

            local scenariosTotalGold = scenarioGoldTotal

            rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", Loot.FormatMoney(scenariosTotalGold))

            for _, placeKey in ipairs(scenarioKeys) do
                local _, _, _, placeName = strsplit("|", placeKey)
                local expandedPlace = FarmingoDB.ui.expandedPlaces[placeKey]

                local placeTotalLoots = placeLootTotals[placeKey] or 0

                local placeRow = GetRow(rowIndex)
                placeRow:Show()
                placeRow.isMobRow = false
                placeRow.mobKey = nil
                placeRow.itemLink = nil
                placeRow.placeKey = placeKey
                placeRow.text:SetText("    " .. (expandedPlace and "[-] " or "[+] ") .. (placeName or placeKey))
                placeRow.countText:SetText(placeTotalLoots .. " loots")
                placeRow:SetScript("OnClick", function(self)
                    DB.EnsureDB()
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

                    local placeTotalGold = placeGoldTotals[placeKey] or 0

                    rowIndex = AddInfoRow(rowIndex, "        |cffd8b25dTotal gold:|r", Loot.FormatMoney(placeTotalGold))

                    local mobList = {}

                    for mobKey, mobData in pairs(placeData.scenarios[placeKey]) do
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
                            local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
                            local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
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
                        local mobDisplayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, mobData.displayName, duplicateNameMap)

                        if State.searchQuery ~= "" then
                            mobDisplayName = Loot.HighlightSearchMatch(mobDisplayName)
                        end

                        if Loot.IsFallbackMobName(mobDisplayName) then
                            mobRow.text:SetText(prefix .. "|cff888888" .. mobDisplayName .. "|r")
                        else
                            mobRow.text:SetText(prefix .. mobDisplayName)
                        end

                        local lootWord = (placeLootCount == 1) and "loot" or "loots"
                        mobRow.countText:SetText(placeLootCount .. " " .. lootWord)
                        mobRow:SetScript("OnClick", function(self)
                            DB.EnsureDB()
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
                                rowIndex = AddNoItemsRow(rowIndex, "          |cff888888No items recorded|r")
                            else
                                for _, itemName in ipairs(itemNames) do
                                    local itemData = mobData.items[itemName]

                                    local itemText = itemData.link or itemName
                                    if State.searchQuery ~= "" and not itemData.link then
                                        itemText = Loot.HighlightSearchMatch(itemText)
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
                                rowIndex = AddInfoRow(rowIndex, "          |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                            end

                            local sessionData = State.session.mobs[mobKey]
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
                            sessionRow.text:SetText("          |cff66ccffThis session loots:|r")
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
                                sessionGoldRow.text:SetText("          |cff66ccffThis session gold:|r")
                                sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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

    local frame = UI.frame
    local content = UI.content
    local rows = UI.rows

    for i = rowIndex, #rows do
        rows[i]:Hide()
        rows[i]:SetScript("OnClick", nil)
    end

    local totalHeight = math.max((rowIndex - 1) * UI.ROW_HEIGHT, 1)
    content:SetWidth(frame:GetWidth() - 40)
    content:SetSize(frame:GetWidth() - 40, totalHeight)

    return
end

local RenderMobView = function(profileMobs, duplicateNameMap)
    local mobList = {}
    for mobKey, data in pairs(profileMobs) do
        if Loot.MobMatchesSearch(mobKey, data) then
            table.insert(mobList, {
                key = mobKey,
                data = data,
                count = data.lootCount or 0
            })
        end
    end

    table.sort(mobList, function(a, b)
        if a.count == b.count then
            local nameA = Loot.GetSafeDisplayName(a.key, a.data.displayName)
            local nameB = Loot.GetSafeDisplayName(b.key, b.data.displayName)
            return nameA < nameB
        end
        return a.count > b.count
    end)

    local rowIndex = 1

    if #mobList == 0 then
        local row = GetRow(rowIndex)
        row:Show()
        row.isMobRow = false
        row.mobKey = nil
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
            local displayName = Loot.GetDisplayNameWithDuplicateSuffix(mobKey, data.displayName, duplicateNameMap)
            local lootCount = data.lootCount or 0
            local expanded = FarmingoDB.ui.expandedMobs[mobKey]

            local mobRow = GetRow(rowIndex)
            mobRow:Show()
            mobRow.isMobRow = true
            mobRow.mobKey = mobKey
            local rowName = displayName

            if State.searchQuery ~= "" then
                rowName = Loot.HighlightSearchMatch(rowName)
            end

            if Loot.IsFallbackMobName(displayName) then
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
                DB.EnsureDB()
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
                        if State.searchQuery ~= "" and not itemData.link then
                            itemText = Loot.HighlightSearchMatch(itemText)
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
                        rowIndex = AddInfoRow(rowIndex, "    |cffd8b25dTotal gold:|r", Loot.FormatMoney(mobGold))
                    end

                    local sessionData = State.session.mobs[mobKey]
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
                        sessionGoldRow.countText:SetText("|cffffffff" .. Loot.FormatMoney(sessionGold) .. "|r")
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

    local frame = UI.frame
    local content = UI.content
    local rows = UI.rows

    for i = rowIndex, #rows do
        rows[i]:Hide()
        rows[i]:SetScript("OnClick", nil)
    end

    local totalHeight = math.max((rowIndex - 1) * UI.ROW_HEIGHT, 1)
    content:SetWidth(frame:GetWidth() - 40)
    content:SetSize(frame:GetWidth() - 40, totalHeight)
end

UpdateDisplay = function()
    DB.EnsureDB()

    local profileMobs = DB.GetProfileMobs()
    local dataRevision = State.dataRevision or 0

    if cachedDuplicateNameRevision ~= dataRevision then
        cachedDuplicateNameMap = Loot.BuildDuplicateMobNameMap()
        cachedDuplicateNameRevision = dataRevision
    end

    UpdateToggleAllButton(profileMobs)

    if cachedFooterRevision ~= dataRevision then
        UpdateFooterTotals(profileMobs)
        cachedFooterRevision = dataRevision
    end

    local duplicateNameMap = cachedDuplicateNameMap

    if State.currentViewMode == "place" then
        RenderPlaceView(profileMobs, duplicateNameMap)
    else
        RenderMobView(profileMobs, duplicateNameMap)
    end
end

if UI and UI.frame then
    UpdateDisplay()
end

UI.AreAnyMobsExpanded = AreAnyMobsExpanded
UI.UpdateDisplay = UpdateDisplay
UI.RequestUpdateDisplay = RequestUpdateDisplay
UI.RenderMobView = RenderMobView
UI.RenderPlaceView = RenderPlaceView