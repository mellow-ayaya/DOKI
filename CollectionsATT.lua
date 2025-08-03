-- DOKI Collections ATT - AllTheThings Integration Functions
local addonName, DOKI = ...
-- ===== ENHANCED ATT COLLECTION STATUS WITH ITEM LOADING =====
function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- Check cache first
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
	-- Cache the result
	if isCollected ~= nil then
		self:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherTransmogSources, isPartiallyCollected)
	else
		self:SetCachedATTStatus(itemID, itemLink, nil, nil, nil)
	end

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
function DOKI:GetCachedATTStatus(itemID, itemLink)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	local cached = self.collectionCache[cacheKey]
	if cached and cached.isATTResult then
		if cached.noATTData then
			return "NO_ATT_DATA", nil, nil
		end

		return cached.isCollected, cached.hasOtherTransmogSources, cached.isPartiallyCollected
	end

	return nil, nil, nil
end

function DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherTransmogSources, isPartiallyCollected)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	if isCollected == nil and hasOtherTransmogSources == nil and isPartiallyCollected == nil then
		self.collectionCache[cacheKey] = {
			isATTResult = true,
			noATTData = true,
			timestamp = GetTime(),
		}
	else
		self.collectionCache[cacheKey] = {
			isCollected = isCollected,
			hasOtherTransmogSources = hasOtherTransmogSources,
			isPartiallyCollected = isPartiallyCollected,
			isATTResult = true,
			noATTData = false,
			timestamp = GetTime(),
		}
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
