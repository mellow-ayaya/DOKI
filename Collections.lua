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
-- Chunked scanning state
DOKI.chunkedScanState = nil
DOKI.CHUNKED_SCAN_DELAYS = {
	STANDARD_MODE = 0.10, -- 50ms between bags in standard mode
	ATT_MODE = 1,        -- 80ms between bags in ATT mode (where FPS spikes occur)

	-- Suggested values to try:
	-- Very fast: 0.02 / 0.04 (might still cause micro-stutters)
	-- Balanced: 0.05 / 0.08 (current default)
	-- Smooth: 0.10 / 0.15 (very smooth but slower scan)
	-- Ultra smooth: 0.20 / 0.30 (for potato PCs)
}
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
-- UI visibility tracking for initial scans
DOKI.lastUIVisibilityState = {
	elvui = false,
	combined = false,
	individual = false,
	merchant = false,
}
DOKI.progressiveFullScanState = nil
DOKI.testingMode = false
-- Enter testing mode - disable all automatic systems
function DOKI:EnterTestingMode()
	print("|cffff00ffTEST MODE|r === ENTERING TESTING MODE ===")
	-- Set testing mode flag
	self.testingMode = true
	-- Cancel all running scans
	print("|cffff00ffTEST MODE|r Cancelling all running scans...")
	self:CancelProgressiveFullScan()
	if self.CancelDedicatedSurgical then
		self:CancelDedicatedSurgical()
	end

	-- Cancel all timers
	print("|cffff00ffTEST MODE|r Cancelling all timers...")
	if self.safetyTimer then
		self.safetyTimer:Cancel()
		self.safetyTimer = nil
	end

	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
		self.surgicalTimer = nil
	end

	-- Clear all indicators and state
	print("|cffff00ffTEST MODE|r Clearing all state...")
	if self.ClearAllButtonIndicators then
		local cleared = self:ClearAllButtonIndicators()
		print(string.format("|cffff00ffTEST MODE|r Cleared %d indicators", cleared))
	end

	-- Clear all snapshots and mappings
	self.lastButtonSnapshot = {}
	if self.buttonItemMap then
		self.buttonItemMap = {}
	end

	-- Clear collection cache
	self:ClearCollectionCache()
	print("|cffff00ffTEST MODE|r Collection cache cleared")
	-- Reset performance tracking
	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Clear scan state variables
	self.progressiveFullScanState = nil
	if self.dedicatedSurgicalState then
		self.dedicatedSurgicalState = nil
	end

	if self.smartSurgicalState then
		self.smartSurgicalState = nil
	end

	print("|cffff00ffTEST MODE|r === TESTING MODE ACTIVE ===")
	print("|cffff00ffTEST MODE|r All automatic scanning disabled")
	print("|cffff00ffTEST MODE|r All timers cancelled")
	print("|cffff00ffTEST MODE|r All state cleared")
	print("|cffff00ffTEST MODE|r Ready for clean testing")
	print("|cffff00ffTEST MODE|r")
	print("|cffff00ffTEST MODE|r Available test commands:")
	print("|cffff00ffTEST MODE|r   /doki testminimal   - Full system test")
	print("|cffff00ffTEST MODE|r   /doki testatt       - ATT parsing only")
	print("|cffff00ffTEST MODE|r   /doki testindicators - Indicator creation only")
	print("|cffff00ffTEST MODE|r")
end

-- Exit testing mode - re-enable automatic systems
function DOKI:ExitTestingMode()
	print("|cffff00ffTEST MODE|r === EXITING TESTING MODE ===")
	-- Clear testing mode flag
	self.testingMode = false
	-- Re-initialize automatic systems
	print("|cffff00ffTEST MODE|r Re-enabling automatic scanning...")
	self:InitializeUniversalScanning()
	print("|cffff00ffTEST MODE|r === TESTING MODE DISABLED ===")
	print("|cffff00ffTEST MODE|r Automatic scanning re-enabled")
	print("|cffff00ffTEST MODE|r Normal operation resumed")
end

-- Check if currently in testing mode
function DOKI:IsInTestingMode()
	return self.testingMode == true
end

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
function DOKI:SetupDebouncedEventSystemWithUIDetection()
	-- SETUP PHASE: Create frame and register events (happens once)
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	-- Define event categories (setup phase)
	local debouncedEvents = {
		"BAG_UPDATE",
		"BAG_UPDATE_DELAYED",
		"ITEM_LOCK_CHANGED",
		"CURSOR_CHANGED",
		"MERCHANT_UPDATE",
	}
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
	local uiVisibilityEvents = {
		"ADDON_LOADED",
		"PLAYER_ENTERING_WORLD",
		"BAG_CONTAINER_UPDATE",
		"BAG_SLOT_FLAGS_UPDATED",
	}
	-- Register all events ONCE (setup phase)
	for _, event in ipairs(debouncedEvents) do
		self.eventFrame:RegisterEvent(event)
	end

	for _, event in ipairs(immediateEvents) do
		self.eventFrame:RegisterEvent(event)
	end

	for _, event in ipairs(uiVisibilityEvents) do
		self.eventFrame:RegisterEvent(event)
	end

	-- Set up the event handler ONCE (setup phase)
	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		-- TESTING MODE: Skip all automatic event processing
		if DOKI:IsInTestingMode() then
			print(string.format("|cffff00ffTEST MODE|r Ignoring event: %s (testing mode active)", event))
			return
		end

		-- Continue with normal event processing only if not in testing mode
		if not (DOKI.db and DOKI.db.enabled) then return end

		print(string.format("|cff00ffff UI DEBUG|r %.3f - Event received: %s", GetTime(), event))
		-- Handle debounced events (item movement)
		if tContains(debouncedEvents, event) then
			print("|cff00ffff UI DEBUG|r - Debouncing surgical update for item movement")
			DOKI:DebouncedSurgicalUpdate(event, false)
			return
		end

		-- Handle immediate events
		if event == "MERCHANT_SHOW" then
			DOKI.merchantScrollDetector.merchantOpen = true
			DOKI:InitializeMerchantScrollDetection()
			DOKI:OnUIBecameVisible("MERCHANT_SHOW")
		elseif event == "MERCHANT_CLOSED" then
			DOKI.merchantScrollDetector.merchantOpen = false
			DOKI.merchantScrollDetector.lastMerchantState = nil
			if DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			end
		elseif event == "BANKFRAME_OPENED" then
			DOKI:OnUIBecameVisible("BANKFRAME_OPENED")
		elseif event == "BANKFRAME_CLOSED" then
			if DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" or event == "UI_INFO_MESSAGE" then
			DOKI:DebounceEvent("MERCHANT_SELL", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end, 0.05)
		elseif event == "PET_JOURNAL_LIST_UPDATE" or
				event == "COMPANION_LEARNED" or
				event == "COMPANION_UNLEARNED" then
			DOKI:DebounceEvent("COLLECTION_CHANGE", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan(true) -- Use withDelay for battlepet timing
				end
			end, 0.1)
		elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TOYS_UPDATED" then
			DOKI:DebounceEvent("COLLECTION_CHANGE", function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end, 0.1)
			-- Handle potential UI visibility events
		elseif tContains(uiVisibilityEvents, event) then
			print("|cff00ffff UI DEBUG|r - Checking for UI visibility changes")
			C_Timer.After(0.1, function() -- Small delay to let UI settle
				if DOKI.db and DOKI.db.enabled then
					local currentUIState = DOKI:GetCurrentUIVisibilityState()
					local stateChanged = DOKI:CompareUIVisibilityStates(DOKI.lastUIVisibilityState, currentUIState)
					if stateChanged then
						DOKI:OnUIBecameVisible(event)
					end

					DOKI.lastUIVisibilityState = currentUIState
				end
			end)
		end
	end)
	-- Debug output (setup phase)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced event system with UI detection initialized")
		print(string.format("  Debounced events: %d", #debouncedEvents))
		print(string.format("  Immediate events: %d", #immediateEvents))
		print(string.format("  UI visibility events: %d", #uiVisibilityEvents))
	end
end

function DOKI:ParseBagSpec(bagSpec)
	if not bagSpec or bagSpec == "" or bagSpec == "all" then
		-- Scan all bags
		local allBags = {}
		for bagID = 0, NUM_BAG_SLOTS do
			table.insert(allBags, bagID)
		end

		return allBags
	end

	-- Parse comma-separated list (e.g., "0,1,2")
	local selectedBags = {}
	for bagIDStr in string.gmatch(bagSpec, "([^,]+)") do
		local bagID = tonumber(strtrim(bagIDStr))
		if bagID and bagID >= 0 and bagID <= NUM_BAG_SLOTS then
			table.insert(selectedBags, bagID)
		else
			print(string.format("|cffff00ffTEST|r Invalid bag ID: %s (must be 0-%d)", bagIDStr, NUM_BAG_SLOTS))
		end
	end

	if #selectedBags == 0 then
		print("|cffff00ffTEST|r No valid bags specified, using all bags")
		return self:ParseBagSpec("all")
	end

	return selectedBags
end

-- Enhanced ATT parsing test with bag selection
function DOKI:TestATTParsingOnlySelective(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === SELECTIVE ATT PARSING TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local itemsProcessed = 0
	local collectibleItems = 0
	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then
		print("|cffff00ffTEST|r No bags visible")
		return 0
	end

	print(string.format("|cffff00ffTEST|r Active bag system: %s", activeBagSystem))
	-- Scan only selected bags
	for _, bagID in ipairs(selectedBags) do
		print(string.format("|cffff00ffTEST|r Scanning bag %d...", bagID))
		local bagStartTime = GetTime()
		local bagItems = 0
		local bagCollectible = 0
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			print(string.format("|cffff00ffTEST|r   Bag %d has %d slots", bagID, numSlots))
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					bagItems = bagItems + 1
					-- Only test ATT parsing (no button finding)
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						collectibleItems = collectibleItems + 1
						bagCollectible = bagCollectible + 1
						local isCollected = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						-- Do nothing with the result - just parse
					end
				end
			end
		end

		local bagDuration = GetTime() - bagStartTime
		print(string.format("|cffff00ffTEST|r   Bag %d: %d items (%d collectible) in %.3fs",
			bagID, bagItems, bagCollectible, bagDuration))
	end

	local totalDuration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r === SELECTIVE ATT TEST COMPLETE ==="))
	print(string.format("|cffff00ffTEST|r %d items processed (%d collectible) in %.3fs",
		itemsProcessed, collectibleItems, totalDuration))
	print(string.format("|cffff00ffTEST|r Average: %.3fs per item",
		collectibleItems > 0 and (totalDuration / collectibleItems) or 0))
	return itemsProcessed
end

-- Enhanced indicator test with bag selection
function DOKI:TestIndicatorCreationOnlySelective(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === SELECTIVE INDICATOR CREATION TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local indicatorsCreated = 0
	-- Clear existing first
	if self.ClearAllButtonIndicators then
		self:ClearAllButtonIndicators()
	end

	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then
		print("|cffff00ffTEST|r No bags visible")
		return 0
	end

	print(string.format("|cffff00ffTEST|r Active bag system: %s", activeBagSystem))
	-- Create indicators only on selected bags
	for _, bagID in ipairs(selectedBags) do
		print(string.format("|cffff00ffTEST|r Processing bag %d...", bagID))
		local bagStartTime = GetTime()
		local bagIndicators = 0
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					local button = nil
					if activeBagSystem == "elvui" then
						button = self:FindElvUIButton(bagID, slotID)
					elseif activeBagSystem == "combined" then
						button = self:FindCombinedButton(bagID, slotID)
					elseif activeBagSystem == "individual" then
						button = self:FindIndividualButton(bagID, slotID)
					end

					if button then
						-- Create test indicator (no collection checking)
						local testItemData = {
							itemID = itemInfo.itemID,
							itemLink = itemInfo.hyperlink,
							isCollected = false, -- Always create indicator
							hasOtherTransmogSources = false,
							isPartiallyCollected = false,
							frameType = "test",
						}
						if self:CreateUniversalIndicator(button, testItemData) > 0 then
							indicatorsCreated = indicatorsCreated + 1
							bagIndicators = bagIndicators + 1
						end
					end
				end
			end
		end

		local bagDuration = GetTime() - bagStartTime
		print(string.format("|cffff00ffTEST|r   Bag %d: %d indicators in %.3fs",
			bagID, bagIndicators, bagDuration))
	end

	local totalDuration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r === SELECTIVE INDICATOR TEST COMPLETE ==="))
	print(string.format("|cffff00ffTEST|r %d indicators created in %.3fs", indicatorsCreated, totalDuration))
	print(string.format("|cffff00ffTEST|r Average: %.3fs per indicator",
		indicatorsCreated > 0 and (totalDuration / indicatorsCreated) or 0))
	return indicatorsCreated
end

-- Enhanced minimal test with bag selection
function DOKI:MinimalTestScanSelective(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === SELECTIVE MINIMAL TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	-- Clear existing indicators first
	if self.ClearAllButtonIndicators then
		self:ClearAllButtonIndicators()
	end

	local indicatorCount = 0
	local itemsProcessed = 0
	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then
		print("|cffff00ffTEST|r No bags visible")
		return 0
	end

	print(string.format("|cffff00ffTEST|r Active bag system: %s", activeBagSystem))
	-- Process only selected bags
	for _, bagID in ipairs(selectedBags) do
		print(string.format("|cffff00ffTEST|r Processing bag %d...", bagID))
		local bagStartTime = GetTime()
		local bagIndicators = 0
		local bagItems = 0
		if activeBagSystem == "elvui" then
			bagIndicators, bagItems = self:MinimalScanElvUIBag(bagID)
		elseif activeBagSystem == "combined" then
			bagIndicators, bagItems = self:MinimalScanCombinedBag(bagID)
		elseif activeBagSystem == "individual" then
			bagIndicators, bagItems = self:MinimalScanIndividualBag(bagID)
		end

		indicatorCount = indicatorCount + bagIndicators
		itemsProcessed = itemsProcessed + bagItems
		local bagDuration = GetTime() - bagStartTime
		print(string.format("|cffff00ffTEST|r   Bag %d: %d items, %d indicators in %.3fs",
			bagID, bagItems, bagIndicators, bagDuration))
	end

	local totalDuration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r === SELECTIVE MINIMAL TEST COMPLETE ==="))
	print(string.format("|cffff00ffTEST|r %d items processed, %d indicators created in %.3fs",
		itemsProcessed, indicatorCount, totalDuration))
	print(string.format("|cffff00ffTEST|r Average: %.3fs per indicator",
		indicatorCount > 0 and (totalDuration / indicatorCount) or 0))
	return indicatorCount
end

-- Helper functions for single bag scanning
function DOKI:MinimalScanElvUIBag(bagID)
	local indicatorCount = 0
	local itemsProcessed = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if numSlots and numSlots > 0 then
		for slotID = 1, numSlots do
			local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
				itemsProcessed = itemsProcessed + 1
				local button = self:FindElvUIButton(bagID, slotID)
				if button then
					if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
						indicatorCount = indicatorCount + 1
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

function DOKI:MinimalScanCombinedBag(bagID)
	local indicatorCount = 0
	local itemsProcessed = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if numSlots and numSlots > 0 then
		for slotID = 1, numSlots do
			local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
				itemsProcessed = itemsProcessed + 1
				local button = self:FindCombinedButton(bagID, slotID)
				if button then
					if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
						indicatorCount = indicatorCount + 1
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

function DOKI:MinimalScanIndividualBag(bagID)
	local indicatorCount = 0
	local itemsProcessed = 0
	local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
	if containerFrame and containerFrame:IsVisible() then
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					local button = self:FindIndividualButton(bagID, slotID)
					if button then
						if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
							indicatorCount = indicatorCount + 1
						end
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

-- Test 1: Only itemLink generation (no tooltip work)
function DOKI:TestItemLinkGenerationOnly(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === ITEMLINK GENERATION TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local itemsProcessed = 0
	local linksGenerated = 0
	for _, bagID in ipairs(selectedBags) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					itemsProcessed = itemsProcessed + 1
					-- Test itemLink generation
					local itemLink = itemInfo.hyperlink
					if not itemLink then
						-- Try to get it via API
						itemLink = C_Container.GetContainerItemLink(bagID, slotID)
					end

					if not itemLink then
						-- Try to generate via GetItemInfo
						local _, generatedLink = C_Item.GetItemInfo(itemInfo.itemID)
						itemLink = generatedLink
					end

					if itemLink then
						linksGenerated = linksGenerated + 1
						-- Check if collectible (no ATT parsing)
						local isCollectible = self:IsCollectibleItem(itemInfo.itemID, itemLink)
						-- Do nothing with result - just test link generation
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r ItemLink generation: %d items, %d links in %.3fs",
		itemsProcessed, linksGenerated, duration))
	return itemsProcessed
end

-- Test 2: Tooltip creation and cleanup (no item setting)
function DOKI:TestTooltipCreationOnly(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === TOOLTIP CREATION TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local tooltipsCreated = 0
	for _, bagID in ipairs(selectedBags) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						tooltipsCreated = tooltipsCreated + 1
						-- Test tooltip creation and cleanup only
						local tooltip = GameTooltip
						tooltip:Hide()
						tooltip:ClearLines()
						tooltip:SetOwner(UIParent, "ANCHOR_NONE")
						-- Don't set the item - just create/cleanup
						tooltip:Hide()
						tooltip:ClearLines()
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r Tooltip creation: %d tooltips in %.3fs", tooltipsCreated, duration))
	return tooltipsCreated
end

-- Test 3: Tooltip item setting (triggers ATT injection)
function DOKI:TestTooltipItemSettingOnly(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === TOOLTIP ITEM SETTING TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local tooltipsSet = 0
	for _, bagID in ipairs(selectedBags) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						tooltipsSet = tooltipsSet + 1
						-- Test tooltip item setting (this triggers ATT)
						local tooltip = GameTooltip
						tooltip:Hide()
						tooltip:ClearLines()
						tooltip:SetOwner(UIParent, "ANCHOR_NONE")
						-- THIS IS THE EXPENSIVE PART - setting the item triggers ATT
						if itemInfo.hyperlink then
							tooltip:SetHyperlink(itemInfo.hyperlink)
						else
							tooltip:SetItemByID(itemInfo.itemID)
						end

						tooltip:Show()
						-- Don't parse - just set item and cleanup
						tooltip:Hide()
						tooltip:ClearLines()
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r Tooltip item setting: %d items in %.3fs", tooltipsSet, duration))
	return tooltipsSet
end

-- Test 4: Tooltip parsing only (assume tooltip already populated)
function DOKI:TestTooltipParsingOnly(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === TOOLTIP PARSING TEST ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local startTime = GetTime()
	local tooltipsParsed = 0
	for _, bagID in ipairs(selectedBags) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						tooltipsParsed = tooltipsParsed + 1
						-- Set up tooltip with item (expensive part)
						local tooltip = GameTooltip
						tooltip:Hide()
						tooltip:ClearLines()
						tooltip:SetOwner(UIParent, "ANCHOR_NONE")
						if itemInfo.hyperlink then
							tooltip:SetHyperlink(itemInfo.hyperlink)
						else
							tooltip:SetItemByID(itemInfo.itemID)
						end

						tooltip:Show()
						-- Wait for ATT to inject data, then test parsing speed
						C_Timer.After(0.001, function()
							local parseStartTime = GetTime()
							-- Test only the parsing logic (this should be fast)
							local attStatus, hasOtherTransmogSources, isPartiallyCollected =
									DOKI:ParseATTTooltipFromGameTooltipEnhanced(itemInfo.itemID)
							local parseTime = GetTime() - parseStartTime
							tooltip:Hide()
							tooltip:ClearLines()
							-- Don't print per-item to avoid spam, just accumulate
						end)
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r Tooltip parsing test: %d items in %.3fs", tooltipsParsed, duration))
	print("|cffff00ffTEST|r Note: This includes tooltip setting time - parsing time is negligible")
	return tooltipsParsed
end

-- Test 5: Full ATT pipeline with timing breakdown
function DOKI:TestATTFullPipelineBreakdown(bagSpec)
	local selectedBags = self:ParseBagSpec(bagSpec)
	print("|cffff00ffTEST|r === ATT FULL PIPELINE BREAKDOWN ===")
	print(string.format("|cffff00ffTEST|r Testing bags: %s", table.concat(selectedBags, ", ")))
	local totalStartTime = GetTime()
	local itemsProcessed = 0
	local timings = {
		linkGeneration = 0,
		tooltipSetup = 0,
		itemSetting = 0,
		attWait = 0,
		parsing = 0,
		cleanup = 0,
	}
	for _, bagID in ipairs(selectedBags) do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						itemsProcessed = itemsProcessed + 1
						-- Step 1: Link generation
						local step1Start = GetTime()
						local itemLink = itemInfo.hyperlink
						timings.linkGeneration = timings.linkGeneration + (GetTime() - step1Start)
						-- Step 2: Tooltip setup
						local step2Start = GetTime()
						local tooltip = GameTooltip
						tooltip:Hide()
						tooltip:ClearLines()
						tooltip:SetOwner(UIParent, "ANCHOR_NONE")
						timings.tooltipSetup = timings.tooltipSetup + (GetTime() - step2Start)
						-- Step 3: Item setting (triggers ATT)
						local step3Start = GetTime()
						if itemLink then
							tooltip:SetHyperlink(itemLink)
						else
							tooltip:SetItemByID(itemInfo.itemID)
						end

						tooltip:Show()
						timings.itemSetting = timings.itemSetting + (GetTime() - step3Start)
						-- Step 4: ATT processing wait
						local step4Start = GetTime()
						-- ATT injects data asynchronously, simulate wait
						timings.attWait = timings.attWait + (GetTime() - step4Start)
						-- Step 5: Parsing
						local step5Start = GetTime()
						local attStatus = self:ParseATTTooltipFromGameTooltipEnhanced(itemInfo.itemID)
						timings.parsing = timings.parsing + (GetTime() - step5Start)
						-- Step 6: Cleanup
						local step6Start = GetTime()
						tooltip:Hide()
						tooltip:ClearLines()
						timings.cleanup = timings.cleanup + (GetTime() - step6Start)
					end
				end
			end
		end
	end

	local totalDuration = GetTime() - totalStartTime
	print(string.format("|cffff00ffTEST|r === ATT PIPELINE BREAKDOWN RESULTS ==="))
	print(string.format("|cffff00ffTEST|r Total items: %d, Total time: %.3fs", itemsProcessed, totalDuration))
	print(string.format("|cffff00ffTEST|r Average per item: %.3fs",
		itemsProcessed > 0 and (totalDuration / itemsProcessed) or 0))
	print(string.format("|cffff00ffTEST|r"))
	print(string.format("|cffff00ffTEST|r Step breakdown:"))
	print(string.format("|cffff00ffTEST|r   Link generation: %.3fs (%.1f%%)", timings.linkGeneration,
		(timings.linkGeneration / totalDuration) * 100))
	print(string.format("|cffff00ffTEST|r   Tooltip setup:   %.3fs (%.1f%%)", timings.tooltipSetup,
		(timings.tooltipSetup / totalDuration) * 100))
	print(string.format("|cffff00ffTEST|r   Item setting:    %.3fs (%.1f%%)", timings.itemSetting,
		(timings.itemSetting / totalDuration) * 100))
	print(string.format("|cffff00ffTEST|r   ATT wait:        %.3fs (%.1f%%)", timings.attWait,
		(timings.attWait / totalDuration) * 100))
	print(string.format("|cffff00ffTEST|r   Parsing:         %.3fs (%.1f%%)", timings.parsing,
		(timings.parsing / totalDuration) * 100))
	print(string.format("|cffff00ffTEST|r   Cleanup:         %.3fs (%.1f%%)", timings.cleanup,
		(timings.cleanup / totalDuration) * 100))
	return itemsProcessed
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
	-- REMOVED: CancelDelayedScan() - no more delayed scans!
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
	-- Call the button texture system's smart surgical update
	if self.ProcessSurgicalUpdate then
		changeCount = self:ProcessSurgicalUpdate()
	end

	local updateDuration = GetTime() - startTime
	self:TrackUpdatePerformance(updateDuration, isImmediate)
	-- REMOVED: No more delayed cleanup scans!
	-- REMOVED: if isImmediate and changeCount >= 0 then self:ScheduleDelayedCleanupScan() end
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

	-- REMOVED: CancelDelayedScan() - no more delayed scans!
	-- Only trigger if relevant UI is visible
	local anyUIVisible = false
	if ElvUI and self:IsElvUIBagVisible() then
		anyUIVisible = true
	end

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

	if not anyUIVisible and MerchantFrame and MerchantFrame:IsVisible() then
		anyUIVisible = true
	end

	if anyUIVisible then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Item movement detected - triggering immediate update")
		end

		self:SurgicalUpdate(true) -- REMOVED: No automatic delayed cleanup scheduling
	end
end

function DOKI:FullItemScan(withDelay)
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - FullItemScan called (withDelay: %s)",
		GetTime(), tostring(withDelay)))
	if not self.db or not self.db.enabled then
		print("|cffff0000FULL SCAN DEBUG|r - ABORTED: addon disabled")
		return 0
	end

	-- Add slight delay for battlepet caging timing issues
	if withDelay then
		print("|cffff0000FULL SCAN DEBUG|r - Scheduling delayed full scan...")
		C_Timer.After(0.15, function()
			if self.db and self.db.enabled then
				print("|cffff0000FULL SCAN DEBUG|r - Starting delayed full scan")
				DOKI:StartProgressiveFullScan()
			end
		end)
		return 0
	end

	print("|cffff0000FULL SCAN DEBUG|r - Starting immediate full scan")
	return self:StartProgressiveFullScan()
end

-- Dedicated progressive full scan (always processes ALL bags)
function DOKI:StartProgressiveFullScan()
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - StartProgressiveFullScan called", GetTime()))
	if not self.db or not self.db.enabled then
		print("|cffff0000FULL SCAN DEBUG|r - ABORTED: addon disabled")
		return 0
	end

	-- Cancel any existing full scan
	self:CancelProgressiveFullScan()
	print("|cffff0000FULL SCAN DEBUG|r - Initializing progressive full scan state")
	-- Initialize dedicated full scan state
	self.progressiveFullScanState = {
		phase = "bags",   -- "bags", "merchant", "complete"
		bagID = 0,        -- Current bag being processed
		scanType = "elvui", -- "elvui", "combined", "individual"
		indicatorCount = 0,
		startTime = GetTime(),
		foundFrames = {},
	}
	-- Reset foundFramesThisScan (like original)
	self.foundFramesThisScan = {}
	print("|cffff0000FULL SCAN DEBUG|r - Starting first full scan chunk")
	-- Start immediately with first chunk
	self:ProcessNextFullScanChunk()
	return 0
end

-- Process one chunk of the full scan
function DOKI:ProcessNextFullScanChunk()
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - ProcessNextFullScanChunk called", GetTime()))
	if not self.progressiveFullScanState or not (self.db and self.db.enabled) then
		print("|cffff0000FULL SCAN DEBUG|r - ABORTED: no full scan state or addon disabled")
		return
	end

	local state = self.progressiveFullScanState
	print(string.format("|cffff0000FULL SCAN DEBUG|r - Phase: %s, BagID: %d, ScanType: %s",
		state.phase, state.bagID, state.scanType))
	-- Check if UI is still visible
	if not self:IsAnyRelevantUIVisible() then
		print("|cffff0000FULL SCAN DEBUG|r - CANCELLED: UI no longer visible")
		self:CancelProgressiveFullScan()
		return
	end

	if state.phase == "bags" then
		self:ProcessFullScanBagChunk()
	elseif state.phase == "merchant" then
		self:ProcessFullScanMerchantChunk()
	elseif state.phase == "complete" then
		self:CompleteProgressiveFullScan()
	end
end

-- Process one bag in full scan mode
function DOKI:ProcessFullScanBagChunk()
	local state = self.progressiveFullScanState
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - Processing full scan bag %d (%s)",
		GetTime(), state.bagID, state.scanType))
	local indicatorCount = 0
	-- QUICK FIX 1: Only process the active bag system (skip invisible UI)
	local activeBagSystem = self:GetActiveBagSystem()
	if state.scanType == "elvui" then
		if activeBagSystem == "elvui" then
			print("|cffff0000FULL SCAN DEBUG|r - Processing ElvUI full scan bag (active)")
			indicatorCount = self:ProcessElvUIBagWithATTChunking(state.bagID)
		else
			print("|cffff0000FULL SCAN DEBUG|r - Skipping ElvUI bag (not active)")
		end

		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000FULL SCAN DEBUG|r - ElvUI full scan complete, moving to combined")
			state.scanType = "combined"
			state.bagID = 0
		end
	elseif state.scanType == "combined" then
		if activeBagSystem == "combined" then
			print("|cffff0000FULL SCAN DEBUG|r - Processing combined full scan bag (active)")
			indicatorCount = self:ProcessCombinedBagWithATTChunking(state.bagID)
		else
			print("|cffff0000FULL SCAN DEBUG|r - Skipping combined bag (not active)")
		end

		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000FULL SCAN DEBUG|r - Combined full scan complete, moving to individual")
			state.scanType = "individual"
			state.bagID = 0
		end
	elseif state.scanType == "individual" then
		if activeBagSystem == "individual" then
			print("|cffff0000FULL SCAN DEBUG|r - Processing individual full scan bag (active)")
			indicatorCount = self:ProcessIndividualBagWithATTChunking(state.bagID)
		else
			print("|cffff0000FULL SCAN DEBUG|r - Skipping individual bag (not active)")
		end

		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000FULL SCAN DEBUG|r - Individual full scan complete, moving to merchant")
			state.phase = "merchant"
		end
	end

	state.indicatorCount = state.indicatorCount + indicatorCount
	print(string.format("|cffff0000FULL SCAN DEBUG|r - Full scan bag processed: %d indicators (total: %d)",
		indicatorCount, state.indicatorCount))
	-- Schedule next chunk (same timing as before)
	if state.phase == "bags" then
		local delay = self.db.attMode and self.CHUNKED_SCAN_DELAYS.ATT_MODE or self.CHUNKED_SCAN_DELAYS.STANDARD_MODE
		print(string.format("|cffff0000FULL SCAN DEBUG|r - Scheduling next full scan chunk in %.3fs (ATT mode: %s)",
			delay, tostring(self.db.attMode)))
		C_Timer.After(delay, function()
			if DOKI.progressiveFullScanState then
				print("|cffff0000FULL SCAN DEBUG|r - Full scan timer fired")
				DOKI:ProcessNextFullScanChunk()
			else
				print("|cffff0000FULL SCAN DEBUG|r - Full scan timer fired but state is gone!")
			end
		end)
	else
		print("|cffff0000FULL SCAN DEBUG|r - Moving to next full scan phase immediately")
		self:ProcessNextFullScanChunk()
	end
end

-- Process merchant in full scan
function DOKI:ProcessFullScanMerchantChunk()
	local state = self.progressiveFullScanState
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - Processing full scan merchant", GetTime()))
	local merchantIndicators = self:ScanMerchantFrames()
	state.indicatorCount = state.indicatorCount + merchantIndicators
	print(string.format("|cffff0000FULL SCAN DEBUG|r - Full scan merchant processed: %d indicators", merchantIndicators))
	state.phase = "complete"
	self:ProcessNextFullScanChunk()
end

-- Complete the full scan
function DOKI:CompleteProgressiveFullScan()
	local state = self.progressiveFullScanState
	if not state then
		print("|cffff0000FULL SCAN DEBUG|r - CompleteProgressiveFullScan called but no state!")
		return
	end

	local scanDuration = GetTime() - state.startTime
	local indicatorCount = state.indicatorCount
	print(string.format("|cffff0000FULL SCAN DEBUG|r %.3f - Progressive full scan complete: %d indicators in %.3fs",
		GetTime(), indicatorCount, scanDuration))
	-- Update snapshot after scan (same as original)
	if self.CreateButtonSnapshot then
		self.lastButtonSnapshot = self:CreateButtonSnapshot()
	end

	-- Track performance (same as original)
	self:TrackUpdatePerformance(scanDuration, false)
	-- REMOVED: No more delayed rescans!
	-- REMOVED: self:ScheduleDelayedFullRescan()
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Progressive full scan complete: %d indicators in %.3fs",
			indicatorCount, scanDuration))
	end

	-- Clean up
	self.progressiveFullScanState = nil
	return indicatorCount
end

-- Cancel progressive full scan
function DOKI:CancelProgressiveFullScan()
	if self.progressiveFullScanState then
		print("|cffff0000FULL SCAN DEBUG|r - Progressive full scan cancelled")
		self.progressiveFullScanState = nil
	end
end

-- Main chunked scanning function
function DOKI:StartChunkedFullScan()
	print(string.format("|cffff0000SCAN DEBUG|r %.3f - StartChunkedFullScan called", GetTime()))
	if not self.db or not self.db.enabled then
		print("|cffff0000SCAN DEBUG|r - ABORTED: addon disabled in chunked scan")
		return 0
	end

	-- Cancel any existing scan
	self:CancelChunkedScan()
	print("|cffff0000SCAN DEBUG|r - Initializing chunked scan state")
	-- Initialize scan state
	self.chunkedScanState = {
		phase = "bags",   -- "bags", "merchant", "complete"
		bagID = 0,        -- Current bag being processed
		scanType = "elvui", -- "elvui", "combined", "individual"
		indicatorCount = 0,
		startTime = GetTime(),
		foundFrames = {},
	}
	-- Reset foundFramesThisScan (like original function)
	self.foundFramesThisScan = {}
	print("|cffff0000SCAN DEBUG|r - Calling first ProcessNextScanChunk")
	-- Start immediately with first chunk
	self:ProcessNextScanChunk()
	return 0 -- Will return actual count when complete
end

-- Process one chunk of the scan
function DOKI:ProcessNextScanChunk()
	print(string.format("|cffff0000SCAN DEBUG|r %.3f - ProcessNextScanChunk called", GetTime()))
	if not self.chunkedScanState or not (self.db and self.db.enabled) then
		print("|cffff0000SCAN DEBUG|r - ABORTED: no scan state or addon disabled")
		return
	end

	local state = self.chunkedScanState
	print(string.format("|cffff0000SCAN DEBUG|r - Phase: %s, BagID: %d, ScanType: %s",
		state.phase, state.bagID, state.scanType))
	-- Check if UI is still visible (cancel if closed)
	if not self:IsAnyRelevantUIVisible() then
		print("|cffff0000SCAN DEBUG|r - CANCELLED: UI no longer visible")
		self:CancelChunkedScan()
		return
	end

	if state.phase == "bags" then
		self:ProcessBagChunk()
	elseif state.phase == "merchant" then
		self:ProcessMerchantChunk()
	elseif state.phase == "complete" then
		self:CompleteChunkedScan()
	end
end

-- Process one bag worth of items
function DOKI:ProcessBagChunk()
	local state = self.chunkedScanState
	print(string.format("|cffff0000SCAN DEBUG|r %.3f - Processing bag %d (%s)",
		GetTime(), state.bagID, state.scanType))
	local indicatorCount = 0
	-- Process current bag based on scan type
	if state.scanType == "elvui" then
		print("|cffff0000SCAN DEBUG|r - Processing ElvUI bag")
		indicatorCount = self:ProcessElvUIBag(state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000SCAN DEBUG|r - ElvUI bags complete, moving to combined")
			state.scanType = "combined"
			state.bagID = 0
		end
	elseif state.scanType == "combined" then
		print("|cffff0000SCAN DEBUG|r - Processing combined bag")
		indicatorCount = self:ProcessCombinedBag(state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000SCAN DEBUG|r - Combined bags complete, moving to individual")
			state.scanType = "individual"
			state.bagID = 0
		end
	elseif state.scanType == "individual" then
		print("|cffff0000SCAN DEBUG|r - Processing individual bag")
		indicatorCount = self:ProcessIndividualBag(state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cffff0000SCAN DEBUG|r - Individual bags complete, moving to merchant")
			state.phase = "merchant"
		end
	end

	state.indicatorCount = state.indicatorCount + indicatorCount
	print(string.format("|cffff0000SCAN DEBUG|r - Bag %d processed: %d indicators (total: %d)",
		state.bagID - 1, indicatorCount, state.indicatorCount))
	-- Schedule next chunk with delays
	if state.phase == "bags" then
		local delay = self.db.attMode and self.CHUNKED_SCAN_DELAYS.ATT_MODE or self.CHUNKED_SCAN_DELAYS.STANDARD_MODE
		print(string.format("|cffff0000SCAN DEBUG|r - Scheduling next chunk in %.3fs (ATT mode: %s)",
			delay, tostring(self.db.attMode)))
		C_Timer.After(delay, function()
			if DOKI.chunkedScanState then
				print("|cffff0000SCAN DEBUG|r - Timer fired, calling ProcessNextScanChunk")
				DOKI:ProcessNextScanChunk()
			else
				print("|cffff0000SCAN DEBUG|r - Timer fired but scan state is gone!")
			end
		end)
	else
		print("|cffff0000SCAN DEBUG|r - Moving to next phase immediately")
		self:ProcessNextScanChunk()
	end
end

-- Process merchant phase (keep existing logic)
function DOKI:ProcessMerchantChunk()
	local state = self.chunkedScanState
	print(string.format("|cffff0000SCAN DEBUG|r %.3f - Processing merchant phase", GetTime()))
	-- Merchant scanning is already fast, no need to chunk
	local merchantIndicators = self:ScanMerchantFrames()
	state.indicatorCount = state.indicatorCount + merchantIndicators
	print(string.format("|cffff0000SCAN DEBUG|r - Merchant processed: %d indicators", merchantIndicators))
	state.phase = "complete"
	self:ProcessNextScanChunk()
end

-- Complete the chunked scan
function DOKI:CompleteChunkedScan()
	local state = self.chunkedScanState
	if not state then
		print("|cffff0000SCAN DEBUG|r - CompleteChunkedScan called but no state!")
		return
	end

	local scanDuration = GetTime() - state.startTime
	local indicatorCount = state.indicatorCount
	print(string.format("|cffff0000SCAN DEBUG|r %.3f - Chunked scan complete: %d indicators in %.3fs",
		GetTime(), indicatorCount, scanDuration))
	-- Update snapshot after scan (same as original)
	if self.CreateButtonSnapshot then
		self.lastButtonSnapshot = self:CreateButtonSnapshot()
	end

	-- Track performance (same as original)
	self:TrackUpdatePerformance(scanDuration, false)
	-- Schedule delayed rescan if needed (same as original)
	if indicatorCount > 0 or (#state.foundFrames > 0) then
		self:ScheduleDelayedFullRescan()
	end

	-- Clean up
	self.chunkedScanState = nil
	return indicatorCount
end

-- Cancel chunked scan
function DOKI:CancelChunkedScan()
	if self.chunkedScanState then
		print("|cffff0000SCAN DEBUG|r - Chunked scan cancelled")
		self.chunkedScanState = nil
	end
end

-- Process ElvUI bag (extracted from ScanBagFrames)
function DOKI:ProcessElvUIBag(bagID)
	if not ElvUI or not self:IsElvUIBagVisible() then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000SCAN DEBUG|r - ElvUI bag %d has %d slots", bagID, numSlots))
	for slotID = 1, numSlots do
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
			local possibleNames = {
				string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
				string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
				string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
			}
			for _, buttonName in ipairs(possibleNames) do
				local button = _G[buttonName]
				if button and button:IsVisible() then
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						local isCollected, hasOtherTransmogSources, isPartiallyCollected =
								self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						if not isCollected or isPartiallyCollected then
							local itemData = {
								itemID = itemInfo.itemID,
								itemLink = itemInfo.hyperlink,
								isCollected = isCollected,
								hasOtherTransmogSources = hasOtherTransmogSources,
								isPartiallyCollected = isPartiallyCollected,
								frameType = "bag",
							}
							indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
						end
					end

					break
				end
			end
		end
	end

	return indicatorCount
end

-- Process combined bags (extracted from ScanBagFrames)
function DOKI:ProcessCombinedBag(bagID)
	if not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000SCAN DEBUG|r - Combined bag %d has %d slots", bagID, numSlots))
	for slotID = 1, numSlots do
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
			-- Find matching button in combined bags
			local button = nil
			if ContainerFrameCombinedBags.EnumerateValidItems then
				for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
					if itemButton and itemButton:IsVisible() then
						local buttonBagID, buttonSlotID = nil, nil
						if itemButton.GetBagID and itemButton.GetID then
							local success1, bag = pcall(itemButton.GetBagID, itemButton)
							local success2, slot = pcall(itemButton.GetID, itemButton)
							if success1 and success2 then
								buttonBagID, buttonSlotID = bag, slot
							end
						end

						if buttonBagID == bagID and buttonSlotID == slotID then
							button = itemButton
							break
						end
					end
				end
			end

			if button and self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
				local isCollected, hasOtherTransmogSources, isPartiallyCollected =
						self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
				if not isCollected or isPartiallyCollected then
					local itemData = {
						itemID = itemInfo.itemID,
						itemLink = itemInfo.hyperlink,
						isCollected = isCollected,
						hasOtherTransmogSources = hasOtherTransmogSources,
						isPartiallyCollected = isPartiallyCollected,
						frameType = "bag",
					}
					indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
				end
			end
		end
	end

	return indicatorCount
end

-- Process individual container (extracted from ScanBagFrames)
function DOKI:ProcessIndividualBag(bagID)
	local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
	if not (containerFrame and containerFrame:IsVisible()) then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000SCAN DEBUG|r - Individual bag %d has %d slots", bagID, numSlots))
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
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						local isCollected, hasOtherTransmogSources, isPartiallyCollected =
								self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						if not isCollected or isPartiallyCollected then
							local itemData = {
								itemID = itemInfo.itemID,
								itemLink = itemInfo.hyperlink,
								isCollected = isCollected,
								hasOtherTransmogSources = hasOtherTransmogSources,
								isPartiallyCollected = isPartiallyCollected,
								frameType = "bag",
							}
							indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
						end
					end

					break
				end
			end
		end
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
	-- Cancel full scan
	self:CancelProgressiveFullScan()
	if self.safetyTimer then
		self.safetyTimer:Cancel()
		self.safetyTimer = nil
		print("|cff00ffff UI DEBUG|r Cancelled safety timer")
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Collection system cleaned up (no delayed scans)")
	end
end

-- ===== INITIALIZATION =====
function DOKI:InitializeUniversalScanning()
	print("|cff00ffff UI DEBUG|r InitializeUniversalScanning called")
	-- Cancel any existing aggressive timer
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
		self.surgicalTimer = nil
		print("|cff00ffff UI DEBUG|r Cancelled aggressive surgical timer")
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Initialize ensemble detection
	self:InitializeEnsembleDetection()
	-- Initialize cache and debouncing systems
	self:SetupCacheInvalidationEvents()
	self:SetupDebouncedEventSystemWithUIDetection() -- Modified version
	-- Add a much slower safety timer (5s instead of 0.2s) as fallback only
	self.safetyTimer = C_Timer.NewTicker(5.0, function()
		if self.db and self.db.enabled then
			-- Only run if there might be missed changes (very rare)
			local anyUIVisible = self:IsAnyRelevantUIVisible()
			if anyUIVisible then
				-- Check if UI state changed since last check
				local currentUIState = self:GetCurrentUIVisibilityState()
				local stateChanged = self:CompareUIVisibilityStates(self.lastUIVisibilityState, currentUIState)
				if stateChanged then
					print("|cff00ffff UI DEBUG|r Safety timer detected UI state change - triggering scan")
					self:OnUIBecameVisible("safety_timer")
				end

				self.lastUIVisibilityState = currentUIState
			end
		end
	end)
	-- Do initial scan
	self:FullItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Event-driven surgical system initialized (no aggressive timer)")
		print("  |cff00ff00•|r Safety timer: 5s (fallback only)")
		print("  |cff00ff00•|r Primary updates: event-driven")
		print("  |cff00ff00•|r Initial scan on UI visibility changes")
	end
end

-- Get current UI visibility state
function DOKI:GetCurrentUIVisibilityState()
	return {
		elvui = ElvUI and self:IsElvUIBagVisible() or false,
		combined = ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() or false,
		individual = self:AreIndividualContainersVisible(),
		merchant = MerchantFrame and MerchantFrame:IsVisible() or false,
	}
end

-- Detect which bag system is actually visible (skip invisible ones)
function DOKI:GetActiveBagSystem()
	-- Priority order: ElvUI > Combined > Individual
	if ElvUI and self:IsElvUIBagVisible() then
		return "elvui"
	elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		return "combined"
	elseif self:AreIndividualContainersVisible() then
		return "individual"
	else
		return nil -- No bags visible
	end
end

-- Check if individual containers are visible (reuse from event system)
function DOKI:AreIndividualContainersVisible()
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			return true
		end
	end

	return false
end

-- Compare UI visibility states
function DOKI:CompareUIVisibilityStates(oldState, newState)
	for key, newValue in pairs(newState) do
		local oldValue = oldState[key]
		-- UI became visible (false -> true)
		if not oldValue and newValue then
			print(string.format("|cff00ffff UI DEBUG|r UI became visible: %s", key))
			return true
		end

		-- UI became hidden (true -> false) - also interesting for cleanup
		if oldValue and not newValue then
			print(string.format("|cff00ffff UI DEBUG|r UI became hidden: %s", key))
		end
	end

	return false
end

-- Called when UI becomes visible (initial scan needed)
function DOKI:OnUIBecameVisible(trigger)
	print(string.format("|cff00ffff UI DEBUG|r %.3f - OnUIBecameVisible triggered by: %s", GetTime(), trigger))
	if not self.db or not self.db.enabled then return end

	-- Use chunked full scan for initial population
	self:FullItemScan()
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

function DOKI:ProcessElvUIBagWithATTChunking(bagID)
	if not ElvUI or not self:IsElvUIBagVisible() then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000FULL SCAN DEBUG|r - ElvUI bag %d has %d slots", bagID, numSlots))
	-- Collect all items first
	local bagItems = {}
	for slotID = 1, numSlots do
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
			local possibleNames = {
				string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
				string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
				string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
			}
			for _, buttonName in ipairs(possibleNames) do
				local button = _G[buttonName]
				if button and button:IsVisible() then
					table.insert(bagItems, {
						itemID = itemInfo.itemID,
						itemLink = itemInfo.hyperlink,
						button = button,
					})
					break
				end
			end
		end
	end

	-- Process items in ATT mode with micro-chunking
	if self.db.attMode and #bagItems > 0 then
		indicatorCount = self:ProcessItemsWithATTMicroChunking(bagItems)
	else
		-- Standard mode: process all at once
		for _, item in ipairs(bagItems) do
			if self:IsCollectibleItem(item.itemID, item.itemLink) then
				local isCollected, hasOtherTransmogSources, isPartiallyCollected =
						self:IsItemCollected(item.itemID, item.itemLink)
				if not isCollected or isPartiallyCollected then
					local itemData = {
						itemID = item.itemID,
						itemLink = item.itemLink,
						isCollected = isCollected,
						hasOtherTransmogSources = hasOtherTransmogSources,
						isPartiallyCollected = isPartiallyCollected,
						frameType = "bag",
					}
					indicatorCount = indicatorCount + self:CreateUniversalIndicator(item.button, itemData)
				end
			end
		end
	end

	return indicatorCount
end

function DOKI:ProcessCombinedBagWithATTChunking(bagID)
	if not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000FULL SCAN DEBUG|r - Combined bag %d has %d slots", bagID, numSlots))
	-- Collect all items first
	local bagItems = {}
	for slotID = 1, numSlots do
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
			-- Find matching button in combined bags
			local button = nil
			if ContainerFrameCombinedBags.EnumerateValidItems then
				for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
					if itemButton and itemButton:IsVisible() then
						local buttonBagID, buttonSlotID = nil, nil
						if itemButton.GetBagID and itemButton.GetID then
							local success1, bag = pcall(itemButton.GetBagID, itemButton)
							local success2, slot = pcall(itemButton.GetID, itemButton)
							if success1 and success2 then
								buttonBagID, buttonSlotID = bag, slot
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
				table.insert(bagItems, {
					itemID = itemInfo.itemID,
					itemLink = itemInfo.hyperlink,
					button = button,
				})
			end
		end
	end

	-- Process items with ATT micro-chunking or standard
	if self.db.attMode and #bagItems > 0 then
		indicatorCount = self:ProcessItemsWithATTMicroChunking(bagItems)
	else
		-- Standard mode: process all at once
		for _, item in ipairs(bagItems) do
			if self:IsCollectibleItem(item.itemID, item.itemLink) then
				local isCollected, hasOtherTransmogSources, isPartiallyCollected =
						self:IsItemCollected(item.itemID, item.itemLink)
				if not isCollected or isPartiallyCollected then
					local itemData = {
						itemID = item.itemID,
						itemLink = item.itemLink,
						isCollected = isCollected,
						hasOtherTransmogSources = hasOtherTransmogSources,
						isPartiallyCollected = isPartiallyCollected,
						frameType = "bag",
					}
					indicatorCount = indicatorCount + self:CreateUniversalIndicator(item.button, itemData)
				end
			end
		end
	end

	return indicatorCount
end

function DOKI:ProcessIndividualBagWithATTChunking(bagID)
	local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
	if not (containerFrame and containerFrame:IsVisible()) then
		return 0
	end

	local indicatorCount = 0
	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if not numSlots or numSlots == 0 then
		return 0
	end

	print(string.format("|cffff0000FULL SCAN DEBUG|r - Individual bag %d has %d slots", bagID, numSlots))
	-- Collect all items first
	local bagItems = {}
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
					table.insert(bagItems, {
						itemID = itemInfo.itemID,
						itemLink = itemInfo.hyperlink,
						button = button,
					})
					break
				end
			end
		end
	end

	-- Process items with ATT micro-chunking or standard
	if self.db.attMode and #bagItems > 0 then
		indicatorCount = self:ProcessItemsWithATTMicroChunking(bagItems)
	else
		-- Standard mode: process all at once
		for _, item in ipairs(bagItems) do
			if self:IsCollectibleItem(item.itemID, item.itemLink) then
				local isCollected, hasOtherTransmogSources, isPartiallyCollected =
						self:IsItemCollected(item.itemID, item.itemLink)
				if not isCollected or isPartiallyCollected then
					local itemData = {
						itemID = item.itemID,
						itemLink = item.itemLink,
						isCollected = isCollected,
						hasOtherTransmogSources = hasOtherTransmogSources,
						isPartiallyCollected = isPartiallyCollected,
						frameType = "bag",
					}
					indicatorCount = indicatorCount + self:CreateUniversalIndicator(item.button, itemData)
				end
			end
		end
	end

	return indicatorCount
end

-- ==================================================================
-- 4. ADD ATT MICRO-CHUNKING FUNCTION (Collections.lua)
-- ==================================================================
-- QUICK FIX 2: Process items with 1-2 items per micro-chunk to reduce ATT FPS drops
function DOKI:ProcessItemsWithATTMicroChunking(bagItems)
	local indicatorCount = 0
	local itemsPerChunk = 2 -- Process 2 items per micro-chunk
	local totalItems = #bagItems
	print(string.format("|cffff0000FULL SCAN DEBUG|r - ATT micro-chunking: %d items, %d per chunk",
		totalItems, itemsPerChunk))
	-- Process items in small chunks
	local function processNextMicroChunk(startIndex)
		local endIndex = math.min(startIndex + itemsPerChunk - 1, totalItems)
		print(string.format("|cffff0000FULL SCAN DEBUG|r - Processing ATT micro-chunk: items %d-%d",
			startIndex, endIndex))
		-- Process this micro-chunk
		for i = startIndex, endIndex do
			local item = bagItems[i]
			if self:IsCollectibleItem(item.itemID, item.itemLink) then
				local isCollected, hasOtherTransmogSources, isPartiallyCollected =
						self:IsItemCollected(item.itemID, item.itemLink)
				if not isCollected or isPartiallyCollected then
					local itemData = {
						itemID = item.itemID,
						itemLink = item.itemLink,
						isCollected = isCollected,
						hasOtherTransmogSources = hasOtherTransmogSources,
						isPartiallyCollected = isPartiallyCollected,
						frameType = "bag",
					}
					indicatorCount = indicatorCount + self:CreateUniversalIndicator(item.button, itemData)
				end
			end
		end

		-- Schedule next micro-chunk if more items remain
		if endIndex < totalItems then
			local microDelay = 0.05 -- 50ms between micro-chunks in ATT mode
			print(string.format("|cffff0000FULL SCAN DEBUG|r - Scheduling next ATT micro-chunk in %.3fs", microDelay))
			C_Timer.After(microDelay, function()
				processNextMicroChunk(endIndex + 1)
			end)
		else
			print(string.format("|cffff0000FULL SCAN DEBUG|r - ATT micro-chunking complete: %d indicators",
				indicatorCount))
		end
	end

	-- Start processing if we have items
	if totalItems > 0 then
		processNextMicroChunk(1)
	end

	return indicatorCount
end

-- Minimal test scan (no chunking, no complexity)
function DOKI:MinimalTestScan()
	print("|cffff00ffTEST|r === MINIMAL TEST SCAN START ===")
	local startTime = GetTime()
	-- Clear existing indicators first (simple)
	if self.ClearAllButtonIndicators then
		self:ClearAllButtonIndicators()
	end

	local indicatorCount = 0
	local itemsProcessed = 0
	-- Only scan the active bag system (no triple scanning)
	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then
		print("|cffff00ffTEST|r No bags visible")
		return 0
	end

	print(string.format("|cffff00ffTEST|r Active system: %s", activeBagSystem))
	-- Scan only the active system
	if activeBagSystem == "elvui" then
		indicatorCount, itemsProcessed = self:MinimalScanElvUI()
	elseif activeBagSystem == "combined" then
		indicatorCount, itemsProcessed = self:MinimalScanCombined()
	elseif activeBagSystem == "individual" then
		indicatorCount, itemsProcessed = self:MinimalScanIndividual()
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r === MINIMAL TEST COMPLETE ==="))
	print(string.format("|cffff00ffTEST|r %d items processed, %d indicators created in %.3fs",
		itemsProcessed, indicatorCount, duration))
	return indicatorCount
end

-- Minimal ElvUI scan
function DOKI:MinimalScanElvUI()
	local indicatorCount = 0
	local itemsProcessed = 0
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					-- Find button (simple)
					local button = self:FindElvUIButton(bagID, slotID)
					if button then
						-- Test core functionality
						if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
							indicatorCount = indicatorCount + 1
						end
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

-- Minimal combined scan
function DOKI:MinimalScanCombined()
	local indicatorCount = 0
	local itemsProcessed = 0
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					-- Find button (simple)
					local button = self:FindCombinedButton(bagID, slotID)
					if button then
						-- Test core functionality
						if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
							indicatorCount = indicatorCount + 1
						end
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

-- Minimal individual scan
function DOKI:MinimalScanIndividual()
	local indicatorCount = 0
	local itemsProcessed = 0
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						itemsProcessed = itemsProcessed + 1
						-- Find button (simple)
						local button = self:FindIndividualButton(bagID, slotID)
						if button then
							-- Test core functionality
							if self:MinimalProcessItem(itemInfo.itemID, itemInfo.hyperlink, button) then
								indicatorCount = indicatorCount + 1
							end
						end
					end
				end
			end
		end
	end

	return indicatorCount, itemsProcessed
end

-- Core item processing (the actual test)
function DOKI:MinimalProcessItem(itemID, itemLink, button)
	-- Step 1: Check if collectible (same as current)
	if not self:IsCollectibleItem(itemID, itemLink) then
		return false
	end

	-- Step 2: Check collection status (this includes ATT parsing)
	local isCollected, hasOtherTransmogSources, isPartiallyCollected = self:IsItemCollected(itemID, itemLink)
	-- Step 3: Create indicator if needed (same as current)
	if not isCollected or isPartiallyCollected then
		local itemData = {
			itemID = itemID,
			itemLink = itemLink,
			isCollected = isCollected,
			hasOtherTransmogSources = hasOtherTransmogSources,
			isPartiallyCollected = isPartiallyCollected,
			frameType = "test",
		}
		-- Test indicator creation
		return self:CreateUniversalIndicator(button, itemData) > 0
	end

	return false
end

-- Simple button finders (no complex logic)
function DOKI:FindElvUIButton(bagID, slotID)
	local possibleNames = {
		string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
		string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
		string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
	}
	for _, buttonName in ipairs(possibleNames) do
		local button = _G[buttonName]
		if button and button:IsVisible() then
			return button
		end
	end

	return nil
end

function DOKI:FindCombinedButton(bagID, slotID)
	if not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		return nil
	end

	if ContainerFrameCombinedBags.EnumerateValidItems then
		for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
			if itemButton and itemButton:IsVisible() then
				local buttonBagID, buttonSlotID = nil, nil
				if itemButton.GetBagID and itemButton.GetID then
					local success1, bag = pcall(itemButton.GetBagID, itemButton)
					local success2, slot = pcall(itemButton.GetID, itemButton)
					if success1 and success2 then
						buttonBagID, buttonSlotID = bag, slot
					end
				end

				if buttonBagID == bagID and buttonSlotID == slotID then
					return itemButton
				end
			end
		end
	end

	return nil
end

function DOKI:FindIndividualButton(bagID, slotID)
	local possibleNames = {
		string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
		string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
	}
	for _, buttonName in ipairs(possibleNames) do
		local button = _G[buttonName]
		if button and button:IsVisible() then
			return button
		end
	end

	return nil
end

-- ==================================================================
-- STEP 2: ADD TEST VERSIONS WITH ISOLATED COMPONENTS
-- ==================================================================
-- Test 1: ATT parsing only (no indicators)
function DOKI:TestATTParsingOnly()
	print("|cffff00ffTEST|r === ATT PARSING ONLY TEST ===")
	local startTime = GetTime()
	local itemsProcessed = 0
	-- Scan items but don't create indicators
	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then return 0 end

	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					-- Only test ATT parsing
					if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
						local isCollected = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						-- Do nothing with the result - just parse
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r ATT parsing only: %d items in %.3fs", itemsProcessed, duration))
	return itemsProcessed
end

-- Test 2: Indicator creation only (no ATT)
function DOKI:TestIndicatorCreationOnly()
	print("|cffff00ffTEST|r === INDICATOR CREATION ONLY TEST ===")
	local startTime = GetTime()
	local indicatorsCreated = 0
	-- Clear existing first
	if self.ClearAllButtonIndicators then
		self:ClearAllButtonIndicators()
	end

	-- Find all buttons and create test indicators (no ATT parsing)
	local activeBagSystem = self:GetActiveBagSystem()
	if not activeBagSystem then return 0 end

	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					local button = nil
					if activeBagSystem == "elvui" then
						button = self:FindElvUIButton(bagID, slotID)
					elseif activeBagSystem == "combined" then
						button = self:FindCombinedButton(bagID, slotID)
					elseif activeBagSystem == "individual" then
						button = self:FindIndividualButton(bagID, slotID)
					end

					if button then
						-- Create test indicator (no collection checking)
						local testItemData = {
							itemID = itemInfo.itemID,
							itemLink = itemInfo.hyperlink,
							isCollected = false, -- Always create indicator
							hasOtherTransmogSources = false,
							isPartiallyCollected = false,
							frameType = "test",
						}
						if self:CreateUniversalIndicator(button, testItemData) > 0 then
							indicatorsCreated = indicatorsCreated + 1
						end
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	print(string.format("|cffff00ffTEST|r Indicator creation only: %d indicators in %.3fs", indicatorsCreated, duration))
	return indicatorsCreated
end
