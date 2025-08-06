-- DOKI Collections - ENHANCED: Surgical Update System (No Batching/Lazy Loading)
local addonName, DOKI = ...
-- Initialize collection-specific storage
DOKI.foundFramesThisScan = {}
-- Ensemble detection variables
DOKI.ensembleWordCache = nil
DOKI.ensembleKnownItemID = 234522
-- Merchant scroll detection system
DOKI.merchantScrollDetector = {
	isScrolling = false,
	scrollTimer = nil,
	lastMerchantState = nil,
	merchantOpen = false,
}
-- Item loading system for ATT mode only
DOKI.itemLoader = {
	pendingItems = {}, -- [itemID] = { callbacks = {...}, bagID, slotID }
	initialized = false,
}
-- Enhanced surgical update throttling with delayed cleanup
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.1
DOKI.pendingSurgicalUpdate = false
-- Enhanced scanning system variables
DOKI.delayedScanTimer = nil
DOKI.delayedScanCancelled = false
-- Enhanced cache system with specific cache types
DOKI.collectionCache = DOKI.collectionCache or {}
DOKI.cacheStats = {
	hits = 0,
	misses = 0,
	invalidations = 0,
	totalEntries = 0,
}
-- Cache type constants for targeted invalidation (GLOBAL to DOKI namespace)
DOKI.CACHE_TYPES = {
	TRANSMOG = "transmog",
	PET = "pet",
	MOUNT = "mount",
	TOY = "toy",
	ENSEMBLE = "ensemble",
	ATT = "att",
	BATTLEPET = "battlepet",
}
-- Debouncing system for rapid-fire events (GLOBAL to DOKI namespace)
DOKI.eventDebouncer = {
	timers = {},
	pendingUpdates = {},
	stats = {
		totalEvents = 0,
		debouncedEvents = 0,
		executedUpdates = 0,
	},
}
-- Debounce settings (in seconds) (GLOBAL to DOKI namespace)
DOKI.DEBOUNCE_DELAYS = {
	BAG_UPDATE = 0.1,         -- items moving in bags
	ITEM_LOCK_CHANGED = 0.1,  -- item pickup/drop
	CURSOR_CHANGED = 0.1,     -- cursor state changes
	MERCHANT_UPDATE = 0.1,    -- merchant page changes
	BAG_UPDATE_DELAYED = 0.15, -- delayed bag updates
}
-- ===== DEBOUNCING CORE FUNCTIONS =====
function DOKI:DebounceEvent(eventName, callback, customDelay)
	local delay = customDelay or DOKI.DEBOUNCE_DELAYS[eventName] or 0.05
	-- Cancel existing timer for this event
	if self.eventDebouncer.timers[eventName] then
		self.eventDebouncer.timers[eventName]:Cancel()
		self.eventDebouncer.stats.debouncedEvents = self.eventDebouncer.stats.debouncedEvents + 1
	end

	self.eventDebouncer.stats.totalEvents = self.eventDebouncer.stats.totalEvents + 1
	self.eventDebouncer.pendingUpdates[eventName] = true
	-- DEBUG: Simple logging
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r DEBOUNCE: %s (%.0fms delay, total events: %d)",
			eventName, delay * 1000, self.eventDebouncer.stats.totalEvents))
	end

	-- Create new debounced timer
	self.eventDebouncer.timers[eventName] = C_Timer.NewTimer(delay, function()
		if DOKI.eventDebouncer.pendingUpdates[eventName] then
			DOKI.eventDebouncer.pendingUpdates[eventName] = nil
			DOKI.eventDebouncer.timers[eventName] = nil
			DOKI.eventDebouncer.stats.executedUpdates = DOKI.eventDebouncer.stats.executedUpdates + 1
			-- Execute the callback
			local success, result = pcall(callback)
			if not success and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Debounced callback error for %s: %s", eventName, tostring(result)))
			end
		end
	end)
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Debounced %s (%.0fms delay)", eventName, delay * 1000))
	end
end

-- Enhanced surgical update with debouncing
function DOKI:DebouncedSurgicalUpdate(eventName, isImmediate)
	if not self.db or not self.db.enabled then return end

	-- Check if UI is visible (same logic as before)
	local anyUIVisible = self:IsAnyRelevantUIVisible()
	if anyUIVisible then
		self:DebounceEvent(eventName or "SURGICAL_UPDATE", function()
			if DOKI.db and DOKI.db.enabled then
				DOKI:TriggerImmediateSurgicalUpdate()
			end
		end)
	end
end

-- Check if any relevant UI is visible
function DOKI:IsAnyRelevantUIVisible()
	-- Check ElvUI
	if ElvUI and self:IsElvUIBagVisible() then
		return true
	end

	-- Check Blizzard UI
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		return true
	end

	-- Check individual containers
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			return true
		end
	end

	-- Check merchant
	if MerchantFrame and MerchantFrame:IsVisible() then
		return true
	end

	-- Check if cursor has item
	if C_Cursor and C_Cursor.GetCursorItem() then
		return true
	end

	return false
end

-- ===== ENHANCED EVENT SYSTEM WITH DEBOUNCING =====
function DOKI:SetupDebouncedEventSystem()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	-- Events that should be debounced (rapid-fire events)
	local debouncedEvents = {
		"BAG_UPDATE",
		"BAG_UPDATE_DELAYED",
		"ITEM_LOCK_CHANGED",
		"CURSOR_CHANGED",
		"MERCHANT_UPDATE",
	}
	-- Events that should trigger immediate updates (collection changes)
	local immediateEvents = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"PET_JOURNAL_LIST_UPDATE",
		"COMPANION_LEARNED",
		"COMPANION_UNLEARNED",
		"TRANSMOG_COLLECTION_UPDATED",
		"TOYS_UPDATED",
		"MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL",
		"UI_INFO_MESSAGE",
	}
	-- Register all events
	for _, event in ipairs(debouncedEvents) do
		self.eventFrame:RegisterEvent(event)
	end

	for _, event in ipairs(immediateEvents) do
		self.eventFrame:RegisterEvent(event)
	end

	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		if not (DOKI.db and DOKI.db.enabled) then return end

		-- Handle debounced events
		if tContains(debouncedEvents, event) then
			DOKI:DebouncedSurgicalUpdate(event, false)
			return
		end

		-- Handle immediate events (existing logic with minor optimizations)
		if event == "MERCHANT_SHOW" then
			DOKI.merchantScrollDetector.merchantOpen = true
			DOKI:InitializeMerchantScrollDetection()
			-- Debounce this too since merchant can be spammy
			DOKI:DebounceEvent("MERCHANT_SHOW", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end, 0.2)
		elseif event == "MERCHANT_CLOSED" then
			DOKI.merchantScrollDetector.merchantOpen = false
			DOKI.merchantScrollDetector.lastMerchantState = nil
			if DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			end
		elseif event == "BANKFRAME_OPENED" then
			DOKI:DebounceEvent("BANKFRAME_OPENED", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end, 0.2)
		elseif event == "BANKFRAME_CLOSED" then
			if DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" or event == "UI_INFO_MESSAGE" then
			-- Enhanced detection for merchant selling - still debounce slightly
			DOKI:DebounceEvent("MERCHANT_SELL", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end, 0.05)
		elseif event == "PET_JOURNAL_LIST_UPDATE" or
				event == "COMPANION_LEARNED" or
				event == "COMPANION_UNLEARNED" then
			-- Collection changed - these can be slightly debounced too
			DOKI:DebounceEvent("COLLECTION_CHANGE", function()
				if DOKI.db and DOKI.db.enabled then
					-- Cache was already cleared by the cache invalidation system
					DOKI:FullItemScan(true) -- Use withDelay for battlepet timing
				end
			end, 0.1)
		elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TOYS_UPDATED" then
			-- Transmog/toy collection changed
			DOKI:DebounceEvent("COLLECTION_CHANGE", function()
				if DOKI.db and DOKI.db.enabled then
					-- Cache was already cleared by the cache invalidation system
					DOKI:FullItemScan()
				end
			end, 0.1)
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced event system with debouncing initialized")
		print(string.format("  Debounced events: %d", #debouncedEvents))
		print(string.format("  Immediate events: %d", #immediateEvents))
	end
end

-- ===== DEBOUNCING STATISTICS AND CLEANUP =====
function DOKI:GetDebouncingStats()
	return {
		totalEvents = self.eventDebouncer.stats.totalEvents,
		debouncedEvents = self.eventDebouncer.stats.debouncedEvents,
		executedUpdates = self.eventDebouncer.stats.executedUpdates,
		pendingTimers = self:TableCount(self.eventDebouncer.timers),
		pendingUpdates = self:TableCount(self.eventDebouncer.pendingUpdates),
	}
end

function DOKI:ShowDebouncingStats()
	local stats = self:GetDebouncingStats()
	print("|cffff69b4DOKI|r === DEBOUNCING STATISTICS ===")
	print(string.format("Total events received: %d", stats.totalEvents))
	print(string.format("Events debounced: %d", stats.debouncedEvents))
	print(string.format("Updates executed: %d", stats.executedUpdates))
	print(string.format("Currently pending: %d timers, %d updates", stats.pendingTimers, stats.pendingUpdates))
	if stats.totalEvents > 0 then
		local efficiency = ((stats.totalEvents - stats.executedUpdates) / stats.totalEvents) * 100
		print(string.format("Efficiency: %.1f%% fewer updates", efficiency))
	end

	print("|cffff69b4DOKI|r === END DEBOUNCING STATS ===")
end

function DOKI:CleanupDebouncingSystem()
	-- Cancel all pending timers
	for eventName, timer in pairs(self.eventDebouncer.timers) do
		if timer then
			timer:Cancel()
		end
	end

	-- Clear state
	self.eventDebouncer.timers = {}
	self.eventDebouncer.pendingUpdates = {}
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Debouncing system cleaned up")
	end
end

-- Initialize the item loading system (called from Core.lua)
function DOKI:InitializeItemLoader()
	if self.itemLoader.initialized then return end

	self.itemLoader.initialized = true
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Item loader initialized with GET_ITEM_INFO_RECEIVED event")
	end
end

-- Handle the event when item data becomes available (called from Core.lua)
function DOKI:OnItemInfoReceived(itemID, success)
	local pendingItemLoadData = self.itemLoader.pendingItems[itemID]
	if not pendingItemLoadData then return end

	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		print(string.format("|cffff69b4DOKI|r GET_ITEM_INFO_RECEIVED: %s (ID: %d, success: %s)",
			itemName, itemID, tostring(success)))
	end

	-- Get the now-available item link
	local itemLink = nil
	if pendingItemLoadData.bagID and pendingItemLoadData.slotID then
		itemLink = C_Container.GetContainerItemLink(pendingItemLoadData.bagID, pendingItemLoadData.slotID)
	end

	-- Validate that the itemLink is actually complete now
	local isComplete = self:IsItemLinkComplete(itemLink)
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r ItemLink after event: %s (complete: %s)",
			itemLink or "NIL", tostring(isComplete)))
	end

	-- Execute all callbacks for this item
	for _, callback in ipairs(pendingItemLoadData.callbacks) do
		local success, result = pcall(callback, itemID, itemLink, isComplete)
		if not success and self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Callback error for item %d: %s", itemID, result))
		end
	end

	-- Clean up
	self.itemLoader.pendingItems[itemID] = nil
end

-- Check if itemLink has complete content (not just correct length)
function DOKI:IsItemLinkComplete(itemLink)
	if not itemLink or itemLink == "" then
		return false
	end

	-- Check 1: Must be reasonable length
	if string.len(itemLink) < 50 then
		return false
	end

	-- Check 2: Must contain actual item name, not just []
	if string.find(itemLink, "%[%]") then
		-- Contains [], which means item name is missing
		return false
	end

	-- Check 3: Must have proper itemLink structure with actual name
	local itemName = string.match(itemLink, "%[([^%]]+)%]")
	if not itemName or itemName == "" then
		return false
	end

	-- Check 4: Item name shouldn't be placeholder text
	if itemName == "..." or itemName == "Loading" or string.len(itemName) < 3 then
		return false
	end

	return true
end

-- Smart item link getter with automatic loading (ATT mode only)
function DOKI:GetItemLinkWhenReady(bagID, slotID, callback)
	if not self.itemLoader.initialized then
		self:InitializeItemLoader()
	end

	-- Try to get item info immediately
	local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
	if not itemInfo or not itemInfo.itemID then
		callback(nil, nil, false)
		return
	end

	local itemID = itemInfo.itemID
	-- Try to get item link immediately
	local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
	-- Check if we have COMPLETE data with actual content
	if self:IsItemLinkComplete(itemLink) then
		-- Data is ready, execute callback immediately
		if self.db and self.db.debugMode then
			local itemName = string.match(itemLink, "%[([^%]]+)%]") or "Unknown"
			print(string.format("|cffff69b4DOKI|r Item data ready immediately: %s (%d chars)",
				itemName, string.len(itemLink)))
		end

		callback(itemID, itemLink, true)
		return
	end

	-- Data is not ready, need to request loading
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Item data incomplete for ID %d (link: %s), requesting load...",
			itemID, itemLink or "NIL"))
	end

	-- Add to pending items
	if not self.itemLoader.pendingItems[itemID] then
		self.itemLoader.pendingItems[itemID] = {
			callbacks = {},
			bagID = bagID,
			slotID = slotID,
		}
	end

	table.insert(self.itemLoader.pendingItems[itemID].callbacks, callback)
	-- Request the item data to be loaded
	C_Item.RequestLoadItemDataByID(itemID)
	-- Also try GetItemInfo to trigger additional loading
	C_Item.GetItemInfo(itemID)
end

-- Cleanup function
function DOKI:CleanupItemLoader()
	self.itemLoader.pendingItems = {}
	self.itemLoader.initialized = false
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Item loader cleaned up")
	end
end

-- ===== ENHANCED CACHE MANAGEMENT =====
function DOKI:ClearCollectionCache(cacheType)
	if not cacheType then
		-- Clear all caches
		local oldCount = self:TableCount(self.collectionCache)
		self.collectionCache = {}
		self.cacheStats.invalidations = self.cacheStats.invalidations + 1
		self.cacheStats.totalEntries = 0
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Cleared entire cache (%d entries)", oldCount))
		end

		return
	end

	-- Clear specific cache type
	local clearedCount = 0
	for key, cached in pairs(self.collectionCache) do
		if cached.cacheType == cacheType then
			self.collectionCache[key] = nil
			clearedCount = clearedCount + 1
		end
	end

	self.cacheStats.invalidations = self.cacheStats.invalidations + 1
	self.cacheStats.totalEntries = self.cacheStats.totalEntries - clearedCount
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cleared %s cache (%d entries)", cacheType, clearedCount))
	end
end

function DOKI:GetCachedCollectionStatus(itemID, itemLink)
	local cacheKey = itemLink or tostring(itemID)
	local cached = self.collectionCache[cacheKey]
	if cached then
		self.cacheStats.hits = self.cacheStats.hits + 1
		-- DEBUG: Simple logging
		if self.db and self.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			print(string.format("|cffff69b4DOKI|r CACHE HIT: %s (ID: %d)", itemName, itemID))
		end

		return cached.isCollected, cached.hasOtherTransmogSources, cached.isPartiallyCollected or false
	end

	self.cacheStats.misses = self.cacheStats.misses + 1
	-- DEBUG: Simple logging
	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		print(string.format("|cffff69b4DOKI|r CACHE MISS: %s (ID: %d)", itemName, itemID))
	end

	return nil, nil, nil
end

function DOKI:SetCachedCollectionStatus(itemID, itemLink, isCollected, hasOtherTransmogSources, isPartiallyCollected,
		cacheType)
	local cacheKey = itemLink or tostring(itemID)
	-- Don't cache if we don't have a proper result
	if isCollected == nil then return end

	-- Determine cache type if not provided
	if not cacheType then
		if itemLink and string.find(itemLink, "battlepet:") then
			cacheType = DOKI.CACHE_TYPES.BATTLEPET
		elseif itemID and self:IsEnsembleItem(itemID) then
			cacheType = DOKI.CACHE_TYPES.ENSEMBLE
		else
			-- Determine by item class
			local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
			if classID == 15 and subClassID == 5 then
				cacheType = DOKI.CACHE_TYPES.MOUNT
			elseif classID == 15 and subClassID == 2 then
				cacheType = DOKI.CACHE_TYPES.PET
			elseif C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
				cacheType = DOKI.CACHE_TYPES.TOY
			elseif classID == 2 or classID == 4 then
				cacheType = DOKI.CACHE_TYPES.TRANSMOG
			else
				cacheType = "unknown"
			end
		end
	end

	-- Add to cache if not already present
	if not self.collectionCache[cacheKey] then
		self.cacheStats.totalEntries = self.cacheStats.totalEntries + 1
	end

	self.collectionCache[cacheKey] = {
		isCollected = isCollected,
		hasOtherTransmogSources = hasOtherTransmogSources,
		isPartiallyCollected = isPartiallyCollected or false,
		cacheType = cacheType,
		sessionTime = GetTime(), -- For debugging/stats only
	}
end

-- ===== EVENT-BASED CACHE INVALIDATION =====
function DOKI:SetupCacheInvalidationEvents()
	if self.cacheEventFrame then
		self.cacheEventFrame:UnregisterAllEvents()
	else
		self.cacheEventFrame = CreateFrame("Frame")
	end

	-- FIXED: Better events that don't spam
	local cacheEvents = {
		["TRANSMOG_COLLECTION_UPDATED"] = DOKI.CACHE_TYPES.TRANSMOG,
		["PET_JOURNAL_LIST_UPDATE"] = DOKI.CACHE_TYPES.PET,
		["COMPANION_LEARNED"] = DOKI.CACHE_TYPES.PET,
		["COMPANION_UNLEARNED"] = DOKI.CACHE_TYPES.PET,
		["TOYS_UPDATED"] = DOKI.CACHE_TYPES.TOY,
		-- FIXED: Use proper mount event instead of COMPANION_UPDATE
		["NEW_MOUNT_ADDED"] = DOKI.CACHE_TYPES.MOUNT,
		-- REMOVED: COMPANION_UPDATE (spams on movement)
	}
	for event, cacheType in pairs(cacheEvents) do
		self.cacheEventFrame:RegisterEvent(event)
	end

	self.cacheEventFrame:SetScript("OnEvent", function(self, event, ...)
		local cacheType = cacheEvents[event]
		if cacheType then
			-- FIXED: Only clear cache if we have entries to clear (reduce spam)
			local clearedCount = 0
			for key, cached in pairs(DOKI.collectionCache) do
				if cached.cacheType == cacheType then
					DOKI.collectionCache[key] = nil
					clearedCount = clearedCount + 1
				end
			end

			if clearedCount > 0 then
				DOKI.cacheStats.invalidations = DOKI.cacheStats.invalidations + 1
				DOKI.cacheStats.totalEntries = DOKI.cacheStats.totalEntries - clearedCount
				if DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Cleared %s cache (%d entries)", cacheType, clearedCount))
				end
			end

			-- FIXED: Only clear ATT cache if we actually have ATT entries
			if DOKI.db and DOKI.db.attMode then
				local attCleared = 0
				for key, cached in pairs(DOKI.collectionCache) do
					if cached.isATTResult then
						DOKI.collectionCache[key] = nil
						attCleared = attCleared + 1
					end
				end

				if attCleared > 0 then
					DOKI.cacheStats.totalEntries = DOKI.cacheStats.totalEntries - attCleared
					if DOKI.db and DOKI.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Also cleared %d ATT cache entries", attCleared))
					end
				end
			end
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Cache invalidation events registered (reduced spam)")
	end
end

-- ===== CACHE STATISTICS AND DEBUGGING =====
function DOKI:GetCacheStats()
	local stats = {
		totalEntries = self.cacheStats.totalEntries,
		hits = self.cacheStats.hits,
		misses = self.cacheStats.misses,
		invalidations = self.cacheStats.invalidations,
		hitRate = 0,
	}
	local totalRequests = stats.hits + stats.misses
	if totalRequests > 0 then
		stats.hitRate = (stats.hits / totalRequests) * 100
	end

	-- Count by type
	stats.byType = {}
	for _, cached in pairs(self.collectionCache) do
		local cacheType = cached.cacheType or "unknown"
		stats.byType[cacheType] = (stats.byType[cacheType] or 0) + 1
	end

	return stats
end

function DOKI:ShowCacheStats()
	local stats = self:GetCacheStats()
	print("|cffff69b4DOKI|r === SESSION CACHE STATISTICS ===")
	print(string.format("Total entries: %d", stats.totalEntries))
	print(string.format("Cache hits: %d", stats.hits))
	print(string.format("Cache misses: %d", stats.misses))
	print(string.format("Hit rate: %.1f%%", stats.hitRate))
	print(string.format("Invalidations: %d", stats.invalidations))
	print("\nEntries by type:")
	for cacheType, count in pairs(stats.byType) do
		print(string.format("  %s: %d", cacheType, count))
	end

	print("|cffff69b4DOKI|r === END CACHE STATS ===")
end

-- ===== ENSEMBLE DETECTION SYSTEM =====
function DOKI:InitializeEnsembleDetection()
	if not self.ensembleWordCache then
		self:ExtractEnsembleWord()
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Ensemble detection initialized with word: '%s'",
			self.ensembleWordCache or "unknown"))
	end
end

function DOKI:ExtractEnsembleWord()
	local itemName = C_Item.GetItemInfo(self.ensembleKnownItemID)
	if itemName then
		-- Extract the word before the colon (e.g., "Ensemble" from "Ensemble: Southsea Cruise Loungewear")
		local ensembleWord = string.match(itemName, "^([^:]+):")
		if ensembleWord then
			self.ensembleWordCache = strtrim(ensembleWord)
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Extracted ensemble word: '%s' from item '%s'",
					self.ensembleWordCache, itemName))
			end
		else
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Could not extract ensemble word from: '%s'", itemName))
			end
		end
	else
		-- Request item data and try again later
		C_Item.RequestLoadItemDataByID(self.ensembleKnownItemID)
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Requesting ensemble reference item data...")
		end
	end
end

function DOKI:IsEnsembleItem(itemID, itemName)
	if not itemID then return false end

	-- Initialize ensemble word if not cached
	if not self.ensembleWordCache then
		self:ExtractEnsembleWord()
		if not self.ensembleWordCache then
			return false -- Can't detect without ensemble word
		end
	end

	-- Check item class/subclass criteria
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false
	end

	-- Must be Class 0 (Consumable) + Subclass 8 (Other)
	if classID ~= 0 or subClassID ~= 8 then
		return false
	end

	-- Must have a spell effect
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then
		return false
	end

	-- Check if name starts with ensemble word
	if not itemName then
		itemName = C_Item.GetItemInfo(itemID)
	end

	if itemName then
		local startsWithEnsemble = string.find(itemName, "^" .. self.ensembleWordCache .. ":")
		if self.db and self.db.debugMode and startsWithEnsemble then
			print(string.format("|cffff69b4DOKI|r Detected ensemble: %s (ID: %d)", itemName, itemID))
		end

		return startsWithEnsemble ~= nil
	end

	return false
end

function DOKI:IsEnsembleCollected(itemID, itemLink)
	if not itemID then return false, false, false end

	-- Check cache first
	local cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected = self:GetCachedCollectionStatus(itemID,
		itemLink)
	if cachedIsCollected ~= nil then
		return cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected
	end

	local isCollected = self:CheckEnsembleByTooltip(itemID, itemLink)
	-- Cache the result (ensembles don't use yellow D or purple logic)
	self:SetCachedCollectionStatus(itemID, itemLink, isCollected, false, false)
	return isCollected, false, false
end

function DOKI:CheckEnsembleByTooltip(itemID, itemLink)
	if not itemID then return false end

	-- Create unique tooltip name to avoid conflicts
	local tooltipName = "DOKIEnsembleTooltip" .. itemID
	local tooltip = CreateFrame("GameTooltip", tooltipName, nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	-- Set the item (prefer itemLink for accuracy)
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	else
		tooltip:SetItemByID(itemID)
	end

	tooltip:Show()
	local isCollected = false
	-- Pure color-based detection (100% locale agnostic)
	for i = 1, tooltip:NumLines() do
		local line = _G[tooltipName .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text and string.len(text) > 0 then
				local r, g, b = line:GetTextColor()
				if r and g and b then
					-- Red text indicates "already known" across all locales
					if r > 0.8 and g < 0.4 and b < 0.4 then
						-- Additional validation: Red text should be reasonably short
						if string.len(text) < 50 then
							isCollected = true
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Ensemble %d already collected (red text): '%s'",
									itemID, text))
							end

							break
						end
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Ensemble tooltip line %d: '%s' (r=%.2f, g=%.2f, b=%.2f)",
							i, text, r or 0, g or 0, b or 0))
					end
				end
			end
		end

		if isCollected then break end
	end

	tooltip:Hide()
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Ensemble %d collection status: %s",
			itemID, isCollected and "COLLECTED" or "NOT COLLECTED"))
	end

	return isCollected
end

-- ===== ENHANCED TRACE FUNCTION FOR ENSEMBLES =====
function DOKI:TraceEnsembleDetection(itemID, itemLink)
	if not itemID then
		print("|cffff69b4DOKI|r No item ID provided")
		return
	end

	print("|cffff69b4DOKI|r === ENSEMBLE DETECTION TRACE ===")
	local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
	print(string.format("Item: %s (ID: %d)", itemName, itemID))
	-- Check if ensemble word is cached
	if not self.ensembleWordCache then
		print("   Ensemble word not cached - attempting extraction...")
		self:ExtractEnsembleWord()
		if not self.ensembleWordCache then
			print("   Could not extract ensemble word - ensemble detection unavailable")
			return
		end
	end

	print(string.format("   Ensemble word: '%s'", self.ensembleWordCache))
	-- Check class/subclass
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	print(string.format("  Class: %d, Subclass: %d", classID or -1, subClassID or -1))
	if classID ~= 0 or subClassID ~= 8 then
		print("   Not Class 0/Subclass 8 - not an ensemble")
		return
	end

	print("   Correct class/subclass for ensemble")
	-- Check spell effect
	local spellID = C_Item.GetItemSpell(itemID)
	print(string.format("  Spell ID: %s", spellID and tostring(spellID) or "none"))
	if not spellID then
		print("   No spell effect - not an ensemble")
		return
	end

	print("   Has spell effect")
	-- Check name pattern
	if itemName then
		local startsWithEnsemble = string.find(itemName, "^" .. self.ensembleWordCache .. ":")
		print(string.format("  Name starts with '%s:': %s", self.ensembleWordCache,
			startsWithEnsemble and "YES" or "NO"))
		if not startsWithEnsemble then
			print("   Name doesn't match ensemble pattern")
			return
		end

		print("   Name matches ensemble pattern")
	else
		print("   Item name not available")
		return
	end

	-- Check collection status
	print("")
	print("|cffff69b4DOKI|r 2. COLLECTION STATUS CHECK:")
	local isCollected = self:CheckEnsembleByTooltip(itemID, itemLink)
	print("")
	print("|cffff69b4DOKI|r 3. FINAL DECISION:")
	print(string.format("  Ensemble: YES"))
	print(string.format("  Collected: %s", isCollected and "YES" or "NO"))
	print(string.format("   NEEDS INDICATOR: %s", isCollected and "NO" or "YES"))
	print("|cffff69b4DOKI|r === END ENSEMBLE TRACE ===")
end

-- ===== MERCHANT SCROLL DETECTION SYSTEM =====
function DOKI:InitializeMerchantScrollDetection()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Initializing merchant scroll detection...")
	end

	-- Method 1: Hook ScrollBox mouse wheel (modern War Within approach) - if available
	if MerchantFrame and MerchantFrame.ScrollBox then
		MerchantFrame.ScrollBox:EnableMouseWheel(true)
		MerchantFrame.ScrollBox:HookScript("OnMouseWheel", function(self, delta)
			DOKI:OnMerchantMouseWheel(delta)
		end)
		-- Register ScrollBox callbacks if available
		if MerchantFrame.ScrollBox.RegisterCallback then
			MerchantFrame.ScrollBox:RegisterCallback("OnScroll", function(self, scrollPercent)
				DOKI:OnMerchantScrollPosition(scrollPercent)
			end)
		end

		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Hooked ScrollBox mouse wheel events")
		end
	else
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r ScrollBox not found, using fallback methods")
		end
	end

	-- Method 2: Hook main merchant frame (fallback and primary for classic merchants)
	if MerchantFrame then
		MerchantFrame:EnableMouseWheel(true)
		MerchantFrame:HookScript("OnMouseWheel", function(self, delta)
			DOKI:OnMerchantMouseWheel(delta)
		end)
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Hooked MerchantFrame mouse wheel events")
		end
	end

	-- Method 3: Hook merchant update functions
	hooksecurefunc("MerchantFrame_Update", function()
		if DOKI.merchantScrollDetector.isScrolling then
			DOKI:OnMerchantScrollPageChange()
		end
	end)
end

function DOKI:OnMerchantMouseWheel(delta)
	if not (MerchantFrame and MerchantFrame:IsVisible()) then return end

	local direction = delta > 0 and "up" or "down"
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scroll detected: %s", direction))
	end

	-- Mark as scrolling
	self.merchantScrollDetector.isScrolling = true
	-- Reset scroll end timer
	if self.merchantScrollDetector.scrollTimer then
		self.merchantScrollDetector.scrollTimer:Cancel()
	end

	self.merchantScrollDetector.scrollTimer = C_Timer.NewTimer(0.3, function()
		DOKI.merchantScrollDetector.isScrolling = false
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Merchant scrolling ended")
		end
	end)
	-- Immediate response to scroll
	self:OnMerchantScrollPageChange()
end

function DOKI:OnMerchantScrollPosition(scrollPercent)
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scroll position: %.2f", scrollPercent))
	end

	self:OnMerchantScrollPageChange()
end

function DOKI:OnMerchantScrollPageChange()
	if not (MerchantFrame and MerchantFrame:IsVisible()) then return end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Merchant page changed via scroll - updating indicators")
	end

	-- Always update on scroll
	C_Timer.After(0.1, function()
		if self.db and self.db.enabled and MerchantFrame and MerchantFrame:IsVisible() then
			-- Force a surgical update to detect button changes
			local changedCount = self:TriggerImmediateSurgicalUpdate()
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Merchant scroll update: triggered surgical update"))
			end
		end
	end)
end

function DOKI:GetCurrentMerchantState()
	local state = {}
	local numItems = GetMerchantNumItems()
	for i = 1, numItems do
		local itemInfo = C_MerchantFrame.GetItemInfo(i)
		if itemInfo and itemInfo.name then -- Item exists
			state[i] = {
				name = itemInfo.name,
				texture = itemInfo.texture,
				price = itemInfo.price,
				quantity = itemInfo.stackCount,
				available = itemInfo.numAvailable,
				isPurchasable = itemInfo.isPurchasable,
			}
		end
	end

	return state
end

function DOKI:CompareMerchantState(state1, state2)
	if not state1 and not state2 then return true end

	if not state1 or not state2 then return false end

	-- Quick count comparison
	local previousStateItemCount, currentStateItemCount = 0, 0
	for _ in pairs(state1) do previousStateItemCount = previousStateItemCount + 1 end

	for _ in pairs(state2) do currentStateItemCount = currentStateItemCount + 1 end

	if previousStateItemCount ~= currentStateItemCount then return false end

	-- Compare items
	for i, previousStateItem in pairs(state1) do
		local currentStateItem = state2[i]
		if not currentStateItem then return false end

		-- Handle table structures properly
		if type(previousStateItem) == "table" and type(currentStateItem) == "table" then
			if previousStateItem.name ~= currentStateItem.name or previousStateItem.texture ~= currentStateItem.texture or previousStateItem.price ~= currentStateItem.price then
				return false
			end
		else
			-- Fallback for non-table data
			if previousStateItem ~= currentStateItem then return false end
		end
	end

	return true
end

-- ===== ENHANCED DELAYED CLEANUP SCAN SYSTEM =====
function DOKI:ScheduleDelayedCleanupScan()
	-- Cancel any existing delayed scan
	self:CancelDelayedScan()
	-- Reset cancellation flag
	self.delayedScanCancelled = false
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scheduling delayed cleanup scan in 0.2s...")
	end

	-- Schedule new delayed scan
	self.delayedScanTimer = C_Timer.NewTimer(0.2, function()
		-- Check if scan was cancelled
		if DOKI.delayedScanCancelled or not (DOKI.db and DOKI.db.enabled) then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Delayed cleanup scan cancelled")
			end

			return
		end

		-- Only run if relevant UI is still visible
		local anyUIVisible = false
		if ElvUI and DOKI:IsElvUIBagVisible() then
			anyUIVisible = true
		elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
			anyUIVisible = true
		else
			for bagID = 0, NUM_BAG_SLOTS do
				local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
				if containerFrame and containerFrame:IsVisible() then
					anyUIVisible = true
					break
				end
			end
		end

		if not anyUIVisible and not (MerchantFrame and MerchantFrame:IsVisible()) then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Delayed cleanup scan skipped - no UI visible")
			end

			return
		end

		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Running delayed cleanup scan...")
		end

		-- Run a focused surgical update to catch any missed changes
		local cleanupChanges = 0
		if DOKI.ProcessSurgicalUpdate then
			cleanupChanges = DOKI:ProcessSurgicalUpdate()
		end

		if DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Delayed cleanup scan: %d changes found", cleanupChanges))
		end

		-- Clear the timer reference
		DOKI.delayedScanTimer = nil
	end)
end

function DOKI:CancelDelayedScan()
	if self.delayedScanTimer then
		self.delayedScanTimer:Cancel()
		self.delayedScanTimer = nil
		self.delayedScanCancelled = true
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Cancelled pending delayed cleanup scan")
		end
	end
end

-- ===== PERFORMANCE MONITORING =====
function DOKI:GetPerformanceStats()
	local stats = {
		updateInterval = 0.2,
		lastUpdateDuration = self.lastUpdateDuration or 0,
		avgUpdateDuration = self.avgUpdateDuration or 0,
		totalUpdates = self.totalUpdates or 0,
		immediateUpdates = self.immediateUpdates or 0,
		throttledUpdates = self.throttledUpdates or 0,
		activeIndicators = 0,
		texturePoolSize = #(self.texturePool or {}),
		debugMode = self.db and self.db.debugMode or false,
	}
	-- Count active button indicators
	for _, textureData in pairs(self.buttonTextures or {}) do
		if textureData.isActive then
			stats.activeIndicators = stats.activeIndicators + 1
		end
	end

	return stats
end

function DOKI:ShowPerformanceStats()
	local stats = self:GetPerformanceStats()
	print("|cffff69b4DOKI|r === SURGICAL SYSTEM STATS ===")
	print(string.format("Update interval: %.1fs", stats.updateInterval))
	print(string.format("Last update duration: %.3fs", stats.lastUpdateDuration))
	print(string.format("Average update duration: %.3fs", stats.avgUpdateDuration))
	print(string.format("Total updates performed: %d", stats.totalUpdates))
	print(string.format("Immediate updates: %d", stats.immediateUpdates))
	print(string.format("Throttled updates: %d", stats.throttledUpdates))
	print(string.format("Active indicators: %d", stats.activeIndicators))
	print(string.format("Texture pool size: %d", stats.texturePoolSize))
	print(string.format("Debug mode: %s", stats.debugMode and "ON" or "OFF"))
	if stats.lastUpdateDuration > 0.05 then
		print("|cffffff00NOTICE:|r Update duration is moderate (>50ms)")
	else
		print("|cff00ff00GOOD:|r Update performance is optimal (<50ms)")
	end

	print("|cffff69b4DOKI|r === END STATS ===")
end

function DOKI:TrackUpdatePerformance(duration, isImmediate)
	self.lastUpdateDuration = duration
	self.totalUpdates = (self.totalUpdates or 0) + 1
	if isImmediate then
		self.immediateUpdates = (self.immediateUpdates or 0) + 1
	end

	-- Calculate rolling average (last 10 updates)
	if not self.updateDurations then
		self.updateDurations = {}
	end

	table.insert(self.updateDurations, duration)
	if #self.updateDurations > 10 then
		table.remove(self.updateDurations, 1)
	end

	local total = 0
	for _, d in ipairs(self.updateDurations) do
		total = total + d
	end

	self.avgUpdateDuration = total / #self.updateDurations
end

-- ===== ENHANCED SURGICAL UPDATE SYSTEM =====
function DOKI:SurgicalUpdate(isImmediate)
	if not self.db or not self.db.enabled then return 0 end

	local currentTime = GetTime()
	-- Cancel any pending delayed scan since we're doing a real update now
	self:CancelDelayedScan()
	-- Throttling check
	if currentTime - self.lastSurgicalUpdate < self.surgicalUpdateThrottleTime then
		if not self.pendingSurgicalUpdate then
			self.pendingSurgicalUpdate = true
			self.throttledUpdates = (self.throttledUpdates or 0) + 1
			local delay = self.surgicalUpdateThrottleTime - (currentTime - self.lastSurgicalUpdate)
			C_Timer.After(delay, function()
				if self.db and self.db.enabled and self.pendingSurgicalUpdate then
					self.pendingSurgicalUpdate = false
					self:SurgicalUpdate(false)
				end
			end)
		end

		return 0
	end

	self.lastSurgicalUpdate = currentTime
	self.pendingSurgicalUpdate = false
	if self.db.debugMode then
		local updateType = isImmediate and "IMMEDIATE" or "SCHEDULED"
		if isImmediate then
			print(string.format("|cffff69b4DOKI|r === %s SURGICAL UPDATE START ===", updateType))
		end
	end

	local startTime = GetTime()
	local changeCount = 0
	-- Call the button texture system's surgical update
	if self.ProcessSurgicalUpdate then
		changeCount = self:ProcessSurgicalUpdate()
	end

	local updateDuration = GetTime() - startTime
	self:TrackUpdatePerformance(updateDuration, isImmediate)
	-- Schedule delayed cleanup scan for item movement edge cases
	-- Only schedule if this was an immediate update (triggered by item movement)
	if isImmediate and changeCount >= 0 then -- Even if 0 changes, movement might have edge cases
		self:ScheduleDelayedCleanupScan()
	end

	if self.db.debugMode then
		local updateType = isImmediate and "immediate" or "scheduled"
		if isImmediate or changeCount > 0 then
			print(string.format("|cffff69b4DOKI|r %s surgical update: %d changes in %.3fs",
				updateType, changeCount, updateDuration))
			if isImmediate then
				print("|cffff69b4DOKI|r === SURGICAL UPDATE END ===")
			end
		end
	end

	return changeCount
end

function DOKI:TriggerImmediateSurgicalUpdate()
	if not self.db or not self.db.enabled then return end

	-- Cancel any pending delayed scan since we're doing an immediate update
	self:CancelDelayedScan()
	-- Only trigger if relevant UI is visible
	local anyUIVisible = false
	-- Check ElvUI
	if ElvUI and self:IsElvUIBagVisible() then
		anyUIVisible = true
	end

	-- Check Blizzard UI
	if not anyUIVisible then
		if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
			anyUIVisible = true
		end

		if not anyUIVisible then
			for bagID = 0, NUM_BAG_SLOTS do
				local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
				if containerFrame and containerFrame:IsVisible() then
					anyUIVisible = true
					break
				end
			end
		end
	end

	-- Check merchant
	if not anyUIVisible and MerchantFrame and MerchantFrame:IsVisible() then
		anyUIVisible = true
	end

	if anyUIVisible then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Item movement detected - triggering immediate update")
		end

		self:SurgicalUpdate(true) -- This will automatically schedule delayed cleanup
	end
end

function DOKI:FullItemScan(withDelay)
	if not self.db or not self.db.enabled then return 0 end

	-- Add slight delay for battlepet caging timing issues
	if withDelay then
		C_Timer.After(0.15, function()
			if self.db and self.db.enabled then
				self:FullItemScan(false) -- Run without delay on retry
			end
		end)
		return 0
	end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r === ENHANCED FULL SCAN START ===")
	end

	local startTime = GetTime()
	local indicatorCount = 0
	self.foundFramesThisScan = {}
	-- Use standard scanning for bags
	indicatorCount = indicatorCount + self:ScanBagFrames()
	-- Keep original merchant scanning
	indicatorCount = indicatorCount + self:ScanMerchantFrames()
	-- Update snapshot after full scan
	if self.CreateButtonSnapshot then
		self.lastButtonSnapshot = self:CreateButtonSnapshot()
	end

	local scanDuration = GetTime() - startTime
	self:TrackUpdatePerformance(scanDuration, false)
	-- Schedule delayed rescan to catch items that may have failed to load
	if indicatorCount > 0 or self.foundFramesThisScan and #self.foundFramesThisScan > 0 then
		self:ScheduleDelayedFullRescan()
	end

	if self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Enhanced full scan: %d indicators in %.3fs",
			indicatorCount, scanDuration))
		print("|cffff69b4DOKI|r === ENHANCED FULL SCAN END ===")
	end

	return indicatorCount
end

-- Helper function to get item info directly from merchant button
function DOKI:GetItemFromMerchantButton(button, slotIndex)
	if not button then return nil, nil end

	-- Method 1: Check if button has item properties directly (War Within - this works!)
	if button.link and button.hasItem then
		local itemID = self:GetItemID(button.link)
		if itemID then
			return itemID, button.link
		end
	end

	-- Check if button is visible but has no item
	if button:IsVisible() then
		return "EMPTY_SLOT", nil
	end

	return nil, nil
end

-- ===== MERCHANT FRAME SCANNING =====
function DOKI:ScanMerchantFrames()
	local indicatorCount = 0
	if not (MerchantFrame and MerchantFrame:IsVisible()) then
		return 0
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scanning merchant frames...")
	end

	-- Scan only visible merchant button slots (not all API items)
	for i = 1, 12 do -- Most merchants have 10-12 visible slots
		local possibleButtonNames = {
			string.format("MerchantItem%dItemButton", i),
			string.format("MerchantItem%d", i),
		}
		for _, buttonName in ipairs(possibleButtonNames) do
			local button = _G[buttonName]
			if button and button:IsVisible() then
				-- Get item directly from the button
				local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
				-- Skip empty slots entirely for indicator creation
				if itemID and itemID ~= "EMPTY_SLOT" and self:IsCollectibleItem(itemID, itemLink) then
					local isCollected, hasOtherTransmogSources, isPartiallyCollected = self:IsItemCollected(itemID, itemLink)
					-- Only create indicator if NOT collected OR if it needs purple indicator
					if not isCollected or isPartiallyCollected then
						local itemData = {
							itemID = itemID,
							itemLink = itemLink,
							isCollected = isCollected,
							hasOtherTransmogSources = hasOtherTransmogSources,
							isPartiallyCollected = isPartiallyCollected,
							frameType = "merchant",
						}
						-- Try to create indicator
						local success = self:AddButtonIndicator(button, itemData)
						if success then
							indicatorCount = indicatorCount + 1
							if self.db.debugMode then
								local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
								local colorType = isPartiallyCollected and "PURPLE" or (hasOtherTransmogSources and "BLUE" or "ORANGE")
								print(string.format("|cffff69b4DOKI|r Created %s indicator for %s (ID: %d) on %s",
									colorType, itemName, itemID, buttonName))
							end
						end

						table.insert(self.foundFramesThisScan, {
							frame = button,
							frameName = buttonName,
							itemData = itemData,
						})
					else
						if self.db.debugMode then
							local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
							print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) on %s - ALREADY COLLECTED",
								itemName, itemID, buttonName))
						end
					end
				elseif itemID == "EMPTY_SLOT" then
					if self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Skipping %s - EMPTY SLOT", buttonName))
					end
				elseif itemID then
					if self.db.debugMode then
						local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
						print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) on %s - NOT COLLECTIBLE",
							itemName, itemID, buttonName))
					end
				end

				break
			end
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scan complete: %d indicators created", indicatorCount))
	end

	return indicatorCount
end

-- ===== BAG FRAME SCANNING =====
function DOKI:ScanBagFrames()
	if not self.db or not self.db.enabled then return 0 end

	local indicatorCount = 0
	-- Collect all bag items first
	local allBagItems = {}
	-- Scan ElvUI bags if visible
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
								local possibleNames = {
									string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
								}
								for _, elvUIButtonName in ipairs(possibleNames) do
									local elvUIButton = _G[elvUIButtonName]
									if elvUIButton and elvUIButton:IsVisible() then
										allBagItems[elvUIButton] = {
											itemID = itemInfo.itemID,
											itemLink = itemInfo.hyperlink,
											frameType = "bag",
										}
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Scan Blizzard bags
	local scannedBlizzardBags = false
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		-- Combined bags logic
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						local button = nil
						if ContainerFrameCombinedBags.EnumerateValidItems then
							for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
								if itemButton and itemButton:IsVisible() then
									local buttonBagID, buttonSlotID = nil, nil
									if itemButton.GetBagID and itemButton.GetID then
										local bagIDRetrievalSuccess, retrievedBagID = pcall(itemButton.GetBagID, itemButton)
										local slotIDRetrievalSuccess, retrievedBagID = pcall(itemButton.GetID, itemButton)
										if bagIDRetrievalSuccess and slotIDRetrievalSuccess then
											buttonBagID, buttonSlotID = retrievedBagID, retrievedBagID
										end
									end

									if buttonBagID == bagID and buttonSlotID == slotID then
										button = itemButton
										break
									end
								end
							end
						end

						if button then
							allBagItems[button] = {
								itemID = itemInfo.itemID,
								itemLink = itemInfo.hyperlink,
								frameType = "bag",
							}
						end
					end
				end
			end
		end

		scannedBlizzardBags = true
	end

	-- Individual container frames
	if not scannedBlizzardBags then
		for bagID = 0, NUM_BAG_SLOTS do
			local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
			if containerFrame and containerFrame:IsVisible() then
				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
							local possibleNames = {
								string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
								string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
							}
							for _, buttonName in ipairs(possibleNames) do
								local button = _G[buttonName]
								if button and button:IsVisible() then
									allBagItems[button] = {
										itemID = itemInfo.itemID,
										itemLink = itemInfo.hyperlink,
										frameType = "bag",
									}
									break
								end
							end
						end
					end
				end

				scannedBlizzardBags = true
			end
		end
	end

	-- Create indicators for collectible items only
	for button, itemData in pairs(allBagItems) do
		-- FIXED: Check if item is collectible before processing (same logic as merchant scanning)
		if self:IsCollectibleItem(itemData.itemID, itemData.itemLink) then
			local isCollected, hasOtherTransmogSources, isPartiallyCollected = self:IsItemCollected(itemData.itemID,
				itemData.itemLink)
			itemData.isCollected = isCollected
			itemData.hasOtherTransmogSources = hasOtherTransmogSources
			itemData.isPartiallyCollected = isPartiallyCollected
			-- Only create indicator if NOT collected OR if it needs purple indicator
			if not isCollected or isPartiallyCollected then
				indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
			elseif self.db and self.db.debugMode then
				local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
				print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) in bags - ALREADY COLLECTED",
					itemName, itemData.itemID))
			end
		elseif self.db and self.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
			print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) in bags - NOT COLLECTIBLE",
				itemName, itemData.itemID))
		end
	end

	return indicatorCount
end

-- Create universal indicator (only called for items that need indicators)
function DOKI:CreateUniversalIndicator(frame, itemData)
	if not frame or type(frame) ~= "table" then return 0 end

	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Check if indicator already exists for this exact item
	if self.buttonTextures and self.buttonTextures[frame] then
		local existingTexture = self.buttonTextures[frame]
		if existingTexture and existingTexture.isActive and existingTexture.itemID == itemData.itemID then
			return 0
		end
	end

	-- Add button indicator
	if self.AddButtonIndicator then
		local success = self:AddButtonIndicator(frame, itemData)
		return success and 1 or 0
	end

	return 0
end

function DOKI:CleanupMerchantTextures()
	if not self.buttonTextures then return 0 end

	local removedCount = 0
	local toRemove = {}
	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive then
			-- Check if this is a merchant button that's no longer valid
			local buttonName = ""
			local success, name = pcall(button.GetName, button)
			if success and name then
				buttonName = name
			end

			if string.find(buttonName, "Merchant") then
				-- This is a merchant button - check if merchant is still open
				if not (MerchantFrame and MerchantFrame:IsVisible()) then
					table.insert(toRemove, button)
					removedCount = removedCount + 1
				end
			end
		end
	end

	for _, button in ipairs(toRemove) do
		self:RemoveButtonIndicator(button)
	end

	if self.db and self.db.debugMode and removedCount > 0 then
		print(string.format("|cffff69b4DOKI|r Cleaned up %d merchant indicators", removedCount))
	end

	return removedCount
end

-- ===== ENHANCED WAR WITHIN EVENT SYSTEM WITH BETTER MERCHANT SELLING DETECTION =====
function DOKI:SetupMinimalEventSystem()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	-- Enhanced event list with merchant support
	local events = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"MERCHANT_UPDATE", -- Added for merchant page changes
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"ITEM_UNLOCKED",
		"BAG_UPDATE",
		"BAG_UPDATE_DELAYED",
		"ITEM_LOCK_CHANGED",
		"CURSOR_CHANGED",
		-- WAR WITHIN COLLECTION EVENTS (removed noisy ones)
		"PET_JOURNAL_LIST_UPDATE",            -- Main pet event (confirmed working)
		"COMPANION_LEARNED",                  -- Mount/pet learning (confirmed in Blizzard code)
		"COMPANION_UNLEARNED",                -- Mount/pet unlearning (confirmed in Blizzard code)
		"TRANSMOG_COLLECTION_UPDATED",        -- When transmog is collected
		"TOYS_UPDATED",                       -- When toys are learned
		-- Enhanced merchant selling detection
		"MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", -- When selling items
		"UI_INFO_MESSAGE",                    -- For sell confirmations
	}
	for _, event in ipairs(events) do
		self.eventFrame:RegisterEvent(event)
	end

	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		if not (DOKI.db and DOKI.db.enabled) then return end

		-- Cancel delayed scans for most events since they trigger normal scanning
		local cancelDelayedScan = true
		if event == "MERCHANT_SHOW" then
			DOKI.merchantScrollDetector.merchantOpen = true
			DOKI:InitializeMerchantScrollDetection()
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "MERCHANT_UPDATE" then
			-- Detect page changes during scrolling or filter changes
			if DOKI.merchantScrollDetector.merchantOpen then
				C_Timer.After(0.1, function()
					if DOKI.db and DOKI.db.enabled and MerchantFrame and MerchantFrame:IsVisible() then
						DOKI:ScanMerchantFrames()
					end
				end)
			end
		elseif event == "MERCHANT_CLOSED" then
			DOKI.merchantScrollDetector.merchantOpen = false
			DOKI.merchantScrollDetector.lastMerchantState = nil
			if DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			end
		elseif event == "BANKFRAME_OPENED" then
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "BANKFRAME_CLOSED" then
			if DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "ITEM_UNLOCKED" then
			-- Item movement detected - immediate response
			cancelDelayedScan = false -- Let immediate update handle delayed scan scheduling
			C_Timer.After(0.02, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "ITEM_LOCK_CHANGED" or event == "CURSOR_CHANGED" then
			-- Item pickup/drop detected - very immediate response
			cancelDelayedScan = false -- Let immediate update handle delayed scan scheduling
			C_Timer.After(0.01, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" or event == "UI_INFO_MESSAGE" then
			-- Enhanced detection for merchant selling
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Merchant sell event detected - forcing update")
			end

			cancelDelayedScan = false
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "PET_JOURNAL_LIST_UPDATE" or
				event == "COMPANION_LEARNED" or event == "COMPANION_UNLEARNED" then
			-- Collection changed - clear cache and FORCE FULL SCAN WITH DELAY for battlepets
			DOKI:ClearCollectionCache()
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					-- Use withDelay=true for potential battlepet timing issues
					DOKI:FullItemScan(true)
				end
			end)
		elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TOYS_UPDATED" then
			-- Transmog/toy collection changed - clear cache and FORCE FULL SCAN
			DOKI:ClearCollectionCache()
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					-- Force full scan to re-evaluate all visible items
					DOKI:FullItemScan()
				end
			end)
		elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
			-- Check if should update based on UI visibility
			local shouldUpdate = false
			if ElvUI and DOKI:IsElvUIBagVisible() then
				shouldUpdate = true
			elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
				shouldUpdate = true
			else
				for bagID = 0, NUM_BAG_SLOTS do
					local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
					if containerFrame and containerFrame:IsVisible() then
						shouldUpdate = true
						break
					end
				end
			end

			if shouldUpdate then
				cancelDelayedScan = false -- Let immediate update handle delayed scan scheduling
				local delay = (event == "BAG_UPDATE_DELAYED") and 0.1 or 0.05
				C_Timer.After(delay, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end

		-- Cancel delayed scan for events that trigger normal scanning
		if cancelDelayedScan then
			DOKI:CancelDelayedScan()
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced event system initialized with merchant selling detection")
	end
end

-- ===== CLEANUP SYSTEM =====
function DOKI:CleanupCollectionSystem()
	-- Stop delayed scans
	if self.delayedScanTimer then
		self.delayedScanTimer:Cancel()
		self.delayedScanTimer = nil
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Collection system cleaned up")
	end
end

-- Utility function
function DOKI:TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end

	return count
end

-- ===== INITIALIZATION =====
function DOKI:InitializeUniversalScanning()
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Initialize ensemble detection
	self:InitializeEnsembleDetection()
	-- NEW: Initialize cache and debouncing systems
	self:SetupCacheInvalidationEvents() -- This was missing!
	self:SetupDebouncedEventSystem()
	-- Enhanced surgical update timer
	self.surgicalTimer = C_Timer.NewTicker(0.2, function()
		if self.db and self.db.enabled then
			local anyUIVisible = false
			if ElvUI and self:IsElvUIBagVisible() then
				anyUIVisible = true
			elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
				anyUIVisible = true
			else
				for bagID = 0, NUM_BAG_SLOTS do
					local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
					if containerFrame and containerFrame:IsVisible() then
						anyUIVisible = true
						break
					end
				end
			end

			local cursorHasItem = C_Cursor and C_Cursor.GetCursorItem() and true or false
			if anyUIVisible or (MerchantFrame and MerchantFrame:IsVisible()) or cursorHasItem then
				DOKI:SurgicalUpdate(false)
			end
		end
	end)
	-- Use the debounced event system instead of minimal
	-- self:SetupMinimalEventSystem()  -- Remove this line
	self:FullItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced surgical system initialized")
		print("  |cff00ff00•|r Session-long caching enabled")
		print("  |cff00ff00•|r Event debouncing enabled")
		print("  |cff00ff00•|r Cache invalidation events registered")
	end
end

-- ===== DEBUG FUNCTIONS =====
function DOKI:DebugFoundFrames()
	if not self.foundFramesThisScan or #self.foundFramesThisScan == 0 then
		print("|cffff69b4DOKI|r No frames found in last scan. Try /doki scan first.")
		return
	end

	print(string.format("|cffff69b4DOKI|r === FOUND FRAMES DEBUG (%d frames) ===", #self.foundFramesThisScan))
	for i, frameInfo in ipairs(self.foundFramesThisScan) do
		local itemName = C_Item.GetItemInfo(frameInfo.itemData.itemID) or "Unknown"
		local extraInfo = ""
		if frameInfo.itemData.petSpeciesID then
			extraInfo = string.format(" [Pet Species: %d]", frameInfo.itemData.petSpeciesID)
		elseif frameInfo.itemData.isPartiallyCollected then
			extraInfo = " [Purple Indicator]"
		end

		print(string.format("%d. %s (ID: %d) in %s [%s] - %s%s",
			i, itemName, frameInfo.itemData.itemID, frameInfo.frameName,
			frameInfo.itemData.frameType,
			frameInfo.itemData.isCollected and "COLLECTED" or "NOT collected",
			extraInfo))
	end

	print("|cffff69b4DOKI|r === END FOUND FRAMES DEBUG ===")
end

function DOKI:DebugBattlepetSnapshot()
	if not self.CreateButtonSnapshot then
		print("|cffff69b4DOKI|r ButtonTextures system not available")
		return
	end

	local snapshot = self:CreateButtonSnapshot()
	local battlepetCount = 0
	local regularItemCount = 0
	local ensembleCount = 0
	local purpleIndicatorCount = 0
	print("|cffff69b4DOKI|r === BATTLEPET + ENSEMBLE + PURPLE SNAPSHOT DEBUG ===")
	for button, itemData in pairs(snapshot) do
		if type(itemData) == "table" and itemData.itemID then
			if itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
				battlepetCount = battlepetCount + 1
				local speciesID = self:GetPetSpeciesFromBattlePetLink(itemData.itemLink)
				print(string.format("  Battlepet: %s -> Species %d",
					button:GetName() or "unnamed", speciesID or "unknown"))
			elseif self:IsEnsembleItem(itemData.itemID) then
				ensembleCount = ensembleCount + 1
				local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
				print(string.format("  Ensemble: %s -> %s (ID: %d)",
					button:GetName() or "unnamed", itemName, itemData.itemID))
			else
				regularItemCount = regularItemCount + 1
				-- Check if this would get a purple indicator from ATT
				if self.db and self.db.attMode then
					local _, _, isPartiallyCollected = self:GetATTCollectionStatus(itemData.itemID, itemData.itemLink)
					if isPartiallyCollected then
						purpleIndicatorCount = purpleIndicatorCount + 1
						local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
						print(string.format("  Purple Indicator: %s -> %s (ID: %d)",
							button:GetName() or "unnamed", itemName, itemData.itemID))
					end
				end
			end
		else
			regularItemCount = regularItemCount + 1
		end
	end

	print(string.format("Total snapshot items: %d (%d regular, %d battlepets, %d ensembles, %d purple indicators)",
		regularItemCount + battlepetCount + ensembleCount, regularItemCount, battlepetCount, ensembleCount,
		purpleIndicatorCount))
	print("|cffff69b4DOKI|r === END SNAPSHOT DEBUG ===")
end
