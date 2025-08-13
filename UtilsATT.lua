-- DOKI Enhanced ATT Scanning - Two-Phase State-Driven Architecture (Race Condition Eliminated)
local addonName, DOKI = ...
-- ===== SCAN STATE MANAGEMENT =====
DOKI.scanState = {
	isScanInProgress = false,
	isLoginScan = false,
	isInternalScan = false, -- Flag to allow our own tooltip usage
	scanStartTime = 0,
	totalItems = 0,
	processedItems = 0,
	progressFrame = nil,
	tooltipHooks = {},
}
-- ===== CACHE DETECTION =====
local function needsFullScan()
	-- No previous scan recorded
	if not DOKI.db.lastFullScanTime then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r No previous full scan recorded - full scan needed")
		end

		return true
	end

	-- No ATT cache entries exist
	if not DOKI.collectionCache then return true end

	for _, cached in pairs(DOKI.collectionCache) do
		if cached.isATTResult then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ATT cache found - no full scan needed")
			end

			return false
		end
	end

	if DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r No ATT cache found - full scan needed")
	end

	return true
end

-- ===== SMART TOOLTIP BLOCKING SYSTEM =====
local tooltipTypes = {
	"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
	"ShoppingTooltip2", "WorldMapTooltip", "PerksProgramTooltip",
}
-- Smart tooltip blocker that allows our internal scanning
local function SmartTooltipBlocker(tooltipFrame)
	-- Block tooltips ONLY if scan is running AND it's not our own internal call
	if DOKI and DOKI.scanState and DOKI.scanState.isScanInProgress and not DOKI.scanState.isInternalScan then
		if tooltipFrame and tooltipFrame.Hide then
			tooltipFrame:Hide()
		end
	end
end

local function InstallTooltipHooks()
	DOKI.scanState.isScanInProgress = true
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r Installing SMART tooltip hooks...")
	end

	for _, tooltipName in ipairs(tooltipTypes) do
		local tooltip = _G[tooltipName]
		if tooltip and tooltip.Show then
			if not DOKI.scanState.tooltipHooks[tooltipName] then
				-- Use the smart blocker instead of aggressive blocking
				hooksecurefunc(tooltip, "Show", function(self)
					SmartTooltipBlocker(self)
				end)
				DOKI.scanState.tooltipHooks[tooltipName] = true
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Hooked %s with smart blocker", tooltipName))
				end
			end
		end
	end
end

-- ===== PROGRESS FRAME SYSTEM =====
local function CreateScanProgressFrame()
	if DOKI.scanState.progressFrame then
		return DOKI.scanState.progressFrame
	end

	local frame = CreateFrame("Frame", "DOKIScanProgressFrame", UIParent)
	frame:SetSize(200, 40)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(9999)
	-- Background
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.8)
	frame.bg = bg
	-- Border
	local border = CreateFrame("Frame", nil, frame, "DialogBorderTemplate")
	border:SetAllPoints()
	-- Progress text
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER", 0, 5)
	text:SetText("DOKI is scanning...")
	frame.text = text
	-- Percentage text
	local percentText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	percentText:SetPoint("CENTER", 0, -8)
	percentText:SetText("0%")
	frame.percentText = percentText
	-- Mouse following behavior
	frame:SetScript("OnUpdate", function(self)
		if not DOKI.scanState.isScanInProgress then
			return
		end

		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
			(x / scale) + 15, (y / scale) + 15)
	end)
	DOKI.scanState.progressFrame = frame
	return frame
end

function DOKI:UpdateProgressFrame()
	local frame = DOKI.scanState.progressFrame
	if not frame then return end

	local processed = DOKI.scanState.processedItems
	local total = DOKI.scanState.totalItems
	if total > 0 then
		local percentage = math.floor((processed / total) * 100)
		frame.percentText:SetText(string.format("%d%% (%d/%d)", percentage, processed, total))
		-- Update main text with estimated time remaining
		local elapsed = GetTime() - DOKI.scanState.scanStartTime
		if processed > 0 then
			local timePerItem = elapsed / processed
			local remaining = (total - processed) * timePerItem
			if remaining > 1 then
				frame.text:SetText(string.format("DOKI is scanning... ~%.0fs", remaining))
			else
				frame.text:SetText("DOKI is scanning... almost done")
			end
		end
	else
		frame.percentText:SetText("Preparing...")
	end
end

local function ShowProgressFrame()
	local frame = CreateScanProgressFrame()
	if frame then
		frame:Show()
		DOKI:UpdateProgressFrame()
	end
end

local function HideProgressFrame()
	if DOKI.scanState and DOKI.scanState.progressFrame then
		DOKI.scanState.progressFrame:Hide()
		DOKI.scanState.progressFrame:SetScript("OnUpdate", nil)
		DOKI.scanState.progressFrame = nil
	end
end

-- ===== PHASE 2: CLIENT DATA WATCHER ("CANARY SCAN") =====
function DOKI:StartClientDataWatcher(callback)
	if self.db and self.db.debugMode then
		print("|cffff6600DOKI PHASE 2:|r Starting Quorum Canary Scan (No Timeout - User Initiated)...")
	end

	local attempt = 0
	local canaryTicker = nil
	-- Find the items we need to watch
	local allItemLocations = {}
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				if C_Container.GetContainerItemID(bagID, slotID) then
					table.insert(allItemLocations, { bag = bagID, slot = slotID })
				end
			end
		end
	end

	local firstItem, middleItem, lastItem = nil, nil, nil
	if #allItemLocations > 0 then
		firstItem = allItemLocations[1]
		middleItem = allItemLocations[math.max(1, math.floor(#allItemLocations / 2))]
		lastItem = allItemLocations[#allItemLocations]
	end

	local function CheckClientDataReady()
		attempt = attempt + 1
		-- If there are no items in the bags at all, we succeed immediately.
		if not firstItem then
			if canaryTicker then canaryTicker:Cancel() end

			if DOKI.db.debugMode then
				print("|cff00ff00DOKI CANARY SUCCESS:|r No items in bags to check.")
			end

			callback()
			return
		end

		-- Check the readiness of our three canary items
		local function isLinkReady(location)
			if not location then return false end

			local success, itemInfo = pcall(C_Container.GetContainerItemInfo, location.bag, location.slot)
			if success and itemInfo and itemInfo.hyperlink then
				return not itemInfo.hyperlink:find("%[%]")
			end

			return false
		end

		local firstReady = isLinkReady(firstItem)
		local middleReady = isLinkReady(middleItem)
		local lastReady = isLinkReady(lastItem)
		-- Check the success condition
		if firstReady and middleReady and lastReady then
			if canaryTicker then canaryTicker:Cancel() end

			if DOKI.db.debugMode then
				print(string.format("|cff00ff00DOKI CANARY SUCCESS:|r Quorum met after %.1fs. All items should be ready.",
					attempt * 0.5))
			end

			callback()
			return
		end

		-- Log progress every 20 attempts (10 seconds) instead of every 10
		if DOKI.db.debugMode and (attempt % 20 == 0) then
			print(string.format("|cffff6600DOKI CANARY:|r Still waiting... (%.1fs elapsed). First:%s Middle:%s Last:%s",
				attempt * 0.5,
				tostring(firstReady),
				tostring(middleReady),
				tostring(lastReady)
			))
		end

		-- REMOVED: Timeout check - client data will be ready when it's ready
		-- The user initiated this by opening bags, so we wait until it's truly ready
	end

	-- Start the canary watcher, checking every 0.5 seconds
	canaryTicker = C_Timer.NewTicker(0.5, CheckClientDataReady)
end

-- ===== ENHANCED ATT SCANNING INTEGRATION =====
function DOKI:StartEnhancedATTScan(isLoginScan)
	-- Combat detection (keep this - it's still relevant)
	if UnitAffectingCombat("player") then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r ATT scan - Player in combat, waiting...")
		end

		local combatWaitFrame = CreateFrame("Frame")
		combatWaitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		combatWaitFrame:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_ENABLED" then
				if DOKI.db and DOKI.db.debugMode then
					print("|cffff69b4DOKI|r Combat ended - proceeding with ATT scan")
				end

				DOKI:StartEnhancedATTScan(isLoginScan)
				self:UnregisterAllEvents()
			end
		end)
		return
	end

	if DOKI.scanState.isScanInProgress then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Scan already in progress")
		end

		return
	end

	if DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Starting UNIFIED ATT scan (login: %s)", tostring(isLoginScan)))
	end

	-- Use unified item collection logic
	local allBagItems = self:GetAllBagItems()
	-- Filter for ATT mode and build scan queue
	local scanQueue = {}
	for _, itemData in ipairs(allBagItems) do
		if self:ShouldTrackItemInATTMode(itemData.itemID) then
			table.insert(scanQueue, itemData)
		end
	end

	if #scanQueue == 0 then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r No items to scan (unified logic found 0 trackable items)")
		end

		if isLoginScan then
			C_Timer.After(0.1, function()
				DOKI:CompleteEnhancedATTScan(false)
			end)
		end

		return
	end

	if DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r UNIFIED SCAN: Found %d total items, %d trackable for ATT",
			#allBagItems, #scanQueue))
	end

	-- Initialize scan state
	DOKI.scanState.isScanInProgress = true
	DOKI.scanState.isLoginScan = isLoginScan or false
	DOKI.scanState.scanStartTime = GetTime()
	DOKI.scanState.totalItems = #scanQueue
	DOKI.scanState.processedItems = 0
	-- Show progress UI for login scans
	if isLoginScan then
		InstallTooltipHooks()
		ShowProgressFrame()
		if DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Progress UI enabled - scanning %d items", #scanQueue))
		end
	end

	-- Process the queue - NO TIMEOUT ANYMORE since it's user-initiated
	local totalToProcess = #scanQueue
	for _, itemData in ipairs(scanQueue) do
		if GetATTStatusAsync then
			GetATTStatusAsync(itemData.itemID, itemData.itemLink,
				function(isCollected, hasOtherSources, isPartiallyCollected, debugInfo)
					-- Update progress
					DOKI.scanState.processedItems = (DOKI.scanState.processedItems or 0) + 1
					if DOKI.UpdateProgressFrame then
						DOKI:UpdateProgressFrame()
					end

					-- Debug logging
					if DOKI.db and DOKI.db.debugMode then
						local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
						local result = isCollected and "COLLECTED" or "NOT_COLLECTED"
						if isPartiallyCollected then result = result .. " (PARTIAL)" end

						print(string.format("|cff00ff00DOKI UNIFIED SUCCESS:|r %s -> %s", itemName, result))
					end

					-- Check for completion
					if DOKI.scanState.processedItems >= totalToProcess then
						if DOKI.db and DOKI.db.debugMode then
							print(string.format("|cff00ff00DOKI UNIFIED COMPLETE:|r %d/%d items processed",
								DOKI.scanState.processedItems, totalToProcess))
						end

						-- Complete the scan
						C_Timer.After(0.1, function()
							DOKI:CompleteEnhancedATTScan(false)
						end)
					end
				end)
		end
	end

	-- REMOVED: Safety timeout - no longer needed for user-initiated scans
	-- Players can take as long as they want before opening bags
end

function DOKI:CompleteEnhancedATTScan(isTimeout)
	if not DOKI.scanState.isScanInProgress then return end

	local elapsed = GetTime() - DOKI.scanState.scanStartTime
	local wasLoginScan = DOKI.scanState.isLoginScan
	if DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Two-Phase validated ATT scan complete - %.2fs%s",
			elapsed, isTimeout and " (TIMEOUT)" or ""))
	end

	-- Clean up progress UI
	C_Timer.After(0.1, function()
		HideProgressFrame()
		-- Reset scan state
		DOKI.scanState.isScanInProgress = false
		DOKI.scanState.isLoginScan = false
		DOKI.scanState.processedItems = 0
		DOKI.scanState.totalItems = 0
	end)
	-- Update last scan time for successful scans
	if wasLoginScan and not isTimeout then
		DOKI.db.lastFullScanTime = time()
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Two-Phase validated scan completed - timestamp updated")
		end
	end

	-- Register collection events after login scan
	if wasLoginScan then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r === TWO-PHASE SCAN COMPLETE - REGISTERING COLLECTION EVENTS ===")
		end

		if DOKI.RegisterCollectionEvents then
			DOKI:RegisterCollectionEvents()
		end
	end

	-- Show completion message
	if isTimeout then
		print("|cffff0000DOKI ERROR:|r Two-Phase validated scan timed out (this should not happen)")
	elseif wasLoginScan then
		print(string.format("|cff00ff00DOKI SUCCESS:|r Two-Phase validated login scan completed in %.1fs!", elapsed))
	end

	-- Set completion flags
	if wasLoginScan then
		C_Timer.After(0.2, function()
			DOKI.isInitialScanComplete = true
			DOKI.needsFullIndicatorRefresh = true
			if DOKI.db and DOKI.db.debugMode then
				print("|cff00ff00DOKI TWO-PHASE COMPLETION:|r Flags set after Two-Phase validated scan")
				print(string.format("|cff00ff00DOKI VERIFY:|r isInitialScanComplete=%s, needsFullIndicatorRefresh=%s",
					tostring(DOKI.isInitialScanComplete), tostring(DOKI.needsFullIndicatorRefresh)))
			end
		end)
	end

	-- Trigger UI update
	if DOKI.TriggerImmediateSurgicalUpdate then
		C_Timer.After(0.3, function()
			DOKI:TriggerImmediateSurgicalUpdate()
		end)
	end
end

-- ===== PHASE 1: ATT READY-STATE WATCHER =====
local function StartATTWatcher()
	if DOKI.db and DOKI.db.debugMode then
		print("|cffffd100DOKI PHASE 1:|r Starting ATT Ready-State Watcher (No Timeout - User Initiated)...")
	end

	local attempt = 0
	local watcherTicker = nil
	local function CheckATTReadyState()
		attempt = attempt + 1
		-- The definitive "ready" check
		if _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults then
			-- SUCCESS! ATT is ready.
			if watcherTicker then
				watcherTicker:Cancel()
				watcherTicker = nil
			end

			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cff00ff00DOKI PHASE 1 COMPLETE:|r ATT is ready after %d seconds", attempt))
			end

			-- START PHASE 2: Client Data Watcher (Canary Scan)
			DOKI:StartClientDataWatcher(function()
				-- This callback executes only after BOTH Phase 1 and Phase 2 succeed.
				if DOKI.db and DOKI.db.debugMode then
					print("|cffffd100DOKI:|r Waiting 3 seconds for UI to settle before starting scan...")
				end

				C_Timer.After(3, function()
					if DOKI.db and DOKI.db.debugMode then
						print("|cff00ff00DOKI:|r UI settled. Starting the login scan now.")
					end

					DOKI:StartEnhancedATTScan(true)
				end)
			end)
			return
		end

		-- Debug output every 10 seconds instead of 5 (less spam)
		if DOKI and DOKI.db and DOKI.db.debugMode and (attempt % 10 == 0) then
			print(string.format(
				"|cffff69b4DOKI PHASE 1:|r %d seconds elapsed, still waiting for AllTheThings.GetCachedSearchResults...",
				attempt))
		end

		-- REMOVED: Timeout check - ATT might take longer on some systems
		-- The scan will wait indefinitely until ATT is ready or player disables ATT mode
	end

	-- Start the watcher, checking once per second
	watcherTicker = C_Timer.NewTicker(1, CheckATTReadyState)
end

-- ===== CLEAN STARTUP FUNCTION =====
local function ProceedWithTwoPhaseStartup(isInitialLogin, isReloadingUi)
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r Proceeding with Two-Phase State-Driven startup")
	end

	-- Check if we need ATT functionality
	if DOKI and DOKI.db and DOKI.db.enabled and DOKI.db.attMode then
		if needsFullScan() then
			if DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ATT mode enabled and scan needed - starting Two-Phase State-Driven system")
			end

			-- Start the ATT watcher (Phase 1, which will trigger Phase 2 when ready)
			StartATTWatcher()
		else
			if DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ATT cache found - registering collection events without scan")
			end

			-- No scan needed, but we still need to register collection events
			C_Timer.After(1, function()
				if DOKI and DOKI.RegisterCollectionEvents then
					DOKI:RegisterCollectionEvents()
				end

				-- Set completion flags
				DOKI.isInitialScanComplete = true
				DOKI.needsFullIndicatorRefresh = false
			end)
		end
	else
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r ATT mode disabled or addon disabled - registering collection events")
		end

		-- ATT mode disabled, register collection events immediately
		C_Timer.After(1, function()
			if DOKI and DOKI.RegisterCollectionEvents then
				DOKI:RegisterCollectionEvents()
			end

			DOKI.isInitialScanComplete = true
			DOKI.needsFullIndicatorRefresh = false
		end)
	end
end

-- ===== COMBAT-SAFE WRAPPER =====
local combatWaitFrame = nil
local function HandleCombatSafeStartup(isInitialLogin, isReloadingUi)
	if UnitAffectingCombat("player") then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Player in combat - waiting for combat to end...")
		end

		if not combatWaitFrame then
			combatWaitFrame = CreateFrame("Frame")
			combatWaitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			combatWaitFrame:SetScript("OnEvent", function(self, event)
				if event == "PLAYER_REGEN_ENABLED" then
					if DOKI and DOKI.db and DOKI.db.debugMode then
						print("|cffff69b4DOKI|r Combat ended - proceeding with Two-Phase startup")
					end

					ProceedWithTwoPhaseStartup(isInitialLogin, isReloadingUi)
					self:UnregisterAllEvents()
					combatWaitFrame = nil
				end
			end)
		end
	else
		ProceedWithTwoPhaseStartup(isInitialLogin, isReloadingUi)
	end
end

-- ===== MAIN STARTUP FRAME =====
local twoPhaseStartupFrame = CreateFrame("Frame")
twoPhaseStartupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
twoPhaseStartupFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
	if event == "PLAYER_ENTERING_WORLD" and (isInitialLogin or isReloadingUi) then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Login detected - starting Two-Phase State-Driven Architecture")
		end

		HandleCombatSafeStartup(isInitialLogin, isReloadingUi)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end)
-- ===== INITIALIZATION =====
function DOKI:InitializeEnhancedATTSystem()
	if DOKI.db and DOKI.db.attMode then
		-- The Two-Phase startup frame handles everything automatically
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Enhanced ATT system with Two-Phase State-Driven Architecture initialized")
		end
	else
		-- ATT mode disabled - still need to register collection events for normal mode
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r ATT mode disabled - will register collection events immediately")
		end

		C_Timer.After(10, function() -- Give addon time to fully load
			if DOKI.RegisterCollectionEvents then
				DOKI:RegisterCollectionEvents()
			end
		end)
		-- Set initial scan complete flag for non-ATT mode
		DOKI.isInitialScanComplete = true
		DOKI.needsFullIndicatorRefresh = false -- No special refresh needed for non-ATT mode
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r ATT mode disabled - initial scan flag set to TRUE (no scan needed)")
		end
	end
end

-- ===== UTILITY FUNCTIONS FOR INTEGRATION =====
function DOKI:CheckATTStatus()
	if _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults then
		print("|cff00ff00DOKI:|r ATT Status: AllTheThings is ready and functional")
		return true
	elseif _G["AllTheThings"] then
		print("|cffffd100DOKI:|r ATT Status: AllTheThings loaded but GetCachedSearchResults not available")
		return false
	else
		print("|cffff0000DOKI:|r ATT Status: AllTheThings addon not found")
		return false
	end
end

function DOKI:GetATTWatcherStatus()
	-- Return whether the ATT watcher system is active
	return _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults and true or false
end

function DOKI:TestCanaryScan()
	-- Manual test function for the canary scan
	print("|cffff69b4DOKI|r === TESTING CANARY SCAN ===")
	self:StartClientDataWatcher(function()
		print("|cff00ff00DOKI CANARY TEST SUCCESS:|r Client data is ready!")
		print("|cffff69b4DOKI|r === END CANARY TEST ===")
	end)
end
