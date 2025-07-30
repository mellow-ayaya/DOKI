-- DOKI Collections - Cache Management, ATT Support, Ensemble Detection, Surgical Updates
local addonName, DOKI = ...
-- Initialize collection-specific storage
DOKI.foundFramesThisScan = {}
DOKI.collectionCache = DOKI.collectionCache or {}
DOKI.lastCacheUpdate = 0
-- Ensemble detection variables
DOKI.ensembleWordCache = nil
DOKI.ensembleKnownItemID = 234522 -- Known ensemble item for word extraction
-- Merchant scroll detection system
DOKI.merchantScrollDetector = {
	isScrolling = false,
	scrollTimer = nil,
	lastMerchantState = nil,
	merchantOpen = false,
}
-- Enhanced surgical update throttling with delayed cleanup
DOKI.lastSurgicalUpdate = 0
DOKI.surgicalUpdateThrottleTime = 0.05 -- 50ms minimum between updates
DOKI.pendingSurgicalUpdate = false
-- Enhanced scanning system variables
DOKI.delayedScanTimer = nil       -- Timer for delayed secondary scan
DOKI.delayedScanCancelled = false -- Flag to track if delayed scan should be cancelled
-- ===== CACHE MANAGEMENT WITH PURPLE SUPPORT =====
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

-- ===== ATT SUPPORT WITH PURPLE INDICATORS =====
function DOKI:GetCachedATTStatus(itemID, itemLink)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	local cached = self.collectionCache[cacheKey]
	-- Cache expires after 30 seconds
	if cached and (GetTime() - cached.timestamp < 30) then
		return cached.isCollected, cached.showYellowD, cached.showPurple
	end

	return nil, nil, nil
end

function DOKI:SetCachedATTStatus(itemID, itemLink, isCollected, showYellowD, showPurple)
	local cacheKey = "ATT_" .. (itemLink or tostring(itemID))
	self.collectionCache[cacheKey] = {
		isCollected = isCollected,
		showYellowD = showYellowD,
		showPurple = showPurple,
		timestamp = GetTime(),
	}
end

function DOKI:GetATTCollectionStatus(itemID, itemLink)
	if not itemID then return nil, nil, nil end

	-- Check cache first (now handles all three values)
	local cachedCollected, cachedYellowD, cachedPurple = self:GetCachedATTStatus(itemID, itemLink)
	if cachedCollected ~= nil then
		if self.db and self.db.debugMode then
			print(string.format("|cffff69b4DOKI|r ATT using CACHED result for item %d: %s%s%s",
				itemID,
				cachedCollected and "COLLECTED" or "NOT COLLECTED",
				cachedYellowD and " (other source)" or "",
				cachedPurple and " (fractional)" or ""))
		end

		return cachedCollected, cachedYellowD, cachedPurple
	end

	-- Create fresh tooltip with unique name
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
	local showYellowD = false
	local showPurple = false
	for i = 1, math.min(5, tooltip:NumLines()) do
		-- CHECK RIGHT SIDE (where ATT puts collection status)
		local rightLine = _G[tooltipName .. "TextRight" .. i]
		if rightLine and rightLine.GetText then
			local success, text = pcall(rightLine.GetText, rightLine)
			if success and text and string.len(text) > 0 then
				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r ATT tooltip line %d: '%s'", i, text))
				end

				-- LOCALE-INDEPENDENT: Look for Unicode symbols first
				if string.find(text, "✗") or string.find(text, "❌") or string.find(text, "✕") or string.find(text, "X") then
					-- Not collected symbols
					attStatus = false
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT symbol detection - NOT COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(text, "⭕") or string.find(text, "🔴") or (string.find(text, "✓") and string.find(text, "*")) then
					-- Circled symbols or checkmark with asterisk - collected from other source
					attStatus = true
					showYellowD = true -- Show blue indicator in basic mode
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT symbol detection - COLLECTED (other source): '%s' (ID: %d)", text,
							itemID))
					end

					break
				elseif string.find(text, "✓") or string.find(text, "✅") or string.find(text, "☑") then
					-- Regular checkmark - fully collected
					attStatus = true
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT symbol detection - COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				end

				-- LOCALE-INDEPENDENT: Look for numerical patterns like "1/3", "2/3", "3/3"
				local current, total = string.match(text, "(%d+)/(%d+)")
				if current and total then
					current = tonumber(current)
					total = tonumber(total)
					if current >= total then
						-- Fully collected (3/3, etc.)
						attStatus = true
						showYellowD = false
						showPurple = false
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r ATT numerical detection - FULLY COLLECTED (%d/%d): '%s' (ID: %d)",
								current, total, text, itemID))
						end
					else
						-- Partially collected (1/3, 2/3, etc.) - show PURPLE indicator
						attStatus = false
						showYellowD = false
						showPurple = true
						if self.db and self.db.debugMode then
							print(string.format(
								"|cffff69b4DOKI|r ATT numerical detection - FRACTIONAL (%d/%d) - PURPLE INDICATOR: '%s' (ID: %d)",
								current, total, text, itemID))
						end
					end

					break
				end

				-- LOCALE-INDEPENDENT: Look for percentage patterns like "66.66%", "100%"
				local percentage = string.match(text, "(%d+%.?%d*)%%")
				if percentage then
					percentage = tonumber(percentage)
					if percentage >= 100 then
						-- 100% collected
						attStatus = true
						showYellowD = false
						showPurple = false
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r ATT percentage detection - FULLY COLLECTED (%.1f%%): '%s' (ID: %d)",
								percentage, text, itemID))
						end
					else
						-- Partially collected - show PURPLE indicator
						attStatus = false
						showYellowD = false
						showPurple = true
						if self.db and self.db.debugMode then
							print(string.format(
								"|cffff69b4DOKI|r ATT percentage detection - FRACTIONAL (%.1f%%) - PURPLE INDICATOR: '%s' (ID: %d)",
								percentage, text, itemID))
						end
					end

					break
				end

				-- FALLBACK: Text-based detection (existing logic, kept for compatibility)
				local lowerText = string.lower(text)
				if string.find(lowerText, "not collected") then
					attStatus = false
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT text fallback - NOT COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(lowerText, "unknown") then
					attStatus = false
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT text fallback - NOT COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				elseif string.find(lowerText, "collected") and not string.find(lowerText, "not collected") then
					-- Make sure it's "collected" but not "not collected"
					-- Check if it mentions other source
					if string.find(lowerText, "source") or string.find(lowerText, "other") or string.find(text, "*") then
						attStatus = true
						showYellowD = true
						showPurple = false
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r ATT text fallback - COLLECTED (other source): '%s' (ID: %d)", text,
								itemID))
						end
					else
						attStatus = true
						showYellowD = false
						showPurple = false
						if self.db and self.db.debugMode then
							print(string.format("|cffff69b4DOKI|r ATT text fallback - COLLECTED: '%s' (ID: %d)", text, itemID))
						end
					end

					break
				elseif string.find(lowerText, "known") then
					attStatus = true
					showYellowD = false
					showPurple = false
					if self.db and self.db.debugMode then
						print(string.format("|cffff69b4DOKI|r ATT text fallback - COLLECTED: '%s' (ID: %d)", text, itemID))
					end

					break
				end
			end
		end
	end

	tooltip:Hide()
	tooltip:SetParent(nil)
	-- Cache the result if we found ATT status (now caches all three values)
	if attStatus ~= nil then
		self:SetCachedATTStatus(itemID, itemLink, attStatus, showYellowD, showPurple)
	end

	return attStatus, showYellowD, showPurple
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
								local isCollected, showYellowD, showPurple = self:IsItemCollected(itemInfo.itemID, itemInfo.hyperlink)
								local itemData = {
									itemID = itemInfo.itemID,
									itemLink = itemInfo.hyperlink,
									isCollected = isCollected,
									showYellowD = showYellowD,
									showPurple = showPurple,
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
										local isCollected, showYellowD, showPurple = self:IsItemCollected(itemInfo.itemID, itemInfo
											.hyperlink)
										local itemData = {
											itemID = itemInfo.itemID,
											itemLink = itemInfo.hyperlink,
											isCollected = isCollected,
											showYellowD = showYellowD,
											showPurple = showPurple,
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
			"|cffff69b4DOKI|r Enhanced surgical system initialized with ensemble + delayed cleanup scanning + PURPLE indicators (FACTION DETECTION REMOVED)")
		print("  |cff00ff00•|r Regular updates: 0.2s interval")
		print("  |cff00ff00•|r Clean events: Removed noisy COMPANION_UPDATE, etc.")
		print("  |cff00ff00•|r Battlepet support: Caged pet detection")
		print("  |cff00ff00•|r Timing fix: Delays for battlepet caging")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble support: Locale-aware detection + color-based collection status")
		print("  |cff00ff00•|r |cffff8000NEW:|r Ensemble tooltips: Collection status parsing")
		print("  |cff00ff00•|r |cffff8000NEW:|r Merchant scroll detection")
		print("  |cff00ff00•|r |cffff8000NEW:|r OnMouseWheel + MERCHANT_UPDATE events")
		print("  |cff00ff00•|r |cffff8000NEW:|r Delayed cleanup scan (0.2s) with auto-cancellation")
		print("  |cff00ff00•|r |cffff8000NEW:|r PURPLE indicators for fractional items")
		print("  |cff00ff00•|r |cffff8000REMOVED:|r Faction detection (unreliable)")
		print(string.format("  |cff00ff00•|r Throttling: %.0fms minimum between updates",
			self.surgicalUpdateThrottleTime * 1000))
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
