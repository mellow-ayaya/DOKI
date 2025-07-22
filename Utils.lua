-- DOKI Utilities - Your Original Logic with Faction Support
local addonName, DOKI = ...
-- Initialize storage (keeping your originals)
DOKI.currentItems = DOKI.currentItems or {}
DOKI.pendingRetries = DOKI.pendingRetries or {} -- Items needing retry
DOKI.elvuiHooksSetup = false                    -- Track if ElvUI hooks are established
-- Extract item ID from item link (ORIGINAL)
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

-- Check if an item is a collectible type (ORIGINAL)
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

-- Check if item is already collected using the SPECIFIC variant from the bag (ORIGINAL)
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

-- Check if mount is collected (ORIGINAL)
function DOKI:IsMountCollected(itemID)
	if not itemID or not C_MountJournal then return false end

	-- Get the spell that this mount item teaches
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then return false end

	-- Convert to number if it's a string
	local spellIDNum = tonumber(spellID)
	return spellIDNum and IsSpellKnown(spellIDNum) or false
end

-- Check if pet is collected (ORIGINAL)
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

-- Enhanced transmog collection check with yellow D feature using CORRECT API pattern (ORIGINAL)
function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

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

	return false, showYellowD -- Don't have this variant, but return yellow D flag
end

-- SMART: Enhanced transmog collection check with class AND faction restriction awareness
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

			return false, false -- Show pink D (we need this item)
		end
	end

	return false, false -- Default to pink D
end

-- Get class and faction restrictions for a specific source - TOOLTIP-BASED approach
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

				-- Check for faction restrictions with expanded patterns
				local lowerText = string.lower(text)
				if string.find(lowerText, "alliance") then
					-- Look for various Alliance indicators
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
					-- Look for various Horde indicators
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

				-- Also log all tooltip lines for debugging
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

						-- If both have faction restrictions but different factions = not equivalent
					end

					-- If one has faction restriction and other doesn't = not equivalent
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
						-- Different faction restrictions - sources are not equivalent, don't replace each other
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

-- Check if we have other sources for this appearance using the WORKING API pattern (ORIGINAL)
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

-- MINIMAL ElvUI Support Functions (Only what's needed)
function DOKI:SetupElvUIHooks()
	if self.elvuiHooksSetup or not ElvUI then return end

	local E = ElvUI[1]
	if not E then return end

	local B = E:GetModule("Bags", true)
	if not B then return end

	-- Hook ElvUI's Layout function - this is called when bags update
	if B.Layout then
		hooksecurefunc(B, "Layout", function()
			if self.db and self.db.enabled then
				-- Small delay to ensure layout is complete
				C_Timer.After(0.1, function()
					self:ScanCurrentItems()
					self:UpdateAllOverlays()
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r ElvUI Layout triggered scan and overlay update")
					end
				end)
			end
		end)
	end

	-- Hook ElvUI bag frame show events
	if B.BagFrame then
		B.BagFrame:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.2, function()
					self:ScanCurrentItems()
					self:UpdateAllOverlays()
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r ElvUI BagFrame shown - scanned and updated overlays")
					end
				end)
			end
		end)
	end

	if B.BankFrame then
		B.BankFrame:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.2, function()
					self:ScanCurrentItems()
					self:UpdateAllOverlays()
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r ElvUI BankFrame shown - scanned and updated overlays")
					end
				end)
			end
		end)
	end

	if B.WarbankFrame then
		B.WarbankFrame:HookScript("OnShow", function()
			if self.db and self.db.enabled then
				C_Timer.After(0.2, function()
					self:ScanCurrentItems()
					self:UpdateAllOverlays()
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r ElvUI WarbankFrame shown - scanned and updated overlays")
					end
				end)
			end
		end)
	end

	self.elvuiHooksSetup = true
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ElvUI hooks established successfully")
	end
end

function DOKI:IsElvUIBagVisible()
	if not ElvUI then return false end

	local E = ElvUI[1]
	if not E then return false end

	local B = E:GetModule("Bags", true)
	if not B then return false end

	return (B.BagFrame and B.BagFrame:IsShown()) or
			(B.BankFrame and B.BankFrame:IsShown()) or
			(B.WarbankFrame and B.WarbankFrame:IsShown())
end

function DOKI:InitializeElvUISupport()
	if ElvUI and not self.elvuiHooksSetup then
		self:SetupElvUIHooks()
		C_Timer.After(1.0, function()
			if not self.elvuiHooksSetup then
				self:SetupElvUIHooks()
			end
		end)
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r ElvUI support initialization started")
		end
	end
end

-- Scan all bags for collectible items - ENSURES we pass hyperlinks (ORIGINAL WITH MINIMAL ELVUI)
function DOKI:ScanCurrentItems()
	if not self.db or not self.db.enabled then return end

	-- Setup ElvUI hooks if needed
	if ElvUI and not self.elvuiHooksSetup then
		self:SetupElvUIHooks()
	end

	-- Clear existing bag items
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.location == "bag" then
			self.currentItems[itemLink] = nil
		end
	end

	-- For ElvUI, we need to ensure we only scan when bags are actually visible
	if ElvUI and not self:IsElvUIBagVisible() then
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r ElvUI detected but no bags visible, skipping scan")
		end

		return
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

-- Scan merchant items (ORIGINAL)
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

-- Get count of current items (ORIGINAL)
function DOKI:GetCurrentItemCount()
	local count = 0
	for _ in pairs(self.currentItems) do
		count = count + 1
	end

	return count
end

-- Get table size utility (ORIGINAL)
function DOKI:GetTableSize(t)
	if not t then return 0 end

	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end

	return count
end

-- DEBUG FUNCTION: Detailed transmog analysis (ORIGINAL)
function DOKI:DebugTransmogItem(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki debug <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === DEBUGGING ITEM %d ===", itemID))
	-- Get basic item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID = C_Item.GetItemInfo(itemID)
	if not itemName then
		print("|cffff69b4DOKI|r Item not found or not cached. Try again in a few seconds.")
		return
	end

	print(string.format("Item Name: %s", itemName))
	print(string.format("Class ID: %d, SubClass ID: %d", classID or 0, subClassID or 0))
	print(string.format("Item Type: %s, SubType: %s", itemType or "nil", itemSubType or "nil"))
	-- Check if it's a transmog item
	if not (classID == 2 or classID == 4) then
		print("|cffff69b4DOKI|r Not a transmog item (not weapon or armor)")
		return
	end

	-- Create a mock hyperlink for testing
	local testLink = string.format("|cffffffff|Hitem:%d:::::::::::::|h[%s]|h|r", itemID, itemName)
	-- Step 1: Get appearance IDs
	print("\n--- Step 1: Getting Appearance IDs ---")
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	print(string.format("Item Appearance ID: %s", tostring(itemAppearanceID)))
	print(string.format("Modified Appearance ID: %s", tostring(itemModifiedAppearanceID)))
	if not itemModifiedAppearanceID then
		print("|cffff69b4DOKI|r No appearance IDs found - item cannot be transmogged")
		return
	end

	-- Step 2: Check if we have this specific variant
	print("\n--- Step 2: Checking This Specific Variant ---")
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	print(string.format("Has this variant: %s", tostring(hasThisVariant)))
	if hasThisVariant then
		print("|cffff69b4DOKI|r Result: COLLECTED - No overlay needed")
		return
	end

	-- Step 3: Check for other sources
	print("\n--- Step 3: Checking Other Sources ---")
	if not itemAppearanceID then
		print("|cffff69b4DOKI|r No base appearance ID - cannot check other sources")
		print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
		return
	end

	local sourceIDs = C_TransmogCollection.GetAllAppearanceSources(itemAppearanceID)
	print(string.format("Number of sources found: %d", sourceIDs and #sourceIDs or 0))
	if not sourceIDs or #sourceIDs == 0 then
		print("|cffff69b4DOKI|r No sources found")
		print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
		return
	end

	-- Check each source
	local foundOtherSource = false
	for i, sourceID in ipairs(sourceIDs) do
		print(string.format("\nSource %d: ID %d", i, sourceID))
		if sourceID == itemModifiedAppearanceID then
			print("  This is the current item's source (excluding)")
		else
			local success, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
			print(string.format("  Has this source: %s", success and tostring(hasSource) or "error"))
			if success and hasSource then
				-- Get source info for debugging
				local sourceInfo = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
				if sourceInfo and type(sourceInfo) == "table" then
					local itemLinkField = sourceInfo["itemLink"]
					if itemLinkField and type(itemLinkField) == "string" then
						local linkedItemID = self:GetItemID(itemLinkField)
						local sourceName = linkedItemID and C_Item.GetItemInfo(linkedItemID) or "Unknown"
						print(string.format("  Source item: %s (ID: %d)", sourceName, linkedItemID or 0))
					end
				end

				foundOtherSource = true
			end
		end
	end

	-- Final result
	print("\n--- FINAL RESULT ---")
	if foundOtherSource then
		if self.db.smartMode then
			print("|cffff69b4DOKI|r Smart mode enabled - checking class and faction restrictions...")
			local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
			if hasEqualOrBetterSources then
				print("|cffff69b4DOKI|r Result: HAVE EQUAL OR BETTER SOURCE - No D")
			else
				print("|cffff69b4DOKI|r Result: OTHER SOURCES MORE RESTRICTIVE - Pink D")
			end
		else
			print("|cffff69b4DOKI|r Result: COLLECTED FROM OTHER SOURCE - Yellow D")
		end
	else
		print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
end

-- DEBUG FUNCTION: Smart transmog analysis with faction info
function DOKI:DebugSmartTransmog(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki smart <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SMART TRANSMOG DEBUG: %d ===", itemID))
	-- Try to find this item in current bags to get the actual hyperlink being used
	local foundHyperlink = nil
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.itemID == itemID then
			foundHyperlink = itemLink
			print(string.format("Found item in bags with hyperlink: %s", itemLink))
			break
		end
	end

	-- Get appearance IDs using the same method as the actual scanning
	local itemAppearanceID, itemModifiedAppearanceID
	if foundHyperlink then
		-- Use hyperlink first (same as scanning logic)
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(foundHyperlink)
		print(string.format("Using hyperlink for appearance lookup"))
	end

	-- Fallback to itemID
	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
		print(string.format("Using itemID for appearance lookup"))
	end

	if not itemAppearanceID then
		print("No appearance ID found")
		return
	end

	print(string.format("Appearance ID: %d, Modified ID: %d", itemAppearanceID, itemModifiedAppearanceID))
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then
		print("No sources found or error retrieving sources")
		return
	end

	print(string.format("Found %d total sources", #allSources))
	-- Analyze current item restrictions
	local currentRestrictions = self:GetClassRestrictionsForSource(itemModifiedAppearanceID, itemAppearanceID)
	print(string.format("\n--- Current Item Restrictions ---"))
	if currentRestrictions then
		print(string.format("Valid for %d classes: %s", #currentRestrictions.validClasses,
			table.concat(currentRestrictions.validClasses, ", ")))
		print(string.format("Armor type: %s", tostring(currentRestrictions.armorType)))
		print(string.format("Has class restriction: %s", tostring(currentRestrictions.hasClassRestriction)))
		print(string.format("Faction: %s", tostring(currentRestrictions.faction)))
		print(string.format("Has faction restriction: %s", tostring(currentRestrictions.hasFactionRestriction)))
	else
		print("Could not determine restrictions")
	end

	-- Analyze each source
	for i, sourceID in ipairs(allSources) do
		print(string.format("\n--- Source %d: %d ---", i, sourceID))
		local success2, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
		print(string.format("Has source: %s", success2 and tostring(hasSource) or "error"))
		if success2 and hasSource then
			local sourceRestrictions = self:GetClassRestrictionsForSource(sourceID, itemAppearanceID)
			if sourceRestrictions then
				print(string.format("Valid for %d classes: %s", #sourceRestrictions.validClasses,
					table.concat(sourceRestrictions.validClasses, ", ")))
				print(string.format("Faction: %s", tostring(sourceRestrictions.faction)))
				print(string.format("Has faction restriction: %s", tostring(sourceRestrictions.hasFactionRestriction)))
				if currentRestrictions then
					-- Check for less restrictive
					local isLessRestrictive = #sourceRestrictions.validClasses > #currentRestrictions.validClasses
					local factionLessRestrictive = not sourceRestrictions.hasFactionRestriction and
							currentRestrictions.hasFactionRestriction
					print(string.format("Less restrictive than current (classes): %s", tostring(isLessRestrictive)))
					print(string.format("Less restrictive than current (faction): %s", tostring(factionLessRestrictive)))
				end
			end
		end

		local sourceInfo = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
		if sourceInfo and type(sourceInfo) == "table" then
			local itemLinkField = sourceInfo["itemLink"]
			local useErrorField = sourceInfo["useError"]
			print(string.format("Item: %s", itemLinkField or "Unknown"))
			if useErrorField then
				print(string.format("Use error: %s", useErrorField))
			end
		end
	end

	-- Final smart assessment
	print(string.format("\n--- Smart Assessment ---"))
	local success3, hasEqualOrBetterSources = pcall(self.HasEqualOrLessRestrictiveSources, self, itemAppearanceID,
		itemModifiedAppearanceID)
	print(string.format("Has equal or less restrictive sources: %s",
		success3 and tostring(hasEqualOrBetterSources) or "error"))
	local success4, regularCheck = pcall(self.HasOtherTransmogSources, self, itemAppearanceID, itemModifiedAppearanceID)
	print(string.format("Has any other sources: %s", success4 and tostring(regularCheck) or "error"))
	print("|cffff69b4DOKI|r === END SMART DEBUG ===")
end

-- DEBUG FUNCTION: Deep dive into class restrictions for a specific source (ORIGINAL)
function DOKI:DebugClassRestrictions(sourceID, appearanceID)
	print(string.format("|cffff69b4DOKI|r === CLASS RESTRICTION DEBUG: Source %d, Appearance %d ===", sourceID,
		appearanceID))
	local testClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }
	local classNames = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock",
		"Monk", "Druid", "Demon Hunter", "Evoker" }
	for i, classID in ipairs(testClasses) do
		print(string.format("\n--- Testing Class %d (%s) ---", classID, classNames[i] or "Unknown"))
		local success, validSources = pcall(C_TransmogCollection.GetValidAppearanceSourcesForClass, appearanceID, classID)
		if success and validSources then
			print(string.format("Found %d valid sources for this class", #validSources))
			local foundOurSource = false
			for j, validSource in ipairs(validSources) do
				if validSource.sourceID == sourceID then
					foundOurSource = true
					print(string.format("FOUND our source at index %d:", j))
					print(string.format("  isValidSourceForPlayer: %s", tostring(validSource.isValidSourceForPlayer)))
					print(string.format("  canDisplayOnPlayer: %s", tostring(validSource.canDisplayOnPlayer)))
					print(string.format("  useErrorType: %s", tostring(validSource.useErrorType)))
					print(string.format("  useError: %s", tostring(validSource.useError)))
					print(string.format("  meetsTransmogPlayerCondition: %s", tostring(validSource.meetsTransmogPlayerCondition)))
					-- The logic check from our function
					if validSource.useErrorType and validSource.useErrorType == 7 then
						print("  -> RESULT: Has class restriction")
					elseif validSource.isValidSourceForPlayer or not validSource.useErrorType then
						print("  -> RESULT: Valid for this class")
					else
						print("  -> RESULT: Not valid for this class")
					end

					break
				end
			end

			if not foundOurSource then
				print("Our source was NOT found in valid sources for this class")
			end
		elseif not success then
			print(string.format("ERROR calling GetValidAppearanceSourcesForClass: %s", tostring(validSources)))
		else
			print("No valid sources returned")
		end
	end

	print("|cffff69b4DOKI|r === END CLASS RESTRICTION DEBUG ===")
end

-- DEBUG FUNCTION: Test faction detection for specific source
function DOKI:DebugSourceRestrictions(sourceID)
	if not sourceID then
		print("|cffff69b4DOKI|r Usage: /doki source <sourceID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SOURCE RESTRICTION DEBUG: %d ===", sourceID))
	-- Get the restrictions using our function
	local restrictions = self:GetClassRestrictionsForSource(sourceID, nil)
	if restrictions then
		print("Results from GetClassRestrictionsForSource:")
		print(string.format("  Valid classes: %s", table.concat(restrictions.validClasses, ", ")))
		print(string.format("  Armor type: %s", tostring(restrictions.armorType)))
		print(string.format("  Has class restriction: %s", tostring(restrictions.hasClassRestriction)))
		print(string.format("  Faction: %s", tostring(restrictions.faction)))
		print(string.format("  Has faction restriction: %s", tostring(restrictions.hasFactionRestriction)))
	else
		print("Could not get restrictions")
	end

	print("|cffff69b4DOKI|r === END SOURCE DEBUG ===")
end

-- DEBUG FUNCTION: Simple item analysis (ORIGINAL)
function DOKI:DebugItemInfo(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki item <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === ITEM INFO DEBUG: %d ===", itemID))
	-- Get all available item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID, bindType, expacID, setID, isCraftingReagent = C_Item
			.GetItemInfo(itemID)
	print(string.format("Name: %s", itemName or "Unknown"))
	print(string.format("Type: %s (%d), SubType: %s (%d)", itemType or "nil", classID or 0, itemSubType or "nil",
		subClassID or 0))
	print(string.format("Equip Loc: %s", itemEquipLoc or "nil"))
	-- Check if this gives us any class restriction hints
	local _, _, _, _, _, _, instantClassID, instantSubClassID = C_Item.GetItemInfoInstant(itemID)
	print(string.format("Instant: Class %d, SubClass %d", instantClassID or 0, instantSubClassID or 0))
	-- Check tooltip for class restrictions (this might show "Classes: Rogue" etc)
	local tooltip = CreateFrame("GameTooltip", "DOKIDebugTooltip", nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetItemByID(itemID)
	tooltip:Show()
	print("Tooltip lines:")
	for i = 1, tooltip:NumLines() do
		local line = _G["DOKIDebugTooltipTextLeft" .. i]
		if line then
			local text = line:GetText()
			if text and text ~= "" then
				print(string.format("  Line %d: %s", i, text))
				-- Look for class restrictions in tooltip
				if string.find(text, "Classes:") then
					print(string.format("  -> FOUND CLASS RESTRICTION: %s", text))
				end

				-- Look for faction restrictions in tooltip
				if string.find(text, "Alliance") or string.find(text, "Horde") then
					print(string.format("  -> POTENTIAL FACTION RESTRICTION: %s", text))
				end
			end
		end
	end

	tooltip:Hide()
	print("|cffff69b4DOKI|r === END ITEM DEBUG ===")
end
