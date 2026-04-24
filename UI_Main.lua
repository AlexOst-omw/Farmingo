-- ============================================================================
-- 1. SavedVariables defaults and runtime state
-- ============================================================================

local ADDON_NAME, ns = ...
local DB = ns and ns.DB
local Loot = ns and ns.Loot
local State = ns and ns.State

local SEARCH_PLACEHOLDER = "Search info..."

-- ============================================================================
-- 2. Forward declarations
-- ============================================================================

local function RefreshSettingsUI()
    if ns.UI.RefreshSettingsUI then
        ns.UI.RefreshSettingsUI()
    end
end

local RefreshFooterLayout

local function UpdateDisplay()
    if ns.UI.UpdateDisplay then
        ns.UI.UpdateDisplay()
    end
end

local function AreAnyMobsExpanded()
    if ns.UI.AreAnyMobsExpanded then
        return ns.UI.AreAnyMobsExpanded()
    end
    return false
end

-- ============================================================================
-- 3. UI creation
-- ============================================================================

local frame = CreateFrame("Frame", "FarmingoFrame", UIParent, "BackdropTemplate")
DB.EnsureDB()
frame:SetSize(FarmingoDB.ui.width, FarmingoDB.ui.height)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetResizable(true)
frame:SetResizeBounds(260, 180)

local icon = LibStub("LibDBIcon-1.0")

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
profileValue:SetText(DB.GetActiveProfileName())

local profileDropdown = CreateFrame("Frame", "FarmingoProfileDropdown", settingsContent, "UIDropDownMenuTemplate")
profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(profileDropdown, 150)

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
    "|cffbfbfbf/ft reset|r - request FULL data reset\n" ..
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

function RefreshFooterLayout()
    DB.EnsureDB()

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

footerToggleButton:SetScript("OnClick", function()
    DB.EnsureDB()
    FarmingoDB.ui.footerHidden = not FarmingoDB.ui.footerHidden
    RefreshFooterLayout()
    UpdateDisplay()
end)

viewModeButton:SetScript("OnClick", function()
    if State.currentViewMode == "mob" then
        State.currentViewMode = "place"
        viewModeButton:SetText("Place")
    else
        State.currentViewMode = "mob"
        viewModeButton:SetText("Mob")
    end

    UpdateDisplay()
end)

toggleAllButton:SetScript("OnClick", function()
    DB.EnsureDB()
    local profileMobs = DB.GetProfileMobs()

    if State.currentViewMode == "place" then
        local anyExpanded = false

        for _, expanded in pairs(FarmingoDB.ui.expandedWorlds) do
            if expanded then anyExpanded = true break end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedContinents) do
                if expanded then anyExpanded = true break end
            end
        end

        if not anyExpanded then
            for _, expanded in pairs(FarmingoDB.ui.expandedPlaces) do
                if expanded then anyExpanded = true break end
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

searchButton:SetScript("OnClick", function()
    State.isSearchOpen = not State.isSearchOpen

    if State.isSearchOpen then
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
        State.searchQuery = ""
        searchBox:Hide()
        searchBoxBG:Hide()
    end

    UpdateDisplay()
end)

searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:SetText(SEARCH_PLACEHOLDER)
    self:SetTextColor(0.6, 0.6, 0.6)
    State.searchQuery = ""
    State.isSearchOpen = false
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
        State.searchQuery = ""
        return
    end

    State.searchQuery = text:lower()
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

resizeButton:SetScript("OnMouseDown", function(self, button)
    DB.EnsureDB()

    if button == "LeftButton" and not FarmingoDB.ui.locked then
        frame:StartSizing("BOTTOMRIGHT", true)
    end
end)

resizeButton:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()

    DB.EnsureDB()
    FarmingoDB.ui.width = frame:GetWidth()
    FarmingoDB.ui.height = frame:GetHeight()

    UpdateDisplay()
end)

local rows = {}
local ROW_HEIGHT = 20

ns.UI.frame = frame
ns.UI.content = content
ns.UI.rows = rows
ns.UI.ROW_HEIGHT = ROW_HEIGHT
ns.UI.toggleAllButton = toggleAllButton
ns.UI.totalLootsValue = totalLootsValue
ns.UI.totalGoldValue = totalGoldValue
ns.UI.sessionValue = sessionValue
ns.UI.sessionGoldValue = sessionGoldValue
ns.UI.RefreshFooterLayout = RefreshFooterLayout
ns.UI.settingsPanel = settingsPanel
ns.UI.settingsScrollFrame = settingsScrollFrame
ns.UI.settingsContent = settingsContent
ns.UI.profileValue = profileValue
ns.UI.profileDropdown = profileDropdown
ns.UI.lockCheck = lockCheck
ns.UI.tooltipCheck = tooltipCheck
ns.UI.resizeButton = resizeButton
ns.UI.scrollFrame = scrollFrame
ns.UI.footer = footer
ns.UI.searchBox = searchBox
ns.UI.settingsButton = settingsButton
ns.UI.createButton = createButton
ns.UI.frame = frame
ns.UI.ldb = ldb
ns.UI.icon = icon

-- ============================================================================
-- 4. Event registration and event handler
-- ============================================================================

frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_SLOT_CLEARED")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("ENCOUNTER_START")

frame:SetScript("OnDragStart", function(self)
    DB.EnsureDB()
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
            DB.EnsureDB()
            State.session = {
                mobs = {}
            }

            if ns.Minimap_OnAddonLoaded then
                ns.Minimap_OnAddonLoaded()
            end

            RefreshSettingsUI()
            RefreshFooterLayout()
            UpdateDisplay()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        Loot.RememberMob("target")

    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Loot.RememberMob("mouseover")
    
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        Loot.RememberMob(unit)

    elseif event == "LOOT_OPENED" then
        local autoLoot = ...
        State.currentLootWasAuto = autoLoot and true or false
        State.lootHadInventoryFullError = false
        Loot.BuildPendingLoot()

    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        Loot.ProcessClearedLootSlot(slot)

    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        Loot.CaptureEncounterBoss(encounterID, encounterName)

    elseif event == "UI_ERROR_MESSAGE" then
        local arg1, arg2 = ...

        if arg1 == ERR_INV_FULL or arg2 == ERR_INV_FULL then
            State.lootHadInventoryFullError = true

            if #State.pendingClosedLootWindows > 0 then
                State.pendingClosedLootWindows[#State.pendingClosedLootWindows].hadInventoryFullError = true
            end
        end

    elseif event == "LOOT_CLOSED" then
        local closedLootWindow = Loot.CreateClosedLootWindowSnapshot()
        table.insert(State.pendingClosedLootWindows, closedLootWindow)

        Loot.ClearPendingLoot()
        State.currentLootWasAuto = false
        State.lootHadInventoryFullError = false

        C_Timer.After(0.10, function()
            Loot.HandleClosedLootWindow(closedLootWindow)

            for i = #State.pendingClosedLootWindows, 1, -1 do
                if State.pendingClosedLootWindows[i] == closedLootWindow then
                    table.remove(State.pendingClosedLootWindows, i)
                    break
                end
            end
        end)
    end
end)