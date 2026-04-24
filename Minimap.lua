local ADDON_NAME, ns = ...
local DB = ns.DB
local UI = ns.UI

local minimapRegistered = false

-- Public API

function ns.Minimap_OnAddonLoaded()
    DB.EnsureDB()

    local ldb = UI.ldb
    local icon = UI.icon

    if not ldb or not icon then
        return
    end

    if not minimapRegistered then
        icon:Register("Farmingo", ldb, FarmingoDB.ui.minimap)
        minimapRegistered = true
    end

    if FarmingoDB.ui.minimap.hide then
        icon:Hide("Farmingo")
    else
        icon:Show("Farmingo")
    end
end