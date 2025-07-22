-- DOKI Overlays - Enhanced with ElvUI Bags Support
local addonName, DOKI = ...
-- Overlay management
local overlayIndex = 1
-- Initialize button tracking system
DOKI.buttonCache = {}
DOKI.buttonCacheValid = false
-- Check if any ElvUI bags are visible
function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or
			(B.BankFrame and B.BankFrame:IsShown()) or
			(B.WarbandFrame and B.WarbandFrame:IsShown())
end

-- Detect which bag addon is active
function DOKI:DetectBagAddon()
	-- Check for ElvUI
	if ElvUI then
		local E = ElvUI[1]
		if E and E:GetModule("Bags", true) then
			return "ElvUI"
		end
	end

	-- Default to Blizzard
	return "Blizzard"
end

-- Get or create an overlay from the pool
function DOKI:GetOverlay()
	local overlay = table.remove(self.overlayPool)
	if not overlay then
		overlay = self:CreateOverlay()
	end

	return overlay
end

-- Return overlay to pool
function DOKI:ReleaseOverlay(overlay)
	if not overlay then return end

	overlay:Hide()
	overlay:SetParent(nil)
	overlay:ClearAllPoints()
	-- Clean up references
	for itemLink, activeOverlay in pairs(self.activeOverlays) do
		if activeOverlay == overlay then
			self.activeOverlays[itemLink] = nil
			break
		end
	end

	table.insert(self.overlayPool, overlay)
end

-- Create new overlay frame
function DOKI:CreateOverlay()
	local overlay = CreateFrame("Frame", "DOKIOverlay" .. overlayIndex)
	overlayIndex = overlayIndex + 1
	-- Create text element
	overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	overlay.text:SetPoint("CENTER")
	overlay.text:SetText("D")
	overlay.text:SetTextColor(1, 0.41, 0.71) -- Default pink color
	overlay.text:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
	-- Make overlay click-through
	overlay:EnableMouse(false)
	overlay:SetFrameLevel(1000) -- High frame level to appear on top
	-- Function to set color
	overlay.SetColor = function(self, r, g, b)
		self.text:SetTextColor(r, g, b)
	end
	return overlay
end

-- ===== ELVUI BUTTON FINDING SYSTEM =====
-- Find ElvUI item button using their naming convention
function DOKI:FindElvUIItemButton(bagID, slotID)
	if not bagID or not slotID then return nil end

	-- ElvUI uses: ElvUI_ContainerFrameBag[bagID]Slot[slotID]Hash
	local buttonName = string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID)
	local button = _G[buttonName]
	if button and button:IsVisible() then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Found ElvUI button %s for bag %d slot %d", buttonName, bagID, slotID))
		end

		return button
	end

	-- Try alternative naming patterns
	local alternativeNames = {
		string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
		string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
		string.format("ElvUI_ContainerFrameBag%dSlot%dArea", bagID, slotID),
	}
	for _, altName in ipairs(alternativeNames) do
		local altButton = _G[altName]
		if altButton and altButton:IsVisible() then
			-- Verify this button has the right bag/slot info
			if altButton.BagID == bagID and altButton.SlotID == slotID then
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Found ElvUI button %s (alternative) for bag %d slot %d", altName, bagID,
						slotID))
				end

				return altButton
			end
		end
	end

	-- Try searching through ElvUI container frames
	return self:FindElvUIItemButtonByEnumeration(bagID, slotID)
end

-- Find ElvUI item button by searching through ElvUI frames
function DOKI:FindElvUIItemButtonByEnumeration(bagID, slotID)
	if not ElvUI then return nil end

	local E = ElvUI[1]
	if not E then return nil end

	local B = E:GetModule("Bags", true)
	if not B then return nil end

	-- Check ElvUI bag frames
	local framesToCheck = {}
	if B.BagFrame and B.BagFrame:IsShown() then
		table.insert(framesToCheck, B.BagFrame)
	end

	if B.BankFrame and B.BankFrame:IsShown() then
		table.insert(framesToCheck, B.BankFrame)
	end

	if B.WarbandFrame and B.WarbandFrame:IsShown() then
		table.insert(framesToCheck, B.WarbandFrame)
	end

	-- Search through frame children
	for _, frame in ipairs(framesToCheck) do
		local button = self:SearchElvUIFrameForButton(frame, bagID, slotID)
		if button then
			return button
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Could not find ElvUI button for bag %d slot %d", bagID, slotID))
	end

	return nil
end

-- Recursively search ElvUI frame for the specific button
function DOKI:SearchElvUIFrameForButton(frame, targetBagID, targetSlotID)
	if not frame then return nil end

	-- Check if this frame itself is the button we're looking for
	if frame.BagID == targetBagID and frame.SlotID == targetSlotID and frame:IsVisible() then
		return frame
	end

	-- Search children
	for i = 1, frame:GetNumChildren() do
		local child = select(i, frame:GetChildren())
		if child then
			local result = self:SearchElvUIFrameForButton(child, targetBagID, targetSlotID)
			if result then
				return result
			end
		end
	end

	return nil
end

-- ===== MODERN BLIZZARD BUTTON FINDING SYSTEM =====
-- Modern approach to find item buttons using enumeration
function DOKI:FindBlizzardItemButton(bagID, slotID)
	if not bagID or not slotID then return nil end

	-- Method 1: Try official Blizzard utility first (if available)
	if ContainerFrameUtil_GetItemButtonAndContainer then
		local success, itemButton, container = pcall(ContainerFrameUtil_GetItemButtonAndContainer, bagID, slotID)
		if success and itemButton and itemButton:IsVisible() then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Found button via official utility for bag %d slot %d", bagID, slotID))
			end

			return itemButton
		end
	end

	-- Method 2: Check combined bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if ContainerFrameCombinedBags.EnumerateValidItems then
			local success, result = pcall(function()
				for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
					if itemButton and itemButton.GetBagID and itemButton.GetID then
						if itemButton:GetBagID() == bagID and itemButton:GetID() == slotID then
							return itemButton
						end
					end
				end

				return nil
			end)
			if success and result then
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Found button in combined bags for bag %d slot %d", bagID, slotID))
				end

				return result
			end
		end
	end

	-- Method 3: Use ContainerFrameUtil_EnumerateContainerFrames
	if ContainerFrameUtil_EnumerateContainerFrames then
		local success, result = pcall(function()
			for i, frame in ContainerFrameUtil_EnumerateContainerFrames() do
				if frame and frame:IsShown() and frame.EnumerateValidItems then
					for _, itemButton in frame:EnumerateValidItems() do
						if itemButton and itemButton.GetBagID and itemButton.GetID then
							if itemButton:GetBagID() == bagID and itemButton:GetID() == slotID then
								return itemButton, i
							end
						end
					end
				end
			end

			return nil
		end)
		if success and result then
			if self.db and self.db.debugMode then
				local itemButton, frameIndex = result, select(2, result) or "unknown"
				print(string.format("|cffff69b4DOKI|r Found button in enumerated frame %s for bag %d slot %d", frameIndex, bagID,
					slotID))
			end

			return result
		end
	end

	-- Method 4: Try individual container frames manually
	for i = 1, NUM_CONTAINER_FRAMES do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame:IsShown() then
			if frame.EnumerateValidItems then
				local success, result = pcall(function()
					for _, itemButton in frame:EnumerateValidItems() do
						if itemButton and itemButton.GetBagID and itemButton.GetID then
							if itemButton:GetBagID() == bagID and itemButton:GetID() == slotID then
								return itemButton
							end
						end
					end

					return nil
				end)
				if success and result then
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found button in manual frame %d for bag %d slot %d", i, bagID, slotID))
					end

					return result
				end
			end
		end
	end

	-- Method 5: Legacy fallback
	return self:FindItemButtonLegacy(bagID, slotID)
end

-- Legacy fallback method for older container frame structures
function DOKI:FindItemButtonLegacy(bagID, slotID)
	-- Try to find which container frame has this bag open
	local containerID = IsBagOpen(bagID)
	if not containerID then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Bag %d is not open", bagID))
		end

		return nil
	end

	-- Try different legacy naming patterns
	local possibleButtons = {
		_G["ContainerFrame" .. containerID .. "Item" .. slotID],
		_G["ContainerFrame" .. containerID .. "Item" .. (slotID)],
	}
	for _, button in ipairs(possibleButtons) do
		if button and button:IsVisible() then
			-- Verify this is the correct button
			if button.GetBagID and button.GetID then
				if button:GetBagID() == bagID and button:GetID() == slotID then
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found button via legacy method for bag %d slot %d", bagID, slotID))
					end

					return button
				end
			end
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Could not find button for bag %d slot %d via any method", bagID, slotID))
	end

	return nil
end

-- ===== UNIVERSAL BUTTON FINDING SYSTEM =====
-- Main function to find item button (detects bag addon and uses appropriate method)
function DOKI:FindItemButton(bagID, slotID)
	-- Try cache first (fastest)
	local button = self:GetButtonFromCache(bagID, slotID)
	if button and button:IsVisible() then
		return button
	end

	-- Detect which bag system to use
	local bagAddon = self:DetectBagAddon()
	if bagAddon == "ElvUI" then
		return self:FindElvUIItemButton(bagID, slotID)
	else
		return self:FindBlizzardItemButton(bagID, slotID)
	end
end

-- Find merchant button (unchanged)
function DOKI:FindMerchantButton(merchantIndex)
	return _G["MerchantItem" .. merchantIndex .. "ItemButton"]
end

-- Initialize button tracking and hook system
function DOKI:InitializeButtonTracking()
	self.buttonCache = {}
	self.buttonCacheValid = false
	local bagAddon = self:DetectBagAddon()
	if bagAddon == "ElvUI" then
		self:InitializeElvUIHooks()
	else
		self:InitializeBlizzardHooks()
	end
end

-- Initialize ElvUI-specific hooks
function DOKI:InitializeElvUIHooks()
	if not ElvUI then return end

	local E = ElvUI[1]
	if not E then return end

	local B = E:GetModule("Bags", true)
	if not B then return end

	-- Hook ElvUI bag layout function
	if B.Layout then
		hooksecurefunc(B, "Layout", function()
			self:InvalidateButtonCache()
		end)
	end

	-- Hook ElvUI bag frame show/hide
	if B.BagFrame then
		B.BagFrame:HookScript("OnShow", function()
			self:InvalidateButtonCache()
		end)
		B.BagFrame:HookScript("OnHide", function()
			self:InvalidateButtonCache()
		end)
	end

	if B.BankFrame then
		B.BankFrame:HookScript("OnShow", function()
			self:InvalidateButtonCache()
		end)
		B.BankFrame:HookScript("OnHide", function()
			self:InvalidateButtonCache()
		end)
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ElvUI hooks initialized")
	end
end

-- Initialize Blizzard-specific hooks
function DOKI:InitializeBlizzardHooks()
	-- Hook combined bags update
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
		hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", function()
			self:InvalidateButtonCache()
		end)
	end

	-- Hook individual container frame updates
	if ContainerFrameUtil_EnumerateContainerFrames then
		for i, frame in ContainerFrameUtil_EnumerateContainerFrames() do
			if frame and frame.UpdateItems then
				hooksecurefunc(frame, "UpdateItems", function()
					self:InvalidateButtonCache()
				end)
			end
		end
	else
		-- Legacy container frame hooks
		for i = 1, NUM_CONTAINER_FRAMES do
			local frame = _G["ContainerFrame" .. i]
			if frame and frame.UpdateItems then
				hooksecurefunc(frame, "UpdateItems", function()
					self:InvalidateButtonCache()
				end)
			end
		end
	end

	-- Hook bag open/close events
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("BAG_UPDATE")
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	eventFrame:SetScript("OnEvent", function(self, event, bagID)
		DOKI:InvalidateButtonCache()
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Blizzard hooks initialized")
	end
end

-- Invalidate button cache when bags update
function DOKI:InvalidateButtonCache()
	self.buttonCacheValid = false
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Button cache invalidated")
	end
end

-- Build/rebuild button cache
function DOKI:UpdateButtonCache()
	if self.buttonCacheValid then return end

	wipe(self.buttonCache)
	local buttonCount = 0
	local bagAddon = self:DetectBagAddon()
	if bagAddon == "ElvUI" then
		buttonCount = self:CacheElvUIButtons()
	else
		buttonCount = self:CacheBlizzardButtons()
	end

	self.buttonCacheValid = true
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Button cache updated (%s): %d buttons cached", bagAddon, buttonCount))
	end
end

-- Cache ElvUI buttons
function DOKI:CacheElvUIButtons()
	local buttonCount = 0
	-- Cache all visible ElvUI buttons by searching through global namespace
	for name, obj in pairs(_G) do
		if type(obj) == "table" and obj.GetObjectType and
				string.match(name, "^ElvUI_ContainerFrameBag%d+Slot%d+") then
			-- Extract bag and slot info from name
			local bagID, slotID = string.match(name, "ElvUI_ContainerFrameBag(%d+)Slot(%d+)")
			if bagID and slotID and obj:IsVisible() then
				bagID = tonumber(bagID)
				slotID = tonumber(slotID)
				-- Verify this is actually an item button
				if obj.BagID == bagID and obj.SlotID == slotID then
					local key = bagID .. "_" .. slotID
					self.buttonCache[key] = obj
					buttonCount = buttonCount + 1
				end
			end
		end
	end

	return buttonCount
end

-- Cache Blizzard buttons
function DOKI:CacheBlizzardButtons()
	local buttonCount = 0
	-- Cache combined bags buttons
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() and ContainerFrameCombinedBags.EnumerateValidItems then
		for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
			if itemButton and itemButton.GetBagID and itemButton.GetID then
				local bagID = itemButton:GetBagID()
				local slotID = itemButton:GetID()
				local key = bagID .. "_" .. slotID
				self.buttonCache[key] = itemButton
				buttonCount = buttonCount + 1
			end
		end
	end

	-- Cache individual container frame buttons
	if ContainerFrameUtil_EnumerateContainerFrames then
		for i, frame in ContainerFrameUtil_EnumerateContainerFrames() do
			if frame and frame:IsShown() and frame.EnumerateValidItems then
				for _, itemButton in frame:EnumerateValidItems() do
					if itemButton and itemButton.GetBagID and itemButton.GetID then
						local bagID = itemButton:GetBagID()
						local slotID = itemButton:GetID()
						local key = bagID .. "_" .. slotID
						if not self.buttonCache[key] then -- Don't overwrite combined bags
							self.buttonCache[key] = itemButton
							buttonCount = buttonCount + 1
						end
					end
				end
			end
		end
	end

	return buttonCount
end

-- Get button from cache (fastest method)
function DOKI:GetButtonFromCache(bagID, slotID)
	if not bagID or not slotID then return nil end

	self:UpdateButtonCache()
	local key = bagID .. "_" .. slotID
	return self.buttonCache[key]
end

-- ===== OVERLAY MANAGEMENT =====
-- Create overlay for specific item with color support
function DOKI:CreateOverlayForItem(itemLink, itemData)
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Creating overlay for %s at %s", itemLink, itemData.location))
	end

	local button = nil
	if itemData.location == "bag" then
		button = self:FindItemButton(itemData.bagID, itemData.slotID)
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Looking for bag %d slot %d button: %s",
				itemData.bagID, itemData.slotID, button and "found" or "not found"))
		end
	elseif itemData.location == "merchant" then
		button = self:FindMerchantButton(itemData.merchantIndex)
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Looking for merchant %d button: %s",
				itemData.merchantIndex, button and "found" or "not found"))
		end
	end

	if not button or not button:IsVisible() then
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Could not find button for " .. itemLink)
		end

		return
	end

	local overlay = self:GetOverlay()
	overlay:SetParent(button)
	overlay:SetAllPoints(button)
	-- Set color based on type
	if itemData.showYellowD then
		overlay:SetColor(1, 1, 0) -- Yellow for "have other sources"
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Set yellow D for " .. itemLink)
		end
	else
		overlay:SetColor(1, 0.41, 0.71) -- Pink for "don't have any sources"
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Set pink D for " .. itemLink)
		end
	end

	overlay:Show()
	-- Store reference
	self.activeOverlays[itemLink] = overlay
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Created overlay for " .. itemLink .. " on button " .. (button:GetName() or "unnamed"))
	end
end

-- Update overlay for a single item
function DOKI:UpdateSingleItemOverlay(itemLink, itemData)
	if not (self.db and self.db.enabled) then return end

	-- Clear existing overlay for this item
	if self.activeOverlays[itemLink] then
		self:ReleaseOverlay(self.activeOverlays[itemLink])
		self.activeOverlays[itemLink] = nil
	end

	-- Create new overlay if item is not collected
	if not itemData.isCollected then
		self:CreateOverlayForItem(itemLink, itemData)
	end
end

-- Update all overlays
function DOKI:UpdateAllOverlays()
	if not (self.db and self.db.enabled) then return end

	-- Clear existing overlays
	self:ClearAllOverlays()
	-- Ensure button tracking is initialized
	if not self.buttonCache then
		self:InitializeOverlaySystem()
	end

	-- Create overlays for current items
	local overlayCount = 0
	for itemLink, itemData in pairs(self.currentItems) do
		if not itemData.isCollected then -- Only show for uncollected items
			self:CreateOverlayForItem(itemLink, itemData)
			overlayCount = overlayCount + 1
		end
	end

	if self.db and self.db.debugMode then
		local bagAddon = self:DetectBagAddon()
		print(string.format("|cffff69b4DOKI|r Created %d overlays for uncollected items (%s bags)", overlayCount, bagAddon))
	end
end

-- Update merchant overlays
function DOKI:UpdateMerchantOverlays()
	if not (self.db and self.db.enabled) or not MerchantFrame or not MerchantFrame:IsVisible() then return end

	-- Clear existing merchant overlays
	self:ClearMerchantOverlays()
	-- Create overlays for merchant items
	local overlayCount = 0
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "merchant" and not itemData.isCollected then
			self:CreateOverlayForItem(itemLink, itemData)
			overlayCount = overlayCount + 1
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Created %d merchant overlays", overlayCount))
	end
end

-- Clear all overlays
function DOKI:ClearAllOverlays()
	for itemLink, overlay in pairs(self.activeOverlays) do
		self:ReleaseOverlay(overlay)
	end

	wipe(self.activeOverlays)
end

-- Clear merchant overlays
function DOKI:ClearMerchantOverlays()
	for itemLink, overlay in pairs(self.activeOverlays) do
		if self.currentItems[itemLink] and self.currentItems[itemLink].location == "merchant" then
			self:ReleaseOverlay(overlay)
			self.activeOverlays[itemLink] = nil
		end
	end

	-- Remove merchant items from current items
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "merchant" then
			self.currentItems[itemLink] = nil
		end
	end
end

-- ===== INITIALIZATION AND TESTING =====
-- Initialize the enhanced overlay system
function DOKI:InitializeOverlaySystem()
	local bagAddon = self:DetectBagAddon()
	self:InitializeButtonTracking()
	-- Hook container frame show events to refresh overlays when bags are opened
	self:HookContainerFrameEvents()
	-- Setup ElvUI integration if detected
	if bagAddon == "ElvUI" then
		self:SetupElvUIIntegration()
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Enhanced overlay system initialized (%s bags detected)", bagAddon))
	end
end

-- Setup comprehensive ElvUI integration
function DOKI:SetupElvUIIntegration()
	if not ElvUI then return end

	-- Setup ElvUI hooks from Utils module
	if self.SetupElvUIHooks then
		self:SetupElvUIHooks()
	end

	-- Start polling system for ElvUI bags
	self:StartElvUIPolling()
	-- Hook standard bag opening functions to ensure scanning
	self:HookStandardBagFunctions()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ElvUI integration setup complete")
	end
end

-- Start polling system for ElvUI bags (backup method)
function DOKI:StartElvUIPolling()
	if self.elvuiPollingTimer then
		self.elvuiPollingTimer:Cancel()
	end

	-- Poll every 2 seconds to check for new items
	self.elvuiPollingTimer = C_Timer.NewTicker(2, function()
		if not self.db or not self.db.enabled then return end

		if self:IsElvUIBagVisible() then
			-- Check if we have items scanned, if not, scan now
			local hasItems = false
			for _ in pairs(self.currentItems) do
				hasItems = true
				break
			end

			if not hasItems then
				if self.db and self.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI polling: No items found, triggering scan")
				end

				self:ScanCurrentItems()
				self:UpdateAllOverlays()
			end
		end
	end)
end

-- Hook standard bag functions to ensure ElvUI scanning
function DOKI:HookStandardBagFunctions()
	-- These functions can be called even with ElvUI
	local originalOpenBackpack = OpenBackpack
	OpenBackpack = function(...)
		local result = originalOpenBackpack(...)
		if ElvUI and self.db and self.db.enabled then
			C_Timer.After(0.3, function()
				self:ScanCurrentItems()
				self:UpdateAllOverlays()
			end)
		end

		return result
	end
	local originalToggleAllBags = ToggleAllBags
	ToggleAllBags = function(...)
		local result = originalToggleAllBags(...)
		if ElvUI and self.db and self.db.enabled then
			C_Timer.After(0.3, function()
				self:ScanCurrentItems()
				self:UpdateAllOverlays()
			end)
		end

		return result
	end
	local originalOpenAllBags = OpenAllBags
	OpenAllBags = function(...)
		local result = originalOpenAllBags(...)
		if ElvUI and self.db and self.db.enabled then
			C_Timer.After(0.3, function()
				self:ScanCurrentItems()
				self:UpdateAllOverlays()
			end)
		end

		return result
	end
end

-- Hook container frame show events - Enhanced for both ElvUI and Blizzard
function DOKI:HookContainerFrameEvents()
	local bagAddon = self:DetectBagAddon()
	if bagAddon == "ElvUI" then
		self:HookElvUIFrameEvents()
	else
		self:HookBlizzardFrameEvents()
	end
end

-- Hook ElvUI frame events
function DOKI:HookElvUIFrameEvents()
	if not ElvUI then return end

	local E = ElvUI[1]
	if not E then return end

	local B = E:GetModule("Bags", true)
	if not B then return end

	-- Hook ElvUI bag frames
	if B.BagFrame then
		B.BagFrame:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.1, function()
					self:ScanCurrentItems() -- SCAN FIRST
					self:UpdateAllOverlays() -- THEN UPDATE
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Refreshed overlays: ElvUI bags opened")
					end
				end)
			end
		end)
	end

	if B.BankFrame then
		B.BankFrame:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.1, function()
					self:ScanCurrentItems() -- SCAN FIRST
					self:UpdateAllOverlays() -- THEN UPDATE
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Refreshed overlays: ElvUI bank opened")
					end
				end)
			end
		end)
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ElvUI frame events hooked")
	end
end

-- Hook Blizzard frame events
function DOKI:HookBlizzardFrameEvents()
	-- Hook combined bags
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.1, function()
					self:ScanCurrentItems() -- SCAN FIRST
					self:UpdateAllOverlays() -- THEN UPDATE
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Refreshed overlays: Combined bags opened")
					end
				end)
			end
		end)
	end

	-- Hook individual container frames
	for i = 1, NUM_CONTAINER_FRAMES do
		local frame = _G["ContainerFrame" .. i]
		if frame then
			frame:HookScript("OnShow", function()
				if self.db and self.db.enabled then
					C_Timer.After(0.1, function()
						self:ScanCurrentItems() -- SCAN FIRST
						self:UpdateAllOverlays() -- THEN UPDATE
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Refreshed overlays: Container frame %d opened", i))
						end
					end)
				end
			end)
		end
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Blizzard frame events hooked")
	end
end

-- Enhanced diagnostic function to test button finding
function DOKI:TestButtonFinding()
	if not self.db or not self.db.debugMode then
		print("|cffff69b4DOKI|r Enable debug mode first with /doki debug")
		return
	end

	local bagAddon = self:DetectBagAddon()
	print(string.format("|cffff69b4DOKI|r Testing button finding methods (%s)...", bagAddon))
	if bagAddon == "ElvUI" then
		self:TestElvUIButtonFinding()
	else
		self:TestBlizzardButtonFinding()
	end

	-- Test current items
	local testCount = 0
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "bag" and testCount < 3 then
			local button = self:FindItemButton(itemData.bagID, itemData.slotID)
			print(string.format("Test %d: Bag %d Slot %d - %s",
				testCount + 1, itemData.bagID, itemData.slotID, button and "FOUND" or "NOT FOUND"))
			testCount = testCount + 1
		end
	end

	if testCount == 0 then
		print("No bag items found to test with. Try scanning first with /doki scan")
	end
end

-- Test ElvUI button finding
function DOKI:TestElvUIButtonFinding()
	if not ElvUI then
		print("ElvUI not detected")
		return
	end

	local E = ElvUI[1]
	local B = E and E:GetModule("Bags", true)
	print("ElvUI version:", E and E.version or "unknown")
	print("Bags module:", B and "exists" or "missing")
	print("BagFrame:", B and B.BagFrame and "exists" or "missing")
	print("BankFrame:", B and B.BankFrame and "exists" or "missing")
	-- Test searching for ElvUI buttons in global namespace
	local elvuiButtonCount = 0
	for name, obj in pairs(_G) do
		if string.match(name, "^ElvUI_ContainerFrameBag%d+Slot%d+") and type(obj) == "table" and obj.GetObjectType then
			elvuiButtonCount = elvuiButtonCount + 1
		end
	end

	print("ElvUI item buttons found:", elvuiButtonCount)
end

-- Test Blizzard button finding
function DOKI:TestBlizzardButtonFinding()
	print("ContainerFrameCombinedBags:", ContainerFrameCombinedBags and "exists" or "missing")
	print("ContainerFrameUtil_EnumerateContainerFrames:",
		ContainerFrameUtil_EnumerateContainerFrames and "exists" or "missing")
	print("ContainerFrameUtil_GetItemButtonAndContainer:",
		ContainerFrameUtil_GetItemButtonAndContainer and "exists" or "missing")
end
