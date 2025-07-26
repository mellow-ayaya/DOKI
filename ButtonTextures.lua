-- DOKI Button Texture System - Clean Implementation
local addonName, DOKI = ...
-- Storage
DOKI.buttonTextures = {}
DOKI.texturePool = {}
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected"
-- Surgical update tracking
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
		textureData.texture:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", -2, -2)
	else
		textureData.texture:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
	end

	textureData.texture:SetSize(16, 16)
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
			local texture = region:GetTexture()
			if texture and texture ~= "" and not string.find(texture:lower(), "border") then
				return region
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
	self.buttonTextures[button] = nil
	self.buttonItemMap[button] = nil
	table.insert(self.texturePool, textureData)
end

-- ===== SNAPSHOT SYSTEM =====
function DOKI:CreateButtonSnapshot()
	local snapshot = {}
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
								snapshot[button] = itemInfo.itemID
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
							snapshot[button] = itemInfo.itemID
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
								snapshot[button] = itemInfo.itemID
								break
							end
						end
					end
				end
			end
		end
	end

	-- Merchant buttons
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

-- ===== SURGICAL UPDATE PROCESSING =====
function DOKI:ProcessSurgicalUpdate()
	local currentSnapshot = self:CreateButtonSnapshot()
	local changes = {
		removed = {},
		added = {},
		changed = {},
	}
	-- Find buttons that lost items or changed items
	for button, oldItemID in pairs(self.lastButtonSnapshot or {}) do
		local newItemID = currentSnapshot[button]
		if not newItemID then
			table.insert(changes.removed, { button = button, oldItemID = oldItemID })
		elseif newItemID ~= oldItemID then
			table.insert(changes.changed, { button = button, oldItemID = oldItemID, newItemID = newItemID })
		end
	end

	-- Find buttons that gained items
	for button, newItemID in pairs(currentSnapshot) do
		local oldItemID = self.lastButtonSnapshot and self.lastButtonSnapshot[button]
		if not oldItemID then
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
		print(string.format("|cffff69b4DOKI|r Surgical update: %d changes (%d removed, %d added, %d changed)",
			updateCount, #changes.removed, #changes.added, #changes.changed))
	end

	return updateCount
end

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

		print(string.format("|cffff69b4DOKI|r Added indicator for %s (ID: %d) on %s",
			itemName, itemData.itemID, buttonName))
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

-- ===== INITIALIZATION =====
function DOKI:InitializeButtonTextureSystem()
	self.buttonTextures = self.buttonTextures or {}
	self.texturePool = self.texturePool or {}
	self.lastButtonSnapshot = {}
	self.buttonItemMap = {}
	self:ValidateTexture()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Clean button texture system initialized")
	end
end

function DOKI:CleanupButtonTextureSystem()
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
		print("|cffff69b4DOKI|r Button texture system cleaned up")
	end
end

-- ===== BACKWARDS COMPATIBILITY =====
function DOKI:ClearUniversalOverlays()
	return self:CleanupButtonTextures()
end

function DOKI:ClearAllOverlays()
	return self:ClearAllButtonIndicators()
end

-- ===== DEBUG FUNCTIONS =====
function DOKI:DebugButtonTextures()
	print("|cffff69b4DOKI|r === BUTTON TEXTURE DEBUG ===")
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
	print("|cffff69b4DOKI|r === END DEBUG ===")
end

function DOKI:TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do count = count + 1 end

	return count
end

function DOKI:TestButtonTextureCreation()
	print("|cffff69b4DOKI|r Testing button texture system...")
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
			print("|cffff69b4DOKI|r Test indicator created (orange, top-right)")
			print("|cffff69b4DOKI|r Try moving items to test response")
		else
			print("|cffff69b4DOKI|r Failed to create test indicator")
		end
	else
		print("|cffff69b4DOKI|r No suitable button found - open bags first")
	end
end
