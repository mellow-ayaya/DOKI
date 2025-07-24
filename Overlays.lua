-- DOKI Overlays - Universal Scanning Version
local addonName, DOKI = ...
-- Overlay management
local overlayIndex = 1
-- ===== OVERLAY POOL MANAGEMENT =====
-- Get or create an overlay from the pool
function DOKI:GetOverlay()
	local overlay = table.remove(self.overlayPool)
	if not overlay then
		overlay = self:CreateOverlay()
	end

	return overlay
end

-- Return overlay to pool
function DOKI:ReleaseOverlay(overlay)
	if not overlay then return end

	overlay:Hide()
	overlay:SetParent(nil)
	overlay:ClearAllPoints()
	-- Clean up references
	for overlayKey, activeOverlay in pairs(self.activeOverlays) do
		if activeOverlay == overlay then
			self.activeOverlays[overlayKey] = nil
			break
		end
	end

	table.insert(self.overlayPool, overlay)
end

-- Create new overlay frame
function DOKI:CreateOverlay()
	local overlay = CreateFrame("Frame", "DOKIOverlay" .. overlayIndex)
	overlayIndex = overlayIndex + 1
	-- Create text element
	overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	overlay.text:SetPoint("CENTER")
	overlay.text:SetText("D")
	overlay.text:SetTextColor(1, 0.41, 0.71) -- Default pink color
	overlay.text:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
	-- Make overlay click-through
	overlay:EnableMouse(false)
	overlay:SetFrameLevel(1000) -- High frame level to appear on top
	-- Function to set color
	overlay.SetColor = function(self, r, g, b)
		self.text:SetTextColor(r, g, b)
	end
	return overlay
end

-- ===== OVERLAY MANAGEMENT FUNCTIONS =====
-- Clear all overlays
function DOKI:ClearAllOverlays()
	for overlayKey, overlay in pairs(self.activeOverlays) do
		self:ReleaseOverlay(overlay)
	end

	wipe(self.activeOverlays)
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r All overlays cleared")
	end
end

-- Clear overlays by type
function DOKI:ClearOverlaysByType(overlayType)
	local count = 0
	for overlayKey, overlay in pairs(self.activeOverlays) do
		if string.match(overlayKey, "^" .. overlayType .. "_") then
			self:ReleaseOverlay(overlay)
			self.activeOverlays[overlayKey] = nil
			count = count + 1
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Cleared %d %s overlays", count, overlayType))
	end

	return count
end

-- Clear universal overlays specifically
function DOKI:ClearUniversalOverlays()
	return self:ClearOverlaysByType("universal")
end

-- ===== INITIALIZATION =====
-- Initialize the overlay system
function DOKI:InitializeOverlaySystem()
	-- Initialize overlay pool and active overlays if needed
	if not self.overlayPool then
		self.overlayPool = {}
	end

	if not self.activeOverlays then
		self.activeOverlays = {}
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Overlay system initialized")
	end
end

-- ===== LEGACY COMPATIBILITY FUNCTIONS =====
-- These functions are kept for compatibility but now use the universal system
-- Legacy: Update all overlays (now triggers universal scan)
function DOKI:UpdateAllOverlays()
	if not (self.db and self.db.enabled) then return end

	if self.UniversalItemScan then
		self:UniversalItemScan()
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Legacy UpdateAllOverlays called - triggered universal scan")
	end
end

-- Legacy: Update merchant overlays (now triggers universal scan)
function DOKI:UpdateMerchantOverlays()
	if not (self.db and self.db.enabled) then return end

	if self.UniversalItemScan then
		self:UniversalItemScan()
	end

	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Legacy UpdateMerchantOverlays called - triggered universal scan")
	end
end

-- Legacy: Clear bag overlays (now clears universal overlays)
function DOKI:ClearBagOverlays()
	-- In universal system, we clear all universal overlays since we can't distinguish bag vs other types
	self:ClearUniversalOverlays()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Legacy ClearBagOverlays called - cleared universal overlays")
	end
end

-- Legacy: Clear merchant overlays (now clears universal overlays)
function DOKI:ClearMerchantOverlays()
	-- In universal system, we clear all universal overlays since we can't distinguish merchant vs other types
	self:ClearUniversalOverlays()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Legacy ClearMerchantOverlays called - cleared universal overlays")
	end
end

-- ===== DIAGNOSTIC FUNCTIONS =====
-- Get overlay statistics
function DOKI:GetOverlayStats()
	local stats = {
		totalActive = 0,
		byType = {},
	}
	for overlayKey, overlay in pairs(self.activeOverlays) do
		stats.totalActive = stats.totalActive + 1
		-- Extract type from key
		local overlayType = overlayKey:match("^([^_]+)_") or "unknown"
		if not stats.byType[overlayType] then
			stats.byType[overlayType] = 0
		end

		stats.byType[overlayType] = stats.byType[overlayType] + 1
	end

	return stats
end

-- Debug overlay information
function DOKI:DebugOverlays()
	local stats = self:GetOverlayStats()
	print(string.format("|cffff69b4DOKI|r === OVERLAY DEBUG ==="))
	print(string.format("Total active overlays: %d", stats.totalActive))
	print(string.format("Overlays in pool: %d", #self.overlayPool))
	if next(stats.byType) then
		print("Overlays by type:")
		for overlayType, count in pairs(stats.byType) do
			print(string.format("  %s: %d", overlayType, count))
		end
	end

	-- Show some example overlay keys
	local count = 0
	for overlayKey, overlay in pairs(self.activeOverlays) do
		if count < 5 then -- Show first 5 as examples
			local parent = overlay:GetParent()
			local parentName = parent and (parent:GetName() or tostring(parent)) or "no parent"
			print(string.format("  %s -> %s", overlayKey, parentName))
			count = count + 1
		end
	end

	if stats.totalActive > 5 then
		print(string.format("  ... and %d more", stats.totalActive - 5))
	end

	print("|cffff69b4DOKI|r === END OVERLAY DEBUG ===")
end

-- Test overlay creation
function DOKI:TestOverlayCreation()
	print("|cffff69b4DOKI|r Testing overlay creation...")
	-- Create a test overlay on UIParent
	local testOverlay = self:GetOverlay()
	testOverlay:SetParent(UIParent)
	testOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	testOverlay:SetSize(50, 50)
	testOverlay:SetColor(1, 0, 0) -- Red for test
	testOverlay:Show()
	-- Store it with a test key
	self.activeOverlays["test_overlay"] = testOverlay
	print("|cffff69b4DOKI|r Created test overlay in center of screen (red D)")
	print("|cffff69b4DOKI|r Use /doki clear to remove it")
end

-- Validate all active overlays
function DOKI:ValidateOverlays()
	local validCount = 0
	local invalidCount = 0
	local toRemove = {}
	for overlayKey, overlay in pairs(self.activeOverlays) do
		if overlay and overlay:IsShown() then
			local parent = overlay:GetParent()
			if parent and parent:IsVisible() then
				validCount = validCount + 1
			else
				-- Parent is not visible, mark for removal
				table.insert(toRemove, overlayKey)
				invalidCount = invalidCount + 1
			end
		else
			-- Overlay is not shown or is nil, mark for removal
			table.insert(toRemove, overlayKey)
			invalidCount = invalidCount + 1
		end
	end

	-- Remove invalid overlays
	for _, overlayKey in ipairs(toRemove) do
		local overlay = self.activeOverlays[overlayKey]
		if overlay then
			self:ReleaseOverlay(overlay)
		else
			self.activeOverlays[overlayKey] = nil
		end
	end

	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Overlay validation: %d valid, %d invalid (removed)",
			validCount, invalidCount))
	end

	return validCount, invalidCount
end

-- ===== ADVANCED OVERLAY FUNCTIONS =====
-- Create overlay with advanced options
function DOKI:CreateAdvancedOverlay(frame, options)
	if not frame or not frame:IsVisible() then return nil end

	local overlay = self:GetOverlay()
	overlay:SetParent(frame)
	-- Apply positioning options
	if options.allPoints then
		overlay:SetAllPoints(frame)
	elseif options.size then
		overlay:SetSize(options.size.width or 32, options.size.height or 32)
		overlay:SetPoint(options.point or "CENTER", frame, options.relativePoint or "CENTER",
			options.xOffset or 0, options.yOffset or 0)
	else
		overlay:SetAllPoints(frame)
	end

	-- Apply color options
	if options.color then
		overlay:SetColor(options.color.r or 1, options.color.g or 0.41, options.color.b or 0.71)
	elseif options.showYellowD then
		overlay:SetColor(1, 1, 0)     -- Yellow
	else
		overlay:SetColor(1, 0.41, 0.71) -- Pink
	end

	-- Apply text options
	if options.text then
		overlay.text:SetText(options.text)
	end

	if options.fontSize then
		overlay.text:SetFont("Fonts\\FRIZQT__.TTF", options.fontSize, "OUTLINE")
	end

	-- Apply frame level
	if options.frameLevel then
		overlay:SetFrameLevel(options.frameLevel)
	end

	overlay:Show()
	return overlay
end

-- Batch overlay operations
function DOKI:BatchOverlayOperation(operation, overlayType)
	local count = 0
	local pattern = overlayType and ("^" .. overlayType .. "_") or nil
	for overlayKey, overlay in pairs(self.activeOverlays) do
		if not pattern or string.match(overlayKey, pattern) then
			if operation == "hide" then
				overlay:Hide()
				count = count + 1
			elseif operation == "show" then
				overlay:Show()
				count = count + 1
			elseif operation == "remove" then
				self:ReleaseOverlay(overlay)
				self.activeOverlays[overlayKey] = nil
				count = count + 1
			end
		end
	end

	if self.db and self.db.debugMode then
		local typeStr = overlayType and (" " .. overlayType) or ""
		print(string.format("|cffff69b4DOKI|r Batch %s operation on%s overlays: %d affected",
			operation, typeStr, count))
	end

	return count
end

-- Hide all overlays (without removing them)
function DOKI:HideAllOverlays()
	return self:BatchOverlayOperation("hide")
end

-- Show all overlays
function DOKI:ShowAllOverlays()
	return self:BatchOverlayOperation("show")
end

-- Performance monitoring
function DOKI:GetOverlayPerformanceInfo()
	local info = {
		overlayPoolSize = #self.overlayPool,
		activeOverlays = 0,
		memoryEstimate = 0,
	}
	for _ in pairs(self.activeOverlays) do
		info.activeOverlays = info.activeOverlays + 1
	end

	-- Rough memory estimate (each overlay is ~1KB)
	info.memoryEstimate = (info.overlayPoolSize + info.activeOverlays) * 1024
	return info
end
