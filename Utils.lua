-- DOKI Utils - Enhanced Surgical Update System
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
DOKI.foundFramesThisScan = {}
-- ===== ENHANCED SURGICAL UPDATE THROTTLING =====
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.1 -- 100ms minimum between updates
DOKI.pendingSurgicalUpdate = false
-- ===== PERFORMANCE MONITORING =====
function DOKI:GetPerformanceStats()
	local stats = {
		updateInterval = 0.5, -- seconds for surgical updates (reduced from 1.0)
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
	print("|cffff69b4DOKI|r === ENHANCED SURGICAL SYSTEM STATS ===")
	print(string.format("Update interval: %.1fs", stats.updateInterval))
	print(string.format("Last update duration: %.3fs", stats.lastUpdateDuration))
	print(string.format("Average update duration: %.3fs", stats.avgUpdateDuration))
	print(string.format("Total updates performed: %d", stats.totalUpdates))
	print(string.format("Immediate updates: %d", stats.immediateUpdates))
	print(string.format("Throttled updates: %d", stats.throttledUpdates))
	print(string.format("Active indicators: %d", stats.activeIndicators))
	print(string.format("Texture pool size: %d", stats.texturePoolSize))
	print(string.format("Debug mode: %s", stats.debugMode and "ON" or "OFF"))
	-- Performance assessment
	if stats.lastUpdateDuration > 0.05 then
		print("|cffffff00NOTICE:|r Update duration is moderate (>50ms)")
	else
		print("|cff00ff00GOOD:|r Update performance is optimal (<50ms)")
	end

	-- Response time info
	print(string.format("|cff00ff00ENHANCED:|r Item drop response: immediate + %.1fs throttle",
		self.surgicalUpdateThrottleTime))
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

-- ===== ENHANCED SURGICAL UPDATE SYSTEM =====
-- Enhanced surgical update with throttling
function DOKI:SurgicalUpdate(isImmediate)
	if not self.db or not self.db.enabled then return 0 end

	local currentTime = GetTime()
	-- Throttling check - prevent updates more frequent than throttle time
	if currentTime - self.lastSurgicalUpdate < self.surgicalUpdateThrottleTime then
		if not self.pendingSurgicalUpdate then
			-- Schedule a throttled update
			self.pendingSurgicalUpdate = true
			self.throttledUpdates = (self.throttledUpdates or 0) + 1
			local delay = self.surgicalUpdateThrottleTime - (currentTime - self.lastSurgicalUpdate)
			C_Timer.After(delay, function()
				if self.db and self.db.enabled and self.pendingSurgicalUpdate then
					self.pendingSurgicalUpdate = false
					self:SurgicalUpdate(false) -- Execute the throttled update
				end
			end)
			if self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Throttled update scheduled (%.3fs delay)", delay))
			end
		end

		return 0
	end

	self.lastSurgicalUpdate = currentTime
	self.pendingSurgicalUpdate = false
	if self.db.debugMode then
		local updateType = isImmediate and "IMMEDIATE" or "SCHEDULED"
		print(string.format("|cffff69b4DOKI|r === %s SURGICAL UPDATE START ===", updateType))
	end

	local startTime = GetTime()
	-- Use the button texture system's surgical update
	local changeCount = 0
	if self.SurgicalUpdate then
		changeCount = self:SurgicalUpdate()
	end

	local updateDuration = GetTime() - startTime
	self:TrackUpdatePerformance(updateDuration, isImmediate)
	if self.db.debugMode then
		local updateType = isImmediate and "immediate" or "scheduled"
		print(string.format("|cffff69b4DOKI|r %s surgical update: %d changes in %.3fs",
			updateType, changeCount, updateDuration))
		print("|cffff69b4DOKI|r === SURGICAL UPDATE END ===")
	end

	return changeCount
end

-- Immediate surgical update trigger (for events)
function DOKI:TriggerImmediateSurgicalUpdate()
	if not self.db or not self.db.enabled then return end

	-- Only trigger if relevant UI is visible
	if (ElvUI and self:IsElvUIBagVisible()) or
			(ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) or
			(MerchantFrame and MerchantFrame:IsVisible()) then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Item movement detected - triggering immediate update")
		end

		self:SurgicalUpdate(true) -- Mark as immediate update
	end
end

-- Full scan for initial setup or when explicitly requested
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
											indicatorCount = indicatorCount + self:CreateUniversalIndicator(elvUIButton, itemData)
											if self.db.debugMode then
												table.insert(self.foundFramesThisScan, {
													frame = elvUIButton,
													frameName = elvUIButtonName,
													itemData = itemData,
												})
											end
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

	-- Scan Blizzard bags if visible
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Scanning Blizzard bags...")
		end

		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					local frameName = itemButton:GetName() or "CombinedBagItem"
					local itemData = self:ExtractItemFromAnyFrameOptimized(itemButton, frameName)
					if itemData then
						indicatorCount = indicatorCount + self:CreateUniversalIndicator(itemButton, itemData)
						if self.db.debugMode then
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

	return indicatorCount
end

-- Create universal indicator (surgical version)
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

	-- Check if indicator already exists for this exact item
	if self.buttonTextures and self.buttonTextures[frame] then
		local existingTexture = self.buttonTextures[frame]
		if existingTexture and existingTexture.isActive and existingTexture.itemID == itemData.itemID then
			-- Same item, same indicator - no change needed
			return 0
		end
	end

	-- Add or update button indicator
	if self.AddButtonIndicator then
		local success = self:AddButtonIndicator(frame, itemData)
		return success and 1 or 0
	end

	return 0
end

-- ===== ENHANCED EVENT SYSTEM FOR RESPONSIVE UPDATES =====
function DOKI:SetupMinimalEventSystem()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	-- Enhanced event list with item movement detection
	local events = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"ITEM_UNLOCKED", -- Key addition: fires when items are dropped/moved
	}
	for _, event in ipairs(events) do
		self.eventFrame:RegisterEvent(event)
	end

	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		if not (DOKI.db and DOKI.db.enabled) then return end

		if DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r UI Event: %s", event))
		end

		-- Handle UI state changes with full scans
		if event == "MERCHANT_SHOW" or event == "BANKFRAME_OPENED" then
			-- UI opened - do full scan after short delay
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "MERCHANT_CLOSED" or event == "BANKFRAME_CLOSED" then
			-- UI closed - clean up specific textures
			if event == "MERCHANT_CLOSED" and DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			elseif event == "BANKFRAME_CLOSED" and DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "ITEM_UNLOCKED" then
			-- Item movement detected - trigger immediate surgical update
			-- Small delay to ensure UI has updated
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced event system: immediate item movement response")
	end
end

-- ===== MAIN SYSTEM INITIALIZATION =====
function DOKI:InitializeUniversalScanning()
	-- Clear any existing timers
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	-- Initialize throttling state
	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Set up enhanced surgical update timer - now 0.5 seconds (improved from 1.0s)
	self.surgicalTimer = C_Timer.NewTicker(0.5, function()
		if self.db and self.db.enabled then
			-- Only do surgical updates if any UI is visible
			if (ElvUI and self:IsElvUIBagVisible()) or
					(ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) or
					(MerchantFrame and MerchantFrame:IsVisible()) then
				DOKI:SurgicalUpdate(false) -- Regular scheduled update
			end
		end
	end)
	-- Set up enhanced event system for immediate responses
	self:SetupMinimalEventSystem()
	-- Initial full scan
	self:FullItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced surgical system initialized:")
		print("|cffff69b4DOKI|r - Regular updates: 0.5s interval")
		print("|cffff69b4DOKI|r - Immediate updates: ITEM_UNLOCKED event")
		print(string.format("|cffff69b4DOKI|r - Throttling: %.1fs minimum between updates", self.surgicalUpdateThrottleTime))
	end
end

function DOKI:ForceUniversalScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Force full scan...")
	end

	return self:FullItemScan()
end

-- ===== LEGACY COMPATIBILITY =====
function DOKI:UniversalItemScan()
	-- Legacy function - redirect to surgical update
	return self:SurgicalUpdate(false)
end

function DOKI:ClearUniversalOverlays()
	-- Legacy function - just do cleanup
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

-- Enhanced ElvUI bag visibility check
function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or (B.BankFrame and B.BankFrame:IsShown())
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

	-- Quick filter check
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
	-- Only process actual merchant item buttons
	local merchantIndex = frameName:match("MerchantItem(%d+)ItemButton")
	if merchantIndex then
		local itemLink = GetMerchantItemLink(tonumber(merchantIndex))
		return itemLink and self:GetItemID(itemLink)
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
	elseif frameName:match("ActionButton") then
		return "actionbar"
	elseif frameName:match("Bank.*Item") then
		return "bank"
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

	return false, showYellowD -- Don't have this variant, but return blue D flag if have other sources
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
	-- Simplified for surgical system - just check if we have any other sources
	return self:HasOtherTransmogSources(itemAppearanceID, excludeModifiedAppearanceID)
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

-- Test enhanced surgical update system
function DOKI:TestSurgicalSystem()
	print("|cffff69b4DOKI|r === TESTING ENHANCED SURGICAL SYSTEM ===")
	-- Create initial snapshot
	local snapshot1 = self:CreateButtonSnapshot()
	local count1 = 0
	for _ in pairs(snapshot1) do count1 = count1 + 1 end

	print(string.format("Current snapshot: %d buttons with items", count1))
	print("|cffff69b4DOKI|r Enhanced features:")
	print("  - Regular updates every 0.5s (improved from 1.0s)")
	print("  - Immediate updates on ITEM_UNLOCKED events")
	print(string.format("  - Throttling: %.1fs minimum between updates", self.surgicalUpdateThrottleTime))
	print("|cffff69b4DOKI|r Now try moving an item and watch for immediate response...")
	-- Set up a test timer to show changes
	local testTimer = C_Timer.NewTicker(2.0, function()
		local snapshot2 = self:CreateButtonSnapshot()
		local count2 = 0
		for _ in pairs(snapshot2) do count2 = count2 + 1 end

		local changes = 0
		for button, itemID in pairs(snapshot2) do
			if snapshot1[button] ~= itemID then
				changes = changes + 1
			end
		end

		for button, itemID in pairs(snapshot1) do
			if snapshot2[button] ~= itemID then
				changes = changes + 1
			end
		end

		if changes > 0 then
			print(string.format("|cffff69b4DOKI|r Detected %d button changes", changes))
			snapshot1 = snapshot2
		end
	end)
	-- Cancel test after 30 seconds
	C_Timer.After(30, function()
		testTimer:Cancel()
		print("|cffff69b4DOKI|r Enhanced surgical system test ended")
	end)
end
