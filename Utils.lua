-- DOKI Utils - War Within Complete Fix with Merchant Scroll Detection + Enhanced Delayed Cleanup + Ensemble Support (FACTION DETECTION REMOVED)
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
DOKI.foundFramesThisScan = {}
-- Cache for collection status to avoid redundant API calls
DOKI.collectionCache = DOKI.collectionCache or {}
DOKI.lastCacheUpdate = 0
-- ADDED: Ensemble detection variables
DOKI.ensembleWordCache = nil
DOKI.ensembleKnownItemID = 234522 -- Known ensemble item for word extraction
-- ===== MERCHANT SCROLL DETECTION SYSTEM =====
DOKI.merchantScrollDetector = {
	isScrolling = false,
	scrollTimer = nil,
	lastMerchantState = nil,
	merchantOpen = false,
}
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

-- ===== ENHANCED SURGICAL UPDATE THROTTLING WITH DELAYED CLEANUP =====
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.05 -- 50ms minimum between updates
DOKI.pendingSurgicalUpdate = false
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

-- ===== CACHE MANAGEMENT =====
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
	-- Cache expires after 30 seconds or if collections were updated
	if cached and (GetTime() - cached.timestamp < 30) then
		return cached.isCollected, cached.showYellowD
	end

	return nil, nil
end

function DOKI:SetCachedCollectionStatus(itemID, itemLink, isCollected, showYellowD)
	local cacheKey = itemLink or tostring(itemID)
	self.collectionCache[cacheKey] = {
		isCollected = isCollected,
		showYellowD = showYellowD,
		timestamp = GetTime(),
	}
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
	if not itemID then return false, false end

	-- Check cache first (following your existing pattern)
	local cachedCollected, cachedYellowD = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		return cachedCollected, cachedYellowD
	end

	local isCollected = self:CheckEnsembleByTooltip(itemID, itemLink)
	-- Cache the result (ensembles don't use yellow D logic)
	self:SetCachedCollectionStatus(itemID, itemLink, isCollected, false)
	return isCollected, false
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

-- Full scan for initial setup with delay for battlepets
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
					local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
					-- Only create indicator if NOT collected
					if not isCollected then
						local itemData = {
							itemID = itemID,
							itemLink = itemLink,
							isCollected = isCollected,
							showYellowD = showYellowD,
							frameType = "merchant",
						}
						-- Try to create indicator
						local success = self:AddButtonIndicator(button, itemData)
						if success then
							indicatorCount = indicatorCount + 1
							if self.db.debugMode then
								local itemName = C_Item.GetItemInfo(itemID) or "Unknown"
								print(string.format("|cffff69b4DOKI|r Created indicator for %s (ID: %d) on %s",
									itemName, itemID, buttonName))
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

function DOKI:FindMerchantItemButton(frame)
	if not frame then return nil end

	-- Common button names and properties
	local buttonFields = { "ItemButton", "itemButton", "button", "Button" }
	for _, field in ipairs(buttonFields) do
		local button = frame[field]
		if button and type(button) == "table" and button.IsVisible then
			local success, isVisible = pcall(button.IsVisible, button)
			if success and isVisible then
				return button
			end
		end
	end

	-- Search children
	local children = { frame:GetChildren() }
	for _, child in ipairs(children) do
		if child and child.IsVisible then
			local success, isVisible = pcall(child.IsVisible, child)
			if success and isVisible then
				-- Check if this looks like an item button
				if child.GetNormalTexture or child.icon or child.Icon then
					return child
				end
			end
		end
	end

	return nil
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

function DOKI:ScanBagFrames()
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
											local isCollected, showYellowD = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
											local itemData = {
												itemID = itemInfo.itemID,
												itemLink = itemInfo.hyperlink,
												isCollected = isCollected,
												showYellowD = showYellowD,
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

	-- Scan Blizzard bags using container API approach
	local scannedBlizzardBags = false
	-- Combined bags (newer interface)
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots and numSlots > 0 then
				for slotID = 1, numSlots do
					local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
					if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
						if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
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
				local numSlots = C_Container.GetContainerNumSlots(bagID)
				if numSlots and numSlots > 0 then
					for slotID = 1, numSlots do
						local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
						if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
							if self:IsCollectibleItem(itemInfo.itemID, itemInfo.hyperlink) then
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

-- ===== ENHANCED WAR WITHIN EVENT SYSTEM WITH DELAYED SCAN CANCELLATION =====
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
		"PET_JOURNAL_LIST_UPDATE",   -- Main pet event (confirmed working)
		"COMPANION_LEARNED",         -- Mount/pet learning (confirmed in Blizzard code)
		"COMPANION_UNLEARNED",       -- Mount/pet unlearning (confirmed in Blizzard code)
		"TRANSMOG_COLLECTION_UPDATED", -- When transmog is collected
		"TOYS_UPDATED",              -- When toys are learned
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
		elseif event == "PET_JOURNAL_LIST_UPDATE" or
				event == "COMPANION_LEARNED" or event == "COMPANION_UNLEARNED" then
			-- Collection changed - clear cache and FORCE FULL SCAN WITH DELAY for battlepets
			DOKI:ClearCollectionCache()
			C_Timer.After(0.05, function()
				if DOKI.db and DOKI.db.enabled then
					-- Use withDelay=true for potential battlepet timing issues
					DOKI:FullItemScan(true)
				end
			end)
		elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TOYS_UPDATED" then
			-- Transmog/toy collection changed - clear cache and FORCE FULL SCAN
			DOKI:ClearCollectionCache()
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
		print("|cffff69b4DOKI|r Enhanced event system initialized with delayed cleanup scanning")
	end
end

-- ===== ENHANCED INITIALIZATION WITH DELAYED SCAN SUPPORT =====
function DOKI:InitializeUniversalScanning()
	if self.surgicalTimer then
		self.surgicalTimer:Cancel()
	end

	self.lastSurgicalUpdate = 0
	self.pendingSurgicalUpdate = false
	-- ADDED: Initialize ensemble detection
	self:InitializeEnsembleDetection()
	-- Enhanced surgical update timer (0.2s intervals for more responsive fallback)
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
		print(
			"|cffff69b4DOKI|r Enhanced surgical system initialized with ensemble + delayed cleanup scanning (FACTION DETECTION REMOVED)")
		print("  |cff00ff00•|r Regular updates: 0.2s interval")
		print("  |cff00ff00•|r Clean events: Removed noisy COMPANION_UPDATE, etc.")
		print("  |cff00ff00•|r Battlepet support: Caged pet detection")
		print("  |cff00ff00•|r Timing fix: Delays for battlepet caging")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble support: Locale-aware detection + color-based collection status")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble tooltips: Collection status parsing")
		print("  |cff00ff00•|r |cffff8000NEW:|r Merchant scroll detection")
		print("  |cff00ff00•|r |cffff8000NEW:|r OnMouseWheel + MERCHANT_UPDATE events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Delayed cleanup scan (0.2s) with auto-cancellation")
		print("  |cff00ff00•|r |cffff8000REMOVED:|r Faction detection (unreliable)")
		print(string.format("  |cff00ff00•|r Throttling: %.0fms minimum between updates",
			self.surgicalUpdateThrottleTime * 1000))
	end
end

-- ===== ENHANCED ITEM DETECTION TRACING WITH TRANSMOG VALIDATION + ENSEMBLE SUPPORT (FACTION DETECTION REMOVED) =====
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
	local cachedCollected, cachedYellowD = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		print("   Found in cache:")
		print(string.format("    Collected: %s", cachedCollected and "YES" or "NO"))
		print(string.format("    Show Yellow D: %s", cachedYellowD and "YES" or "NO"))
	else
		print("   Not in cache - checking APIs...")
	end

	local isCollected, showYellowD = false, false
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
	local needsIndicator = isCollectible and not isCollected
	print(string.format("   NEEDS INDICATOR: %s", needsIndicator and "YES" or "NO"))
	if needsIndicator then
		local color = showYellowD and "BLUE (has other sources)" or "ORANGE (no other sources)"
		print(string.format("   Indicator Color: %s", color))
	end

	print("|cffff69b4DOKI|r === END TRACE ===")
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

-- ===== WAR WITHIN COLLECTION DETECTION =====
function DOKI:GetItemID(itemLink)
	if not itemLink then return nil end

	if type(itemLink) == "number" then return itemLink end

	if type(itemLink) == "string" then
		local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
		return itemID
	end

	return nil
end

-- FIXED: Enhanced collectible item detection with caged pets, ensembles, and offhand support
function DOKI:IsCollectibleItem(itemID, itemLink)
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
			-- FIXED: Properly handle offhands - check if they're actually transmoggable
			if itemEquipLoc == "INVTYPE_HOLDABLE" then
				-- Use the transmog API to check if this offhand is actually transmoggable
				local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
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

-- ===== ATT SUPPORT ADDITION =====
function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil end

	-- Check cache first using existing system
	local cachedCollected, cachedYellowD = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT using CACHED result for item %d: %s",
				itemID, cachedCollected and "COLLECTED" or "NOT COLLECTED"))
		end

		return cachedCollected
	end

	-- Create fresh tooltip with unique name (same pattern as ensemble tooltips)
	local tooltipName = "DOKIATTTooltip" .. itemID
	local tooltip = CreateFrame("GameTooltip", tooltipName, nil, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	-- Set the item (prefer itemLink for accuracy)
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	else
		tooltip:SetItemByID(itemID)
	end

	tooltip:Show()
	-- Look for ATT collection status in the first few lines
	local attStatus = nil
	for i = 1, math.min(5, tooltip:NumLines()) do
		-- CHECK RIGHT SIDE (where ATT puts collection status)
		local rightLine = _G[tooltipName .. "TextRight" .. i]
		if rightLine and rightLine.GetText then
			local success, text = pcall(rightLine.GetText, rightLine)
			if success and text then
				-- Convert to lowercase for case-insensitive matching
				local lowerText = string.lower(text)
				-- Look for ATT status patterns (handles ✕ ✓ symbols)
				if string.find(lowerText, "not collected") then
					attStatus = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT status found - NOT COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(lowerText, "unknown") then
					attStatus = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT status found - NOT COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(lowerText, "collected") and not string.find(lowerText, "not collected") then
					-- Make sure it's "collected" but not "not collected"
					attStatus = true
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT status found - COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(lowerText, "known") then
					attStatus = true
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT status found - COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				end
			end
		end
	end

	tooltip:Hide()
	tooltip:SetParent(nil)
	-- Cache the result if we found ATT status
	if attStatus ~= nil then
		self:SetCachedCollectionStatus(itemID, itemLink, attStatus, false)
	end

	return attStatus
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

-- WAR WITHIN FIXED: Enhanced collection detection with caged pets, ensembles, and corrected APIs
function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID and not itemLink then return false, false end

	-- ATT MODE: Try to get ATT status first (if enabled)
	if self.db and self.db.attMode then
		local attStatus = self:GetATTCollectionStatus(itemID, itemLink)
		if attStatus ~= nil then
			-- ATT gave us a definitive answer
			if self.db and self.db.debugMode then
				print(string.format("|cffff69b4DOKI|r Using ATT result for item %d: %s",
					itemID, attStatus and "COLLECTED" or "NOT COLLECTED"))
			end

			return attStatus, false -- ATT doesn't use showYellowD logic
		end

		-- ATT didn't have data for this item, continue with fallback logic
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r No ATT data for item %d, using fallback logic", itemID))
		end
	end

	-- ADDED: Handle ensembles first
	local itemName = C_Item.GetItemInfo(itemID)
	if self:IsEnsembleItem(itemID, itemName) then
		local isCollected = self:IsEnsembleCollected(itemID, itemLink)
		return isCollected, false
	end

	-- ADDED: Handle caged pets (battlepet links) next
	local petSpeciesID = self:GetPetSpeciesFromBattlePetLink(itemLink)
	if petSpeciesID then
		local isCollected = self:IsPetSpeciesCollected(petSpeciesID)
		-- Cache the result using itemLink as key since no itemID
		self:SetCachedCollectionStatus(petSpeciesID, itemLink, isCollected, false)
		return isCollected, false
	end

	if not itemID then return false, false end

	-- Check cache first
	local cachedCollected, cachedYellowD = self:GetCachedCollectionStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		return cachedCollected, cachedYellowD
	end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		-- Cache negative result briefly
		self:SetCachedCollectionStatus(itemID, itemLink, false, false)
		return false, false
	end

	local isCollected, showYellowD = false, false
	-- Check mounts - FIXED FOR WAR WITHIN
	if classID == 15 and subClassID == 5 then
		isCollected = self:IsMountCollectedWarWithin(itemID)
		showYellowD = false
		-- Check pets - FIXED FOR WAR WITHIN
	elseif classID == 15 and subClassID == 2 then
		isCollected = self:IsPetCollectedWarWithin(itemID)
		showYellowD = false
		-- Check toys
	elseif C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		isCollected = PlayerHasToy(itemID)
		showYellowD = false
		-- Check transmog
	elseif classID == 2 or classID == 4 then
		if self.db and self.db.smartMode then
			isCollected, showYellowD = self:IsTransmogCollectedSmart(itemID, itemLink)
		else
			isCollected, showYellowD = self:IsTransmogCollected(itemID, itemLink)
		end
	end

	-- Cache the result
	self:SetCachedCollectionStatus(itemID, itemLink, isCollected, showYellowD)
	return isCollected, showYellowD
end

-- WAR WITHIN FIXED: Use the correct GetMountFromItem API
function DOKI:IsMountCollectedWarWithin(itemID)
	if not itemID or not C_MountJournal then return false end

	-- FIXED: Use the proper War Within API - GetMountFromItem
	local mountID = C_MountJournal.GetMountFromItem(itemID)
	if not mountID then
		-- Item might not be loaded yet, or not a mount item
		C_Item.RequestLoadItemDataByID(itemID)
		return false
	end

	-- Get mount info using the mount ID
	local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
	isFactionSpecific, faction, shouldHideOnChar, isCollected, mountIDReturn, isSteadyFlight = C_MountJournal
			.GetMountInfoByID(mountID)
	return isCollected or false
end

-- WAR WITHIN FIXED: Proper pet detection using current journal API
function DOKI:IsPetCollectedWarWithin(itemID)
	if not itemID or not C_PetJournal then return false end

	-- Get pet info from the item - this API is confirmed to work in War Within
	local name, icon, petType, creatureID, sourceText, description, isWild, canBattle,
	isTradeable, isUnique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then
		-- Pet data not loaded yet
		C_Item.RequestLoadItemDataByID(itemID)
		return false
	end

	-- Check if we have any of this pet species
	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

-- FIXED: Enhanced transmog collection detection with proper data loading
function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	-- FIXED: Handle missing transmog data properly
	if not itemModifiedAppearanceID then
		-- Check if the item can actually be transmogged before assuming it's collectible
		if C_Transmog and C_Transmog.GetItemInfo then
			local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
			-- If the item cannot be a transmog source, it's not actually collectible
			if not canBeSource then
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Item %d cannot be transmog source: %s",
						itemID, noSourceReason or "unknown reason"))
				end

				return true, false -- Treat as "collected" (no indicator needed)
			end
		end

		-- Request transmog collection data to be loaded
		C_TransmogCollection.GetItemInfo(itemID)  -- This triggers the cache loading
		if itemLink then
			C_TransmogCollection.GetItemInfo(itemLink) -- Try with link too
		end

		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Transmog data not loaded for item %d, requesting...", itemID))
		end

		-- Return "unknown" state - don't show indicator until we know for sure
		-- This prevents false positives on non-transmoggable items
		return true, false -- Treat as "collected" temporarily to avoid false indicators
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
			if not canBeSource then
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Smart mode: Item %d cannot be transmog source: %s",
						itemID, noSourceReason or "unknown reason"))
				end

				return true, false -- Treat as "collected" (no indicator needed)
			end
		end

		-- Request transmog collection data to be loaded
		C_TransmogCollection.GetItemInfo(itemID)
		if itemLink then
			C_TransmogCollection.GetItemInfo(itemLink)
		end

		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Smart mode: Transmog data not loaded for item %d, requesting...", itemID))
		end

		-- Return "unknown" state - don't show indicator until we know for sure
		return true, false -- Treat as "collected" temporarily
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
		local extraInfo = ""
		if frameInfo.itemData.petSpeciesID then
			extraInfo = string.format(" [Pet Species: %d]", frameInfo.itemData.petSpeciesID)
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
	print("|cffff69b4DOKI|r === BATTLEPET + ENSEMBLE SNAPSHOT DEBUG ===")
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
			end
		else
			regularItemCount = regularItemCount + 1
		end
	end

	print(string.format("Total snapshot items: %d (%d regular, %d battlepets, %d ensembles)",
		regularItemCount + battlepetCount + ensembleCount, regularItemCount, battlepetCount, ensembleCount))
	print("|cffff69b4DOKI|r === END SNAPSHOT DEBUG ===")
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
