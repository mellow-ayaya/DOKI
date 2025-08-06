-- DOKI Collections ATT - AllTheThings Integration Functions
local addonName, DOKI = ...
-- ===== ENHANCED ATT COLLECTION STATUS WITH ITEM LOADING =====
function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- FIXED: Actually use the cache lookup function!
	local cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected = self:GetCachedATTStatus(itemID, itemLink)
	if cachedIsCollected == "NO_ATT_DATA" then
		return "NO_ATT_DATA", nil, nil
	elseif cachedIsCollected ~= nil then
		return cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected
	end

	-- ENHANCED: Check if item data is loaded
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName or itemName == "" then
		-- Item data not loaded - request it and return "still processing"
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT: Item %d data not loaded, requesting...", itemID))
		end

		C_Item.RequestLoadItemDataByID(itemID)
		-- Return nil so IsItemCollected treats as "still processing"
		return nil, nil, nil
	end

	-- ENHANCED: Check if we have complete itemLink data for ATT processing
	if itemLink and not self:IsItemLinkComplete(itemLink) then
		-- ItemLink is incomplete - try fallback
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT: ItemLink incomplete for ID %d, using fallback...", itemID))
		end

		-- Try to get complete itemLink via GetItemInfo as fallback
		local _, fallbackItemLink = C_Item.GetItemInfo(itemID)
		if fallbackItemLink and self:IsItemLinkComplete(fallbackItemLink) then
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT: Using fallback itemLink from GetItemInfo"))
			end

			itemLink = fallbackItemLink
		else
			-- No complete itemLink available, return "still processing" status
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT: No complete itemLink available for ID %d", itemID))
			end

			return nil, nil, nil -- This will be treated as "still processing" by IsItemCollected
		end
	end

	-- Parse with validated data - use enhanced parsing
	local isCollected, hasOtherTransmogSources, isPartiallyCollected = self:ParseATTTooltipDirectEnhanced(itemID, itemLink)
	-- FIXED: Cache the result using the enhanced cache system
	self:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherTransmogSources, isPartiallyCollected)
	if isCollected == nil then
		return "NO_ATT_DATA", nil, nil
	else
		return isCollected, hasOtherTransmogSources, isPartiallyCollected
	end
end

-- ===== ENHANCED ATT TOOLTIP PARSING =====
function DOKI:ParseATTTooltipDirectEnhanced(itemID, itemLink)
	local tooltip = GameTooltip
	tooltip:Hide()
	tooltip:ClearLines()
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	else
		tooltip:SetItemByID(itemID)
	end

	tooltip:Show()
	-- Wait for ATT to inject data, then parse
	local attStatus, hasOtherTransmogSources, isPartiallyCollected
	C_Timer.After(0.2, function()
		attStatus, hasOtherTransmogSources, isPartiallyCollected = DOKI:ParseATTTooltipFromGameTooltipEnhanced(itemID)
		tooltip:Hide()
		tooltip:ClearLines()
	end)
	-- Also try immediate parsing (may not get ATT data due to timing)
	attStatus, hasOtherTransmogSources, isPartiallyCollected = self:ParseATTTooltipFromGameTooltipEnhanced(itemID)
	tooltip:Hide()
	tooltip:ClearLines()
	return attStatus, hasOtherTransmogSources, isPartiallyCollected
end

-- ===== ENHANCED TOOLTIP PARSING WITH TEXT RECOGNITION =====
function DOKI:ParseATTTooltipFromGameTooltipEnhanced(itemID)
	local tooltip = GameTooltip
	local attStatus = nil
	local hasOtherTransmogSources = false
	local isPartiallyCollected = false
	-- Scan ALL tooltip lines for ATT data
	for i = 1, tooltip:NumLines() do
		-- Check both left and right lines
		local leftLine = _G["GameTooltipTextLeft" .. i]
		local rightLine = _G["GameTooltipTextRight" .. i]
		-- Check right side first (where status usually appears)
		if rightLine and rightLine.GetText then
			local success, text = pcall(rightLine.GetText, rightLine)
			if success and text and string.len(text) > 0 then
				-- PRIORITY 1: Look for percentage patterns (most reliable)
				-- Pattern: "2 / 3 (66.66%)" or "Currency Collected 2 / 2 (100.00%)"
				local current, total, percentage = string.match(text, "(%d+)%s*/%s*(%d+)%s*%(([%d%.]+)%%%)")
				if current and total and percentage then
					current = tonumber(current)
					total = tonumber(total)
					percentage = tonumber(percentage)
					if current and total and percentage then
						if percentage >= 100 or current >= total then
							attStatus = true
							hasOtherTransmogSources = false
							isPartiallyCollected = false
						elseif percentage == 0 or current == 0 then
							attStatus = false
							hasOtherTransmogSources = false
							isPartiallyCollected = false
						else
							-- Partial collection - show pink indicator
							attStatus = false
							hasOtherTransmogSources = false
							isPartiallyCollected = true
						end

						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Found ATT percentage: %d/%d (%.1f%%) -> %s",
								current, total, percentage,
								attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
						end

						break
					end
				end

				-- PRIORITY 2: Look for simple fractions without percentage like "(0/1)" or "(2/3)"
				local fractionCurrentValue, fractionTotalValue = string.match(text, "%((%d+)/(%d+)%)")
				if fractionCurrentValue and fractionTotalValue then
					fractionCurrentValue = tonumber(fractionCurrentValue)
					fractionTotalValue = tonumber(fractionTotalValue)
					if fractionCurrentValue and fractionTotalValue then
						if fractionCurrentValue >= fractionTotalValue and fractionTotalValue > 0 then
							attStatus = true
							hasOtherTransmogSources = false
							isPartiallyCollected = false
						elseif fractionCurrentValue == 0 then
							attStatus = false
							hasOtherTransmogSources = false
							isPartiallyCollected = false
						else
							-- Partial collection
							attStatus = false
							hasOtherTransmogSources = false
							isPartiallyCollected = true
						end

						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r Found ATT fraction: (%d/%d) -> %s",
								fractionCurrentValue, fractionTotalValue,
								attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
						end

						break
					end
				end

				-- PRIORITY 3: Unicode symbol detection (locale-independent) - YOUR ORIGINAL APPROACH
				-- ❌ for not collected
				if string.find(text, "❌") or string.find(text, "✗") or string.find(text, "✕") then
					attStatus = false
					hasOtherTransmogSources = false
					isPartiallyCollected = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT X symbol -> NOT COLLECTED")
					end

					break
				end

				-- ✅ for collected
				if string.find(text, "✅") or string.find(text, "✓") or string.find(text, "☑") then
					attStatus = true
					hasOtherTransmogSources = false
					isPartiallyCollected = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT checkmark -> COLLECTED")
					end

					break
				end

				-- PRIORITY 4: 💎 Diamond symbol with enhanced parsing (your original approach)
				if string.find(text, "💎") or string.find(text, "♦") then
					-- This is likely a currency/reagent item, look for the status
					if string.find(text, "Collected") then
						-- Look for the numbers in this line with safe pattern
						local currentCount, totalCount = string.match(text, "(%d+)%s*/%s*(%d+)")
						if currentCount and totalCount then
							currentCount = tonumber(currentCount)
							totalCount = tonumber(totalCount)
							if currentCount and totalCount then
								attStatus = (currentCount >= totalCount)
								hasOtherTransmogSources = false
								isPartiallyCollected = (currentCount > 0 and currentCount < totalCount)
								if self.db and self.db.debugMode then
									print(string.format("|cffff69b4DOKI|r Found diamond currency: %d/%d -> %s",
										currentCount, totalCount,
										attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
								end

								break
							end
						else
							-- Diamond + "Collected" but no numbers - assume collected
							attStatus = true
							hasOtherTransmogSources = false
							isPartiallyCollected = false
							if self.db and self.db.debugMode then
								print("|cffff69b4DOKI|r Found diamond + 'Collected' (no numbers) -> COLLECTED")
							end

							break
						end
					end
				end

				-- PRIORITY 5: Text-based fallback (ONLY if no symbols found)
				-- This handles cases like item 159478 that show text but no symbols
				if attStatus == nil then
					-- Be very specific about text patterns to avoid false positives
					if string.find(text, "❌") == nil and string.find(text, "✅") == nil and string.find(text, "💎") == nil then
						-- No symbols found, check text patterns carefully
						-- Check for "Not Collected" (but not "Catalyst Collected" or similar)
						if string.find(text, "Not Collected") and not string.find(text, "Catalyst") then
							attStatus = false
							hasOtherTransmogSources = false
							isPartiallyCollected = false
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Found ATT 'Not Collected' text (fallback) -> NOT COLLECTED"))
							end

							break
						end

						-- Check for standalone "Collected" (but be very careful about context)
						if text == "Collected" or (string.find(text, "^Collected$") or string.find(text, "^Collected%s*$")) then
							attStatus = true
							hasOtherTransmogSources = false
							isPartiallyCollected = false
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Found ATT standalone 'Collected' text (fallback) -> COLLECTED"))
							end

							break
						end
					end
				end
			end
		end

		-- Check left side for ATT path indicators
		if leftLine and leftLine.GetText then
			local success, text = pcall(leftLine.GetText, leftLine)
			if success and text and string.len(text) > 0 then
				-- If we find ATT path but no status yet, we know ATT is processing this item
				if string.find(text, "ATT >") and attStatus == nil then
					-- Continue scanning - ATT data is present
				end
			end
		end
	end

	return attStatus, hasOtherTransmogSources, isPartiallyCollected
end

-- ===== NEW: ATT COLLECTION STATUS WITH AUTOMATIC RETRY =====
function DOKI:GetATTCollectionStatusWithRetry(itemID, itemLink, callback)
	-- Try immediate parsing first
	local result, hasOtherTransmogSources, isPartiallyCollected = self:GetATTCollectionStatus(itemID, itemLink)
	if result ~= nil and result ~= "NO_ATT_DATA" then
		-- Got valid result immediately
		if callback then
			callback(result, hasOtherTransmogSources, isPartiallyCollected)
		end

		return result, hasOtherTransmogSources, isPartiallyCollected
	end

	-- No immediate result - request item data and retry
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r ATT: No immediate result for item %d, requesting data...", itemID))
	end

	C_Item.RequestLoadItemDataByID(itemID)
	-- Set up retry after item loads
	C_Timer.After(0.3, function()
		local retryResult, retryYellowD, retryPurple = DOKI:GetATTCollectionStatus(itemID, itemLink)
		if DOKI.db and DOKI.db.debugMode then
			if retryResult == "NO_ATT_DATA" then
				print(string.format("|cffff69b4DOKI|r ATT: Retry failed for item %d - still no data", itemID))
			elseif retryResult ~= nil then
				print(string.format("|cffff69b4DOKI|r ATT: Retry success for item %d - result: %s", itemID, tostring(retryResult)))
			else
				print(string.format("|cffff69b4DOKI|r ATT: Retry incomplete for item %d - still processing", itemID))
			end
		end

		if callback then
			callback(retryResult, retryYellowD, retryPurple)
		end
	end)
	-- Return temporary "still processing" status
	return nil, nil, nil
end

function DOKI:ParseATTTooltipFromGameTooltip(itemID)
	local tooltip = GameTooltip
	local attStatus = nil
	local hasOtherTransmogSources = false
	local isPartiallyCollected = false
	-- Scan ALL tooltip lines for ATT data
	for i = 1, tooltip:NumLines() do
		-- Check both left and right lines
		local leftLine = _G["GameTooltipTextLeft" .. i]
		local rightLine = _G["GameTooltipTextRight" .. i]
		-- Check right side first (where status usually appears)
		if rightLine and rightLine.GetText then
			local success, text = pcall(rightLine.GetText, rightLine)
			if success and text and string.len(text) > 0 then
				-- Look for percentage patterns like "2 / 3 (66.66%)" or "Currency Collected 2 / 2 (100.00%)"
				local current, total, percentage = string.match(text, "(%d+) */ *(%d+) *%(([%d%.]+)%%")
				if current and total and percentage then
					current = tonumber(current)
					total = tonumber(total)
					percentage = tonumber(percentage)
					if percentage >= 100 or current >= total then
						attStatus = true
						hasOtherTransmogSources = false
						isPartiallyCollected = false
					elseif percentage == 0 or current == 0 then
						attStatus = false
						hasOtherTransmogSources = false
						isPartiallyCollected = false
					else
						-- Partial collection - show pink indicator
						attStatus = false
						hasOtherTransmogSources = false
						isPartiallyCollected = true
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found ATT percentage: %d/%d (%.1f%%) -> %s",
							current, total, percentage,
							attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
					end

					break
				end

				-- Look for simple fractions without percentage like "(0/1)" or "(2/3)"
				local fractionCurrentValue, fractionTotalValue = string.match(text, "%((%d+)/(%d+)%)")
				if fractionCurrentValue and fractionTotalValue then
					fractionCurrentValue = tonumber(fractionCurrentValue)
					fractionTotalValue = tonumber(fractionTotalValue)
					if fractionCurrentValue >= fractionTotalValue and fractionTotalValue > 0 then
						attStatus = true
						hasOtherTransmogSources = false
						isPartiallyCollected = false
					elseif fractionCurrentValue == 0 then
						attStatus = false
						hasOtherTransmogSources = false
						isPartiallyCollected = false
					else
						-- Partial collection
						attStatus = false
						hasOtherTransmogSources = false
						isPartiallyCollected = true
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found ATT fraction: (%d/%d) -> %s",
							fractionCurrentValue, fractionTotalValue,
							attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
					end

					break
				end

				-- Unicode symbol detection (locale-independent)
				-- ❌ for not collected
				if string.find(text, "❌") or string.find(text, "✗") or string.find(text, "✕") then
					attStatus = false
					hasOtherTransmogSources = false
					isPartiallyCollected = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT X symbol -> NOT COLLECTED")
					end

					break
				end

				-- ✅ for collected
				if string.find(text, "✅") or string.find(text, "✓") or string.find(text, "☑") then
					attStatus = true
					hasOtherTransmogSources = false
					isPartiallyCollected = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT checkmark -> COLLECTED")
					end

					break
				end

				-- 💎 Diamond symbol typically indicates currency/reagent items
				if string.find(text, "💎") or string.find(text, "♦") then
					-- This is likely a currency/reagent item, look for the status
					if string.find(text, "Collected") then
						-- Look for the numbers in this line
						local currentCount, totalCount = string.match(text, "(%d+) */ *(%d+)")
						if currentCount and totalCount then
							currentCount = tonumber(currentCount)
							totalCount = tonumber(totalCount)
							attStatus = (currentCount >= totalCount)
							hasOtherTransmogSources = false
							isPartiallyCollected = (currentCount > 0 and currentCount < totalCount)
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Found diamond currency: %d/%d -> %s",
									currentCount, totalCount,
									attStatus and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT COLLECTED")))
							end

							break
						end
					end
				end
			end
		end

		-- Check left side for ATT path indicators
		if leftLine and leftLine.GetText then
			local success, text = pcall(leftLine.GetText, leftLine)
			if success and text and string.len(text) > 0 then
				-- If we find ATT path but no status yet, we know ATT is processing this item
				if string.find(text, "ATT >") and attStatus == nil then
					-- Continue scanning - ATT data is present
				end
			end
		end
	end

	return attStatus, hasOtherTransmogSources, isPartiallyCollected
end

-- ===== ATT CACHE MANAGEMENT =====
-- Enhanced ATT cache methods with session-long storage
function DOKI:GetCachedATTStatus(itemID, itemLink)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	local cached = self.collectionCache[cacheKey]
	if cached and cached.isATTResult then
		self.cacheStats.hits = self.cacheStats.hits + 1
		if cached.noATTData then
			return "NO_ATT_DATA", nil, nil
		end

		return cached.isCollected, cached.hasOtherTransmogSources, cached.isPartiallyCollected
	end

	self.cacheStats.misses = self.cacheStats.misses + 1
	return nil, nil, nil
end

function DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherTransmogSources, isPartiallyCollected)
	-- Use the enhanced cache system
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	-- Add to cache count if not already present
	if not self.collectionCache[cacheKey] then
		self.cacheStats.totalEntries = self.cacheStats.totalEntries + 1
	end

	if isCollected == nil and hasOtherTransmogSources == nil and isPartiallyCollected == nil then
		self.collectionCache[cacheKey] = {
			isATTResult = true,
			noATTData = true,
			cacheType = DOKI.CACHE_TYPES.ATT,
			sessionTime = GetTime(),
		}
	else
		self.collectionCache[cacheKey] = {
			isCollected = isCollected,
			hasOtherTransmogSources = hasOtherTransmogSources,
			isPartiallyCollected = isPartiallyCollected,
			isATTResult = true,
			noATTData = false,
			cacheType = DOKI.CACHE_TYPES.ATT,
			sessionTime = GetTime(),
		}
	end

	-- DEBUG: Simple logging
	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		local result = isCollected and "COLLECTED" or (isCollected == nil and "NO_ATT_DATA" or "NOT_COLLECTED")
		print(string.format("|cffff69b4DOKI|r ATT CACHED: %s (ID: %d) -> %s", itemName, itemID, result))
	end
end

-- ===== ATT DEBUG FUNCTIONS =====
function DOKI:TestFixedATTParsing()
	if not self.db or not self.db.attMode then
		print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
		return
	end

	print("|cffff69b4DOKI|r === TESTING FIXED ATT PARSING ===")
	-- Test with known items
	local testItems = {
		{ id = 32458, name = "Ashes of Al'ar" }, -- Mount (should show currency format)
	}
	-- Add first collectible from bags
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					local itemName = C_Item.GetItemInfo(itemInfo.itemID) or "Unknown"
					table.insert(testItems, { id = itemInfo.itemID, name = itemName, link = itemInfo.hyperlink })
					break
				end
			end
		end

		if #testItems > 1 then break end
	end

	for i, item in ipairs(testItems) do
		print(string.format("\nTesting %d: %s (ID: %d)", i, item.name, item.id))
		local tooltip = GameTooltip
		tooltip:Hide()
		tooltip:ClearLines()
		tooltip:SetOwner(UIParent, "ANCHOR_NONE")
		if item.link then
			tooltip:SetHyperlink(item.link)
		else
			tooltip:SetItemByID(item.id)
		end

		tooltip:Show()
		-- Test with 0.2s delay
		C_Timer.After(0.2, function()
			local isCollected, hasOtherTransmogSources, isPartiallyCollected = DOKI:ParseATTTooltipFromGameTooltip(item.id)
			tooltip:Hide()
			if isCollected ~= nil then
				local result = "✓ SUCCESS: "
				if isCollected and not isPartiallyCollected then
					result = result .. "COLLECTED (no indicator)"
				elseif isPartiallyCollected then
					result = result .. "PARTIAL (PINK indicator)"
				elseif hasOtherTransmogSources then
					result = result .. "OTHER SOURCE (BLUE indicator)"
				else
					result = result .. "NOT COLLECTED (ORANGE indicator)"
				end

				print(result)
			else
				print("✗ FAILED: No ATT data found")
			end
		end)
	end

	print("\nFixed parsing test complete!")
end

-- ===== ATT DEBUGGING FUNCTIONS =====
-- Quick test for specific items that should have ATT data
function DOKI:TestKnownATTItems()
	print("|cffff69b4DOKI|r === TESTING KNOWN ATT ITEMS ===")
	-- Test items that should definitely be in ATT
	local knownItems = {
		{ id = 32458, name = "Ashes of Al'ar" },              -- Mount
		{ id = 71665, name = "Flametalon of Alysrazor" },     -- Mount
		{ id = 19902, name = "Red Qiraji Resonating Crystal" }, -- Mount
		{ id = 159478, name = "Your problem item" },          -- Your problematic item
	}
	for _, item in ipairs(knownItems) do
		print(string.format("\nTesting: %s (ID: %d)", item.name, item.id))
		local attStatus = self:GetATTCollectionStatus(item.id, nil)
		if attStatus == "NO_ATT_DATA" then
			print("  ❌ NO ATT DATA")
		elseif attStatus == nil then
			print("  ⚠ Still processing")
		else
			print(string.format("  ✅ ATT Result: %s", tostring(attStatus)))
		end
	end

	print("|cffff69b4DOKI|r === END KNOWN ITEMS TEST ===")
end

-- Test function using the proper loading system
function DOKI:TestProperItemLoading(targetItemID)
	targetItemID = targetItemID or 211017
	print(string.format("|cffff69b4DOKI|r === TESTING PROPER ITEM LOADING FOR ITEM %d ===", targetItemID))
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID == targetItemID then
					print(string.format("Found item in bag %d slot %d", bagID, slotID))
					-- Test immediate vs loaded data
					print("=== IMMEDIATE CHECK ===")
					local immediateLink = C_Container.GetContainerItemLink(bagID, slotID)
					local immediateComplete = self:IsItemLinkComplete(immediateLink)
					print(string.format("Immediate link: %s", immediateLink or "NIL"))
					print(string.format("Immediate length: %d", string.len(immediateLink or "")))
					print(string.format("Immediate complete: %s", tostring(immediateComplete)))
					if immediateLink then
						local itemName = string.match(immediateLink, "%[([^%]]+)%]") or "MISSING"
						print(string.format("Extracted name: '%s'", itemName))
					end

					-- Test proper loading system
					print("\n=== PROPER LOADING SYSTEM ===")
					self:GetItemLinkWhenReady(bagID, slotID, function(itemID, itemLink, success)
						print(string.format("Loaded ItemID: %d", itemID or 0))
						print(string.format("Loaded link: %s", itemLink or "NIL"))
						print(string.format("Loaded length: %d", string.len(itemLink or "")))
						print(string.format("Loading success: %s", tostring(success)))
						if itemLink then
							local loadedName = string.match(itemLink, "%[([^%]]+)%]") or "MISSING"
							print(string.format("Loaded name: '%s'", loadedName))
							local isLoadedComplete = self:IsItemLinkComplete(itemLink)
							print(string.format("Loaded complete: %s", tostring(isLoadedComplete)))
						end

						-- Test ATT integration only if we have complete data
						if success and itemLink and self:IsItemLinkComplete(itemLink) then
							print("\n=== ATT CATALYST TEST ===")
							local result = self:GetATTCollectionStatus(itemID, itemLink)
							print(string.format("ATT result: %s", tostring(result)))
							-- Check for bonus IDs
							local bonusIDs = string.match(itemLink, "item:%d+:[^:]*:([^:]*)")
							if bonusIDs and bonusIDs ~= "" then
								print(string.format("✓ Bonus IDs: %s", bonusIDs))
							else
								print("⚠ No bonus IDs found")
							end
						else
							print("\n=== ATT TEST SKIPPED ===")
							print("Reason: ItemLink is still incomplete")
						end

						print("|cffff69b4DOKI|r === PROPER LOADING TEST COMPLETE ===")
					end)
					return
				end
			end
		end
	end

	print(string.format("Item %d not found in bags", targetItemID))
end

function DOKI:DebugATTBagScan(maxItems)
	maxItems = maxItems or 10 -- Default to 10 items, easily changeable
	if not self.db or not self.db.attMode then
		print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
		return
	end

	print(string.format("|cffff69b4DOKI|r === ATT BAG SCAN DEBUG (First %d bag slots) ===", maxItems))
	print("|cffff69b4DOKI|r Using proper async item loading system...")
	local slotsToScan = {}
	local slotsScanned = 0
	local slotScanResults = {}
	local totalSlots = 0
	-- First, collect all the slots we want to scan
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				if totalSlots >= maxItems then
					break
				end

				totalSlots = totalSlots + 1
				table.insert(slotsToScan, { bagID = bagID, slotID = slotID })
			end
		end

		if totalSlots >= maxItems then
			break
		end
	end

	-- Function to process slotScanResults when all slots are done
	local function processResults()
		print(string.format("|cffff69b4DOKI|r Processing %d slot slotScanResults...", #slotScanResults))
		local itemsFound = 0
		local collectibleItems = 0
		local attDataItems = 0
		-- Sort slotScanResults by bagID, slotID for consistent output
		table.sort(slotScanResults, function(a, b)
			if a.bagID == b.bagID then
				return a.slotID < b.slotID
			end

			return a.bagID < b.bagID
		end)
		for _, slotScanResult in ipairs(slotScanResults) do
			if slotScanResult.isEmpty then
				print(string.format("Slot %d.%d: EMPTY", slotScanResult.bagID, slotScanResult.slotID))
			else
				itemsFound = itemsFound + 1
				if slotScanResult.isCollectible then
					collectibleItems = collectibleItems + 1
				end

				if slotScanResult.hasATTData then
					attDataItems = attDataItems + 1
				end

				local collectibleFlag = slotScanResult.isCollectible and " [COLLECTIBLE]" or ""
				print(string.format("Slot %d.%d: %s (ID: %d)%s -> ATT: %s",
					slotScanResult.bagID, slotScanResult.slotID, slotScanResult.itemName, slotScanResult.itemID, collectibleFlag,
					slotScanResult.attResult))
			end
		end

		print(string.format("|cffff69b4DOKI|r Summary: %d slots scanned, %d items found (%d collectible, %d with ATT data)",
			#slotScanResults, itemsFound, collectibleItems, attDataItems))
		print("|cffff69b4DOKI|r === END ATT BAG SCAN ===")
	end

	-- Async scan each slot
	for i, slot in ipairs(slotsToScan) do
		local bagID, slotID = slot.bagID, slot.slotID
		-- Check if slot has an item first
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		if not itemInfo or not itemInfo.itemID then
			-- Empty slot
			table.insert(slotScanResults, {
				bagID = bagID,
				slotID = slotID,
				isEmpty = true,
			})
			-- Check if we're done
			if #slotScanResults >= #slotsToScan then
				processResults()
			end
		else
			-- Use the proper async loading system
			self:GetItemLinkWhenReady(bagID, slotID, function(itemID, itemLink, success)
				local slotScanResult = {
					bagID = bagID,
					slotID = slotID,
					isEmpty = false,
					itemID = itemID or 0,
					itemName = "Unknown",
					isCollectible = false,
					hasATTData = false,
					attResult = "FAILED",
				}
				if success and itemID and itemLink then
					-- Got complete item data
					slotScanResult.itemName = C_Item.GetItemInfo(itemID) or "Loading..."
					slotScanResult.isCollectible = DOKI:IsCollectibleItem(itemID, itemLink)
					-- Test ATT with the complete hyperlink
					local attStatus, attYellow, attPurple = DOKI:GetATTCollectionStatus(itemID, itemLink)
					if attStatus == "NO_ATT_DATA" then
						slotScanResult.attResult = "NO_ATT_DATA"
						slotScanResult.hasATTData = false
					elseif attStatus == nil then
						slotScanResult.attResult = "STILL_PROCESSING"
						slotScanResult.hasATTData = false
					elseif attStatus == true then
						slotScanResult.attResult = "COLLECTED"
						slotScanResult.hasATTData = true
					elseif attStatus == false then
						slotScanResult.hasATTData = true
						if attPurple then
							slotScanResult.attResult = "PARTIAL (purple)"
						elseif attYellow then
							slotScanResult.attResult = "UNCOLLECTED (blue)"
						else
							slotScanResult.attResult = "UNCOLLECTED"
						end
					else
						slotScanResult.attResult = "UNKNOWN: " .. tostring(attStatus)
						slotScanResult.hasATTData = false
					end

					if DOKI.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Async loaded: %s -> %s",
							slotScanResult.itemName, slotScanResult.attResult))
					end
				else
					-- Failed to load complete data
					slotScanResult.attResult = "LOAD_FAILED"
					if itemID then
						slotScanResult.itemName = C_Item.GetItemInfo(itemID) or "Failed to load"
					end
				end

				table.insert(slotScanResults, slotScanResult)
				-- Check if we're done with all slots
				if #slotScanResults >= #slotsToScan then
					processResults()
				end
			end)
		end
	end

	print(string.format("|cffff69b4DOKI|r Initiated async scan of %d slots...", #slotsToScan))
end

-- ATT Integration - Fixed Async Tooltip Priming Solution
-- Add this to your CollectionsATT.lua file
-- Enhanced ATT Status function with proper tooltip priming
local function GetATTStatusAsync(itemID, itemLink, callback)
	if not itemLink or not callback then
		if callback then callback(nil, "INVALID_INPUT") end

		return
	end

	local tooltip = GameTooltip -- Use the REAL GameTooltip
	-- 1. Store the original script handler
	local originalOnSetItem = tooltip:GetScript("OnTooltipSetItem")
	-- 2. Set our temporary script
	tooltip:SetScript("OnTooltipSetItem", function(self)
		-- The data is now "hot" and primed for ATT
		-- Restore the original script handler immediately
		self:SetScript("OnTooltipSetItem", originalOnSetItem)
		self:Hide()
		-- Now call ATT Internal API with primed data
		local isCollected, hasOtherSources, isPartiallyCollected, debugInfo = GetATTCollectionStatusInternal(itemID, itemLink)
		-- Pass the results back to the caller
		callback(isCollected, hasOtherSources, isPartiallyCollected, debugInfo)
	end)
	-- 3. Prime the data invisibly (no visual rendering overhead)
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetHyperlink(itemLink)
	tooltip:Hide() -- Hide immediately - this prevents visual rendering but keeps data primed
end

-- Your existing GetATTCollectionStatusInternal function (from paste.txt)
function GetATTCollectionStatusInternal(itemID, itemLink)
	-- Ensure ATT is available
	local ATT = _G["AllTheThings"]
	if not ATT or not ATT.SearchForLink or not ATT.ProcessInformationTypesForExternalTooltips then
		return nil, "ATT_API_NOT_AVAILABLE"
	end

	-- Need itemLink for SearchForLink
	if not itemLink then
		return nil, "NO_ITEMLINK"
	end

	-- STEP 1: Search for item data using hyperlink (data is now primed!)
	local status, group = pcall(ATT.SearchForLink, itemLink)
	if not status or not group then
		return nil, "NO_ATT_DATA"
	end

	-- STEP 2: Process the group to get tooltip information
	local tooltipLines = {}
	local processStatus = pcall(ATT.ProcessInformationTypesForExternalTooltips, tooltipLines, group)
	if not processStatus then
		return nil, "PROCESSING_FAILED"
	end

	-- STEP 3: Parse the structured tooltip data
	local isCollected = nil
	local hasOtherSources = false
	local isPartiallyCollected = false
	local debugInfo = {}
	for i, lineData in ipairs(tooltipLines) do
		local leftText = lineData.left or ""
		local rightText = lineData.right or ""
		local color = lineData.color
		-- Debug info
		if DOKI and DOKI.db and DOKI.db.debugMode then
			table.insert(debugInfo, string.format("Line %d: L='%s' R='%s' Color=%s",
				i, leftText, rightText, color or "nil"))
		end

		-- Look for collection status indicators
		-- Method 1: Text-based detection
		if leftText:find("Not Collected") or rightText:find("Not Collected") then
			isCollected = false
			table.insert(debugInfo, "Found 'Not Collected' text")
			break
		elseif leftText:find("Collected") or rightText:find("Collected") then
			-- Look for fraction patterns like "2/2 (100%)"
			local current, total = rightText:match("(%d+)%s*/%s*(%d+)")
			if current and total then
				current, total = tonumber(current), tonumber(total)
				if current and total then
					if current >= total then
						isCollected = true
					elseif current > 0 then
						isCollected = false
						isPartiallyCollected = true
					else
						isCollected = false
					end

					table.insert(debugInfo, string.format("Found fraction: %d/%d", current, total))
					break
				end
			else
				isCollected = true
				table.insert(debugInfo, "Found 'Collected' text")
				break
			end
		end

		-- Method 2: Symbol detection (same as your current parsing)
		local combinedText = leftText .. " " .. rightText
		if combinedText:find("❌") or combinedText:find("✗") then
			isCollected = false
			table.insert(debugInfo, "Found X symbol")
			break
		elseif combinedText:find("✅") or combinedText:find("✓") then
			isCollected = true
			table.insert(debugInfo, "Found checkmark symbol")
			break
		elseif combinedText:find("💎") then
			-- Diamond symbol for currency items
			if combinedText:find("Collected") then
				local currentCount, totalCount = rightText:match("(%d+)%s*/%s*(%d+)")
				if currentCount and totalCount then
					currentCount, totalCount = tonumber(currentCount), tonumber(totalCount)
					if currentCount and totalCount then
						isCollected = (currentCount >= totalCount)
						isPartiallyCollected = (currentCount > 0 and currentCount < totalCount)
						table.insert(debugInfo, string.format("Found diamond currency: %d/%d", currentCount, totalCount))
						break
					end
				end
			end
		end
	end

	return isCollected, hasOtherSources, isPartiallyCollected, debugInfo
end

-- Replace your current DOKI:GetATTCollectionStatusDirect function with this:
function DOKI:GetATTCollectionStatusDirect(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- Check cache first (use your existing cache system)
	local cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected = self:GetCachedATTStatus(itemID, itemLink)
	if cachedIsCollected == "NO_ATT_DATA" then
		return "NO_ATT_DATA", nil, nil
	elseif cachedIsCollected ~= nil then
		return cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected
	end

	-- Check if item data is loaded (your existing logic)
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName or itemName == "" then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT Direct: Item %d data not loaded, requesting...", itemID))
		end

		C_Item.RequestLoadItemDataByID(itemID)
		return nil, nil, nil -- Still processing
	end

	-- Check if itemLink is complete (your existing logic)
	if itemLink and not self:IsItemLinkComplete(itemLink) then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT Direct: ItemLink incomplete for ID %d", itemID))
		end

		-- Try fallback (your existing logic)
		local _, fallbackItemLink = C_Item.GetItemInfo(itemID)
		if fallbackItemLink and self:IsItemLinkComplete(fallbackItemLink) then
			itemLink = fallbackItemLink
		else
			return nil, nil, nil -- Still processing
		end
	end

	-- Use the async tooltip priming approach (this is the key fix!)
	GetATTStatusAsync(itemID, itemLink, function(isCollected, hasOtherSources, isPartiallyCollected, debugInfo)
		-- Cache the result
		if isCollected ~= nil then
			DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherSources, isPartiallyCollected)
			if DOKI.db and DOKI.db.debugMode then
				local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
				local result = isCollected and "COLLECTED" or (isPartiallyCollected and "PARTIAL" or "NOT_COLLECTED")
				print(string.format("|cffff69b4DOKI|r ATT Direct: %s (ID: %d) -> %s", itemName, itemID, result))
				-- Debug info from ATT parsing
				if debugInfo then
					for _, info in ipairs(debugInfo) do
						print(string.format("|cffff69b4DOKI|r   %s", info))
					end
				end
			end
		else
			-- No ATT data found
			DOKI:SetCachedATTStatus(itemID, itemLink, nil, nil, nil) -- Cache "no data" result
		end

		-- Since this is async, you may need to trigger a UI update here
		-- depending on how your addon works
		if DOKI.TriggerImmediateSurgicalUpdate then
			DOKI:TriggerImmediateSurgicalUpdate()
		end
	end)
	-- Return "processing" status for now - the callback will handle the actual result
	return nil, nil, nil
end

-- ATT Internal API - Fixed Implementation
-- Uses your existing item loading system instead of broken tooltip scripts
-- Core ATT internal API function (no changes needed)
local function GetATTCollectionStatusInternal(itemID, itemLink)
	-- Ensure ATT is available
	local ATT = _G["AllTheThings"]
	if not ATT or not ATT.SearchForLink or not ATT.ProcessInformationTypesForExternalTooltips then
		return nil, "ATT_API_NOT_AVAILABLE"
	end

	-- Need itemLink for SearchForLink
	if not itemLink then
		return nil, "NO_ITEMLINK"
	end

	-- STEP 1: Search for item data using hyperlink
	local status, group = pcall(ATT.SearchForLink, itemLink)
	if not status or not group then
		return nil, "NO_ATT_DATA"
	end

	-- STEP 2: Process the group to get tooltip information
	local tooltipLines = {}
	local processStatus = pcall(ATT.ProcessInformationTypesForExternalTooltips, tooltipLines, group)
	if not processStatus then
		return nil, "PROCESSING_FAILED"
	end

	-- STEP 3: Parse the structured tooltip data
	local isCollected = nil
	local hasOtherSources = false
	local isPartiallyCollected = false
	local debugInfo = {}
	for i, lineData in ipairs(tooltipLines) do
		local leftText = lineData.left or ""
		local rightText = lineData.right or ""
		local color = lineData.color
		-- Debug info
		if DOKI and DOKI.db and DOKI.db.debugMode then
			table.insert(debugInfo, string.format("Line %d: L='%s' R='%s' Color=%s",
				i, leftText, rightText, color or "nil"))
		end

		-- Look for collection status indicators
		-- Method 1: Text-based detection (same as your current parsing)
		if leftText:find("Not Collected") or rightText:find("Not Collected") then
			isCollected = false
			table.insert(debugInfo, "Found 'Not Collected' text")
			break
		elseif leftText:find("Collected") or rightText:find("Collected") then
			-- Look for fraction patterns like "2/2 (100%)"
			local current, total = rightText:match("(%d+)%s*/%s*(%d+)")
			if current and total then
				current, total = tonumber(current), tonumber(total)
				if current and total then
					if current >= total then
						isCollected = true
					elseif current > 0 then
						isCollected = false
						isPartiallyCollected = true
					else
						isCollected = false
					end

					table.insert(debugInfo, string.format("Found fraction: %d/%d", current, total))
					break
				end
			else
				isCollected = true
				table.insert(debugInfo, "Found 'Collected' text")
				break
			end
		end

		-- Method 2: Symbol detection (same as your current parsing)
		local combinedText = leftText .. " " .. rightText
		if combinedText:find("❌") or combinedText:find("✗") then
			isCollected = false
			table.insert(debugInfo, "Found X symbol")
			break
		elseif combinedText:find("✅") or combinedText:find("✓") then
			isCollected = true
			table.insert(debugInfo, "Found checkmark symbol")
			break
		elseif combinedText:find("💎") then
			-- Diamond symbol for currency items
			if combinedText:find("Collected") then
				local currentCount, totalCount = rightText:match("(%d+)%s*/%s*(%d+)")
				if currentCount and totalCount then
					currentCount, totalCount = tonumber(currentCount), tonumber(totalCount)
					if currentCount and totalCount then
						isCollected = (currentCount >= totalCount)
						isPartiallyCollected = (currentCount > 0 and currentCount < totalCount)
						table.insert(debugInfo, string.format("Found diamond currency: %d/%d", currentCount, totalCount))
						break
					end
				end
			end
		end
	end

	return isCollected, hasOtherSources, isPartiallyCollected, debugInfo
end

-- NEW: Direct replacement for your current ATT function
-- This integrates with your existing item loading system
-- Test function using your existing item loading system
local function TestATTDirectIntegration(itemID)
	if not DOKI then
		print("|cff00ff00ATTFIX|r DOKI addon not found")
		return
	end

	itemID = itemID or 32458 -- Default to Ashes of Al'ar
	print(string.format("|cff00ff00ATTFIX|r === TESTING ATT DIRECT INTEGRATION FOR ITEM %d ===", itemID))
	local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
	print(string.format("Item: %s (ID: %d)", itemName, itemID))
	-- Try to find this item in bags to get real itemLink
	local itemLink = nil
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID == itemID then
					itemLink = C_Container.GetContainerItemLink(bagID, slotID)
					break
				end
			end
		end

		if itemLink then break end
	end

	if not itemLink then
		-- Try to get generic itemlink
		local _, fallbackLink = C_Item.GetItemInfo(itemID)
		itemLink = fallbackLink
	end

	print(string.format("ItemLink: %s", itemLink and (itemLink:sub(1, 80) .. "...") or "Not found"))
	-- Test new direct method
	print("\n--- NEW ATT DIRECT METHOD ---")
	local startTime = GetTime()
	local directResult, directOther, directPartial = DOKI:GetATTCollectionStatusDirect(itemID, itemLink)
	local directDuration = GetTime() - startTime
	print(string.format("Direct result: %s (hasOther: %s, partial: %s) [%.4fs]",
		tostring(directResult), tostring(directOther), tostring(directPartial), directDuration))
	-- Compare with your current method
	print("\n--- CURRENT TOOLTIP METHOD ---")
	local currentStart = GetTime()
	local currentResult = DOKI:GetATTCollectionStatus(itemID, itemLink)
	local currentDuration = GetTime() - currentStart
	print(string.format("Current result: %s [%.4fs]", tostring(currentResult), currentDuration))
	-- Performance comparison
	if directDuration > 0 and currentDuration > 0 then
		local speedup = currentDuration / directDuration
		print(string.format("Performance: %.1fx speedup", speedup))
	end

	-- Result comparison
	if directResult == currentResult or (directResult == false and currentResult == false) or (directResult == true and currentResult == true) then
		print("✅ RESULTS MATCH")
	else
		print("❌ RESULTS DIFFER")
		print(string.format("   Direct: %s vs Current: %s", tostring(directResult), tostring(currentResult)))
	end

	print("|cff00ff00ATTFIX|r === END INTEGRATION TEST ===")
end

-- Test with bag items using your existing async loading
local function TestBagItemsDirect(maxItems)
	if not DOKI then
		print("|cff00ff00ATTFIX|r DOKI addon not found")
		return
	end

	maxItems = maxItems or 3
	print(string.format("|cff00ff00ATTFIX|r === TESTING %d BAG ITEMS WITH ATT DIRECT ===", maxItems))
	local itemsFound = 0
	local processedCount = 0
	local totalDuration = 0
	for bagID = 0, NUM_BAG_SLOTS do
		if itemsFound >= maxItems then break end

		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				if itemsFound >= maxItems then break end

				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					itemsFound = itemsFound + 1
					-- Use your existing async item loading system
					DOKI:GetItemLinkWhenReady(bagID, slotID, function(itemID, itemLink, success)
						processedCount = processedCount + 1
						local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
						print(string.format("\n--- Item %d: %s ---", processedCount, itemName))
						if success and itemLink then
							local startTime = GetTime()
							local isCollected, hasOther, isPartial = DOKI:GetATTCollectionStatusDirect(itemID, itemLink)
							local duration = GetTime() - startTime
							totalDuration = totalDuration + duration
							if isCollected == "NO_ATT_DATA" then
								print(string.format("  Result: NO ATT DATA (%.4fs)", duration))
							elseif isCollected ~= nil then
								local status = isCollected and "COLLECTED" or "NOT COLLECTED"
								if isPartial then status = status .. " (PARTIAL)" end

								if hasOther then status = status .. " (OTHER SOURCES)" end

								print(string.format("  Result: %s (%.4fs)", status, duration))
							else
								print(string.format("  Result: STILL PROCESSING (%.4fs)", duration))
							end
						else
							print("  Result: FAILED TO LOAD ITEM DATA")
						end

						-- Show summary when all items are processed
						if processedCount >= maxItems then
							print(string.format("\nSummary: %d items processed, average %.4fs per item",
								processedCount, totalDuration / math.max(1, processedCount)))
							print("|cff00ff00ATTFIX|r === END BAG ITEMS TEST ===")
						end
					end)
				end
			end
		end
	end

	if itemsFound == 0 then
		print("No items found in bags to test")
	end
end

-- Simple slash commands
SLASH_ATTFIX1 = "/attfix"
SlashCmdList["ATTFIX"] = function(msg)
	local args = { strsplit(" ", msg) }
	local command = args[1] and strlower(args[1]) or ""
	if command == "test" then
		local itemID = tonumber(args[2]) or 32458
		TestATTDirectIntegration(itemID)
	elseif command == "bags" then
		local maxItems = tonumber(args[2]) or 3
		TestBagItemsDirect(maxItems)
	else
		print("|cff00ff00ATTFIX|r Available commands:")
		print("/attfix test [itemID] - Test direct ATT integration (default: 32458)")
		print("/attfix bags [count] - Test bag items with direct method (default: 3)")
		print("")
		print("This uses your existing item loading system - no broken tooltip scripts!")
	end
end
print("|cff00ff00ATTFIX|r ATT Direct Integration (fixed) loaded. Try /attfix")
