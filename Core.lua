-- DOKI Core - Two-Phase State-Driven Architecture Integration
local addonName, DOKI = ...
-- Initialize addon namespace
DOKI.currentItems = {}
DOKI.overlayPool = {}
DOKI.activeOverlays = {}
DOKI.textureCache = {}
-- Enhanced scanning system variables
DOKI.delayedScanTimer = nil       -- Timer for delayed secondary scan
DOKI.delayedScanCancelled = false -- Flag to track if delayed scan should be cancelled
-- Category-based re-evaluation flags for ATT mode
DOKI.needsTransmogReevaluation = false
DOKI.needsPetReevaluation = false
DOKI.needsMountReevaluation = false
DOKI.needsToyReevaluation = false
DOKI.needsConsumableReevaluation = false
DOKI.needsReagentReevaluation = false
DOKI.needsOtherReevaluation = false
-- Track if collection events are registered
DOKI.collectionEventsRegistered = false
-- ===== TWO-PHASE INTEGRATION: COMPLETION FLAGS =====
-- These prevent surgical updates from interfering with the login scan
DOKI.isInitialScanComplete = false
DOKI.needsFullIndicatorRefresh = false
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
			attTrackReagents = false,
			attTrackConsumables = false,
			lastFullScanTime = nil,
		}
	else
		if DOKI_DB.smartMode == nil then
			DOKI_DB.smartMode = false
		end

		if DOKI_DB.attMode == nil then
			DOKI_DB.attMode = false
		end

		-- Initialize ATT tracking settings
		if DOKI_DB.attTrackReagents == nil then
			DOKI_DB.attTrackReagents = false
		end

		if DOKI_DB.attTrackConsumables == nil then
			DOKI_DB.attTrackConsumables = false
		end

		if DOKI_DB.lastFullScanTime == nil then
			DOKI_DB.lastFullScanTime = nil
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
			-- Proper initialization sequence
			DOKI:InitializeAddonSystems()
			if ElvUI then
				print(
					"|cffff69b4DOKI|r loaded with Two-Phase State-Driven Architecture + ElvUI support + Merchant scroll detection + Ensemble support. Type /doki for commands.")
			else
				print(
					"|cffff69b4DOKI|r loaded with Two-Phase State-Driven Architecture + Merchant scroll detection + Ensemble support. Type /doki for commands.")
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

-- Proper initialization sequence function
function DOKI:InitializeAddonSystems()
	-- Initialize ensemble detection first
	if self.InitializeEnsembleDetection then
		self:InitializeEnsembleDetection()
	end

	-- Initialize surgical update system
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Enhanced surgical update timer with Two-Phase integration
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
				-- ===== ENHANCED TWO-PHASE INTEGRATION: IMMEDIATE INDICATOR CREATION =====
				if DOKI.needsFullIndicatorRefresh and DOKI.isInitialScanComplete then
					DOKI.needsFullIndicatorRefresh = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r === CREATING INDICATORS AFTER TWO-PHASE SCAN (IMMEDIATE MODE) ===")
					end

					-- Use immediate indicator creation instead of throttled scanning
					self:CreateIndicatorsFromCache()
				else
					-- Normal surgical update
					self:SurgicalUpdate(false)
				end
			end
		end
	end)
	-- Initialize enhanced ATT system with Two-Phase State-Driven Watcher
	if self.InitializeEnhancedATTSystem then
		self:InitializeEnhancedATTSystem()
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Addon systems initialized with Two-Phase State-Driven Architecture")
		print("  |cff00ff00•|r Session-long caching enabled")
		print("  |cff00ff00•|r Event debouncing enabled")
		print("  |cff00ff00•|r Cache invalidation events registered")
		print("  |cffffff00•|r Collection events will be registered AFTER Two-Phase validation")
	end
end

function DOKI:CreateIndicatorsFromCache()
	if not self.db or not self.db.enabled or not self.db.attMode then
		-- Fallback to normal scan for non-ATT mode
		return self:FullItemScan()
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Creating indicators directly from ATT cache...")
	end

	local startTime = GetTime()
	local indicatorsCreated = 0
	local itemsProcessed = 0
	local cacheHits = 0
	local cacheMisses = 0
	-- Clear existing indicators first
	if self.ClearAllButtonIndicators then
		self:ClearAllButtonIndicators()
	end

	-- Process all bag items immediately using cached data
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					itemsProcessed = itemsProcessed + 1
					-- Apply ATT filtering
					if self:ShouldTrackItemInATTMode(itemInfo.itemID) then
						-- Check cache directly (no ATT processing)
						local cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected =
								self:GetCachedATTStatus(itemInfo.itemID, itemInfo.hyperlink)
						if cachedIsCollected ~= nil and cachedIsCollected ~= "NO_ATT_DATA" then
							cacheHits = cacheHits + 1
							-- Only create indicator if needed
							if not cachedIsCollected or cachedIsPartiallyCollected then
								-- Find the button for this item
								local button = self:FindBagButton(bagID, slotID)
								if button then
									local itemData = {
										itemID = itemInfo.itemID,
										itemLink = itemInfo.hyperlink,
										isCollected = cachedIsCollected,
										hasOtherTransmogSources = cachedHasOtherSources,
										isPartiallyCollected = cachedIsPartiallyCollected,
										frameType = "cache_refresh",
									}
									if self:AddButtonIndicator(button, itemData) then
										indicatorsCreated = indicatorsCreated + 1
									end
								end
							end
						else
							cacheMisses = cacheMisses + 1
							if self.db and self.db.debugMode and cacheMisses <= 5 then
								local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
								print(string.format("|cffff6600DOKI CACHE MISS:|r %s (ID: %d)", itemName, itemInfo.itemID))
							end
						end
					end
				end
			end
		end
	end

	local duration = GetTime() - startTime
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cache-based indicator creation complete:"))
		print(string.format("  Items processed: %d", itemsProcessed))
		print(string.format("  Cache hits: %d", cacheHits))
		print(string.format("  Cache misses: %d", cacheMisses))
		print(string.format("  Indicators created: %d", indicatorsCreated))
		print(string.format("  Duration: %.3fs", duration))
		if cacheMisses > 0 then
			print(string.format("|cffffff00WARNING:|r %d items not in cache - login scan may have been incomplete", cacheMisses))
		end
	end

	return indicatorsCreated
end

-- Add this helper function to find bag buttons:
function DOKI:FindBagButton(bagID, slotID)
	-- Try ElvUI first
	if ElvUI and self:IsElvUIBagVisible() then
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
	end

	-- Try Blizzard combined bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					local buttonBagID, buttonSlotID = nil, nil
					if itemButton.GetBagID and itemButton.GetID then
						local bagIDSuccess, retrievedBagID = pcall(itemButton.GetBagID, itemButton)
						local slotIDSuccess, retrievedSlotID = pcall(itemButton.GetID, itemButton)
						if bagIDSuccess and slotIDSuccess then
							buttonBagID, buttonSlotID = retrievedBagID, retrievedSlotID
						end
					end

					if buttonBagID == bagID and buttonSlotID == slotID then
						return itemButton
					end
				end
			end
		end
	end

	-- Try individual container frames
	local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
	if containerFrame and containerFrame:IsVisible() then
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
	end

	return nil
end

-- Register events (ONLY startup events, NOT collection events)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", OnEvent)
-- Enhanced slash commands with Two-Phase architecture support
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
		-- ENHANCED: Use enhanced status display with Two-Phase information
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
			DOKI.db.attMode and "On" or "Off",
			DOKI.db.debugMode and "On" or "Off"))
		print(string.format("|cffff69b4DOKI|r Active indicators: %d (%d battlepets)", indicatorCount, battlepetCount))
		print(string.format("|cffff69b4DOKI|r Tracked buttons: %d", snapshotCount))
		-- ADDED: Two-Phase system status
		print(string.format("|cffff69b4DOKI|r Two-Phase Status: Initial scan %s, Refresh needed %s",
			DOKI.isInitialScanComplete and "Complete" or "Pending",
			DOKI.needsFullIndicatorRefresh and "YES" or "NO"))
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
	elseif command == "twophase" or command == "phases" then
		-- Show Two-Phase State-Driven system status
		print("|cffff69b4DOKI|r === TWO-PHASE STATE-DRIVEN SYSTEM STATUS ===")
		-- Check ATT readiness (Phase 1)
		local attReady = _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults and true or false
		print(string.format("Phase 1 (ATT Ready): %s", attReady and "|cff00ff00YES|r" or "|cffff0000NO|r"))
		-- Check scan status
		if DOKI.scanState and DOKI.scanState.isScanInProgress then
			print("|cffffff00STATUS:|r Scan currently in progress")
		elseif DOKI.isInitialScanComplete then
			print("|cff00ff00STATUS:|r Initial scan completed")
		else
			print("|cffffd100STATUS:|r Waiting for Two-Phase validation")
		end

		-- Show Phase 2 test (Client Data Ready)
		print("Phase 2 (Client Data Ready): Testing...")
		local hasCompleteItemLink = false
		local testItemName = "No items found"
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						local itemLink = itemInfo.hyperlink
						if itemLink and not itemLink:find("%[%]") then
							hasCompleteItemLink = true
							testItemName = string.match(itemLink, "%[([^%]]+)%]") or "Unknown"
							break
						else
							testItemName = string.format("Incomplete: '%s'", itemLink)
						end
					end
				end

				if hasCompleteItemLink then break end
			end
		end

		print(string.format("Phase 2 (Client Data Ready): %s - Test item: %s",
			hasCompleteItemLink and "|cff00ff00YES|r" or "|cffff0000NO|r", testItemName))
		-- Show item count in bags
		local totalItems = 0
		local uniqueItems = 0
		local itemIDs = {}
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						if not itemIDs[itemInfo.itemID] then
							itemIDs[itemInfo.itemID] = true
							uniqueItems = uniqueItems + 1
						end
					end
				end
			end
		end

		print(string.format("Inventory: %d total items (%d unique)", totalItems, uniqueItems))
		print(string.format("Cache entries: %d", DOKI.collectionCache and DOKI:TableCount(DOKI.collectionCache) or 0))
		print("|cffffd100NOTE:|r Two-Phase validation ensures both ATT and Client Data are ready")
		print("|cffff69b4DOKI|r === END TWO-PHASE STATUS ===")
	elseif command == "testcanary" then
		-- Test the canary scan manually
		if not DOKI.TestCanaryScan then
			print("|cffff0000ERROR:|r TestCanaryScan function not available")
			return
		end

		DOKI:TestCanaryScan()
	elseif command == "twophasescan" then
		-- Force start the Two-Phase scan process manually
		if DOKI.scanState and DOKI.scanState.isScanInProgress then
			print("|cffff69b4DOKI|r Scan already in progress")
			return
		end

		print("|cffff69b4DOKI|r Forcing Two-Phase State-Driven scan...")
		-- Check ATT readiness first (Phase 1)
		local attReady = _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults and true or false
		if not attReady then
			print("|cffff0000ERROR:|r ATT is not ready - cannot start scan")
			return
		end

		-- Execute Two-Phase sequence manually
		print("|cffff69b4DOKI|r Phase 1 ready - starting Phase 2 (Canary Scan)...")
		if DOKI.StartClientDataWatcher then
			DOKI:StartClientDataWatcher(function()
				print("|cff00ff00DOKI:|r Two-Phase validation complete, executing Force-Prime and scan...")
				-- Execute Force-Prime sequence
				OpenAllBags()
				C_Timer.After(0, function()
					CloseAllBags()
					C_Timer.After(0.1, function()
						if DOKI.StartEnhancedATTScan then
							DOKI:StartEnhancedATTScan(true)
						else
							print("|cffff0000ERROR:|r StartEnhancedATTScan function not available")
						end
					end)
				end)
			end)
		else
			print("|cffff0000ERROR:|r StartClientDataWatcher function not available")
		end
	elseif command == "itemlinks" then
		-- Check the quality of item links (still useful for debugging)
		print("|cffff69b4DOKI|r === ITEM LINK QUALITY CHECK ===")
		local totalItems = 0
		local completeLinks = 0
		local incompleteLinks = 0
		local noLinks = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID then
						totalItems = totalItems + 1
						if itemInfo.hyperlink then
							if DOKI:IsItemLinkComplete(itemInfo.hyperlink) then
								completeLinks = completeLinks + 1
							else
								incompleteLinks = incompleteLinks + 1
								if incompleteLinks <= 3 then
									local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
									print(string.format("  INCOMPLETE: %s -> '%s'", itemName, itemInfo.hyperlink))
								end
							end
						else
							noLinks = noLinks + 1
							if noLinks <= 3 then
								local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
								print(string.format("  NO LINK: %s (ID: %d)", itemName, itemInfo.itemID))
							end
						end
					end
				end
			end
		end

		print(string.format("Results: %d total items", totalItems))
		print(string.format("  %d complete links (%d%%)", completeLinks,
			totalItems > 0 and math.floor((completeLinks / totalItems) * 100) or 0))
		print(string.format("  %d incomplete links (%d%%)", incompleteLinks,
			totalItems > 0 and math.floor((incompleteLinks / totalItems) * 100) or 0))
		print(string.format("  %d no links (%d%%)", noLinks, totalItems > 0 and math.floor((noLinks / totalItems) * 100) or 0))
		if completeLinks == totalItems then
			print("|cff00ff00EXCELLENT:|r All item links are complete - Two-Phase validation worked perfectly!")
		elseif completeLinks > totalItems * 0.9 then
			print("|cffffff00GOOD:|r Most item links are complete - minor issues only")
		else
			print("|cffff6600POOR:|r Many incomplete links - may need Two-Phase validation")
		end

		print("|cffff69b4DOKI|r === END LINK CHECK ===")
		-- All other existing commands remain the same...
		-- [Previous commands continue here - att, attbatch, etc.]
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
	elseif command == "loginscan" then
		print("|cffff69b4DOKI|r Simulating Two-Phase login scan...")
		if DOKI.StartEnhancedATTScan then
			DOKI:StartEnhancedATTScan(true)
		else
			print("|cffff69b4DOKI|r Enhanced ATT system not available")
		end
	elseif command == "scanstatus" then
		if DOKI.scanState and DOKI.scanState.isScanInProgress then
			print(string.format("|cffff69b4DOKI|r Two-Phase scan in progress: %d/%d items (%.1fs)",
				DOKI.scanState.processedItems, DOKI.scanState.totalItems,
				GetTime() - DOKI.scanState.scanStartTime))
		else
			print("|cffff69b4DOKI|r No scan in progress")
			if DOKI.db and DOKI.db.lastFullScanTime then
				local lastScan = date("%H:%M:%S", DOKI.db.lastFullScanTime)
				print(string.format("Last full scan: %s", lastScan))
			else
				print("No full scan recorded")
			end
		end
	elseif command == "forcecomplete" then
		if DOKI.scanState and DOKI.scanState.isScanInProgress then
			print("|cffff69b4DOKI|r Forcing scan completion...")
			if DOKI.CompleteEnhancedATTScan then
				DOKI:CompleteEnhancedATTScan(true)
			end
		else
			print("|cffff69b4DOKI|r No scan in progress to complete")
		end
	elseif command == "forcerefresh" then
		-- Manually trigger indicator refresh
		print("|cffff69b4DOKI|r Forcing indicator refresh...")
		DOKI.needsFullIndicatorRefresh = false
		if DOKI.FullItemScan then
			local count = DOKI:FullItemScan()
			print(string.format("|cffff69b4DOKI|r Force refresh complete: %d indicators created", count))
		else
			print("|cffff69b4DOKI|r FullItemScan function not available")
		end
	elseif command == "setrefreshflag" then
		-- Manually set the refresh flag for testing
		DOKI.needsFullIndicatorRefresh = true
		print("|cffff69b4DOKI|r Indicator refresh flag manually set to TRUE")
		print("|cffff69b4DOKI|r Open bags to trigger indicator creation")
	elseif command == "racecondition" then
		-- Debug the race condition
		print("|cffff69b4DOKI|r === TWO-PHASE RACE CONDITION DEBUG ===")
		print(string.format("Initial scan complete: %s", DOKI.isInitialScanComplete and "YES" or "NO"))
		print(string.format("Needs indicator refresh: %s", DOKI.needsFullIndicatorRefresh and "YES" or "NO"))
		print(string.format("ATT mode enabled: %s", DOKI.db.attMode and "YES" or "NO"))
		print(string.format("Scan in progress: %s", (DOKI.scanState and DOKI.scanState.isScanInProgress) and "YES" or "NO"))
		if DOKI.GetATTWatcherStatus then
			local watcherActive = DOKI:GetATTWatcherStatus()
			print(string.format("ATT watcher active: %s", watcherActive and "YES" or "NO"))
		end

		-- Check if surgical timer is running
		print(string.format("Surgical timer active: %s", DOKI.surgicalTimer and "YES" or "NO"))
		-- Show current cache status
		local cacheCount = 0
		if DOKI.collectionCache then
			for _ in pairs(DOKI.collectionCache) do
				cacheCount = cacheCount + 1
			end
		end

		print(string.format("Collection cache entries: %d", cacheCount))
		print("|cffff69b4DOKI|r === END TWO-PHASE RACE CONDITION DEBUG ===")
		print("")
		print("|cffffd100DIAGNOSIS:|r")
		if not DOKI.isInitialScanComplete and cacheCount == 0 then
			print("  • Two-Phase validation in progress or not started")
		elseif DOKI.isInitialScanComplete and DOKI.needsFullIndicatorRefresh then
			print("  • Cache populated but indicators not yet created")
			print("  • Solution: Open your bags to trigger indicator creation")
		elseif DOKI.isInitialScanComplete and not DOKI.needsFullIndicatorRefresh then
			print("  • System working correctly with Two-Phase validation")
		else
			print("  • Scan still in progress or cache being populated")
		end
	elseif command == "itemcompare" then
		-- Compare item counts between methods
		print("|cffff69b4DOKI|r === ITEM COLLECTION COMPARISON ===")
		-- Method 1: Unified logic
		local unifiedItems = DOKI:GetAllBagItems()
		print(string.format("Unified GetAllBagItems(): %d items", #unifiedItems))
		-- Method 2: Simple bag iteration (old StartEnhancedATTScan logic)
		local simpleCount = 0
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						simpleCount = simpleCount + 1
					end
				end
			end
		end

		print(string.format("Simple bag iteration: %d items", simpleCount))
		-- Show difference
		local difference = #unifiedItems - simpleCount
		if difference == 0 then
			print("|cff00ff00PERFECT MATCH:|r Both methods find the same number of items")
		else
			print(string.format("|cffff6600DIFFERENCE:|r Unified finds %d %s items than simple iteration",
				math.abs(difference), difference > 0 and "more" or "fewer"))
		end

		-- Show first few items from unified method with their sources
		if #unifiedItems > 0 then
			print("First 5 items from unified method:")
			for i = 1, math.min(5, #unifiedItems) do
				local item = unifiedItems[i]
				local itemName = C_Item.GetItemInfo(item.itemID) or "Unknown"
				print(string.format("  %d. %s (%s)", i, itemName, item.source))
			end
		end

		print("|cffff69b4DOKI|r === END COMPARISON ===")
	else
		print("|cffff69b4DOKI|r Two-Phase State-Driven Enhanced Surgical System Commands:")
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
		print("")
		print("|cffff8000NEW - Two-Phase State-Driven ATT System:|r")
		print("  /doki twophase - Show Two-Phase system status and validation")
		print("  /doki testcanary - Test the canary scan (Phase 2) manually")
		print("  /doki twophasescan - Force start Two-Phase scan manually")
		print("  /doki itemlinks - Check item link quality and completeness")
		print("  /doki loginscan - Simulate login scan with progress UI")
		print("  /doki scanstatus - Show current scan progress")
		print("  /doki forcecomplete - Force complete current scan")
		print("")
		print("ATT Mode:")
		print("  /doki att - Toggle ATT mode (uses AllTheThings data)")
		print("  /doki forcerefresh - Force indicator refresh after scan")
		print("  /doki racecondition - Debug Two-Phase race condition status")
	end
end
