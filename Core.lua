local ADDON_NAME, ns = ...

ns.State = ns.State or {}
ns.Modules = ns.Modules or {}
ns.Constants = ns.Constants or {}
ns.UI = ns.UI or {}
ns.Functions = ns.Functions or {}

ns.Constants.SEARCH_PLACEHOLDER = "Search info..."

ns.State.observedMobNamesByKey = ns.State.observedMobNamesByKey or {}
ns.State.pendingReset = false
ns.State.session = ns.State.session or {
    mobs = {}
}
ns.State.pendingLootSlots = ns.State.pendingLootSlots or {}
ns.State.attemptedLootSlots = ns.State.attemptedLootSlots or {}
ns.State.runtimeSeenSources = ns.State.runtimeSeenSources or {}
ns.State.bossChestLootCounted = ns.State.bossChestLootCounted or {}
ns.State.recentEncounterBoss = nil
ns.State.recentEncounterTime = 0
ns.State.currentViewMode = "mob"
ns.State.clearedSourcesThisWindow = ns.State.clearedSourcesThisWindow or {}
ns.State.sourceLootNumberThisWindow = ns.State.sourceLootNumberThisWindow or {}
ns.State.currentLootWasAuto = false
ns.State.lootHadInventoryFullError = false
ns.State.pendingClosedLootWindows = ns.State.pendingClosedLootWindows or {}
ns.State.isSearchOpen = false
ns.State.searchQuery = ""
ns.State.dataRevision = ns.State.dataRevision or 0