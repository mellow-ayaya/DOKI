-- DOKI Core - Universal Scanning Version
local addonName, DOKI = ...
-- Initialize addon namespace
DOKI.currentItems = {}
DOKI.overlayPool = {}
DOKI.activeOverlays = {}
DOKI.textureCache = {}
-- Scroll detection variables
DOKI.isScrolling = false
DOKI.scrollTimer = nil
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
			-- Clean up when disabled
			if DOKI.CleanupTimers then
				DOKI:CleanupTimers()
			end

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
	elseif command == "cleanup" then
		if DOKI.CleanupStaleOverlays then
			local removedCount = DOKI:CleanupStaleOverlays()
			print(string.format("|cffff69b4DOKI|r Cleaned up %d stale overlays", removedCount))
		else
			print("|cffff69b4DOKI|r Cleanup function not available")
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
	elseif command == "movementtest" then
		if not DOKI:IsElvUIBagVisible() then
			print("|cffff69b4DOKI|r ElvUI bags not visible - open them first")
			return
		end

		print("|cffff69b4DOKI|r Testing movement detection...")
		print("|cffff69b4DOKI|r Current bag snapshot:")
		local snapshot = DOKI:CreateBagItemSnapshot()
		local itemCount = 0
		for bagID, bag in pairs(snapshot) do
			for slotID, itemID in pairs(bag) do
				local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
				print(string.format("  Bag %d Slot %d: %s (ID: %d)", bagID, slotID, itemName, itemID))
				itemCount = itemCount + 1
			end
		end

		if itemCount == 0 then
			print("|cffff69b4DOKI|r No items found in bags")
		else
			print(string.format(
				"|cffff69b4DOKI|r Found %d items. Try moving an item and watch for movement detection messages.", itemCount))
		end
	elseif command == "perftest" then
		print("|cffff69b4DOKI|r Testing scan performance...")
		local startTime = GetTime()
		if DOKI.UniversalItemScan then
			local overlayCount = DOKI:UniversalItemScan()
			local duration = GetTime() - startTime
			print(string.format("|cffff69b4DOKI|r Scan completed: %d overlays in %.3fs", overlayCount, duration))
			if duration > 0.1 then
				print("|cffffff00DOKI|r Scan took longer than 100ms - consider optimizing")
			else
				print("|cff00ff00DOKI|r Scan performance is good (<100ms)")
			end
		else
			print("|cffff69b4DOKI|r Scan function not available")
		end
	elseif command == "performance" or command == "perf" then
		if DOKI.ShowPerformanceStats then
			DOKI:ShowPerformanceStats()
		else
			print("|cffff69b4DOKI|r Performance stats not available")
		end

		-- === MERCHANT DEBUGGING COMMANDS ===
	elseif command == "merchantdebug" then
		if not MerchantFrame or not MerchantFrame:IsVisible() then
			print("|cffff69b4DOKI|r Merchant frame not visible")
			return
		end

		print("|cffff69b4DOKI|r === MERCHANT DEBUG ===")
		print(string.format("Merchant frame visible: %s", MerchantFrame:IsVisible() and "yes" or "no"))
		-- Check navigation buttons
		if MerchantNextPageButton then
			print(string.format("Next page button exists: yes, visible: %s, enabled: %s",
				MerchantNextPageButton:IsVisible() and "yes" or "no",
				MerchantNextPageButton:IsEnabled() and "yes" or "no"))
		else
			print("Next page button exists: no")
		end

		if MerchantPrevPageButton then
			print(string.format("Previous page button exists: yes, visible: %s, enabled: %s",
				MerchantPrevPageButton:IsVisible() and "yes" or "no",
				MerchantPrevPageButton:IsEnabled() and "yes" or "no"))
		else
			print("Previous page button exists: no")
		end

		-- Check current merchant page info
		local numMerchantItems = GetMerchantNumItems()
		print(string.format("Number of merchant items: %d", numMerchantItems))
		-- Check hooks
		print(string.format("Merchant hooks installed: %s",
			DOKI.merchantHooksInstalled and "yes" or "no"))
		print("|cffff69b4DOKI|r === END MERCHANT DEBUG ===")
	elseif command == "scrolldebug" then
		if not MerchantFrame or not MerchantFrame:IsVisible() then
			print("|cffff69b4DOKI|r Merchant frame not visible")
			return
		end

		print("|cffff69b4DOKI|r === SCROLL DEBUG ===")
		print(string.format("MerchantFrame exists: %s", MerchantFrame and "yes" or "no"))
		if MerchantFrame then
			print(string.format("MerchantFrame.ScrollBox exists: %s",
				MerchantFrame.ScrollBox and "yes" or "no"))
			if MerchantFrame.ScrollBox then
				print(string.format("ScrollBox has RegisterCallback: %s",
					MerchantFrame.ScrollBox.RegisterCallback and "yes" or "no"))
				print(string.format("ScrollBox mouse wheel enabled: %s",
					MerchantFrame.ScrollBox:IsMouseWheelEnabled() and "yes" or "no"))
			end

			print(string.format("MerchantFrame mouse wheel enabled: %s",
				MerchantFrame:IsMouseWheelEnabled() and "yes" or "no"))
		end

		print("|cffff69b4DOKI|r === END SCROLL DEBUG ===")
	elseif command == "merchantevents" then
		if DOKI.merchantEventMonitor then
			-- Stop monitoring
			DOKI.merchantEventMonitor:UnregisterAllEvents()
			DOKI.merchantEventMonitor = nil
			print("|cffff69b4DOKI|r Stopped monitoring merchant events")
		else
			-- Start monitoring
			DOKI.merchantEventMonitor = CreateFrame("Frame")
			local events = { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "MERCHANT_FILTER_ITEM_UPDATE" }
			for _, event in ipairs(events) do
				DOKI.merchantEventMonitor:RegisterEvent(event)
			end

			DOKI.merchantEventMonitor:SetScript("OnEvent", function(self, event, ...)
				local args = { ... }
				local argStr = ""
				if #args > 0 then
					local argStrings = {}
					for i, arg in ipairs(args) do
						table.insert(argStrings, tostring(arg))
					end

					argStr = " (" .. table.concat(argStrings, ", ") .. ")"
				end

				print(string.format("|cffff69b4DOKI|r MERCHANT EVENT: %s%s", event, argStr))
			end)
			print("|cffff69b4DOKI|r Started monitoring merchant events - use command again to stop")
			print("|cffff69b4DOKI|r Now try changing merchant pages to see which events fire")
		end
	elseif command == "testcontent" then
		print("|cffff69b4DOKI|r Testing merchant content monitoring...")
		if not MerchantFrame or not MerchantFrame:IsVisible() then
			print("|cffff69b4DOKI|r Merchant frame not visible")
			return
		end

		-- Show current merchant items
		print("Current merchant items:")
		for i = 1, 10 do
			local itemLink = GetMerchantItemLink(i)
			if itemLink then
				local itemID = DOKI:GetItemID(itemLink)
				local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
				print(string.format("  %d: %s (ID: %d)", i, itemName, itemID))
			else
				print(string.format("  %d: empty", i))
			end
		end

		print("Try changing merchant pages now, then run this command again to see the difference.")
	elseif command == "fastmonitor" then
		if DOKI.StartFastMerchantContentMonitoring then
			DOKI:StartFastMerchantContentMonitoring()
			print("|cffff69b4DOKI|r Started fast merchant content monitoring (0.1s interval)")
			print("|cffff69b4DOKI|r Try changing pages now - should see immediate detection")
		else
			print("|cffff69b4DOKI|r Fast monitoring function not available")
		end
	elseif command == "testhooks" then
		print("|cffff69b4DOKI|r Testing button hook installation...")
		if MerchantNextPageButton then
			print(string.format("MerchantNextPageButton exists: yes, hasScript: %s",
				MerchantNextPageButton:HasScript("OnClick") and "yes" or "no"))
			-- Test manual hook
			MerchantNextPageButton:HookScript("OnClick", function()
				print("|cffff69b4DOKI|r TEST: Next page button clicked!")
			end)
			print("Test hook installed on next button")
		else
			print("MerchantNextPageButton does not exist")
		end

		if MerchantPrevPageButton then
			print(string.format("MerchantPrevPageButton exists: yes, hasScript: %s",
				MerchantPrevPageButton:HasScript("OnClick") and "yes" or "no"))
			-- Test manual hook
			MerchantPrevPageButton:HookScript("OnClick", function()
				print("|cffff69b4DOKI|r TEST: Previous page button clicked!")
			end)
			print("Test hook installed on previous button")
		else
			print("MerchantPrevPageButton does not exist")
		end
	elseif command == "merchantnothrotte" or command == "nothrottle" then
		-- Toggle a flag to bypass throttling for merchant events (for testing)
		DOKI.bypassMerchantThrottle = not (DOKI.bypassMerchantThrottle or false)
		local status = DOKI.bypassMerchantThrottle and "enabled" or "disabled"
		print(string.format("|cffff69b4DOKI|r Bypass merchant throttling: %s", status))
		print("|cffff69b4DOKI|r This is for testing only - may cause performance issues if left on")
		-- === TESTING AND DEBUG COMMANDS ===
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
	elseif command == "testelvui" then
		if DOKI.TestElvUIBags then
			DOKI:TestElvUIBags()
		else
			print("|cffff69b4DOKI|r ElvUI test function not available")
		end

		-- === ITEM DEBUG COMMANDS ===
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

		-- === HELP ===
	else
		print("|cffff69b4DOKI|r commands:")
		print("  /doki toggle - Enable/disable addon")
		print("  /doki debug - Toggle debug messages")
		print("  /doki smart - Toggle smart mode (considers class restrictions)")
		print("  /doki scan - Force universal scan for all items")
		print("  /doki universal - Same as scan")
		print("  /doki universalinit - Reinitialize universal scanning system")
		print("  /doki clear - Clear all overlays")
		print("  /doki cleanup - Clean up stale overlays manually")
		print("  /doki status - Show addon status and statistics")
		print("  /doki performance - Show performance statistics")
		print("  /doki perftest - Test scan performance")
		print("")
		print("Merchant debugging:")
		print("  /doki merchantdebug - Debug merchant page detection")
		print("  /doki scrolldebug - Debug ScrollBox detection capabilities")
		print("  /doki merchantevents - Toggle merchant event monitoring")
		print("  /doki testcontent - Show current merchant items for comparison")
		print("  /doki fastmonitor - Start fast merchant content monitoring")
		print("  /doki testhooks - Test merchant button hook installation")
		print("  /doki nothrottle - Toggle bypass of merchant event throttling")
		print("")
		print("Frame and item debugging:")
		print("  /doki frames - Debug found item frames")
		print("  /doki testmerchant - Test merchant frame detection")
		print("  /doki testelvui - Test ElvUI bag detection")
		print("  /doki elvuidebug - Debug ElvUI integration status")
		print("  /doki movementtest - Test item movement detection")
		print("  /doki debug <itemID> - Debug transmog collection status")
		print("  /doki smart <itemID> - Debug smart transmog analysis")
		print("  /doki class <sourceID> <appearanceID> - Debug class restrictions")
		print("  /doki item <itemID> - Debug basic item info")
		print("  /doki source <sourceID> - Debug restrictions for specific source")
	end
end
