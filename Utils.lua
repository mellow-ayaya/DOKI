-- DOKI Utils - Universal Scanning Version with Button Texture Integration
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
DOKI.foundFramesThisScan = {}
-- Scroll detection variables
DOKI.isScrolling = false
DOKI.scrollTimer = nil
-- ElvUI state tracking
DOKI.lastElvUIBagState = false
-- Simple hook tracking (no replacement of functions)
DOKI.hookFlags = DOKI.hookFlags or {}
-- ===== PERFORMANCE MONITORING =====
function DOKI:GetPerformanceStats()
	local stats = {
		scanInterval = 15, -- seconds
		lastScanDuration = self.lastScanDuration or 0,
		avgScanDuration = self.avgScanDuration or 0,
		totalScans = self.totalScans or 0,
		activeIndicators = 0,                      -- Changed from activeOverlays
		texturePoolSize = #(self.texturePool or {}), -- Changed from overlayPoolSize
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
	print("|cffff69b4DOKI|r === PERFORMANCE STATS ===")
	print(string.format("Scan interval: %ds", stats.scanInterval))
	print(string.format("Last scan duration: %.3fs", stats.lastScanDuration))
	print(string.format("Average scan duration: %.3fs", stats.avgScanDuration))
	print(string.format("Total scans performed: %d", stats.totalScans))
	print(string.format("Active indicators: %d", stats.activeIndicators)) -- Changed from overlays
	print(string.format("Texture pool size: %d", stats.texturePoolSize))
	print(string.format("Debug mode: %s", stats.debugMode and "ON (reduces performance)" or "OFF"))
	-- Performance assessment
	if stats.lastScanDuration > 0.1 then
		print("|cffff0000WARNING:|r Scan duration is high (>100ms)")
	elseif stats.lastScanDuration > 0.05 then
		print("|cffffff00NOTICE:|r Scan duration is moderate (>50ms)")
	else
		print("|cff00ff00GOOD:|r Scan performance is optimal (<50ms)")
	end

	print("|cffff69b4DOKI|r === END PERFORMANCE STATS ===")
end

function DOKI:TrackScanPerformance(duration)
	self.lastScanDuration = duration
	self.totalScans = (self.totalScans or 0) + 1
	-- Calculate rolling average (last 10 scans)
	if not self.scanDurations then
		self.scanDurations = {}
	end

	table.insert(self.scanDurations, duration)
	if #self.scanDurations > 10 then
		table.remove(self.scanDurations, 1)
	end

	local total = 0
	for _, d in ipairs(self.scanDurations) do
		total = total + d
	end

	self.avgScanDuration = total / #self.scanDurations
end

-- ===== MAIN UNIVERSAL SCANNER =====
function DOKI:UniversalItemScan()
	if not self.db or not self.db.enabled then return 0 end

	-- REMOVED: self:ClearUniversalOverlays() - this was causing flickering
	-- The button texture system now handles selective updates internally
	local indicatorCount = 0
	self.foundFramesThisScan = {}
	-- Performance optimization: Reset debug counters only if debug is enabled
	if self.db.debugMode then
		self.filterDebugCount = 0
		self.extractDebugCount = 0
	end

	local startTime = GetTime()
	-- Direct merchant scanning (if merchant is open)
	if MerchantFrame and MerchantFrame:IsVisible() then
		indicatorCount = indicatorCount + self:ScanMerchantFramesDirectly()
	end

	-- Direct bag scanning (ElvUI and Blizzard)
	indicatorCount = indicatorCount + self:ScanBagFramesDirectly()
	local scanDuration = GetTime() - startTime
	-- Track performance metrics
	self:TrackScanPerformance(scanDuration)
	-- Performance optimization: Only do debug output if debug mode is enabled
	if self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Optimized scan: %d indicators in %.3fs, %d items found",
			indicatorCount, scanDuration, #self.foundFramesThisScan))
	end

	return indicatorCount
end

function DOKI:ScanMerchantFramesDirectly()
	local indicatorCount = 0
	local debugMode = self.db.debugMode
	if debugMode then
		print("|cffff69b4DOKI|r Scanning merchant frames with button textures...")
	end

	-- Track which merchant buttons we find items on
	local activeMerchantButtons = {}
	for i = 1, 10 do
		local buttonName = "MerchantItem" .. i .. "ItemButton"
		local button = _G[buttonName]
		if button and button:IsVisible() then
			local itemData = self:ExtractItemFromAnyFrameOptimized(button, buttonName)
			if itemData then
				activeMerchantButtons[button] = true
				indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
				-- Store for debugging only if debug is enabled
				if debugMode then
					table.insert(self.foundFramesThisScan, {
						frame = button,
						frameName = buttonName,
						itemData = itemData,
					})
					-- Limit debug output to reduce overhead
					if indicatorCount <= 3 then
						local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
						print(string.format("|cffff69b4DOKI|r Direct merchant: %s (ID: %d)",
							itemName, itemData.itemID))
					end
				end
			else
				-- No item on this button, remove any indicator
				self:RemoveButtonIndicator(button)
			end
		end
	end

	-- Clean up indicators on merchant buttons that are no longer visible or have no items
	for button, textureData in pairs(self.buttonTextures or {}) do
		if textureData.isActive then
			local buttonName = ""
			local nameSuccess, name = pcall(button.GetName, button)
			if nameSuccess and name and name:match("MerchantItem%d+ItemButton") then
				if not activeMerchantButtons[button] then
					-- This merchant button no longer has an item or isn't visible
					self:RemoveButtonIndicator(button)
				end
			end
		end
	end

	return indicatorCount
end

function DOKI:ScanBagFramesDirectly()
	local indicatorCount = 0
	local debugMode = self.db.debugMode
	local activeBagButtons = {}
	-- Scan ElvUI bags if ElvUI is active
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				if debugMode then
					print("|cffff69b4DOKI|r Scanning ElvUI bags with button textures...")
				end

				local elvUIItemsFound = 0
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							-- Performance optimization: Check if slot has item before trying button patterns
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID then
								-- Try multiple ElvUI button naming patterns
								local possibleNames = {
									string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
								}
								for _, elvUIButtonName in ipairs(possibleNames) do
									local elvUIButton = _G[elvUIButtonName]
									if elvUIButton and elvUIButton:IsVisible() then
										local itemData = self:ExtractItemFromAnyFrameOptimized(elvUIButton, elvUIButtonName)
										if itemData then
											activeBagButtons[elvUIButton] = true
											indicatorCount = indicatorCount + self:CreateUniversalIndicator(elvUIButton, itemData)
											elvUIItemsFound = elvUIItemsFound + 1
											if debugMode then
												table.insert(self.foundFramesThisScan, {
													frame = elvUIButton,
													frameName = elvUIButtonName,
													itemData = itemData,
												})
											end
										end

										break -- Found working pattern, skip others
									end
								end
							else
								-- No item in this slot, check if there's an indicator to remove
								local possibleNames = {
									string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
								}
								for _, elvUIButtonName in ipairs(possibleNames) do
									local elvUIButton = _G[elvUIButtonName]
									if elvUIButton then
										self:RemoveButtonIndicator(elvUIButton)
										break
									end
								end
							end
						end
					end
				end

				if debugMode and elvUIItemsFound > 0 then
					print(string.format("|cffff69b4DOKI|r ElvUI found %d items", elvUIItemsFound))
				elseif debugMode then
					print("|cffff69b4DOKI|r ElvUI bags visible but no items found")
				end
			else
				if debugMode then
					print("|cffff69b4DOKI|r ElvUI detected but BagFrame not shown")
				end
			end
		end
	elseif debugMode and ElvUI then
		print("|cffff69b4DOKI|r ElvUI detected but bags not visible")
	end

	-- Scan Blizzard bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if debugMode then
			print("|cffff69b4DOKI|r Scanning Blizzard bags with button textures...")
		end

		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					local frameName = itemButton:GetName() or "CombinedBagItem"
					local itemData = self:ExtractItemFromAnyFrameOptimized(itemButton, frameName)
					if itemData then
						activeBagButtons[itemButton] = true
						indicatorCount = indicatorCount + self:CreateUniversalIndicator(itemButton, itemData)
						if debugMode then
							table.insert(self.foundFramesThisScan, {
								frame = itemButton,
								frameName = frameName,
								itemData = itemData,
							})
						end
					end
				end
			end
		end
	end

	-- Clean up indicators on bag buttons that no longer have items (only if bags are visible)
	if (ElvUI and self:IsElvUIBagVisible()) or (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		for button, textureData in pairs(self.buttonTextures or {}) do
			if textureData.isActive then
				local buttonName = ""
				local nameSuccess, name = pcall(button.GetName, button)
				if nameSuccess and name then
					-- Check if this is a bag button that's no longer active
					local isBagButton = name:match("ElvUI_ContainerFrame") or name:match("CombinedBag")
					if isBagButton and not activeBagButtons[button] then
						-- Check if button is still visible and valid
						local success, isVisible = pcall(button.IsVisible, button)
						if not success or not isVisible then
							self:RemoveButtonIndicator(button)
						end
					end
				end
			end
		end
	end

	return indicatorCount
end

-- ===== CONTENT VALIDATION AND CLEANUP =====
function DOKI:ValidateFrameContent(frame, expectedItemID)
	if not frame or not expectedItemID then return false end

	-- Check if frame is still visible
	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return false end

	-- Try to extract current item from frame
	local currentItemData = self:ExtractItemFromAnyFrameOptimized(frame, frame:GetName())
	if not currentItemData or not currentItemData.itemID then return false end

	-- Check if it's still the same item
	return currentItemData.itemID == expectedItemID
end

-- Updated to use button texture system
function DOKI:CreateUniversalIndicator(frame, itemData)
	if itemData.isCollected then
		-- If item is collected, remove any existing indicator
		if self.RemoveButtonIndicator then
			self:RemoveButtonIndicator(frame)
		end

		return 0
	end

	-- Enhanced frame validation
	if not frame or type(frame) ~= "table" then return 0 end

	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Check if indicator already exists and is correct
	if self.buttonTextures and self.buttonTextures[frame] then
		local existingTexture = self.buttonTextures[frame]
		if existingTexture and existingTexture.isActive then
			-- Indicator already exists and is active, avoid recreation
			return 0
		end
	end

	-- Add button indicator using new system
	if self.AddButtonIndicator then
		local success = self:AddButtonIndicator(frame, itemData)
		return success and 1 or 0
	end

	-- Fallback to legacy system if button texture system not available
	return 0
end

-- Smart clear function that only clears when actually needed
function DOKI:SmartClearForEvent(eventName)
	-- Events that should trigger full clears (major changes)
	local majorEvents = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		-- Removed ITEM_UNLOCKED from here - handle it specially
	}
	-- Events that should only trigger cleanup (minor changes)
	local minorEvents = {
		"BAG_UPDATE_COOLDOWN",
		"BAG_SLOT_FLAGS_UPDATED",
		"INVENTORY_SEARCH_UPDATE",
		"ITEM_LOCKED", -- Just picking up an item shouldn't clear indicators
	}
	-- Events to ignore completely (too noisy)
	local ignoredEvents = {
		"BAG_UPDATE", -- Too frequent, handled by BAG_UPDATE_DELAYED
	}
	-- Check if event should be ignored
	for _, ignoredEvent in ipairs(ignoredEvents) do
		if eventName == ignoredEvent then
			return 0
		end
	end

	for _, majorEvent in ipairs(majorEvents) do
		if eventName == majorEvent then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Major event %s: clearing indicators", eventName))
			end

			if self.ClearAllButtonIndicators then
				return self:ClearAllButtonIndicators()
			end

			return 0
		end
	end

	for _, minorEvent in ipairs(minorEvents) do
		if eventName == minorEvent then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Minor event %s: cleanup only", eventName))
			end

			if self.CleanupButtonTextures then
				return self:CleanupButtonTextures()
			end

			return 0
		end
	end

	-- Special handling for ITEM_UNLOCKED - only clear if item actually moved
	if eventName == "ITEM_UNLOCKED" then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Item unlocked - checking for actual movement"))
		end

		-- Let the scanning system handle this intelligently
		if self.CleanupButtonTextures then
			return self:CleanupButtonTextures()
		end

		return 0
	end

	-- Default: cleanup only for unknown events
	if self.CleanupButtonTextures then
		return self:CleanupButtonTextures()
	end

	return 0
end

-- Legacy compatibility functions - updated to use button texture system
function DOKI:ClearUniversalOverlays()
	-- Instead of clearing all indicators, just clean up invalid ones
	if self.CleanupButtonTextures then
		return self:CleanupButtonTextures()
	end

	return 0
end

function DOKI:ClearAllOverlays()
	-- Only clear all when explicitly requested (like /doki clear command)
	if self.ClearAllButtonIndicators then
		return self:ClearAllButtonIndicators()
	end

	return 0
end

-- ===== MODERN MERCHANT SCROLL DETECTION =====
function DOKI:HookMerchantNavigation()
	-- Prevent multiple hooks
	if self.merchantHooksInstalled then return end

	-- Capture DOKI reference for use in hook closures
	local doki = self
	-- === MODERN SCROLLBOX DETECTION (The War Within) ===
	-- Primary method: Hook ScrollBox mouse wheel events
	if MerchantFrame and MerchantFrame.ScrollBox then
		MerchantFrame.ScrollBox:EnableMouseWheel(true)
		MerchantFrame.ScrollBox:HookScript("OnMouseWheel", function(self, delta)
			if doki.db and doki.db.enabled then
				local direction = delta > 0 and "up" or "down"
				if doki.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Merchant ScrollBox wheel: %s", direction))
				end

				-- Mark as scrolling and use smart clearing
				doki.isScrolling = true
				doki:SmartClearForEvent("MERCHANT_SCROLL")
				-- Reset scroll end timer
				if doki.scrollTimer then
					doki.scrollTimer:Cancel()
				end

				doki.scrollTimer = C_Timer.NewTimer(0.3, function()
					doki.isScrolling = false
					if doki.db.debugMode then
						print("|cffff69b4DOKI|r Scrolling ended")
					end
				end)
				-- Immediate rescan after short delay
				C_Timer.After(0.1, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
		-- Register ScrollBox callbacks if available (modern)
		if MerchantFrame.ScrollBox.RegisterCallback then
			MerchantFrame.ScrollBox:RegisterCallback("OnScroll", function(self, scrollPercent)
				if doki.db and doki.db.enabled then
					if doki.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ScrollBox position: %.2f", scrollPercent))
					end

					-- Trigger rescan on scroll position changes
					C_Timer.After(0.1, function()
						if doki.db and doki.db.enabled then
							doki:UniversalItemScan()
						end
					end)
				end
			end)
		end
	end

	-- === FALLBACK: Main MerchantFrame scroll detection ===
	if MerchantFrame then
		MerchantFrame:EnableMouseWheel(true)
		MerchantFrame:HookScript("OnMouseWheel", function(self, delta)
			if doki.db and doki.db.enabled then
				local direction = delta > 0 and "up" or "down"
				if doki.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Merchant frame wheel: %s", direction))
				end

				doki:SmartClearForEvent("MERCHANT_SCROLL")
				C_Timer.After(0.1, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
	end

	-- === LEGACY: Button click detection ===
	if MerchantNextPageButton then
		MerchantNextPageButton:HookScript("OnClick", function()
			if doki.db and doki.db.enabled then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r Merchant next page clicked")
				end

				doki:SmartClearForEvent("MERCHANT_SHOW")
				C_Timer.After(0.2, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
	end

	if MerchantPrevPageButton then
		MerchantPrevPageButton:HookScript("OnClick", function()
			if doki.db and doki.db.enabled then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r Merchant previous page clicked")
				end

				doki:SmartClearForEvent("MERCHANT_SHOW")
				C_Timer.After(0.2, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
	end

	self.merchantHooksInstalled = true
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Merchant navigation and scroll hooks installed")
		if MerchantFrame and MerchantFrame.ScrollBox then
			print("|cffff69b4DOKI|r Modern ScrollBox detection enabled")
		else
			print("|cffff69b4DOKI|r Using legacy scroll detection")
		end
	end
end

function DOKI:StartMerchantContentMonitoring()
	if self.merchantMonitorTimer then
		self.merchantMonitorTimer:Cancel()
	end

	self.lastMerchantItems = {}
	-- Capture DOKI reference for closure
	local doki = self
	-- Check merchant content every 0.5 seconds when merchant is open
	self.merchantMonitorTimer = C_Timer.NewTicker(0.5, function()
		if not (doki.db and doki.db.enabled) then return end

		if MerchantFrame and MerchantFrame:IsVisible() then
			local currentItems = {}
			local hasChanged = false
			-- Get current merchant items
			for i = 1, 10 do
				local itemLink = GetMerchantItemLink(i)
				if itemLink then
					local itemID = doki:GetItemID(itemLink)
					if itemID then
						currentItems[i] = itemID
					end
				end
			end

			-- Compare with last known items
			for i = 1, 10 do
				if currentItems[i] ~= doki.lastMerchantItems[i] then
					hasChanged = true
					break
				end
			end

			-- If content changed, use smart clearing and rescan
			if hasChanged then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r Merchant content changed - rescanning")
				end

				doki:SmartClearForEvent("MERCHANT_UPDATE")
				C_Timer.After(0.1, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
				doki.lastMerchantItems = currentItems
			end
		else
			-- Merchant closed, stop monitoring
			if doki.merchantMonitorTimer then
				doki.merchantMonitorTimer:Cancel()
				doki.merchantMonitorTimer = nil
			end
		end
	end)
end

function DOKI:StartFastMerchantContentMonitoring()
	if self.fastMerchantMonitorTimer then
		self.fastMerchantMonitorTimer:Cancel()
	end

	self.lastMerchantItems = {}
	-- Capture DOKI reference for closure
	local doki = self
	-- Check merchant content every 0.1 seconds when merchant is open (very fast for testing)
	self.fastMerchantMonitorTimer = C_Timer.NewTicker(0.1, function()
		if not (doki.db and doki.db.enabled) then return end

		if MerchantFrame and MerchantFrame:IsVisible() then
			local currentItems = {}
			local hasChanged = false
			-- Get current merchant items
			for i = 1, 10 do
				local itemLink = GetMerchantItemLink(i)
				if itemLink then
					local itemID = doki:GetItemID(itemLink)
					if itemID then
						currentItems[i] = itemID
					end
				end
			end

			-- Compare with last known items
			for i = 1, 10 do
				if currentItems[i] ~= doki.lastMerchantItems[i] then
					hasChanged = true
					break
				end
			end

			-- If content changed, use smart clearing and rescan
			if hasChanged then
				print("|cffff69b4DOKI|r FAST MONITOR: Merchant content changed - rescanning")
				doki:SmartClearForEvent("MERCHANT_UPDATE")
				C_Timer.After(0.1, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
				doki.lastMerchantItems = currentItems
			end
		else
			-- Merchant closed, stop monitoring
			if doki.fastMerchantMonitorTimer then
				doki.fastMerchantMonitorTimer:Cancel()
				doki.fastMerchantMonitorTimer = nil
				print("|cffff69b4DOKI|r Fast merchant monitoring stopped")
			end
		end
	end)
end

function DOKI:InitializeMerchantHooks()
	-- Hook merchant show to install navigation hooks AND start content monitoring
	if not self.merchantShowHooked then
		-- Capture DOKI reference for closure
		local doki = self
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("MERCHANT_SHOW")
		frame:SetScript("OnEvent", function()
			-- Small delay to ensure merchant frame is fully loaded
			C_Timer.After(0.1, function()
				doki:HookMerchantNavigation()
				doki:StartMerchantContentMonitoring()
			end)
		end)
		self.merchantShowHooked = true
	end
end

-- ===== ELVUI-SPECIFIC HOOKS AND EVENTS =====
-- ===== OPTIMIZED ELVUI INTEGRATION =====
function DOKI:SetupElvUIHooks()
	if not ElvUI then return end

	-- Prevent duplicate setup
	if self.elvUIHooksInstalled then return end

	local E = ElvUI[1]
	if not E then return end

	local B = E:GetModule("Bags", true)
	if not B then return end

	local doki = self
	-- FAST monitoring for immediate detection (every 0.1s instead of 0.5s)
	if not self.elvUIMonitorTimer then
		self.elvUIMonitorTimer = C_Timer.NewTicker(0.1, function()
			if not (doki.db and doki.db.enabled) then return end

			-- Check if ElvUI bags just became visible
			local currentlyVisible = doki:IsElvUIBagVisible()
			if currentlyVisible and not doki.lastElvUIBagState then
				-- Bags just opened - scan immediately with minimal delay
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI bags opened (fast detection)")
				end

				-- Much shorter delay for faster response
				C_Timer.After(0.05, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end

			doki.lastElvUIBagState = currentlyVisible
		end)
	end

	-- ADDITIONAL: Hook bag frame show events directly (safer than global functions)
	if B.BagFrame and not self.bagFrameHooked then
		B.BagFrame:HookScript("OnShow", function()
			if doki.db and doki.db.enabled then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI BagFrame OnShow triggered")
				end

				-- Immediate scan when bag frame shows
				C_Timer.After(0.02, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
		self.bagFrameHooked = true
	end

	-- Hook bank frame show events too
	if B.BankFrame and not self.bankFrameHooked then
		B.BankFrame:HookScript("OnShow", function()
			if doki.db and doki.db.enabled then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI BankFrame OnShow triggered")
				end

				C_Timer.After(0.02, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end
		end)
		self.bankFrameHooked = true
	end

	-- CRITICAL: Hook ElvUI's Layout function for item movement detection
	if B.Layout and not self.layoutHooked then
		local originalLayout = B.Layout
		B.Layout = function(self, ...)
			local result = originalLayout(self, ...)
			-- Trigger rescan after ElvUI layout changes
			if doki.db and doki.db.enabled and doki:IsElvUIBagVisible() then
				if doki.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI Layout triggered - rescanning for item movement")
				end

				-- Use smart clearing instead of aggressive clearing
				doki:SmartClearForEvent("ELVUI_LAYOUT")
				-- Short delay to let ElvUI finish its layout
				C_Timer.After(0.05, function()
					if doki.db and doki.db.enabled then
						doki:UniversalItemScan()
					end
				end)
			end

			return result
		end
		self.layoutHooked = true
	end

	-- Add faster monitoring when bags are open to catch item movements
	if not self.elvUIItemMovementTimer then
		self.elvUIItemMovementTimer = C_Timer.NewTicker(0.2, function()
			if not (doki.db and doki.db.enabled) then return end

			-- Only monitor when bags are visible
			if doki:IsElvUIBagVisible() then
				-- Create a snapshot of current item positions
				local currentSnapshot = doki:CreateBagItemSnapshot()
				-- Compare with last snapshot
				if doki.lastBagSnapshot and not doki:CompareBagSnapshots(doki.lastBagSnapshot, currentSnapshot) then
					if doki.db.debugMode then
						print("|cffff69b4DOKI|r Item movement detected - updating indicators")
					end

					-- Items moved - use smart clearing
					doki:SmartClearForEvent("ITEM_MOVEMENT")
					C_Timer.After(0.05, function()
						if doki.db and doki.db.enabled then
							doki:UniversalItemScan()
						end
					end)
				end

				doki.lastBagSnapshot = currentSnapshot
			else
				-- Clear snapshot when bags close
				doki.lastBagSnapshot = nil
			end
		end)
	end

	self.elvUIHooksInstalled = true
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ElvUI fast monitoring + layout hooks + movement detection enabled")
	end
end

-- Create a snapshot of current bag item positions
function DOKI:CreateBagItemSnapshot()
	local snapshot = {}
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			snapshot[bagID] = {}
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					snapshot[bagID][slotID] = itemInfo.itemID
				end
			end
		end
	end

	return snapshot
end

-- Compare two bag snapshots to detect item movement
function DOKI:CompareBagSnapshots(snapshot1, snapshot2)
	if not snapshot1 or not snapshot2 then return false end

	-- Check all bag slots
	for bagID = 0, NUM_BAG_SLOTS do
		local bag1 = snapshot1[bagID] or {}
		local bag2 = snapshot2[bagID] or {}
		-- Check each slot
		local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
		for slotID = 1, numSlots do
			if bag1[slotID] ~= bag2[slotID] then
				return false -- Items have moved
			end
		end
	end

	return true -- No movement detected
end

-- Enhanced ElvUI bag visibility check
function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or (B.BankFrame and B.BankFrame:IsShown())
end

function DOKI:InitializeUniversalScanning()
	-- Clear any existing timer
	if self.universalScanTimer then
		self.universalScanTimer:Cancel()
	end

	-- Performance optimization: Increased scan interval from 5s to 15s
	self.universalScanTimer = C_Timer.NewTicker(15, function()
		if self.db and self.db.enabled then
			self:UniversalItemScan()
		end
	end)
	-- Set up throttled event-driven scanning with smart clearing
	self:SetupThrottledUniversalEvents()
	-- Initialize merchant navigation hooks
	self:InitializeMerchantHooks()
	-- Initialize ElvUI-specific hooks
	self:SetupElvUIHooks()
	-- Initial scan
	self:UniversalItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Optimized universal scanning initialized (15s interval)")
	end
end

function DOKI:SetupThrottledUniversalEvents()
	if self.universalEventFrame then return end

	self.universalEventFrame = CreateFrame("Frame")
	-- Event list with enhanced item movement detection
	local events = {
		"BAG_UPDATE_DELAYED",        -- Bag contents changed
		"BAG_UPDATE_COOLDOWN",       -- ElvUI-compatible bag cooldown updates
		"MERCHANT_SHOW",             -- Merchant opened
		"MERCHANT_UPDATE",           -- Merchant contents updated (should fire on page changes)
		"MERCHANT_CLOSED",           -- Merchant closed
		"MERCHANT_FILTER_ITEM_UPDATE", -- When specific merchant items update
		"ADDON_LOADED",              -- Other addons might affect UI
		"BAG_CONTAINER_UPDATE",      -- Alternative bag update event
		"ITEM_LOCKED",               -- Item being moved (key for movement detection)
		"ITEM_UNLOCKED",             -- Item move completed (key for movement detection)
		"BANKFRAME_OPENED",          -- Bank events
		"BANKFRAME_CLOSED",
		"BAG_SLOT_FLAGS_UPDATED",    -- Additional bag update events
		"INVENTORY_SEARCH_UPDATE",   -- Search/filter changes
	}
	for _, event in ipairs(events) do
		self.universalEventFrame:RegisterEvent(event)
	end

	-- Performance optimization: Different throttling for different event types
	local lastEventTime = 0
	local lastMerchantEventTime = 0
	local generalThrottleDelay = 0.5 -- General events
	local merchantThrottleDelay = 0.2 -- Faster for merchant events
	self.universalEventFrame:SetScript("OnEvent", function(self, event, ...)
		local currentTime = GetTime()
		-- Special handling for merchant closed - use smart clearing
		if event == "MERCHANT_CLOSED" then
			if DOKI.db and DOKI.db.enabled then
				DOKI:SmartClearForEvent(event)
			end

			return
		end

		-- Handle MERCHANT_FILTER_ITEM_UPDATE with its itemID parameter
		if event == "MERCHANT_FILTER_ITEM_UPDATE" then
			local itemID = ...
			if DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Merchant filter item update: %s", tostring(itemID)))
			end
		end

		-- Enhanced handling for item movement events
		if event == "ITEM_LOCKED" or event == "ITEM_UNLOCKED" then
			-- Only process if bags are visible to avoid unnecessary scans
			if DOKI:IsElvUIBagVisible() or (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
				if DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Item movement event: %s", event))
				end

				-- For ITEM_LOCKED (picking up), don't clear immediately - just note it
				if event == "ITEM_LOCKED" then
					-- Don't clear indicators when just picking up an item
					-- The item is still in the same slot, just "locked"
					return
				end

				-- For ITEM_UNLOCKED (dropping), use smart clearing and delayed scan
				if event == "ITEM_UNLOCKED" then
					-- Use smart clearing
					DOKI:SmartClearForEvent(event)
					-- Longer delay to let the item settle in its new location
					C_Timer.After(0.15, function()
						if DOKI.db and DOKI.db.enabled then
							DOKI:UniversalItemScan()
						end
					end)
					return
				end
			end
		end

		-- Enhanced MERCHANT_UPDATE handling for scroll detection
		if event == "MERCHANT_UPDATE" then
			-- Detect page changes during scrolling (from research-based approach)
			if DOKI.isScrolling then
				if DOKI.db and DOKI.db.debugMode then
					print("|cffff69b4DOKI|r MERCHANT_UPDATE during scroll - processing")
				end

				-- Process immediately when scrolling, skip throttling
				C_Timer.After(0.1, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:UniversalItemScan()
					end
				end)
				return
			end
		end

		-- Determine if this is a merchant-related event
		local isMerchantEvent = event:match("MERCHANT") ~= nil
		local throttleDelay = isMerchantEvent and merchantThrottleDelay or generalThrottleDelay
		local lastRelevantTime = isMerchantEvent and lastMerchantEventTime or lastEventTime
		-- Check for throttle bypass (for testing)
		local shouldBypassThrottle = DOKI.bypassMerchantThrottle and isMerchantEvent
		-- Throttle rapid events (unless bypassing or handling item movement)
		if not shouldBypassThrottle and currentTime - lastRelevantTime < throttleDelay then
			return -- Skip this event, too soon after last one
		end

		-- Update appropriate timestamp
		if isMerchantEvent then
			lastMerchantEventTime = currentTime
		else
			lastEventTime = currentTime
		end

		-- Debug output to see which events are firing
		if DOKI.db and DOKI.db.debugMode then
			local bypassNote = shouldBypassThrottle and " (throttle bypassed)" or ""
			local scrollNote = DOKI.isScrolling and " (during scroll)" or ""
			print(string.format("|cffff69b4DOKI|r Event triggered: %s%s%s", event, bypassNote, scrollNote))
		end

		-- Use smart clearing instead of aggressive clearing
		DOKI:SmartClearForEvent(event)
		-- Shorter delay for merchant events
		local scanDelay = isMerchantEvent and 0.1 or 0.2
		C_Timer.After(scanDelay, function()
			if DOKI.db and DOKI.db.enabled then
				DOKI:UniversalItemScan()
			end
		end)
	end)
end

function DOKI:ForceUniversalScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Forcing universal scan...")
	end

	-- Use smart clearing instead of clearing all
	self:SmartClearForEvent("FORCE_SCAN")
	-- Also clean up any truly stale indicators
	if self.CleanupButtonTextures then
		self:CleanupButtonTextures()
	end

	return self:UniversalItemScan()
end

-- ===== ITEM EXTRACTION AND PROCESSING =====
function DOKI:ExtractItemFromAnyFrameOptimized(frame, frameName)
	-- Quick validation
	if not frame or type(frame) ~= "table" then return nil end

	-- Safe IsVisible check
	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return nil end

	-- Use provided frameName to avoid additional GetName calls
	if not frameName then
		local success, name = pcall(frame.GetName, frame)
		if success and name then
			frameName = name
		else
			frameName = ""
		end
	end

	-- Quick filter check without extensive debugging
	if frameName ~= "" and not self:IsLikelyItemFrameOptimized(frameName) then
		return nil
	end

	local itemID, itemLink
	-- Method 1: Direct item methods
	if frame.GetItemID then
		local success, id = pcall(frame.GetItemID, frame)
		if success and id then itemID = id end
	end

	if not itemID and frame.GetItem then
		local success, item = pcall(frame.GetItem, frame)
		if success and item then
			if type(item) == "number" then
				itemID = item
			elseif type(item) == "string" then
				itemLink = item
				itemID = self:GetItemID(item)
			end
		end
	end

	-- Method 2: Frame properties
	if not itemID then
		itemID = frame.itemID or frame.id
	end

	if not itemLink then
		itemLink = frame.itemLink or frame.link
		if itemLink then itemID = itemID or self:GetItemID(itemLink) end
	end

	-- Method 3: Specific extraction methods
	if not itemID then
		if frameName:match("ContainerFrame") or frame.GetBagID then
			itemID = self:ExtractBagItemID(frame)
		elseif frameName:match("MerchantItem") then
			itemID = self:ExtractMerchantItemID(frame, frameName)
		elseif frameName:match("ActionButton") then
			itemID = self:ExtractActionItemID(frame)
		end
	end

	-- Quick validation
	if not itemID or not self:IsCollectibleItem(itemID) then return nil end

	local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
	return {
		itemID = itemID,
		itemLink = itemLink,
		isCollected = isCollected,
		showYellowD = showYellowD,
		frameType = self:DetermineFrameType(frame, frameName),
	}
end

function DOKI:IsLikelyItemFrameOptimized(frameName)
	if not frameName or frameName == "" then return false end

	-- Quick exclusions
	if frameName:match("^table:") then return false end

	-- Quick quest exclusions
	local questExclusions = {
		"QuestLog", "QuestFrame", "QuestObjective", "ObjectiveTracker", "AllObjectives",
	}
	for _, exclusion in ipairs(questExclusions) do
		if frameName:find(exclusion) then return false end
	end

	-- Streamlined inclusion patterns
	return frameName:match("ContainerFrame.*Item") or
			frameName:match("MerchantItem.*Button") or
			frameName:match(".*ItemButton$") or
			frameName:match("ActionButton%d+$") or
			frameName:match("ElvUI_ContainerFrame") or
			frameName:match("ElvUI.*Hash$") or
			frameName:match(".*LootButton") or
			frameName:match("BankFrameItem")
end

function DOKI:ExtractBagItemID(frame)
	if frame.GetBagID and frame.GetID then
		local success1, bagID = pcall(frame.GetBagID, frame)
		local success2, slotID = pcall(frame.GetID, frame)
		if success1 and success2 and bagID and slotID then
			local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			return itemInfo and itemInfo.itemID
		end
	end

	-- Alternative: Check for bagID/slotID properties
	if frame.bagID and frame.slotID then
		local itemInfo = C_Container.GetContainerItemInfo(frame.bagID, frame.slotID)
		return itemInfo and itemInfo.itemID
	end

	return nil
end

function DOKI:ExtractMerchantItemID(frame, frameName)
	-- Only process actual merchant item buttons, not parent frames
	local merchantIndex = frameName:match("MerchantItem(%d+)ItemButton")
	if merchantIndex then
		local itemLink = GetMerchantItemLink(tonumber(merchantIndex))
		return itemLink and self:GetItemID(itemLink)
	end

	-- Skip parent merchant frames (MerchantItem1, MerchantItem2, etc.)
	if frameName:match("^MerchantItem%d+$") then
		return nil
	end

	if frame.merchantIndex then
		local itemLink = GetMerchantItemLink(frame.merchantIndex)
		return itemLink and self:GetItemID(itemLink)
	end

	return nil
end

function DOKI:ExtractActionItemID(frame)
	if not frame.action then return nil end

	local actionType, itemID = GetActionInfo(frame.action)
	if actionType == "item" then
		return itemID
	end

	return nil
end

function DOKI:DetermineFrameType(frame, frameName)
	if frameName:match("ContainerFrame") or frameName:match("Bag.*Item") then
		return "bag"
	elseif frameName:match("MerchantItem.*ItemButton") then
		return "merchant"
	elseif frameName:match("Quest.*Button") or frameName:match("QuestLog.*Button") then
		return "quest"
	elseif frameName:match("Adventure") or frameName:match("Encounter") or frameName:match("Journal") then
		return "journal"
	elseif frameName:match("ActionButton") then
		return "actionbar"
	elseif frameName:match("Bank.*Item") then
		return "bank"
	elseif frameName:match("Guild.*Item") then
		return "guild"
	elseif frameName:match("Loot.*Button") then
		return "loot"
	elseif frameName:match("Trade.*Item") then
		return "trade"
	elseif frameName:match("Mail.*Item") then
		return "mail"
	elseif frameName:match("Auction.*Item") then
		return "auction"
	else
		return "unknown"
	end
end

function DOKI:GetItemID(itemLink)
	if not itemLink then return nil end

	if type(itemLink) == "number" then
		return itemLink
	end

	if type(itemLink) == "string" then
		local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
		return itemID
	end

	return nil
end

function DOKI:IsCollectibleItem(itemID)
	if not itemID then return false end

	-- Use C_Item.GetItemInfoInstant for immediate info
	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false
	end

	-- Mount items (class 15, subclass 5)
	if classID == 15 and subClassID == 5 then
		return true
	end

	-- Pet items (class 15, subclass 2)
	if classID == 15 and subClassID == 2 then
		return true
	end

	-- Toy items - check with toy API
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		return true
	end

	-- Transmog items (weapons class 2, armor class 4)
	if classID == 2 or classID == 4 then
		-- Filter out non-transmog equipment slots
		if itemEquipLoc then
			local nonTransmogSlots = {
				"INVTYPE_NECK", -- Necklaces
				"INVTYPE_FINGER", -- Rings
				"INVTYPE_TRINKET", -- Trinkets
				"INVTYPE_HOLDABLE", -- Off-hand items (some)
				"INVTYPE_BAG",  -- Bags
				"INVTYPE_QUIVER", -- Quivers
			}
			for _, slot in ipairs(nonTransmogSlots) do
				if itemEquipLoc == slot then
					return false
				end
			end

			-- If it's an equipment slot that can have transmog, it's collectible
			return true
		end
	end

	return false
end

-- ===== COLLECTION STATUS FUNCTIONS =====
function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID then return false, false end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false, false
	end

	-- Check mounts
	if classID == 15 and subClassID == 5 then
		return self:IsMountCollected(itemID), false
	end

	-- Check pets
	if classID == 15 and subClassID == 2 then
		return self:IsPetCollected(itemID), false
	end

	-- Check toys
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		return PlayerHasToy(itemID), false
	end

	-- Check transmog - use appropriate method based on smart mode
	if classID == 2 or classID == 4 then
		if self.db and self.db.smartMode then
			return self:IsTransmogCollectedSmart(itemID, itemLink)
		else
			return self:IsTransmogCollected(itemID, itemLink)
		end
	end

	return false, false
end

function DOKI:IsMountCollected(itemID)
	if not itemID or not C_MountJournal then return false end

	-- Get the spell that this mount item teaches
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then return false end

	-- Convert to number if it's a string
	local spellIDNum = tonumber(spellID)
	return spellIDNum and IsSpellKnown(spellIDNum) or false
end

function DOKI:IsPetCollected(itemID)
	if not itemID or not C_PetJournal then return false end

	-- Get species info for this pet item
	local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, obtainable, displayID, speciesID =
			C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then return false end

	-- Check if we have any pets of this species
	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	-- Try hyperlink first (works for mythic/heroic/normal variants)
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	-- Method 2: If hyperlink failed, fallback to itemID
	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	if not itemModifiedAppearanceID then
		return false, false
	end

	-- Check if THIS specific variant is collected
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		return true, false -- Have this specific variant, no indicator needed
	end

	-- Don't have this variant, check if we have other sources of this appearance
	local showYellowD = false
	if itemAppearanceID then
		local hasOtherSources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasOtherSources then
			showYellowD = true
		end
	end

	return false, showYellowD -- Don't have this variant, but return yellow D flag
end

function DOKI:IsTransmogCollectedSmart(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	-- Try hyperlink first (critical for difficulty variants)
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	-- Fallback to itemID
	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	if not itemModifiedAppearanceID then
		return false, false
	end

	-- Check if we have this specific variant
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		return true, false -- Have this variant, no indicator needed
	end

	-- We don't have this variant - check if we have equal or better sources
	if itemAppearanceID then
		local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasEqualOrBetterSources then
			-- We have identical or less restrictive sources, so we don't need this item
			return true, false -- Treat as collected (no D shown)
		else
			-- We either have no sources, or only more restrictive sources - show orange D
			return false, false -- Show orange D (we need this item)
		end
	end

	return false, false -- Default to orange D
end

function DOKI:HasOtherTransmogSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not sourceIDs or type(sourceIDs) ~= "table" then return false end

	-- Check each source
	for _, sourceID in ipairs(sourceIDs) do
		if type(sourceID) == "number" and sourceID ~= excludeModifiedAppearanceID then
			local success2, hasThisSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
			if success2 and hasThisSource then
				return true
			end
		end
	end

	return false
end

function DOKI:HasEqualOrLessRestrictiveSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then return false end

	-- Get class and faction restrictions for the current item
	local currentItemRestrictions = self:GetClassRestrictionsForSource(excludeModifiedAppearanceID, itemAppearanceID)
	if not currentItemRestrictions then return false end

	-- Check each source we have collected
	for _, sourceID in ipairs(allSources) do
		if sourceID ~= excludeModifiedAppearanceID then
			local success2, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
			if success2 and hasSource then
				-- Get restrictions for this known source
				local sourceRestrictions = self:GetClassRestrictionsForSource(sourceID, itemAppearanceID)
				if sourceRestrictions then
					local sourceClassCount = #sourceRestrictions.validClasses
					local currentClassCount = #currentItemRestrictions.validClasses
					-- Compare faction restrictions
					local factionEquivalent = false
					if sourceRestrictions.hasFactionRestriction == currentItemRestrictions.hasFactionRestriction then
						if not sourceRestrictions.hasFactionRestriction then
							factionEquivalent = true
						elseif sourceRestrictions.faction == currentItemRestrictions.faction then
							factionEquivalent = true
						end
					end

					-- Only compare class restrictions if faction restrictions are equivalent
					if factionEquivalent then
						-- Check if source is less restrictive in terms of classes
						if sourceClassCount > currentClassCount then
							return true
						end

						-- Check if source has identical class restrictions
						if sourceClassCount == currentClassCount then
							-- Create sorted lists to compare classes
							local sourceCopy = {}
							local currentCopy = {}
							for _, classID in ipairs(sourceRestrictions.validClasses) do
								table.insert(sourceCopy, classID)
							end

							for _, classID in ipairs(currentItemRestrictions.validClasses) do
								table.insert(currentCopy, classID)
							end

							table.sort(sourceCopy)
							table.sort(currentCopy)
							-- Check if they're identical
							local identical = true
							for i = 1, #sourceCopy do
								if sourceCopy[i] ~= currentCopy[i] then
									identical = false
									break
								end
							end

							if identical then
								return true
							end
						end
					end
				end
			end
		end
	end

	return false
end

function DOKI:GetClassRestrictionsForSource(sourceID, appearanceID)
	local restrictions = {
		validClasses = {},
		armorType = nil,
		hasClassRestriction = false,
		faction = nil,
		hasFactionRestriction = false,
	}
	-- Get the item from the source
	local linkedItemID = nil
	local success, sourceInfo = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
	if success and sourceInfo and type(sourceInfo) == "table" then
		local itemLinkField = sourceInfo["itemLink"]
		if itemLinkField then
			linkedItemID = self:GetItemID(itemLinkField)
		end
	end

	-- Fallback to GetSourceInfo
	if not linkedItemID then
		local success2, sourceInfo2 = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
		if success2 and sourceInfo2 and sourceInfo2.itemID then
			linkedItemID = sourceInfo2.itemID
		end
	end

	if not linkedItemID then
		return restrictions
	end

	-- Get item properties for armor type
	local success3, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, linkedItemID)
	if success3 and classID == 4 then -- Armor
		restrictions.armorType = subClassID
	end

	-- Parse tooltip for class and faction restrictions
	local tooltip = CreateFrame("GameTooltip", "DOKIClassTooltip" .. sourceID, nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetItemByID(linkedItemID)
	tooltip:Show()
	local foundClassRestriction = false
	local restrictedClasses = {}
	for i = 1, tooltip:NumLines() do
		local line = _G["DOKIClassTooltip" .. sourceID .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text then
				-- Check for class restrictions
				if string.find(text, "Classes:") then
					foundClassRestriction = true
					local classText = string.match(text, "Classes:%s*(.+)")
					if classText then
						local classNameToID = {
							["Warrior"] = 1,
							["Paladin"] = 2,
							["Hunter"] = 3,
							["Rogue"] = 4,
							["Priest"] = 5,
							["Death Knight"] = 6,
							["Shaman"] = 7,
							["Mage"] = 8,
							["Warlock"] = 9,
							["Monk"] = 10,
							["Druid"] = 11,
							["Demon Hunter"] = 12,
							["Evoker"] = 13,
						}
						for className in string.gmatch(classText, "([^,]+)") do
							className = strtrim(className)
							local classID = classNameToID[className]
							if classID then
								table.insert(restrictedClasses, classID)
							end
						end
					end
				end

				-- Check for faction restrictions
				local lowerText = string.lower(text)
				if string.find(lowerText, "alliance") then
					if string.find(lowerText, "require") or string.find(lowerText, "only") or
							string.find(lowerText, "exclusive") or string.find(lowerText, "specific") or
							string.find(lowerText, "reputation") or string.find(text, "Alliance") then
						restrictions.faction = "Alliance"
						restrictions.hasFactionRestriction = true
					end
				elseif string.find(lowerText, "horde") then
					if string.find(lowerText, "require") or string.find(lowerText, "only") or
							string.find(lowerText, "exclusive") or string.find(lowerText, "specific") or
							string.find(lowerText, "reputation") or string.find(text, "Horde") then
						restrictions.faction = "Horde"
						restrictions.hasFactionRestriction = true
					end
				end
			end
		end
	end

	tooltip:Hide()
	if foundClassRestriction then
		restrictions.validClasses = restrictedClasses
		restrictions.hasClassRestriction = true
	else
		-- No class restrictions found - use armor type defaults
		if restrictions.armorType == 1 then                                      -- Cloth
			restrictions.validClasses = { 5, 8, 9 }                                -- Priest, Mage, Warlock
		elseif restrictions.armorType == 2 then                                  -- Leather
			restrictions.validClasses = { 4, 10, 11, 12 }                          -- Rogue, Monk, Druid, Demon Hunter
		elseif restrictions.armorType == 3 then                                  -- Mail
			restrictions.validClasses = { 3, 7, 13 }                               -- Hunter, Shaman, Evoker
		elseif restrictions.armorType == 4 then                                  -- Plate
			restrictions.validClasses = { 1, 2, 6 }                                -- Warrior, Paladin, Death Knight
		elseif classID == 2 then                                                 -- Weapon
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- All classes
		else
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- Unknown, assume all
		end
	end

	return restrictions
end

-- ===== DEBUG AND TESTING FUNCTIONS =====
function DOKI:DebugFoundFrames()
	if not self.foundFramesThisScan or #self.foundFramesThisScan == 0 then
		print("|cffff69b4DOKI|r No frames found in last scan. Try /doki scan first.")
		return
	end

	print(string.format("|cffff69b4DOKI|r === FOUND FRAMES DEBUG (%d frames) ===", #self.foundFramesThisScan))
	for i, frameInfo in ipairs(self.foundFramesThisScan) do
		local itemName = C_Item.GetItemInfo(frameInfo.itemData.itemID) or "Unknown"
		print(string.format("%d. %s (ID: %d) in %s [%s] - %s",
			i, itemName, frameInfo.itemData.itemID, frameInfo.frameName,
			frameInfo.itemData.frameType,
			frameInfo.itemData.isCollected and "COLLECTED" or "NOT collected"))
	end

	print("|cffff69b4DOKI|r === END FOUND FRAMES DEBUG ===")
end

function DOKI:TestElvUIBags()
	if not ElvUI then
		print("|cffff69b4DOKI|r ElvUI not detected")
		return
	end

	print("|cffff69b4DOKI|r === ELVUI BAG TEST ===")
	local E = ElvUI[1]
	print(string.format("ElvUI[1] exists: %s", E and "yes" or "no"))
	if not E then
		print("|cffff69b4DOKI|r Cannot proceed without ElvUI[1]")
		return
	end

	local B = E:GetModule("Bags", true)
	print(string.format("Bags module exists: %s", B and "yes" or "no"))
	if B then
		print(string.format("BagFrame exists: %s", B.BagFrame and "yes" or "no"))
		if B.BagFrame then
			print(string.format("BagFrame shown: %s", B.BagFrame:IsShown() and "yes" or "no"))
		end
	end

	-- Test button naming patterns for first few slots
	print("\nTesting button naming patterns:")
	local patternsFound = 0
	for bagID = 0, 1 do -- Just test first two bags
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, math.min(3, numSlots) do -- Just test first 3 slots
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					print(string.format("Bag %d Slot %d has item %d", bagID, slotID, itemInfo.itemID))
					-- Test different naming patterns
					local patterns = {
						string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%dArea", bagID, slotID),
					}
					for _, pattern in ipairs(patterns) do
						local button = _G[pattern]
						if button then
							print(string.format("  Found button: %s (visible: %s)",
								pattern, button:IsVisible() and "yes" or "no"))
							if button:IsVisible() then
								patternsFound = patternsFound + 1
							end
						end
					end
				end
			end
		end
	end

	print(string.format("\nVisible ElvUI buttons found: %d", patternsFound))
	print("|cffff69b4DOKI|r === END ELVUI TEST ===")
end

function DOKI:TestMerchantFrames()
	if not MerchantFrame or not MerchantFrame:IsVisible() then
		print("|cffff69b4DOKI|r Merchant frame not visible")
		return
	end

	print("|cffff69b4DOKI|r === MERCHANT FRAME TEST ===")
	for i = 1, 10 do
		local buttonName = "MerchantItem" .. i .. "ItemButton"
		local button = _G[buttonName]
		print(string.format("Testing %s:", buttonName))
		print(string.format("  Button exists: %s", button and "yes" or "no"))
		if button then
			local isVisible = button:IsVisible()
			print(string.format("  Button visible: %s", tostring(isVisible)))
			if isVisible then
				-- Test item extraction
				local itemLink = GetMerchantItemLink(i)
				print(string.format("  GetMerchantItemLink(%d): %s", i, itemLink or "nil"))
				if itemLink then
					local itemID = self:GetItemID(itemLink)
					print(string.format("  ItemID: %s", tostring(itemID)))
					if itemID then
						local isCollectible = self:IsCollectibleItem(itemID)
						print(string.format("  Is collectible: %s", tostring(isCollectible)))
						if isCollectible then
							local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
							print(string.format("  Collection status: %s%s",
								isCollected and "COLLECTED" or "NOT collected",
								showYellowD and " (blue D)" or ""))
						end
					end
				end

				-- Test frame extraction
				local frameItemData = self:ExtractItemFromAnyFrameOptimized(button, buttonName)
				print(string.format("  Frame extraction: %s",
					frameItemData and ("ItemID " .. frameItemData.itemID) or "failed"))
			end
		end

		print("") -- Empty line between items
	end

	print("|cffff69b4DOKI|r === END MERCHANT TEST ===")
end

-- Debug transmog functions (abbreviated for space - full versions in original code)
function DOKI:DebugTransmogItem(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki debug <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === DEBUGGING ITEM %d ===", itemID))
	-- Get basic item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID = C_Item.GetItemInfo(itemID)
	if not itemName then
		print("|cffff69b4DOKI|r Item not found or not cached. Try again in a few seconds.")
		return
	end

	print(string.format("Item Name: %s", itemName))
	print(string.format("Class ID: %d, SubClass ID: %d", classID or 0, subClassID or 0))
	print(string.format("Item Type: %s, SubType: %s", itemType or "nil", itemSubType or "nil"))
	-- Check if it's a transmog item
	if not (classID == 2 or classID == 4) then
		print("|cffff69b4DOKI|r Not a transmog item (not weapon or armor)")
		return
	end

	-- Get appearance IDs
	print("\n--- Getting Appearance IDs ---")
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	print(string.format("Item Appearance ID: %s", tostring(itemAppearanceID)))
	print(string.format("Modified Appearance ID: %s", tostring(itemModifiedAppearanceID)))
	if not itemModifiedAppearanceID then
		print("|cffff69b4DOKI|r No appearance IDs found - item cannot be transmogged")
		return
	end

	-- Check if we have this specific variant
	print("\n--- Checking This Specific Variant ---")
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	print(string.format("Has this variant: %s", tostring(hasThisVariant)))
	if hasThisVariant then
		print("|cffff69b4DOKI|r Result: COLLECTED - No indicator needed")
		return
	end

	-- Check for other sources
	print("\n--- Checking Other Sources ---")
	if itemAppearanceID then
		local sourceIDs = C_TransmogCollection.GetAllAppearanceSources(itemAppearanceID)
		print(string.format("Number of sources found: %d", sourceIDs and #sourceIDs or 0))
		if sourceIDs and #sourceIDs > 0 then
			local foundOtherSource = false
			for i, sourceID in ipairs(sourceIDs) do
				if sourceID ~= itemModifiedAppearanceID then
					local success, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
					if success and hasSource then
						foundOtherSource = true
						break
					end
				end
			end

			-- Final result
			print("\n--- FINAL RESULT ---")
			if foundOtherSource then
				if self.db.smartMode then
					print("|cffff69b4DOKI|r Smart mode enabled - checking class and faction restrictions...")
					local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID,
						itemModifiedAppearanceID)
					if hasEqualOrBetterSources then
						print("|cffff69b4DOKI|r Result: HAVE EQUAL OR BETTER SOURCE - No D")
					else
						print("|cffff69b4DOKI|r Result: OTHER SOURCES MORE RESTRICTIVE - Orange D")
					end
				else
					print("|cffff69b4DOKI|r Result: COLLECTED FROM OTHER SOURCE - Blue D")
				end
			else
				print("|cffff69b4DOKI|r Result: UNCOLLECTED - Orange D")
			end
		else
			print("|cffff69b4DOKI|r Result: UNCOLLECTED - Orange D")
		end
	else
		print("|cffff69b4DOKI|r Result: UNCOLLECTED - Orange D")
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
end

function DOKI:DebugSmartTransmog(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki smart <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SMART TRANSMOG DEBUG: %d ===", itemID))
	-- Get appearance IDs
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	if not itemAppearanceID then
		print("No appearance ID found")
		return
	end

	print(string.format("Appearance ID: %d, Modified ID: %d", itemAppearanceID, itemModifiedAppearanceID))
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then
		print("No sources found or error retrieving sources")
		return
	end

	print(string.format("Found %d total sources", #allSources))
	-- Analyze current item restrictions
	local currentRestrictions = self:GetClassRestrictionsForSource(itemModifiedAppearanceID, itemAppearanceID)
	print(string.format("\n--- Current Item Restrictions ---"))
	if currentRestrictions then
		print(string.format("Valid for %d classes: %s", #currentRestrictions.validClasses,
			table.concat(currentRestrictions.validClasses, ", ")))
		print(string.format("Faction: %s", tostring(currentRestrictions.faction)))
		print(string.format("Has faction restriction: %s", tostring(currentRestrictions.hasFactionRestriction)))
	else
		print("Could not determine restrictions")
	end

	-- Final smart assessment
	print(string.format("\n--- Smart Assessment ---"))
	local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
	print(string.format("Has equal or less restrictive sources: %s", tostring(hasEqualOrBetterSources)))
	local regularCheck = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
	print(string.format("Has any other sources: %s", tostring(regularCheck)))
	print("|cffff69b4DOKI|r === END SMART DEBUG ===")
end

function DOKI:DebugClassRestrictions(sourceID, appearanceID)
	print(string.format("|cffff69b4DOKI|r === CLASS RESTRICTION DEBUG: Source %d, Appearance %d ===", sourceID,
		appearanceID))
	local restrictions = self:GetClassRestrictionsForSource(sourceID, appearanceID)
	if restrictions then
		print("Results from GetClassRestrictionsForSource:")
		print(string.format("  Valid classes: %s", table.concat(restrictions.validClasses, ", ")))
		print(string.format("  Armor type: %s", tostring(restrictions.armorType)))
		print(string.format("  Has class restriction: %s", tostring(restrictions.hasClassRestriction)))
		print(string.format("  Faction: %s", tostring(restrictions.faction)))
		print(string.format("  Has faction restriction: %s", tostring(restrictions.hasFactionRestriction)))
	else
		print("Could not get restrictions")
	end

	print("|cffff69b4DOKI|r === END CLASS RESTRICTION DEBUG ===")
end

function DOKI:DebugSourceRestrictions(sourceID)
	if not sourceID then
		print("|cffff69b4DOKI|r Usage: /doki source <sourceID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SOURCE RESTRICTION DEBUG: %d ===", sourceID))
	local restrictions = self:GetClassRestrictionsForSource(sourceID, nil)
	if restrictions then
		print("Results from GetClassRestrictionsForSource:")
		print(string.format("  Valid classes: %s", table.concat(restrictions.validClasses, ", ")))
		print(string.format("  Armor type: %s", tostring(restrictions.armorType)))
		print(string.format("  Has class restriction: %s", tostring(restrictions.hasClassRestriction)))
		print(string.format("  Faction: %s", tostring(restrictions.faction)))
		print(string.format("  Has faction restriction: %s", tostring(restrictions.hasFactionRestriction)))
	else
		print("Could not get restrictions")
	end

	print("|cffff69b4DOKI|r === END SOURCE DEBUG ===")
end

function DOKI:DebugItemInfo(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki item <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === ITEM INFO DEBUG: %d ===", itemID))
	-- Get all available item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID, bindType, expacID, setID, isCraftingReagent = C_Item
			.GetItemInfo(itemID)
	print(string.format("Name: %s", itemName or "Unknown"))
	print(string.format("Type: %s (%d), SubType: %s (%d)", itemType or "nil", classID or 0, itemSubType or "nil",
		subClassID or 0))
	print(string.format("Equip Loc: %s", itemEquipLoc or "nil"))
	-- Check if this gives us any class restriction hints
	local _, _, _, _, _, _, instantClassID, instantSubClassID = C_Item.GetItemInfoInstant(itemID)
	print(string.format("Instant: Class %d, SubClass %d", instantClassID or 0, instantSubClassID or 0))
	print("|cffff69b4DOKI|r === END ITEM DEBUG ===")
end
