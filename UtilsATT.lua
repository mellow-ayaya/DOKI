-- DOKI Enhanced ATT Scanning - Login Scan with Progress UI and Tooltip Blocking
-- THIS FILE: UtilsATT.lua
-- Add this line to DOKI.toc after CollectionsATT.lua:
-- UtilsATT.lua
local addonName, DOKI = ...
-- ===== SCAN STATE MANAGEMENT =====
DOKI.scanState = {
	isScanInProgress = false,
	isLoginScan = false,
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

-- ===== TOOLTIP BLOCKING SYSTEM =====
local tooltipTypes = {
	"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
	"ShoppingTooltip2", "WorldMapTooltip", "PerksProgramTooltip",
}
local function InstallTooltipHooks()
	if DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r Installing tooltip hooks...")
	end

	for _, tooltipName in ipairs(tooltipTypes) do
		local tooltip = _G[tooltipName]
		if tooltip and tooltip.Show then
			if not DOKI.scanState.tooltipHooks[tooltipName] then
				hooksecurefunc(tooltip, "Show", function(self)
					if DOKI.scanState and DOKI.scanState.isScanInProgress then
						if self and self.Hide then
							self:Hide()
						end
					end
				end)
				DOKI.scanState.tooltipHooks[tooltipName] = true
				if DOKI.db and DOKI.db.debugMode then
					print(string.format("|cffff69b4DOKI|r Hooked %s", tooltipName))
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

		return
	end

	-- Initialize scan state
	DOKI.scanState.isScanInProgress = true
	DOKI.scanState.isLoginScan = isLoginScan or false
	DOKI.scanState.scanStartTime = GetTime()
	DOKI.scanState.totalItems = #scanQueue
	DOKI.scanState.processedItems = 0
	if showProgressUI then
		-- Install tooltip hooks to prevent user confusion
		InstallTooltipHooks()
		-- Show progress frame
		ShowProgressFrame()
		if DOKI.db and DOKI.db.debugMode then
			print(string.format("|cffff69b4DOKI|r Progress UI enabled - scanning %d items", #scanQueue))
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

	-- Safety timeout (11 seconds max)
	C_Timer.After(11, function()
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
	-- Show completion message
	if isTimeout then
		print("|cffff69b4DOKI|r Scan incomplete. Use /doki scan to retry.")
	elseif wasLoginScan then
		print(string.format("|cffff69b4DOKI|r Login scan completed in %.1fs. Ready to use!", elapsed))
	end

	-- Trigger UI update
	if DOKI.TriggerImmediateSurgicalUpdate then
		C_Timer.After(0.1, function()
			DOKI:TriggerImmediateSurgicalUpdate()
		end)
	end
end

-- ===== LOGIN TRIGGER SYSTEM =====
function DOKI:SetupLoginScanSystem()
	-- Hook PLAYER_ENTERING_WORLD for login detection
	if not DOKI.loginEventFrame then
		DOKI.loginEventFrame = CreateFrame("Frame")
		DOKI.loginEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		DOKI.loginEventFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
			-- Only trigger on initial login, not on loading screens or zone changes
			if event == "PLAYER_ENTERING_WORLD" and (isInitialLogin or isReloadingUi) then
				-- Small delay to ensure everything is loaded
				C_Timer.After(2, function()
					if DOKI.db and DOKI.db.enabled and DOKI.db.attMode then
						if needsFullScan() then
							if DOKI.db and DOKI.db.debugMode then
								print("|cffff69b4DOKI|r Login detected - starting full ATT scan")
							end

							DOKI:StartEnhancedATTScan(true)
						else
							if DOKI.db and DOKI.db.debugMode then
								print("|cffff69b4DOKI|r Login detected - ATT cache found, no scan needed")
							end
						end
					end
				end)
			end
		end)
	end

	if DOKI.db and DOKI.db.debugMode then
		print("|cffff69b4DOKI|r Login scan system initialized")
	end
end

-- ===== INITIALIZATION =====
function DOKI:InitializeEnhancedATTSystem()
	if DOKI.db and DOKI.db.attMode then
		self:SetupLoginScanSystem()
		if DOKI.db and DOKI.db.debugMode then
			print("|cffff69b4DOKI|r Enhanced ATT system with login scanning initialized")
		end
	end
end
