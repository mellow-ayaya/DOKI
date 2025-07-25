-- DOKI Button-Internal Texture System
-- Replace external overlays with integrated button textures
local addonName, DOKI = ...
-- Texture management
DOKI.buttonTextures = {}                                                  -- Track textures by button reference
DOKI.texturePool = {}                                                     -- Pool of reusable texture objects
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected" -- Path to indicator texture
-- ===== TEXTURE CREATION AND MANAGEMENT =====
-- Validate that our texture file exists
function DOKI:ValidateTexture()
	if not self.textureValidated then
		-- Create a temporary texture to test if file exists
		local testTexture = UIParent:CreateTexture()
		testTexture:SetTexture(self.indicatorTexturePath)
		local textureFile = testTexture:GetTexture()
		if textureFile then
			if self.db and self.db.debugMode then
				print("|cffff69b4DOKI|r Texture file found: " .. self.indicatorTexturePath)
			end

			self.textureValidated = true
		else
			print("|cffff69b4DOKI|r WARNING: Texture file not found: " .. self.indicatorTexturePath .. ".tga")
			print("|cffff69b4DOKI|r Please ensure uncollected.tga is in your DOKI\\Media addon folder")
			self.textureValidated = false
		end

		-- Clean up test texture
		testTexture:SetParent(nil)
	end

	return self.textureValidated
end

-- Get or create a texture for a button
function DOKI:GetButtonTexture(button)
	if not button or type(button) ~= "table" then return nil end

	-- Check if button already has our texture
	if self.buttonTextures[button] then
		return self.buttonTextures[button]
	end

	-- Try to get from pool first
	local textureData = table.remove(self.texturePool)
	if not textureData then
		textureData = self:CreateButtonTexture()
	end

	if not textureData then return nil end

	-- Configure texture for this button
	textureData.texture:SetParent(button)
	textureData.texture:SetDrawLayer("OVERLAY", 7) -- High sublevel to appear on top
	-- Position at top-left corner of item icon
	local iconTexture = self:FindButtonIcon(button)
	if iconTexture then
		textureData.texture:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 2, -2)
	else
		-- Fallback to button positioning
		textureData.texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
	end

	textureData.texture:SetSize(16, 16)
	textureData.button = button
	-- Store reference
	self.buttonTextures[button] = textureData
	return textureData
end

-- Create a new texture object
function DOKI:CreateButtonTexture()
	-- Validate our texture file exists
	if not self:ValidateTexture() then
		return nil
	end

	-- Create texture on a temporary parent (will be reparented when used)
	local texture = UIParent:CreateTexture(nil, "OVERLAY")
	if not texture then return nil end

	-- Set the indicator texture
	texture:SetTexture(self.indicatorTexturePath)
	-- Ensure texture loaded properly
	if not texture:GetTexture() then
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Failed to load texture: " .. self.indicatorTexturePath)
		end

		return nil
	end

	local textureData = {
		texture = texture,
		button = nil,
		isActive = false,
	}
	-- Function to set color (using vertex coloring)
	textureData.SetColor = function(self, r, g, b)
		self.texture:SetVertexColor(r, g, b, 1.0)
	end
	-- Function to show/hide
	textureData.Show = function(self)
		self.texture:Show()
		self.isActive = true
	end
	textureData.Hide = function(self)
		self.texture:Hide()
		self.isActive = false
	end
	return textureData
end

-- Find the icon texture within a button
function DOKI:FindButtonIcon(button)
	if not button then return nil end

	-- Common icon texture names for different button types
	local iconNames = {
		"icon", "Icon", "ItemIcon", "Texture", "NormalTexture",
	}
	-- Try to find icon by name
	for _, name in ipairs(iconNames) do
		local icon = button[name]
		if icon and icon.GetTexture then
			return icon
		end
	end

	-- Try to find icon by region scanning
	local regions = { button:GetRegions() }
	for _, region in ipairs(regions) do
		if region:GetObjectType() == "Texture" then
			local texture = region:GetTexture()
			if texture and texture ~= "" and not string.find(texture:lower(), "border") then
				return region
			end
		end
	end

	return nil
end

-- Release a button texture back to pool
function DOKI:ReleaseButtonTexture(button)
	local textureData = self.buttonTextures[button]
	if not textureData then return end

	-- Hide and reset
	textureData:Hide()
	textureData.texture:SetParent(UIParent)
	textureData.texture:ClearAllPoints()
	textureData.texture:SetVertexColor(1, 1, 1, 1) -- Reset to white
	textureData.button = nil
	-- Remove from tracking
	self.buttonTextures[button] = nil
	-- Return to pool
	table.insert(self.texturePool, textureData)
end

-- ===== INDICATOR MANAGEMENT =====
-- Add indicator to a button
function DOKI:AddButtonIndicator(button, itemData)
	if not button or not itemData or itemData.isCollected then return false end

	-- Validate button
	local success, isVisible = pcall(button.IsVisible, button)
	if not success or not isVisible then return false end

	-- Get or create texture for this button
	local textureData = self:GetButtonTexture(button)
	if not textureData then return false end

	-- Set appropriate color
	if itemData.showYellowD then
		textureData:SetColor(0.082, 0.671, 1.0) -- Blue (RGB 21, 171, 255)
	else
		textureData:SetColor(1.0, 0.573, 0.2) -- Orange (RGB 255, 146, 51)
	end

	-- Show the indicator
	textureData:Show()
	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
		local buttonName = ""
		local nameSuccess, name = pcall(button.GetName, button)
		if nameSuccess and name then
			buttonName = name
		else
			buttonName = "unnamed"
		end

		print(string.format("|cffff69b4DOKI|r Added button texture for %s (ID: %d) on %s [%s]",
			itemName, itemData.itemID, buttonName, itemData.frameType))
	end

	return true
end

-- Remove indicator from a button
function DOKI:RemoveButtonIndicator(button)
	if not button then return false end

	local textureData = self.buttonTextures[button]
	if textureData and textureData.isActive then
		textureData:Hide()
		return true
	end

	return false
end

-- Clear all button indicators
function DOKI:ClearAllButtonIndicators()
	local count = 0
	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive then
			textureData:Hide()
			count = count + 1
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cleared %d button indicators", count))
	end

	return count
end

-- Clean up invalid button textures (smarter than clearing all)
function DOKI:CleanupButtonTextures()
	local removedCount = 0
	local toRemove = {}
	for button, textureData in pairs(self.buttonTextures) do
		if not button then
			table.insert(toRemove, button)
			removedCount = removedCount + 1
		else
			-- Check if button is still visible
			local success, isVisible = pcall(button.IsVisible, button)
			if not success or not isVisible then
				table.insert(toRemove, button)
				removedCount = removedCount + 1
			end
		end
	end

	-- Remove invalid entries
	for _, button in ipairs(toRemove) do
		self:ReleaseButtonTexture(button)
	end

	if self.db and self.db.debugMode and removedCount > 0 then
		print(string.format("|cffff69b4DOKI|r Cleaned up %d invalid button textures", removedCount))
	end

	return removedCount
end

-- Smart clear function that only clears when actually needed
function DOKI:SmartClearForEvent(eventName)
	-- Events that should trigger full clears (major changes)
	local majorEvents = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"ITEM_UNLOCKED", -- Item movement completed
	}
	-- Events that should only trigger cleanup (minor changes)
	local minorEvents = {
		"BAG_UPDATE_COOLDOWN",
		"BAG_SLOT_FLAGS_UPDATED",
		"INVENTORY_SEARCH_UPDATE",
	}
	for _, majorEvent in ipairs(majorEvents) do
		if eventName == majorEvent then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Major event %s: clearing indicators", eventName))
			end

			return self:ClearAllButtonIndicators()
		end
	end

	for _, minorEvent in ipairs(minorEvents) do
		if eventName == minorEvent then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Minor event %s: cleanup only", eventName))
			end

			return self:CleanupButtonTextures()
		end
	end

	-- Default: cleanup only for unknown events
	return self:CleanupButtonTextures()
end

-- ===== INTEGRATION WITH EXISTING SCANNING SYSTEM =====
-- Enhanced version of CreateUniversalOverlay that uses button textures
function DOKI:CreateUniversalIndicator(frame, itemData)
	if itemData.isCollected then
		-- If item is collected, remove any existing indicator
		self:RemoveButtonIndicator(frame)
		return 0
	end

	-- Enhanced frame validation
	if not frame or type(frame) ~= "table" then return 0 end

	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Check if indicator already exists and is correct
	local existingTexture = self.buttonTextures[frame]
	if existingTexture and existingTexture.isActive then
		-- Validate that it's showing the right color
		local shouldShowYellow = itemData.showYellowD
		-- For now, just assume it's correct to avoid flicker
		-- We could add color validation here if needed
		return 0 -- Already has correct indicator
	end

	-- Add button indicator instead of overlay
	local success = self:AddButtonIndicator(frame, itemData)
	return success and 1 or 0
end

-- Hook into button lifecycle for ElvUI
function DOKI:HookElvUIButtonLifecycle()
	if not ElvUI then return end

	local E = ElvUI[1]
	if not E then return end

	local B = E:GetModule("Bags", true)
	if not B then return end

	-- Hook button creation/update
	if B.UpdateSlot and not self.elvUISlotHooked then
		local originalUpdateSlot = B.UpdateSlot
		B.UpdateSlot = function(self, frame, bagID, slotID)
			local result = originalUpdateSlot(self, frame, bagID, slotID)
			-- Clear any existing indicator when slot updates
			if frame and frame.itemButton then
				DOKI:RemoveButtonIndicator(frame.itemButton)
			end

			-- Trigger rescan after slot update
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.05, function()
					DOKI:UniversalItemScan()
				end)
			end

			return result
		end
		self.elvUISlotHooked = true
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r ElvUI slot update hook installed")
		end
	end
end

-- Hook into Blizzard button lifecycle
function DOKI:HookBlizzardButtonLifecycle()
	-- Hook container frame updates
	if not self.blizzardContainerHooked then
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("BAG_UPDATE_DELAYED")
		frame:RegisterEvent("ITEM_LOCK_CHANGED")
		frame:SetScript("OnEvent", function(self, event, ...)
			if event == "BAG_UPDATE_DELAYED" then
				-- Clear indicators that might be stale
				C_Timer.After(0.05, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:CleanupButtonTextures()
						DOKI:UniversalItemScan()
					end
				end)
			elseif event == "ITEM_LOCK_CHANGED" then
				-- Item moved, clear stale indicators quickly
				C_Timer.After(0.02, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:ClearAllButtonIndicators()
						C_Timer.After(0.03, function()
							DOKI:UniversalItemScan()
						end)
					end
				end)
			end
		end)
		self.blizzardContainerHooked = true
	end
end

-- Modified scanning functions to use button textures with smart clearing
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
			else
				-- No item on this button, remove any indicator
				self:RemoveButtonIndicator(button)
			end
		end
	end

	-- Clean up indicators on merchant buttons that are no longer visible or have no items
	for button, textureData in pairs(self.buttonTextures) do
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
	-- Scan ElvUI bags
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				if debugMode then
					print("|cffff69b4DOKI|r Scanning ElvUI bags with button textures...")
				end

				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID then
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
										end

										break
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
			end
		end
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
					end
				end
			end
		end
	end

	-- Clean up indicators on bag buttons that no longer have items (only if bags are visible)
	if (ElvUI and self:IsElvUIBagVisible()) or (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		for button, textureData in pairs(self.buttonTextures) do
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

-- ===== INITIALIZATION AND CLEANUP =====
-- Initialize button texture system
function DOKI:InitializeButtonTextureSystem()
	-- Initialize storage
	self.buttonTextures = self.buttonTextures or {}
	self.texturePool = self.texturePool or {}
	-- Validate our texture file
	self:ValidateTexture()
	-- Hook button lifecycle
	self:HookElvUIButtonLifecycle()
	self:HookBlizzardButtonLifecycle()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Button texture system initialized")
	end
end

-- Cleanup function for addon disable/reload
function DOKI:CleanupButtonTextureSystem()
	-- Clear all indicators
	self:ClearAllButtonIndicators()
	-- Release all textures
	for button, textureData in pairs(self.buttonTextures) do
		self:ReleaseButtonTexture(button)
	end

	-- Clean up pools
	for _, textureData in ipairs(self.texturePool) do
		if textureData.texture then
			textureData.texture:SetParent(nil)
		end
	end

	self.buttonTextures = {}
	self.texturePool = {}
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Button texture system cleaned up")
	end
end

-- ===== BACKWARDS COMPATIBILITY =====
-- Replace the old overlay functions with button texture equivalents
function DOKI:ClearUniversalOverlays()
	-- Instead of clearing all indicators, just clean up invalid ones
	return self:CleanupButtonTextures()
end

function DOKI:ClearAllOverlays()
	-- Only clear all when explicitly requested (like /doki clear command)
	return self:ClearAllButtonIndicators()
end

-- ===== DEBUG AND DIAGNOSTIC FUNCTIONS =====
function DOKI:DebugButtonTextures()
	print("|cffff69b4DOKI|r === BUTTON TEXTURE DEBUG ===")
	-- Check texture validation
	print(string.format("Texture file validated: %s", tostring(self.textureValidated)))
	print(string.format("Texture path: %s", self.indicatorTexturePath))
	local activeCount = 0
	local totalCount = 0
	for button, textureData in pairs(self.buttonTextures) do
		totalCount = totalCount + 1
		if textureData.isActive then
			activeCount = activeCount + 1
		end
	end

	print(string.format("Button textures: %d total, %d active", totalCount, activeCount))
	print(string.format("Texture pool size: %d", #self.texturePool))
	-- Show some examples
	local count = 0
	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive and count < 3 then
			local buttonName = ""
			local nameSuccess, name = pcall(button.GetName, button)
			if nameSuccess and name then
				buttonName = name
			else
				buttonName = "unnamed"
			end

			-- Check if texture is properly loaded
			local textureFile = textureData.texture:GetTexture()
			print(string.format("  Active indicator on: %s (texture: %s)", buttonName, textureFile or "nil"))
			count = count + 1
		end
	end

	if activeCount > 3 then
		print(string.format("  ... and %d more", activeCount - 3))
	end

	print("|cffff69b4DOKI|r === END BUTTON TEXTURE DEBUG ===")
end

function DOKI:TestButtonTextureCreation()
	print("|cffff69b4DOKI|r Testing button texture creation...")
	-- Validate texture first
	if not self:ValidateTexture() then
		print("|cffff69b4DOKI|r Cannot test - texture validation failed")
		return
	end

	-- Find a visible button to test on
	local testButton = nil
	-- Try to find an ElvUI button
	if ElvUI and self:IsElvUIBagVisible() then
		for bagID = 0, 1 do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local buttonName = string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID)
					local button = _G[buttonName]
					if button and button:IsVisible() then
						testButton = button
						break
					end
				end

				if testButton then break end
			end
		end
	end

	-- Try Blizzard bags if ElvUI not found
	if not testButton and ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					testButton = itemButton
					break
				end
			end
		end
	end

	if testButton then
		local testData = {
			itemID = 12345,
			isCollected = false,
			showYellowD = false,
			frameType = "test",
		}
		local success = self:AddButtonIndicator(testButton, testData)
		if success then
			print("|cffff69b4DOKI|r Test indicator created successfully (orange icon)")
			print("|cffff69b4DOKI|r Use /doki clear to remove test indicators")
		else
			print("|cffff69b4DOKI|r Failed to create test indicator")
		end
	else
		print("|cffff69b4DOKI|r No suitable button found for testing")
		print("|cffff69b4DOKI|r Try opening your bags first")
	end
end
