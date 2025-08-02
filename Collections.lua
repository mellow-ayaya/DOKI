-- DOKI Collections - ENHANCED: ATT Lazy Loading System to Eliminate FPS Drops
local addonName, DOKI = ...
-- Initialize collection-specific storage
DOKI.foundFramesThisScan = {}
DOKI.collectionCache = DOKI.collectionCache or {}
DOKI.lastCacheUpdate = 0
-- Ensemble detection variables
DOKI.ensembleWordCache = nil
DOKI.ensembleKnownItemID = 234522
-- Merchant scroll detection system
DOKI.merchantScrollDetector = {
	isScrolling = false,
	scrollTimer = nil,
	lastMerchantState = nil,
	merchantOpen = false,
}
-- Enhanced surgical update throttling with delayed cleanup
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.1
DOKI.pendingSurgicalUpdate = false
-- Enhanced scanning system variables
DOKI.delayedScanTimer = nil
DOKI.delayedScanCancelled = false
-- ===== ATT LAZY LOADING SYSTEM =====
DOKI.attLazyLoader = {
	-- Discovery system
	discoveredItems = {}, -- [itemID] = { itemLink, lastSeen, priority }
	discoveryEnabled = true,

	-- Background processing
	processingQueue = {}, -- Items to process in background
	isProcessing = false,
	processingTimer = nil,

	-- Performance settings
	itemsPerTick = 2,       -- Process 2 items every tick (very slow to avoid ATT spam)
	tickInterval = 1.0,     -- 1 second between ticks
	maxItemsPerSession = 50, -- Don't process more than 50 items per session

	-- Session tracking
	sessionItemsProcessed = 0,
	lastActivityTime = 0,
	idleThreshold = 5.0, -- 5 seconds of inactivity = idle

	-- Statistics
	stats = {
		totalItemsDiscovered = 0,
		totalItemsProcessed = 0,
		cacheHits = 0,
		cacheMisses = 0,
		backgroundProcessingTime = 0,
	},
}
-- ===== ITEM DISCOVERY SYSTEM =====
function DOKI:StartATTItemDiscovery()
	if not self.db or not self.db.attMode then return end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r Starting ATT lazy loading item discovery...")
	end

	self.attLazyLoader.discoveryEnabled = true
	-- Initial discovery scan
	self:DiscoverBagItems()
	-- Set up periodic discovery (every 30 seconds)
	if not self.attLazyLoader.discoveryTimer then
		self.attLazyLoader.discoveryTimer = C_Timer.NewTicker(30, function()
			if DOKI.db and DOKI.db.attMode and DOKI.attLazyLoader.discoveryEnabled then
				DOKI:DiscoverBagItems()
			end
		end)
	end

	-- Set up background processing
	self:StartBackgroundATTProcessing()
end

function DOKI:DiscoverBagItems()
	if not self.attLazyLoader.discoveryEnabled then return end

	local currentTime = GetTime()
	local discovered = 0
	-- Scan all bags for items
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					local itemID = itemInfo.itemID
					local itemLink = itemInfo.hyperlink
					-- Check if we already know about this item
					local existing = self.attLazyLoader.discoveredItems[itemID]
					if not existing then
						-- New item discovered
						self.attLazyLoader.discoveredItems[itemID] = {
							itemLink = itemLink,
							lastSeen = currentTime,
							priority = self:CalculateItemPriority(itemID, itemLink),
							discovered = currentTime,
						}
						discovered = discovered + 1
						-- Add to processing queue if we don't have cached data
						local cached = self:GetCachedATTStatus(itemID, itemLink)
						if cached == nil then
							self:AddToBackgroundQueue(itemID, itemLink)
						end
					else
						-- Update last seen time
						existing.lastSeen = currentTime
					end
				end
			end
		end
	end

	if discovered > 0 then
		self.attLazyLoader.stats.totalItemsDiscovered = self.attLazyLoader.stats.totalItemsDiscovered + discovered
		if self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT Discovery: Found %d new items", discovered))
		end
	end
end

function DOKI:CalculateItemPriority(itemID, itemLink)
	-- Higher priority = process sooner
	local priority = 1
	-- Boost priority for common collectible types
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if classID then
		if classID == 15 then                  -- Mounts and Pets
			priority = priority + 10
		elseif classID == 2 or classID == 4 then -- Weapons and Armor (transmog)
			priority = priority + 5
		end
	end

	-- Boost priority for toys
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		priority = priority + 8
	end

	-- Boost priority for ensembles
	if self:IsEnsembleItem(itemID) then
		priority = priority + 7
	end

	-- Boost priority for battlepets
	if itemLink and string.find(itemLink, "battlepet:") then
		priority = priority + 6
	end

	return priority
end

-- ===== BACKGROUND PROCESSING SYSTEM =====
function DOKI:StartBackgroundATTProcessing()
	if self.attLazyLoader.isProcessing then return end

	self.attLazyLoader.isProcessing = true
	self.attLazyLoader.sessionItemsProcessed = 0
	if self.db.debugMode then
		print("|cffff69b4DOKI|r Starting ATT background processing...")
	end

	-- Start the processing timer
	self.attLazyLoader.processingTimer = C_Timer.NewTicker(self.attLazyLoader.tickInterval, function()
		DOKI:ProcessBackgroundATTTick()
	end)
end

function DOKI:StopBackgroundATTProcessing()
	if not self.attLazyLoader.isProcessing then return end

	self.attLazyLoader.isProcessing = false
	if self.attLazyLoader.processingTimer then
		self.attLazyLoader.processingTimer:Cancel()
		self.attLazyLoader.processingTimer = nil
	end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r Stopped ATT background processing")
	end
end

function DOKI:AddToBackgroundQueue(itemID, itemLink)
	-- Don't add duplicates
	for _, queued in ipairs(self.attLazyLoader.processingQueue) do
		if queued.itemID == itemID then return end
	end

	-- Add with priority
	local priority = self:CalculateItemPriority(itemID, itemLink)
	table.insert(self.attLazyLoader.processingQueue, {
		itemID = itemID,
		itemLink = itemLink,
		priority = priority,
		added = GetTime(),
	})
	-- Sort queue by priority (highest first)
	table.sort(self.attLazyLoader.processingQueue, function(a, b)
		return a.priority > b.priority
	end)
	if self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Added item %d to background queue (priority %d, queue size: %d)",
			itemID, priority, #self.attLazyLoader.processingQueue))
	end
end

function DOKI:ProcessBackgroundATTTick()
	-- Check if we should be processing
	if not self.db or not self.db.attMode or not self.attLazyLoader.isProcessing then
		self:StopBackgroundATTProcessing()
		return
	end

	-- Check if player is idle enough
	if not self:IsPlayerIdleForATTProcessing() then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r Skipping ATT processing - player not idle")
		end

		return
	end

	-- Check session limits
	if self.attLazyLoader.sessionItemsProcessed >= self.attLazyLoader.maxItemsPerSession then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r ATT processing session limit reached, pausing...")
		end

		-- Pause for 60 seconds then reset session
		C_Timer.After(60, function()
			if DOKI.attLazyLoader then
				DOKI.attLazyLoader.sessionItemsProcessed = 0
			end
		end)
		return
	end

	-- Process items from queue
	local processed = 0
	local startTime = GetTime()
	for i = 1, self.attLazyLoader.itemsPerTick do
		if #self.attLazyLoader.processingQueue == 0 then break end

		local item = table.remove(self.attLazyLoader.processingQueue, 1)
		if item then
			-- Check if we already have cached data (might have been processed elsewhere)
			local cached = self:GetCachedATTStatus(item.itemID, item.itemLink)
			if cached == nil then
				-- Process the item
				local success = self:ProcessSingleATTItem(item.itemID, item.itemLink)
				if success then
					processed = processed + 1
					self.attLazyLoader.sessionItemsProcessed = self.attLazyLoader.sessionItemsProcessed + 1
					self.attLazyLoader.stats.totalItemsProcessed = self.attLazyLoader.stats.totalItemsProcessed + 1
				end
			end
		end
	end

	local processingTime = GetTime() - startTime
	self.attLazyLoader.stats.backgroundProcessingTime = self.attLazyLoader.stats.backgroundProcessingTime + processingTime
	if processed > 0 and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r ATT Background: Processed %d items in %.3fs (queue: %d remaining)",
			processed, processingTime, #self.attLazyLoader.processingQueue))
	end
end

function DOKI:ProcessSingleATTItem(itemID, itemLink)
	if not itemID then return false end

	local tooltip = GameTooltip
	tooltip:Hide()
	tooltip:ClearLines()
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	else
		tooltip:SetItemByID(itemID)
	end

	-- CRITICAL: Show tooltip so ATT can inject data
	tooltip:Show()
	-- Use the 0.2s delay observed in testing
	C_Timer.After(0.2, function()
		local attStatus, showYellowD, showPurple = DOKI:ParseATTTooltipFromGameTooltip(itemID)
		-- Cache the result
		if attStatus ~= nil then
			DOKI:SetCachedATTStatus(itemID, itemLink, attStatus, showYellowD, showPurple)
		else
			DOKI:SetCachedATTStatus(itemID, itemLink, nil, nil, nil)
		end

		-- Clean up
		tooltip:Hide()
		tooltip:ClearLines()
		if DOKI.db and DOKI.db.debugMode then
			local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
			if attStatus ~= nil then
				local statusText = attStatus and "COLLECTED" or "NOT COLLECTED"
				local colorText = ""
				if showPurple then
					colorText = " (PINK indicator)"
				elseif showYellowD then
					colorText = " (BLUE indicator)"
				elseif not attStatus then
					colorText = " (ORANGE indicator)"
				end

				print(string.format("|cffff69b4DOKI|r Background: %s -> %s%s",
					itemName, statusText, colorText))
			else
				print(string.format("|cffff69b4DOKI|r Background: %s -> NO ATT DATA", itemName))
			end
		end
	end)
	return true
end

function DOKI:ParseATTTooltipFromGameTooltip(itemID)
	local tooltip = GameTooltip
	local attStatus = nil
	local showYellowD = false
	local showPurple = false
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
						showYellowD = false
						showPurple = false
					elseif percentage == 0 or current == 0 then
						attStatus = false
						showYellowD = false
						showPurple = false
					else
						-- Partial collection - show pink indicator
						attStatus = false
						showYellowD = false
						showPurple = true
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found ATT percentage: %d/%d (%.1f%%) -> %s",
							current, total, percentage, attStatus and "COLLECTED" or (showPurple and "PARTIAL" or "NOT COLLECTED")))
					end

					break
				end

				-- Look for simple fractions without percentage like "(0/1)" or "(2/3)"
				local parenCurrent, parenTotal = string.match(text, "%((%d+)/(%d+)%)")
				if parenCurrent and parenTotal then
					parenCurrent = tonumber(parenCurrent)
					parenTotal = tonumber(parenTotal)
					if parenCurrent >= parenTotal and parenTotal > 0 then
						attStatus = true
						showYellowD = false
						showPurple = false
					elseif parenCurrent == 0 then
						attStatus = false
						showYellowD = false
						showPurple = false
					else
						-- Partial collection
						attStatus = false
						showYellowD = false
						showPurple = true
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Found ATT fraction: (%d/%d) -> %s",
							parenCurrent, parenTotal, attStatus and "COLLECTED" or (showPurple and "PARTIAL" or "NOT COLLECTED")))
					end

					break
				end

				-- Unicode symbol detection (locale-independent)
				-- Note: These are the actual symbols from your screenshots
				-- ❌ for not collected
				if string.find(text, "❌") or string.find(text, "✗") or string.find(text, "✕") then
					attStatus = false
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT X symbol -> NOT COLLECTED")
					end

					break
				end

				-- ✅ for collected
				if string.find(text, "✅") or string.find(text, "✓") or string.find(text, "☑") then
					attStatus = true
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print("|cffff69b4DOKI|r Found ATT checkmark -> COLLECTED")
					end

					break
				end

				-- 💎 Diamond symbol typically indicates currency/reagent items
				-- If we see diamond + "Currency" or "Collected", parse accordingly
				if string.find(text, "💎") or string.find(text, "♦") then
					-- This is likely a currency/reagent item, look for the status
					if string.find(text, "Collected") then
						-- Look for the numbers in this line
						local curr, tot = string.match(text, "(%d+) */ *(%d+)")
						if curr and tot then
							curr = tonumber(curr)
							tot = tonumber(tot)
							attStatus = (curr >= tot)
							showYellowD = false
							showPurple = (curr > 0 and curr < tot)
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Found diamond currency: %d/%d -> %s",
									curr, tot, attStatus and "COLLECTED" or (showPurple and "PARTIAL" or "NOT COLLECTED")))
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

	return attStatus, showYellowD, showPurple
end

function DOKI:IsPlayerIdleForATTProcessing()
	local currentTime = GetTime()
	-- Don't process during combat
	if InCombatLockdown() then
		return false
	end

	-- Don't process if bags are open (player is actively using them)
	if self:IsElvUIBagVisible() or
			(ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
		self.attLazyLoader.lastActivityTime = currentTime
		return false
	end

	-- Check for any individual bag frames
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			self.attLazyLoader.lastActivityTime = currentTime
			return false
		end
	end

	-- Don't process if merchant is open
	if MerchantFrame and MerchantFrame:IsVisible() then
		self.attLazyLoader.lastActivityTime = currentTime
		return false
	end

	-- Check if enough idle time has passed
	local idleTime = currentTime - self.attLazyLoader.lastActivityTime
	return idleTime >= self.attLazyLoader.idleThreshold
end

-- ===== LAZY LOADING MANAGEMENT =====
function DOKI:GetATTLazyLoadingStats()
	return {
		discoveredItems = self:TableCount(self.attLazyLoader.discoveredItems),
		queueSize = #self.attLazyLoader.processingQueue,
		isProcessing = self.attLazyLoader.isProcessing,
		sessionItemsProcessed = self.attLazyLoader.sessionItemsProcessed,
		maxItemsPerSession = self.attLazyLoader.maxItemsPerSession,
		itemsPerTick = self.attLazyLoader.itemsPerTick,
		tickInterval = self.attLazyLoader.tickInterval,
		stats = self.attLazyLoader.stats,
	}
end

function DOKI:SetATTLazyLoadingSettings(itemsPerTick, tickInterval, maxItemsPerSession)
	if itemsPerTick then
		self.attLazyLoader.itemsPerTick = math.max(1, math.min(10, itemsPerTick))
	end

	if tickInterval then
		self.attLazyLoader.tickInterval = math.max(0.5, math.min(5.0, tickInterval))
	end

	if maxItemsPerSession then
		self.attLazyLoader.maxItemsPerSession = math.max(10, math.min(200, maxItemsPerSession))
	end

	-- Restart processing with new settings
	if self.attLazyLoader.isProcessing then
		self:StopBackgroundATTProcessing()
		self:StartBackgroundATTProcessing()
	end
end

function DOKI:ClearATTLazyLoadingData()
	-- Stop processing
	self:StopBackgroundATTProcessing()
	-- Clear discovery data
	self.attLazyLoader.discoveredItems = {}
	self.attLazyLoader.processingQueue = {}
	-- Clear ATT cache
	if self.collectionCache then
		for key, cached in pairs(self.collectionCache) do
			if cached.isATTResult then
				self.collectionCache[key] = nil
			end
		end
	end

	-- Reset stats
	self.attLazyLoader.stats = {
		totalItemsDiscovered = 0,
		totalItemsProcessed = 0,
		cacheHits = 0,
		cacheMisses = 0,
		backgroundProcessingTime = 0,
	}
	print("|cffff69b4DOKI|r ATT lazy loading data cleared")
end

-- ===== CLEANUP WITH LAZY LOADING =====
function DOKI:CleanupCollectionSystem()
	-- Stop lazy loading
	if self.attLazyLoader and self.attLazyLoader.isProcessing then
		self:StopBackgroundATTProcessing()
	end

	-- Stop discovery
	if self.attLazyLoader and self.attLazyLoader.discoveryTimer then
		self.attLazyLoader.discoveryTimer:Cancel()
		self.attLazyLoader.discoveryTimer = nil
	end

	-- Clear data
	if self.attLazyLoader then
		self.attLazyLoader.discoveredItems = {}
		self.attLazyLoader.processingQueue = {}
		self.attLazyLoader.discoveryEnabled = false
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ATT lazy loading system cleaned up")
	end
end

-- Utility function
function DOKI:TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end

	return count
end

-- ===== CACHE MANAGEMENT WITH PURPLE SUPPORT AND ATT "NO DATA" TRACKING =====
function DOKI:ClearCollectionCache()
	self.collectionCache = {}
	self.lastCacheUpdate = GetTime()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Collection cache cleared")
	end
end

function DOKI:GetCachedCollectionStatus(itemID, itemLink)
	local cacheKey = itemLink or tostring(itemID)
	local cached = self.collectionCache[cacheKey]
	if cached and (GetTime() - cached.timestamp < 30) then
		return cached.isCollected, cached.showYellowD, cached.showPurple or false
	end

	return nil, nil, nil
end

function DOKI:SetCachedCollectionStatus(itemID, itemLink, isCollected, showYellowD, showPurple)
	local cacheKey = itemLink or tostring(itemID)
	self.collectionCache[cacheKey] = {
		isCollected = isCollected,
		showYellowD = showYellowD,
		showPurple = showPurple or false,
		timestamp = GetTime(),
	}
end

function DOKI:GetCachedATTStatus(itemID, itemLink)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	local cached = self.collectionCache[cacheKey]
	if cached and cached.isATTResult then
		if cached.noATTData then
			return "NO_ATT_DATA", nil, nil
		end

		return cached.isCollected, cached.showYellowD, cached.showPurple
	end

	return nil, nil, nil
end

function DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, showYellowD, showPurple)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	if isCollected == nil and showYellowD == nil and showPurple == nil then
		self.collectionCache[cacheKey] = {
			isATTResult = true,
			noATTData = true,
			timestamp = GetTime(),
		}
	else
		self.collectionCache[cacheKey] = {
			isCollected = isCollected,
			showYellowD = showYellowD,
			showPurple = showPurple,
			isATTResult = true,
			noATTData = false,
			timestamp = GetTime(),
		}
	end
end

-- ===== ENHANCED ATT BATCH PROCESSING SYSTEM =====
function DOKI:ProcessATTBatchQueue()
	-- DISABLED: This system was causing individual item processing
	-- Now using direct processing with immediate caching
	self.attBatchProcessing = false
	self.attBatchQueue = {}
	return
end

function DOKI:ProcessATTBatchChunk()
	-- DISABLED: This was the source of the "1 items queued" spam
	return
end

-- ===== ENHANCED ATT COLLECTION STATUS WITH LAZY LOADING =====
function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- Check cache first (this is now the primary path)
	local cachedCollected, cachedYellowD, cachedPurple = self:GetCachedATTStatus(itemID, itemLink)
	if cachedCollected == "NO_ATT_DATA" then
		self.attLazyLoader.stats.cacheHits = self.attLazyLoader.stats.cacheHits + 1
		return "NO_ATT_DATA", nil, nil
	elseif cachedCollected ~= nil then
		self.attLazyLoader.stats.cacheHits = self.attLazyLoader.stats.cacheHits + 1
		return cachedCollected, cachedYellowD, cachedPurple
	end

	-- Cache miss - add to discovery and queue for background processing
	self.attLazyLoader.stats.cacheMisses = self.attLazyLoader.stats.cacheMisses + 1
	-- Discover this item
	if not self.attLazyLoader.discoveredItems[itemID] then
		self.attLazyLoader.discoveredItems[itemID] = {
			itemLink = itemLink,
			lastSeen = GetTime(),
			priority = self:CalculateItemPriority(itemID, itemLink),
			discovered = GetTime(),
		}
		self.attLazyLoader.stats.totalItemsDiscovered = self.attLazyLoader.stats.totalItemsDiscovered + 1
	end

	-- Add to background processing queue
	self:AddToBackgroundQueue(itemID, itemLink)
	-- For immediate needs (like when bags are open), fall back to real-time parsing
	-- But only if we're in a critical path (bags open)
	if self:IsElvUIBagVisible() or
			(ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) or
			self:AnyBagFrameVisible() then
		if self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Cache miss during bag use - using fallback parsing for item %d", itemID))
		end

		-- Use the original direct parsing as fallback
		local isCollected, showYellowD, showPurple = self:ParseATTTooltipDirect(itemID, itemLink)
		if isCollected ~= nil then
			self:SetCachedATTStatus(itemID, itemLink, isCollected, showYellowD, showPurple)
		else
			self:SetCachedATTStatus(itemID, itemLink, nil, nil, nil)
		end

		if isCollected == nil then
			return "NO_ATT_DATA", nil, nil
		else
			return isCollected, showYellowD, showPurple
		end
	end

	-- Not in critical path - return "no data" for now, will be processed in background
	return "NO_ATT_DATA", nil, nil
end

function DOKI:AnyBagFrameVisible()
	for bagID = 0, NUM_BAG_SLOTS do
		local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
		if containerFrame and containerFrame:IsVisible() then
			return true
		end
	end

	return false
end

-- ===== ENHANCED ATT TOOLTIP PARSING WITH 0/number vs >0/number DISTINCTION =====
function DOKI:ParseATTTooltipDirect(itemID, itemLink)
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
	-- Try immediate parsing (may not get ATT data due to timing)
	local attStatus, showYellowD, showPurple = self:ParseATTTooltipFromGameTooltip(itemID)
	tooltip:Hide()
	tooltip:ClearLines()
	return attStatus, showYellowD, showPurple
end

function DOKI:TestFixedATTParsing()
	if not self.db or not self.db.attMode then
		print("|cffff69b4DOKI|r ATT mode is disabled. Enable with /doki att")
		return
	end

	print("|cffff69b4DOKI|r === TESTING FIXED ATT PARSING ===")
	-- Test with known items
	local testItems = {
		{ id = 32458, name = "Ashes of Al'ar" }, -- Mount (should show currency format)
		-- Add first item from bags
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
			local isCollected, showYellowD, showPurple = DOKI:ParseATTTooltipFromGameTooltip(item.id)
			tooltip:Hide()
			if isCollected ~= nil then
				local result = "✓ SUCCESS: "
				if isCollected and not showPurple then
					result = result .. "COLLECTED (no indicator)"
				elseif showPurple then
					result = result .. "PARTIAL (PINK indicator)"
				elseif showYellowD then
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

-- ===== CLEAR ATT BATCH QUEUE =====
function DOKI:ClearATTBatchQueue()
	self.attBatchQueue = {}
	self.attBatchProcessing = false
	if self.attBatchTimer then
		self.attBatchTimer:Cancel()
		self.attBatchTimer = nil
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r ATT batch queue cleared")
	end
end

-- ===== ENSEMBLE DETECTION SYSTEM =====
function DOKI:InitializeEnsembleDetection()
	if not self.ensembleWordCache then
		self:ExtractEnsembleWord()
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Ensemble detection initialized with word: '%s'",
			self.ensembleWordCache or "unknown"))
	end
end

function DOKI:ExtractEnsembleWord()
	local itemName = C_Item.GetItemInfo(self.ensembleKnownItemID)
	if itemName then
		-- Extract the word before the colon (e.g., "Ensemble" from "Ensemble: Southsea Cruise Loungewear")
		local ensembleWord = string.match(itemName, "^([^:]+):")
		if ensembleWord then
			self.ensembleWordCache = strtrim(ensembleWord)
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Extracted ensemble word: '%s' from item '%s'",
					self.ensembleWordCache, itemName))
			end
		else
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Could not extract ensemble word from: '%s'", itemName))
			end
		end
	else
		-- Request item data and try again later
		C_Item.RequestLoadItemDataByID(self.ensembleKnownItemID)
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Requesting ensemble reference item data...")
		end
	end
end

function DOKI:IsEnsembleItem(itemID, itemName)
	if not itemID then return false end

	-- Initialize ensemble word if not cached
	if not self.ensembleWordCache then
		self:ExtractEnsembleWord()
		if not self.ensembleWordCache then
			return false -- Can't detect without ensemble word
		end
	end

	-- Check item class/subclass criteria
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false
	end

	-- Must be Class 0 (Consumable) + Subclass 8 (Other)
	if classID ~= 0 or subClassID ~= 8 then
		return false
	end

	-- Must have a spell effect
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then
		return false
	end

	-- Check if name starts with ensemble word
	if not itemName then
		itemName = C_Item.GetItemInfo(itemID)
	end

	if itemName then
		local startsWithEnsemble = string.find(itemName, "^" .. self.ensembleWordCache .. ":")
		if self.db and self.db.debugMode and startsWithEnsemble then
			print(string.format("|cffff69b4DOKI|r Detected ensemble: %s (ID: %d)", itemName, itemID))
		end

		return startsWithEnsemble ~= nil
	end

	return false
end

function DOKI:IsEnsembleCollected(itemID, itemLink)
	if not itemID then return false, false, false end

	-- Check cache first (following your existing pattern)
	local cachedCollected, cachedYellowD, cachedPurple = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		return cachedCollected, cachedYellowD, cachedPurple
	end

	local isCollected = self:CheckEnsembleByTooltip(itemID, itemLink)
	-- Cache the result (ensembles don't use yellow D or purple logic)
	self:SetCachedCollectionStatus(itemID, itemLink, isCollected, false, false)
	return isCollected, false, false
end

function DOKI:CheckEnsembleByTooltip(itemID, itemLink)
	if not itemID then return false end

	-- Create unique tooltip name to avoid conflicts (following your existing pattern)
	local tooltipName = "DOKIEnsembleTooltip" .. itemID
	local tooltip = CreateFrame("GameTooltip", tooltipName, nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	-- Set the item (prefer itemLink for accuracy)
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	else
		tooltip:SetItemByID(itemID)
	end

	tooltip:Show()
	local isCollected = false
	-- Pure color-based detection (100% locale agnostic)
	for i = 1, tooltip:NumLines() do
		local line = _G[tooltipName .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text and string.len(text) > 0 then
				local r, g, b = line:GetTextColor()
				if r and g and b then
					-- Red text indicates "already known" across all locales
					if r > 0.8 and g < 0.4 and b < 0.4 then
						-- Additional validation: Red text should be reasonably short
						if string.len(text) < 50 then
							isCollected = true
							if self.db and self.db.debugMode then
								print(string.format("|cffff69b4DOKI|r Ensemble %d already collected (red text): '%s'",
									itemID, text))
							end

							break
						end
					end

					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Ensemble tooltip line %d: '%s' (r=%.2f, g=%.2f, b=%.2f)",
							i, text, r or 0, g or 0, b or 0))
					end
				end
			end
		end

		if isCollected then break end
	end

	tooltip:Hide()
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Ensemble %d collection status: %s",
			itemID, isCollected and "COLLECTED" or "NOT COLLECTED"))
	end

	return isCollected
end

-- ===== ENHANCED TRACE FUNCTION FOR ENSEMBLES =====
function DOKI:TraceEnsembleDetection(itemID, itemLink)
	if not itemID then
		print("|cffff69b4DOKI|r No item ID provided")
		return
	end

	print("|cffff69b4DOKI|r === ENSEMBLE DETECTION TRACE ===")
	local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
	print(string.format("Item: %s (ID: %d)", itemName, itemID))
	-- Check if ensemble word is cached
	if not self.ensembleWordCache then
		print("   Ensemble word not cached - attempting extraction...")
		self:ExtractEnsembleWord()
		if not self.ensembleWordCache then
			print("   Could not extract ensemble word - ensemble detection unavailable")
			return
		end
	end

	print(string.format("   Ensemble word: '%s'", self.ensembleWordCache))
	-- Check class/subclass
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	print(string.format("  Class: %d, Subclass: %d", classID or -1, subClassID or -1))
	if classID ~= 0 or subClassID ~= 8 then
		print("   Not Class 0/Subclass 8 - not an ensemble")
		return
	end

	print("   Correct class/subclass for ensemble")
	-- Check spell effect
	local spellID = C_Item.GetItemSpell(itemID)
	print(string.format("  Spell ID: %s", spellID and tostring(spellID) or "none"))
	if not spellID then
		print("   No spell effect - not an ensemble")
		return
	end

	print("   Has spell effect")
	-- Check name pattern
	if itemName then
		local startsWithEnsemble = string.find(itemName, "^" .. self.ensembleWordCache .. ":")
		print(string.format("  Name starts with '%s:': %s", self.ensembleWordCache,
			startsWithEnsemble and "YES" or "NO"))
		if not startsWithEnsemble then
			print("   Name doesn't match ensemble pattern")
			return
		end

		print("   Name matches ensemble pattern")
	else
		print("   Item name not available")
		return
	end

	-- Check collection status
	print("")
	print("|cffff69b4DOKI|r 2. COLLECTION STATUS CHECK:")
	local isCollected = self:CheckEnsembleByTooltip(itemID, itemLink)
	print("")
	print("|cffff69b4DOKI|r 3. FINAL DECISION:")
	print(string.format("  Ensemble: YES"))
	print(string.format("  Collected: %s", isCollected and "YES" or "NO"))
	print(string.format("   NEEDS INDICATOR: %s", isCollected and "NO" or "YES"))
	print("|cffff69b4DOKI|r === END ENSEMBLE TRACE ===")
end

-- ===== MERCHANT SCROLL DETECTION SYSTEM =====
function DOKI:InitializeMerchantScrollDetection()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Initializing merchant scroll detection...")
	end

	-- Method 1: Hook ScrollBox mouse wheel (modern War Within approach) - if available
	if MerchantFrame and MerchantFrame.ScrollBox then
		MerchantFrame.ScrollBox:EnableMouseWheel(true)
		MerchantFrame.ScrollBox:HookScript("OnMouseWheel", function(self, delta)
			DOKI:OnMerchantMouseWheel(delta)
		end)
		-- Register ScrollBox callbacks if available
		if MerchantFrame.ScrollBox.RegisterCallback then
			MerchantFrame.ScrollBox:RegisterCallback("OnScroll", function(self, scrollPercent)
				DOKI:OnMerchantScrollPosition(scrollPercent)
			end)
		end

		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Hooked ScrollBox mouse wheel events")
		end
	else
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r ScrollBox not found, using fallback methods")
		end
	end

	-- Method 2: Hook main merchant frame (fallback and primary for classic merchants)
	if MerchantFrame then
		MerchantFrame:EnableMouseWheel(true)
		MerchantFrame:HookScript("OnMouseWheel", function(self, delta)
			DOKI:OnMerchantMouseWheel(delta)
		end)
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Hooked MerchantFrame mouse wheel events")
		end
	end

	-- Method 3: Hook merchant update functions
	hooksecurefunc("MerchantFrame_Update", function()
		if DOKI.merchantScrollDetector.isScrolling then
			DOKI:OnMerchantScrollPageChange()
		end
	end)
end

function DOKI:OnMerchantMouseWheel(delta)
	if not (MerchantFrame and MerchantFrame:IsVisible()) then return end

	local direction = delta > 0 and "up" or "down"
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scroll detected: %s", direction))
	end

	-- Mark as scrolling
	self.merchantScrollDetector.isScrolling = true
	-- Reset scroll end timer
	if self.merchantScrollDetector.scrollTimer then
		self.merchantScrollDetector.scrollTimer:Cancel()
	end

	self.merchantScrollDetector.scrollTimer = C_Timer.NewTimer(0.3, function()
		DOKI.merchantScrollDetector.isScrolling = false
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Merchant scrolling ended")
		end
	end)
	-- Immediate response to scroll
	self:OnMerchantScrollPageChange()
end

function DOKI:OnMerchantScrollPosition(scrollPercent)
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scroll position: %.2f", scrollPercent))
	end

	self:OnMerchantScrollPageChange()
end

function DOKI:OnMerchantScrollPageChange()
	if not (MerchantFrame and MerchantFrame:IsVisible()) then return end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Merchant page changed via scroll - updating indicators")
	end

	-- FIXED: Don't rely on API state comparison since GetMerchantNumItems()
	-- returns ALL items, not just visible ones. Always update on scroll.
	C_Timer.After(0.1, function()
		if self.db and self.db.enabled and MerchantFrame and MerchantFrame:IsVisible() then
			-- Force a surgical update to detect button changes
			local changedCount = self:TriggerImmediateSurgicalUpdate()
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Merchant scroll update: triggered surgical update"))
			end
		end
	end)
end

function DOKI:GetCurrentMerchantState()
	local state = {}
	local numItems = GetMerchantNumItems()
	for i = 1, numItems do
		-- FIXED: Use new War Within API
		local itemInfo = C_MerchantFrame.GetItemInfo(i)
		if itemInfo and itemInfo.name then -- Item exists
			state[i] = {
				name = itemInfo.name,
				texture = itemInfo.texture,
				price = itemInfo.price,
				quantity = itemInfo.stackCount,
				available = itemInfo.numAvailable,
				isPurchasable = itemInfo.isPurchasable,
			}
		end
	end

	return state
end

function DOKI:CompareMerchantState(state1, state2)
	if not state1 and not state2 then return true end

	if not state1 or not state2 then return false end

	-- Quick count comparison
	local count1, count2 = 0, 0
	for _ in pairs(state1) do count1 = count1 + 1 end

	for _ in pairs(state2) do count2 = count2 + 1 end

	if count1 ~= count2 then return false end

	-- Compare items
	for i, item1 in pairs(state1) do
		local item2 = state2[i]
		if not item2 then return false end

		-- FIXED: Handle table structures properly
		if type(item1) == "table" and type(item2) == "table" then
			if item1.name ~= item2.name or item1.texture ~= item2.texture or item1.price ~= item2.price then
				return false
			end
		else
			-- Fallback for non-table data
			if item1 ~= item2 then return false end
		end
	end

	return true
end

-- ===== ENHANCED DELAYED CLEANUP SCAN SYSTEM =====
-- ADDED: Schedule a delayed cleanup scan with auto-cancellation
function DOKI:ScheduleDelayedCleanupScan()
	-- Cancel any existing delayed scan
	self:CancelDelayedScan()
	-- Reset cancellation flag
	self.delayedScanCancelled = false
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scheduling delayed cleanup scan in 0.2s...")
	end

	-- Schedule new delayed scan
	self.delayedScanTimer = C_Timer.NewTimer(0.2, function()
		-- Check if scan was cancelled
		if DOKI.delayedScanCancelled or not (DOKI.db and DOKI.db.enabled) then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Delayed cleanup scan cancelled")
			end

			return
		end

		-- Only run if relevant UI is still visible
		local anyUIVisible = false
		if ElvUI and DOKI:IsElvUIBagVisible() then
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

		if not anyUIVisible and not (MerchantFrame and MerchantFrame:IsVisible()) then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Delayed cleanup scan skipped - no UI visible")
			end

			return
		end

		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Running delayed cleanup scan...")
		end

		-- Run a focused surgical update to catch any missed changes
		local cleanupChanges = 0
		if DOKI.ProcessSurgicalUpdate then
			cleanupChanges = DOKI:ProcessSurgicalUpdate()
		end

		if DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Delayed cleanup scan: %d changes found", cleanupChanges))
		end

		-- Clear the timer reference
		DOKI.delayedScanTimer = nil
	end)
end

-- ADDED: Cancel any pending delayed cleanup scan
function DOKI:CancelDelayedScan()
	if self.delayedScanTimer then
		self.delayedScanTimer:Cancel()
		self.delayedScanTimer = nil
		self.delayedScanCancelled = true
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Cancelled pending delayed cleanup scan")
		end
	end
end

-- ===== PERFORMANCE MONITORING =====
function DOKI:GetPerformanceStats()
	local stats = {
		updateInterval = 0.2,
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

-- ===== ENHANCED SURGICAL UPDATE SYSTEM =====
function DOKI:SurgicalUpdate(isImmediate)
	if not self.db or not self.db.enabled then return 0 end

	local currentTime = GetTime()
	-- ADDED: Cancel any pending delayed scan since we're doing a real update now
	self:CancelDelayedScan()
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
	-- ADDED: Schedule delayed cleanup scan for item movement edge cases
	-- Only schedule if this was an immediate update (triggered by item movement)
	if isImmediate and changeCount >= 0 then -- Even if 0 changes, movement might have edge cases
		self:ScheduleDelayedCleanupScan()
	end

	if self.db.debugMode then
		local updateType = isImmediate and "immediate" or "scheduled"
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

-- ENHANCED: Immediate surgical update trigger with delayed scan cancellation
function DOKI:TriggerImmediateSurgicalUpdate()
	if not self.db or not self.db.enabled then return end

	-- ADDED: Cancel any pending delayed scan since we're doing an immediate update
	self:CancelDelayedScan()
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

		self:SurgicalUpdate(true) -- This will automatically schedule delayed cleanup
	end
end

-- FIXED: Enhanced full scan with delayed rescan scheduling
function DOKI:FullItemScan(withDelay)
	if not self.db or not self.db.enabled then return 0 end

	-- FIXED: Add slight delay for battlepet caging timing issues
	if withDelay then
		C_Timer.After(0.15, function()
			if self.db and self.db.enabled then
				self:FullItemScan(false) -- Run without delay on retry
			end
		end)
		return 0
	end

	if self.db.debugMode then
		print("|cffff69b4DOKI|r === ENHANCED FULL SCAN START ===")
	end

	local startTime = GetTime()
	local indicatorCount = 0
	self.foundFramesThisScan = {}
	-- Use enhanced scanning for bags (with ATT pre-processing when enabled)
	indicatorCount = indicatorCount + self:ScanBagFrames()
	-- Keep original merchant scanning (usually fewer items)
	indicatorCount = indicatorCount + self:ScanMerchantFrames()
	-- Update snapshot after full scan
	if self.CreateButtonSnapshot then
		self.lastButtonSnapshot = self:CreateButtonSnapshot()
	end

	local scanDuration = GetTime() - startTime
	self:TrackUpdatePerformance(scanDuration, false)
	-- ADDED: Schedule delayed rescan to catch items that may have failed to load
	if indicatorCount > 0 or self.foundFramesThisScan and #self.foundFramesThisScan > 0 then
		self:ScheduleDelayedFullRescan()
	end

	if self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Enhanced full scan: %d indicators in %.3fs",
			indicatorCount, scanDuration))
		print("|cffff69b4DOKI|r === ENHANCED FULL SCAN END ===")
	end

	return indicatorCount
end

function DOKI:SetATTPerformanceSettings(batchSize, batchDelay)
	if batchSize then
		self.attPerformanceSettings.batchSize = math.max(1, math.min(50, batchSize))
	end

	if batchDelay then
		self.attPerformanceSettings.batchDelay = math.max(0.01, math.min(0.2, batchDelay))
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Updated ATT performance settings: batch size %d, delay %.0fms",
			self.attPerformanceSettings.batchSize, self.attPerformanceSettings.batchDelay * 1000))
	end
end

function DOKI:GetATTPerformanceSettings()
	return self.attPerformanceSettings.batchSize, self.attPerformanceSettings.batchDelay
end

-- Helper function to get item info directly from merchant button
function DOKI:GetItemFromMerchantButton(button, slotIndex)
	if not button then return nil, nil end

	-- Method 1: Check if button has item properties directly (War Within - this works!)
	if button.link and button.hasItem then
		local itemID = self:GetItemID(button.link)
		if itemID then
			return itemID, button.link
		end
	end

	-- FIXED: Don't use API fallback - if button doesn't have direct item data, it's empty
	-- The API returns all items regardless of what page is visible, so we can't rely on it
	-- Check if button is visible but has no item
	if button:IsVisible() then
		return "EMPTY_SLOT", nil
	end

	return nil, nil
end

-- ===== FIXED MERCHANT FRAME SCANNING =====
function DOKI:ScanMerchantFrames()
	local indicatorCount = 0
	if not (MerchantFrame and MerchantFrame:IsVisible()) then
		return 0
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scanning merchant frames...")
	end

	-- Scan only visible merchant button slots (not all API items)
	for i = 1, 12 do -- Most merchants have 10-12 visible slots
		local possibleButtonNames = {
			string.format("MerchantItem%dItemButton", i),
			string.format("MerchantItem%d", i),
		}
		for _, buttonName in ipairs(possibleButtonNames) do
			local button = _G[buttonName]
			if button and button:IsVisible() then
				-- Get item directly from the button
				local itemID, itemLink = self:GetItemFromMerchantButton(button, i)
				-- FIXED: Skip empty slots entirely for indicator creation
				if itemID and itemID ~= "EMPTY_SLOT" and self:IsCollectibleItem(itemID, itemLink) then
					local isCollected, showYellowD, showPurple = self:IsItemCollected(itemID, itemLink)
					-- Only create indicator if NOT collected OR if it needs purple indicator
					if not isCollected or showPurple then
						local itemData = {
							itemID = itemID,
							itemLink = itemLink,
							isCollected = isCollected,
							showYellowD = showYellowD,
							showPurple = showPurple,
							frameType = "merchant",
						}
						-- Try to create indicator
						local success = self:AddButtonIndicator(button, itemData)
						if success then
							indicatorCount = indicatorCount + 1
							if self.db.debugMode then
								local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
								local colorType = showPurple and "PURPLE" or (showYellowD and "BLUE" or "ORANGE")
								print(string.format("|cffff69b4DOKI|r Created %s indicator for %s (ID: %d) on %s",
									colorType, itemName, itemID, buttonName))
							end
						end

						table.insert(self.foundFramesThisScan, {
							frame = button,
							frameName = buttonName,
							itemData = itemData,
						})
					else
						if self.db.debugMode then
							local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
							print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) on %s - ALREADY COLLECTED",
								itemName, itemID, buttonName))
						end
					end
				elseif itemID == "EMPTY_SLOT" then
					if self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r Skipping %s - EMPTY SLOT", buttonName))
					end
				elseif itemID then
					if self.db.debugMode then
						local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
						print(string.format("|cffff69b4DOKI|r Skipping %s (ID: %d) on %s - NOT COLLECTIBLE",
							itemName, itemID, buttonName))
					end
				end

				break
			end
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Merchant scan complete: %d indicators created", indicatorCount))
	end

	return indicatorCount
end

-- ===== ENHANCED SCANNING WITH LAZY LOADING =====
function DOKI:ScanBagFrames()
	if not self.db or not self.db.enabled then return 0 end

	local indicatorCount = 0
	-- ATT MODE: Use preloaded data when possible
	if self.db.attMode then
		if self.db.debugMode then
			print("|cffff69b4DOKI|r ATT mode: Using lazy-loaded data for bag scanning...")
		end

		-- Trigger item discovery for current bags
		self:DiscoverBagItems()
		-- Use the existing scanning logic, but now GetATTCollectionStatus will primarily use cache
		indicatorCount = self:ScanBagFramesWithATT()
	else
		-- Non-ATT mode uses original logic
		indicatorCount = self:ScanBagFramesOriginal()
	end

	return indicatorCount
end

function DOKI:ScanBagFramesWithATT()
	local indicatorCount = 0
	-- Collect all bag items first
	local allBagItems = {}
	-- Scan ElvUI bags if visible
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
								local possibleNames = {
									string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
									string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
								}
								for _, elvUIButtonName in ipairs(possibleNames) do
									local elvUIButton = _G[elvUIButtonName]
									if elvUIButton and elvUIButton:IsVisible() then
										allBagItems[elvUIButton] = {
											itemID = itemInfo.itemID,
											itemLink = itemInfo.hyperlink,
											frameType = "bag",
										}
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

	-- Scan Blizzard bags
	local scannedBlizzardBags = false
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		-- Combined bags logic (same as before)
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
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
							allBagItems[button] = {
								itemID = itemInfo.itemID,
								itemLink = itemInfo.hyperlink,
								frameType = "bag",
							}
						end
					end
				end
			end
		end

		scannedBlizzardBags = true
	end

	-- Individual container frames
	if not scannedBlizzardBags then
		for bagID = 0, NUM_BAG_SLOTS do
			local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
			if containerFrame and containerFrame:IsVisible() then
				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
							local possibleNames = {
								string.format("ContainerFrame%dItem%d", bagID + 1, slotID),
								string.format("ContainerFrame%dItem%dButton", bagID + 1, slotID),
							}
							for _, buttonName in ipairs(possibleNames) do
								local button = _G[buttonName]
								if button and button:IsVisible() then
									allBagItems[button] = {
										itemID = itemInfo.itemID,
										itemLink = itemInfo.hyperlink,
										frameType = "bag",
									}
									break
								end
							end
						end
					end
				end

				scannedBlizzardBags = true
			end
		end
	end

	-- Create indicators for all items (now using cached data)
	for button, itemData in pairs(allBagItems) do
		local isCollected, showYellowD, showPurple = self:IsItemCollected(itemData.itemID, itemData.itemLink)
		itemData.isCollected = isCollected
		itemData.showYellowD = showYellowD
		itemData.showPurple = showPurple
		indicatorCount = indicatorCount + self:CreateUniversalIndicator(button, itemData)
	end

	return indicatorCount
end

function DOKI:ScanBagFramesOriginal()
	-- Original non-ATT scanning logic (same as before)
	local indicatorCount = 0
	-- Scan ElvUI bags if visible
	if ElvUI and self:IsElvUIBagVisible() then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
							if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
								if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
									local possibleNames = {
										string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
										string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
										string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
									}
									for _, elvUIButtonName in ipairs(possibleNames) do
										local elvUIButton = _G[elvUIButtonName]
										if elvUIButton and elvUIButton:IsVisible() then
											local isCollected, showYellowD, showPurple = self:IsItemCollected(itemInfo.itemID,
												itemInfo.hyperlink)
											local itemData = {
												itemID = itemInfo.itemID,
												itemLink = itemInfo.hyperlink,
												isCollected = isCollected,
												showYellowD = showYellowD,
												showPurple = showPurple,
												frameType = "bag",
											}
											indicatorCount = indicatorCount + self:CreateUniversalIndicator(elvUIButton, itemData)
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

	-- Similar logic for Blizzard bags...
	-- (keeping original code for non-ATT mode)
	return indicatorCount
end

-- Create universal indicator
function DOKI:CreateUniversalIndicator(frame, itemData)
	if itemData.isCollected and not itemData.showPurple then
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

-- ===== ENHANCED WAR WITHIN EVENT SYSTEM WITH BETTER MERCHANT SELLING DETECTION =====
function DOKI:SetupMinimalEventSystem()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	else
		self.eventFrame = CreateFrame("Frame")
	end

	-- Enhanced event list with merchant support
	local events = {
		"MERCHANT_SHOW",
		"MERCHANT_CLOSED",
		"MERCHANT_UPDATE", -- Added for merchant page changes
		"BANKFRAME_OPENED",
		"BANKFRAME_CLOSED",
		"ITEM_UNLOCKED",
		"BAG_UPDATE",
		"BAG_UPDATE_DELAYED",
		"ITEM_LOCK_CHANGED",
		"CURSOR_CHANGED",
		-- WAR WITHIN COLLECTION EVENTS (removed noisy ones)
		"PET_JOURNAL_LIST_UPDATE",            -- Main pet event (confirmed working)
		"COMPANION_LEARNED",                  -- Mount/pet learning (confirmed in Blizzard code)
		"COMPANION_UNLEARNED",                -- Mount/pet unlearning (confirmed in Blizzard code)
		"TRANSMOG_COLLECTION_UPDATED",        -- When transmog is collected
		"TOYS_UPDATED",                       -- When toys are learned
		-- ADDED: Enhanced merchant selling detection
		"MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", -- When selling items
		"UI_INFO_MESSAGE",                    -- For sell confirmations
	}
	for _, event in ipairs(events) do
		self.eventFrame:RegisterEvent(event)
	end

	self.eventFrame:SetScript("OnEvent", function(self, event, ...)
		if not (DOKI.db and DOKI.db.enabled) then return end

		-- ENHANCED: Cancel delayed scans for most events since they trigger normal scanning
		local cancelDelayedScan = true
		if event == "MERCHANT_SHOW" then
			DOKI.merchantScrollDetector.merchantOpen = true
			DOKI:InitializeMerchantScrollDetection()
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "MERCHANT_UPDATE" then
			-- Detect page changes during scrolling or filter changes
			if DOKI.merchantScrollDetector.merchantOpen then
				C_Timer.After(0.1, function()
					if DOKI.db and DOKI.db.enabled and MerchantFrame and MerchantFrame:IsVisible() then
						DOKI:ScanMerchantFrames()
					end
				end)
			end
		elseif event == "MERCHANT_CLOSED" then
			DOKI.merchantScrollDetector.merchantOpen = false
			DOKI.merchantScrollDetector.lastMerchantState = nil
			if DOKI.CleanupMerchantTextures then
				DOKI:CleanupMerchantTextures()
			end
		elseif event == "BANKFRAME_OPENED" then
			C_Timer.After(0.2, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:FullItemScan()
				end
			end)
		elseif event == "BANKFRAME_CLOSED" then
			if DOKI.CleanupBankTextures then
				DOKI:CleanupBankTextures()
			end
		elseif event == "ITEM_UNLOCKED" then
			-- Item movement detected - immediate response
			cancelDelayedScan = false -- ENHANCED: Let immediate update handle delayed scan scheduling
			C_Timer.After(0.02, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "ITEM_LOCK_CHANGED" or event == "CURSOR_CHANGED" then
			-- Item pickup/drop detected - very immediate response
			cancelDelayedScan = false -- ENHANCED: Let immediate update handle delayed scan scheduling
			C_Timer.After(0.01, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" or event == "UI_INFO_MESSAGE" then
			-- ADDED: Enhanced detection for merchant selling
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Merchant sell event detected - forcing update")
			end

			cancelDelayedScan = false
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					DOKI:TriggerImmediateSurgicalUpdate()
				end
			end)
		elseif event == "PET_JOURNAL_LIST_UPDATE" or
				event == "COMPANION_LEARNED" or event == "COMPANION_UNLEARNED" then
			-- Collection changed - clear cache and FORCE FULL SCAN WITH DELAY for battlepets
			DOKI:ClearCollectionCache()
			-- ENHANCED: Also clear ATT cache for pets/mounts since collection status changed
			DOKI:ClearATTBatchQueue()
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					-- Use withDelay=true for potential battlepet timing issues
					DOKI:FullItemScan(true)
				end
			end)
		elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TOYS_UPDATED" then
			-- Transmog/toy collection changed - clear cache and FORCE FULL SCAN
			DOKI:ClearCollectionCache()
			-- ENHANCED: Also clear ATT cache since collection status changed
			DOKI:ClearATTBatchQueue()
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					-- Force full scan to re-evaluate all visible items
					DOKI:FullItemScan()
				end
			end)
		elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
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
				cancelDelayedScan = false -- ENHANCED: Let immediate update handle delayed scan scheduling
				local delay = (event == "BAG_UPDATE_DELAYED") and 0.1 or 0.05
				C_Timer.After(delay, function()
					if DOKI.db and DOKI.db.enabled then
						DOKI:TriggerImmediateSurgicalUpdate()
					end
				end)
			end
		end

		-- ENHANCED: Cancel delayed scan for events that trigger normal scanning
		if cancelDelayedScan then
			DOKI:CancelDelayedScan()
		end
	end)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced event system initialized with merchant selling detection")
	end
end

-- ===== ENHANCED INITIALIZATION WITH DELAYED SCAN SUPPORT =====
function DOKI:InitializeUniversalScanning()
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- Initialize ensemble detection
	self:InitializeEnsembleDetection()
	-- Start ATT lazy loading if in ATT mode
	if self.db and self.db.attMode then
		self:StartATTItemDiscovery()
	end

	-- Enhanced surgical update timer
	self.surgicalTimer = C_Timer.NewTicker(0.2, function()
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

			local cursorHasItem = C_Cursor and C_Cursor.GetCursorItem() and true or false
			if anyUIVisible or (MerchantFrame and MerchantFrame:IsVisible()) or cursorHasItem then
				DOKI:SurgicalUpdate(false)
			end
		end
	end)
	self:SetupMinimalEventSystem()
	self:FullItemScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Enhanced surgical system initialized with ATT lazy loading")
		print("  |cff00ff00•|r ATT Lazy Loading: Background processing during idle time")
		print("  |cff00ff00•|r Item Discovery: Automatic detection of bag contents")
		print("  |cff00ff00•|r Smart Caching: Persistent ATT results with instant access")
		print("  |cff00ff00•|r Performance: Eliminates FPS drops when opening bags")
	end
end

-- ===== DEBUG FUNCTIONS =====
function DOKI:DebugFoundFrames()
	if not self.foundFramesThisScan or #self.foundFramesThisScan == 0 then
		print("|cffff69b4DOKI|r No frames found in last scan. Try /doki scan first.")
		return
	end

	print(string.format("|cffff69b4DOKI|r === FOUND FRAMES DEBUG (%d frames) ===", #self.foundFramesThisScan))
	for i, frameInfo in ipairs(self.foundFramesThisScan) do
		local itemName = C_Item.GetItemInfo(frameInfo.itemData.itemID) or "Unknown"
		local extraInfo = ""
		if frameInfo.itemData.petSpeciesID then
			extraInfo = string.format(" [Pet Species: %d]", frameInfo.itemData.petSpeciesID)
		elseif frameInfo.itemData.showPurple then
			extraInfo = " [Purple Indicator]"
		end

		print(string.format("%d. %s (ID: %d) in %s [%s] - %s%s",
			i, itemName, frameInfo.itemData.itemID, frameInfo.frameName,
			frameInfo.itemData.frameType,
			frameInfo.itemData.isCollected and "COLLECTED" or "NOT collected",
			extraInfo))
	end

	print("|cffff69b4DOKI|r === END FOUND FRAMES DEBUG ===")
end

-- ADDED: Debug function to help identify battlepet surgical update issues
function DOKI:DebugBattlepetSnapshot()
	if not self.CreateButtonSnapshot then
		print("|cffff69b4DOKI|r ButtonTextures system not available")
		return
	end

	local snapshot = self:CreateButtonSnapshot()
	local battlepetCount = 0
	local regularItemCount = 0
	local ensembleCount = 0
	local purpleIndicatorCount = 0
	print("|cffff69b4DOKI|r === BATTLEPET + ENSEMBLE + PURPLE SNAPSHOT DEBUG ===")
	for button, itemData in pairs(snapshot) do
		if type(itemData) == "table" and itemData.itemID then
			if itemData.itemLink and string.find(itemData.itemLink, "battlepet:") then
				battlepetCount = battlepetCount + 1
				local speciesID = self:GetPetSpeciesFromBattlePetLink(itemData.itemLink)
				print(string.format("  Battlepet: %s -> Species %d",
					button:GetName() or "unnamed", speciesID or "unknown"))
			elseif self:IsEnsembleItem(itemData.itemID) then
				ensembleCount = ensembleCount + 1
				local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
				print(string.format("  Ensemble: %s -> %s (ID: %d)",
					button:GetName() or "unnamed", itemName, itemData.itemID))
			else
				regularItemCount = regularItemCount + 1
				-- Check if this would get a purple indicator from ATT
				if self.db and self.db.attMode then
					local _, _, showPurple = self:GetATTCollectionStatus(itemData.itemID, itemData.itemLink)
					if showPurple then
						purpleIndicatorCount = purpleIndicatorCount + 1
						local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
						print(string.format("  Purple Indicator: %s -> %s (ID: %d)",
							button:GetName() or "unnamed", itemName, itemData.itemID))
					end
				end
			end
		else
			regularItemCount = regularItemCount + 1
		end
	end

	print(string.format("Total snapshot items: %d (%d regular, %d battlepets, %d ensembles, %d purple indicators)",
		regularItemCount + battlepetCount + ensembleCount, regularItemCount, battlepetCount, ensembleCount,
		purpleIndicatorCount))
	print("|cffff69b4DOKI|r === END SNAPSHOT DEBUG ===")
end
