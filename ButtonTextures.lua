-- DOKI Button Texture System - FIXED: Empty Slot Detection, Surgical Updates, Merchant Selling
local addonName, DOKI = ...
-- Storage
DOKI.buttonTextures = {}
DOKI.texturePool = {}
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected"
-- FIXED: Enhanced surgical update tracking for proper empty slot detection
DOKI.lastButtonSnapshot = {}
DOKI.buttonItemMap = {}
-- ===== TEXTURE CREATION =====
function DOKI:ValidateTexture()
	if not self.textureValidated then
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
			self.textureValidated = false
		end

		testTexture:SetParent(nil)
	end

	return self.textureValidated
end

function DOKI:GetButtonTexture(button)
	if not button or type(button) ~= "table" then return nil end

	if self.buttonTextures[button] then
		return self.buttonTextures[button]
	end

	local textureData = table.remove(self.texturePool)
	if not textureData then
		textureData = self:CreateButtonTexture()
	end

	if not textureData then return nil end

	-- Configure for this button
	textureData.texture:SetParent(button)
	textureData.texture:SetDrawLayer("OVERLAY", 7)
	-- Position at top-right corner
	local iconTexture = self:FindButtonIcon(button)
	if iconTexture then
		textureData.texture:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 2, 2)
	else
		textureData.texture:SetPoint("TOPRIGHT", button, "TOPRIGHT", 2, 2)
	end

	textureData.texture:SetSize(12, 12)
	textureData.button = button
	self.buttonTextures[button] = textureData
	return textureData
end

function DOKI:CreateButtonTexture()
	if not self:ValidateTexture() then
		return nil
	end

	local texture = UIParent:CreateTexture(nil, "OVERLAY")
	if not texture then return nil end

	texture:SetTexture(self.indicatorTexturePath)
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
		itemID = nil,
		itemLink = nil, -- ADDED: Track itemLink for battlepets
	}
	textureData.SetColor = function(self, r, g, b)
		self.texture:SetVertexColor(r, g, b, 1.0)
	end
	textureData.Show = function(self)
		self.texture:Show()
		self.isActive = true
	end
	textureData.Hide = function(self)
		self.texture:Hide()
		self.isActive = false
		self.itemID = nil
		self.itemLink = nil -- ADDED: Clear itemLink too
	end
	return textureData
end

function DOKI:FindButtonIcon(button)
	if not button then return nil end

	local iconNames = {
		"icon", "Icon", "ItemIcon", "Texture", "NormalTexture",
	}
	for _, name in ipairs(iconNames) do
		local icon = button[name]
		if icon and icon.GetTexture then
			return icon
		end
	end

	local regions = { button:GetRegions() }
	for _, region in ipairs(regions) do
		if region:GetObjectType() == "Texture" then
			local textureFile = region:GetTexture()
			-- FIXED: Check if textureFile is valid and region has GetTexture method
			if textureFile and textureFile ~= "" and region.GetTexture then
				local textureName = tostring(textureFile):lower()
				if not string.find(textureName, "border") and not string.find(textureName, "background") then
					return region
				end
			end
		end
	end

	return nil
end

function DOKI:ReleaseButtonTexture(button)
	local textureData = self.buttonTextures[button]
	if not textureData then return end

	textureData:Hide()
	textureData.texture:SetParent(UIParent)
	textureData.texture:ClearAllPoints()
	textureData.texture:SetVertexColor(1, 1, 1, 1)
	textureData.button = nil
	textureData.itemID = nil
	textureData.itemLink = nil -- ADDED: Clear itemLink
	self.buttonTextures[button] = nil
	self.buttonItemMap[button] = nil
	table.insert(self.texturePool, textureData)
end

-- ===== ENHANCED SNAPSHOT SYSTEM WITH PROPER EMPTY SLOT DETECTION =====
function DOKI:CreateButtonSnapshot()
	local snapshot = {}
	-- FIXED: Enhanced function to add items to snapshot with better empty slot tracking
	local function addToSnapshot(button, itemID, itemLink)
		if button then
			if itemID and itemID ~= "EMPTY_SLOT" then
				snapshot[button] = {
					itemID = itemID,
					itemLink = itemLink,
					hasItem = true,
				}
			else
				-- FIXED: Track empty slots explicitly
				snapshot[button] = {
					itemID = nil,
					itemLink = nil,
					hasItem = false,
					isEmpty = true,
				}
			end
		end
	end

	-- ElvUI buttons
	if ElvUI and self:IsElvUIBagVisible() then
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					local possibleNames = {
						string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
					}
					for _, buttonName in ipairs(possibleNames) do
						local button = _G[buttonName]
						if button and button:IsVisible() then
							if itemInfo and itemInfo.itemID then
								addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
							else
								-- FIXED: Track empty bag slots
								addToSnapshot(button, nil, nil)
							end

							break
						end
					end
				end
			end
		end
	end

	-- Blizzard combined bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					-- Find matching button
					local button = nil
					if ContainerFrameCombinedBags.EnumerateValidItems then
						for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
							if itemButton and itemButton:IsVisible() then
								local buttonBagID, buttonSlotID = nil, nil
								if itemButton.GetBagID and itemButton.GetID then
									local bagIDRetrievalSuccess, retrievedBagID = pcall(itemButton.GetBagID, itemButton)
									local slotIDRetrievalSuccess, retrievedBagID = pcall(itemButton.GetID, itemButton)
									if bagIDRetrievalSuccess and slotIDRetrievalSuccess then
										buttonBagID, buttonSlotID = retrievedBagID, retrievedBagID
									end
								end

								if buttonBagID == bagID and buttonSlotID == slotID then
									button = itemButton
									break
								end
							end
						end
					end

					if button then
						if itemInfo and itemInfo.itemID then
							addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
						else
							-- FIXED: Track empty bag slots in combined bags
							addToSnapshot(button, nil, nil)
						end
					end
				end
			end
		end
	end

	-- Individual container frames
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					local possibleNames = {
						string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
						string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
					}
					for _, buttonName in ipairs(possibleNames) do
						local button = _G[buttonName]
						if button and button:IsVisible() then
							if itemInfo and itemInfo.itemID then
								addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
							else
								-- FIXED: Track empty bag slots in individual containers
								addToSnapshot(button, nil, nil)
							end

							break
						end
					end
				end
			end
		end
	end

	-- ENHANCED: Merchant buttons with proper empty slot detection
	if MerchantFrame and MerchantFrame:IsVisible() then
		-- Scan only the visible merchant button slots
		for i = 1, 12 do -- Check up to 12 merchant slots
			local possibleButtonNames = {
				string.format("MerchantItem%dItemButton", i),
				string.format("MerchantItem%d", i),
			}
			for _, buttonName in ipairs(possibleButtonNames) do
				local button = _G[buttonName]
				if button and button:IsVisible() then
					-- Try to get item info directly from the button
					local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
					if itemID == "EMPTY_SLOT" or not itemID then
						-- FIXED: Properly track empty merchant slots
						addToSnapshot(button, nil, nil)
					else
						addToSnapshot(button, itemID, itemLink)
					end

					break
				end
			end
		end
	end

	return snapshot
end

-- ===== ENHANCED SURGICAL UPDATE PROCESSING WITH RAPID-SALE SAFEGUARDS =====
function DOKI:ProcessSurgicalUpdate()
	local currentSnapshot = self:CreateButtonSnapshot()
	local changes = {
		removed = {},
		added = {},
		changed = {},
	}
	-- ADDED: Force cleanup of any indicators on empty slots before comparison
	local cleanedIndicators = 0
	for button, textureData in pairs(self.buttonTextures or {}) do
		if textureData.isActive then
			-- Check if this button is now empty in current snapshot
			local currentButtonData = currentSnapshot[button]
			if currentButtonData and currentButtonData.isEmpty then
				if self:RemoveButtonIndicator(button) then
					cleanedIndicators = cleanedIndicators + 1
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Force cleaned indicator from empty slot"))
					end
				end
			end
		end
	end

	-- FIXED: Enhanced comparison that properly handles empty slots and item changes
	local function itemsEqual(oldItem, newItem)
		-- Both nil/empty
		if not oldItem and not newItem then return true end

		-- One nil, one not
		if not oldItem or not newItem then return false end

		-- Both marked as empty
		if oldItem.isEmpty and newItem.isEmpty then return true end

		-- One empty, one not
		if oldItem.isEmpty ~= newItem.isEmpty then return false end

		-- Both have items - compare them
		if oldItem.hasItem and newItem.hasItem then
			-- Different item IDs
			if oldItem.itemID ~= newItem.itemID then return false end

			-- For battlepets, also compare itemLinks (since same itemID can have different species)
			if oldItem.itemLink and newItem.itemLink then
				if string.find(oldItem.itemLink, "battlepet:") or string.find(newItem.itemLink, "battlepet:") then
					return oldItem.itemLink == newItem.itemLink
				end
			end

			return true
		end

		-- One has item, one doesn't
		return oldItem.hasItem == newItem.hasItem
	end

	-- FIXED: Better detection of buttons that lost items or changed items
	for button, oldItemData in pairs(self.lastButtonSnapshot or {}) do
		local newItemData = currentSnapshot[button]
		if not newItemData then
			-- Button disappeared entirely
			table.insert(changes.removed, { button = button, oldItemData = oldItemData })
		elseif not itemsEqual(oldItemData, newItemData) then
			-- Button content changed
			table.insert(changes.changed, { button = button, oldItemData = oldItemData, newItemData = newItemData })
		end
	end

	-- FIXED: Better detection of buttons that gained items
	for button, newItemData in pairs(currentSnapshot) do
		local oldItemData = self.lastButtonSnapshot and self.lastButtonSnapshot[button]
		if not oldItemData then
			-- New button appeared
			table.insert(changes.added, { button = button, newItemData = newItemData })
		end
	end

	-- Apply surgical updates
	local updateCount = 0
	-- Remove indicators from buttons that lost items or became empty
	for _, change in ipairs(changes.removed) do
		if self:RemoveButtonIndicator(change.button) then
			updateCount = updateCount + 1
			if self.db and self.db.debugMode then
				local extraInfo = self:GetItemDebugInfo(change.oldItemData)
				print(string.format("|cffff69b4DOKI|r Removed indicator: button lost item %s%s",
					tostring(change.oldItemData.itemID or "unknown"), extraInfo))
			end
		end
	end

	-- Update buttons that changed items
	for _, change in ipairs(changes.changed) do
		-- Always remove old indicator first
		self:RemoveButtonIndicator(change.button)
		-- Only add new indicator if the new item exists and needs an indicator
		if change.newItemData.hasItem and not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and (not itemData.isCollected or itemData.isPartiallyCollected) then
				if self:AddButtonIndicator(change.button, itemData) then
					updateCount = updateCount + 1
				end
			end
		end

		if self.db and self.db.debugMode then
			local oldExtra = self:GetItemDebugInfo(change.oldItemData)
			local newExtra = self:GetItemDebugInfo(change.newItemData)
			local oldItemID = change.oldItemData.itemID or (change.oldItemData.isEmpty and "empty" or "unknown")
			local newItemID = change.newItemData.isEmpty and "empty" or (change.newItemData.itemID or "unknown")
			print(string.format("|cffff69b4DOKI|r Changed indicator: %s%s -> %s%s",
				tostring(oldItemID), oldExtra, tostring(newItemID), newExtra))
		end
	end

	-- Add indicators to buttons that gained items
	for _, change in ipairs(changes.added) do
		-- Only add indicator if the new item exists and needs an indicator
		if change.newItemData.hasItem and not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and (not itemData.isCollected or itemData.isPartiallyCollected) then
				if self:AddButtonIndicator(change.button, itemData) then
					updateCount = updateCount + 1
					if self.db and self.db.debugMode then
						local extraInfo = self:GetItemDebugInfo(change.newItemData)
						print(string.format("|cffff69b4DOKI|r Added indicator: button gained item %s%s",
							tostring(change.newItemData.itemID), extraInfo))
					end
				end
			end
		end
	end

	-- Update snapshot
	self.lastButtonSnapshot = currentSnapshot
	-- ADDED: Always return total changes including forced cleanup
	local totalChanges = updateCount + cleanedIndicators
	if self.db and self.db.debugMode and totalChanges > 0 then
		print(string.format(
			"|cffff69b4DOKI|r Surgical update: %d changes (%d removed, %d added, %d changed, %d force cleaned)",
			totalChanges, #changes.removed, #changes.added, #changes.changed, cleanedIndicators))
	end

	return totalChanges
end

-- ADDED: Helper function to get debug info for items
function DOKI:GetItemDebugInfo(itemData)
	if not itemData then return "" end

	local extraInfo = ""
	if itemData.isEmpty then
		extraInfo = " (empty slot)"
	elseif itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
		extraInfo = " (battlepet)"
	elseif itemData.itemID and self:IsEnsembleItem(itemData.itemID) then
		extraInfo = " (ensemble)"
	end

	-- Check if this is a merchant button
	if itemData.button then
		local buttonName = ""
		local success, name = pcall(itemData.button.GetName, itemData.button)
		if success and name and string.find(name, "Merchant") then
			extraInfo = extraInfo .. " (merchant)"
		end
	end

	return extraInfo
end

-- ADDED: Enhanced item data retrieval for surgical updates (supports battlepets + ensembles)
function DOKI:GetItemDataForSurgicalUpdate(itemID, itemLink)
	-- FIXED: Handle empty slots - return nil so no indicator is created
	if itemID == "EMPTY_SLOT" or not itemID then return nil end

	-- ADDED: Handle caged pets first
	if itemLink then
		local petSpeciesID = self:GetPetSpeciesFromBattlePetLink(itemLink)
		if petSpeciesID then
			local isCollected = self:IsPetSpeciesCollected(petSpeciesID)
			return {
				itemID = itemID,
				itemLink = itemLink,
				isCollected = isCollected,
				hasOtherTransmogSources = false,
				isPartiallyCollected = false,
				frameType = "surgical",
				petSpeciesID = petSpeciesID,
			}
		end
	end

	-- ADDED: Handle ensembles next
	if self:IsEnsembleItem(itemID) then
		local isCollected = self:IsEnsembleCollected(itemID, itemLink)
		return {
			itemID = itemID,
			itemLink = itemLink,
			isCollected = isCollected,
			hasOtherTransmogSources = false,
			isPartiallyCollected = false,
			frameType = "surgical",
			isEnsemble = true,
		}
	end

	if not self:IsCollectibleItem(itemID, itemLink) then return nil end

	local isCollected, hasOtherTransmogSources, isPartiallyCollected = self:IsItemCollected(itemID, itemLink)
	return {
		itemID = itemID,
		itemLink = itemLink,
		isCollected = isCollected,
		hasOtherTransmogSources = hasOtherTransmogSources,
		isPartiallyCollected = isPartiallyCollected,
		frameType = "surgical",
	}
end

-- ===== INDICATOR MANAGEMENT =====
function DOKI:AddButtonIndicator(button, itemData)
	if not button or not itemData then return false end

	-- FIXED: Don't add indicators for collected items unless they need purple indicator
	if itemData.isCollected and not itemData.isPartiallyCollected then return false end

	local success, isVisible = pcall(button.IsVisible, button)
	if not success or not isVisible then return false end

	local textureData = self:GetButtonTexture(button)
	if not textureData then return false end

	-- Set color based on indicator type
	if itemData.isPartiallyCollected then
		textureData:SetColor(1.0, 0.4, 0.7)   -- Purple for fractional items
	elseif itemData.hasOtherTransmogSources then
		textureData:SetColor(0.082, 0.671, 1.0) -- Blue for other sources
	else
		textureData:SetColor(1.0, 0.573, 0.2) -- Orange for uncollected
	end

	textureData:Show()
	textureData.itemID = itemData.itemID
	textureData.itemLink = itemData.itemLink -- ADDED: Store itemLink for battlepets
	-- FIXED: Store complete item info for battlepets + ensembles
	if itemData.itemLink then
		self.buttonItemMap[button] = {
			itemID = itemData.itemID,
			itemLink = itemData.itemLink,
		}
	else
		self.buttonItemMap[button] = itemData.itemID
	end

	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
		local buttonName = ""
		local nameSuccess, name = pcall(button.GetName, button)
		if nameSuccess and name then
			buttonName = name
		else
			buttonName = "unnamed"
		end

		local extraInfo = ""
		if itemData.petSpeciesID then
			extraInfo = string.format(" [Battlepet Species: %d]", itemData.petSpeciesID)
		elseif itemData.isEnsemble then
			extraInfo = " [Ensemble]"
		elseif itemData.isPartiallyCollected then
			extraInfo = " [Purple]"
		end

		-- Check if this is a merchant button
		if buttonName and string.find(buttonName, "Merchant") then
			extraInfo = extraInfo .. " [Merchant]"
		end

		local colorType = itemData.isPartiallyCollected and "PURPLE" or
				(itemData.hasOtherTransmogSources and "BLUE" or "ORANGE")
		print(string.format("|cffff69b4DOKI|r Added %s indicator for %s (ID: %d) on %s%s",
			colorType, itemName, itemData.itemID, buttonName, extraInfo))
	end

	return true
end

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

	self.buttonItemMap = {}
	self.lastButtonSnapshot = {}
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cleared %d button indicators", count))
	end

	return count
end

function DOKI:CleanupButtonTextures()
	local removedCount = 0
	local toRemove = {}
	for button, textureData in pairs(self.buttonTextures) do
		if not button then
			table.insert(toRemove, button)
			removedCount = removedCount + 1
		else
			local success, isVisible = pcall(button.IsVisible, button)
			if not success or not isVisible then
				table.insert(toRemove, button)
				removedCount = removedCount + 1
			end
		end
	end

	for _, button in ipairs(toRemove) do
		self:ReleaseButtonTexture(button)
	end

	if self.db and self.db.debugMode and removedCount > 0 then
		print(string.format("|cffff69b4DOKI|r Cleaned up %d invalid button textures", removedCount))
	end

	return removedCount
end

-- ADDED: Force cleanup function for empty slots (useful for rapid selling issues)
function DOKI:ForceCleanEmptySlots()
	if not self.buttonTextures then return 0 end

	local snapshot = self:CreateButtonSnapshot()
	local cleanedCount = 0
	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive then
			local buttonData = snapshot[button]
			if buttonData and buttonData.isEmpty then
				if self:RemoveButtonIndicator(button) then
					cleanedCount = cleanedCount + 1
					if self.db and self.db.debugMode then
						local buttonName = ""
						local success, name = pcall(button.GetName, button)
						if success and name then
							buttonName = name
						else
							buttonName = "unnamed"
						end

						print(string.format("|cffff69b4DOKI|r Force cleaned indicator from empty slot: %s", buttonName))
					end
				end
			end
		end
	end

	if self.db and self.db.debugMode and cleanedCount > 0 then
		print(string.format("|cffff69b4DOKI|r Force cleaned %d indicators from empty slots", cleanedCount))
	end

	return cleanedCount
end

function DOKI:CleanupMerchantTextures()
	if not self.buttonTextures then return 0 end

	local removedCount = 0
	local toRemove = {}
	for button, textureData in pairs(self.buttonTextures) do
		if textureData.isActive then
			-- Check if this is a merchant button that's no longer valid
			local buttonName = ""
			local success, name = pcall(button.GetName, button)
			if success and name then
				buttonName = name
			end

			if string.find(buttonName, "Merchant") then
				-- This is a merchant button - check if merchant is still open
				if not (MerchantFrame and MerchantFrame:IsVisible()) then
					table.insert(toRemove, button)
					removedCount = removedCount + 1
				end
			end
		end
	end

	for _, button in ipairs(toRemove) do
		self:RemoveButtonIndicator(button)
	end

	if self.db and self.db.debugMode and removedCount > 0 then
		print(string.format("|cffff69b4DOKI|r Cleaned up %d merchant indicators", removedCount))
	end

	return removedCount
end

-- ===== ENHANCED INITIALIZATION WITH PROPER EMPTY SLOT SUPPORT =====
function DOKI:InitializeButtonTextureSystem()
	self.buttonTextures = self.buttonTextures or {}
	self.texturePool = self.texturePool or {}
	self.lastButtonSnapshot = {}
	self.buttonItemMap = {}
	self:ValidateTexture()
	if self.db and self.db.debugMode then
		print(
			"|cffff69b4DOKI|r Enhanced button texture system initialized with proper empty slot detection + merchant selling support")
	end
end

-- ENHANCED: Cleanup with delayed scan cancellation support
function DOKI:CleanupButtonTextureSystem()
	-- ADDED: Cancel any pending delayed scans during cleanup
	if self.CancelDelayedScan then
		self:CancelDelayedScan()
	end

	self:ClearAllButtonIndicators()
	for button, textureData in pairs(self.buttonTextures) do
		self:ReleaseButtonTexture(button)
	end

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
		print("|cffff69b4DOKI|r Button texture system cleaned up with delayed scan cancellation")
	end
end

-- ===== BACKWARDS COMPATIBILITY =====
function DOKI:ClearUniversalOverlays()
	return self:CleanupButtonTextures()
end

function DOKI:ClearAllOverlays()
	return self:ClearAllButtonIndicators()
end

-- ===== ENHANCED DEBUG FUNCTIONS WITH EMPTY SLOT SUPPORT =====
function DOKI:DebugButtonTextures()
	print("|cffff69b4DOKI|r === BUTTON TEXTURE DEBUG ===")
	print(string.format("Texture file validated: %s", tostring(self.textureValidated)))
	local activeCount = 0
	local totalCount = 0
	local battlepetCount = 0
	local ensembleCount = 0
	local merchantCount = 0
	for button, textureData in pairs(self.buttonTextures) do
		totalCount = totalCount + 1
		if textureData.isActive then
			activeCount = activeCount + 1
			if textureData.itemLink and string.find(textureData.itemLink, "battlepet:") then
				battlepetCount = battlepetCount + 1
			elseif textureData.itemID and self:IsEnsembleItem(textureData.itemID) then
				ensembleCount = ensembleCount + 1
			end

			-- Check if this is a merchant button
			local buttonName = ""
			local success, name = pcall(button.GetName, button)
			if success and name and string.find(name, "Merchant") then
				merchantCount = merchantCount + 1
			end
		end
	end

	print(string.format("Button textures: %d total, %d active (%d battlepets, %d ensembles, %d merchant)",
		totalCount, activeCount, battlepetCount, ensembleCount, merchantCount))
	print(string.format("Texture pool size: %d", #self.texturePool))
	-- ADDED: Enhanced snapshot debugging
	local snapshotInfo = self:DebugSnapshotInfo()
	print(string.format("Button tracking: %s", snapshotInfo))
	-- ADDED: Show delayed scan status
	if self.delayedScanTimer then
		print(string.format("Delayed cleanup scan: PENDING"))
	else
		print(string.format("Delayed cleanup scan: Ready"))
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
end

-- ADDED: Enhanced snapshot debugging
function DOKI:DebugSnapshotInfo()
	if not self.lastButtonSnapshot then
		return "No snapshot available"
	end

	local totalButtons = 0
	local buttonsWithItems = 0
	local emptySlots = 0
	local battlepets = 0
	local ensembles = 0
	for button, itemData in pairs(self.lastButtonSnapshot) do
		totalButtons = totalButtons + 1
		if itemData.isEmpty then
			emptySlots = emptySlots + 1
		elseif itemData.hasItem then
			buttonsWithItems = buttonsWithItems + 1
			if itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
				battlepets = battlepets + 1
			elseif itemData.itemID and self:IsEnsembleItem(itemData.itemID) then
				ensembles = ensembles + 1
			end
		end
	end

	return string.format("%d buttons (%d with items, %d empty, %d battlepets, %d ensembles)",
		totalButtons, buttonsWithItems, emptySlots, battlepets, ensembles)
end

function DOKI:DebugEnsembleTracking()
	print("|cffff69b4DOKI|r === ENSEMBLE TRACKING DEBUG ===")
	if not self.CreateButtonSnapshot then
		print("|cffff69b4DOKI|r ButtonTextures system not available")
		return
	end

	local snapshot = self:CreateButtonSnapshot()
	local ensembleCount = 0
	local regularItemCount = 0
	local battlepetCount = 0
	local emptySlotCount = 0
	print("|cffff69b4DOKI|r Current button snapshot analysis:")
	for button, itemData in pairs(snapshot) do
		if itemData.isEmpty then
			emptySlotCount = emptySlotCount + 1
		elseif itemData.hasItem and itemData.itemID then
			-- Check if it's a battlepet
			if itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
				battlepetCount = battlepetCount + 1
				-- Check if it's an ensemble
			elseif self:IsEnsembleItem(itemData.itemID) then
				ensembleCount = ensembleCount + 1
				local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
				local buttonName = ""
				local success, name = pcall(button.GetName, button)
				if success and name then
					buttonName = name
				else
					buttonName = "unnamed"
				end

				print(string.format("  Ensemble: %s -> %s (ID: %d)",
					buttonName, itemName, itemData.itemID))
			else
				regularItemCount = regularItemCount + 1
			end
		else
			regularItemCount = regularItemCount + 1
		end
	end

	print(string.format("Total snapshot items: %d (%d regular, %d battlepets, %d ensembles, %d empty)",
		regularItemCount + battlepetCount + ensembleCount + emptySlotCount,
		regularItemCount, battlepetCount, ensembleCount, emptySlotCount))
	-- Check active indicators for ensembles
	local activeEnsembleIndicators = 0
	if self.buttonTextures then
		for button, textureData in pairs(self.buttonTextures) do
			if textureData.isActive and textureData.itemID then
				if self:IsEnsembleItem(textureData.itemID) then
					activeEnsembleIndicators = activeEnsembleIndicators + 1
				end
			end
		end
	end

	print(string.format("Active ensemble indicators: %d", activeEnsembleIndicators))
	print("|cffff69b4DOKI|r === END ENSEMBLE TRACKING DEBUG ===")
end

function DOKI:TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do count = count + 1 end

	return count
end

function DOKI:TestButtonTextureCreation()
	print("|cffff69b4DOKI|r Testing enhanced button texture system...")
	if not self:ValidateTexture() then
		print("|cffff69b4DOKI|r Cannot test - texture validation failed")
		return
	end

	-- Find a visible button
	local testButton = nil
	-- Try merchant first if available
	if MerchantFrame and MerchantFrame:IsVisible() then
		for i = 1, 10 do
			local buttonName = "MerchantItem" .. i .. "ItemButton"
			local button = _G[buttonName]
			if button and button:IsVisible() then
				testButton = button
				print("|cffff69b4DOKI|r Using merchant button for test")
				break
			end
		end
	end

	-- Fallback to bag buttons
	if not testButton and ElvUI and self:IsElvUIBagVisible() then
		for bagID = 0, 1 do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local buttonName = string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID)
					local button = _G[buttonName]
					if button and button:IsVisible() then
						testButton = button
						print("|cffff69b4DOKI|r Using bag button for test")
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
			itemLink = nil,
			isCollected = false,
			hasOtherTransmogSources = false,
			isPartiallyCollected = false,
			frameType = "test",
		}
		local success = self:AddButtonIndicator(testButton, testData)
		if success then
			print("|cffff69b4DOKI|r Test indicator created (orange, top-right)")
			print("|cffff69b4DOKI|r Try moving items or selling to merchant to test response")
			print("|cffff69b4DOKI|r Enhanced empty slot detection will catch item removals")
		else
			print("|cffff69b4DOKI|r Failed to create test indicator")
		end
	else
		print("|cffff69b4DOKI|r No suitable button found - open bags or merchant first")
	end
end

-- ADDED: Test function for empty slot detection
function DOKI:TestEmptySlotDetection()
	print("|cffff69b4DOKI|r === TESTING EMPTY SLOT DETECTION ===")
	-- Create initial snapshot
	local snapshot1 = self:CreateButtonSnapshot()
	local totalSlots = 0
	local emptySlots = 0
	local itemSlots = 0
	for button, itemData in pairs(snapshot1) do
		totalSlots = totalSlots + 1
		if itemData.isEmpty then
			emptySlots = emptySlots + 1
		elseif itemData.hasItem then
			itemSlots = itemSlots + 1
		end
	end

	print(string.format("Initial snapshot: %d total slots (%d with items, %d empty)",
		totalSlots, itemSlots, emptySlots))
	-- Store as last snapshot
	self.lastButtonSnapshot = snapshot1
	-- Test surgical update (should show no changes)
	local changes = self:ProcessSurgicalUpdate()
	print(string.format("Surgical update result: %d changes (should be 0)", changes))
	print("|cffff69b4DOKI|r Try selling an item to a merchant, then check /doki status")
	print("|cffff69b4DOKI|r The indicator should disappear when the item is sold")
	print("|cffff69b4DOKI|r === END EMPTY SLOT DETECTION TEST ===")
end
