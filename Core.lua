-- DOKI Core - Universal Scanning Version
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
			DOKI:InitializeOverlaySystem()
			-- Initialize universal scanning system
			DOKI:InitializeUniversalScanning()
			if ElvUI then
				print("|cffff69b4DOKI|r loaded with universal scanning + ElvUI support. Type /doki for commands.")
			else
				print("|cffff69b4DOKI|r loaded with universal scanning. Type /doki for commands.")
			end

			frame:UnregisterEvent("ADDON_LOADED")
		end
	end

	-- Note: Universal scanning system handles all other events automatically
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
			if DOKI.ClearAllOverlays then
				DOKI:ClearAllOverlays()
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
			print(string.format("|cffff69b4DOKI|r Universal scan complete: %d overlays created", count))
		else
			print("|cffff69b4DOKI|r Universal scan function not available")
		end
	elseif command == "universalinit" then
		if DOKI.InitializeUniversalScanning then
			DOKI:InitializeUniversalScanning()
			print("|cffff69b4DOKI|r Universal scanning system reinitialized")
		else
			print("|cffff69b4DOKI|r Universal scanning not available")
		end
	elseif command == "clear" then
		if DOKI.ClearAllOverlays then
			DOKI:ClearAllOverlays()
			print("|cffff69b4DOKI|r All overlays cleared")
		end
	elseif command == "status" then
		local overlayCount = 0
		for _ in pairs(DOKI.activeOverlays) do
			overlayCount = overlayCount + 1
		end

		local itemCount = 0
		for _ in pairs(DOKI.currentItems) do
			itemCount = itemCount + 1
		end

		print(string.format("|cffff69b4DOKI|r Status: %s, Smart: %s, Debug: %s",
			DOKI.db.enabled and "Enabled" or "Disabled",
			DOKI.db.smartMode and "On" or "Off",
			DOKI.db.debugMode and "On" or "Off"))
		print(string.format("|cffff69b4DOKI|r Active overlays: %d, Tracked items: %d", overlayCount, itemCount))
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
	elseif string.match(command, "^class (%d+) (%d+)$") then
		local sourceIDStr, appearanceIDStr = string.match(command, "^class (%d+) (%d+)$")
		local sourceID = tonumber(sourceIDStr)
		local appearanceID = tonumber(appearanceIDStr)
		if DOKI.DebugClassRestrictions then
			DOKI:DebugClassRestrictions(sourceID, appearanceID)
		else
			print("|cffff69b4DOKI|r Class debug function not available")
		end
	elseif string.match(command, "^item (%d+)$") then
		local itemID = tonumber(string.match(command, "^item (%d+)$"))
		if DOKI.DebugItemInfo then
			DOKI:DebugItemInfo(itemID)
		else
			print("|cffff69b4DOKI|r Item debug function not available")
		end
	elseif string.match(command, "^source (%d+)$") then
		local sourceID = tonumber(string.match(command, "^source (%d+)$"))
		if DOKI.DebugSourceRestrictions then
			DOKI:DebugSourceRestrictions(sourceID)
		else
			print("|cffff69b4DOKI|r Source debug function not available")
		end
	elseif command == "frames" then
		if DOKI.DebugFoundFrames then
			DOKI:DebugFoundFrames()
		else
			print("|cffff69b4DOKI|r Frame debug function not available")
		end
	elseif command == "testmerchant" then
		if DOKI.TestMerchantFrames then
			DOKI:TestMerchantFrames()
		else
			print("|cffff69b4DOKI|r Merchant test function not available")
		end
	else
		print("|cffff69b4DOKI|r commands:")
		print("  /doki toggle - Enable/disable addon")
		print("  /doki debug - Toggle debug messages")
		print("  /doki smart - Toggle smart mode (considers class restrictions)")
		print("  /doki scan - Force universal scan for all items")
		print("  /doki universal - Same as scan")
		print("  /doki universalinit - Reinitialize universal scanning system")
		print("  /doki clear - Clear all overlays")
		print("  /doki status - Show addon status and statistics")
		print("  /doki frames - Debug found item frames")
		print("  /doki testmerchant - Test merchant frame detection")
		print("  /doki debug <itemID> - Debug transmog collection status for item")
		print("  /doki smart <itemID> - Debug smart transmog analysis for item")
		print("  /doki class <sourceID> <appearanceID> - Debug class restrictions")
		print("  /doki item <itemID> - Debug basic item info and tooltip")
		print("  /doki source <sourceID> - Debug restrictions for specific source")
	end
end
