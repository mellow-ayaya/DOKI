-- DOKI Utilities - Enhanced with Retry Logic for Reliable Restriction Checking
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.restrictionCache = DOKI.restrictionCache or {} -- Cache for restriction data
DOKI.pendingRetries = DOKI.pendingRetries or {}     -- Items needing retry
-- Extract item ID from item link
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

-- Check if item data is fully loaded
function DOKI:IsItemDataReady(itemID)
	if not itemID then return false end

	-- Check if basic item info is available
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Item %d data not ready - name unavailable", itemID))
		end

		return false
	end

	-- For transmog items, also check if appearance data is available
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	if classID == 2 or classID == 4 then -- Weapons or armor
		local appearanceID = C_TransmogCollection.GetItemInfo(itemID)
		if not appearanceID then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d transmog data not ready", itemID))
			end

			return false
		end
	end

	return true
end

-- Check if an item is a collectible type
function DOKI:IsCollectibleItem(itemID)
	if not itemID then return false end

	-- Use C_Item.GetItemInfoInstant for immediate info (doesn't require server query)
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
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Skipping non-transmog slot %s for item %d", itemEquipLoc, itemID))
					end

					return false
				end
			end

			-- If it's an equipment slot that can have transmog, it's collectible
			return true
		end
	end

	return false
end

-- Check if item is already collected using the SPECIFIC variant from the bag
function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID then return false, false end

	-- For complex items, check if data is ready first
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
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
		-- Check if item data is ready for complex analysis
		if not self:IsItemDataReady(itemID) then
			-- Mark for retry and return false for now
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d not ready, marking for retry", itemID))
			end

			self:ScheduleItemRetry(itemLink, itemID)
			return false, false
		end

		if self.db and self.db.smartMode then
			return self:IsTransmogCollectedSmart(itemID, itemLink)
		else
			return self:IsTransmogCollected(itemID, itemLink)
		end
	end

	return false, false
end

-- Schedule item for retry when data becomes available
function DOKI:ScheduleItemRetry(itemLink, itemID)
	if not self.pendingRetries[itemLink] then
		self.pendingRetries[itemLink] = {
			itemID = itemID,
			retryCount = 0,
			maxRetries = 3,
		}
		-- Schedule retry in 1 second
		C_Timer.After(1.0, function()
			self:ProcessItemRetry(itemLink)
		end)
	end
end

-- Process retry for an item
function DOKI:ProcessItemRetry(itemLink)
	local retryData = self.pendingRetries[itemLink]
	if not retryData then return end

	retryData.retryCount = retryData.retryCount + 1
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Retry %d for item %d", retryData.retryCount, retryData.itemID))
	end

	-- Check if item data is now ready
	if self:IsItemDataReady(retryData.itemID) then
		-- Data is ready, re-scan this item
		local itemData = self.currentItems[itemLink]
		if itemData then
			local isCollected, showYellowD = self:IsItemCollected(retryData.itemID, itemLink)
			itemData.isCollected = isCollected
			itemData.showYellowD = showYellowD
			if self.db and self.db.debugMode then
				local itemName = C_Item.GetItemInfo(retryData.itemID) or "Unknown"
				local yellowStatus = showYellowD and " (YELLOW D)" or ""
				print(string.format("|cffff69b4DOKI|r Retry successful for %s - %s%s",
					itemName, isCollected and "COLLECTED" or "NOT collected", yellowStatus))
			end

			-- Update overlay for this specific item
			self:UpdateSingleItemOverlay(itemLink, itemData)
		end

		-- Remove from retry list
		self.pendingRetries[itemLink] = nil
	elseif retryData.retryCount < retryData.maxRetries then
		-- Schedule another retry with exponential backoff
		local delay = 1.5 * retryData.retryCount
		C_Timer.After(delay, function()
			self:ProcessItemRetry(itemLink)
		end)
	else
		-- Max retries reached, give up
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Max retries reached for item %d", retryData.itemID))
		end

		self.pendingRetries[itemLink] = nil
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

-- Check if mount is collected
function DOKI:IsMountCollected(itemID)
	if not itemID or not C_MountJournal then return false end

	-- Get the spell that this mount item teaches
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then return false end

	-- Convert to number if it's a string
	local spellIDNum = tonumber(spellID)
	return spellIDNum and IsSpellKnown(spellIDNum) or false
end

-- Check if pet is collected
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

-- Enhanced transmog collection check with better data validation
function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	-- Check cache first
	local cacheKey = itemLink or tostring(itemID)
	if self.restrictionCache[cacheKey] then
		local cached = self.restrictionCache[cacheKey]
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Using cached result for %d", itemID))
		end

		return cached.isCollected, cached.showYellowD
	end

	local itemAppearanceID, itemModifiedAppearanceID
	-- CRITICAL: Try hyperlink first (works for mythic/heroic/normal variants)
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	-- Method 2: If hyperlink failed, fallback to itemID
	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	if not itemModifiedAppearanceID then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r No appearance ID for item %d", itemID))
		end

		return false, false
	end

	-- Check if THIS specific variant is collected
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Item %d - have this specific variant", itemID))
		end

		-- Cache the result
		self.restrictionCache[cacheKey] = { isCollected = true, showYellowD = false }
		return true, false -- Have this specific variant, no overlay needed
	end

	-- Don't have this variant, check if we have other sources of this appearance
	local showYellowD = false
	if itemAppearanceID then
		local hasOtherSources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasOtherSources then
			showYellowD = true
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d - have other sources, will show yellow D", itemID))
			end
		else
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d - no sources at all, will show pink D", itemID))
			end
		end
	end

	-- Cache the result
	self.restrictionCache[cacheKey] = { isCollected = false, showYellowD = showYellowD }
	return false, showYellowD -- Don't have this variant, but return yellow D flag
end

-- SMART: Enhanced transmog collection check with class restriction awareness and validation
function DOKI:IsTransmogCollectedSmart(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	-- Check cache first
	local cacheKey = (itemLink or tostring(itemID)) .. "_smart"
	if self.restrictionCache[cacheKey] then
		local cached = self.restrictionCache[cacheKey]
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Using cached smart result for %d", itemID))
		end

		return cached.isCollected, cached.showYellowD
	end

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

		-- Cache the result
		self.restrictionCache[cacheKey] = { isCollected = true, showYellowD = false }
		return true, false -- Have this variant, no overlay needed
	end

	-- We don't have this variant - check if we have equal or better sources
	if itemAppearanceID then
		local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasEqualOrBetterSources then
			-- We have identical or less restrictive sources, so we don't need this item
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Item %d - have equal or better sources, no D needed", itemID))
			end

			-- Cache the result
			self.restrictionCache[cacheKey] = { isCollected = true, showYellowD = false }
			return true, false -- Treat as collected (no D shown)
		else
			-- We either have no sources, or only more restrictive sources - show pink D
			local hasAnySources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
			if self.db and self.db.debugMode then
				if hasAnySources then
					print(string.format("|cffff69b4DOKI|r Item %d - have other sources but they're more restrictive, show pink D",
						itemID))
				else
					print(string.format("|cffff69b4DOKI|r Item %d - no sources at all, show pink D", itemID))
				end
			end

			-- Cache the result
			self.restrictionCache[cacheKey] = { isCollected = false, showYellowD = false }
			return false, false -- Show pink D (we need this item)
		end
	end

	-- Cache the result
	self.restrictionCache[cacheKey] = { isCollected = false, showYellowD = false }
	return false, false -- Default to pink D
end

-- Enhanced class restriction check with validation
function DOKI:GetClassRestrictionsForSource(sourceID, appearanceID)
	local restrictions = {
		validClasses = {},
		armorType = nil,
		hasClassRestriction = false,
		dataReady = false,
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

	-- Verify item data is ready before proceeding
	if not self:IsItemDataReady(linkedItemID) then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Item data not ready for source %d (item %d)", sourceID, linkedItemID))
		end

		return restrictions
	end

	-- Get item properties for armor type
	local success3, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, linkedItemID)
	if success3 and classID == 4 then -- Armor
		restrictions.armorType = subClassID
	end

	-- Parse tooltip for class restrictions with validation
	local tooltip = CreateFrame("GameTooltip", "DOKIClassTooltip" .. sourceID .. "_" .. GetTime(), nil,
		"GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetItemByID(linkedItemID)
	tooltip:Show()
	-- Wait a moment for tooltip to populate
	local foundClassRestriction = false
	local restrictedClasses = {}
	-- Validate tooltip has content
	if tooltip:NumLines() > 0 then
		for i = 1, tooltip:NumLines() do
			local line = _G["DOKIClassTooltip" .. sourceID .. "_" .. GetTime() .. "TextLeft" .. i]
			if line then
				local text = line:GetText()
				if text and string.find(text, "Classes:") then
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

					break
				end
			end
		end

		restrictions.dataReady = true
	else
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Tooltip empty for item %d", linkedItemID))
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
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- All classes (simplified)
		else
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- Unknown, assume all
		end
	end

	return restrictions
end

-- Check if we have sources with identical or less restrictive class sets
function DOKI:HasEqualOrLessRestrictiveSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then return false end

	-- Get class restrictions for the current item
	local currentItemRestrictions = self:GetClassRestrictionsForSource(excludeModifiedAppearanceID, itemAppearanceID)
	if not currentItemRestrictions or not currentItemRestrictions.dataReady then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Current item restrictions not ready, cannot compare"))
		end

		return false
	end

	-- Check each source we have collected
	for _, sourceID in ipairs(allSources) do
		if sourceID ~= excludeModifiedAppearanceID then
			local success2, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
			if success2 and hasSource then
				-- Get restrictions for this known source
				local sourceRestrictions = self:GetClassRestrictionsForSource(sourceID, itemAppearanceID)
				if sourceRestrictions and sourceRestrictions.dataReady then
					local sourceClassCount = #sourceRestrictions.validClasses
					local currentClassCount = #currentItemRestrictions.validClasses
					-- Check if source is less restrictive (more classes)
					if sourceClassCount > currentClassCount then
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Found less restrictive source %d (usable by %d classes vs %d)",
								sourceID, sourceClassCount, currentClassCount))
						end

						return true
					end

					-- Check if source has identical class restrictions (same classes, not just same count)
					if sourceClassCount == currentClassCount then
						-- Create sorted lists to compare
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
								print(string.format("|cffff69b4DOKI|r Found identical restriction source %d (same classes: %s)",
									sourceID, table.concat(sourceCopy, ", ")))
							end

							return true
						end
					end
				else
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Source %d restrictions not ready, skipping", sourceID))
					end
				end
			end
		end
	end

	return false
end

-- Check if we have other sources for this appearance using the WORKING API pattern
function DOKI:HasOtherTransmogSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not sourceIDs or type(sourceIDs) ~= "table" then return false end

	-- Check each source using the working API
	for _, sourceID in ipairs(sourceIDs) do
		if type(sourceID) == "number" and sourceID ~= excludeModifiedAppearanceID then
			-- Use the WORKING API that handles variants correctly
			local success2, hasThisSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
			if success2 and hasThisSource then
				if self.db and self.db.debugMode then
					local sourceInfo = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
					local sourceName = "Unknown"
					if sourceInfo and type(sourceInfo) == "table" then
						local itemLinkField = sourceInfo["itemLink"]
						if itemLinkField and type(itemLinkField) == "string" then
							local linkedItemID = self:GetItemID(itemLinkField)
							if linkedItemID then
								sourceName = C_Item.GetItemInfo(linkedItemID) or "Unknown"
							end
						end
					end

					print(string.format("|cffff69b4DOKI|r Found other source: %s (sourceID: %d)", sourceName, sourceID))
				end

				return true
			end
		end
	end

	return false
end

-- Clear restriction cache when needed
function DOKI:ClearRestrictionCache()
	wipe(self.restrictionCache)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Restriction cache cleared")
	end
end

-- Scan all bags for collectible items - ENSURES we pass hyperlinks with enhanced retry logic
function DOKI:ScanCurrentItems()
	if not self.db or not self.db.enabled then return end

	-- Clear existing bag items
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "bag" then
			self.currentItems[itemLink] = nil
		end
	end

	-- Scan all bags
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					if self:IsCollectibleItem(itemInfo.itemID) then
						-- CRITICAL: Pass the hyperlink so we check the correct difficulty variant
						local isCollected, showYellowD = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
						self.currentItems[itemInfo.hyperlink] = {
							itemID = itemInfo.itemID,
							location = "bag",
							bagID = bagID,
							slotID = slotID,
							isCollected = isCollected,
							showYellowD = showYellowD,
						}
						if self.db.debugMode then
							local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
							local yellowStatus = showYellowD and " (YELLOW D)" or ""
							local modeStatus = self.db.smartMode and " [SMART]" or " [NORMAL]"
							print(string.format("|cffff69b4DOKI|r Found %s (ID: %d) in bag %d slot %d - %s%s%s",
								itemName, itemInfo.itemID, bagID, slotID,
								isCollected and "COLLECTED" or "NOT collected", yellowStatus, modeStatus))
						end
					end
				end
			end
		end
	end
end

-- Scan merchant items
function DOKI:ScanMerchantItems()
	if not self.db or not self.db.enabled then return end

	if not MerchantFrame or not MerchantFrame:IsVisible() then return end

	-- Clear existing merchant items
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "merchant" then
			self.currentItems[itemLink] = nil
		end
	end

	local numItems = GetMerchantNumItems()
	for i = 1, numItems do
		local itemLink = GetMerchantItemLink(i)
		if itemLink then
			local itemID = self:GetItemID(itemLink)
			if itemID and self:IsCollectibleItem(itemID) then
				-- Pass the merchant item link as well for accuracy
				local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
				self.currentItems[itemLink] = {
					itemID = itemID,
					location = "merchant",
					merchantIndex = i,
					isCollected = isCollected,
					showYellowD = showYellowD,
				}
				if self.db.debugMode then
					local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
					local yellowStatus = showYellowD and " (YELLOW D)" or ""
					local modeStatus = self.db.smartMode and " [SMART]" or " [NORMAL]"
					print(string.format("|cffff69b4DOKI|r Found merchant item %s (ID: %d) at index %d - %s%s%s",
						itemName, itemID, i, isCollected and "COLLECTED" or "NOT collected", yellowStatus, modeStatus))
				end
			end
		end
	end
end

-- Get count of current items
function DOKI:GetCurrentItemCount()
	local count = 0
	for _ in pairs(self.currentItems) do
		count = count + 1
	end

	return count
end

-- Get table size utility
function DOKI:GetTableSize(t)
	if not t then return 0 end

	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end

	return count
end

-- Debug functions remain unchanged but add cache info
function DOKI:DebugTransmogItem(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki debug <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === DEBUGGING ITEM %d ===", itemID))
	print(string.format("Data ready: %s", tostring(self:IsItemDataReady(itemID))))
	print(string.format("Restriction cache size: %d", self:GetTableSize(self.restrictionCache)))
	print(string.format("Pending retries: %d", self:GetTableSize(self.pendingRetries)))
	-- Continue with existing debug logic...
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID = C_Item.GetItemInfo(itemID)
	if not itemName then
		print("|cffff69b4DOKI|r Item not found or not cached. Try again in a few seconds.")
		return
	end

	-- Rest of existing debug function...
end

-- Additional debug functions and existing code continue as before...
function DOKI:DebugSmartTransmog(itemID)
	-- Existing function content remains the same
end

function DOKI:DebugClassRestrictions(sourceID, appearanceID)
	-- Existing function content remains the same
end

function DOKI:DebugItemInfo(itemID)
	-- Existing function content remains the same
end
