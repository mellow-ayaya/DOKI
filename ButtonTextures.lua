-- DOKI Button-Internal Texture System - ENHANCED SURGICAL UPDATES
-- Responsive updates with immediate item movement tracking
local addonName, DOKI = ...
-- Texture management
DOKI.buttonTextures = {}                                                  -- Track textures by button reference
DOKI.texturePool = {}                                                     -- Pool of reusable texture objects
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected" -- Path to indicator texture
-- Enhanced surgical update tracking
DOKI.lastButtonSnapshot = {}                                              -- Track what items are on what buttons
DOKI.buttonItemMap = {}                                                   -- Map buttons to their current item IDs
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
		itemID = nil, -- Track what item this indicator is for
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
		self.itemID = nil
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
	textureData.itemID = nil
	-- Remove from tracking
	self.buttonTextures[button] = nil
	self.buttonItemMap[button] = nil
	-- Return to pool
	table.insert(self.texturePool, textureData)
end

-- ===== ENHANCED SURGICAL UPDATE SYSTEM =====
-- Create a snapshot of current button-to-item mapping
function DOKI:CreateButtonSnapshot()
	local snapshot = {}
	-- Snapshot ElvUI buttons
	if ElvUI and self:IsElvUIBagVisible() then
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
						for _, buttonName in ipairs(possibleNames) do
							local button = _G[buttonName]
							if button and button:IsVisible() then
								snapshot[button] = itemInfo.itemID
								break
							end
						end
					end
				end
			end
		end
	end

	-- Snapshot Blizzard buttons
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					-- Extract item ID from button
					local itemData = self:ExtractItemFromButton(itemButton)
					if itemData and itemData.itemID then
						snapshot[itemButton] = itemData.itemID
					end
				end
			end
		end
	end

	-- Snapshot Merchant buttons
	if MerchantFrame and MerchantFrame:IsVisible() then
		for i = 1, 10 do
			local buttonName = "MerchantItem" .. i .. "ItemButton"
			local button = _G[buttonName]
			if button and button:IsVisible() then
				local itemLink = GetMerchantItemLink(i)
				if itemLink then
					local itemID = self:GetItemID(itemLink)
					if itemID then
						snapshot[button] = itemID
					end
				end
			end
		end
	end

	return snapshot
end

-- Enhanced surgical update - this is called by the main surgical update system
function DOKI:ProcessSurgicalUpdate()
	local currentSnapshot = self:CreateButtonSnapshot()
	local changes = {
		removed = {}, -- Buttons that lost items
		added = {}, -- Buttons that gained items
		changed = {}, -- Buttons that changed items
	}
	-- Find buttons that lost items or changed items
	for button, oldItemID in pairs(self.lastButtonSnapshot or {}) do
		local newItemID = currentSnapshot[button]
		if not newItemID then
			-- Button lost its item
			table.insert(changes.removed, { button = button, oldItemID = oldItemID })
		elseif newItemID ~= oldItemID then
			-- Button changed items
			table.insert(changes.changed, { button = button, oldItemID = oldItemID, newItemID = newItemID })
		end
	end

	-- Find buttons that gained items
	for button, newItemID in pairs(currentSnapshot) do
		local oldItemID = self.lastButtonSnapshot and self.lastButtonSnapshot[button]
		if not oldItemID then
			-- Button gained an item
			table.insert(changes.added, { button = button, newItemID = newItemID })
		end
	end

	-- Apply surgical updates
	local updateCount = 0
	-- Remove indicators from buttons that lost items
	for _, change in ipairs(changes.removed) do
		self:RemoveButtonIndicator(change.button)
		updateCount = updateCount + 1
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Removed indicator: button lost item %d", change.oldItemID))
		end
	end

	-- Update buttons that changed items
	for _, change in ipairs(changes.changed) do
		self:RemoveButtonIndicator(change.button)
		local itemData = self:GetItemDataForID(change.newItemID)
		if itemData and not itemData.isCollected then
			self:AddButtonIndicator(change.button, itemData)
		end

		updateCount = updateCount + 1
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Changed indicator: %d → %d", change.oldItemID, change.newItemID))
		end
	end

	-- Add indicators to buttons that gained items
	for _, change in ipairs(changes.added) do
		local itemData = self:GetItemDataForID(change.newItemID)
		if itemData and not itemData.isCollected then
			self:AddButtonIndicator(change.button, itemData)
			updateCount = updateCount + 1
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Added indicator: button gained item %d", change.newItemID))
			end
		end
	end

	-- Update snapshot
	self.lastButtonSnapshot = currentSnapshot
	if self.db and self.db.debugMode and updateCount > 0 then
		print(string.format("|cffff69b4DOKI|r Enhanced surgical update: %d changes (%d removed, %d added, %d changed)",
			updateCount, #changes.removed, #changes.added, #changes.changed))
	end

	return updateCount
end

-- Legacy function name compatibility - redirect to the new enhanced function
function DOKI:SurgicalUpdate()
	return self:ProcessSurgicalUpdate()
end

-- Get item data for surgical updates
function DOKI:GetItemDataForID(itemID)
	if not itemID or not self:IsCollectibleItem(itemID) then return nil end

	local isCollected, showYellowD = self:IsItemCollected(itemID, nil)
	return {
		itemID = itemID,
		itemLink = nil,
		isCollected = isCollected,
		showYellowD = showYellowD,
		frameType = "surgical",
	}
end

-- Extract item from button (simplified for enhanced responsiveness)
function DOKI:ExtractItemFromButton(button)
	if not button then return nil end

	local itemID = nil
	-- Try direct methods
	if button.GetItemID then
		local success, id = pcall(button.GetItemID, button)
		if success and id then itemID = id end
	end

	if not itemID and button.GetItem then
		local success, item = pcall(button.GetItem, button)
		if success and item then
			if type(item) == "number" then
				itemID = item
			elseif type(item) == "string" then
				itemID = self:GetItemID(item)
			end
		end
	end

	-- Try properties
	if not itemID then
		itemID = button.itemID or button.id
	end

	if not itemID then return nil end

	local isCollected, showYellowD = self:IsItemCollected(itemID, nil)
	return {
		itemID = itemID,
		isCollected = isCollected,
		showYellowD = showYellowD,
		frameType = "button",
	}
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

	-- Show the indicator and track item
	textureData:Show()
	textureData.itemID = itemData.itemID
	self.buttonItemMap[button] = itemData.itemID
	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
		local buttonName = ""
		local nameSuccess, name = pcall(button.GetName, button)
		if nameSuccess and name then
			buttonName = name
		else
			buttonName = "unnamed"
		end

		print(string.format("|cffff69b4DOKI|r Enhanced: Added indicator for %s (ID: %d) on %s",
			itemName, itemData.itemID, buttonName))
	end

	return true
end

-- Remove indicator from a button
function DOKI:RemoveButtonIndicator(button)
	if not button then return false end

	local textureData = self.buttonTextures[button]
	if textureData and textureData.isActive then
		textureData:Hide()
		self.buttonItemMap[button] = nil
		return true
	end

	return false
end

-- Clear all button indicators (for manual commands only)
function DOKI:ClearAllButtonIndicators()
	local count = 0
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Manual clear all indicators")
	end

	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive then
			textureData:Hide()
			count = count + 1
		end
	end

	-- Clear tracking
	self.buttonItemMap = {}
	self.lastButtonSnapshot = {}
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cleared %d button indicators", count))
	end

	return count
end

-- Clean up invalid button textures
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

	-- Check if indicator already exists for this item
	local existingTexture = self.buttonTextures[frame]
	if existingTexture and existingTexture.isActive and existingTexture.itemID == itemData.itemID then
		-- Same item, same indicator - no change needed
		return 0
	end

	-- Add or update button indicator
	local success = self:AddButtonIndicator(frame, itemData)
	return success and 1 or 0
end

-- ===== INITIALIZATION AND CLEANUP =====
-- Initialize enhanced button texture system
function DOKI:InitializeButtonTextureSystem()
	-- Initialize storage
	self.buttonTextures = self.buttonTextures or {}
	self.texturePool = self.texturePool or {}
	self.lastButtonSnapshot = {}
	self.buttonItemMap = {}
	-- Validate our texture file
	self:ValidateTexture()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced surgical button texture system initialized")
		print("  |cff00ff00•|r Immediate response to ITEM_UNLOCKED events")
		print("  |cff00ff00•|r Smart throttling to prevent update spam")
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

	-- Clean up pools and tracking
	for _, textureData in ipairs(self.texturePool) do
		if textureData.texture then
			textureData.texture:SetParent(nil)
		end
	end

	self.buttonTextures = {}
	self.texturePool = {}
	self.lastButtonSnapshot = {}
	self.buttonItemMap = {}
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced button texture system cleaned up")
	end
end

-- ===== BACKWARDS COMPATIBILITY =====
-- Replace the old overlay functions with button texture equivalents
function DOKI:ClearUniversalOverlays()
	-- For surgical system, just do cleanup
	return self:CleanupButtonTextures()
end

function DOKI:ClearAllOverlays()
	return self:ClearAllButtonIndicators()
end

-- ===== UTILITY FUNCTIONS =====
function DOKI:GetItemID(itemLink)
	if not itemLink then return nil end

	if type(itemLink) == "number" then return itemLink end

	if type(itemLink) == "string" then
		local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
		return itemID
	end

	return nil
end

function DOKI:IsCollectibleItem(itemID)
	if not itemID then return false end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then return false end

	-- Mount items (class 15, subclass 5)
	if classID == 15 and subClassID == 5 then return true end

	-- Pet items (class 15, subclass 2)
	if classID == 15 and subClassID == 2 then return true end

	-- Toy items
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then return true end

	-- Transmog items (weapons class 2, armor class 4)
	if classID == 2 or classID == 4 then
		if itemEquipLoc then
			local nonTransmogSlots = {
				"INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET",
				"INVTYPE_HOLDABLE", "INVTYPE_BAG", "INVTYPE_QUIVER",
			}
			for _, slot in ipairs(nonTransmogSlots) do
				if itemEquipLoc == slot then return false end
			end

			return true
		end
	end

	return false
end

function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID then return false, false end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then return false, false end

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

	-- Check transmog - simplified for surgical system
	if classID == 2 or classID == 4 then
		return self:IsTransmogCollected(itemID, itemLink)
	end

	return false, false
end

function DOKI:IsMountCollected(itemID)
	if not itemID or not C_MountJournal then return false end

	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then return false end

	local spellIDNum = tonumber(spellID)
	return spellIDNum and IsSpellKnown(spellIDNum) or false
end

function DOKI:IsPetCollected(itemID)
	if not itemID or not C_PetJournal then return false end

	local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, obtainable, displayID, speciesID =
			C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then return false end

	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	if not itemModifiedAppearanceID then return false, false end

	-- Check if THIS specific variant is collected
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then return true, false end

	-- Check if we have other sources
	local showYellowD = false
	if itemAppearanceID then
		local success, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
		if success and sourceIDs then
			for _, sourceID in ipairs(sourceIDs) do
				if sourceID ~= itemModifiedAppearanceID then
					local success2, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
					if success2 and hasSource then
						showYellowD = true
						break
					end
				end
			end
		end
	end

	return false, showYellowD
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

-- ===== ENHANCED DEBUG FUNCTIONS =====
function DOKI:DebugButtonTextures()
	print("|cffff69b4DOKI|r === ENHANCED SURGICAL BUTTON TEXTURE DEBUG ===")
	print(string.format("Texture file validated: %s", tostring(self.textureValidated)))
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
	print(string.format("Button tracking: %d buttons in snapshot",
		self.lastButtonSnapshot and self:TableCount(self.lastButtonSnapshot) or 0))
	-- Enhanced system info
	print("|cff00ff00Enhanced features:|r")
	print("  - Immediate ITEM_UNLOCKED event response")
	print("  - 0.5s regular update interval")
	print(string.format("  - %.1fs throttling between updates", self.surgicalUpdateThrottleTime or 0.1))
	if self.immediateUpdates and self.immediateUpdates > 0 then
		print(string.format("  - %d immediate updates performed", self.immediateUpdates))
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
end

function DOKI:TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do count = count + 1 end

	return count
end

function DOKI:TestButtonTextureCreation()
	print("|cffff69b4DOKI|r Testing enhanced surgical button texture system...")
	if not self:ValidateTexture() then
		print("|cffff69b4DOKI|r Cannot test - texture validation failed")
		return
	end

	-- Find a visible button
	local testButton = nil
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

	if testButton then
		local testData = {
			itemID = 12345,
			isCollected = false,
			showYellowD = false,
			frameType = "test",
		}
		local success = self:AddButtonIndicator(testButton, testData)
		if success then
			print("|cffff69b4DOKI|r Test indicator created (orange)")
			print("|cffff69b4DOKI|r Try moving items to test enhanced immediate response")
			print("  |cff00ff00•|r Items should follow immediately on drop")
			print("  |cff00ff00•|r No flicker or delay with ITEM_UNLOCKED events")
		else
			print("|cffff69b4DOKI|r Failed to create test indicator")
		end
	else
		print("|cffff69b4DOKI|r No suitable button found - open bags first")
	end
end
