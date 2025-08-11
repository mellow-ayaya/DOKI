-- DOKI Enhanced ATT Scanning - The Definitive "ATT Ready-State Watcher" (Local Scope)
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

-- ===== THE DEFINITIVE ATT READY-STATE WATCHER (LOCAL SCOPE) =====
-- By declaring these functions and variables as 'local', we ensure they cannot
-- conflict with any other addon or any other part of your own code.
local function StartEnhancedATTScan(isLoginScan)
	-- This is a safe wrapper for the real DOKI function
	if DOKI and DOKI.StartEnhancedATTScan then
		DOKI:StartEnhancedATTScan(isLoginScan)
	else
		print("|cffff0000DOKI ERROR:|r StartEnhancedATTScan function not available")
	end
end

local attWatcherIsActive = false
local function StartATTWatcher()
	-- Safety check to ensure we don't start multiple watchers
	if attWatcherIsActive then return end

	attWatcherIsActive = true
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print("|cffffd100DOKI:|r Starting ATT Ready-State Watcher...")
	end

	local maxAttempts = 60 -- 60-second timeout to prevent infinite loops
	local attempt = 0
	local watcherTicker = nil
	local function CheckATTReadyState()
		attempt = attempt + 1
		-- === THE DEFINITIVE "READY" CHECK ===
		if _G["AllTheThings"] and _G["AllTheThings"].GetCachedSearchResults then
			-- SUCCESS! ATT is ready.
			if watcherTicker then
				watcherTicker:Cancel()
			end

			attWatcherIsActive = false
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print(string.format("|cff00ff00DOKI SUCCESS:|r ATT is ready after %d seconds. Proceeding with scan.", attempt))
			end

			-- === THE "FORCE-PRIME AND SCAN" SEQUENCE ===
			-- 1. Force-prime the WoW client's item data
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Opening bags to prime inventory data...")
			end

			OpenAllBags()
			-- 2. Wait one frame for the open command to process
			C_Timer.After(0, function()
				if DOKI and DOKI.db and DOKI.db.debugMode then
					print("|cffff69b4DOKI|r Closing bags...")
				end

				CloseAllBags()
				-- 3. Wait a fraction of a second to ensure the client has settled
				C_Timer.After(0.1, function()
					if DOKI and DOKI.db and DOKI.db.debugMode then
						print("|cffff69b4DOKI|r Starting enhanced ATT scan...")
					end

					-- 4. Execute the main blocking scan
					StartEnhancedATTScan(true)
				end)
			end)
			return
		end

		-- Debug output every 5 seconds to show progress
		if DOKI and DOKI.db and DOKI.db.debugMode and (attempt % 5 == 0) then
			print(string.format(
				"|cffff69b4DOKI|r ATT Watcher: %d seconds elapsed, still waiting for AllTheThings.GetCachedSearchResults...",
				attempt))
		end

		-- Check for timeout
		if attempt > maxAttempts then
			if watcherTicker then
				watcherTicker:Cancel()
			end

			attWatcherIsActive = false
			print(
				"|cffff0000DOKI ERROR:|r ATT Ready-State Watcher timed out after 60 seconds. ATT may not be loaded correctly.")
			-- Still register collection events even if ATT failed to load
			if DOKI and DOKI.RegisterCollectionEvents then
				C_Timer.After(1, function()
					DOKI:RegisterCollectionEvents()
				end)
			end
		end
	end

	-- Start the watcher, checking once per second
	watcherTicker = C_Timer.NewTicker(1, CheckATTReadyState)
end

-- DOKI UtilsATT.lua - Replace your existing startup frame with this working version
-- Simple combat detection function
local function IsInCombat()
	return UnitAffectingCombat("player") -- More reliable than InCombatLockdown for this purpose
end

-- Proceed with normal startup logic
local function ProceedWithStartup(isInitialLogin, isReloadingUi)
	if DOKI and DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r Proceeding with startup (combat ended)")
	end

	-- Check if we need ATT functionality
	if DOKI and DOKI.db and DOKI.db.enabled and DOKI.db.attMode then
		if needsFullScan() then
			if DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ATT mode enabled and scan needed - starting ATT watcher")
			end

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

			-- Set initial scan complete flag for non-ATT mode
			DOKI.isInitialScanComplete = true
			DOKI.needsFullIndicatorRefresh = false
			if DOKI and DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ATT mode disabled - initial scan flag set to TRUE (no scan needed)")
			end
		end)
	end
end

-- Combat wait frame (created only when needed)
local combatWaitFrame = nil
-- Handle combat detection
local function HandleCombatSafeStartup(isInitialLogin, isReloadingUi)
	if IsInCombat() then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Player in combat - waiting for combat to end...")
		end

		-- Create combat wait frame
		if not combatWaitFrame then
			combatWaitFrame = CreateFrame("Frame")
			combatWaitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			combatWaitFrame:SetScript("OnEvent", function(self, event)
				if event == "PLAYER_REGEN_ENABLED" then
					if DOKI and DOKI.db and DOKI.db.debugMode then
						print("|cffff69b4DOKI|r Combat ended - proceeding with startup")
					end

					ProceedWithStartup(isInitialLogin, isReloadingUi)
					-- Clean up
					self:UnregisterAllEvents()
					combatWaitFrame = nil
				end
			end)
		end
	else
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Player not in combat - proceeding immediately")
		end

		ProceedWithStartup(isInitialLogin, isReloadingUi)
	end
end

-- Main startup frame (replace your existing one with this)
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
startupFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
	if event == "PLAYER_ENTERING_WORLD" and (isInitialLogin or isReloadingUi) then
		if DOKI and DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Login detected - checking combat status")
		end

		HandleCombatSafeStartup(isInitialLogin, isReloadingUi)
		-- Unregister to prevent multiple triggers
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end)
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

-- ===== ENHANCED ATT SCANNING INTEGRATION =====
function DOKI:StartEnhancedATTScan(isLoginScan)
	if DOKI.scanState.isScanInProgress then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Scan already in progress")
		end

		return
	end

	-- Only show progress UI and block tooltips for login scans or when no cache exists
	local showProgressUI = isLoginScan or needsFullScan()
	if DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Starting enhanced ATT scan (login: %s, showUI: %s)",
			tostring(isLoginScan), tostring(showProgressUI)))
	end

	-- Collect all items to scan
	local scanQueue = {}
	for bagID = 0, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, numSlots do
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
					-- Check if we should track this item in ATT mode
					if DOKI:ShouldTrackItemInATTMode(itemInfo.itemID) then
						table.insert(scanQueue, {
							itemID = itemInfo.itemID,
							itemLink = itemInfo.hyperlink,
							bagID = bagID,
							slotID = slotID,
						})
					end
				end
			end
		end
	end

	if #scanQueue == 0 then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r No items to scan")
		end

		-- Even if no items to scan, we still need to register events
		if isLoginScan then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r No items to scan, but registering collection events")
			end

			-- Mark scan as complete and register events
			C_Timer.After(0.1, function()
				DOKI:CompleteEnhancedATTScan(false)
			end)
		end

		return
	end

	-- Initialize scan state
	DOKI.scanState.isScanInProgress = true
	DOKI.scanState.isLoginScan = isLoginScan or false
	DOKI.scanState.scanStartTime = GetTime()
	DOKI.scanState.totalItems = #scanQueue
	DOKI.scanState.processedItems = 0
	if showProgressUI then
		-- Install smart tooltip hooks to prevent user confusion while allowing our scanning
		InstallTooltipHooks()
		-- Show progress frame
		ShowProgressFrame()
		if DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Progress UI enabled with SMART tooltip blocking - scanning %d items",
				#scanQueue))
		end
	end

	-- Process the queue using existing ATT system
	for _, itemData in ipairs(scanQueue) do
		-- Add items to the existing ATT processing queue
		if GetATTStatusAsync then
			GetATTStatusAsync(itemData.itemID, itemData.itemLink,
				function(isCollected, hasOtherSources, isPartiallyCollected, debugInfo)
					-- Progress tracking is handled in ProcessNextATTInQueue in CollectionsATT.lua
				end)
		end
	end

	-- Safety timeout (60 seconds max)
	C_Timer.After(60, function()
		if DOKI.scanState.isScanInProgress then
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Scan timeout reached - forcing completion")
			end

			DOKI:CompleteEnhancedATTScan(true)
		end
	end)
end

function DOKI:CompleteEnhancedATTScan(isTimeout)
	if not DOKI.scanState.isScanInProgress then return end

	local elapsed = GetTime() - DOKI.scanState.scanStartTime
	local wasLoginScan = DOKI.scanState.isLoginScan
	if DOKI.db and DOKI.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Enhanced ATT scan complete - %.2fs, %d/%d items%s",
			elapsed, DOKI.scanState.processedItems, DOKI.scanState.totalItems,
			isTimeout and " (TIMEOUT)" or ""))
	end

	-- Update last scan time only for successful login scans
	if wasLoginScan and not isTimeout then
		DOKI.db.lastFullScanTime = time()
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Login scan completed - timestamp updated")
		end
	end

	-- Clean up progress UI
	HideProgressFrame()
	-- Reset scan state
	DOKI.scanState.isScanInProgress = false
	DOKI.scanState.isLoginScan = false
	DOKI.scanState.processedItems = 0
	DOKI.scanState.totalItems = 0
	-- ===== REGISTER COLLECTION EVENTS AFTER SCAN COMPLETION =====
	if wasLoginScan then
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r === LOGIN SCAN COMPLETE - REGISTERING COLLECTION EVENTS ===")
		end

		-- This is the key to the event registration architecture
		if DOKI.RegisterCollectionEvents then
			DOKI:RegisterCollectionEvents()
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r Collection events registered after login scan completion")
			end
		else
			if DOKI.db and DOKI.db.debugMode then
				print("|cffff69b4DOKI|r ERROR: RegisterCollectionEvents function not available!")
			end
		end
	end

	-- Show completion message
	if isTimeout then
		print("|cffff69b4DOKI|r Scan incomplete. Use /doki scan to retry.")
	elseif wasLoginScan then
		print(string.format("|cffff69b4DOKI|r Login scan completed in %.1fs. Collection events now active!", elapsed))
	end

	-- Trigger UI update
	if DOKI.TriggerImmediateSurgicalUpdate then
		C_Timer.After(0.1, function()
			DOKI:TriggerImmediateSurgicalUpdate()
		end)
	end

	-- Force set the flags regardless of other logic
	if wasLoginScan then
		-- Small delay to ensure all other completion logic has run
		C_Timer.After(0.1, function()
			-- Explicitly set both flags
			DOKI.isInitialScanComplete = true
			DOKI.needsFullIndicatorRefresh = true
			if DOKI.db and DOKI.db.debugMode then
				print("|cff00ff00DOKI EXPLICIT FIX:|r Flags force-set after login scan completion")
				print(string.format("|cff00ff00DOKI VERIFY:|r isInitialScanComplete=%s, needsFullIndicatorRefresh=%s",
					tostring(DOKI.isInitialScanComplete), tostring(DOKI.needsFullIndicatorRefresh)))
			end
		end)
	end
end

-- ===== INITIALIZATION =====
function DOKI:InitializeEnhancedATTSystem()
	if DOKI.db and DOKI.db.attMode then
		-- The local startup frame handles everything automatically
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Enhanced ATT system with local scope ATT Ready-State Watcher initialized")
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
		-- ===== IMPORTANT: Set initial scan complete flag for non-ATT mode =====
		-- Since no ATT scan is needed, surgical updates can start immediately
		DOKI.isInitialScanComplete = true
		DOKI.needsFullIndicatorRefresh = false -- No special refresh needed for non-ATT mode
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r ATT mode disabled - initial scan flag set to TRUE (no scan needed)")
		end
	end
end

-- ===== UTILITY FUNCTIONS FOR INTEGRATION =====
-- Expose some functions to the DOKI namespace for compatibility and testing
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

function DOKI:TestATTWatcher()
	print("|cffff69b4DOKI|r Testing local scope ATT watcher system...")
	if attWatcherIsActive then
		print("|cffffd100DOKI:|r Watcher already active")
	else
		StartATTWatcher()
	end
end

function DOKI:GetATTWatcherStatus()
	return attWatcherIsActive
end
