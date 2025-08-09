-- DOKI Collections ATT - FINAL FIX: Borrow Real GameTooltip for ATT Hooks
local addonName, DOKI = ...
-- ===== NO MORE HIDDEN TOOLTIP - WE BORROW THE REAL ONE =====
-- Remove the hiddenTooltip variable and InitializeATTTooltip function
-- ATT only hooks the real GameTooltip now!
-- Keep your existing queue variables (unchanged)
local attProcessingQueue = {}
local isProcessingATT = false
local currentlyProcessingRequest = nil
-- Enhanced scanning state
DOKI.scanState = DOKI.scanState or {
	isScanInProgress = false,
	isLoginScan = false,
	scanStartTime = 0,
	totalItems = 0,
	processedItems = 0,
	progressFrame = nil,
	tooltipHooks = {},
}
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

			-- NEW: Add progress tracking after successful callback
			if DOKI.scanState and DOKI.scanState.isScanInProgress then
				DOKI.scanState.processedItems = (DOKI.scanState.processedItems or 0) + 1
				-- Update progress UI if available
				if DOKI.UpdateProgressFrame then
					DOKI:UpdateProgressFrame()
				end

				-- Check if scan is complete
				if DOKI.scanState.processedItems >= DOKI.scanState.totalItems then
					if DOKI.CompleteEnhancedATTScan then
						C_Timer.After(0.1, function()
							DOKI:CompleteEnhancedATTScan()
						end)
					end
				end
			end
		else
			-- Handle error
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cffff69b4DOKI|r ATT error during real tooltip read for item %d: %s",
					currentlyProcessingRequest.itemID, tostring(isCollected)))
			end

			currentlyProcessingRequest.callback(nil, nil, nil, { "ATT_ERROR_IN_PROCESSING", tostring(isCollected) })
			-- NEW: Add progress tracking for failed callbacks too
			if DOKI.scanState and DOKI.scanState.isScanInProgress then
				DOKI.scanState.processedItems = (DOKI.scanState.processedItems or 0) + 1
				-- Update progress UI if available
				if DOKI.UpdateProgressFrame then
					DOKI:UpdateProgressFrame()
				end

				-- Check if scan is complete
				if DOKI.scanState.processedItems >= DOKI.scanState.totalItems then
					if DOKI.CompleteEnhancedATTScan then
						C_Timer.After(0.1, function()
							DOKI:CompleteEnhancedATTScan()
						end)
					end
				end
			end
		end

		-- STEP 5: Process next item in queue
		currentlyProcessingRequest = nil
		C_Timer.After(0.05, ProcessNextATTInQueue)
	end)
end

-- KEEP: Your existing parsing function (unchanged - it's perfect!)
-- Helper function to remove ONLY WoW's invisible formatting codes.
-- This version is safer and will NOT remove visible Unicode symbols.
local function StripWoWFormatting(str)
	if not str then return "" end

	-- This pattern finds color codes |c(8 hex chars) and removes them.
	str = str:gsub("|c%x%x%x%x%x%x%x%x", "")
	-- This pattern finds texture codes |T(any characters until the next)|t and removes them.
	str = str:gsub("|T.-|t", "")
	-- This pattern finds hyperlink codes |H(any characters until the next)|h and removes the enclosing part.
	str = str:gsub("|H(.-)|h(.-)|h", "%2")
	-- This pattern removes the closing color tag |r.
	str = str:gsub("|r", "")
	return str
end

-- FINAL, ROBUST PARSER with corrected cleaning and symbol detection
function ParseATTTooltipLines(tooltipLines, itemID, itemLink)
	local hasOtherSources = false -- Kept for API consistency
	local debugInfo = {}
	-- Default to "collected" if ATT provides no usable data, as per your request.
	local finalResult = true
	local finalPartial = false
	if #tooltipLines > 0 then
		local lineData = tooltipLines[1]
		local rightText = lineData.right or ""
		table.insert(debugInfo, string.format("Line 1 Raw: R='%s'", rightText))
		-- Clean the string to remove only invisible formatting.
		local cleanText = StripWoWFormatting(rightText)
		table.insert(debugInfo, string.format("Line 1 Cleaned: '%s'", cleanText))
		-- === STEP 1: Check for the HIGHEST priority pattern: the "uncollected" symbol ===
		-- This must be checked first and is definitive.
		if cleanText:find("❌") or cleanText:find("✗") or cleanText:find("✕") or cleanText:find("Not Collected") then
			finalResult = false
			finalPartial = false
			table.insert(debugInfo, "Found Uncollected symbol/text. Result: Not Collected.")
			return finalResult, hasOtherSources, finalPartial, debugInfo -- Return immediately
		end

		-- === STEP 2: Check for any other known ATT symbols/keywords ===
		-- This list now correctly includes the currency symbol and Reagent/Currency keywords.
		local hasATTSymbol = cleanText:find("✅") or cleanText:find("✓") or cleanText:find("☑") or
				cleanText:find("💎") or cleanText:find("♦") or cleanText:find("🪙") or
				cleanText:find("Catalyst") or cleanText:find("Reagent") or cleanText:find("Currency")
		if hasATTSymbol then
			table.insert(debugInfo, "Found a positive ATT symbol/keyword.")
			-- === STEP 3: If a symbol was found, look for a fraction ===
			local current, total = cleanText:match("(%d+)%s*/%s*(%d+)")
			if current and total then
				current, total = tonumber(current), tonumber(total)
				table.insert(debugInfo, string.format("Found fraction %d/%d", current, total))
				if current >= total then
					finalResult = true
					finalPartial = false
				elseif current > 0 then
					finalResult = false
					finalPartial = true
				else
					finalResult = false
					finalPartial = false
				end
			else
				-- A positive symbol was found, but NO fraction.
				finalResult = true
				finalPartial = false
				table.insert(debugInfo, "Positive symbol found, no fraction. Result: Collected.")
			end
		else
			-- No ATT symbols of any kind were found.
			finalResult = true
			finalPartial = false
			table.insert(debugInfo, "No ATT symbols found at all. Defaulting to Collected.")
		end
	else
		-- The tooltip was empty.
		finalResult = true
		finalPartial = false
		table.insert(debugInfo, "No tooltip lines found. Defaulting to Collected.")
	end

	return finalResult, hasOtherSources, finalPartial, debugInfo
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

		-- NEW: Create indicators directly instead of triggering full rescan
		C_Timer.After(0.05, function() -- Small delay to ensure button state is stable
			if DOKI and DOKI.db and DOKI.db.enabled then
				local indicatorsCreated = DOKI:CreateATTIndicatorDirectly(itemID, itemLink, isCollected, hasOtherSources,
					isPartiallyCollected)
				if DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r ATT callback: %d indicators created directly", indicatorsCreated))
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
-- Add this new function to find the button for a specific item
function DOKI:FindButtonForItem(targetItemID, targetItemLink)
	local foundButtons = {}
	-- Search ElvUI bags
	if ElvUI and self:IsElvUIBagVisible() then
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID == targetItemID then
						-- Check if itemLink matches for battlepets
						if not targetItemLink or not string.find(targetItemLink, "battlepet:") or
								itemInfo.hyperlink == targetItemLink then
							local possibleNames = {
								string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
								string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
								string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
							}
							for _, buttonName in ipairs(possibleNames) do
								local button = _G[buttonName]
								if button and button:IsVisible() then
									table.insert(foundButtons, button)
									break
								end
							end
						end
					end
				end
			end
		end
	end

	-- Search Blizzard combined bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID == targetItemID then
						if not targetItemLink or not string.find(targetItemLink, "battlepet:") or
								itemInfo.hyperlink == targetItemLink then
							-- Find button in combined bags
							if ContainerFrameCombinedBags.EnumerateValidItems then
								for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
									if itemButton and itemButton:IsVisible() then
										local buttonBagID, buttonSlotID = nil, nil
										if itemButton.GetBagID and itemButton.GetID then
											local bagIDSuccess, retrievedBagID = pcall(itemButton.GetBagID, itemButton)
											local slotIDSuccess, retrievedSlotID = pcall(itemButton.GetID, itemButton)
											if bagIDSuccess and slotIDSuccess then
												buttonBagID, buttonSlotID = retrievedBagID, retrievedSlotID
											end
										end

										if buttonBagID == bagID and buttonSlotID == slotID then
											table.insert(foundButtons, itemButton)
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

	-- Search individual container frames
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID == targetItemID then
						if not targetItemLink or not string.find(targetItemLink, "battlepet:") or
								itemInfo.hyperlink == targetItemLink then
							local possibleNames = {
								string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
								string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
							}
							for _, buttonName in ipairs(possibleNames) do
								local button = _G[buttonName]
								if button and button:IsVisible() then
									table.insert(foundButtons, button)
									break
								end
							end
						end
					end
				end
			end
		end
	end

	-- Search merchant frames
	if MerchantFrame and MerchantFrame:IsVisible() then
		for i = 1, 12 do
			local possibleButtonNames = {
				string.format("MerchantItem%dItemButton", i),
				string.format("MerchantItem%d", i),
			}
			for _, buttonName in ipairs(possibleButtonNames) do
				local button = _G[buttonName]
				if button and button:IsVisible() then
					local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
					if itemID == targetItemID then
						if not targetItemLink or itemLink == targetItemLink then
							table.insert(foundButtons, button)
						end
					end

					break
				end
			end
		end
	end

	return foundButtons
end

-- Replace the callback in GetATTStatusAsync with this version:
-- This should go in CollectionsATT.lua, replacing the existing callback section
function DOKI:CreateATTIndicatorDirectly(itemID, itemLink, isCollected, hasOtherSources, isPartiallyCollected)
	-- Don't create indicator if ATT has no data for this item (isCollected = nil means no ATT data)
	if isCollected == nil then
		if self.db and self.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			print(string.format("|cffff69b4DOKI|r ATT: %s has no ATT data, no indicator needed", itemName))
		end

		return 0
	end

	-- Don't create indicator if item is collected and not partial
	if isCollected and not isPartiallyCollected then
		if self.db and self.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			print(string.format("|cffff69b4DOKI|r ATT: %s is collected, no indicator needed", itemName))
		end

		return 0
	end

	-- Find all buttons for this item
	local buttons = self:FindButtonForItem(itemID, itemLink)
	local indicatorsCreated = 0
	for _, button in ipairs(buttons) do
		local itemData = {
			itemID = itemID,
			itemLink = itemLink,
			isCollected = isCollected,
			hasOtherTransmogSources = hasOtherSources,
			isPartiallyCollected = isPartiallyCollected,
			frameType = "att_callback",
		}
		if self:AddButtonIndicator(button, itemData) then
			indicatorsCreated = indicatorsCreated + 1
		end
	end

	if self.db and self.db.debugMode and indicatorsCreated > 0 then
		local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
		print(string.format("|cffff69b4DOKI|r ATT: Created %d indicators for %s", indicatorsCreated, itemName))
	end

	return indicatorsCreated
end
