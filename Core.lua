-- DOKI Core
local addonName, DOKI = ...
-- Initialize addon namespace
DOKI.currentItems = {}
DOKI.overlayPool = {}
DOKI.activeOverlays = {}
-- Main addon frame
local frame = CreateFrame("Frame", "DOKIFrame")
-- Check if any bags are currently open
local function AnyBagsOpen()
	-- Check combined bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		return true
	end

	-- Check individual container frames
	for i = 1, NUM_CONTAINER_FRAMES do
		local containerFrame = _G["ContainerFrame" .. i]
		if containerFrame and containerFrame:IsShown() then
			return true
		end
	end

	return false
end
-- Initialize saved variables
local function InitializeSavedVariables()
	if not DOKI_DB then
		DOKI_DB = {
			enabled = true,
			debugMode = true,
			smartMode = false, -- New: Smart detection mode for class restrictions
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
			print("|cffff69b4DOKI|r loaded. Type /doki for commands.")
			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
		-- Only scan if bags are actually open
		if DOKI.db and DOKI.db.enabled and AnyBagsOpen() then
			if DOKI.ScanCurrentItems then
				DOKI:ScanCurrentItems()
			end

			if DOKI.UpdateAllOverlays then
				DOKI:UpdateAllOverlays()
			end
		end
	elseif event == "MERCHANT_SHOW" then
		-- Small delay to let merchant frame populate
		C_Timer.After(0.1, function()
			if DOKI.ScanMerchantItems then
				DOKI:ScanMerchantItems()
			end

			if DOKI.UpdateMerchantOverlays then
				DOKI:UpdateMerchantOverlays()
			end
		end)
	elseif event == "MERCHANT_CLOSED" then
		if DOKI.ClearMerchantOverlays then
			DOKI:ClearMerchantOverlays()
		end
	end
end

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
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
		-- Rescan and update overlays when mode changes
		if DOKI.db.enabled then
			if DOKI.ScanCurrentItems then
				DOKI:ScanCurrentItems()
			end

			if DOKI.UpdateAllOverlays then
				DOKI:UpdateAllOverlays()
			end
		end
	elseif command == "scan" then
		print("|cffff69b4DOKI|r force scanning...")
		if DOKI.ScanCurrentItems then
			DOKI:ScanCurrentItems()
		end

		if DOKI.ScanMerchantItems then
			DOKI:ScanMerchantItems()
		end

		print("|cffff69b4DOKI|r updating overlays...")
		if DOKI.UpdateAllOverlays then
			DOKI:UpdateAllOverlays()
		end

		if DOKI.UpdateMerchantOverlays then
			DOKI:UpdateMerchantOverlays()
		end

		local itemCount = 0
		if DOKI.GetCurrentItemCount then
			itemCount = DOKI:GetCurrentItemCount()
		end

		local overlayCount = 0
		for _ in pairs(DOKI.activeOverlays) do
			overlayCount = overlayCount + 1
		end

		print(string.format("|cffff69b4DOKI|r scan complete. Found %d collectible items, created %d overlays", itemCount,
			overlayCount))
	elseif command == "test" then
		if DOKI.TestButtonFinding then
			DOKI:TestButtonFinding()
		else
			print("|cffff69b4DOKI|r Test function not available")
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
	else
		print("|cffff69b4DOKI|r commands:")
		print("  /doki toggle - Enable/disable addon")
		print("  /doki debug - Toggle debug messages")
		print("  /doki smart - Toggle smart mode (considers class restrictions)")
		print("  /doki scan - Force rescan items")
		print("  /doki test - Test button finding methods")
		print("  /doki debug <itemID> - Debug transmog collection status for item")
		print("  /doki smart <itemID> - Debug smart transmog analysis for item")
		print("  /doki class <sourceID> <appearanceID> - Debug class restrictions for specific source")
		print("  /doki item <itemID> - Debug basic item info and tooltip")
	end
end
