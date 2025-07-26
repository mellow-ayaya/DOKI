-- DOKI Core - Enhanced Surgical Update System
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
			smartMode = false, -- Smart detection mode for class restrictions
		}
	else
		-- Add new settings to existing DB
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
			-- Initialize surgical button texture system
			DOKI:InitializeButtonTextureSystem()
			-- Initialize enhanced surgical scanning system
			DOKI:InitializeUniversalScanning()
			if ElvUI then
				print("|cffff69b4DOKI|r loaded with enhanced surgical update system + ElvUI support. Type /doki for commands.")
			else
				print("|cffff69b4DOKI|r loaded with enhanced surgical update system. Type /doki for commands.")
			end

			frame:UnregisterEvent("ADDON_LOADED")
		end
	end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)
-- Slash commands
SLASH_DOKI1 = "/doki"
SlashCmdList["DOKI"] = function(msg)
	local command = string.lower(strtrim(msg or ""))
	if command == "toggle" then
		DOKI.db.enabled = not DOKI.db.enabled
		local status = DOKI.db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		print("|cffff69b4DOKI|r is now " .. status)
		if not DOKI.db.enabled then
			-- Clean up when disabled
			if DOKI.CleanupButtonTextureSystem then
				DOKI:CleanupButtonTextureSystem()
			end
		else
			-- Re-initialize when enabled
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
		-- Rescan when mode changes
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
		if DOKI.buttonTextures then
			for _, textureData in pairs(DOKI.buttonTextures) do
				if textureData.isActive then
					indicatorCount = indicatorCount + 1
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
		print(string.format("|cffff69b4DOKI|r Active indicators: %d", indicatorCount))
		print(string.format("|cffff69b4DOKI|r Tracked buttons: %d", snapshotCount))
		print("|cffff69b4DOKI|r System: Enhanced Surgical Updates")
		print("  |cff00ff00•|r Regular updates: 0.5s interval")
		print("  |cff00ff00•|r Immediate updates: ITEM_UNLOCKED event")
		print(string.format("  |cff00ff00•|r Throttling: %.1fs minimum between updates",
			DOKI.surgicalUpdateThrottleTime or 0.1))
		-- Show performance stats if available
		if DOKI.totalUpdates and DOKI.totalUpdates > 0 then
			print(string.format("  |cff00ff00•|r Total updates: %d (%d immediate)",
				DOKI.totalUpdates, DOKI.immediateUpdates or 0))
			if DOKI.throttledUpdates and DOKI.throttledUpdates > 0 then
				print(string.format("  |cffffff00•|r Throttled updates: %d", DOKI.throttledUpdates))
			end
		end
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
	elseif command == "testsurgical" then
		if DOKI.TestSurgicalSystem then
			DOKI:TestSurgicalSystem()
		else
			print("|cffff69b4DOKI|r Surgical test not available")
		end
	elseif command == "testenhanced" or command == "testresponse" then
		print("|cffff69b4DOKI|r === TESTING ENHANCED RESPONSE SYSTEM ===")
		print("|cffff69b4DOKI|r This test will demonstrate the enhanced update system:")
		print("  1. Move an item in your bags")
		print("  2. Watch for immediate indicator response")
		print("  3. The indicator should follow the item instantly")
		print("")
		print("|cffff69b4DOKI|r System details:")
		print("  - ITEM_UNLOCKED event triggers immediate updates")
		print("  - Regular fallback updates every 0.5s")
		print("  - 100ms throttling prevents update spam")
		print("")
		print("|cffff69b4DOKI|r Open your bags and try moving collectible items!")
	elseif command == "snapshot" then
		if DOKI.CreateButtonSnapshot then
			local snapshot = DOKI:CreateButtonSnapshot()
			local count = 0
			for button, itemID in pairs(snapshot) do
				count = count + 1
				if count <= 5 then -- Show first 5 as examples
					local buttonName = ""
					local nameSuccess, name = pcall(button.GetName, button)
					if nameSuccess and name then
						buttonName = name
					else
						buttonName = "unnamed"
					end

					local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
					print(string.format("|cffff69b4DOKI|r %s: %s (ID: %d)", buttonName, itemName, itemID))
				end
			end

			if count > 5 then
				print(string.format("|cffff69b4DOKI|r ... and %d more buttons", count - 5))
			end

			print(string.format("|cffff69b4DOKI|r Total: %d buttons with items", count))
		else
			print("|cffff69b4DOKI|r Snapshot function not available")
		end
	elseif command == "performance" or command == "perf" then
		if DOKI.ShowPerformanceStats then
			DOKI:ShowPerformanceStats()
		else
			print("|cffff69b4DOKI|r Performance stats not available")
		end

		-- Debug commands for original functionality
	elseif command == "frames" then
		if DOKI.DebugFoundFrames then
			DOKI:DebugFoundFrames()
		else
			print("|cffff69b4DOKI|r Frame debug function not available")
		end
	elseif string.match(command, "^debug (%d+)$") then
		local itemID = tonumber(string.match(command, "^debug (%d+)$"))
		if DOKI.DebugTransmogItem then
			DOKI:DebugTransmogItem(itemID)
		else
			print("|cffff69b4DOKI|r Debug function not available")
		end
	elseif string.match(command, "^smart (%d+)$") then
		local itemID = tonumber(string.match(command, "^smart (%d+)$"))
		if DOKI.DebugSmartTransmog then
			DOKI:DebugSmartTransmog(itemID)
		else
			print("|cffff69b4DOKI|r Smart debug function not available")
		end
	else
		-- Help
		print("|cffff69b4DOKI|r Enhanced Surgical Update System Commands:")
		print("")
		print("Basic controls:")
		print("  /doki toggle - Enable/disable addon")
		print("  /doki debug - Toggle debug messages")
		print("  /doki smart - Toggle smart mode (considers class restrictions)")
		print("  /doki status - Show addon status and enhanced system info")
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
		print("  /doki testsurgical - Test surgical update detection")
		print("  /doki testenhanced - Test enhanced response system")
		print("  /doki snapshot - Show current button-to-item mapping")
		print("  /doki frames - Debug found item frames")
		print("")
		print("Advanced debugging:")
		print("  /doki debug <itemID> - Debug transmog collection status")
		print("  /doki smart <itemID> - Debug smart transmog analysis")
		print("")
		print("|cff00ff00Enhanced System Features:|r")
		print("  |cff00ff00•|r No flickering (no mass clearing)")
		print("  |cff00ff00•|r Only updates buttons that actually changed")
		print("  |cff00ff00•|r 0.5-second regular update interval")
		print("  |cff00ff00•|r |cffff8000IMMEDIATE|r response to item drops (ITEM_UNLOCKED)")
		print("  |cff00ff00•|r Indicators follow items automatically")
		print("  |cff00ff00•|r Smart throttling prevents update spam")
		print("  |cff00ff00•|r Minimal events (UI state changes only)")
		print("")
		print("|cffff8000Try moving items in your bags to see immediate response!|r")
	end
end
