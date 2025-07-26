-- DOKI Utils - Clean Enhanced Surgical Update System
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
DOKI.foundFramesThisScan = {}
-- ===== SURGICAL UPDATE THROTTLING =====
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.05 -- 50ms minimum between updates (reduced from 150ms)
DOKI.pendingSurgicalUpdate = false
-- ===== PERFORMANCE MONITORING =====
function DOKI:GetPerformanceStats()
	local stats = {
		updateInterval = 0.2, -- Updated to reflect new faster interval
		lastUpdateDuration = self.lastUpdateDuration or 0,
		avgUpdateDuration = self.avgUpdateDuration or 0,
		totalUpdates = self.totalUpdates or 0,
		immediateUpdates = self.immediateUpdates or 0,
		throttledUpdates = self.throttledUpdates or 0,
		activeIndicators = 0,
		texturePoolSize = #(self.texturePool or {}),
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
	print("|cffff69b4DOKI|r === SURGICAL SYSTEM STATS ===")
	print(string.format("Update interval: %.1fs", stats.updateInterval))
	print(string.format("Last update duration: %.3fs", stats.lastUpdateDuration))
	print(string.format("Average update duration: %.3fs", stats.avgUpdateDuration))
	print(string.format("Total updates performed: %d", stats.totalUpdates))
	print(string.format("Immediate updates: %d", stats.immediateUpdates))
	print(string.format("Throttled updates: %d", stats.throttledUpdates))
	print(string.format("Active indicators: %d", stats.activeIndicators))
	print(string.format("Texture pool size: %d", stats.texturePoolSize))
	print(string.format("Debug mode: %s", stats.debugMode and "ON" or "OFF"))
	if stats.lastUpdateDuration > 0.05 then
		print("|cffffff00NOTICE:|r Update duration is moderate (>50ms)")
	else
		print("|cff00ff00GOOD:|r Update performance is optimal (<50ms)")
	end

	print("|cffff69b4DOKI|r === END STATS ===")
end

function DOKI:TrackUpdatePerformance(duration, isImmediate)
	self.lastUpdateDuration = duration
	self.totalUpdates = (self.totalUpdates or 0) + 1
	if isImmediate then
		self.immediateUpdates = (self.immediateUpdates or 0) + 1
	end

	-- Calculate rolling average (last 10 updates)
	if not self.updateDurations then
		self.updateDurations = {}
	end

	table.insert(self.updateDurations, duration)
	if #self.updateDurations > 10 then
		table.remove(self.updateDurations, 1)
	end

	local total = 0
	for _, d in ipairs(self.updateDurations) do
		total = total + d
	end

	self.avgUpdateDuration = total / #self.updateDurations
end

-- ===== SURGICAL UPDATE SYSTEM =====
function DOKI:SurgicalUpdate(isImmediate)
	if not self.db or not self.db.enabled then return 0 end

	local currentTime = GetTime()
	-- Throttling check
	if currentTime - self.lastSurgicalUpdate < self.surgicalUpdateThrottleTime then
		if not self.pendingSurgicalUpdate then
			self.pendingSurgicalUpdate = true
			self.throttledUpdates = (self.throttledUpdates or 0) + 1
			local delay = self.surgicalUpdateThrottleTime - (currentTime - self.lastSurgicalUpdate)
			C_Timer.After(delay, function()
				if self.db and self.db.enabled and self.pendingSurgicalUpdate then
					self.pendingSurgicalUpdate = false
					self:SurgicalUpdate(false)
				end
			end)
		end

		return 0
	end

	self.lastSurgicalUpdate = currentTime
	self.pendingSurgicalUpdate = false
	if self.db.debugMode then
		local updateType = isImmediate and "IMMEDIATE" or "SCHEDULED"
		-- Only show debug for immediate updates or when changes are expected
		if isImmediate then
			print(string.format("|cffff69b4DOKI|r === %s SURGICAL UPDATE START ===", updateType))
		end
	end

	local startTime = GetTime()
	local changeCount = 0
	-- Call the button texture system's surgical update
	if self.ProcessSurgicalUpdate then
		changeCount = self:ProcessSurgicalUpdate()
	end

	local updateDuration = GetTime() - startTime
	self:TrackUpdatePerformance(updateDuration, isImmediate)
	if self.db.debugMode then
		local updateType = isImmediate and "immediate" or "scheduled"
		-- Only show debug for immediate updates or when there are actual changes
		if isImmediate or changeCount > 0 then
			print(string.format("|cffff69b4DOKI|r %s surgical update: %d changes in %.3fs",
				updateType, changeCount, updateDuration))
			if isImmediate then
				print("|cffff69b4DOKI|r === SURGICAL UPDATE END ===")
			end
		end
	end

	return changeCount
end

-- Immediate surgical update trigger
function DOKI:TriggerImmediateSurgicalUpdate()
	if not self.db or not self.db.enabled then return end

	-- Only trigger if relevant UI is visible
	local anyUIVisible = false
	-- Check ElvUI
	if ElvUI and self:IsElvUIBagVisible() then
		anyUIVisible = true
	end

	-- Check Blizzard UI
	if not anyUIVisible then
		if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
			anyUIVisible = true
		end

		if not anyUIVisible then
			for bagID = 0, NUM_BAG_SLOTS do
				local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
				if containerFrame and containerFrame:IsVisible() then
					anyUIVisible = true
					break
				end
			end
		end
	end

	-- Check merchant
	if not anyUIVisible and MerchantFrame and MerchantFrame:IsVisible() then
		anyUIVisible = true
	end

	if anyUIVisible then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Item movement detected - triggering immediate update")
		end

		self:SurgicalUpdate(true)
	end
end

-- Full scan for initial setup
function DOKI:FullItemScan()
	if not self.db or not self.db.enabled then return 0 end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r === FULL SCAN START ===")
	end

	local startTime = GetTime()
	local indicatorCount = 0
	self.foundFramesThisScan = {}
	-- Scan all UI elements
	indicatorCount = indicatorCount + self:ScanMerchantFrames()
	indicatorCount = indicatorCount + self:ScanBagFrames()
	-- Update snapshot after full scan
	if self.CreateButtonSnapshot then
		self.lastButtonSnapshot = self:CreateButtonSnapshot()
	end

	local scanDuration = GetTime() - startTime
	self:TrackUpdatePerformance(scanDuration, false)
	if self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Full scan: %d indicators in %.3fs",
			indicatorCount, scanDuration))
		print("|cffff69b4DOKI|r === FULL SCAN END ===")
	end

	return indicatorCount
end

function DOKI:ScanMerchantFrames()
	local indicatorCount = 0
	if not (MerchantFrame and MerchantFrame:IsVisible()) then
		return 0
	end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r Scanning merchant frames...")
	end

	for i = 1, 10 do
		local buttonName = "MerchantItem" .. i .. "ItemButton"
		local button = _G[buttonName]
		if button and button:IsVisible() then
			local itemData = self:ExtractItemFromAnyFrameOptimized(button, buttonName)
			if itemData then
				indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
				if self.db.debugMode then
					table.insert(self.foundFramesThisScan, {
						frame = button,
						frameName = buttonName,
						itemData = itemData,
					})
				end
			end
		end
	end

	return indicatorCount
end

function DOKI:ScanBagFrames()
	local indicatorCount = 0
	-- Scan ElvUI bags if visible
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				if self.db.debugMode then
					print("|cffff69b4DOKI|r Scanning ElvUI bags...")
				end

				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
								if self:IsCollectibleItem(itemInfo.itemID) then
									local possibleNames = {
										string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
										string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
										string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
									}
									for _, elvUIButtonName in ipairs(possibleNames) do
										local elvUIButton = _G[elvUIButtonName]
										if elvUIButton and elvUIButton:IsVisible() then
											local isCollected, showYellowD = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
											local itemData = {
												itemID = itemInfo.itemID,
												itemLink = itemInfo.hyperlink,
												isCollected = isCollected,
												showYellowD = showYellowD,
												frameType = "bag",
											}
											indicatorCount = indicatorCount + self:CreateUniversalIndicator(elvUIButton, itemData)
											if self.db.debugMode then
												local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
												print(string.format("|cffff69b4DOKI|r Found %s (ID: %d) in ElvUI bag %d slot %d - %s",
													itemName, itemInfo.itemID, bagID, slotID,
													isCollected and "COLLECTED" or "NOT collected"))
												table.insert(self.foundFramesThisScan, {
													frame = elvUIButton,
													frameName = elvUIButtonName,
													itemData = itemData,
												})
											end

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
	end

	-- Scan Blizzard bags using container API approach
	local scannedBlizzardBags = false
	-- Combined bags (newer interface)
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Scanning Blizzard combined bags...")
		end

		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						if self:IsCollectibleItem(itemInfo.itemID) then
							-- Find the corresponding button
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
								local isCollected, showYellowD = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
								local itemData = {
									itemID = itemInfo.itemID,
									itemLink = itemInfo.hyperlink,
									isCollected = isCollected,
									showYellowD = showYellowD,
									frameType = "bag",
								}
								indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
								if self.db.debugMode then
									local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
									print(string.format("|cffff69b4DOKI|r Found %s (ID: %d) in Blizzard bag %d slot %d - %s",
										itemName, itemInfo.itemID, bagID, slotID,
										isCollected and "COLLECTED" or "NOT collected"))
									table.insert(self.foundFramesThisScan, {
										frame = button,
										frameName = button:GetName() or "CombinedBagItem",
										itemData = itemData,
									})
								end
							end
						end
					end
				end
			end
		end

		scannedBlizzardBags = true
	end

	-- Individual container frames (classic interface)
	if not scannedBlizzardBags then
		for bagID = 0, NUM_BAG_SLOTS do
			local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
			if containerFrame and containerFrame:IsVisible() then
				if self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Scanning container frame %d...", bagID + 1))
				end

				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
							if self:IsCollectibleItem(itemInfo.itemID) then
								local possibleNames = {
									string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
									string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
								}
								for _, buttonName in ipairs(possibleNames) do
									local button = _G[buttonName]
									if button and button:IsVisible() then
										local isCollected, showYellowD = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
										local itemData = {
											itemID = itemInfo.itemID,
											itemLink = itemInfo.hyperlink,
											isCollected = isCollected,
											showYellowD = showYellowD,
											frameType = "bag",
										}
										indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
										if self.db.debugMode then
											local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
											print(string.format("|cffff69b4DOKI|r Found %s (ID: %d) in container bag %d slot %d - %s",
												itemName, itemInfo.itemID, bagID, slotID,
												isCollected and "COLLECTED" or "NOT collected"))
											table.insert(self.foundFramesThisScan, {
												frame = button,
												frameName = buttonName,
												itemData = itemData,
											})
										end

										break
									end
								end
							end
						end
					end
				end

				scannedBlizzardBags = true
			end
		end
	end

	return indicatorCount
end

-- Create universal indicator
function DOKI:CreateUniversalIndicator(frame, itemData)
	if itemData.isCollected then
		if self.RemoveButtonIndicator then
			self:RemoveButtonIndicator(frame)
		end

		return 0
	end

	if not frame or type(frame) ~= "table" then return 0 end

	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Check if indicator already exists for this exact item
	if self.buttonTextures and self.buttonTextures[frame] then
		local existingTexture = self.buttonTextures[frame]
		if existingTexture and existingTexture.isActive and existingTexture.itemID == itemData.itemID then
			return 0
		end
	end

	-- Add button indicator
	if self.AddButtonIndicator then
		local success = self:AddButtonIndicator(frame, itemData)
		return success and 1 or 0
	end

	return 0
end

-- ===== EVENT SYSTEM =====
function DOKI:SetupMinimalEventSystem()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	local events = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"ITEM_UNLOCKED",     -- When item is dropped
		"BAG_UPDATE",        -- When bag contents change
		"BAG_UPDATE_DELAYED", -- Delayed bag update
		"ITEM_LOCK_CHANGED", -- When item lock status changes (pickup/drop)
		"BAG_UPDATE_COOLDOWN", -- Another bag update event
		"CURSOR_CHANGED",    -- When cursor state changes (item pickup/drop)
	}
	for _, event in ipairs(events) do
		self.eventFrame:RegisterEvent(event)
	end

	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		if not (DOKI.db and DOKI.db.enabled) then return end

		if DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Event: %s", event))
		end

		if event == "MERCHANT_SHOW" or event == "BANKFRAME_OPENED" then
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "MERCHANT_CLOSED" or event == "BANKFRAME_CLOSED" then
			if event == "MERCHANT_CLOSED" and DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			elseif event == "BANKFRAME_CLOSED" and DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "ITEM_UNLOCKED" then
			-- Item movement detected - immediate response
			C_Timer.After(0.02, function() -- Reduced from 0.05s to 0.02s
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "ITEM_LOCK_CHANGED" or event == "CURSOR_CHANGED" then
			-- Item pickup/drop detected - very immediate response
			C_Timer.After(0.01, function() -- Even faster for these events
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN" then
			-- Check if should update based on UI visibility
			local shouldUpdate = false
			if ElvUI and DOKI:IsElvUIBagVisible() then
				shouldUpdate = true
			elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
				shouldUpdate = true
			else
				for bagID = 0, NUM_BAG_SLOTS do
					local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
					if containerFrame and containerFrame:IsVisible() then
						shouldUpdate = true
						break
					end
				end
			end

			if shouldUpdate then
				local delay = (event == "BAG_UPDATE_DELAYED") and 0.1 or 0.05
				C_Timer.After(delay, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Event system initialized")
	end
end

-- ===== INITIALIZATION =====
function DOKI:InitializeUniversalScanning()
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Enhanced surgical update timer (0.2s intervals for more responsive fallback)
	self.surgicalTimer = C_Timer.NewTicker(0.2, function() -- Reduced from 0.5s to 0.2s
		if self.db and self.db.enabled then
			local anyUIVisible = false
			if ElvUI and self:IsElvUIBagVisible() then
				anyUIVisible = true
			elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
				anyUIVisible = true
			else
				for bagID = 0, NUM_BAG_SLOTS do
					local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
					if containerFrame and containerFrame:IsVisible() then
						anyUIVisible = true
						break
					end
				end
			end

			-- Also check if cursor has an item (indicates active item movement)
			local cursorHasItem = C_Cursor and C_Cursor.GetCursorItem() and true or false
			if anyUIVisible or (MerchantFrame and MerchantFrame:IsVisible()) or cursorHasItem then
				DOKI:SurgicalUpdate(false)
			end
		end
	end)
	self:SetupMinimalEventSystem()
	self:FullItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced surgical system initialized")
		print("  |cff00ff00•|r Regular updates: 0.2s interval (enhanced responsiveness)")
		print("  |cff00ff00•|r Immediate updates: Multiple events + cursor detection")
		print(string.format("  |cff00ff00•|r Throttling: %.0fms minimum between updates",
			self.surgicalUpdateThrottleTime * 1000))
	end
end

-- ===== UTILITY FUNCTIONS =====
function DOKI:ForceUniversalScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Force full scan...")
	end

	return self:FullItemScan()
end

function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or (B.BankFrame and B.BankFrame:IsShown())
end

-- Include the core collection checking functions from your working code
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

	-- Check transmog
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

	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then return true, false end

	local showYellowD = false
	if itemAppearanceID then
		local hasOtherSources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasOtherSources then
			showYellowD = true
		end
	end

	return false, showYellowD
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
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r No appearance ID for item %d", itemID))
		end

		return false, false
	end

	-- Check if we have this specific variant
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Item %d - have this specific variant", itemID))
		end

		return true, false -- Have this variant, no indicator needed
	end

	-- We don't have this variant - check if we have equal or better sources
	if itemAppearanceID then
		local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasEqualOrBetterSources then
			-- We have identical or less restrictive sources, so we don't need this item
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d - have equal or better sources, no D needed", itemID))
			end

			return true, false -- Treat as collected (no D shown)
		else
			-- We either have no sources, or only more restrictive sources - show orange D
			local hasAnySources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
			if self.db and self.db.debugMode then
				if hasAnySources then
					print(string.format(
						"|cffff69b4DOKI|r Item %d - have other sources but they're more restrictive, show orange D", itemID))
				else
					print(string.format("|cffff69b4DOKI|r Item %d - no sources at all, show orange D", itemID))
				end
			end

			return false, false -- Show orange D (we need this item)
		end
	end

	return false, false -- Default to orange D
end

-- Get class and faction restrictions for a specific source
function DOKI:GetClassRestrictionsForSource(sourceID, appearanceID)
	local restrictions = {
		validClasses = {},
		armorType = nil,
		hasClassRestriction = false,
		faction = nil, -- "Alliance", "Horde", or nil (both factions)
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
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Could not get item ID for source %d", sourceID))
		end

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
	local foundFactionRestriction = false
	local restrictedClasses = {}
	for i = 1, tooltip:NumLines() do
		local line = _G["DOKIClassTooltip" .. sourceID .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text then
				-- Check for class restrictions
				if string.find(text, "Classes:") then
					foundClassRestriction = true
					-- Parse "Classes: Rogue" or "Classes: Warrior, Paladin, Death Knight"
					local classText = string.match(text, "Classes:%s*(.+)")
					if classText then
						-- Map class names to IDs
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
						-- Split by comma and convert to class IDs
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
						foundFactionRestriction = true
						restrictions.faction = "Alliance"
						restrictions.hasFactionRestriction = true
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Found Alliance restriction for item %d: %s", linkedItemID, text))
						end
					end
				elseif string.find(lowerText, "horde") then
					if string.find(lowerText, "require") or string.find(lowerText, "only") or
							string.find(lowerText, "exclusive") or string.find(lowerText, "specific") or
							string.find(lowerText, "reputation") or string.find(text, "Horde") then
						foundFactionRestriction = true
						restrictions.faction = "Horde"
						restrictions.hasFactionRestriction = true
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Found Horde restriction for item %d: %s", linkedItemID, text))
						end
					end
				end
			end
		end
	end

	tooltip:Hide()
	if foundClassRestriction then
		-- Item has explicit class restrictions
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

-- Check if we have sources with identical or less restrictive class AND faction sets
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
					-- Compare faction restrictions (faction-agnostic logic)
					local factionEquivalent = false
					-- For factions to be equivalent, they must be exactly the same
					if sourceRestrictions.hasFactionRestriction == currentItemRestrictions.hasFactionRestriction then
						if not sourceRestrictions.hasFactionRestriction then
							-- Both have no faction restriction = equivalent
							factionEquivalent = true
						elseif sourceRestrictions.faction == currentItemRestrictions.faction then
							-- Both have same faction restriction = equivalent
							factionEquivalent = true
						end
					end

					-- Only compare class restrictions if faction restrictions are equivalent
					if factionEquivalent then
						-- Check if source is less restrictive in terms of classes
						if sourceClassCount > currentClassCount then
							if self.db and self.db.debugMode then
								print(string.format(
									"|cffff69b4DOKI|r Found less restrictive source %d (usable by %d classes vs %d, same faction restrictions)",
									sourceID, sourceClassCount, currentClassCount))
							end

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
								if self.db and self.db.debugMode then
									local factionText = sourceRestrictions.hasFactionRestriction and
											(" (same " .. sourceRestrictions.faction .. " restriction)") or " (no faction restriction)"
									print(string.format("|cffff69b4DOKI|r Found identical restriction source %d (same classes: %s)%s",
										sourceID, table.concat(sourceCopy, ", "), factionText))
								end

								return true
							end
						end
					else
						-- Different faction restrictions - sources are not equivalent
						if self.db and self.db.debugMode then
							local currentFactionText = currentItemRestrictions.hasFactionRestriction and
									currentItemRestrictions.faction or "none"
							local sourceFactionText = sourceRestrictions.hasFactionRestriction and sourceRestrictions.faction or "none"
							print(string.format(
								"|cffff69b4DOKI|r Source %d has different faction restrictions (%s vs %s) - not equivalent",
								sourceID, sourceFactionText, currentFactionText))
						end
					end
				end
			end
		end
	end

	return false
end

function DOKI:HasOtherTransmogSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	local success, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not sourceIDs or type(sourceIDs) ~= "table" then return false end

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

-- Debug functions
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

-- Legacy compatibility
function DOKI:UniversalItemScan()
	return self:SurgicalUpdate(false)
end

function DOKI:ClearUniversalOverlays()
	if self.CleanupButtonTextures then
		return self:CleanupButtonTextures()
	end

	return 0
end

function DOKI:ClearAllOverlays()
	if self.ClearAllButtonIndicators then
		return self:ClearAllButtonIndicators()
	end

	return 0
end
