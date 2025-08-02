-- DOKI Core - Complete War Within Fix with Enhanced Merchant Support + Ensemble Support
local addonName, DOKI = ...
-- Initialize addon namespace
DOKI.currentItems = {}
DOKI.overlayPool = {}
DOKI.activeOverlays = {}
DOKI.textureCache = {}
-- Enhanced scanning system variables
DOKI.delayedScanTimer = nil       -- Timer for delayed secondary scan
DOKI.delayedScanCancelled = false -- Flag to track if delayed scan should be cancelled
-- Main addon frame
local frame = CreateFrame("Frame", "DOKIFrame")
-- Initialize saved variables
local function InitializeSavedVariables()
	if not DOKI_DB then
		DOKI_DB = {
			enabled = true,
			debugMode = false,
			smartMode = true,
			attMode = true,
		}
	else
		if DOKI_DB.smartMode == nil then
			DOKI_DB.smartMode = false
		end

		if DOKI_DB.attMode == nil then
			DOKI_DB.attMode = false
		end
	end

	DOKI.db = DOKI_DB
end
function DOKI:Shutdown()
	-- Clean up lazy loading system
	if self.attLazyLoader then
		self:StopBackgroundATTProcessing()
		if self.attLazyLoader.discoveryTimer then
			self.attLazyLoader.discoveryTimer:Cancel()
			self.attLazyLoader.discoveryTimer = nil
		end

		self.attLazyLoader.discoveryEnabled = false
	end

	-- Clean up other systems
	if self.CleanupButtonTextureSystem then
		self:CleanupButtonTextureSystem()
	end

	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
		self.surgicalTimer = nil
	end
end

-- Event handlers
local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		local loadedAddon = ...
		if loadedAddon == addonName then
			InitializeSavedVariables()
			-- Initialize clean systems
			DOKI:InitializeButtonTextureSystem()
			DOKI:InitializeUniversalScanning()
			-- Auto-start ATT lazy loading if ATT mode is enabled
			if DOKI.db.attMode then
				C_Timer.After(2, function() -- Wait 2 seconds for UI to fully load
					if DOKI.db and DOKI.db.attMode then
						print("|cffff69b4DOKI|r Auto-starting ATT lazy loading...")
						DOKI:StartATTItemDiscovery()
					end
				end)
			end

			if ElvUI then
				print("|cffff69b4DOKI|r loaded with War Within surgical system + ElvUI support + ATT Lazy Loading")
			else
				print("|cffff69b4DOKI|r loaded with War Within surgical system + ATT Lazy Loading")
			end

			if DOKI.db.attMode then
				print("|cffff69b4DOKI|r ATT mode active - background processing will start shortly")
			end

			frame:UnregisterEvent("ADDON_LOADED")
		end
	end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)
-- Enhanced slash commands with merchant, battlepet, and ensemble support
SLASH_DOKI1 = "/doki"
SlashCmdList["DOKI"] = function(msg)
	local command = string.lower(strtrim(msg or ""))
	if command == "toggle" then
		DOKI.db.enabled = not DOKI.db.enabled
		local status = DOKI.db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r is now " .. status)
		if not DOKI.db.enabled then
			if DOKI.CleanupButtonTextureSystem then
				DOKI:CleanupButtonTextureSystem()
			end
		else
			if DOKI.InitializeUniversalScanning then
				DOKI:InitializeUniversalScanning()
			end
		end
	elseif command == "debug" then
		DOKI.db.debugMode = not DOKI.db.debugMode
		local status = DOKI.db.debugMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r debug mode is now " .. status)
	elseif command == "smart" then
		-- ENHANCED: Smart mode toggle with automatic cache invalidation and rescan
		DOKI.db.smartMode = not DOKI.db.smartMode
		local status = DOKI.db.smartMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r smart mode is now " .. status)
		print("|cffff69b4DOKI|r Smart mode considers class restrictions when determining if items are needed")
		-- ADDED: Automatic cache invalidation and rescan after smart mode toggle
		if DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Smart mode changed - invalidating collection cache and rescanning...")
		end

		-- Clear collection cache since smart mode changes how collection status is calculated
		if DOKI.ClearCollectionCache then
			DOKI:ClearCollectionCache()
		end

		-- Force full rescan if addon is enabled and UI is visible
		if DOKI.db.enabled then
			C_Timer.After(0.1, function()
				if DOKI.db and DOKI.db.enabled and DOKI.ForceUniversalScan then
					local count = DOKI:ForceUniversalScan()
					if DOKI.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Smart mode toggle rescan: %d indicators created", count))
					end
				end
			end)
		end

		-- Enhanced toggle function
	elseif command == "toggle" then
		DOKI.db.enabled = not DOKI.db.enabled
		local status = DOKI.db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r is now " .. status)
		if not DOKI.db.enabled then
			-- Shutdown everything including lazy loading
			DOKI:Shutdown()
		else
			-- Restart everything
			if DOKI.InitializeUniversalScanning then
				DOKI:InitializeUniversalScanning()
			end

			-- Restart ATT lazy loading if ATT mode is enabled
			if DOKI.db.attMode then
				C_Timer.After(0.5, function()
					if DOKI.db and DOKI.db.enabled and DOKI.db.attMode then
						DOKI:StartATTItemDiscovery()
					end
				end)
			end
		end
	elseif command == "scan" or command == "universal" then
		print("|cffff69b4DOKI|r force scanning...")
		if DOKI.ForceUniversalScan then
			local count = DOKI:ForceUniversalScan()
			print(string.format("|cffff69b4DOKI|r Full scan complete: %d indicators created", count))
		else
			print("|cffff69b4DOKI|r Scan function not available")
		end
	elseif command == "surgical" then
		print("|cffff69b4DOKI|r running surgical update...")
		if DOKI.SurgicalUpdate then
			local changes = DOKI:SurgicalUpdate(false)
			print(string.format("|cffff69b4DOKI|r Surgical update: %d changes", changes))
		else
			print("|cffff69b4DOKI|r Surgical update not available")
		end
	elseif command == "immediate" then
		print("|cffff69b4DOKI|r triggering immediate surgical update...")
		if DOKI.TriggerImmediateSurgicalUpdate then
			DOKI:TriggerImmediateSurgicalUpdate()
			print("|cffff69b4DOKI|r Immediate update triggered")
		else
			print("|cffff69b4DOKI|r Immediate update not available")
		end
	elseif command == "clear" then
		if DOKI.ClearAllOverlays then
			local cleared = DOKI:ClearAllOverlays()
			print(string.format("|cffff69b4DOKI|r Cleared %d indicators", cleared))
		end
	elseif command == "cleanup" then
		if DOKI.CleanupButtonTextures then
			local removedCount = DOKI:CleanupButtonTextures()
			print(string.format("|cffff69b4DOKI|r Cleaned up %d stale indicators", removedCount))
		else
			print("|cffff69b4DOKI|r Cleanup function not available")
		end
	elseif command == "status" then
		-- ENHANCED: Use enhanced status display with delayed scan information
		local indicatorCount = 0
		local battlepetCount = 0
		if DOKI.buttonTextures then
			for _, textureData in pairs(DOKI.buttonTextures) do
				if textureData.isActive then
					indicatorCount = indicatorCount + 1
					if textureData.itemLink and string.find(textureData.itemLink, "battlepet:") then
						battlepetCount = battlepetCount + 1
					end
				end
			end
		end

		local snapshotCount = 0
		if DOKI.lastButtonSnapshot then
			for _ in pairs(DOKI.lastButtonSnapshot) do
				snapshotCount = snapshotCount + 1
			end
		end

		print(string.format("|cffff69b4DOKI|r Status: %s, Smart: %s, ATT: %s, Debug: %s",
			DOKI.db.enabled and "Enabled" or "Disabled",
			DOKI.db.smartMode and "On" or "Off",
			DOKI.db.attMode and "On" or "Off", -- ADDED: ATT mode status
			DOKI.db.debugMode and "On" or "Off"))
		print(string.format("|cffff69b4DOKI|r Active indicators: %d (%d battlepets)", indicatorCount, battlepetCount))
		print(string.format("|cffff69b4DOKI|r Tracked buttons: %d", snapshotCount))
		-- ADDED: Ensemble status
		local ensembleWord = DOKI.ensembleWordCache
		print(string.format("|cffff69b4DOKI|r Ensemble detection: %s",
			ensembleWord and ("Ready (" .. ensembleWord .. ")") or "Not initialized"))
		-- ADDED: Show delayed scan status
		if DOKI.delayedScanTimer then
			print("  |cffffff00•|r Delayed cleanup scan: PENDING")
		else
			print("  |cff00ff00•|r Delayed cleanup scan: Ready")
		end

		print(string.format("  |cff00ff00•|r Throttling: %.0fms minimum between updates",
			(DOKI.surgicalUpdateThrottleTime or 0.05) * 1000))
		if DOKI.totalUpdates and DOKI.totalUpdates > 0 then
			print(string.format("  |cff00ff00•|r Total updates: %d (%d immediate)",
				DOKI.totalUpdates, DOKI.immediateUpdates or 0))
			if DOKI.throttledUpdates and DOKI.throttledUpdates > 0 then
				print(string.format("  |cffffff00•|r Throttled updates: %d", DOKI.throttledUpdates))
			end
		end

		-- Show merchant status
		local merchantOpen = MerchantFrame and MerchantFrame:IsVisible()
		local merchantScrolling = DOKI.merchantScrollDetector and DOKI.merchantScrollDetector.isScrolling
		print(string.format("  |cff00ff00•|r Merchant: %s%s",
			merchantOpen and "Open" or "Closed",
			merchantScrolling and " (scrolling)" or ""))
	elseif command == "attlazy" or command == "lazy" then
		-- ATT Lazy Loading status and control
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === ATT LAZY LOADING STATUS ===")
		local stats = DOKI:GetATTLazyLoadingStats()
		print(string.format("Discovery: %d items found", stats.discoveredItems))
		print(string.format("Background queue: %d items waiting", stats.queueSize))
		print(string.format("Processing: %s", stats.isProcessing and "ACTIVE" or "STOPPED"))
		print(string.format("Session progress: %d/%d items processed",
			stats.sessionItemsProcessed, stats.maxItemsPerSession))
		print("")
		print("Performance settings:")
		print(string.format("  Items per tick: %d", stats.itemsPerTick))
		print(string.format("  Tick interval: %.1fs", stats.tickInterval))
		print(string.format("  Max per session: %d", stats.maxItemsPerSession))
		print("")
		print("Statistics:")
		print(string.format("  Total discovered: %d", stats.stats.totalItemsDiscovered))
		print(string.format("  Total processed: %d", stats.stats.totalItemsProcessed))
		print(string.format("  Cache hits: %d", stats.stats.cacheHits))
		print(string.format("  Cache misses: %d", stats.stats.cacheMisses))
		print(string.format("  Background time: %.3fs", stats.stats.backgroundProcessingTime))
		local hitRate = 0
		if stats.stats.cacheHits + stats.stats.cacheMisses > 0 then
			hitRate = (stats.stats.cacheHits / (stats.stats.cacheHits + stats.stats.cacheMisses)) * 100
		end

		print(string.format("  Cache hit rate: %.1f%%", hitRate))
		print("")
		print("Commands:")
		print("  /doki attstart - Start background processing")
		print("  /doki attstop - Stop background processing")
		print("  /doki attclear - Clear all lazy loading data")
		print("  /doki attperf <items> <interval> <maxsession> - Set performance")
	elseif command == "attstart" then
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		DOKI:StartATTItemDiscovery()
		print("|cffff69b4DOKI|r ATT lazy loading started")
	elseif command == "attstop" then
		if DOKI.attLazyLoader then
			DOKI:StopBackgroundATTProcessing()
			if DOKI.attLazyLoader.discoveryTimer then
				DOKI.attLazyLoader.discoveryTimer:Cancel()
				DOKI.attLazyLoader.discoveryTimer = nil
			end

			DOKI.attLazyLoader.discoveryEnabled = false
		end

		print("|cffff69b4DOKI|r ATT lazy loading stopped")
	elseif command == "attclear" then
		DOKI:ClearATTLazyLoadingData()
	elseif string.find(command, "attperf ") then
		-- Custom performance settings: /doki attperf 3 1.5 75
		local params = {}
		for param in string.gmatch(command, "%S+") do
			table.insert(params, param)
		end

		local itemsPerTick = tonumber(params[2])
		local tickInterval = tonumber(params[3])
		local maxItemsPerSession = tonumber(params[4])
		if not itemsPerTick then
			print("|cffff69b4DOKI|r Usage: /doki attperf <itemsPerTick> <tickInterval> <maxItemsPerSession>")
			print("|cffff69b4DOKI|r Example: /doki attperf 3 1.5 75")
			print("|cffff69b4DOKI|r Current settings:")
			local stats = DOKI:GetATTLazyLoadingStats()
			print(string.format("  Items per tick: %d", stats.itemsPerTick))
			print(string.format("  Tick interval: %.1fs", stats.tickInterval))
			print(string.format("  Max per session: %d", stats.maxItemsPerSession))
			return
		end

		DOKI:SetATTLazyLoadingSettings(itemsPerTick, tickInterval, maxItemsPerSession)
		local stats = DOKI:GetATTLazyLoadingStats()
		print(string.format("|cffff69b4DOKI|r Updated ATT lazy loading settings:"))
		print(string.format("  Items per tick: %d", stats.itemsPerTick))
		print(string.format("  Tick interval: %.1fs", stats.tickInterval))
		print(string.format("  Max per session: %d", stats.maxItemsPerSession))
	elseif command == "attfast" then
		-- Preset: Fast processing for users with good CPUs
		DOKI:SetATTLazyLoadingSettings(5, 0.8, 100)
		print("|cffff69b4DOKI|r Set FAST ATT processing (5 items/tick, 0.8s interval, 100 max/session)")
	elseif command == "attslow" then
		-- Preset: Slow processing for users with weaker CPUs
		DOKI:SetATTLazyLoadingSettings(1, 2.0, 30)
		print("|cffff69b4DOKI|r Set SLOW ATT processing (1 item/tick, 2.0s interval, 30 max/session)")
	elseif command == "attbalanced" then
		-- Preset: Balanced processing (default recommended)
		DOKI:SetATTLazyLoadingSettings(2, 1.0, 50)
		print("|cffff69b4DOKI|r Set BALANCED ATT processing (2 items/tick, 1.0s interval, 50 max/session)")
	elseif command == "attdiscovery" then
		-- Trigger immediate discovery scan
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r Running immediate item discovery scan...")
		local beforeCount = DOKI:TableCount(DOKI.attLazyLoader.discoveredItems)
		DOKI:DiscoverBagItems()
		local afterCount = DOKI:TableCount(DOKI.attLazyLoader.discoveredItems)
		local discovered = afterCount - beforeCount
		print(string.format("|cffff69b4DOKI|r Discovery complete: %d new items found (%d total)",
			discovered, afterCount))
	elseif command == "attfixed2" then
		-- Test the NEW fixed ATT parsing with Unicode symbols
		DOKI:TestFixedATTParsing()
	elseif command == "attfixed" then
		-- Test the FIXED ATT parsing with proper timing and patterns
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING FIXED ATT PARSING ===")
		print("|cffff69b4DOKI|r Using improved patterns and 0.2s timing")
		-- Test with the same item that worked in debug (Ashes of Al'ar)
		local testItemID = 32458
		local itemName = C_Item.GetItemInfo(testItemID) or "Loading..."
		print(string.format("Testing with: %s (ID: %d)", itemName, testItemID))
		print("Setting up tooltip with 0.2s delay...")
		local tooltip = GameTooltip
		tooltip:Hide()
		tooltip:ClearLines()
		tooltip:SetOwner(UIParent, "ANCHOR_NONE")
		tooltip:SetItemByID(testItemID)
		tooltip:Show()
		-- Wait for ATT injection (using the observed 0.2s timing)
		C_Timer.After(0.2, function()
			print("Parsing ATT data after 0.2s delay...")
			local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipFromGameTooltip(testItemID)
			tooltip:Hide()
			tooltip:ClearLines()
			if isCollected ~= nil then
				local colorType = "NONE"
				if not isCollected and not showPurple then
					colorType = "ORANGE (not collected)"
				elseif showPurple then
					colorType = "PINK (partial)"
				elseif isCollected and showYellowD then
					colorType = "BLUE (other source)"
				elseif isCollected then
					colorType = "NONE (collected)"
				end

				print(string.format("  ✓ SUCCESS: %s - Indicator: %s",
					isCollected and "COLLECTED" or "NOT COLLECTED", colorType))
				print("|cffff69b4DOKI|r Fixed parsing is working! Now testing with your bag items...")
				-- Test with first item in bags
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID then
								local bagItemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
								print(string.format("\nTesting bag item: %s (ID: %d)", bagItemName, itemInfo.itemID))
								tooltip:Hide()
								tooltip:ClearLines()
								tooltip:SetOwner(UIParent, "ANCHOR_NONE")
								if itemInfo.hyperlink then
									tooltip:SetHyperlink(itemInfo.hyperlink)
								else
									tooltip:SetItemByID(itemInfo.itemID)
								end

								tooltip:Show()
								C_Timer.After(0.2, function()
									local bagCollected, bagYellow, bagPurple = DOKI:ParseATTTooltipFromGameTooltip(itemInfo.itemID)
									tooltip:Hide()
									if bagCollected ~= nil then
										local bagColorType = "NONE"
										if not bagCollected and not bagPurple then
											bagColorType = "ORANGE (not collected)"
										elseif bagPurple then
											bagColorType = "PINK (partial)"
										elseif bagCollected and bagYellow then
											bagColorType = "BLUE (other source)"
										elseif bagCollected then
											bagColorType = "NONE (collected)"
										end

										print(string.format("  ✓ ATT DATA: %s - %s",
											bagCollected and "COLLECTED" or "NOT COLLECTED", bagColorType))
									else
										print("  ✗ No ATT data for this item")
									end
								end)
								return
							end
						end
					end
				end
			else
				print("  ✗ FAILED: No ATT data found even with fixed parsing")
				print("  This suggests ATT may not be processing this item")
			end
		end)
	elseif command == "attdirect" then
		-- Test the FIXED direct ATT parsing using GameTooltip
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING FIXED ATT DIRECT PARSING ===")
		print("|cffff69b4DOKI|r Testing with GameTooltip (should work with new ATT restrictions)")
		-- Test with first few items in bags
		local tested = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and tested < 3 then
						tested = tested + 1
						local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
						print(string.format("Testing item %d: %s (ID: %d)", tested, itemName, itemInfo.itemID))
						local startTime = GetTime()
						local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipDirect(itemInfo.itemID, itemInfo.hyperlink)
						local endTime = GetTime()
						if isCollected ~= nil then
							local colorType = "NONE"
							if not isCollected and not showPurple then
								colorType = "ORANGE (not collected)"
							elseif showPurple then
								colorType = "PINK (partial)"
							elseif isCollected and showYellowD then
								colorType = "BLUE (other source)"
							elseif isCollected then
								colorType = "NONE (collected)"
							end

							print(string.format("  ✓ ATT DATA FOUND: %s - Indicator: %s (%.3fs)",
								isCollected and "COLLECTED" or "NOT COLLECTED", colorType, endTime - startTime))
						else
							print(string.format("  ✗ NO ATT DATA (%.3fs)", endTime - startTime))
						end
					end
				end
			end

			if tested >= 3 then break end
		end

		if tested == 0 then
			print("|cffff69b4DOKI|r No items found in bags to test")
		else
			print("|cffff69b4DOKI|r Direct parsing test complete")
			print("|cffff69b4DOKI|r If you see 'ATT DATA FOUND' messages, the integration is working!")
		end
	elseif command == "attdebug" then
		-- Comprehensive ATT detection debugging
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		-- Test with first item in bags
		local testItemID, testItemLink = nil, nil
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						testItemID = itemInfo.itemID
						testItemLink = itemInfo.hyperlink
						break
					end
				end
			end

			if testItemID then break end
		end

		if testItemID then
			DOKI:DebugATTDetection(testItemID, testItemLink)
		else
			print("|cffff69b4DOKI|r No items found in bags to test")
		end
	elseif command == "attknown" then
		-- Test with a known collectible item
		DOKI:TestATTWithKnownItem()
	elseif command == "atthooks" then
		-- Check ATT tooltip hook status
		DOKI:CheckATTTooltipHooks()
	elseif string.find(command, "attmanual ") then
		-- Manual tooltip test: /doki attmanual 32458
		local itemID = tonumber(string.match(command, "%d+"))
		if itemID then
			DOKI:ManualTooltipTest(itemID)
		else
			print("|cffff69b4DOKI|r Usage: /doki attmanual <itemID>")
			print("|cffff69b4DOKI|r Example: /doki attmanual 32458")
		end
	elseif command == "attqueue" then
		-- Show current processing queue
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		local queueSize = #(DOKI.attLazyLoader.processingQueue or {})
		print(string.format("|cffff69b4DOKI|r ATT Processing Queue: %d items", queueSize))
		if queueSize > 0 then
			print("Next 10 items to process:")
			for i = 1, math.min(10, queueSize) do
				local item = DOKI.attLazyLoader.processingQueue[i]
				local itemName = C_Item.GetItemInfo(item.itemID) or "Unknown"
				print(string.format("  %d. %s (ID: %d, priority: %d)",
					i, itemName, item.itemID, item.priority))
			end

			if queueSize > 10 then
				print(string.format("  ... and %d more items", queueSize - 10))
			end
		else
			print("Queue is empty - all discovered items have been processed!")
		end

		-- Test the FIXED direct ATT parsing using GameTooltip
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING FIXED ATT DIRECT PARSING ===")
		print("|cffff69b4DOKI|r Testing with GameTooltip (should work with new ATT restrictions)")
		-- Test with first few items in bags
		local tested = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and tested < 3 then
						tested = tested + 1
						local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
						print(string.format("Testing item %d: %s (ID: %d)", tested, itemName, itemInfo.itemID))
						local startTime = GetTime()
						local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipDirect(itemInfo.itemID, itemInfo.hyperlink)
						local endTime = GetTime()
						if isCollected ~= nil then
							local colorType = "NONE"
							if not isCollected and not showPurple then
								colorType = "ORANGE (not collected)"
							elseif showPurple then
								colorType = "PINK (partial)"
							elseif isCollected and showYellowD then
								colorType = "BLUE (other source)"
							elseif isCollected then
								colorType = "NONE (collected)"
							end

							print(string.format("  ✓ ATT DATA FOUND: %s - Indicator: %s (%.3fs)",
								isCollected and "COLLECTED" or "NOT COLLECTED", colorType, endTime - startTime))
						else
							print(string.format("  ✗ NO ATT DATA (%.3fs)", endTime - startTime))
						end
					end
				end
			end

			if tested >= 3 then break end
		end

		if tested == 0 then
			print("|cffff69b4DOKI|r No items found in bags to test")
		else
			print("|cffff69b4DOKI|r Direct parsing test complete")
			print("|cffff69b4DOKI|r If you see 'ATT DATA FOUND' messages, the integration is working!")
		end

		-- Show current processing queue
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		local queueSize = #(DOKI.attLazyLoader.processingQueue or {})
		print(string.format("|cffff69b4DOKI|r ATT Processing Queue: %d items", queueSize))
		if queueSize > 0 then
			print("Next 10 items to process:")
			for i = 1, math.min(10, queueSize) do
				local item = DOKI.attLazyLoader.processingQueue[i]
				local itemName = C_Item.GetItemInfo(item.itemID) or "Unknown"
				print(string.format("  %d. %s (ID: %d, priority: %d)",
					i, itemName, item.itemID, item.priority))
			end

			if queueSize > 10 then
				print(string.format("  ... and %d more items", queueSize - 10))
			end
		else
			print("Queue is empty - all discovered items have been processed!")
		end
	elseif command == "atttest" then
		-- Test the lazy loading system with current bag contents
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING ATT LAZY LOADING PERFORMANCE ===")
		-- Force discovery of current bag items
		DOKI:DiscoverBagItems()
		-- Count items and cache status
		local totalItems = 0
		local cachedItems = 0
		local needProcessing = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						local cached = DOKI:GetCachedATTStatus(itemInfo.itemID, itemInfo.hyperlink)
						if cached ~= nil then
							cachedItems = cachedItems + 1
						else
							needProcessing = needProcessing + 1
						end
					end
				end
			end
		end

		print(string.format("Bag analysis: %d total items", totalItems))
		print(string.format("  Cached: %d items (%.1f%%)", cachedItems, (cachedItems / totalItems) * 100))
		print(string.format("  Need processing: %d items (%.1f%%)", needProcessing, (needProcessing / totalItems) * 100))
		-- Simulate bag opening performance
		print("")
		print("Simulating bag opening performance...")
		local startTime = GetTime()
		local indicatorCount = DOKI:ScanBagFrames()
		local endTime = GetTime()
		local duration = endTime - startTime
		print(string.format("Bag scan results:"))
		print(string.format("  Duration: %.3f seconds", duration))
		print(string.format("  Indicators created: %d", indicatorCount))
		if duration < 0.1 then
			print("|cff00ff00EXCELLENT:|r Bag opening should be instant!")
		elseif duration < 0.3 then
			print("|cff00ff00GOOD:|r Bag opening should feel smooth")
		elseif duration < 0.5 then
			print("|cffffff00ACCEPTABLE:|r Bag opening should be reasonable")
		else
			print("|cffff0000SLOW:|r Still experiencing delays - more processing needed")
			print("|cffffff00TIP:|r Try '/doki attfast' or wait for background processing to complete")
		end

		local stats = DOKI:GetATTLazyLoadingStats()
		print(string.format("Background queue: %d items remaining", stats.queueSize))
	elseif command == "testbags" then
		print("|cffff69b4DOKI|r === TESTING BAG DETECTION ===")
		print("|cffff69b4DOKI|r Checking for visible bag frames...")
		-- Test ElvUI
		local elvuiVisible = false
		if ElvUI then
			elvuiVisible = DOKI:IsElvUIBagVisible()
			print(string.format("  ElvUI bags visible: %s", tostring(elvuiVisible)))
		else
			print("  ElvUI: Not loaded")
		end

		-- Test Blizzard methods
		print("  Blizzard UI detection:")
		local combinedVisible = ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()
		print(string.format("    Combined bags: %s", tostring(combinedVisible)))
		local containerCount = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
			if containerFrame and containerFrame:IsVisible() then
				containerCount = containerCount + 1
				print(string.format("    ContainerFrame%d: visible", bagID + 1))
			end
		end

		print(string.format("    Individual containers visible: %d", containerCount))
		local anyUIVisible = elvuiVisible or combinedVisible or containerCount > 0
		print(string.format("  Would trigger surgical update: %s", tostring(anyUIVisible)))
		if anyUIVisible then
			print("|cffff69b4DOKI|r Running test scan...")
			print("  Items detected in bags via Container API:")
			local totalItems = 0
			local collectibleItems = 0
			local battlepetItems = 0
			for bagID = 0, NUM_BAG_SLOTS do
				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID then
							totalItems = totalItems + 1
							if DOKI:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
								collectibleItems = collectibleItems + 1
								local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
								local isCollected = DOKI:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
								local extraInfo = ""
								-- Check if it's a battlepet
								if itemInfo.hyperlink and string.find(itemInfo.hyperlink, "battlepet:") then
									battlepetItems = battlepetItems + 1
									local speciesID = DOKI:GetPetSpeciesFromBattlePetLink(itemInfo.hyperlink)
									extraInfo = string.format(" [Battlepet Species: %d]", speciesID or 0)
								end

								print(string.format("    Bag %d Slot %d: %s (ID: %d) - %s%s",
									bagID, slotID, itemName, itemInfo.itemID,
									isCollected and "COLLECTED" or "NEEDS INDICATOR", extraInfo))
							end
						end
					end
				end
			end

			print(string.format("  Total items: %d, Collectible items: %d (%d battlepets)",
				totalItems, collectibleItems, battlepetItems))
			local count = DOKI:ScanBagFrames()
			print(string.format("  Scan result: %d indicators would be created", count))
		else
			print("|cffff69b4DOKI|r No bags visible - open your bags and try again")
		end

		-- NEW: Merchant testing commands
	elseif command == "testmerchant" or command == "merchant" then
		print("|cffff69b4DOKI|r === TESTING MERCHANT DETECTION ===")
		local merchantOpen = MerchantFrame and MerchantFrame:IsVisible()
		print(string.format("  Merchant frame visible: %s", tostring(merchantOpen)))
		if not merchantOpen then
			print("|cffff69b4DOKI|r Please open a merchant and try again")
			return
		end

		-- Test scroll detection setup
		print("  Merchant scroll detection status:")
		if MerchantFrame.ScrollBox then
			print("     ScrollBox exists")
			local hasMouseWheel = MerchantFrame.ScrollBox:IsMouseWheelEnabled()
			print(string.format("    Mouse wheel enabled: %s", tostring(hasMouseWheel)))
			if MerchantFrame.ScrollBox.RegisterCallback then
				print("     RegisterCallback available")
			else
				print("     RegisterCallback not available")
			end
		else
			print("     ScrollBox not found")
		end

		-- Test merchant items
		local numItems = GetMerchantNumItems()
		print(string.format("  Merchant has %d items", numItems))
		local collectibleCount = 0
		for i = 1, numItems do
			local itemLink = GetMerchantItemLink(i)
			if itemLink then
				local itemID = DOKI:GetItemID(itemLink)
				if itemID and DOKI:IsCollectibleItem(itemID, itemLink) then
					collectibleCount = collectibleCount + 1
					local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
					local isCollected = DOKI:IsItemCollected(itemID, itemLink)
					print(string.format("    Item %d: %s (ID: %d) - %s",
						i, itemName, itemID, isCollected and "COLLECTED" or "NEEDS INDICATOR"))
				end
			end
		end

		print(string.format("  Collectible items found: %d", collectibleCount))
		-- Test merchant scanning
		local indicatorCount = DOKI:ScanMerchantFrames()
		print(string.format("  Scan result: %d indicators created", indicatorCount))
		-- Test scroll state
		local scrollDetector = DOKI.merchantScrollDetector
		if scrollDetector then
			print(string.format("  Scroll detector state: open=%s, scrolling=%s",
				tostring(scrollDetector.merchantOpen), tostring(scrollDetector.isScrolling)))
		end
	elseif command == "testscroll" then
		print("|cffff69b4DOKI|r === TESTING MERCHANT SCROLL SIMULATION ===")
		if not (MerchantFrame and MerchantFrame:IsVisible()) then
			print("|cffff69b4DOKI|r Please open a merchant first")
			return
		end

		print("|cffff69b4DOKI|r Simulating scroll down...")
		DOKI:OnMerchantMouseWheel(-1)
		C_Timer.After(1, function()
			print("|cffff69b4DOKI|r Simulating scroll up...")
			DOKI:OnMerchantMouseWheel(1)
		end)
	elseif command == "merchantstate" then
		print("|cffff69b4DOKI|r === MERCHANT STATE DEBUG ===")
		if not (MerchantFrame and MerchantFrame:IsVisible()) then
			print("|cffff69b4DOKI|r Merchant is closed")
			return
		end

		local currentState = DOKI:GetCurrentMerchantState()
		local itemCount = 0
		for _ in pairs(currentState) do itemCount = itemCount + 1 end

		print(string.format("  Current merchant state: %d items", itemCount))
		for i, item in pairs(currentState) do
			-- FIXED: Handle table structure properly
			local itemName = "Unknown"
			if type(item) == "table" and item.name then
				itemName = tostring(item.name)
			elseif type(item) == "string" then
				itemName = item
			end

			print(string.format("    Slot %d: %s", i, itemName))
		end

		local lastState = DOKI.merchantScrollDetector and DOKI.merchantScrollDetector.lastMerchantState
		if lastState then
			local lastItemCount = 0
			for _ in pairs(lastState) do lastItemCount = lastItemCount + 1 end

			print(string.format("  Last merchant state: %d items", lastItemCount))
			local statesEqual = DOKI:CompareMerchantState(currentState, lastState)
			print(string.format("  States are equal: %s", tostring(statesEqual)))
		else
			print("  No previous merchant state recorded")
		end
	elseif command == "merchantbuttons" or command == "checkbuttons" then
		print("|cffff69b4DOKI|r === MERCHANT BUTTON DEBUG ===")
		if not (MerchantFrame and MerchantFrame:IsVisible()) then
			print("|cffff69b4DOKI|r Merchant is closed")
			return
		end

		print("|cffff69b4DOKI|r Checking what items are currently visible in merchant buttons:")
		for i = 1, 12 do
			local button = _G[string.format("MerchantItem%dItemButton", i)] or _G[string.format("MerchantItem%d", i)]
			if button and button:IsVisible() then
				local itemID, itemLink = DOKI:GetItemFromMerchantButton(button, i)
				if itemID == "EMPTY_SLOT" then
					print(string.format("  Slot %d: EMPTY (button visible but no item)", i))
				elseif itemID then
					local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
					local isCollectible = DOKI:IsCollectibleItem(itemID, itemLink)
					local isCollected = isCollectible and DOKI:IsItemCollected(itemID, itemLink) or false
					print(string.format("  Slot %d: %s (ID: %d) - %s, %s",
						i, itemName, itemID,
						isCollectible and "Collectible" or "Not Collectible",
						isCollected and "Collected" or "Needs Indicator"))
				else
					print(string.format("  Slot %d: No item detected", i))
				end
			else
				print(string.format("  Slot %d: Button not visible", i))
			end
		end
	elseif command == "ensemble" or command == "ens" then
		print("|cffff69b4DOKI|r === ENSEMBLE SYSTEM STATUS ===")
		local ensembleWord = DOKI.ensembleWordCache
		print(string.format("  Ensemble word: %s", ensembleWord or "not cached"))
		if not ensembleWord then
			print("  Status:  Ensemble detection unavailable")
			print("  Try: /doki initensemble")
		else
			print("  Status:  Ensemble detection ready")
		end

		-- Test with a known ensemble if available
		local testItemID = 234522
		local testName = C_Item.GetItemInfo(testItemID)
		if testName then
			print(string.format("  Test item: %s", testName))
			local isEnsemble = DOKI:IsEnsembleItem(testItemID, testName)
			print(string.format("  Detected as ensemble: %s", tostring(isEnsemble)))
			if isEnsemble then
				local isCollected = DOKI:IsEnsembleCollected(testItemID, nil)
				print(string.format("  Collection status: %s", isCollected and "COLLECTED" or "NOT COLLECTED"))
			end
		end

		-- Show cache status
		local cacheCount = 0
		if DOKI.collectionCache then
			for _ in pairs(DOKI.collectionCache) do
				cacheCount = cacheCount + 1
			end
		end

		print(string.format("  Collection cache entries: %d", cacheCount))
		if DOKI.DebugFoundFrames then
			DOKI:DebugFoundFrames()
		else
			print("|cffff69b4DOKI|r Frame debug function not available")
		end
	elseif command == "att" then
		-- Enhanced ATT mode toggle with automatic lazy loading
		DOKI.db.attMode = not DOKI.db.attMode
		local status = DOKI.db.attMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r ATT mode is now " .. status)
		if DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode uses AllTheThings addon data with lazy loading")
			print("|cffff69b4DOKI|r Starting background item discovery and processing...")
			-- Start the lazy loading system
			DOKI:StartATTItemDiscovery()
			-- Show initial status
			C_Timer.After(1, function()
				if DOKI.db and DOKI.db.attMode then
					local stats = DOKI:GetATTLazyLoadingStats()
					print(string.format("|cffff69b4DOKI|r ATT Lazy Loading active: %d items discovered, processing in background",
						stats.discoveredItems))
					print("|cffff69b4DOKI|r Use '/doki atttest' to check performance or '/doki attlazy' for detailed status")
				end
			end)
		else
			print("|cffff69b4DOKI|r ATT mode disabled, stopping background processing...")
			-- Stop the lazy loading system
			if DOKI.attLazyLoader then
				DOKI:StopBackgroundATTProcessing()
				if DOKI.attLazyLoader.discoveryTimer then
					DOKI.attLazyLoader.discoveryTimer:Cancel()
					DOKI.attLazyLoader.discoveryTimer = nil
				end

				DOKI.attLazyLoader.discoveryEnabled = false
			end
		end

		-- Clear collection cache since ATT mode changes how collection status is calculated
		if DOKI.ClearCollectionCache then
			DOKI:ClearCollectionCache()
		end

		-- Force full rescan if addon is enabled and UI is visible
		if DOKI.db.enabled then
			C_Timer.After(0.1, function()
				if DOKI.db and DOKI.db.enabled and DOKI.ForceUniversalScan then
					local count = DOKI:ForceUniversalScan()
					if DOKI.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT mode toggle rescan: %d indicators created", count))
					end
				end
			end)
		end
	elseif command == "attbatch" then
		print("|cffff69b4DOKI|r === ATT BATCH PROCESSING STATUS ===")
		print(string.format("ATT Mode: %s", DOKI.db.attMode and "ENABLED" or "DISABLED"))
		print(string.format("Queue size: %d items", #(DOKI.attBatchQueue or {})))
		print(string.format("Currently processing: %s", DOKI.attBatchProcessing and "YES" or "NO"))
		local cacheCount = 0
		local attCacheCount = 0
		if DOKI.collectionCache then
			for key, cached in pairs(DOKI.collectionCache) do
				cacheCount = cacheCount + 1
				if cached.isATTResult then
					attCacheCount = attCacheCount + 1
				end
			end
		end

		print(string.format("Cache entries: %d total (%d ATT results)", cacheCount, attCacheCount))
		if #(DOKI.attBatchQueue or {}) > 0 then
			print("Next 5 items in queue:")
			for i = 1, math.min(5, #DOKI.attBatchQueue) do
				local item = DOKI.attBatchQueue[i]
				local itemName = C_Item.GetItemInfo(item.itemID) or "Unknown"
				print(string.format("  %d. %s (ID: %d)", i, itemName, item.itemID))
			end
		end
	elseif command == "attclear" then
		DOKI:ClearATTBatchQueue()
		-- Also clear ATT cache
		local cleared = 0
		if DOKI.collectionCache then
			for key, cached in pairs(DOKI.collectionCache) do
				if cached.isATTResult then
					DOKI.collectionCache[key] = nil
					cleared = cleared + 1
				end
			end
		end

		print(string.format("|cffff69b4DOKI|r Cleared ATT batch queue and %d cached ATT results", cleared))
	elseif command == "debugatt" then
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === ATT DEBUG - TRACING INDICATOR CREATION ===")
		-- Enable debug mode temporarily
		local oldDebug = DOKI.db.debugMode
		DOKI.db.debugMode = true
		-- Force a scan to see what happens
		print("|cffff69b4DOKI|r Running full scan with debug enabled...")
		local count = DOKI:FullItemScan()
		-- Restore debug mode
		DOKI.db.debugMode = oldDebug
		print(string.format("|cffff69b4DOKI|r Full scan complete: %d indicators created", count))
		print("|cffff69b4DOKI|r Check the output above to see which items got indicators and why")
	elseif string.find(command, "attrace ") then
		-- Extract item ID from command like "attrace 12345"
		local itemID = tonumber(string.match(command, "%d+"))
		if not itemID then
			print("|cffff69b4DOKI|r Usage: /doki attrace <itemID>")
			print("|cffff69b4DOKI|r Example: /doki attrace 226107")
			return
		end

		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print(string.format("|cffff69b4DOKI|r === ATT TRACE FOR ITEM %d ===", itemID))
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		print(string.format("Item: %s (ID: %d)", itemName, itemID))
		-- Step 1: Check if considered collectible
		local isCollectible = DOKI:IsCollectibleItem(itemID, nil)
		print(string.format("IsCollectibleItem (ATT mode): %s", isCollectible and "TRUE" or "FALSE"))
		-- Step 2: Check ATT status directly
		local attCollected, attYellowD, attPurple = DOKI:ParseATTTooltipDirect(itemID, nil)
		print("Direct ATT parsing:")
		if attCollected ~= nil then
			print(string.format("  Result: %s", attCollected and "COLLECTED" or "NOT COLLECTED"))
			print(string.format("  Show Yellow D: %s", attYellowD and "YES" or "NO"))
			print(string.format("  Show Purple: %s", attPurple and "YES" or "NO"))
		else
			print("  Result: NO ATT DATA")
		end

		-- Step 3: Check what IsItemCollected returns
		local isCollected, showYellowD, showPurple = DOKI:IsItemCollected(itemID, nil)
		print("IsItemCollected result:")
		print(string.format("  Collected: %s", isCollected and "TRUE" or "FALSE"))
		print(string.format("  Show Yellow D: %s", showYellowD and "YES" or "NO"))
		print(string.format("  Show Purple: %s", showPurple and "YES" or "NO"))
		-- Step 4: Determine if indicator should be created
		local shouldGetIndicator = isCollectible and (not isCollected or showPurple)
		print(string.format("Should get indicator: %s", shouldGetIndicator and "YES" or "NO"))
		if shouldGetIndicator then
			local colorType = "NONE"
			if not isCollected and not showPurple then
				colorType = "ORANGE"
			elseif showPurple then
				colorType = "PINK"
			elseif isCollected and showYellowD then
				colorType = "BLUE"
			end

			print(string.format("Indicator color: %s", colorType))
		end

		print("|cffff69b4DOKI|r === END TRACE ===")
	elseif command == "testatt" then
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING ENHANCED ATT MODE ===")
		print("|cffff69b4DOKI|r Scanning first 10 items in bags for ATT data...")
		print("|cffff69b4DOKI|r (Only items with ATT data will get indicators)")
		local tested = 0
		local attDataFound = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and tested < 10 then
						tested = tested + 1
						local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
						-- Test direct parsing
						local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipDirect(itemInfo.itemID, itemInfo.hyperlink)
						if isCollected ~= nil then
							attDataFound = attDataFound + 1
							local colorType = "NONE"
							if not isCollected and not showPurple then
								colorType = "ORANGE (0/number or not collected)"
							elseif showPurple then
								colorType = "PINK (>0/number partial)"
							elseif isCollected and showYellowD then
								colorType = "BLUE (other source)"
							elseif isCollected then
								colorType = "NONE (fully collected)"
							end

							print(string.format("  ✓ %s (ID: %d) - %s - Indicator: %s",
								itemName, itemInfo.itemID,
								isCollected and "COLLECTED" or "NOT COLLECTED",
								colorType))
						else
							print(string.format("  - %s (ID: %d) - No ATT data (will be ignored)",
								itemName, itemInfo.itemID))
						end
					end
				end
			end

			if tested >= 10 then break end
		end

		if tested == 0 then
			print("|cffff69b4DOKI|r No items found in bags")
		else
			print(string.format("|cffff69b4DOKI|r Summary: %d/%d items have ATT data", attDataFound, tested))
			print("|cffff69b4DOKI|r Items without ATT data will not get indicators in ATT mode")
		end
	elseif command == "testattall" then
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === TESTING ALL ITEMS FOR ATT DATA ===")
		local totalItems = 0
		local attDataFound = 0
		local needsOrangeIndicator = 0
		local needsPinkIndicator = 0
		local needsBlueIndicator = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						-- Test direct parsing
						local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipDirect(itemInfo.itemID, itemInfo.hyperlink)
						if isCollected ~= nil then
							attDataFound = attDataFound + 1
							if not isCollected and not showPurple then
								needsOrangeIndicator = needsOrangeIndicator + 1
							elseif showPurple then
								needsPinkIndicator = needsPinkIndicator + 1
							elseif isCollected and showYellowD then
								needsBlueIndicator = needsBlueIndicator + 1
							end
						end
					end
				end
			end
		end

		print(string.format("Total items in bags: %d", totalItems))
		print(string.format("Items with ATT data: %d (%.1f%%)", attDataFound, (attDataFound / totalItems) * 100))
		print(string.format("Would get ORANGE indicators: %d", needsOrangeIndicator))
		print(string.format("Would get PINK indicators: %d", needsPinkIndicator))
		print(string.format("Would get BLUE indicators: %d", needsBlueIndicator))
		print(string.format("Total indicators: %d", needsOrangeIndicator + needsPinkIndicator + needsBlueIndicator))
	elseif command == "attperf" then
		-- Set performance-tuned ATT settings based on test results
		local batchSize = 20  -- From optimization results
		local batchDelay = 0.03 -- Faster delay for automatic scans
		DOKI:SetATTPerformanceSettings(batchSize, batchDelay)
		print(string.format("|cffff69b4DOKI|r Set performance-tuned ATT settings: %d items/batch, %.0fms delay",
			batchSize, batchDelay * 1000))
		print("|cffff69b4DOKI|r These settings are now active for automatic bag scanning")
	elseif string.find(command, "attperf ") then
		-- Custom performance settings: /doki attperf 15 0.02
		local params = {}
		for param in string.gmatch(command, "%S+") do
			table.insert(params, param)
		end

		local batchSize = tonumber(params[2])
		local delay = tonumber(params[3])
		if not batchSize then
			print("|cffff69b4DOKI|r Usage: /doki attperf <batchSize> [delay]")
			print("|cffff69b4DOKI|r Example: /doki attperf 15 0.02")
			print("|cffff69b4DOKI|r Current settings:")
			local currentBatch, currentDelay = DOKI:GetATTPerformanceSettings()
			print(string.format("  Batch size: %d items", currentBatch))
			print(string.format("  Delay: %.0fms", currentDelay * 1000))
			return
		end

		DOKI:SetATTPerformanceSettings(batchSize, delay)
		local actualBatch, actualDelay = DOKI:GetATTPerformanceSettings()
		print(string.format("|cffff69b4DOKI|r Updated ATT performance settings: %d items/batch, %.0fms delay",
			actualBatch, actualDelay * 1000))
	elseif command == "testbags" then
		print("|cffff69b4DOKI|r === TESTING ENHANCED BAG DETECTION ===")
		print("|cffff69b4DOKI|r Checking for visible bag frames...")
		-- Test ElvUI
		local elvuiVisible = false
		if ElvUI then
			elvuiVisible = DOKI:IsElvUIBagVisible()
			print(string.format("  ElvUI bags visible: %s", tostring(elvuiVisible)))
		else
			print("  ElvUI: Not loaded")
		end

		-- Test Blizzard methods
		print("  Blizzard UI detection:")
		local combinedVisible = ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()
		print(string.format("    Combined bags: %s", tostring(combinedVisible)))
		local containerCount = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
			if containerFrame and containerFrame:IsVisible() then
				containerCount = containerCount + 1
				print(string.format("    ContainerFrame%d: visible", bagID + 1))
			end
		end

		print(string.format("    Individual containers visible: %d", containerCount))
		local anyUIVisible = elvuiVisible or combinedVisible or containerCount > 0
		print(string.format("  Would trigger surgical update: %s", tostring(anyUIVisible)))
		if anyUIVisible then
			print("|cffff69b4DOKI|r Running enhanced scan to see what happens...")
			print("  Items detected in bags via Container API:")
			local totalItems = 0
			local collectibleItems = 0
			local battlepetItems = 0
			for bagID = 0, NUM_BAG_SLOTS do
				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID then
							totalItems = totalItems + 1
							if DOKI:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
								collectibleItems = collectibleItems + 1
								local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
								local isCollected = DOKI:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
								local extraInfo = ""
								-- Check if it's a battlepet
								if itemInfo.hyperlink and string.find(itemInfo.hyperlink, "battlepet:") then
									battlepetItems = battlepetItems + 1
									local speciesID = DOKI:GetPetSpeciesFromBattlePetLink(itemInfo.hyperlink)
									extraInfo = string.format(" [Battlepet Species: %d]", speciesID or 0)
								end

								print(string.format("    Bag %d Slot %d: %s (ID: %d) - %s%s",
									bagID, slotID, itemName, itemInfo.itemID,
									isCollected and "COLLECTED" or "NEEDS INDICATOR", extraInfo))
							end
						end
					end
				end
			end

			print(string.format("  Total items: %d, Collectible items: %d (%d battlepets)",
				totalItems, collectibleItems, battlepetItems))
			-- Test the enhanced scanning
			local startTime = GetTime()
			local count = DOKI:ScanBagFrames()
			local endTime = GetTime()
			local duration = endTime - startTime
			print(string.format("  Enhanced scan result: %d indicators created in %.3fs", count, duration))
			if DOKI.db.attMode then
				local batchSize, delay = DOKI:GetATTPerformanceSettings()
				print(string.format("  ATT performance settings: %d items/batch, %.0fms delay", batchSize, delay * 1000))
			end
		else
			print("|cffff69b4DOKI|r No bags visible - open your bags and try again")
		end
	elseif command == "scanperf" then
		-- Show current scanning performance and settings
		print("|cffff69b4DOKI|r === SCANNING PERFORMANCE STATUS ===")
		print(string.format("ATT Mode: %s", DOKI.db.attMode and "ENABLED" or "DISABLED"))
		if DOKI.db.attMode then
			local currentBatch, currentDelay = DOKI:GetATTPerformanceSettings()
			print(string.format("Performance settings: %d items/batch, %.0fms delay",
				currentBatch, currentDelay * 1000))
			-- Show cache status
			local cacheCount = 0
			local attCacheCount = 0
			local noDataCount = 0
			if DOKI.collectionCache then
				for key, cached in pairs(DOKI.collectionCache) do
					cacheCount = cacheCount + 1
					if cached.isATTResult then
						attCacheCount = attCacheCount + 1
						if cached.noATTData then
							noDataCount = noDataCount + 1
						end
					end
				end
			end

			print(string.format("Cache status: %d total entries (%d ATT results, %d 'no data' results)",
				cacheCount, attCacheCount, noDataCount))
			-- Show queue status
			local queueSize = #(DOKI.attBatchQueue or {})
			local processing = DOKI.attBatchProcessing and "YES" or "NO"
			print(string.format("Batch queue: %d items, processing: %s", queueSize, processing))
			-- Performance recommendation
			if currentBatch < 10 then
				print("|cffffff00SUGGESTION:|r Consider increasing batch size to 15-20 for better performance")
			elseif currentBatch > 25 then
				print("|cffffff00SUGGESTION:|r Consider decreasing batch size to 15-20 to reduce lag")
			else
				print("|cff00ff00OPTIMAL:|r Batch size is in the recommended range")
			end

			if currentDelay > 0.05 then
				print("|cffffff00SUGGESTION:|r Consider decreasing delay to 0.03s for faster scanning")
			elseif currentDelay < 0.02 then
				print("|cffffff00SUGGESTION:|r Consider increasing delay to 0.03s to reduce lag")
			else
				print("|cff00ff00OPTIMAL:|r Delay is in the recommended range")
			end
		else
			print("ATT mode disabled - using standard collectible detection")
		end
	elseif command == "bagtest" then
		-- Quick bag opening performance test
		if not DOKI.db.attMode then
			print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
			return
		end

		print("|cffff69b4DOKI|r === BAG OPENING PERFORMANCE TEST ===")
		print("|cffff69b4DOKI|r This simulates what happens when you open your bags...")
		-- Clear some cache to simulate first-time opening
		local clearedItems = 0
		if DOKI.collectionCache then
			for key, cached in pairs(DOKI.collectionCache) do
				if cached.isATTResult and math.random() < 0.3 then -- Clear 30% randomly
					DOKI.collectionCache[key] = nil
					clearedItems = clearedItems + 1
				end
			end
		end

		print(string.format("Cleared %d cache entries to simulate fresh bag opening", clearedItems))
		-- Test the bag scanning performance
		local startTime = GetTime()
		local indicatorCount = DOKI:ScanBagFrames()
		local endTime = GetTime()
		local duration = endTime - startTime
		local batchSize, delay = DOKI:GetATTPerformanceSettings()
		print("|cffff69b4DOKI|r === BAG PERFORMANCE RESULTS ===")
		print(string.format("Scan duration: %.3f seconds", duration))
		print(string.format("Indicators created: %d", indicatorCount))
		print(string.format("Performance settings: %d items/batch, %.0fms delay", batchSize, delay * 1000))
		if duration < 0.5 then
			print("|cff00ff00EXCELLENT:|r Bag opening should feel smooth")
		elseif duration < 1.0 then
			print("|cffffff00GOOD:|r Bag opening should be acceptable")
		else
			print("|cffff0000SLOW:|r Bag opening may feel laggy - consider adjusting settings")
			print("|cffffff00TIP:|r Try '/doki attperf 25 0.02' for faster processing")
		end
	elseif command == "testfix" then
		print("|cffff69b4DOKI|r === TESTING FIXED ATT SYSTEM ===")
		DOKI:ClearATTBatchQueue()
		local testCount = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, math.min(5, numSlots) do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and testCount < 5 then
						testCount = testCount + 1
						local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
						print(string.format("Testing item %d: %s", testCount, itemName))
						local startTime = GetTime()
						local isCollected, showYellowD, showPurple = DOKI:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						local endTime = GetTime()
						print(string.format("  Result: %s (%.3fs)",
							isCollected and "COLLECTED" or "NOT COLLECTED",
							endTime - startTime))
					end
				end
			end

			if testCount >= 5 then break end
		end
	elseif command == "pace" then
		-- Toggle paced processing
		DOKI.attPerformanceSettings.useAsyncProcessing = not DOKI.attPerformanceSettings.useAsyncProcessing
		local status = DOKI.attPerformanceSettings.useAsyncProcessing and "ENABLED" or "DISABLED"
		print(string.format("|cffff69b4DOKI|r Paced processing: %s", status))
		if DOKI.attPerformanceSettings.useAsyncProcessing then
			print("ATT items will be processed in small batches to prevent FPS drops")
		else
			print("ATT items will be processed immediately (may cause FPS drops)")
		end
	elseif string.find(command, "pace ") then
		-- Custom pace settings: /doki pace 3 0.02
		local params = {}
		for param in string.gmatch(command, "%S+") do
			table.insert(params, param)
		end

		local batchSize = tonumber(params[2])
		local delay = tonumber(params[3])
		if batchSize then
			DOKI.attPerformanceSettings.batchSize = math.max(1, math.min(20, batchSize))
		end

		if delay then
			DOKI.attPerformanceSettings.batchDelay = math.max(0.01, math.min(0.2, delay))
		end

		print(string.format("|cffff69b4DOKI|r Pace settings: %d items/batch, %.0fms delay",
			DOKI.attPerformanceSettings.batchSize,
			DOKI.attPerformanceSettings.batchDelay * 1000))
	elseif command == "pacestatus" then
		-- Show current pace settings
		print("|cffff69b4DOKI|r === PACING STATUS ===")
		print(string.format("Paced processing: %s",
			DOKI.attPerformanceSettings.useAsyncProcessing and "ENABLED" or "DISABLED"))
		print(string.format("Batch size: %d items", DOKI.attPerformanceSettings.batchSize))
		print(string.format("Batch delay: %.0fms", DOKI.attPerformanceSettings.batchDelay * 1000))
		local queueSize = #(DOKI.attBatchQueue or {})
		print(string.format("Current queue: %d items", queueSize))
		print(string.format("Processing: %s", DOKI.attBatchProcessing and "YES" or "NO"))
		print("|cffff69b4DOKI|r Fix test complete - should see no individual batch messages")
	else
		print("|cffff69b4DOKI|r War Within Enhanced Surgical System with Ensemble + Merchant Support Commands:")
		print("")
		print("Basic controls:")
		print("  /doki toggle - Enable/disable addon")
		print("  /doki debug - Toggle debug messages")
		print("  /doki smart - Toggle smart mode (considers class restrictions)")
		print("  /doki status - Show addon status and system info")
		print("")
		print("Scanning and updates:")
		print("  /doki scan - Force full scan (creates indicators)")
		print("  /doki surgical - Force surgical update (compares changes)")
		print("  /doki immediate - Trigger immediate surgical update")
		print("  /doki clear - Clear all indicators")
		print("  /doki cleanup - Clean up stale indicators")
		print("  /doki performance - Show detailed performance statistics")
		print("")
		print("Testing and debugging:")
		print("  /doki buttondebug - Debug button texture status")
		print("  /doki testbutton - Test button texture creation")
		print("  /doki testbags - Test bag frame detection")
		print("  /doki testconnection - Test surgical→texture connection")
		print("  /doki snapshot - Show current button-to-item mapping")
		print("  /doki battlepet - Debug battlepet snapshot tracking")
		print("  /doki frames - Debug found item frames")
		print("  /doki why <itemID> - Trace why an item gets/doesn't get an indicator")
		print("")
		print("|cffff8000NEW - Merchant testing:|r")
		print("  /doki testmerchant - Test merchant frame detection")
		print("  /doki testscroll - Simulate merchant scroll events")
		print("  /doki merchantstate - Debug current merchant state")
		print("  /doki merchantbuttons - Check what's visible in merchant buttons")
		print("")
		print("|cffff8000NEW - Ensemble testing:|r")
		print("  /doki ensemble - Check ensemble system status and test detection")
		print("  /doki initensemble - Re-initialize ensemble word extraction")
		print("  /doki testensemble [itemID] - Trace ensemble detection (default: 234522)")
		print("  /doki testbagensembles - Scan bags for ensemble items")
		print("")
		print("|cff00ff00War Within Enhanced Features:|r")
		print("  |cff00ff00•|r Fixed mount detection (GetMountFromItem API)")
		print("  |cff00ff00•|r Enhanced pet detection with collection events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Battlepet (caged pet) support")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble detection: Class 0/Subclass 8 + spell effect + name pattern")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble collection: 100% locale-agnostic color-based detection")
		print("  |cff00ff00•|r |cffff8000FIXED:|r Removed noisy events (COMPANION_UPDATE, etc.)")
		print("  |cff00ff00•|r |cffff8000IMPROVED:|r Timing delays for pet caging")
		print("  |cff00ff00•|r |cffff8000NEW:|r Merchant scroll detection")
		print("  |cff00ff00•|r |cffff8000NEW:|r OnMouseWheel + MERCHANT_UPDATE events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Smart mode auto-rescan on toggle")
		print("  |cff00ff00•|r |cffff8000NEW:|r Delayed cleanup scan (0.2s) with auto-cancellation")
		print("  |cff00ff00•|r Enhanced surgical updates with battlepet + ensemble tracking")
		print("  |cff00ff00•|r Indicators follow items automatically")
		print("  |cff00ff00•|r Ultra-fast throttling (50ms) prevents spam")
		print("  |cff00ff00•|r Indicators appear in TOP-RIGHT corner")
		print("")
		print(
			"|cffff8000Try scrolling in merchant frames or moving ensemble items - indicators should update immediately!|r")
	end
end
