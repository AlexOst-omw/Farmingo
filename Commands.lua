local ADDON_NAME, ns = ...
local DB = ns.DB
local State = ns.State
local UI = ns.UI

local pendingReset = false

-- Helpers

local function RefreshAll()
    if UI.RefreshSettingsUI then UI.RefreshSettingsUI() end
    if UI.RefreshFooterLayout then UI.RefreshFooterLayout() end
    if UI.UpdateDisplay then UI.UpdateDisplay() end
end

local function Print(msg)
    print("Farmingo: " .. msg)
end

-- Commands

local function HandleProfileCommand(msg)
    local trimmed = strtrim(msg)
    local lower = trimmed:lower()

    if lower == "profile" then
        print("Farmingo current profile: " .. DB.GetActiveProfileName())
        return true
    end

    if lower == "profiles" then
        local names = DB.GetSortedProfileNames()
        print("Farmingo profiles: " .. table.concat(names, ", "))
        return true
    end

    local createName = trimmed:match("^profile%s+create%s+(.+)$")
    if createName then
        local ok, err = DB.CreateProfile(createName)
        if ok then
            Print("profile created - " .. createName)
        else
            Print(err)
        end
        return true
    end

    local deleteName = trimmed:match("^profile%s+delete%s+(.+)$")
    if deleteName then
        local ok, err = DB.DeleteProfile(deleteName)
        if ok then
            RefreshAll()
            Print("profile deleted - " .. deleteName)
        else
            Print(err)
        end
        return true
    end

    local useName = trimmed:match("^profile%s+use%s+(.+)$")
    if useName then
        local ok, err = DB.SetCharacterProfile(useName)
        if ok then
            RefreshAll()
            Print("active profile set to " .. useName)
        else
            Print(err)
        end
        return true
    end

    return false
end

-- Main handler

SLASH_FARMINGO1 = "/ft"

SlashCmdList["FARMINGO"] = function(msg)
    msg = msg or ""
    local trimmed = strtrim(msg)
    local lower = trimmed:lower()

    if lower ~= "reset" and lower ~= "confirmreset" then
        pendingReset = false
    end

    if HandleProfileCommand(trimmed) then
        return
    end

    if lower == "show" then
        UI.frame:Show()
        Print("shown.")
        return

    elseif lower == "hide" then
        UI.frame:Hide()
        Print("hidden.")
        return

    elseif lower == "resetprofile" then
        ns.DB.ResetActiveProfileData()

        print("|cff00ff00Farmingo:|r Current profile data reset.")

        if ns.UI and ns.UI.UpdateDisplay then
            ns.UI.UpdateDisplay()
        end

        return

    elseif lower == "reset" then
        pendingReset = true
        Print("type /ft confirmreset to delete ALL data. OR /ft show to cancel")
        return

    elseif lower == "confirmreset" then
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
                ui = {
                    locked = oldUI.locked or false,
                    settingsOpen = oldUI.settingsOpen or false,
                    width = oldUI.width or 360,
                    height = oldUI.height or 320,
                    footerHidden = oldUI.footerHidden or false,
                    minimap = oldUI.minimap or { hide = false },
                    expandedMobs = {},
                    expandedPlaces = {},
                    expandedContinents = {},
                    expandedWorlds = {},
                }
            }

            FarmingoDB.characterProfile[DB.GetCurrentCharacterKey()] = "Default"

            State.session = { mobs = {} }
            State.dataRevision = (State.dataRevision or 0) + 1
            pendingReset = false

            wipe(State.observedMobNamesByKey)
            wipe(State.runtimeSeenSources)
            wipe(State.pendingLootSlots)
            wipe(State.attemptedLootSlots)
            wipe(State.clearedSourcesThisWindow)
            wipe(State.sourceLootNumberThisWindow)
            wipe(State.pendingClosedLootWindows)
            wipe(State.bossChestLootCounted)
            State.lootHadInventoryFullError = false
            State.recentEncounterBoss = nil
            State.recentEncounterTime = 0
            State.currentLootWasAuto = false

            RefreshAll()
            Print("all saved data deleted.")
        else
            Print("type /ft reset first.")
        end
        return
    end

    -- Help

    print("Farmingo commands:")
    print("/ft show - show window")
    print("/ft hide - hide window")
    print("/ft resetprofile - reset current profile data only")
    print("/ft reset - request full reset")
    print("/ft confirmreset - confirm reset")
    print("/ft profile - current profile")
    print("/ft profiles - list profiles")
    print("/ft profile create NAME")
    print("/ft profile use NAME")
    print("/ft profile delete NAME")
end