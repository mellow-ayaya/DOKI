-- DOKI Button Texture System - FIXED: Empty Slot Detection, Surgical Updates, Merchant Selling
local addonName, DOKI = ...
-- Storage
DOKI.buttonTextures = {}
DOKI.texturePool = {}
DOKI.indicatorTexturePath = "Interface\\AddOns\\DOKI\\Media\\uncollected"
-- FIXED: Enhanced surgical update tracking for proper empty slot detection
DOKI.lastButtonSnapshot = {}
DOKI.buttonItemMap = {}
-- Chunked surgical update state
DOKI.dedicatedSurgicalState = nil
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
	-- TESTING MODE: Skip automatic surgical updates
	if self:IsInTestingMode() then
		print("|cffff00ffTEST MODE|r Ignoring ProcessSurgicalUpdate (testing mode active)")
		return 0
	end

	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - ProcessSurgicalUpdate called", GetTime()))
	-- Check if we're already running a dedicated surgical update
	if self.dedicatedSurgicalState then
		print("|cff00ff00SURGICAL DEBUG|r - Already running dedicated surgical, skipping")
		return 0
	end

	-- Start dedicated surgical update (separate from full scans)
	return self:StartDedicatedSurgicalUpdate()
end

-- Dedicated surgical update (separate from full scans)
function DOKI:StartDedicatedSurgicalUpdate()
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - StartDedicatedSurgicalUpdate called", GetTime()))
	-- Step 1: Quick scan to detect which bags have changes
	local changedBags = self:DetectChangedBags()
	if #changedBags == 0 then
		print("|cff00ff00SURGICAL DEBUG|r - No bags changed, skipping surgical update")
		return 0
	end

	print(string.format("|cff00ff00SURGICAL DEBUG|r - Detected changes in %d bags: %s",
		#changedBags, table.concat(changedBags, ", ")))
	-- Step 2: Choose strategy based on number of changed bags
	if #changedBags <= 2 then
		-- Small change: immediate surgical update on affected bags only
		print("|cff00ff00SURGICAL DEBUG|r - Using IMMEDIATE SURGICAL strategy (≤2 bags changed)")
		return self:ImmediateSurgicalUpdate(changedBags)
	else
		-- Large change: progressive surgical (separate from full scan)
		print("|cff00ff00SURGICAL DEBUG|r - Using PROGRESSIVE SURGICAL strategy (>2 bags changed)")
		return self:StartProgressiveSurgicalUpdate(changedBags)
	end
end

-- Progressive surgical update (for large surgical changes only)
function DOKI:StartProgressiveSurgicalUpdate(changedBags)
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - StartProgressiveSurgicalUpdate called", GetTime()))
	-- Initialize dedicated surgical state
	self.dedicatedSurgicalState = {
		mode = "progressive_surgical",
		changedBags = changedBags,
		currentBagIndex = 1,
		indicatorCount = 0,
		startTime = GetTime(),
	}
	print("|cff00ff00SURGICAL DEBUG|r - Starting progressive surgical processing")
	self:ProcessNextSurgicalBag()
	return 0
end

-- Process next bag in progressive surgical
function DOKI:ProcessNextSurgicalBag()
	local state = self.dedicatedSurgicalState
	if not state then
		print("|cff00ff00SURGICAL DEBUG|r - ProcessNextSurgicalBag called but no state!")
		return
	end

	if state.currentBagIndex > #state.changedBags then
		print("|cff00ff00SURGICAL DEBUG|r - Progressive surgical processing complete")
		self:CompleteDedicatedSurgical()
		return
	end

	local bagIdentifier = state.changedBags[state.currentBagIndex]
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - Processing surgical bag: %s", GetTime(), bagIdentifier))
	-- Process this bag immediately
	local updateCount = self:ImmediateSurgicalUpdate({ bagIdentifier })
	state.indicatorCount = state.indicatorCount + updateCount
	state.currentBagIndex = state.currentBagIndex + 1
	print(string.format("|cff00ff00SURGICAL DEBUG|r - Surgical bag processed: %d changes", updateCount))
	-- Schedule next bag or complete
	if state.currentBagIndex <= #state.changedBags then
		local delay = self.db.attMode and self.CHUNKED_SCAN_DELAYS.ATT_MODE or self.CHUNKED_SCAN_DELAYS.STANDARD_MODE
		print(string.format("|cff00ff00SURGICAL DEBUG|r - Scheduling next surgical bag in %.3fs", delay))
		C_Timer.After(delay, function()
			if DOKI.dedicatedSurgicalState then
				DOKI:ProcessNextSurgicalBag()
			end
		end)
	else
		self:CompleteDedicatedSurgical()
	end
end

-- Complete dedicated surgical
function DOKI:CompleteDedicatedSurgical()
	local state = self.dedicatedSurgicalState
	if not state then return 0 end

	local duration = GetTime() - state.startTime
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - Dedicated surgical complete: %d changes in %.3fs",
		GetTime(), state.indicatorCount, duration))
	local indicatorCount = state.indicatorCount
	self.dedicatedSurgicalState = nil
	return indicatorCount
end

-- Cancel dedicated surgical
function DOKI:CancelDedicatedSurgical()
	if self.dedicatedSurgicalState then
		print("|cff00ff00SURGICAL DEBUG|r - Dedicated surgical cancelled")
		self.dedicatedSurgicalState = nil
	end
end

-- Main smart surgical update - decides strategy based on changes
function DOKI:SmartSurgicalUpdate()
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - SmartSurgicalUpdate called", GetTime()))
	-- Step 1: Quick scan to detect which bags have changes
	local changedBags = self:DetectChangedBags()
	if #changedBags == 0 then
		print("|cff00ff00SURGICAL DEBUG|r - No bags changed, skipping update")
		return 0
	end

	print(string.format("|cff00ff00SURGICAL DEBUG|r - Detected changes in %d bags: %s",
		#changedBags, table.concat(changedBags, ", ")))
	-- Step 2: Choose strategy based on number of changed bags
	if #changedBags <= 2 then
		-- Small change: immediate surgical update on affected bags only
		print("|cff00ff00SURGICAL DEBUG|r - Using IMMEDIATE strategy (≤2 bags changed)")
		return self:ImmediateSurgicalUpdate(changedBags)
	else
		-- Large change: progressive chunked scan with immediate indicator application
		print("|cff00ff00SURGICAL DEBUG|r - Using PROGRESSIVE strategy (>2 bags changed)")
		return self:StartProgressiveChunkedSurgical()
	end
end

-- Detect which bags have changes (fast comparison)
function DOKI:DetectChangedBags()
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - DetectChangedBags called", GetTime()))
	local changedBags = {}
	local currentState = self:GetCurrentUIVisibilityState()
	-- If no previous snapshot exists, consider all visible UI as changed
	if not self.lastButtonSnapshot then
		print("|cff00ff00SURGICAL DEBUG|r - No previous snapshot, marking all visible UI as changed")
		if currentState.elvui then
			for bagID = 0, NUM_BAG_SLOTS do
				table.insert(changedBags, "elvui_" .. bagID)
			end
		end

		if currentState.combined then
			for bagID = 0, NUM_BAG_SLOTS do
				table.insert(changedBags, "combined_" .. bagID)
			end
		end

		if currentState.individual then
			for bagID = 0, NUM_BAG_SLOTS do
				table.insert(changedBags, "individual_" .. bagID)
			end
		end

		if currentState.merchant then
			table.insert(changedBags, "merchant")
		end

		return changedBags
	end

	-- Fast bag-by-bag comparison
	-- Check ElvUI bags
	if currentState.elvui then
		for bagID = 0, NUM_BAG_SLOTS do
			if self:HasBagChanged("elvui", bagID) then
				table.insert(changedBags, "elvui_" .. bagID)
				print(string.format("|cff00ff00SURGICAL DEBUG|r - ElvUI bag %d changed", bagID))
			end
		end
	end

	-- Check combined bags
	if currentState.combined then
		for bagID = 0, NUM_BAG_SLOTS do
			if self:HasBagChanged("combined", bagID) then
				table.insert(changedBags, "combined_" .. bagID)
				print(string.format("|cff00ff00SURGICAL DEBUG|r - Combined bag %d changed", bagID))
			end
		end
	end

	-- Check individual bags
	if currentState.individual then
		for bagID = 0, NUM_BAG_SLOTS do
			if self:HasBagChanged("individual", bagID) then
				table.insert(changedBags, "individual_" .. bagID)
				print(string.format("|cff00ff00SURGICAL DEBUG|r - Individual bag %d changed", bagID))
			end
		end
	end

	-- Check merchant
	if currentState.merchant then
		if self:HasBagChanged("merchant", 0) then
			table.insert(changedBags, "merchant")
			print("|cff00ff00SURGICAL DEBUG|r - Merchant changed")
		end
	end

	return changedBags
end

-- Check if a specific bag has changes (fast comparison)
function DOKI:HasBagChanged(scanType, bagID)
	-- Quick item count and basic hash comparison
	local currentItems = self:GetBagItemSummary(scanType, bagID)
	local lastSnapshot = self.lastButtonSnapshot or {}
	-- Count items from this bag in last snapshot
	local lastItems = {}
	for button, itemData in pairs(lastSnapshot) do
		-- Match buttons from this specific bag
		if self:IsButtonFromBag(button, scanType, bagID) then
			if itemData.hasItem then
				lastItems[itemData.itemID] = (lastItems[itemData.itemID] or 0) + 1
			end
		end
	end

	-- Simple comparison: different item counts means changed
	if self:TableCount(currentItems) ~= self:TableCount(lastItems) then
		return true
	end

	-- Compare item IDs and counts
	for itemID, count in pairs(currentItems) do
		if (lastItems[itemID] or 0) ~= count then
			return true
		end
	end

	for itemID, count in pairs(lastItems) do
		if (currentItems[itemID] or 0) ~= count then
			return true
		end
	end

	return false
end

-- Get summary of items in a bag (for change detection)
function DOKI:GetBagItemSummary(scanType, bagID)
	local items = {}
	if scanType == "merchant" then
		-- Merchant summary
		for i = 1, 12 do
			local possibleButtonNames = {
				string.format("MerchantItem%dItemButton", i),
				string.format("MerchantItem%d", i),
			}
			for _, buttonName in ipairs(possibleButtonNames) do
				local button = _G[buttonName]
				if button and button:IsVisible() then
					local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
					if itemID and itemID ~= "EMPTY_SLOT" then
						items[itemID] = (items[itemID] or 0) + 1
					end

					break
				end
			end
		end
	else
		-- Bag summary
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					items[itemInfo.itemID] = (items[itemInfo.itemID] or 0) + 1
				end
			end
		end
	end

	return items
end

-- Check if button belongs to specific bag
function DOKI:IsButtonFromBag(button, scanType, bagID)
	local success, buttonName = pcall(button.GetName, button)
	if not success or not buttonName then
		return false
	end

	if scanType == "elvui" then
		return string.find(buttonName, string.format("ElvUI_ContainerFrameBag%d", bagID)) ~= nil
	elseif scanType == "individual" then
		return string.find(buttonName, string.format("ContainerFrame%d", bagID + 1)) ~= nil
	elseif scanType == "combined" then
		-- For combined bags, check if button belongs to this bagID (more complex)
		if button.GetBagID then
			local bagIDRetrievalSuccess, buttonBagID = pcall(button.GetBagID, button)
			return bagIDRetrievalSuccess and buttonBagID == bagID
		end
	elseif scanType == "merchant" then
		return string.find(buttonName, "Merchant") ~= nil
	end

	return false
end

-- Immediate surgical update for specific bags (instant)
function DOKI:ImmediateSurgicalUpdate(changedBagList)
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - ImmediateSurgicalUpdate for bags: %s",
		GetTime(), table.concat(changedBagList, ", ")))
	local startTime = GetTime()
	local updateCount = 0
	-- Create snapshot only for changed bags
	local partialSnapshot = {}
	for _, bagIdentifier in ipairs(changedBagList) do
		local scanType, bagID = self:ParseBagIdentifier(bagIdentifier)
		if scanType == "elvui" then
			self:CreateElvUISnapshotChunk(bagID, partialSnapshot)
		elseif scanType == "combined" then
			self:CreateCombinedSnapshotChunk(bagID, partialSnapshot)
		elseif scanType == "individual" then
			self:CreateIndividualSnapshotChunk(bagID, partialSnapshot)
		elseif scanType == "merchant" then
			self:CreateMerchantSnapshotChunk(partialSnapshot)
		end
	end

	-- Compare and apply changes for these bags only
	local changes = self:ComparePartialSnapshots(partialSnapshot, changedBagList)
	updateCount = self:ApplyImmediateChanges(changes)
	-- Update only the changed portions of the snapshot
	if not self.lastButtonSnapshot then
		self.lastButtonSnapshot = {}
	end

	for button, itemData in pairs(partialSnapshot) do
		self.lastButtonSnapshot[button] = itemData
	end

	local duration = GetTime() - startTime
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - Immediate surgical complete: %d changes in %.3fs",
		GetTime(), updateCount, duration))
	return updateCount
end

-- Parse bag identifier (e.g., "elvui_2" -> "elvui", 2)
function DOKI:ParseBagIdentifier(bagIdentifier)
	if bagIdentifier == "merchant" then
		return "merchant", 0
	end

	local scanType, bagID = string.match(bagIdentifier, "([^_]+)_(%d+)")
	return scanType, tonumber(bagID)
end

-- Compare partial snapshots (only for changed bags)
function DOKI:ComparePartialSnapshots(partialSnapshot, changedBagList)
	local changes = {
		removed = {},
		added = {},
		changed = {},
	}
	-- Enhanced comparison logic (same itemsEqual function as before)
	local function itemsEqual(oldItem, newItem)
		if not oldItem and not newItem then return true end

		if not oldItem or not newItem then return false end

		if oldItem.isEmpty and newItem.isEmpty then return true end

		if oldItem.isEmpty ~= newItem.isEmpty then return false end

		if oldItem.hasItem and newItem.hasItem then
			if oldItem.itemID ~= newItem.itemID then return false end

			if oldItem.itemLink and newItem.itemLink then
				if string.find(oldItem.itemLink, "battlepet:") or string.find(newItem.itemLink, "battlepet:") then
					return oldItem.itemLink == newItem.itemLink
				end
			end

			return true
		end

		return oldItem.hasItem == newItem.hasItem
	end

	-- Only compare buttons from changed bags
	for button, newItemData in pairs(partialSnapshot) do
		local oldItemData = self.lastButtonSnapshot and self.lastButtonSnapshot[button]
		if not oldItemData then
			table.insert(changes.added, { button = button, newItemData = newItemData })
		elseif not itemsEqual(oldItemData, newItemData) then
			table.insert(changes.changed, { button = button, oldItemData = oldItemData, newItemData = newItemData })
		end
	end

	-- Check for removed items (only in changed bags)
	if self.lastButtonSnapshot then
		for button, oldItemData in pairs(self.lastButtonSnapshot) do
			-- Only check buttons from changed bags
			local isFromChangedBag = false
			for _, bagIdentifier in ipairs(changedBagList) do
				local scanType, bagID = self:ParseBagIdentifier(bagIdentifier)
				if self:IsButtonFromBag(button, scanType, bagID) then
					isFromChangedBag = true
					break
				end
			end

			if isFromChangedBag and not partialSnapshot[button] then
				table.insert(changes.removed, { button = button, oldItemData = oldItemData })
			end
		end
	end

	return changes
end

-- Apply immediate changes (same logic as before)
function DOKI:ApplyImmediateChanges(changes)
	local updateCount = 0
	-- Remove indicators
	for _, change in ipairs(changes.removed) do
		if self:RemoveButtonIndicator(change.button) then
			updateCount = updateCount + 1
		end
	end

	-- Update changed items
	for _, change in ipairs(changes.changed) do
		self:RemoveButtonIndicator(change.button)
		if change.newItemData.hasItem and not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and (not itemData.isCollected or itemData.isPartiallyCollected) then
				if self:AddButtonIndicator(change.button, itemData) then
					updateCount = updateCount + 1
				end
			end
		end
	end

	-- Add new indicators
	for _, change in ipairs(changes.added) do
		if change.newItemData.hasItem and not change.newItemData.isEmpty then
			local itemData = self:GetItemDataForSurgicalUpdate(change.newItemData.itemID, change.newItemData.itemLink)
			if itemData and (not itemData.isCollected or itemData.isPartiallyCollected) then
				if self:AddButtonIndicator(change.button, itemData) then
					updateCount = updateCount + 1
				end
			end
		end
	end

	return updateCount
end

-- Progressive chunked surgical with immediate indicator application
function DOKI:StartProgressiveChunkedSurgical()
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - StartProgressiveChunkedSurgical called", GetTime()))
	-- Cancel any existing smart surgical update
	self:CancelSmartSurgicalUpdate()
	-- Initialize smart surgical state
	self.smartSurgicalState = {
		mode = "progressive", -- "progressive" vs "immediate"
		phase = "processing", -- "processing", "complete"
		bagID = 0,
		scanType = "elvui", -- "elvui", "combined", "individual", "merchant"
		indicatorCount = 0,
		startTime = GetTime(),
	}
	print("|cff00ff00SURGICAL DEBUG|r - Starting progressive surgical processing")
	-- Start immediately with first chunk
	self:ProcessNextProgressiveChunk()
	return 0 -- Will return actual count when complete
end

-- Process one bag progressively (snapshot + compare + apply immediately)
function DOKI:ProcessNextProgressiveChunk()
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - ProcessNextProgressiveChunk called", GetTime()))
	if not self.smartSurgicalState then
		print("|cff00ff00SURGICAL DEBUG|r - ABORTED: no smart surgical state")
		return
	end

	local state = self.smartSurgicalState
	print(string.format("|cff00ff00SURGICAL DEBUG|r - Processing bag %d (%s)", state.bagID, state.scanType))
	-- Check if UI is still visible
	if not self:IsAnyRelevantUIVisible() then
		print("|cff00ff00SURGICAL DEBUG|r - CANCELLED: UI no longer visible")
		self:CancelSmartSurgicalUpdate()
		return
	end

	local indicatorCount = 0
	-- Process current bag: snapshot + compare + apply immediately
	if state.scanType == "elvui" then
		indicatorCount = self:ProcessProgressiveBag("elvui", state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cff00ff00SURGICAL DEBUG|r - ElvUI bags complete, moving to combined")
			state.scanType = "combined"
			state.bagID = 0
		end
	elseif state.scanType == "combined" then
		indicatorCount = self:ProcessProgressiveBag("combined", state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cff00ff00SURGICAL DEBUG|r - Combined bags complete, moving to individual")
			state.scanType = "individual"
			state.bagID = 0
		end
	elseif state.scanType == "individual" then
		indicatorCount = self:ProcessProgressiveBag("individual", state.bagID)
		state.bagID = state.bagID + 1
		if state.bagID > NUM_BAG_SLOTS then
			print("|cff00ff00SURGICAL DEBUG|r - Individual bags complete, moving to merchant")
			state.scanType = "merchant"
			state.bagID = 0
		end
	elseif state.scanType == "merchant" then
		indicatorCount = self:ProcessProgressiveBag("merchant", 0)
		print("|cff00ff00SURGICAL DEBUG|r - Progressive processing complete")
		state.phase = "complete"
	end

	state.indicatorCount = state.indicatorCount + indicatorCount
	print(string.format("|cff00ff00SURGICAL DEBUG|r - Bag processed: %d indicators (total: %d)",
		indicatorCount, state.indicatorCount))
	-- Schedule next chunk or complete
	if state.phase == "processing" then
		local delay = self.db.attMode and self.CHUNKED_SCAN_DELAYS.ATT_MODE or self.CHUNKED_SCAN_DELAYS.STANDARD_MODE
		print(string.format("|cff00ff00SURGICAL DEBUG|r - Scheduling next progressive chunk in %.3fs (ATT mode: %s)",
			delay, tostring(self.db.attMode)))
		C_Timer.After(delay, function()
			if DOKI.smartSurgicalState then
				print("|cff00ff00SURGICAL DEBUG|r - Progressive timer fired, calling ProcessNextProgressiveChunk")
				DOKI:ProcessNextProgressiveChunk()
			else
				print("|cff00ff00SURGICAL DEBUG|r - Progressive timer fired but surgical state is gone!")
			end
		end)
	else
		print("|cff00ff00SURGICAL DEBUG|r - Completing progressive surgical")
		self:CompleteProgressiveSurgical()
	end
end

-- Process one bag progressively: snapshot + compare + apply
function DOKI:ProcessProgressiveBag(scanType, bagID)
	-- Create snapshot for this bag only
	local bagSnapshot = {}
	if scanType == "elvui" then
		self:CreateElvUISnapshotChunk(bagID, bagSnapshot)
	elseif scanType == "combined" then
		self:CreateCombinedSnapshotChunk(bagID, bagSnapshot)
	elseif scanType == "individual" then
		self:CreateIndividualSnapshotChunk(bagID, bagSnapshot)
	elseif scanType == "merchant" then
		self:CreateMerchantSnapshotChunk(bagSnapshot)
	end

	-- Compare this bag vs old snapshot
	local changes = self:ComparePartialSnapshots(bagSnapshot, { scanType .. "_" .. bagID })
	-- Apply changes immediately
	local updateCount = self:ApplyImmediateChanges(changes)
	-- Update snapshot for this bag
	if not self.lastButtonSnapshot then
		self.lastButtonSnapshot = {}
	end

	for button, itemData in pairs(bagSnapshot) do
		self.lastButtonSnapshot[button] = itemData
	end

	print(string.format("|cff00ff00SURGICAL DEBUG|r - Progressive bag %s_%d: %d changes applied immediately",
		scanType, bagID, updateCount))
	return updateCount
end

-- Complete progressive surgical
function DOKI:CompleteProgressiveSurgical()
	local state = self.smartSurgicalState
	if not state then
		print("|cff00ff00SURGICAL DEBUG|r - CompleteProgressiveSurgical called but no state!")
		return 0
	end

	local surgicalDuration = GetTime() - state.startTime
	local indicatorCount = state.indicatorCount
	print(string.format("|cff00ff00SURGICAL DEBUG|r %.3f - Progressive surgical complete: %d indicators in %.3fs",
		GetTime(), indicatorCount, surgicalDuration))
	-- Clean up
	self.smartSurgicalState = nil
	return indicatorCount
end

-- Cancel smart surgical update
function DOKI:CancelSmartSurgicalUpdate()
	if self.smartSurgicalState then
		print("|cff00ff00SURGICAL DEBUG|r - Smart surgical update cancelled")
		self.smartSurgicalState = nil
	end
end

-- Snapshot creation functions (same as previous artifact)
-- Create ElvUI snapshot chunk
function DOKI:CreateElvUISnapshotChunk(bagID, snapshot)
	if not ElvUI or not self:IsElvUIBagVisible() then
		return
	end

	local function addToSnapshot(button, itemID, itemLink)
		if button then
			if itemID and itemID ~= "EMPTY_SLOT" then
				snapshot[button] = {
					itemID = itemID,
					itemLink = itemLink,
					hasItem = true,
				}
			else
				snapshot[button] = {
					itemID = nil,
					itemLink = nil,
					hasItem = false,
					isEmpty = true,
				}
			end
		end
	end

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
						addToSnapshot(button, nil, nil)
					end

					break
				end
			end
		end
	end
end

-- Create combined snapshot chunk
function DOKI:CreateCombinedSnapshotChunk(bagID, snapshot)
	if not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		return
	end

	local function addToSnapshot(button, itemID, itemLink)
		if button then
			if itemID and itemID ~= "EMPTY_SLOT" then
				snapshot[button] = {
					itemID = itemID,
					itemLink = itemLink,
					hasItem = true,
				}
			else
				snapshot[button] = {
					itemID = nil,
					itemLink = nil,
					hasItem = false,
					isEmpty = true,
				}
			end
		end
	end

	local numSlots = C_Container.GetContainerNumSlots(bagID)
	if numSlots and numSlots > 0 then
		for slotID = 1, numSlots do
			local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			if itemInfo then
				-- Find matching button
				local button = nil
				if ContainerFrameCombinedBags.EnumerateValidItems then
					for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
						if itemButton and itemButton:IsVisible() then
							local buttonBagID, buttonSlotID = nil, nil
							if itemButton.GetBagID and itemButton.GetID then
								local success1, bag = pcall(itemButton.GetBagID, itemButton)
								local success2, slot = pcall(itemButton.GetID, itemButton)
								if success1 and success2 then
									buttonBagID, buttonSlotID = bag, slot
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
					if itemInfo.itemID then
						addToSnapshot(button, itemInfo.itemID, itemInfo.hyperlink)
					else
						addToSnapshot(button, nil, nil)
					end
				end
			end
		end
	end
end

-- Create individual snapshot chunk
function DOKI:CreateIndividualSnapshotChunk(bagID, snapshot)
	local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
	if not (containerFrame and containerFrame:IsVisible()) then
		return
	end

	local function addToSnapshot(button, itemID, itemLink)
		if button then
			if itemID and itemID ~= "EMPTY_SLOT" then
				snapshot[button] = {
					itemID = itemID,
					itemLink = itemLink,
					hasItem = true,
				}
			else
				snapshot[button] = {
					itemID = nil,
					itemLink = nil,
					hasItem = false,
					isEmpty = true,
				}
			end
		end
	end

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
						addToSnapshot(button, nil, nil)
					end

					break
				end
			end
		end
	end
end

-- Create merchant snapshot chunk
function DOKI:CreateMerchantSnapshotChunk(snapshot)
	if not (MerchantFrame and MerchantFrame:IsVisible()) then
		return
	end

	local function addToSnapshot(button, itemID, itemLink)
		if button then
			if itemID and itemID ~= "EMPTY_SLOT" then
				snapshot[button] = {
					itemID = itemID,
					itemLink = itemLink,
					hasItem = true,
				}
			else
				snapshot[button] = {
					itemID = nil,
					itemLink = nil,
					hasItem = false,
					isEmpty = true,
				}
			end
		end
	end

	-- Scan merchant buttons
	for i = 1, 12 do
		local possibleButtonNames = {
			string.format("MerchantItem%dItemButton", i),
			string.format("MerchantItem%d", i),
		}
		for _, buttonName in ipairs(possibleButtonNames) do
			local button = _G[buttonName]
			if button and button:IsVisible() then
				local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
				if itemID == "EMPTY_SLOT" or not itemID then
					addToSnapshot(button, nil, nil)
				else
					addToSnapshot(button, itemID, itemLink)
				end

				break
			end
		end
	end
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
	-- Cancel dedicated surgical (instead of smart surgical)
	self:CancelDedicatedSurgical()
	-- REMOVED: No more delayed scan cleanup
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
		print("|cffff69b4DOKI|r Button texture system cleaned up (dedicated surgical)")
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
