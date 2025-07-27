-- DOKI Button Texture System - Complete War Within Fix with Battlepet Support + Enhanced Delayed Cleanup
local addonName, DOKI = ...
-- Storage
DOKI.buttonTextures = {}
DOKI.texturePool = {}
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected"
-- FIXED: Enhanced surgical update tracking for battlepets and merchant
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

-- ===== ENHANCED SNAPSHOT SYSTEM FOR BATTLEPETS + MERCHANT =====
function DOKI:CreateButtonSnapshot()
	local snapshot = {}
	-- FIXED: Store both itemID and itemLink for battlepet support
	local function addToSnapshot(button, itemID, itemLink)
		if button and itemID then
			snapshot[button] = {
				itemID = itemID,
				itemLink = itemLink,
			}
		end
	end

	-- ElvUI buttons
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
								addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
								break
							end
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
					if itemInfo and itemInfo.itemID then
						-- Find matching button
						local button = nil
						if ContainerFrameCombinedBags.EnumerateValidItems then
							for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
								if itemButton and itemButton:IsVisible() then
									local buttonBagID, buttonSlotID = nil, nil
									if itemButton.GetBagID and itemButton.GetID then
										local success1, bID = pcall(itemButton.GetBagID, itemButton)
										local success2, sID = pcall(itemButton.GetID, itemButton)
										if success1 and success2 then
											buttonBagID, buttonSlotID = bID, sID
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
							addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
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
					if itemInfo and itemInfo.itemID then
						local possibleNames = {
							string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
							string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
						}
						for _, buttonName in ipairs(possibleNames) do
							local button = _G[buttonName]
							if button and button:IsVisible() then
								addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
								break
							end
						end
					end
				end
			end
		end
	end

	-- ENHANCED: Merchant buttons - get items directly from visible buttons
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
					if itemID then
						if itemID == "EMPTY_SLOT" then
							-- Add empty slot to snapshot so surgical update can detect when buttons lose items
							snapshot[button] = {
								itemID = nil,
								itemLink = nil,
								isEmpty = true,
							}
						else
							addToSnapshot(button, itemID, itemLink)
						end
					end

					break
				end
			end
		end
	end

	return snapshot
end

-- ===== ENHANCED SURGICAL UPDATE PROCESSING FOR BATTLEPETS + MERCHANT + DELAYED CLEANUP =====
function DOKI:ProcessSurgicalUpdate()
	local currentSnapshot = self:CreateButtonSnapshot()
	local changes = {
		removed = {},
		added = {},
		changed = {},
	}
	-- FIXED: Enhanced comparison that handles both itemID and itemLink (for battlepets) and empty slots
	local function itemsEqual(oldItem, newItem)
		if not oldItem and not newItem then return true end

		if not oldItem or not newItem then return false end

		-- Handle empty slots
		if oldItem.isEmpty and newItem.isEmpty then return true end

		if oldItem.isEmpty or newItem.isEmpty then return false end

		-- Compare itemIDs
		if oldItem.itemID ~= newItem.itemID then return false end

		-- For battlepets, also compare itemLinks (since same itemID can have different species)
		if oldItem.itemLink and newItem.itemLink then
			if string.find(oldItem.itemLink, "battlepet:") or string.find(newItem.itemLink, "battlepet:") then
				return oldItem.itemLink == newItem.itemLink
			end
		end

		return true
	end

	-- Find buttons that lost items or changed items
	for button, oldItemData in pairs(self.lastButtonSnapshot or {}) do
		local newItemData = currentSnapshot[button]
		if not newItemData then
			table.insert(changes.removed, { button = button, oldItemData = oldItemData })
		elseif not itemsEqual(oldItemData, newItemData) then
			table.insert(changes.changed, { button = button, oldItemData = oldItemData, newItemData = newItemData })
		end
	end

	-- Find buttons that gained items
	for button, newItemData in pairs(currentSnapshot) do
		local oldItemData = self.lastButtonSnapshot and self.lastButtonSnapshot[button]
		if not oldItemData then
			table.insert(changes.added, { button = button, newItemData = newItemData })
		end
	end

	-- Apply surgical updates
	local updateCount = 0
	-- Remove indicators from buttons that lost items
	for _, change in ipairs(changes.removed) do
		self:RemoveButtonIndicator(change.button)
		updateCount = updateCount + 1
		if self.db and self.db.debugMode then
			local extraInfo = ""
			if change.oldItemData.itemLink and string.find(change.oldItemData.itemLink, "battlepet:") then
				extraInfo = " (battlepet)"
			end

			-- Check if this was a merchant button
			local buttonName = ""
			local success, name = pcall(change.button.GetName, change.button)
			if success and name and string.find(name, "Merchant") then
				extraInfo = extraInfo .. " (merchant)"
			end

			local itemID = change.oldItemData.itemID or "unknown"
			print(string.format("|cffff69b4DOKI|r Removed indicator: button lost item %s%s",
				tostring(itemID), extraInfo))
		end
	end

	-- Update buttons that changed items
	for _, change in ipairs(changes.changed) do
		self:RemoveButtonIndicator(change.button)
		-- Only add new indicator if the new item is not empty and not collected
		if not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and not itemData.isCollected then
				self:AddButtonIndicator(change.button, itemData)
			end
		end

		updateCount = updateCount + 1
		if self.db and self.db.debugMode then
			local oldExtra = ""
			local newExtra = ""
			if change.oldItemData.itemLink and string.find(change.oldItemData.itemLink, "battlepet:") then
				oldExtra = " (battlepet)"
			end

			if change.newItemData.itemLink and string.find(change.newItemData.itemLink, "battlepet:") then
				newExtra = " (battlepet)"
			end

			-- Check if this is a merchant button
			local buttonName = ""
			local success, name = pcall(change.button.GetName, change.button)
			if success and name and string.find(name, "Merchant") then
				oldExtra = oldExtra .. " (merchant)"
				newExtra = newExtra .. " (merchant)"
			end

			local oldItemID = change.oldItemData.itemID or "empty"
			local newItemID = change.newItemData.isEmpty and "empty" or (change.newItemData.itemID or "unknown")
			print(string.format("|cffff69b4DOKI|r Changed indicator: %s%s → %s%s",
				tostring(oldItemID), oldExtra, tostring(newItemID), newExtra))
		end
	end

	-- Add indicators to buttons that gained items
	for _, change in ipairs(changes.added) do
		-- Only add indicator if the new item is not empty
		if not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and not itemData.isCollected then
				self:AddButtonIndicator(change.button, itemData)
				updateCount = updateCount + 1
				if self.db and self.db.debugMode then
					local extraInfo = ""
					if change.newItemData.itemLink and string.find(change.newItemData.itemLink, "battlepet:") then
						extraInfo = " (battlepet)"
					end

					-- Check if this is a merchant button
					local buttonName = ""
					local success, name = pcall(change.button.GetName, change.button)
					if success and name and string.find(name, "Merchant") then
						extraInfo = extraInfo .. " (merchant)"
					end

					print(string.format("|cffff69b4DOKI|r Added indicator: button gained item %s%s",
						tostring(change.newItemData.itemID), extraInfo))
				end
			end
		end
	end

	-- Update snapshot
	self.lastButtonSnapshot = currentSnapshot
	if self.db and self.db.debugMode and updateCount > 0 then
		print(string.format("|cffff69b4DOKI|r Surgical update: %d changes (%d removed, %d added, %d changed)",
			updateCount, #changes.removed, #changes.added, #changes.changed))
	end

	return updateCount
end

-- ADDED: Enhanced item data retrieval for surgical updates (supports battlepets)
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
				showYellowD = false,
				frameType = "surgical",
				petSpeciesID = petSpeciesID,
			}
		end
	end

	if not self:IsCollectibleItem(itemID, itemLink) then return nil end

	local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
	return {
		itemID = itemID,
		itemLink = itemLink,
		isCollected = isCollected,
		showYellowD = showYellowD,
		frameType = "surgical",
	}
end

-- ===== INDICATOR MANAGEMENT =====
function DOKI:AddButtonIndicator(button, itemData)
	if not button or not itemData or itemData.isCollected then return false end

	local success, isVisible = pcall(button.IsVisible, button)
	if not success or not isVisible then return false end

	local textureData = self:GetButtonTexture(button)
	if not textureData then return false end

	-- Set color
	if itemData.showYellowD then
		textureData:SetColor(0.082, 0.671, 1.0) -- Blue
	else
		textureData:SetColor(1.0, 0.573, 0.2) -- Orange
	end

	textureData:Show()
	textureData.itemID = itemData.itemID
	textureData.itemLink = itemData.itemLink -- ADDED: Store itemLink for battlepets
	-- FIXED: Store complete item info for battlepets
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
		end

		-- Check if this is a merchant button
		if buttonName and string.find(buttonName, "Merchant") then
			extraInfo = extraInfo .. " [Merchant]"
		end

		print(string.format("|cffff69b4DOKI|r Added indicator for %s (ID: %d) on %s%s",
			itemName, itemData.itemID, buttonName, extraInfo))
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

-- ===== MERCHANT-SPECIFIC CLEANUP =====
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

-- ===== ENHANCED INITIALIZATION WITH DELAYED CLEANUP SUPPORT =====
function DOKI:InitializeButtonTextureSystem()
	self.buttonTextures = self.buttonTextures or {}
	self.texturePool = self.texturePool or {}
	self.lastButtonSnapshot = {}
	self.buttonItemMap = {}
	self:ValidateTexture()
	if self.db and self.db.debugMode then
		print(
			"|cffff69b4DOKI|r Enhanced button texture system initialized with battlepet + merchant + delayed cleanup support")
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

-- ===== ENHANCED DEBUG FUNCTIONS =====
function DOKI:DebugButtonTextures()
	print("|cffff69b4DOKI|r === BUTTON TEXTURE DEBUG ===")
	print(string.format("Texture file validated: %s", tostring(self.textureValidated)))
	local activeCount = 0
	local totalCount = 0
	local battlepetCount = 0
	local merchantCount = 0
	for button, textureData in pairs(self.buttonTextures) do
		totalCount = totalCount + 1
		if textureData.isActive then
			activeCount = activeCount + 1
			if textureData.itemLink and string.find(textureData.itemLink, "battlepet:") then
				battlepetCount = battlepetCount + 1
			end

			-- Check if this is a merchant button
			local buttonName = ""
			local success, name = pcall(button.GetName, button)
			if success and name and string.find(name, "Merchant") then
				merchantCount = merchantCount + 1
			end
		end
	end

	print(string.format("Button textures: %d total, %d active (%d battlepets, %d merchant)",
		totalCount, activeCount, battlepetCount, merchantCount))
	print(string.format("Texture pool size: %d", #self.texturePool))
	print(string.format("Button tracking: %d buttons in snapshot",
		self.lastButtonSnapshot and self:TableCount(self.lastButtonSnapshot) or 0))
	-- ADDED: Show delayed scan status
	if self.delayedScanTimer then
		print(string.format("Delayed cleanup scan: PENDING"))
	else
		print(string.format("Delayed cleanup scan: Ready"))
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
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
			showYellowD = false,
			frameType = "test",
		}
		local success = self:AddButtonIndicator(testButton, testData)
		if success then
			print("|cffff69b4DOKI|r Test indicator created (orange, top-right)")
			print("|cffff69b4DOKI|r Try moving items or scrolling merchant to test response")
			print("|cffff69b4DOKI|r Delayed cleanup scan will trigger in 0.2s after item movement")
		else
			print("|cffff69b4DOKI|r Failed to create test indicator")
		end
	else
		print("|cffff69b4DOKI|r No suitable button found - open bags or merchant first")
	end
end

-- ADDED: Enhanced test function for delayed cleanup scanning
function DOKI:TestDelayedCleanupScan()
	print("|cffff69b4DOKI|r === TESTING DELAYED CLEANUP SCAN ===")
	-- Check if system is available
	if not self.ScheduleDelayedCleanupScan then
		print("|cffff69b4DOKI|r ❌ Delayed cleanup scan system not available")
		return
	end

	-- Show current status
	if self.delayedScanTimer then
		print("|cffff69b4DOKI|r Current status: Delayed scan PENDING")
		print("|cffff69b4DOKI|r Testing cancellation...")
		self:CancelDelayedScan()
		if not self.delayedScanTimer then
			print("|cffff69b4DOKI|r ✅ Cancellation works correctly")
		else
			print("|cffff69b4DOKI|r ❌ Cancellation failed")
		end
	else
		print("|cffff69b4DOKI|r Current status: Ready")
	end

	-- Test scheduling
	print("|cffff69b4DOKI|r Testing delayed scan scheduling...")
	self:ScheduleDelayedCleanupScan()
	if self.delayedScanTimer then
		print("|cffff69b4DOKI|r ✅ Delayed scan scheduled successfully")
		print("|cffff69b4DOKI|r Will trigger in 0.2 seconds unless cancelled")
		-- Test auto-cancellation after 0.5 seconds
		C_Timer.After(0.5, function()
			if DOKI.delayedScanTimer then
				print("|cffff69b4DOKI|r ❌ Delayed scan did not auto-complete")
			else
				print("|cffff69b4DOKI|r ✅ Delayed scan completed or was cancelled correctly")
			end
		end)
	else
		print("|cffff69b4DOKI|r ❌ Failed to schedule delayed scan")
	end

	print("|cffff69b4DOKI|r === END DELAYED CLEANUP TEST ===")
end

-- ADDED: Enhanced snapshot comparison test
function DOKI:TestSnapshotComparison()
	print("|cffff69b4DOKI|r === TESTING SNAPSHOT COMPARISON ===")
	-- Create initial snapshot
	local snapshot1 = self:CreateButtonSnapshot()
	local itemCount = 0
	for _ in pairs(snapshot1) do itemCount = itemCount + 1 end

	print(string.format("|cffff69b4DOKI|r Initial snapshot: %d buttons with items", itemCount))
	-- Store as last snapshot
	self.lastButtonSnapshot = snapshot1
	-- Test surgical update (should show no changes)
	local changes = self:ProcessSurgicalUpdate()
	print(string.format("|cffff69b4DOKI|r Surgical update result: %d changes (should be 0)", changes))
	-- Simulate item movement by clearing a random button from snapshot
	local testButton = nil
	for button, _ in pairs(snapshot1) do
		testButton = button
		break -- Just take the first one
	end

	if testButton then
		print("|cffff69b4DOKI|r Simulating item removal...")
		self.lastButtonSnapshot[testButton] = nil
		-- Test surgical update again
		local changes2 = self:ProcessSurgicalUpdate()
		print(string.format("|cffff69b4DOKI|r After simulated change: %d changes detected", changes2))
	else
		print("|cffff69b4DOKI|r No buttons in snapshot to test with")
	end

	print("|cffff69b4DOKI|r === END SNAPSHOT COMPARISON TEST ===")
end
