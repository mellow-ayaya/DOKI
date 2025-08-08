-- DOKI Collections ATT - FINAL FIX: Borrow Real GameTooltip for ATT Hooks
local addonName, DOKI = ...
-- ===== NO MORE HIDDEN TOOLTIP - WE BORROW THE REAL ONE =====
-- Remove the hiddenTooltip variable and InitializeATTTooltip function
-- ATT only hooks the real GameTooltip now!
-- Keep your existing queue variables (unchanged)
local attProcessingQueue = {}
local isProcessingATT = false
local currentlyProcessingRequest = nil
-- FINAL FIX: Borrow the real GameTooltip temporarily
function ProcessNextATTInQueue()
	if #attProcessingQueue == 0 then
		isProcessingATT = false
		currentlyProcessingRequest = nil
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Queue empty, processing stopped")
		end

		return
	end

	local requestData = table.remove(attProcessingQueue, 1)
	currentlyProcessingRequest = {
		itemID = requestData[1],
		itemLink = requestData[2],
		callback = requestData[3],
	}
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r [Frame 1] Borrowing GameTooltip for item %d", currentlyProcessingRequest
			.itemID))
	end

	-- STEP 1: BORROW THE REAL GAMETOOLTIP
	-- Save its current owner so we can restore it
	local previousOwner = GameTooltip:GetOwner()
	-- Take control and move it off-screen
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	GameTooltip:ClearLines()
	-- Set the hyperlink - THIS will now trigger ATT's hooks because it's the real GameTooltip!
	GameTooltip:SetHyperlink(currentlyProcessingRequest.itemLink)
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r [Frame 1] Set hyperlink on real GameTooltip, waiting for ATT hooks..."))
	end

	-- STEP 2: Schedule the reading and restoration for next frame
	C_Timer.After(0, function()
		if not currentlyProcessingRequest then
			-- Failsafe: restore tooltip and continue queue
			if previousOwner then
				GameTooltip:SetOwner(previousOwner, "ANCHOR_CURSOR")
			else
				GameTooltip:Hide()
			end

			C_Timer.After(0.05, ProcessNextATTInQueue)
			return
		end

		if DOKI and DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r [Frame 2] Reading real GameTooltip for item %d",
				currentlyProcessingRequest.itemID))
		end

		local success, isCollected, hasOtherSources, isPartial, debugInfo = pcall(function()
			local numTooltipLines = GameTooltip:NumLines()
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Real GameTooltip now has %d lines after frame delay", numTooltipLines))
			end

			-- Check if ATT populated the real tooltip
			if numTooltipLines <= 2 then
				return nil, nil, nil, { "ATT_DID_NOT_POPULATE_REAL_TOOLTIP" }
			end

			-- Extract lines from the real GameTooltip
			local tooltipLinesForParser = {}
			for i = 1, numTooltipLines do
				-- Read from the REAL GameTooltip's text elements
				local leftLine = _G["GameTooltipTextLeft" .. i]
				local rightLine = _G["GameTooltipTextRight" .. i]
				if leftLine and rightLine then
					local leftText = leftLine:GetText() or ""
					local rightText = rightLine:GetText() or ""
					table.insert(tooltipLinesForParser, {
						left = leftText,
						right = rightText,
					})
					if DOKI and DOKI.db and DOKI.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Real tooltip line %d: left='%s' right='%s'", i, leftText, rightText))
					end
				end
			end

			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Extracted %d lines from real GameTooltip for parsing",
					#tooltipLinesForParser))
			end

			-- Parse with existing parser
			return ParseATTTooltipLines(tooltipLinesForParser, currentlyProcessingRequest.itemID,
				currentlyProcessingRequest.itemLink)
		end)
		-- STEP 3: RESTORE THE GAMETOOLTIP (CRITICAL!)
		-- Always restore the tooltip's owner, even if pcall failed
		if previousOwner then
			GameTooltip:SetOwner(previousOwner, "ANCHOR_CURSOR")
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r [Frame 2] Restored GameTooltip to previous owner")
			end
		else
			-- No previous owner - hide it to be safe
			GameTooltip:Hide()
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r [Frame 2] Hidden GameTooltip (no previous owner)")
			end
		end

		-- STEP 4: Handle the result
		if success then
			-- Cache and callback with result
			DOKI:SetCachedATTStatus(currentlyProcessingRequest.itemID, currentlyProcessingRequest.itemLink,
				isCollected, hasOtherSources, isPartial)
			currentlyProcessingRequest.callback(isCollected, hasOtherSources, isPartial, debugInfo)
			if DOKI and DOKI.db and DOKI.db.debugMode then
				local itemName = C_Item.GetItemInfo(currentlyProcessingRequest.itemID) or "Unknown"
				local result = isCollected and "COLLECTED" or
						(isCollected == nil and "NO_ATT_DATA" or (isPartial and "PARTIAL" or "NOT_COLLECTED"))
				print(string.format("|cffff69b4DOKI|r [Frame 2] %s -> %s", itemName, result))
			end
		else
			-- Handle error
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT error during real tooltip read for item %d: %s",
					currentlyProcessingRequest.itemID, tostring(isCollected)))
			end

			currentlyProcessingRequest.callback(nil, nil, nil, { "ATT_ERROR_IN_PROCESSING", tostring(isCollected) })
		end

		-- STEP 5: Process next item in queue
		currentlyProcessingRequest = nil
		C_Timer.After(0.05, ProcessNextATTInQueue)
	end)
end

-- KEEP: Your existing parsing function (unchanged - it's perfect!)
function ParseATTTooltipLines(tooltipLines, itemID, itemLink)
	local isCollected = nil
	local hasOtherSources = false
	local isPartiallyCollected = false
	local debugInfo = {}
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Starting parsing of %d tooltip lines...", #tooltipLines))
	end

	for i, lineData in ipairs(tooltipLines) do
		local leftText = lineData.left or ""
		local rightText = lineData.right or ""
		local combinedText = leftText .. " " .. rightText
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r   Parsing line %d: '%s'", i, combinedText))
		end

		-- Debug info
		if DOKI and DOKI.db and DOKI.db.debugMode then
			table.insert(debugInfo, string.format("Line %d: L='%s' R='%s'", i, leftText, rightText))
		end

		-- Priority 1: Percentage patterns "2/3 (66.66%)"
		local current, total, percentage = combinedText:match("(%d+)%s*/%s*(%d+)%s*%(([%d%.]+)%%%)")
		if current and total and percentage then
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r     Found percentage pattern: %s/%s (%s%%)", current, total, percentage))
			end

			current, total, percentage = tonumber(current), tonumber(total), tonumber(percentage)
			if current and total and percentage then
				if current >= total or percentage >= 100 then
					isCollected = true
				elseif current > 0 or percentage > 0 then
					isCollected = false
					isPartiallyCollected = true
				else
					isCollected = false
				end

				table.insert(debugInfo, string.format("Found percentage: %d/%d (%.1f%%)", current, total, percentage))
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r     Result: isCollected=%s, isPartiallyCollected=%s",
						tostring(isCollected), tostring(isPartiallyCollected)))
				end

				break
			end
		end

		-- Priority 2: Simple fractions "2/3" (not in parentheses)
		local simpleCurrent, simpleTotal = combinedText:match("(%d+)%s*/%s*(%d+)")
		if simpleCurrent and simpleTotal and not combinedText:match("%(.*" .. simpleCurrent .. "%s*/%s*" .. simpleTotal .. ".*%)") then
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r     Found simple fraction: %s/%s", simpleCurrent, simpleTotal))
			end

			simpleCurrent, simpleTotal = tonumber(simpleCurrent), tonumber(simpleTotal)
			if simpleCurrent and simpleTotal then
				if simpleCurrent >= simpleTotal then
					isCollected = true
				elseif simpleCurrent > 0 then
					isCollected = false
					isPartiallyCollected = true
				else
					isCollected = false
				end

				table.insert(debugInfo, string.format("Found fraction: %d/%d", simpleCurrent, simpleTotal))
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r     Result: isCollected=%s, isPartiallyCollected=%s",
						tostring(isCollected), tostring(isPartiallyCollected)))
				end

				break
			end
		end

		-- Priority 3: Unicode symbols
		if combinedText:find("❌") or combinedText:find("✗") or combinedText:find("✕") then
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r     Found X symbol -> NOT COLLECTED")
			end

			isCollected = false
			table.insert(debugInfo, "Found X symbol -> NOT COLLECTED")
			break
		end

		if combinedText:find("✅") or combinedText:find("✓") or combinedText:find("☑") then
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r     Found checkmark -> COLLECTED")
			end

			isCollected = true
			table.insert(debugInfo, "Found checkmark -> COLLECTED")
			break
		end

		-- Priority 4: Diamond symbol for currency/reagents
		if combinedText:find("💎") or combinedText:find("♦") then
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r     Found diamond symbol")
			end

			if combinedText:find("Collected") then
				local currentCount, totalCount = combinedText:match("(%d+)%s*/%s*(%d+)")
				if currentCount and totalCount then
					currentCount, totalCount = tonumber(currentCount), tonumber(totalCount)
					if currentCount and totalCount then
						isCollected = (currentCount >= totalCount)
						isPartiallyCollected = (currentCount > 0 and currentCount < totalCount)
						table.insert(debugInfo, string.format("Found diamond: %d/%d", currentCount, totalCount))
						if DOKI and DOKI.db and DOKI.db.debugMode then
							print(string.format("|cffff69b4DOKI|r     Diamond result: isCollected=%s, isPartiallyCollected=%s",
								tostring(isCollected), tostring(isPartiallyCollected)))
						end

						break
					end
				else
					isCollected = true
					table.insert(debugInfo, "Found diamond + 'Collected' (no numbers)")
					if DOKI and DOKI.db and DOKI.db.debugMode then
						print("|cffff69b4DOKI|r     Diamond result: COLLECTED (no numbers)")
					end

					break
				end
			end
		end

		-- Priority 5: Text fallback (only if no symbols found)
		if isCollected == nil and not combinedText:find("[❌✅💎]") then
			if combinedText:find("Not Collected") and not combinedText:find("Catalyst") then
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print("|cffff69b4DOKI|r     Found 'Not Collected' text")
				end

				isCollected = false
				table.insert(debugInfo, "Found 'Not Collected' text")
				break
			end

			if combinedText == "Collected" or combinedText:match("^Collected%s*$") then
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print("|cffff69b4DOKI|r     Found standalone 'Collected' text")
				end

				isCollected = true
				table.insert(debugInfo, "Found standalone 'Collected' text")
				break
			end
		end
	end

	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format(
			"|cffff69b4DOKI|r Final result: isCollected=%s, hasOtherSources=%s, isPartiallyCollected=%s",
			tostring(isCollected), tostring(hasOtherSources), tostring(isPartiallyCollected)))
	end

	return isCollected, hasOtherSources, isPartiallyCollected, debugInfo
end

-- KEEP: Your existing public function (unchanged)
function GetATTStatusAsync(itemID, itemLink, callback)
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r GetATTStatusAsync called")
		print(string.format("  itemID: %s", tostring(itemID)))
		print(string.format("  itemLink: %s", itemLink or "nil"))
		print(string.format("  callback: %s", callback and "function" or "nil"))
	end

	if not itemLink or not callback then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Invalid input")
		end

		if callback then callback(nil, nil, nil, "INVALID_INPUT") end

		return
	end

	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Adding to queue (current length: %d)", #attProcessingQueue))
	end

	table.insert(attProcessingQueue, { itemID, itemLink, callback })
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Queue length after insert: %d", #attProcessingQueue))
	end

	if not isProcessingATT then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Starting queue processing")
		end

		isProcessingATT = true
		ProcessNextATTInQueue()
	else
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Queue already processing, item added to wait")
		end
	end
end

-- KEEP: Your existing main integration function (unchanged)
function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- Check cache first
	local cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected = self:GetCachedATTStatus(itemID, itemLink)
	if cachedIsCollected == "NO_ATT_DATA" then
		return "NO_ATT_DATA", nil, nil
	elseif cachedIsCollected ~= nil then
		return cachedIsCollected, cachedHasOtherSources, cachedIsPartiallyCollected
	end

	-- Check if item data is loaded
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName or itemName == "" then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT: Item %d data not loaded, requesting...", itemID))
		end

		C_Item.RequestLoadItemDataByID(itemID)
		return nil, nil, nil
	end

	-- Check if itemLink is complete
	if itemLink and not self:IsItemLinkComplete(itemLink) then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT: ItemLink incomplete for ID %d", itemID))
		end

		local _, fallbackItemLink = C_Item.GetItemInfo(itemID)
		if fallbackItemLink and self:IsItemLinkComplete(fallbackItemLink) then
			itemLink = fallbackItemLink
		else
			return nil, nil, nil
		end
	end

	-- Use the "borrow GameTooltip" system
	GetATTStatusAsync(itemID, itemLink, function(isCollected, hasOtherSources, isPartiallyCollected, debugInfo)
		-- Cache the result
		if isCollected == nil and hasOtherSources == nil and isPartiallyCollected == nil then
			DOKI:SetCachedATTStatus(itemID, itemLink, nil, nil, nil)
		else
			DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, hasOtherSources, isPartiallyCollected)
		end

		-- Debug logging
		if DOKI.db and DOKI.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			local result = isCollected and "COLLECTED" or
					(isCollected == nil and "NO_ATT_DATA" or (isPartiallyCollected and "PARTIAL" or "NOT_COLLECTED"))
			print(string.format("|cffff69b4DOKI|r ATT: %s (ID: %d) -> %s", itemName, itemID, result))
			if debugInfo then
				for _, info in ipairs(debugInfo) do
					print(string.format("|cffff69b4DOKI|r   %s", info))
				end
			end
		end

		-- Trigger UI update - use full rescan to create indicators
		C_Timer.After(0.1, function()
			if DOKI and DOKI.db and DOKI.db.enabled then
				-- Check if any UI is visible before rescanning
				local anyUIVisible = false
				-- Check ElvUI
				if ElvUI and DOKI:IsElvUIBagVisible() then
					anyUIVisible = true
				end

				-- Check Blizzard bags
				if not anyUIVisible then
					if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
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
				end

				-- Check merchant
				if not anyUIVisible and MerchantFrame and MerchantFrame:IsVisible() then
					anyUIVisible = true
				end

				if anyUIVisible then
					-- Trigger full scan to create indicators for newly processed ATT items
					if DOKI.ScanBagFrames then
						local indicatorCount = DOKI:ScanBagFrames()
						if DOKI.db and DOKI.db.debugMode and indicatorCount > 0 then
							print(string.format("|cffff69b4DOKI|r ATT callback created %d indicators", indicatorCount))
						end
					end

					-- Also scan merchant if visible
					if MerchantFrame and MerchantFrame:IsVisible() and DOKI.ScanMerchantFrames then
						local merchantCount = DOKI:ScanMerchantFrames()
						if DOKI.db and DOKI.db.debugMode and merchantCount > 0 then
							print(string.format("|cffff69b4DOKI|r ATT callback created %d merchant indicators", merchantCount))
						end
					end
				end
			end
		end)
	end)
	return nil, nil, nil
end

-- KEEP: All your existing cache management functions (unchanged)
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
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
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

	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		local result = isCollected and "COLLECTED" or (isCollected == nil and "NO_ATT_DATA" or "NOT_COLLECTED")
		print(string.format("|cffff69b4DOKI|r ATT CACHED: %s (ID: %d) -> %s", itemName, itemID, result))
	end
end

-- Simple diagnostic
function DOKI:ShowATTQueueStatus()
	print(string.format("|cffff69b4DOKI|r ATT Queue Status (BORROW REAL GAMETOOLTIP):"))
	print(string.format("  Items in queue: %d", #attProcessingQueue))
	print(string.format("  Currently processing: %s", tostring(isProcessingATT)))
	if #attProcessingQueue > 0 then
		print("  Next few items in queue:")
		for i = 1, math.min(5, #attProcessingQueue) do
			local request = attProcessingQueue[i]
			local itemID = request[1]
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			print(string.format("    %d. %s (ID: %d)", i, itemName, itemID))
		end
	end

	print("")
	print("BORROW GAMETOOLTIP System Features:")
	print("  ✓ Uses real GameTooltip (ATT definitely hooks this)")
	print("  ✓ Temporarily borrows it without user interference")
	print("  ✓ Restores original owner after reading")
	print("  ✓ Frame delay for ATT hook timing")
end

-- Simple slash commands
SLASH_DOKIATTSTREAM1 = "/attstream"
SlashCmdList["DOKIATTSTREAM"] = function(msg)
	local command = strlower(strtrim(msg or ""))
	if command == "queue" then
		DOKI:ShowATTQueueStatus()
	else
		print("|cffff69b4DOKI|r ATT Commands:")
		print("/attstream queue - Show queue status")
		print("")
		print("FINAL FIX: Borrows real GameTooltip!")
	end
end
