local ADDON_NAME, ns = ...
local DB = ns.DB
local Loot = ns.Loot

-- Setup

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not tooltip or not data then
        return
    end

    DB.EnsureDB()
    if not FarmingoDB.ui.tooltipEnabled then
        return
    end

    local itemID = data.id
    local itemLink = data.hyperlink

    Loot.AddFarmingoTooltipLine(tooltip, itemLink, itemID)
    tooltip:Show()
end)