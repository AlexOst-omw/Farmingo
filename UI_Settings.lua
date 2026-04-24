local ADDON_NAME, ns = ...
local DB = ns.DB
local State = ns.State
local UI = ns.UI

local frame = UI.frame
local settingsButton = UI.settingsButton
local createButton = UI.createButton

local settingsPanel = UI.settingsPanel
local settingsScrollFrame = UI.settingsScrollFrame
local settingsContent = UI.settingsContent
local profileValue = UI.profileValue
local profileDropdown = UI.profileDropdown
local lockCheck = UI.lockCheck
local tooltipCheck = UI.tooltipCheck
local resizeButton = UI.resizeButton
local scrollFrame = UI.scrollFrame
local footer = UI.footer
local searchBox = UI.searchBox

-- Helpers

local function RefreshAll()
    if UI.RefreshSettingsUI then UI.RefreshSettingsUI() end
    if UI.RefreshFooterLayout then UI.RefreshFooterLayout() end
    if UI.UpdateDisplay then UI.UpdateDisplay() end
end

local function Print(msg)
    print("Farmingo: " .. msg)
end

-- Dropdown

local function InitializeProfileDropdown(self, level)
    local profiles = DB.GetSortedProfileNames()
    local activeProfile = DB.GetActiveProfileName()

    for _, name in ipairs(profiles) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (name == activeProfile)

        info.func = function()
            local ok, err = DB.SetCharacterProfile(name)
            if ok then
                RefreshAll()
                Print("active profile set to " .. name)
            else
                Print(err)
            end
        end

        UIDropDownMenu_AddButton(info)
    end
end

-- Refresh

local function RefreshSettingsUI()
    DB.EnsureDB()

    lockCheck:SetChecked(FarmingoDB.ui.locked)
    resizeButton:SetShown(not FarmingoDB.ui.locked)
    tooltipCheck:SetChecked(FarmingoDB.ui.tooltipEnabled)

    profileValue:SetText(DB.GetActiveProfileName())
    UIDropDownMenu_SetText(profileDropdown, DB.GetActiveProfileName())

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

    if State.isSearchOpen and not FarmingoDB.ui.settingsOpen then
        searchBox:Show()
    else
        searchBox:Hide()
    end
end

-- Events

settingsButton:SetScript("OnClick", function()
    DB.EnsureDB()
    FarmingoDB.ui.settingsOpen = not FarmingoDB.ui.settingsOpen
    RefreshSettingsUI()
end)

lockCheck:SetScript("OnClick", function(self)
    DB.EnsureDB()
    frame:StopMovingOrSizing()
    FarmingoDB.ui.locked = self:GetChecked() and true or false
    RefreshSettingsUI()
end)

tooltipCheck:SetScript("OnClick", function(self)
    DB.EnsureDB()
    FarmingoDB.ui.tooltipEnabled = self:GetChecked() and true or false
end)

createButton:SetScript("OnClick", function()
    if not StaticPopupDialogs["FARMINGO_CREATE_PROFILE"] then
        StaticPopupDialogs["FARMINGO_CREATE_PROFILE"] = {
            text = "Enter profile name:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 20,
            OnAccept = function(self)
                local text = strtrim(self.EditBox:GetText() or "")
                local ok, err = DB.CreateProfile(text)
                if ok then
                    DB.SetCharacterProfile(text)
                    RefreshAll()
                    Print("profile created and activated - " .. text)
                else
                    Print(err)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    StaticPopup_Show("FARMINGO_CREATE_PROFILE")
end)

-- Setup

UIDropDownMenu_Initialize(profileDropdown, InitializeProfileDropdown)
UIDropDownMenu_SetText(profileDropdown, DB.GetActiveProfileName())

-- Public API

UI.RefreshSettingsUI = RefreshSettingsUI