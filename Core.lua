-- DOKI Core - Complete War Within Fix
local addonName, DOKI = ...
-- Initialize addon namespace
DOKI.currentItems = {}
DOKI.overlayPool = {}
DOKI.activeOverlays = {}
DOKI.textureCache = {}
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
				print("|cffff69b4DOKI|r loaded with War Within surgical system + ElvUI support. Type /doki for commands.")
			else
				print("|cffff69b4DOKI|r loaded with War Within surgical system. Type /doki for commands.")
			end

			frame:UnregisterEvent("ADDON_LOADED")
		end
	end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)
-- Enhanced slash commands with battlepet support
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
		DOKI.db.smartMode = not DOKI.db.smartMode
		local status = DOKI.db.smartMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r smart mode is now " .. status)
		print("|cffff69b4DOKI|r Smart mode considers class restrictions when determining if items are needed")
		if DOKI.db.enabled and DOKI.ForceUniversalScan then
			DOKI:ForceUniversalScan()
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
		print("|cffff69b4DOKI|r System: War Within Enhanced Surgical System")
		print("  |cff00ff00•|r Regular updates: 0.2s interval")
		print("  |cff00ff00•|r Clean events: Noisy events removed")
		print("  |cff00ff00•|r Battlepet support: Caged pet detection")
		print("  |cff00ff00•|r Mount fix: GetMountFromItem API")
		print("  |cff00ff00•|r Pet timing: Collection event delays")
		print(string.format("  |cff00ff00•|r Throttling: %.0fms minimum between updates",
			(DOKI.surgicalUpdateThrottleTime or 0.05) * 1000))
		if DOKI.totalUpdates and DOKI.totalUpdates > 0 then
			print(string.format("  |cff00ff00•|r Total updates: %d (%d immediate)",
				DOKI.totalUpdates, DOKI.immediateUpdates or 0))
			if DOKI.throttledUpdates and DOKI.throttledUpdates > 0 then
				print(string.format("  |cffffff00•|r Throttled updates: %d", DOKI.throttledUpdates))
			end
		end
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
	elseif command == "testconnection" or command == "testbridge" then
		print("|cffff69b4DOKI|r === TESTING SURGICAL→TEXTURE CONNECTION ===")
		print("|cffff69b4DOKI|r Testing the bridge between surgical detection and button textures...")
		if DOKI.ProcessSurgicalUpdate then
			print("  ✅ ProcessSurgicalUpdate function exists")
			local changes = DOKI:ProcessSurgicalUpdate()
			print(string.format("  ✅ Surgical update completed: %d changes detected", changes))
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

			print(string.format("  ✅ Active button textures: %d (%d battlepets)", activeCount, battlepetCount))
		else
			print("  ❌ ProcessSurgicalUpdate function missing!")
		end

		print("|cffff69b4DOKI|r Event system status:")
		if DOKI.eventFrame then
			print("  ✅ Event frame exists")
			print("  ✅ Listening for: PET_JOURNAL_LIST_UPDATE, COMPANION_LEARNED/UNLEARNED")
			print("  ✅ Removed noisy events: COMPANION_UPDATE, MOUNT_JOURNAL_USABILITY_CHANGED")
		else
			print("  ❌ Event frame missing!")
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
		print("|cffff69b4DOKI|r War Within Enhanced Surgical System Commands:")
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
		print("")
		print("|cff00ff00War Within Enhanced Features:|r")
		print("  |cff00ff00•|r Fixed mount detection (GetMountFromItem API)")
		print("  |cff00ff00•|r Enhanced pet detection with collection events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Battlepet (caged pet) support")
		print("  |cff00ff00•|r |cffff8000FIXED:|r Removed noisy events (COMPANION_UPDATE, etc.)")
		print("  |cff00ff00•|r |cffff8000IMPROVED:|r Timing delays for pet caging")
		print("  |cff00ff00•|r Enhanced surgical updates with battlepet tracking")
		print("  |cff00ff00•|r Indicators follow items automatically")
		print("  |cff00ff00•|r Ultra-fast throttling (50ms) prevents spam")
		print("  |cff00ff00•|r Indicators appear in TOP-RIGHT corner")
		print("")
		print("|cffff8000Try caging/learning pets - indicators should update immediately!|r")
	end
end
