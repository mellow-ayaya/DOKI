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

-- Event handlers
local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		local loadedAddon = ...
		if loadedAddon == addonName then
			InitializeSavedVariables()
			-- Initialize clean systems
			DOKI:InitializeButtonTextureSystem()
			DOKI:InitializeUniversalScanning()
			if ElvUI then
				print(
					"|cffff69b4DOKI|r loaded with War Within surgical system + ElvUI support + Merchant scroll detection + Ensemble support. Type /doki for commands.")
			else
				print(
					"|cffff69b4DOKI|r loaded with War Within surgical system + Merchant scroll detection + Ensemble support. Type /doki for commands.")
			end

			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		local itemID, success = ...
		if DOKI.OnItemInfoReceived then
			DOKI:OnItemInfoReceived(itemID, success)
		end
	end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
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
		-- ADDED: ATT mode toggle
		DOKI.db.attMode = not DOKI.db.attMode
		local status = DOKI.db.attMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r ATT mode is now " .. status)
		print("|cffff69b4DOKI|r ATT mode uses AllTheThings addon data when available")
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

		-- Replace these command handlers with the fixed versions:
	elseif command == "attbagscan" or command == "bagatt" or string.find(command, "^attbagscan ") or string.find(command, "^bagatt ") then
		-- Debug ATT bag scan - scans first N items for ATT data
		local maxItems = 10 -- default
		-- Extract number from command if present
		local num = tonumber(string.match(command, "%d+"))
		if num then
			maxItems = num
		end

		if DOKI.DebugATTBagScan then
			DOKI:DebugATTBagScan(maxItems)
		else
			print("|cffff69b4DOKI|r DebugATTBagScan function not available")
		end
	elseif command == "atttest" or string.find(command, "^atttest ") then
		-- Test proper item loading system
		local targetItemID = 211017 -- default catalyst item
		-- Extract number from command if present
		local num = tonumber(string.match(command, "%d+"))
		if num then
			targetItemID = num
		end

		if DOKI.TestProperItemLoading then
			DOKI:TestProperItemLoading(targetItemID)
		else
			print("|cffff69b4DOKI|r TestProperItemLoading function not available")
		end
	elseif command == "testensemble" or string.find(command, "^testensemble ") then
		-- Test ensemble detection
		local itemID = 234522 -- default ensemble item
		-- Extract number from command if present
		local num = tonumber(string.match(command, "%d+"))
		if num then
			itemID = num
		end

		if DOKI.TraceEnsembleDetection then
			DOKI:TraceEnsembleDetection(itemID, nil)
		else
			print("|cffff69b4DOKI|r TraceEnsembleDetection function not available")
		end
	elseif command == "initensemble" then
		-- Re-initialize ensemble detection
		if DOKI.InitializeEnsembleDetection then
			DOKI.ensembleWordCache = nil -- Force re-extraction
			DOKI:InitializeEnsembleDetection()
			print("|cffff69b4DOKI|r Ensemble detection re-initialized")
		else
			print("|cffff69b4DOKI|r InitializeEnsembleDetection function not available")
		end
	elseif command == "testbagensembles" then
		-- Scan bags for ensemble items
		print("|cffff69b4DOKI|r === SCANNING BAGS FOR ENSEMBLE ITEMS ===")
		local ensemblesFound = 0
		local totalItems = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
						if DOKI:IsEnsembleItem(itemInfo.itemID, itemName) then
							ensemblesFound = ensemblesFound + 1
							local isCollected, _, _ = DOKI:IsEnsembleCollected(itemInfo.itemID, itemInfo.hyperlink)
							print(string.format("  Found: %s (ID: %d) - %s",
								itemName, itemInfo.itemID,
								isCollected and "COLLECTED" or "NEEDS INDICATOR"))
						end
					end
				end
			end
		end

		print(string.format("Scan complete: %d ensembles found out of %d total items", ensemblesFound, totalItems))
	elseif command == "performance" or command == "perf" then
		-- Show detailed performance statistics
		if DOKI.ShowPerformanceStats then
			DOKI:ShowPerformanceStats()
		else
			print("|cffff69b4DOKI|r ShowPerformanceStats function not available")
		end
	elseif command == "buttondebug" then
		-- Debug button texture status
		if DOKI.DebugButtonTextureStatus then
			DOKI:DebugButtonTextureStatus()
		else
			print("|cffff69b4DOKI|r DebugButtonTextureStatus function not available")
		end
	elseif command == "testbutton" then
		-- Test button texture creation
		if DOKI.TestButtonTextureCreation then
			DOKI:TestButtonTextureCreation()
		else
			print("|cffff69b4DOKI|r TestButtonTextureCreation function not available")
		end
	elseif command == "testconnection" then
		-- Test surgical→texture connection
		if DOKI.TestSurgicalTextureConnection then
			DOKI:TestSurgicalTextureConnection()
		else
			print("|cffff69b4DOKI|r TestSurgicalTextureConnection function not available")
		end
	elseif command == "snapshot" then
		-- Show current button-to-item mapping
		if DOKI.DebugButtonSnapshot then
			DOKI:DebugButtonSnapshot()
		else
			print("|cffff69b4DOKI|r DebugButtonSnapshot function not available")
		end
	elseif command == "battlepet" then
		-- Debug battlepet snapshot tracking
		if DOKI.DebugBattlepetSnapshot then
			DOKI:DebugBattlepetSnapshot()
		else
			print("|cffff69b4DOKI|r DebugBattlepetSnapshot function not available")
		end
	elseif command == "frames" then
		-- Debug found item frames
		if DOKI.DebugFoundFrames then
			DOKI:DebugFoundFrames()
		else
			print("|cffff69b4DOKI|r DebugFoundFrames function not available")
		end
	elseif string.find(command, "why ") then
		-- Trace why an item gets/doesn't get an indicator - /doki why 12345
		local itemID = tonumber(string.match(command, "%d+"))
		if not itemID then
			print("|cffff69b4DOKI|r Usage: /doki why <itemID>")
			print("|cffff69b4DOKI|r Example: /doki why 159478")
			return
		end

		print(string.format("|cffff69b4DOKI|r === TRACING INDICATOR LOGIC FOR ITEM %d ===", itemID))
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		print(string.format("Item: %s (ID: %d)", itemName, itemID))
		-- Step 1: Check if collectible
		local isCollectible = DOKI:IsCollectibleItem(itemID, nil)
		print(string.format("Step 1 - IsCollectibleItem: %s", isCollectible and "TRUE" or "FALSE"))
		if not isCollectible then
			print("RESULT: No indicator (item not collectible)")
			return
		end

		-- Step 2: Check collection status
		local isCollected, showYellowD, showPurple = DOKI:IsItemCollected(itemID, nil)
		print(string.format("Step 2 - IsItemCollected: collected=%s, yellowD=%s, purple=%s",
			tostring(isCollected), tostring(showYellowD), tostring(showPurple)))
		-- Step 3: Determine indicator
		if isCollected and not showPurple then
			print("RESULT: No indicator (item fully collected)")
		elseif showPurple then
			print("RESULT: PINK indicator (partial collection)")
		elseif showYellowD then
			print("RESULT: BLUE indicator (special case)")
		elseif not isCollected then
			print("RESULT: ORANGE indicator (not collected)")
		else
			print("RESULT: Unknown case")
		end

		print("|cffff69b4DOKI|r === END TRACE ===")
	elseif command == "initloader" then
		-- Initialize the item loader
		DOKI:InitializeItemLoader()
		print("|cffff69b4DOKI|r Item loader initialized")
	elseif command == "cleanloader" then
		-- Clean up the item loader
		DOKI:CleanupItemLoader()
		print("|cffff69b4DOKI|r Item loader cleaned up")
	elseif command == "testknown" then
		-- Test known ATT items to verify ATT is working
		DOKI:TestKnownATTItems()
		DOKI:InspectItem159478()
	elseif command == "attfixed" then
		-- Test the NEW fixed ATT parsing with Unicode symbols
		if DOKI.TestFixedATTParsing then
			DOKI:TestFixedATTParsing()
		else
			print("|cffff69b4DOKI|r Fixed ATT parsing test function not available")
		end
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
	end
end
