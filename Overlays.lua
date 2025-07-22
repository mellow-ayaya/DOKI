-- DOKI Overlays - Modern WoW Compatible Version with Yellow D Support
local addonName, DOKI = ...
-- Overlay management
local overlayIndex = 1
-- Initialize button tracking system
DOKI.buttonCache = {}
DOKI.buttonCacheValid = false
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

-- ===== MODERN BUTTON FINDING SYSTEM =====
-- Modern approach to find item buttons using enumeration
function DOKI:FindItemButtonModern(bagID, slotID)
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

-- Initialize button tracking and hook system
function DOKI:InitializeButtonTracking()
	self.buttonCache = {}
	self.buttonCacheValid = false
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

	self.buttonCacheValid = true
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Button cache updated: %d buttons cached", buttonCount))
	end
end

-- Get button from cache (fastest method)
function DOKI:GetButtonFromCache(bagID, slotID)
	if not bagID or not slotID then return nil end

	self:UpdateButtonCache()
	local key = bagID .. "_" .. slotID
	return self.buttonCache[key]
end

-- Main function to find item button (use this one)
function DOKI:FindItemButton(bagID, slotID)
	-- Try cache first (fastest)
	local button = self:GetButtonFromCache(bagID, slotID)
	if button and button:IsVisible() then
		return button
	end

	-- Fall back to real-time enumeration
	return self:FindItemButtonModern(bagID, slotID)
end

-- Find merchant button (unchanged)
function DOKI:FindMerchantButton(merchantIndex)
	return _G["MerchantItem" .. merchantIndex .. "ItemButton"]
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
		print(string.format("|cffff69b4DOKI|r Created %d overlays for uncollected items", overlayCount))
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
-- Initialize the modern overlay system
function DOKI:InitializeOverlaySystem()
	self:InitializeButtonTracking()
	-- Hook container frame show events to refresh overlays when bags are opened
	self:HookContainerFrameEvents()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Modern overlay system initialized")
	end
end

-- Hook container frame show events - FIXED to scan before updating overlays
function DOKI:HookContainerFrameEvents()
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
		print("|cffff69b4DOKI|r Hooked container frame show events")
	end
end

-- Diagnostic function to test button finding
function DOKI:TestButtonFinding()
	if not self.db or not self.db.debugMode then
		print("|cffff69b4DOKI|r Enable debug mode first with /doki debug")
		return
	end

	print("|cffff69b4DOKI|r Testing button finding methods...")
	-- Test if modern functions exist
	print("ContainerFrameCombinedBags:", ContainerFrameCombinedBags and "exists" or "missing")
	print("ContainerFrameUtil_EnumerateContainerFrames:",
		ContainerFrameUtil_EnumerateContainerFrames and "exists" or "missing")
	print("ContainerFrameUtil_GetItemButtonAndContainer:",
		ContainerFrameUtil_GetItemButtonAndContainer and "exists" or "missing")
	print("ContainerFrameContainer:", ContainerFrameContainer and "exists" or "missing")
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
