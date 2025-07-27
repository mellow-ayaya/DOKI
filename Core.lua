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
			smartMode = false,
		}
	else
		if DOKI_DB.smartMode == nil then
			DOKI_DB.smartMode = false
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

		print(string.format("|cffff69b4DOKI|r Status: %s, Smart: %s, Debug: %s",
			DOKI.db.enabled and "Enabled" or "Disabled",
			DOKI.db.smartMode and "On" or "Off",
			DOKI.db.debugMode and "On" or "Off"))
		print(string.format("|cffff69b4DOKI|r Active indicators: %d (%d battlepets)", indicatorCount, battlepetCount))
		print(string.format("|cffff69b4DOKI|r Tracked buttons: %d", snapshotCount))
		-- ADDED: Ensemble status
		local ensembleWord = DOKI.ensembleWordCache
		print(string.format("|cffff69b4DOKI|r Ensemble detection: %s",
			ensembleWord and ("Ready (" .. ensembleWord .. ")") or "Not initialized"))
		print("|cffff69b4DOKI|r System: War Within Enhanced Surgical System with Ensemble + Merchant Support")
		print("  |cff00ff00•|r Regular updates: 0.2s interval")
		print("  |cff00ff00•|r Clean events: Noisy events removed")
		print("  |cff00ff00•|r Battlepet support: Caged pet detection")
		print("  |cff00ff00•|r Mount fix: GetMountFromItem API")
		print("  |cff00ff00•|r Pet timing: Collection event delays")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble support: Locale-aware detection + color-based collection status")
		print("  |cff00ff00•|r |cffff8000NEW:|r Merchant scroll detection")
		print("  |cff00ff00•|r |cffff8000NEW:|r OnMouseWheel + MERCHANT_UPDATE events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Smart mode auto-rescan on toggle")
		print("  |cff00ff00•|r |cffff8000NEW:|r Delayed cleanup scan (0.2s) with auto-cancellation")
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
	elseif command == "initensemble" then
		DOKI:InitializeEnsembleDetection()
		print("|cffff69b4DOKI|r Ensemble detection re-initialized")
		-- Show result
		local ensembleWord = DOKI.ensembleWordCache
		if ensembleWord then
			print(string.format("|cffff69b4DOKI|r Successfully extracted ensemble word: '%s'", ensembleWord))
		else
			print("|cffff69b4DOKI|r Failed to extract ensemble word - check if item 234522 is available")
		end
	elseif string.find(command, "testensemble") then
		-- Extract item ID from command like "testensemble 12345"
		local itemID = tonumber(string.match(command, "testensemble (%d+)"))
		if not itemID then
			itemID = 234522 -- Default to known ensemble
		end

		print(string.format("|cffff69b4DOKI|r Testing ensemble detection for item %d", itemID))
		if DOKI.TraceEnsembleDetection then
			DOKI:TraceEnsembleDetection(itemID, nil)
		else
			print("|cffff69b4DOKI|r TraceEnsembleDetection function not available")
		end
	elseif command == "testbagensembles" then
		print("|cffff69b4DOKI|r === SCANNING BAGS FOR ENSEMBLES ===")
		local totalItems = 0
		local ensembleItems = 0
		local collectedEnsembles = 0
		local needIndicatorEnsembles = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						if DOKI:IsEnsembleItem(itemInfo.itemID) then
							ensembleItems = ensembleItems + 1
							local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
							local isCollected = DOKI:IsEnsembleCollected(itemInfo.itemID, itemInfo.hyperlink)
							if isCollected then
								collectedEnsembles = collectedEnsembles + 1
								print(string.format("   %s (ID: %d) - COLLECTED", itemName, itemInfo.itemID))
							else
								needIndicatorEnsembles = needIndicatorEnsembles + 1
								print(string.format("   %s (ID: %d) - NEEDS INDICATOR", itemName, itemInfo.itemID))
							end
						end
					end
				end
			end
		end

		print(string.format("|cffff69b4DOKI|r Bag scan complete:"))
		print(string.format("  Total items: %d", totalItems))
		print(string.format("  Ensemble items: %d", ensembleItems))
		print(string.format("  Collected ensembles: %d", collectedEnsembles))
		print(string.format("  Need indicators: %d", needIndicatorEnsembles))
		if ensembleItems == 0 then
			print("|cffff69b4DOKI|r No ensembles found in bags. Try with known ensemble items.")
		end
	elseif string.find(command, "why ") or string.find(command, "trace ") then
		-- Extract item ID from command like "why 12345" or "trace 12345"
		local itemID = tonumber(string.match(command, "%d+"))
		if itemID then
			DOKI:TraceItemDetection(itemID, nil)
		else
			print("|cffff69b4DOKI|r Usage: /doki why <itemID> or /doki trace <itemID>")
			print("|cffff69b4DOKI|r Example: /doki why 61357")
		end
	elseif command == "testconnection" or command == "testbridge" then
		print("|cffff69b4DOKI|r === TESTING SURGICAL→TEXTURE CONNECTION ===")
		print("|cffff69b4DOKI|r Testing the bridge between surgical detection and button textures...")
		if DOKI.ProcessSurgicalUpdate then
			print("   ProcessSurgicalUpdate function exists")
			local changes = DOKI:ProcessSurgicalUpdate()
			print(string.format("   Surgical update completed: %d changes detected", changes))
			local activeCount = 0
			local battlepetCount = 0
			if DOKI.buttonTextures then
				for _, textureData in pairs(DOKI.buttonTextures) do
					if textureData.isActive then
						activeCount = activeCount + 1
						if textureData.itemLink and string.find(textureData.itemLink, "battlepet:") then
							battlepetCount = battlepetCount + 1
						end
					end
				end
			end

			print(string.format("   Active button textures: %d (%d battlepets)", activeCount, battlepetCount))
		else
			print("   ProcessSurgicalUpdate function missing!")
		end

		print("|cffff69b4DOKI|r Event system status:")
		if DOKI.eventFrame then
			print("   Event frame exists")
			print("   Listening for: PET_JOURNAL_LIST_UPDATE, COMPANION_LEARNED/UNLEARNED")
			print("   |cffff8000NEW:|r Listening for: MERCHANT_SHOW, MERCHANT_UPDATE, MERCHANT_CLOSED")
			print("   Removed noisy events: COMPANION_UPDATE, MOUNT_JOURNAL_USABILITY_CHANGED")
		else
			print("   Event frame missing!")
		end

		print("|cffff69b4DOKI|r Merchant system status:")
		if DOKI.InitializeMerchantScrollDetection then
			print("   Merchant scroll detection available")
			if MerchantFrame and MerchantFrame:IsVisible() then
				print("   Merchant is open - testing scroll hooks")
				local scrollBox = MerchantFrame.ScrollBox
				if scrollBox then
					print("     ScrollBox found")
					print(string.format("    Mouse wheel enabled: %s", tostring(scrollBox:IsMouseWheelEnabled())))
				else
					print("     ScrollBox not found")
				end
			else
				print("   Merchant is closed - open a merchant to test")
			end
		else
			print("   Merchant scroll detection missing!")
		end

		print("|cffff69b4DOKI|r Connection test complete!")
	elseif command == "buttondebug" then
		if DOKI.DebugButtonTextures then
			DOKI:DebugButtonTextures()
		else
			print("|cffff69b4DOKI|r Button texture debug not available")
		end
	elseif command == "testbutton" then
		if DOKI.TestButtonTextureCreation then
			DOKI:TestButtonTextureCreation()
		else
			print("|cffff69b4DOKI|r Button texture test not available")
		end
	elseif command == "snapshot" then
		if DOKI.CreateButtonSnapshot then
			local snapshot = DOKI:CreateButtonSnapshot()
			local count = 0
			local battlepetCount = 0
			for button, itemData in pairs(snapshot) do
				count = count + 1
				if count <= 5 then
					local buttonName = ""
					local nameSuccess, name = pcall(button.GetName, button)
					if nameSuccess and name then
						buttonName = name
					else
						buttonName = "unnamed"
					end

					local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
					local extraInfo = ""
					if itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
						battlepetCount = battlepetCount + 1
						local speciesID = DOKI:GetPetSpeciesFromBattlePetLink(itemData.itemLink)
						extraInfo = string.format(" [Battlepet Species: %d]", speciesID or 0)
					end

					print(string.format("|cffff69b4DOKI|r %s: %s (ID: %d)%s",
						buttonName, itemName, itemData.itemID, extraInfo))
				elseif itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
					battlepetCount = battlepetCount + 1
				end
			end

			if count > 5 then
				print(string.format("|cffff69b4DOKI|r ... and %d more buttons", count - 5))
			end

			print(string.format("|cffff69b4DOKI|r Total: %d buttons with items (%d battlepets)", count, battlepetCount))
		else
			print("|cffff69b4DOKI|r Snapshot function not available")
		end

		-- ADDED: New battlepet-specific debug command
	elseif command == "battlepet" or command == "bp" then
		if DOKI.DebugBattlepetSnapshot then
			DOKI:DebugBattlepetSnapshot()
		else
			print("|cffff69b4DOKI|r Battlepet debug function not available")
		end
	elseif command == "performance" or command == "perf" then
		if DOKI.ShowPerformanceStats then
			DOKI:ShowPerformanceStats()
		else
			print("|cffff69b4DOKI|r Performance stats not available")
		end
	elseif command == "frames" then
		if DOKI.DebugFoundFrames then
			DOKI:DebugFoundFrames()
		else
			print("|cffff69b4DOKI|r Frame debug function not available")
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
