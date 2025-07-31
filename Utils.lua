-- DOKI Utils - Core Item Detection and Basic Utilities (FIXED: Data Loading & Timing)
local addonName, DOKI = ...
-- Initialize core storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
-- ADDED: Data loading retry system
DOKI.pendingDataRequests = DOKI.pendingDataRequests or {}
DOKI.dataLoadRetryTimer = nil
-- ===== ENHANCED DATA LOADING SYSTEM =====
function DOKI:RequestItemDataWithRetry(itemID, itemLink, callback, attempt)
	if not itemID then return end

	attempt = attempt or 1
	local maxAttempts = 3
	-- Create a unique key for this request
	local requestKey = itemLink or tostring(itemID)
	-- Don't duplicate requests
	if self.pendingDataRequests[requestKey] then
		return
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Requesting data for item %d (attempt %d/%d)", itemID, attempt, maxAttempts))
	end

	-- Mark as pending
	self.pendingDataRequests[requestKey] = true
	-- Request the data
	C_Item.RequestLoadItemDataByID(itemID)
	if itemLink then
		-- Also request transmog data if it's equipment
		local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
		if classID and (classID == 2 or classID == 4) then
			C_TransmogCollection.GetItemInfo(itemLink)
			C_TransmogCollection.GetItemInfo(itemID)
		end
	end

	-- Schedule retry
	C_Timer.After(0.5, function()
		-- Clear pending flag
		DOKI.pendingDataRequests[requestKey] = nil
		-- Check if data is now available
		local itemName = C_Item.GetItemInfo(itemID)
		local hasBasicData = itemName ~= nil
		local hasTransmogData = true
		if itemLink then
			local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
			if classID and (classID == 2 or classID == 4) then
				local _, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
				hasTransmogData = itemModifiedAppearanceID ~= nil
			end
		end

		if hasBasicData and hasTransmogData then
			-- Data is ready, execute callback
			if callback then
				callback(itemID, itemLink)
			end

			if DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Data loaded successfully for item %d", itemID))
			end
		elseif attempt < maxAttempts then
			-- Retry
			if DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Retrying data load for item %d", itemID))
			end

			DOKI:RequestItemDataWithRetry(itemID, itemLink, callback, attempt + 1)
		else
			-- Give up after max attempts
			if DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Failed to load data for item %d after %d attempts", itemID, maxAttempts))
			end
		end
	end)
end

-- ADDED: Schedule a delayed full rescan to catch items that failed to load initially
function DOKI:ScheduleDelayedFullRescan()
	if self.delayedRescanTimer then
		self.delayedRescanTimer:Cancel()
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scheduling delayed full rescan in 2 seconds...")
	end

	self.delayedRescanTimer = C_Timer.NewTimer(2.0, function()
		if DOKI.db and DOKI.db.enabled then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Running delayed full rescan to catch missed items...")
			end

			-- Clear cache to force fresh checks
			DOKI:ClearCollectionCache()
			-- Do a full scan
			local count = DOKI:FullItemScan()
			if DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Delayed rescan complete: %d indicators", count))
			end
		end

		DOKI.delayedRescanTimer = nil
	end)
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

function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or (B.BankFrame and B.BankFrame:IsShown())
end

-- ===== CORE ITEM DETECTION =====
-- FIXED: Enhanced collectible item detection with better data loading
function DOKI:IsCollectibleItem(itemID, itemLink)
	-- ATT MODE: Consider ALL items as potentially collectible
	if self.db and self.db.attMode then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT mode: treating item %d as collectible for parsing", itemID or 0))
		end

		return true
	end

	-- EXISTING LOGIC: Only for non-ATT mode
	-- ADDED: Check for ensembles first
	if self:IsEnsembleItem(itemID) then
		return true
	end

	-- ADDED: Check for caged pets (battlepet items) next
	if itemLink and string.find(itemLink, "battlepet:") then
		return true
	end

	if not itemID then return false end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		-- Request data and return false for now (don't assume collectible without data)
		self:RequestItemDataWithRetry(itemID, itemLink, function(loadedItemID, loadedItemLink)
			-- When data loads, trigger a rescan if UI is visible
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		return false -- Not collectible until we know what it is
	end

	-- Mount items (class 15, subclass 5)
	if classID == 15 and subClassID == 5 then return true end

	-- Pet items (class 15, subclass 2)
	if classID == 15 and subClassID == 2 then return true end

	-- Toy items
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then return true end

	-- Transmog items (weapons class 2, armor class 4)
	if classID == 2 or classID == 4 then
		if itemEquipLoc then
			-- FIXED: Properly handle offhands - check if they're actually transmoggable
			if itemEquipLoc == "INVTYPE_HOLDABLE" then
				-- Use the transmog API to check if this offhand is actually transmoggable
				local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
				if not itemModifiedAppearanceID then
					-- Data not loaded yet - request it and assume not collectible for now
					self:RequestItemDataWithRetry(itemID, itemLink, function(loadedItemID, loadedItemLink)
						if DOKI.db and DOKI.db.enabled then
							C_Timer.After(0.1, function()
								if DOKI.TriggerImmediateSurgicalUpdate then
									DOKI:TriggerImmediateSurgicalUpdate()
								end
							end)
						end
					end)
					return false -- Not collectible until we know
				end

				return itemAppearanceID ~= nil and itemModifiedAppearanceID ~= nil
			end

			-- Other non-transmog slots (kept as before)
			local nonTransmogSlots = {
				"INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET",
				"INVTYPE_BAG", "INVTYPE_QUIVER",
			}
			for _, slot in ipairs(nonTransmogSlots) do
				if itemEquipLoc == slot then return false end
			end

			return true
		end
	end

	return false
end

-- ADDED: Extract species ID from caged pet (battlepet) links
function DOKI:GetPetSpeciesFromBattlePetLink(itemLink)
	if not itemLink or not string.find(itemLink, "battlepet:") then
		return nil
	end

	-- Extract species ID from battlepet:speciesID:level:breedQuality:maxHealth:power:speed:battlePetGUID
	local speciesID = tonumber(string.match(itemLink, "battlepet:(%d+)"))
	return speciesID
end

-- ADDED: Check if a pet species is collected (for caged pets)
function DOKI:IsPetSpeciesCollected(speciesID)
	if not speciesID or not C_PetJournal then return false end

	-- Check if we have any of this pet species
	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

-- ===== CORE COLLECTION DETECTION =====
-- FIXED: Enhanced collection detection with proper data loading and no premature caching
function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID and not itemLink then return false, false, false end

	-- ATT MODE: ONLY use ATT data, ignore items ATT doesn't know about
	if self.db and self.db.attMode then
		local attStatus, attShowYellowD, attShowPurple = self:GetATTCollectionStatus(itemID, itemLink)
		if attStatus == "NO_ATT_DATA" then
			-- ATT has no data for this item - treat as "not relevant" (no indicator)
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT mode: No ATT data for item %d, treating as not relevant", itemID))
			end

			return true, false, false -- Return "collected" so no indicator is shown
		elseif attStatus ~= nil then
			-- ATT gave us a definitive answer
			if self.db and self.db.debugMode then
				local statusText = attStatus and "COLLECTED" or "NOT COLLECTED"
				local indicatorText = ""
				if attShowPurple then
					indicatorText = " (show pink indicator)"
				elseif attShowYellowD then
					indicatorText = " (show blue indicator)"
				end

				print(string.format("|cffff69b4DOKI|r Using ATT result for item %d: %s%s",
					itemID, statusText, indicatorText))
			end

			-- Handle purple indicators for fractional items
			if attShowPurple then
				return false, false, true           -- Not collected, don't show yellow D, show purple
			else
				return attStatus, attShowYellowD, false -- Normal ATT result, don't show purple
			end
		else
			-- ATT is still processing this item - return "collected" temporarily to avoid false indicators
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT mode: Item %d still being processed, returning temporary 'collected'",
					itemID))
			end

			return true, false, false -- Return "collected" temporarily until ATT processes it
		end
	end

	-- EXISTING LOGIC: Only for non-ATT mode
	-- ADDED: Handle ensembles first
	local itemName = C_Item.GetItemInfo(itemID)
	if self:IsEnsembleItem(itemID, itemName) then
		local isCollected, showYellowD, showPurple = self:IsEnsembleCollected(itemID, itemLink)
		return isCollected, showYellowD, showPurple
	end

	-- ADDED: Handle caged pets (battlepet links) next
	local petSpeciesID = self:GetPetSpeciesFromBattlePetLink(itemLink)
	if petSpeciesID then
		local isCollected = self:IsPetSpeciesCollected(petSpeciesID)
		-- Cache the result using itemLink as key since no itemID
		self:SetCachedCollectionStatus(petSpeciesID, itemLink, isCollected, false, false)
		return isCollected, false, false
	end

	if not itemID then return false, false, false end

	-- Check cache first
	local cachedCollected, cachedYellowD, cachedPurple = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		return cachedCollected, cachedYellowD, cachedPurple
	end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		-- Request data and return "collected" temporarily to avoid false positives
		self:RequestItemDataWithRetry(itemID, itemLink, function(loadedItemID, loadedItemLink)
			-- When data loads, trigger a rescan
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		return true, false, false -- Treat as "collected" temporarily
	end

	local isCollected, showYellowD, showPurple = false, false, false
	-- Check mounts - FIXED FOR WAR WITHIN
	if classID == 15 and subClassID == 5 then
		isCollected = self:IsMountCollectedWarWithin(itemID)
		showYellowD = false
		showPurple = false
		-- Check pets - FIXED FOR WAR WITHIN
	elseif classID == 15 and subClassID == 2 then
		isCollected = self:IsPetCollectedWarWithin(itemID)
		showYellowD = false
		showPurple = false
		-- Check toys
	elseif C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		isCollected = PlayerHasToy(itemID)
		showYellowD = false
		showPurple = false
		-- Check transmog
	elseif classID == 2 or classID == 4 then
		if self.db and self.db.smartMode then
			isCollected, showYellowD = self:IsTransmogCollectedSmart(itemID, itemLink)
		else
			isCollected, showYellowD = self:IsTransmogCollected(itemID, itemLink)
		end

		showPurple = false -- Transmog items don't use purple indicators (that's only for ATT fractional)
	end

	-- FIXED: Only cache the result if we got valid data
	if classID and subClassID then
		self:SetCachedCollectionStatus(itemID, itemLink, isCollected, showYellowD, showPurple)
	end

	return isCollected, showYellowD, showPurple
end

-- FIXED: Enhanced mount collection with proper data loading fallback
function DOKI:IsMountCollectedWarWithin(itemID)
	if not itemID or not C_MountJournal then return false end

	-- Use the proper War Within API - GetMountFromItem
	local mountID = C_MountJournal.GetMountFromItem(itemID)
	if not mountID then
		-- Data not loaded yet - request it and return true temporarily to avoid false indicators
		self:RequestItemDataWithRetry(itemID, nil, function(loadedItemID, loadedItemLink)
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		return true -- Treat as collected temporarily
	end

	-- Get mount info using the mount ID
	local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
	isFactionSpecific, faction, shouldHideOnChar, isCollected, mountIDReturn, isSteadyFlight = C_MountJournal
			.GetMountInfoByID(mountID)
	return isCollected or false
end

-- FIXED: Enhanced pet collection with proper data loading fallback
function DOKI:IsPetCollectedWarWithin(itemID)
	if not itemID or not C_PetJournal then return false end

	-- Get pet info from the item - this API is confirmed to work in War Within
	local name, icon, petType, creatureID, sourceText, description, isWild, canBattle,
	isTradeable, isUnique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then
		-- Data not loaded yet - request it and return true temporarily to avoid false indicators
		self:RequestItemDataWithRetry(itemID, nil, function(loadedItemID, loadedItemLink)
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		return true -- Treat as collected temporarily
	end

	-- Check if we have any of this pet species
	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

-- ===== TRANSMOG DETECTION =====
-- FIXED: Enhanced transmog collection detection with proper data loading and no premature caching
function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	-- FIXED: Handle missing transmog data without premature caching
	if not itemModifiedAppearanceID then
		-- Check if the item can actually be transmogged before assuming it's collectible
		if C_Transmog and C_Transmog.GetItemInfo then
			local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
			-- If the item cannot be a transmog source, it's not actually collectible
			if canBeSource == false then -- Explicit false check
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Item %d cannot be transmog source: %s",
						itemID, noSourceReason or "unknown reason"))
				end

				return true, false -- Treat as "collected" (no indicator needed)
			end
		end

		-- Request data with retry system
		self:RequestItemDataWithRetry(itemID, itemLink, function(loadedItemID, loadedItemLink)
			-- When data loads, trigger a rescan
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Transmog data not loaded for item %d, requesting...", itemID))
		end

		-- REVERTED: Return "collected" temporarily to avoid false positives
		-- This prevents showing indicators on items that might actually be collected
		return true, false -- Treat as "collected" until we know for sure
	end

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

	-- FIXED: Handle missing transmog data properly in smart mode
	if not itemModifiedAppearanceID then
		-- Check if the item can actually be transmogged
		if C_Transmog and C_Transmog.GetItemInfo then
			local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
			-- If the item cannot be a transmog source, it's not actually collectible
			if canBeSource == false then -- Explicit false check
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Smart mode: Item %d cannot be transmog source: %s",
						itemID, noSourceReason or "unknown reason"))
				end

				return true, false -- Treat as "collected" (no indicator needed)
			end
		end

		-- Request data with retry system
		self:RequestItemDataWithRetry(itemID, itemLink, function(loadedItemID, loadedItemLink)
			if DOKI.db and DOKI.db.enabled then
				C_Timer.After(0.1, function()
					if DOKI.TriggerImmediateSurgicalUpdate then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end)
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Smart mode: Transmog data not loaded for item %d, requesting...", itemID))
		end

		-- REVERTED: Return "collected" temporarily to avoid false positives
		return true, false -- Treat as "collected" until we know for sure
	end

	-- Check if we have this specific variant
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Smart mode: Item %d - have this specific variant", itemID))
		end

		return true, false -- Have this variant, no indicator needed
	end

	-- FIXED: Smart mode logic flow (faction detection removed)
	-- We don't have this variant - check if we have equal or better sources
	if itemAppearanceID then
		local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasEqualOrBetterSources then
			-- We have identical or less restrictive sources, so we don't need this item
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Smart mode: Item %d - have equal or better sources, no indicator needed",
					itemID))
			end

			return true, false -- Treat as collected (no indicator shown)
		else
			-- We either have no sources, or only more restrictive sources - show indicator
			local hasAnySources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
			if self.db and self.db.debugMode then
				if hasAnySources then
					print(string.format(
						"|cffff69b4DOKI|r Smart mode: Item %d - have other sources but they're more restrictive, show indicator",
						itemID))
				else
					print(string.format("|cffff69b4DOKI|r Smart mode: Item %d - no sources at all, show indicator", itemID))
				end
			end

			return false, false -- Show indicator (we need this item)
		end
	end

	return false, false -- Default to show indicator
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

-- Get class restrictions for a specific source (FACTION DETECTION REMOVED)
function DOKI:GetClassRestrictionsForSource(sourceID, appearanceID)
	local restrictions = {
		validClasses = {},
		armorType = nil,
		hasClassRestriction = false,
		-- REMOVED: faction and hasFactionRestriction fields
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

	-- Enhanced tooltip parsing for class restrictions only (FACTION DETECTION REMOVED)
	local tooltip = CreateFrame("GameTooltip", "DOKIClassTooltip" .. sourceID, nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetItemByID(linkedItemID)
	tooltip:Show()
	local foundClassRestriction = false
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

				-- REMOVED: All faction detection code
				-- Debug: log all tooltip lines if needed
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Tooltip line for item %d: %s", linkedItemID, text))
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
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- All classes (simplified)
		else
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- Unknown, assume all
		end
	end

	return restrictions
end

-- Check if we have sources with identical or less restrictive class sets (FACTION LOGIC REMOVED)
function DOKI:HasEqualOrLessRestrictiveSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then return false end

	-- Get class restrictions for the current item
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
					-- REMOVED: All faction comparison logic - now only compare class restrictions
					-- Check if source is less restrictive in terms of classes
					if sourceClassCount > currentClassCount then
						if self.db and self.db.debugMode then
							print(string.format(
								"|cffff69b4DOKI|r Found less restrictive source %d (usable by %d classes vs %d)",
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
								print(string.format("|cffff69b4DOKI|r Found identical restriction source %d (same classes: %s)",
									sourceID, table.concat(sourceCopy, ", ")))
							end

							return true
						end
					end
				end
			end
		end
	end

	return false
end

-- ===== ENHANCED ITEM DETECTION TRACING WITH TRANSMOG VALIDATION (FACTION DETECTION REMOVED) =====
function DOKI:TraceItemDetection(itemID, itemLink)
	if not itemID then
		print("|cffff69b4DOKI|r No item ID provided")
		return
	end

	-- ADDED: Check if this might be an ensemble first
	local itemName = C_Item.GetItemInfo(itemID)
	if self:IsEnsembleItem(itemID, itemName) then
		self:TraceEnsembleDetection(itemID, itemLink)
		return
	end

	print("|cffff69b4DOKI|r === ITEM DETECTION TRACE ===")
	local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
	print(string.format("Item: %s (ID: %d)", itemName, itemID))
	if itemLink then
		print(string.format("Link: %s", itemLink))
	end

	print("")
	-- Step 1: Check if it's collectible
	print("|cffff69b4DOKI|r 1. COLLECTIBLE CHECK:")
	-- Check for battlepets first
	if itemLink and string.find(itemLink, "battlepet:") then
		print("   BATTLEPET detected")
		local speciesID = self:GetPetSpeciesFromBattlePetLink(itemLink)
		print(string.format("  Species ID: %d", speciesID or 0))
		local isCollected = self:IsPetSpeciesCollected(speciesID)
		print(string.format("  Collection Status: %s", isCollected and "COLLECTED" or "NOT COLLECTED"))
		print(string.format("  Indicator Needed: %s", isCollected and "NO" or "YES"))
		return
	end

	-- Get item info
	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		print("   Could not get item info - item not loaded")
		print("  Triggering item data request...")
		C_Item.RequestLoadItemDataByID(itemID)
		return
	end

	print(string.format("  Class: %d, Subclass: %d", classID, subClassID))
	print(string.format("  Type: %s, Subtype: %s", itemType or "Unknown", itemSubType or "Unknown"))
	print(string.format("  Equip Location: %s", itemEquipLoc or "None"))
	local isCollectible = false
	local collectibleReason = ""
	-- Check each collectible type
	if classID == 15 and subClassID == 5 then
		isCollectible = true
		collectibleReason = "Mount item (class 15, subclass 5)"
	elseif classID == 15 and subClassID == 2 then
		isCollectible = true
		collectibleReason = "Pet item (class 15, subclass 2)"
	elseif C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		isCollectible = true
		collectibleReason = "Toy (confirmed by C_ToyBox.GetToyInfo)"
	elseif classID == 2 or classID == 4 then
		if itemEquipLoc then
			-- Check for non-transmog slots
			local nonTransmogSlots = {
				"INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET",
				"INVTYPE_BAG", "INVTYPE_QUIVER",
			}
			local isNonTransmog = false
			for _, slot in ipairs(nonTransmogSlots) do
				if itemEquipLoc == slot then
					isNonTransmog = true
					break
				end
			end

			if isNonTransmog then
				collectibleReason = string.format("Not transmog (equipment slot: %s)", itemEquipLoc)
			elseif itemEquipLoc == "INVTYPE_HOLDABLE" then
				-- Special check for offhands
				local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
				if itemAppearanceID and itemModifiedAppearanceID then
					isCollectible = true
					collectibleReason = "Transmoggable offhand (confirmed by transmog API)"
				else
					collectibleReason = "Non-transmoggable offhand"
				end
			else
				isCollectible = true
				collectibleReason = string.format("Transmog item (%s, %s)",
					classID == 2 and "Weapon" or "Armor", itemEquipLoc)
			end
		else
			collectibleReason = "Weapon/Armor but no equip location"
		end
	else
		collectibleReason = string.format("Not a collectible type (class %d, subclass %d)", classID, subClassID)
	end

	print(string.format("  Result: %s", isCollectible and "COLLECTIBLE" or "NOT COLLECTIBLE"))
	print(string.format("  Reason: %s", collectibleReason))
	if not isCollectible then
		print("   Item is not collectible - NO INDICATOR")
		return
	end

	print("")
	-- Step 2: Check collection status
	print("|cffff69b4DOKI|r 2. COLLECTION STATUS CHECK:")
	-- Check cache first
	local cachedCollected, cachedYellowD, cachedPurple = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		print("   Found in cache:")
		print(string.format("    Collected: %s", cachedCollected and "YES" or "NO"))
		print(string.format("    Show Yellow D: %s", cachedYellowD and "YES" or "NO"))
		print(string.format("    Show Purple: %s", cachedPurple and "YES" or "NO"))
	else
		print("   Not in cache - checking APIs...")
	end

	local isCollected, showYellowD, showPurple = false, false, false
	if classID == 15 and subClassID == 5 then
		-- Mount check
		print("   Checking mount status...")
		local mountID = C_MountJournal.GetMountFromItem(itemID)
		if mountID then
			local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
			isFactionSpecific, faction, shouldHideOnChar, mountCollected = C_MountJournal.GetMountInfoByID(mountID)
			isCollected = mountCollected or false
			print(string.format("    Mount ID: %d", mountID))
			print(string.format("    Mount Name: %s", name or "Unknown"))
			print(string.format("    Collected: %s", isCollected and "YES" or "NO"))
		else
			print("     No mount ID found for this item")
		end
	elseif classID == 15 and subClassID == 2 then
		-- Pet check
		print("   Checking pet status...")
		local name, icon, petType, creatureID, sourceText, description, isWild, canBattle,
		isTradeable, isUnique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
		if speciesID then
			local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
			isCollected = numCollected and numCollected > 0
			print(string.format("    Species ID: %d", speciesID))
			print(string.format("    Pet Name: %s", name or "Unknown"))
			print(string.format("    Collected: %d/%d", numCollected or 0, limit or 3))
			print(string.format("    Has Pet: %s", isCollected and "YES" or "NO"))
		else
			print("     No species ID found for this item")
		end
	elseif C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		-- Toy check
		print("   Checking toy status...")
		isCollected = PlayerHasToy(itemID)
		print(string.format("    Collected: %s", isCollected and "YES" or "NO"))
	elseif classID == 2 or classID == 4 then
		-- Transmog check
		print("   Checking transmog status...")
		local smartMode = self.db and self.db.smartMode
		print(string.format("    Smart Mode: %s", smartMode and "ON" or "OFF"))
		-- ADDED: Check if item can actually be transmogged
		if C_Transmog and C_Transmog.GetItemInfo then
			local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
			print(string.format("    Can be transmog source: %s", canBeSource and "YES" or "NO"))
			if not canBeSource then
				print(string.format("    Cannot be source because: %s", noSourceReason or "unknown"))
				print("   Item cannot be transmogged - treating as COLLECTED (no indicator)")
				return
			end
		end

		if smartMode then
			isCollected, showYellowD = self:IsTransmogCollectedSmart(itemID, itemLink)
			print("    Using smart mode logic...")
		else
			isCollected, showYellowD = self:IsTransmogCollected(itemID, itemLink)
			print("    Using basic transmog logic...")
		end

		local itemAppearanceID, itemModifiedAppearanceID
		if itemLink then
			itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
		end

		if not itemModifiedAppearanceID then
			itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
		end

		if itemModifiedAppearanceID then
			print(string.format("    Appearance ID: %d", itemAppearanceID or 0))
			print(string.format("    Modified Appearance ID: %d", itemModifiedAppearanceID))
			local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
			print(string.format("    Has This Variant: %s", hasThisVariant and "YES" or "NO"))
			if smartMode and itemAppearanceID then
				local hasOtherSources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
				print(string.format("    Has Other Sources: %s", hasOtherSources and "YES" or "NO"))
				if hasOtherSources then
					local hasEqualOrBetter = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
					print(string.format("    Has Equal/Better Sources: %s", hasEqualOrBetter and "YES" or "NO"))
				end
			end
		else
			print("     No transmog appearance data found")
			print("     Requesting transmog data load...")
			-- Trigger data loading
			C_TransmogCollection.GetItemInfo(itemID)
			if itemLink then
				C_TransmogCollection.GetItemInfo(itemLink)
			end

			print("     Data loading requested - try trace again in a few seconds")
			return
		end

		print(string.format("    Final Result: %s", isCollected and "COLLECTED" or "NOT COLLECTED"))
		print(string.format("    Show Yellow D: %s", showYellowD and "YES" or "NO"))
	end

	print("")
	-- Step 3: Final decision
	print("|cffff69b4DOKI|r 3. FINAL DECISION:")
	print(string.format("  Collectible: %s", isCollectible and "YES" or "NO"))
	print(string.format("  Collected: %s", isCollected and "YES" or "NO"))
	print(string.format("  Show Yellow D: %s", showYellowD and "YES" or "NO"))
	print(string.format("  Show Purple: %s", showPurple and "YES" or "NO"))
	local needsIndicator = isCollectible and (not isCollected or showPurple)
	print(string.format("   NEEDS INDICATOR: %s", needsIndicator and "YES" or "NO"))
	if needsIndicator then
		local color = "ORANGE (uncollected)"
		if showPurple then
			color = "PURPLE (fractional)"
		elseif showYellowD then
			color = "BLUE (has other sources)"
		end

		print(string.format("   Indicator Color: %s", color))
	end

	print("|cffff69b4DOKI|r === END TRACE ===")
end

-- ===== UTILITY FUNCTIONS =====
function DOKI:ForceUniversalScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Force full scan...")
	end

	return self:FullItemScan()
end

-- ADDED: Force cleanup of empty slots (for rapid selling issues)
function DOKI:ForceCleanupEmptySlots()
	if self.ForceCleanEmptySlots then
		local cleaned = self:ForceCleanEmptySlots()
		print(string.format("|cffff69b4DOKI|r Force cleaned %d indicators from empty slots", cleaned))
		return cleaned
	else
		print("|cffff69b4DOKI|r Force cleanup function not available")
		return 0
	end
end

-- ===== LEGACY COMPATIBILITY =====
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
