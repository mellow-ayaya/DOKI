-- DOKI Utils - Universal Scanning Version
local addonName, DOKI = ...
-- Initialize storage
DOKI.currentItems = DOKI.currentItems or {}
DOKI.textureCache = DOKI.textureCache or {}
DOKI.foundFramesThisScan = {}
-- ===== UNIVERSAL ITEM SCANNING SYSTEM =====
-- Main universal scanner that finds and overlays items immediately
function DOKI:UniversalItemScan()
	if not self.db or not self.db.enabled then return 0 end

	local overlayCount = 0
	local scannedFrames = {}
	self.foundFramesThisScan = {}
	-- Reset debug counters for fresh output each scan
	self.filterDebugCount = 0
	self.extractDebugCount = 0
	-- Add scan limits to prevent performance issues
	self.scanLimits = {
		maxFrames = 1000, -- Maximum frames to scan in one pass
		scannedCount = 0,
		startTime = GetTime(),
	}
	-- SPECIFIC SCANNING: Check merchant frames directly if merchant is open
	if MerchantFrame and MerchantFrame:IsVisible() then
		overlayCount = overlayCount + self:ScanMerchantFramesDirectly()
	end

	-- SPECIFIC SCANNING: Check bag frames directly if any bags are open
	overlayCount = overlayCount + self:ScanBagFramesDirectly()
	-- GENERAL SCANNING: Scan all visible frames starting from UIParent
	overlayCount = overlayCount + self:ScanFrameTreeForItems(UIParent, scannedFrames, 0)
	local scanDuration = GetTime() - self.scanLimits.startTime
	if self.db and self.db.debugMode then
		print(string.format("|cffff69b4DOKI|r Universal scan: %d overlays, %d frames scanned in %.2fs, %d items found",
			overlayCount, self.scanLimits.scannedCount, scanDuration, #self.foundFramesThisScan))
		-- Show some examples of what was scanned
		if #self.foundFramesThisScan == 0 then
			print("|cffff69b4DOKI|r No items found - detailed extraction debug above")
		end
	end

	return overlayCount
end

-- Directly scan merchant frames (bypasses recursive traversal issues)
function DOKI:ScanMerchantFramesDirectly()
	local overlayCount = 0
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Scanning merchant frames directly...")
	end

	for i = 1, 10 do
		local buttonName = "MerchantItem" .. i .. "ItemButton"
		local button = _G[buttonName]
		if button and button:IsVisible() then
			local itemData = self:ExtractItemFromAnyFrame(button)
			if itemData then
				overlayCount = overlayCount + self:CreateUniversalOverlay(button, itemData)
				-- Store for debugging
				table.insert(self.foundFramesThisScan, {
					frame = button,
					frameName = buttonName,
					itemData = itemData,
				})
				if self.db and self.db.debugMode then
					local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
					print(string.format("|cffff69b4DOKI|r Direct merchant scan: %s (ID: %d) in %s",
						itemName, itemData.itemID, buttonName))
				end
			end
		end
	end

	return overlayCount
end

-- Directly scan bag frames (ElvUI and Blizzard)
function DOKI:ScanBagFramesDirectly()
	local overlayCount = 0
	-- Scan ElvUI bags if ElvUI is active
	if ElvUI then
		local E = ElvUI[1]
		if E then
			local B = E:GetModule("Bags", true)
			if B and (B.BagFrame and B.BagFrame:IsShown()) then
				if self.db and self.db.debugMode then
					print("|cffff69b4DOKI|r Scanning ElvUI bags directly...")
				end

				local elvUIItemsFound = 0
				for bagID = 0, NUM_BAG_SLOTS do
					local numSlots = C_Container.GetContainerNumSlots(bagID)
					if numSlots and numSlots > 0 then
						for slotID = 1, numSlots do
							-- Try multiple ElvUI button naming patterns
							local possibleNames = {
								string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
								string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
								string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
								string.format("ElvUI_ContainerFrameBag%dSlot%dArea", bagID, slotID),
							}
							for _, elvUIButtonName in ipairs(possibleNames) do
								local elvUIButton = _G[elvUIButtonName]
								if elvUIButton and elvUIButton:IsVisible() then
									-- Check if this button has an item
									local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
									if itemInfo and itemInfo.itemID then
										local itemData = self:ExtractItemFromAnyFrame(elvUIButton)
										if itemData then
											overlayCount = overlayCount + self:CreateUniversalOverlay(elvUIButton, itemData)
											table.insert(self.foundFramesThisScan, {
												frame = elvUIButton,
												frameName = elvUIButtonName,
												itemData = itemData,
											})
											elvUIItemsFound = elvUIItemsFound + 1
											if self.db and self.db.debugMode and elvUIItemsFound <= 3 then
												local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
												print(string.format("|cffff69b4DOKI|r ElvUI direct scan: %s (ID: %d) in %s",
													itemName, itemData.itemID, elvUIButtonName))
											end
										end
									end

									break -- Found a working pattern, no need to try others
								end
							end
						end
					end
				end

				if self.db and self.db.debugMode then
					print(string.format("|cffff69b4DOKI|r ElvUI direct scan found %d items", elvUIItemsFound))
				end
			else
				if self.db and self.db.debugMode then
					print("|cffff69b4DOKI|r ElvUI bags not visible or module not found")
					if B then
						print(string.format("|cffff69b4DOKI|r BagFrame exists: %s, shown: %s",
							B.BagFrame and "yes" or "no",
							B.BagFrame and B.BagFrame:IsShown() and "yes" or "no"))
					end
				end
			end
		end
	end

	-- Scan Blizzard bags
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		if self.db and self.db.debugMode then
			print("|cffff69b4DOKI|r Scanning Blizzard combined bags directly...")
		end

		if ContainerFrameCombinedBags.EnumerateValidItems then
			for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
				if itemButton and itemButton:IsVisible() then
					local itemData = self:ExtractItemFromAnyFrame(itemButton)
					if itemData then
						overlayCount = overlayCount + self:CreateUniversalOverlay(itemButton, itemData)
						table.insert(self.foundFramesThisScan, {
							frame = itemButton,
							frameName = itemButton:GetName() or "CombinedBagItem",
							itemData = itemData,
						})
					end
				end
			end
		end
	end

	return overlayCount
end

-- Recursively scan frame tree for item icons
function DOKI:ScanFrameTreeForItems(frame, scannedFrames, depth)
	-- Enhanced frame validation and depth limiting
	if not frame or depth > 10 then return 0 end -- Reduced max depth from 15 to 10

	-- Check scan limits
	if self.scanLimits and self.scanLimits.scannedCount >= self.scanLimits.maxFrames then
		return 0
	end

	-- Check if this is a valid frame object with IsVisible method
	if type(frame) ~= "table" or not frame.IsVisible then return 0 end

	-- Safe IsVisible check with pcall
	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Increment scan counter
	if self.scanLimits then
		self.scanLimits.scannedCount = self.scanLimits.scannedCount + 1
	end

	-- Avoid scanning same frame twice
	local frameAddr = tostring(frame)
	if scannedFrames[frameAddr] then return 0 end

	scannedFrames[frameAddr] = true
	-- Skip certain frame types that are unlikely to contain items
	local frameName = ""
	local nameSuccess, name = pcall(frame.GetName, frame)
	if nameSuccess and name then
		frameName = name
		-- Only skip frames with obvious non-item patterns
		if self:ShouldSkipFrame(frameName) then
			return 0
		end
	end

	-- Note: We don't skip unnamed frames here anymore - let ExtractItemFromAnyFrame handle that
	local overlayCount = 0
	-- Check if this frame contains an item
	local itemData = self:ExtractItemFromAnyFrame(frame)
	if itemData then
		overlayCount = overlayCount + self:CreateUniversalOverlay(frame, itemData)
		-- Store for debugging
		table.insert(self.foundFramesThisScan, {
			frame = frame,
			frameName = frame:GetName() or tostring(frame),
			itemData = itemData,
		})
	end

	-- Safely scan all children
	local success, numChildren = pcall(frame.GetNumChildren, frame)
	if success and numChildren and numChildren > 0 then
		for i = 1, numChildren do
			local success2, child = pcall(select, i, frame:GetChildren())
			if success2 and child and type(child) == "table" then
				overlayCount = overlayCount + self:ScanFrameTreeForItems(child, scannedFrames, depth + 1)
			end
		end
	end

	return overlayCount
end

-- Determine if a frame should be skipped during scanning
function DOKI:ShouldSkipFrame(frameName)
	if not frameName or frameName == "" then
		-- Skip frames without proper names (usually internal elements)
		return true
	end

	-- Skip frames with generic table names (internal objects)
	if frameName:match("^table:") then return true end

	-- Skip frames that are clearly not item-related
	local skipPatterns = {
		"Chat", "Minimap", "Menu", "Dialog", "Tooltip", "EditBox",
		"ScrollFrame", "Slider", "CheckButton", "RadioButton",
		"Communities", "Guild", "Social", "Friends", "Whisper",
		"WorldMap", "Calendar", "Achievement", "Statistics",
		"Video", "Audio", "Interface", "Options", "Settings",
		"Help", "Tutorial", "Binding", "Macro", "LFG", "LFD",
		"PVP", "Honor", "Arena", "Battleground", "Cursor",
		"DropDown", "PopUp", "StatusBar", "ProgressBar",
		"Buff", "Debuff", "Aura", "Temp", "Cache", "Pool",
		"ElvUIPlayerBuffs", "ElvUIPlayerDebuffs", -- ElvUI buff/debuff frames
		"Threat", "Cast", "Timer", "Cooldown",

		-- Quest-related frames that are NOT item buttons
		"QuestLog", "QuestFrame", "QuestObjective", "QuestDetail",
		"QuestProgress", "QuestComplete", "QuestText", "QuestTitle",
		"ObjectiveTracker", "AllObjectives", "Scenario",
	}
	for _, pattern in ipairs(skipPatterns) do
		if frameName:find(pattern) then
			return true
		end
	end

	-- Skip merchant item frames that aren't the actual item button
	-- We want "MerchantItem1ItemButton" but not "MerchantItem1"
	if frameName:match("^MerchantItem%d+$") then
		return true -- Skip the parent frame, we only want the ItemButton
	end

	return false
end

-- Determine if a frame is likely to contain an actual item icon
function DOKI:IsLikelyItemFrame(frameName)
	if not frameName or frameName == "" then return false end

	-- Skip frames with generic table names (internal objects)
	if frameName:match("^table:") then return false end

	-- EXCLUDE quest log and objective frames specifically
	local questExclusions = {
		"QuestLog", "QuestFrame", "QuestObjective", "QuestDetail",
		"QuestProgress", "QuestComplete", "QuestText", "QuestTitle",
		"ObjectiveTracker", "AllObjectives", "Scenario",
	}
	for _, exclusion in ipairs(questExclusions) do
		if frameName:find(exclusion) then
			return false
		end
	end

	-- More specific whitelist of frame patterns that are likely to contain actual item icons
	local itemFramePatterns = {
		-- Blizzard UI patterns (more specific)
		"ContainerFrame.*Item", -- Container/bag items
		"MerchantItem.*Button", -- Merchant item buttons
		".*ItemButton$",      -- Frames ending in ItemButton
		".*LootButton",       -- Loot items
		"BankFrameItem",      -- Bank items
		"GuildBankFrame.*Item", -- Guild bank
		"ActionButton%d+$",   -- Action bar items (specific pattern)
		"TradeFrame.*Item",   -- Trade window
		"MailFrame.*Item",    -- Mail
		"AuctionFrame.*Item", -- Auction house

		-- Quest-specific item buttons (not quest log text!)
		"QuestItem.*Button$", -- Quest item reward BUTTONS (not quest text)
		"QuestReward.*Button$", -- Quest reward buttons
		"QuestChoice.*Button$", -- Quest choice buttons

		-- ElvUI patterns (fixed and more flexible)
		"ElvUI_ContainerFrame", -- Any ElvUI container frame part
		"ElvUI.*Bag.*Slot",   -- ElvUI bag slots (broader pattern)
		"ElvUI.*Hash$",       -- ElvUI frames ending in Hash

		-- Dungeon Journal and Adventure Guide (actual item buttons)
		"EncounterJournal.*Item.*Button",
		"AdventureMap.*Reward.*Button",
	}
	for _, pattern in ipairs(itemFramePatterns) do
		if frameName:match(pattern) then
			if self.db and self.db.debugMode and self.filterDebugCount < 3 then
				print(string.format("|cffff69b4DOKI|r Frame %s passed filter (pattern: %s)", frameName, pattern))
				self.filterDebugCount = self.filterDebugCount + 1
			end

			return true
		end
	end

	return false
end

-- Enhanced item extraction that works with any frame type
function DOKI:ExtractItemFromAnyFrame(frame)
	-- Enhanced frame validation
	if not frame or type(frame) ~= "table" then return nil end

	-- Check if frame is still visible (it might have been hidden during scanning)
	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return nil end

	-- Safely get frame name
	local frameName = ""
	local success, name = pcall(frame.GetName, frame)
	if success and name then
		frameName = name
	end

	-- Debug: Show what frames we're examining (limit output)
	if self.db and self.db.debugMode and not self.extractDebugCount then
		self.extractDebugCount = 0
	end

	-- For debugging - let's be less restrictive initially
	local passedFilter = true
	if frameName ~= "" then
		-- Only apply filtering if we have a frame name
		passedFilter = self:IsLikelyItemFrame(frameName)
		if self.db and self.db.debugMode and self.extractDebugCount < 5 then
			print(string.format("|cffff69b4DOKI|r Examining frame: %s (filter: %s)",
				frameName, passedFilter and "PASS" or "FAIL"))
			self.extractDebugCount = self.extractDebugCount + 1
		end
	end

	-- If we don't have a proper frame name, try to extract anyway
	-- but be more cautious about it
	if not passedFilter and frameName == "" then
		-- For unnamed frames, only proceed if they have clear item methods
		if not (frame.GetItemID or frame.GetItem or frame.GetBagID) then
			return nil
		end
	elseif not passedFilter then
		-- For named frames that don't pass filter, skip them
		return nil
	end

	local itemID, itemLink
	-- Debug: Track extraction attempts
	local extractionAttempts = {}
	-- Method 1: Direct item methods (with error handling)
	if frame.GetItemID then
		local success, id = pcall(frame.GetItemID, frame)
		if success and id then
			itemID = id
			table.insert(extractionAttempts, string.format("GetItemID: %s", tostring(id)))
		else
			table.insert(extractionAttempts, "GetItemID: failed")
		end
	end

	if not itemID and frame.GetItem then
		local success, item = pcall(frame.GetItem, frame)
		if success and item then
			if type(item) == "number" then
				itemID = item
				table.insert(extractionAttempts, string.format("GetItem(num): %s", tostring(item)))
			elseif type(item) == "string" then
				itemLink = item
				itemID = self:GetItemID(item)
				table.insert(extractionAttempts, string.format("GetItem(str): %s -> %s", item, tostring(itemID)))
			end
		else
			table.insert(extractionAttempts, "GetItem: failed")
		end
	end

	-- Method 2: Frame properties
	if not itemID then
		if frame.itemID then
			itemID = frame.itemID
			table.insert(extractionAttempts, string.format("frame.itemID: %s", tostring(frame.itemID)))
		end

		if frame.id then
			itemID = frame.id
			table.insert(extractionAttempts, string.format("frame.id: %s", tostring(frame.id)))
		end
	end

	if not itemLink then
		if frame.itemLink then
			itemLink = frame.itemLink
			itemID = itemID or self:GetItemID(frame.itemLink)
			table.insert(extractionAttempts, string.format("frame.itemLink: %s -> %s", frame.itemLink, tostring(itemID)))
		end

		if frame.link then
			itemLink = frame.link
			itemID = itemID or self:GetItemID(frame.link)
			table.insert(extractionAttempts, string.format("frame.link: %s -> %s", frame.link, tostring(itemID)))
		end
	end

	-- Method 3: Container/Bag items
	if not itemID and (frame.GetBagID or frameName:match("ContainerFrame") or frameName:match("Bag")) then
		local bagItemID = self:ExtractBagItemID(frame)
		if bagItemID then
			itemID = bagItemID
			table.insert(extractionAttempts, string.format("ExtractBagItemID: %s", tostring(bagItemID)))
		else
			table.insert(extractionAttempts, "ExtractBagItemID: failed")
		end
	end

	-- Method 4: Merchant items
	if not itemID and frameName:match("MerchantItem") then
		local merchantItemID = self:ExtractMerchantItemID(frame, frameName)
		if merchantItemID then
			itemID = merchantItemID
			table.insert(extractionAttempts, string.format("ExtractMerchantItemID: %s", tostring(merchantItemID)))
		else
			table.insert(extractionAttempts, "ExtractMerchantItemID: failed")
		end
	end

	-- Method 5: Quest items (only for actual quest reward buttons, not quest text)
	if not itemID and (frameName:match("QuestItem.*Button") or frameName:match("QuestReward.*Button") or frameName:match("QuestChoice.*Button") or frame.questID) then
		local questItemID = self:ExtractQuestItemID(frame)
		if questItemID then
			itemID = questItemID
			table.insert(extractionAttempts, string.format("ExtractQuestItemID: %s", tostring(questItemID)))
		else
			table.insert(extractionAttempts, "ExtractQuestItemID: failed")
		end
	end

	-- Method 6: Dungeon Journal items
	if not itemID and (frameName:match("Adventure") or frameName:match("Encounter") or frameName:match("Journal")) then
		local journalItemID = self:ExtractJournalItemID(frame)
		if journalItemID then
			itemID = journalItemID
			table.insert(extractionAttempts, string.format("ExtractJournalItemID: %s", tostring(journalItemID)))
		else
			table.insert(extractionAttempts, "ExtractJournalItemID: failed")
		end
	end

	-- Method 7: Action bar items
	if not itemID and (frameName:match("ActionButton") or frame.action) then
		local actionItemID = self:ExtractActionItemID(frame)
		if actionItemID then
			itemID = actionItemID
			table.insert(extractionAttempts, string.format("ExtractActionItemID: %s", tostring(actionItemID)))
		else
			table.insert(extractionAttempts, "ExtractActionItemID: failed")
		end
	end

	-- Method 8: Generic button with icon texture
	if not itemID then
		local textureItemID = self:ExtractItemFromTexture(frame)
		if textureItemID then
			itemID = textureItemID
			table.insert(extractionAttempts, string.format("ExtractItemFromTexture: %s", tostring(textureItemID)))
		else
			table.insert(extractionAttempts, "ExtractItemFromTexture: failed")
		end
	end

	-- Debug output for frames that look promising but didn't yield items
	if self.db and self.db.debugMode and self.extractDebugCount < 8 and passedFilter then
		if itemID then
			print(string.format("|cffff69b4DOKI|r SUCCESS: %s -> ItemID %s (%s)",
				frameName, tostring(itemID), table.concat(extractionAttempts, ", ")))
		else
			print(string.format("|cffff69b4DOKI|r FAILED: %s -> No item (%s)",
				frameName, table.concat(extractionAttempts, ", ")))
		end

		self.extractDebugCount = self.extractDebugCount + 1
	end

	-- Validate and return
	if not itemID then return nil end

	-- Check if it's a collectible item
	local isCollectible = self:IsCollectibleItem(itemID)
	if not isCollectible then
		if self.db and self.db.debugMode and self.extractDebugCount < 10 then
			print(string.format("|cffff69b4DOKI|r SKIPPED: %s -> ItemID %s (not collectible)",
				frameName, tostring(itemID)))
			self.extractDebugCount = self.extractDebugCount + 1
		end

		return nil
	end

	local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
	return {
		itemID = itemID,
		itemLink = itemLink,
		isCollected = isCollected,
		showYellowD = showYellowD,
		frameType = self:DetermineFrameType(frame, frameName),
	}
end

-- Extract item ID from bag/container frames
function DOKI:ExtractBagItemID(frame)
	if frame.GetBagID and frame.GetID then
		local success1, bagID = pcall(frame.GetBagID, frame)
		local success2, slotID = pcall(frame.GetID, frame)
		if success1 and success2 and bagID and slotID then
			local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
			return itemInfo and itemInfo.itemID
		end
	end

	-- Alternative: Check for bagID/slotID properties
	if frame.bagID and frame.slotID then
		local itemInfo = C_Container.GetContainerItemInfo(frame.bagID, frame.slotID)
		return itemInfo and itemInfo.itemID
	end

	return nil
end

-- Extract item ID from merchant frames
function DOKI:ExtractMerchantItemID(frame, frameName)
	-- Only process actual merchant item buttons, not parent frames
	local merchantIndex = frameName:match("MerchantItem(%d+)ItemButton")
	if merchantIndex then
		local itemLink = GetMerchantItemLink(tonumber(merchantIndex))
		return itemLink and self:GetItemID(itemLink)
	end

	-- Skip parent merchant frames (MerchantItem1, MerchantItem2, etc.)
	if frameName:match("^MerchantItem%d+$") then
		return nil
	end

	if frame.merchantIndex then
		local itemLink = GetMerchantItemLink(frame.merchantIndex)
		return itemLink and self:GetItemID(itemLink)
	end

	return nil
end

-- Extract item ID from quest frames
function DOKI:ExtractQuestItemID(frame)
	-- Only process frames that are actually quest reward BUTTONS, not quest log text
	local frameName = ""
	local success, name = pcall(frame.GetName, frame)
	if success and name then
		frameName = name
	end

	-- Skip quest log, objective tracker, and other non-button quest frames
	local questTextFrames = {
		"QuestLog", "QuestFrame", "QuestObjective", "QuestDetail",
		"QuestProgress", "QuestComplete", "QuestText", "QuestTitle",
		"ObjectiveTracker", "AllObjectives", "Scenario",
	}
	for _, textFrame in ipairs(questTextFrames) do
		if frameName:find(textFrame) then
			return nil -- Skip quest text frames
		end
	end

	-- Only process actual quest reward buttons
	if not (frameName:match(".*Button$") or frameName:match(".*Reward") or frameName:match(".*Choice")) then
		return nil
	end

	-- Quest rewards
	if frame.type and frame.index then
		local itemLink = GetQuestItemLink(frame.type, frame.index)
		return itemLink and self:GetItemID(itemLink)
	end

	-- Quest log rewards
	if frame.questLogIndex and frame.rewardIndex then
		local itemLink = GetQuestLogItemLink(frame.questLogIndex, frame.rewardIndex)
		return itemLink and self:GetItemID(itemLink)
	end

	return nil
end

-- Extract item ID from dungeon journal frames
function DOKI:ExtractJournalItemID(frame)
	if not C_EncounterJournal then return nil end

	-- Adventure guide rewards
	if frame.abilityID or frame.itemID then
		return frame.itemID
	end

	-- Encounter journal loot
	if frame.encounterID and frame.itemIndex then
		-- This would need specific EncounterJournal API calls
		-- Implementation depends on the specific journal frame structure
	end

	return nil
end

-- Extract item ID from action bar items
function DOKI:ExtractActionItemID(frame)
	if not frame.action then return nil end

	local actionType, itemID = GetActionInfo(frame.action)
	if actionType == "item" then
		return itemID
	end

	return nil
end

-- Extract item ID from frame's texture/icon
function DOKI:ExtractItemFromTexture(frame)
	-- Look for common texture children
	local textureNames = { "icon", "Icon", "texture", "Texture", "IconTexture" }
	for _, textureName in ipairs(textureNames) do
		local textureFrame = frame[textureName] or _G[(frame:GetName() or "") .. textureName]
		if textureFrame and textureFrame.GetTexture then
			local texture = textureFrame:GetTexture()
			if texture then
				-- Try to match texture to known items
				local itemID = self:FindItemByTexture(texture)
				if itemID then return itemID end
			end
		end
	end

	return nil
end

-- Find item ID by matching texture path (with caching)
function DOKI:FindItemByTexture(texturePath)
	if not texturePath then return nil end

	-- Initialize cache
	if not self.textureCache then self.textureCache = {} end

	if self.textureCache[texturePath] then return self.textureCache[texturePath] end

	-- Quick check for numeric item IDs in texture path
	if type(texturePath) == "number" and texturePath > 100000 then
		if self:IsCollectibleItem(texturePath) then
			self.textureCache[texturePath] = texturePath
			return texturePath
		end
	end

	-- Check against current known items (from any previous scans)
	for itemLink, itemData in pairs(self.currentItems) do
		if itemData.itemID then
			local itemTexture = C_Item.GetItemIcon(itemData.itemID)
			if itemTexture == texturePath then
				self.textureCache[texturePath] = itemData.itemID
				return itemData.itemID
			end
		end
	end

	return nil
end

-- Determine what type of UI this frame belongs to
function DOKI:DetermineFrameType(frame, frameName)
	if frameName:match("ContainerFrame") or frameName:match("Bag.*Item") then
		return "bag"
	elseif frameName:match("MerchantItem.*ItemButton") then
		return "merchant"
	elseif frameName:match("Quest.*Button") or frameName:match("QuestLog.*Button") then
		return "quest"
	elseif frameName:match("Adventure") or frameName:match("Encounter") or frameName:match("Journal") then
		return "journal"
	elseif frameName:match("ActionButton") then
		return "actionbar"
	elseif frameName:match("Bank.*Item") then
		return "bank"
	elseif frameName:match("Guild.*Item") then
		return "guild"
	elseif frameName:match("Loot.*Button") then
		return "loot"
	elseif frameName:match("Trade.*Item") then
		return "trade"
	elseif frameName:match("Mail.*Item") then
		return "mail"
	elseif frameName:match("Auction.*Item") then
		return "auction"
	else
		return "unknown"
	end
end

-- Create overlay for any frame type
function DOKI:CreateUniversalOverlay(frame, itemData)
	if itemData.isCollected then return 0 end

	-- Enhanced frame validation before creating overlay
	if not frame or type(frame) ~= "table" then return 0 end

	-- Check if frame is still valid and visible
	local success, isVisible = pcall(frame.IsVisible, frame)
	if not success or not isVisible then return 0 end

	-- Check if frame has necessary methods for parenting
	if not frame.SetParent or not frame.GetName then return 0 end

	local overlayKey = "universal_" .. tostring(frame)
	-- Clear existing overlay
	if self.activeOverlays[overlayKey] then
		self:ReleaseOverlay(self.activeOverlays[overlayKey])
		self.activeOverlays[overlayKey] = nil
	end

	-- Create overlay with error handling
	local success2, overlay = pcall(self.GetOverlay, self)
	if not success2 or not overlay then return 0 end

	local success3 = pcall(overlay.SetParent, overlay, frame)
	if not success3 then
		self:ReleaseOverlay(overlay)
		return 0
	end

	local success4 = pcall(overlay.SetAllPoints, overlay, frame)
	if not success4 then
		self:ReleaseOverlay(overlay)
		return 0
	end

	-- Set color
	if itemData.showYellowD then
		overlay:SetColor(1, 1, 0)     -- Yellow
	else
		overlay:SetColor(1, 0.41, 0.71) -- Pink
	end

	overlay:Show()
	self.activeOverlays[overlayKey] = overlay
	if self.db and self.db.debugMode then
		local itemName = C_Item.GetItemInfo(itemData.itemID) or "Unknown"
		local frameName = ""
		local nameSuccess, name = pcall(frame.GetName, frame)
		if nameSuccess and name then
			frameName = name
		else
			frameName = "unnamed"
		end

		print(string.format("|cffff69b4DOKI|r Created universal overlay for %s (ID: %d) on %s [%s]",
			itemName, itemData.itemID, frameName, itemData.frameType))
	end

	return 1
end

-- Set up universal scanning system
function DOKI:InitializeUniversalScanning()
	-- Clear any existing timer
	if self.universalScanTimer then
		self.universalScanTimer:Cancel()
	end

	-- Scan immediately
	self:UniversalItemScan()
	-- Set up periodic scanning (every 5 seconds instead of 3 for better performance)
	self.universalScanTimer = C_Timer.NewTicker(5, function()
		if self.db and self.db.enabled then
			self:UniversalItemScan()
		end
	end)
	-- Set up event-driven scanning for faster response
	self:SetupUniversalEvents()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Universal scanning system initialized")
	end
end

-- Set up events that trigger immediate rescanning
function DOKI:SetupUniversalEvents()
	if self.universalEventFrame then return end

	self.universalEventFrame = CreateFrame("Frame")
	-- Events that indicate UI changes
	local events = {
		"BAG_UPDATE",
		"BAG_UPDATE_DELAYED",
		"MERCHANT_SHOW",
		"MERCHANT_UPDATE",
		"QUEST_LOG_UPDATE",
		"ADVENTURE_MAP_UPDATE_POIS",
		"ENCOUNTER_JOURNAL_LOOT_UPDATE",
		"ACTIONBAR_SLOT_CHANGED",
		"PLAYER_ENTERING_WORLD",
	}
	for _, event in ipairs(events) do
		self.universalEventFrame:RegisterEvent(event)
	end

	self.universalEventFrame:SetScript("OnEvent", function(self, event, ...)
		-- Longer delay to let UI update and stabilize
		C_Timer.After(0.5, function()
			if DOKI.db and DOKI.db.enabled then
				DOKI:UniversalItemScan()
			end
		end)
	end)
end

-- Clear all universal overlays
function DOKI:ClearUniversalOverlays()
	for overlayKey, overlay in pairs(self.activeOverlays) do
		if overlayKey:match("^universal_") then
			self:ReleaseOverlay(overlay)
			self.activeOverlays[overlayKey] = nil
		end
	end
end

-- Manual trigger for testing
function DOKI:ForceUniversalScan()
	if self.db and self.db.debugMode then
		print("|cffff69b4DOKI|r Forcing universal scan...")
	end

	self:ClearUniversalOverlays()
	return self:UniversalItemScan()
end

-- Debug function to show found frames
function DOKI:DebugFoundFrames()
	if not self.foundFramesThisScan or #self.foundFramesThisScan == 0 then
		print("|cffff69b4DOKI|r No frames found in last scan. Try /doki scan first.")
		return
	end

	print(string.format("|cffff69b4DOKI|r === FOUND FRAMES DEBUG (%d frames) ===", #self.foundFramesThisScan))
	for i, frameInfo in ipairs(self.foundFramesThisScan) do
		local itemName = C_Item.GetItemInfo(frameInfo.itemData.itemID) or "Unknown"
		print(string.format("%d. %s (ID: %d) in %s [%s] - %s",
			i, itemName, frameInfo.itemData.itemID, frameInfo.frameName,
			frameInfo.itemData.frameType,
			frameInfo.itemData.isCollected and "COLLECTED" or "NOT collected"))
	end

	print("|cffff69b4DOKI|r === END FOUND FRAMES DEBUG ===")
end

-- Test ElvUI bag detection
function DOKI:TestElvUIBags()
	if not ElvUI then
		print("|cffff69b4DOKI|r ElvUI not detected")
		return
	end

	print("|cffff69b4DOKI|r === ELVUI BAG TEST ===")
	local E = ElvUI[1]
	print(string.format("ElvUI[1] exists: %s", E and "yes" or "no"))
	if not E then
		print("|cffff69b4DOKI|r Cannot proceed without ElvUI[1]")
		return
	end

	local B = E:GetModule("Bags", true)
	print(string.format("Bags module exists: %s", B and "yes" or "no"))
	if B then
		print(string.format("BagFrame exists: %s", B.BagFrame and "yes" or "no"))
		if B.BagFrame then
			print(string.format("BagFrame shown: %s", B.BagFrame:IsShown() and "yes" or "no"))
		end
	end

	-- Test button naming patterns for first few slots
	print("\nTesting button naming patterns:")
	local patternsFound = 0
	for bagID = 0, 1 do -- Just test first two bags
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots and numSlots > 0 then
			for slotID = 1, math.min(3, numSlots) do -- Just test first 3 slots
				local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
				if itemInfo and itemInfo.itemID then
					print(string.format("Bag %d Slot %d has item %d", bagID, slotID, itemInfo.itemID))
					-- Test different naming patterns
					local patterns = {
						string.format("ElvUI_ContainerFrameBag%dSlot%dHash", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%d", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%dCenter", bagID, slotID),
						string.format("ElvUI_ContainerFrameBag%dSlot%dArea", bagID, slotID),
					}
					for _, pattern in ipairs(patterns) do
						local button = _G[pattern]
						if button then
							print(string.format("  Found button: %s (visible: %s)",
								pattern, button:IsVisible() and "yes" or "no"))
							if button:IsVisible() then
								patternsFound = patternsFound + 1
							end
						end
					end
				end
			end
		end
	end

	print(string.format("\nVisible ElvUI buttons found: %d", patternsFound))
	print("|cffff69b4DOKI|r === END ELVUI TEST ===")
end

-- Test specific merchant frames
function DOKI:TestMerchantFrames()
	if not MerchantFrame or not MerchantFrame:IsVisible() then
		print("|cffff69b4DOKI|r Merchant frame not visible")
		return
	end

	print("|cffff69b4DOKI|r === MERCHANT FRAME TEST ===")
	for i = 1, 10 do
		local buttonName = "MerchantItem" .. i .. "ItemButton"
		local button = _G[buttonName]
		print(string.format("Testing %s:", buttonName))
		print(string.format("  Button exists: %s", button and "yes" or "no"))
		if button then
			local isVisible = button:IsVisible()
			print(string.format("  Button visible: %s", tostring(isVisible)))
			if isVisible then
				-- Test item extraction
				local itemLink = GetMerchantItemLink(i)
				print(string.format("  GetMerchantItemLink(%d): %s", i, itemLink or "nil"))
				if itemLink then
					local itemID = self:GetItemID(itemLink)
					print(string.format("  ItemID: %s", tostring(itemID)))
					if itemID then
						local isCollectible = self:IsCollectibleItem(itemID)
						print(string.format("  Is collectible: %s", tostring(isCollectible)))
						if isCollectible then
							local isCollected, showYellowD = self:IsItemCollected(itemID, itemLink)
							print(string.format("  Collection status: %s%s",
								isCollected and "COLLECTED" or "NOT collected",
								showYellowD and " (yellow D)" or ""))
						end
					end
				end

				-- Test frame extraction
				local frameItemData = self:ExtractItemFromAnyFrame(button)
				print(string.format("  Frame extraction: %s",
					frameItemData and ("ItemID " .. frameItemData.itemID) or "failed"))
			end
		end

		print("") -- Empty line between items
	end

	print("|cffff69b4DOKI|r === END MERCHANT TEST ===")
end

-- ===== ITEM IDENTIFICATION FUNCTIONS =====
-- Extract item ID from item link
function DOKI:GetItemID(itemLink)
	if not itemLink then return nil end

	if type(itemLink) == "number" then
		return itemLink
	end

	if type(itemLink) == "string" then
		local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
		return itemID
	end

	return nil
end

-- Check if an item is a collectible type
function DOKI:IsCollectibleItem(itemID)
	if not itemID then return false end

	-- Use C_Item.GetItemInfoInstant for immediate info
	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false
	end

	-- Mount items (class 15, subclass 5)
	if classID == 15 and subClassID == 5 then
		return true
	end

	-- Pet items (class 15, subclass 2)
	if classID == 15 and subClassID == 2 then
		return true
	end

	-- Toy items - check with toy API
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		return true
	end

	-- Transmog items (weapons class 2, armor class 4)
	if classID == 2 or classID == 4 then
		-- Filter out non-transmog equipment slots
		if itemEquipLoc then
			local nonTransmogSlots = {
				"INVTYPE_NECK", -- Necklaces
				"INVTYPE_FINGER", -- Rings
				"INVTYPE_TRINKET", -- Trinkets
				"INVTYPE_HOLDABLE", -- Off-hand items (some)
				"INVTYPE_BAG",  -- Bags
				"INVTYPE_QUIVER", -- Quivers
			}
			for _, slot in ipairs(nonTransmogSlots) do
				if itemEquipLoc == slot then
					return false
				end
			end

			-- If it's an equipment slot that can have transmog, it's collectible
			return true
		end
	end

	return false
end

-- ===== COLLECTION STATUS FUNCTIONS =====
-- Check if item is already collected using the SPECIFIC variant
function DOKI:IsItemCollected(itemID, itemLink)
	if not itemID then return false, false end

	local _, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not classID or not subClassID then
		return false, false
	end

	-- Check mounts
	if classID == 15 and subClassID == 5 then
		return self:IsMountCollected(itemID), false
	end

	-- Check pets
	if classID == 15 and subClassID == 2 then
		return self:IsPetCollected(itemID), false
	end

	-- Check toys
	if C_ToyBox and C_ToyBox.GetToyInfo(itemID) then
		return PlayerHasToy(itemID), false
	end

	-- Check transmog - use appropriate method based on smart mode
	if classID == 2 or classID == 4 then
		if self.db and self.db.smartMode then
			return self:IsTransmogCollectedSmart(itemID, itemLink)
		else
			return self:IsTransmogCollected(itemID, itemLink)
		end
	end

	return false, false
end

-- Check if mount is collected
function DOKI:IsMountCollected(itemID)
	if not itemID or not C_MountJournal then return false end

	-- Get the spell that this mount item teaches
	local spellID = C_Item.GetItemSpell(itemID)
	if not spellID then return false end

	-- Convert to number if it's a string
	local spellIDNum = tonumber(spellID)
	return spellIDNum and IsSpellKnown(spellIDNum) or false
end

-- Check if pet is collected
function DOKI:IsPetCollected(itemID)
	if not itemID or not C_PetJournal then return false end

	-- Get species info for this pet item
	local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, obtainable, displayID, speciesID =
			C_PetJournal.GetPetInfoByItemID(itemID)
	if not speciesID then return false end

	-- Check if we have any pets of this species
	local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
	return numCollected and numCollected > 0
end

-- Enhanced transmog collection check with yellow D feature
function DOKI:IsTransmogCollected(itemID, itemLink)
	if not itemID or not C_TransmogCollection then return false, false end

	local itemAppearanceID, itemModifiedAppearanceID
	-- Try hyperlink first (works for mythic/heroic/normal variants)
	if itemLink then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)
	end

	-- Method 2: If hyperlink failed, fallback to itemID
	if not itemModifiedAppearanceID then
		itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	end

	if not itemModifiedAppearanceID then
		return false, false
	end

	-- Check if THIS specific variant is collected
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		return true, false -- Have this specific variant, no overlay needed
	end

	-- Don't have this variant, check if we have other sources of this appearance
	local showYellowD = false
	if itemAppearanceID then
		local hasOtherSources = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasOtherSources then
			showYellowD = true
		end
	end

	return false, showYellowD -- Don't have this variant, but return yellow D flag
end

-- SMART: Enhanced transmog collection check with class AND faction restriction awareness
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

	if not itemModifiedAppearanceID then
		return false, false
	end

	-- Check if we have this specific variant
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	if hasThisVariant then
		return true, false -- Have this variant, no overlay needed
	end

	-- We don't have this variant - check if we have equal or better sources
	if itemAppearanceID then
		local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
		if hasEqualOrBetterSources then
			-- We have identical or less restrictive sources, so we don't need this item
			return true, false -- Treat as collected (no D shown)
		else
			-- We either have no sources, or only more restrictive sources - show pink D
			return false, false -- Show pink D (we need this item)
		end
	end

	return false, false -- Default to pink D
end

-- Check if we have other sources for this appearance
function DOKI:HasOtherTransmogSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not sourceIDs or type(sourceIDs) ~= "table" then return false end

	-- Check each source
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

-- Check if we have sources with identical or less restrictive class AND faction sets
function DOKI:HasEqualOrLessRestrictiveSources(itemAppearanceID, excludeModifiedAppearanceID)
	if not itemAppearanceID then return false end

	-- Get all sources for this appearance
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then return false end

	-- Get class and faction restrictions for the current item
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
					-- Compare faction restrictions
					local factionEquivalent = false
					if sourceRestrictions.hasFactionRestriction == currentItemRestrictions.hasFactionRestriction then
						if not sourceRestrictions.hasFactionRestriction then
							factionEquivalent = true
						elseif sourceRestrictions.faction == currentItemRestrictions.faction then
							factionEquivalent = true
						end
					end

					-- Only compare class restrictions if faction restrictions are equivalent
					if factionEquivalent then
						-- Check if source is less restrictive in terms of classes
						if sourceClassCount > currentClassCount then
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
								return true
							end
						end
					end
				end
			end
		end
	end

	return false
end

-- Get class and faction restrictions for a specific source
function DOKI:GetClassRestrictionsForSource(sourceID, appearanceID)
	local restrictions = {
		validClasses = {},
		armorType = nil,
		hasClassRestriction = false,
		faction = nil,
		hasFactionRestriction = false,
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
		return restrictions
	end

	-- Get item properties for armor type
	local success3, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, linkedItemID)
	if success3 and classID == 4 then -- Armor
		restrictions.armorType = subClassID
	end

	-- Parse tooltip for class and faction restrictions
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
					local classText = string.match(text, "Classes:%s*(.+)")
					if classText then
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
						for className in string.gmatch(classText, "([^,]+)") do
							className = strtrim(className)
							local classID = classNameToID[className]
							if classID then
								table.insert(restrictedClasses, classID)
							end
						end
					end
				end

				-- Check for faction restrictions
				local lowerText = string.lower(text)
				if string.find(lowerText, "alliance") then
					if string.find(lowerText, "require") or string.find(lowerText, "only") or
							string.find(lowerText, "exclusive") or string.find(lowerText, "specific") or
							string.find(lowerText, "reputation") or string.find(text, "Alliance") then
						restrictions.faction = "Alliance"
						restrictions.hasFactionRestriction = true
					end
				elseif string.find(lowerText, "horde") then
					if string.find(lowerText, "require") or string.find(lowerText, "only") or
							string.find(lowerText, "exclusive") or string.find(lowerText, "specific") or
							string.find(lowerText, "reputation") or string.find(text, "Horde") then
						restrictions.faction = "Horde"
						restrictions.hasFactionRestriction = true
					end
				end
			end
		end
	end

	tooltip:Hide()
	if foundClassRestriction then
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
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- All classes
		else
			restrictions.validClasses = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- Unknown, assume all
		end
	end

	return restrictions
end

-- ===== DEBUG FUNCTIONS =====
-- DEBUG FUNCTION: Detailed transmog analysis
function DOKI:DebugTransmogItem(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki debug <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === DEBUGGING ITEM %d ===", itemID))
	-- Get basic item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID = C_Item.GetItemInfo(itemID)
	if not itemName then
		print("|cffff69b4DOKI|r Item not found or not cached. Try again in a few seconds.")
		return
	end

	print(string.format("Item Name: %s", itemName))
	print(string.format("Class ID: %d, SubClass ID: %d", classID or 0, subClassID or 0))
	print(string.format("Item Type: %s, SubType: %s", itemType or "nil", itemSubType or "nil"))
	-- Check if it's a transmog item
	if not (classID == 2 or classID == 4) then
		print("|cffff69b4DOKI|r Not a transmog item (not weapon or armor)")
		return
	end

	-- Create a mock hyperlink for testing
	local testLink = string.format("|cffffffff|Hitem:%d:::::::::::::|h[%s]|h|r", itemID, itemName)
	-- Get appearance IDs
	print("\n--- Getting Appearance IDs ---")
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	print(string.format("Item Appearance ID: %s", tostring(itemAppearanceID)))
	print(string.format("Modified Appearance ID: %s", tostring(itemModifiedAppearanceID)))
	if not itemModifiedAppearanceID then
		print("|cffff69b4DOKI|r No appearance IDs found - item cannot be transmogged")
		return
	end

	-- Check if we have this specific variant
	print("\n--- Checking This Specific Variant ---")
	local hasThisVariant = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	print(string.format("Has this variant: %s", tostring(hasThisVariant)))
	if hasThisVariant then
		print("|cffff69b4DOKI|r Result: COLLECTED - No overlay needed")
		return
	end

	-- Check for other sources
	print("\n--- Checking Other Sources ---")
	if itemAppearanceID then
		local sourceIDs = C_TransmogCollection.GetAllAppearanceSources(itemAppearanceID)
		print(string.format("Number of sources found: %d", sourceIDs and #sourceIDs or 0))
		if sourceIDs and #sourceIDs > 0 then
			local foundOtherSource = false
			for i, sourceID in ipairs(sourceIDs) do
				if sourceID ~= itemModifiedAppearanceID then
					local success, hasSource = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
					if success and hasSource then
						foundOtherSource = true
						break
					end
				end
			end

			-- Final result
			print("\n--- FINAL RESULT ---")
			if foundOtherSource then
				if self.db.smartMode then
					print("|cffff69b4DOKI|r Smart mode enabled - checking class and faction restrictions...")
					local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID,
						itemModifiedAppearanceID)
					if hasEqualOrBetterSources then
						print("|cffff69b4DOKI|r Result: HAVE EQUAL OR BETTER SOURCE - No D")
					else
						print("|cffff69b4DOKI|r Result: OTHER SOURCES MORE RESTRICTIVE - Pink D")
					end
				else
					print("|cffff69b4DOKI|r Result: COLLECTED FROM OTHER SOURCE - Yellow D")
				end
			else
				print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
			end
		else
			print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
		end
	else
		print("|cffff69b4DOKI|r Result: UNCOLLECTED - Pink D")
	end

	print("|cffff69b4DOKI|r === END DEBUG ===")
end

-- DEBUG FUNCTION: Smart transmog analysis with faction info
function DOKI:DebugSmartTransmog(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki smart <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SMART TRANSMOG DEBUG: %d ===", itemID))
	-- Get appearance IDs
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemID)
	if not itemAppearanceID then
		print("No appearance ID found")
		return
	end

	print(string.format("Appearance ID: %d, Modified ID: %d", itemAppearanceID, itemModifiedAppearanceID))
	local success, allSources = pcall(C_TransmogCollection.GetAllAppearanceSources, itemAppearanceID)
	if not success or not allSources then
		print("No sources found or error retrieving sources")
		return
	end

	print(string.format("Found %d total sources", #allSources))
	-- Analyze current item restrictions
	local currentRestrictions = self:GetClassRestrictionsForSource(itemModifiedAppearanceID, itemAppearanceID)
	print(string.format("\n--- Current Item Restrictions ---"))
	if currentRestrictions then
		print(string.format("Valid for %d classes: %s", #currentRestrictions.validClasses,
			table.concat(currentRestrictions.validClasses, ", ")))
		print(string.format("Faction: %s", tostring(currentRestrictions.faction)))
		print(string.format("Has faction restriction: %s", tostring(currentRestrictions.hasFactionRestriction)))
	else
		print("Could not determine restrictions")
	end

	-- Final smart assessment
	print(string.format("\n--- Smart Assessment ---"))
	local hasEqualOrBetterSources = self:HasEqualOrLessRestrictiveSources(itemAppearanceID, itemModifiedAppearanceID)
	print(string.format("Has equal or less restrictive sources: %s", tostring(hasEqualOrBetterSources)))
	local regularCheck = self:HasOtherTransmogSources(itemAppearanceID, itemModifiedAppearanceID)
	print(string.format("Has any other sources: %s", tostring(regularCheck)))
	print("|cffff69b4DOKI|r === END SMART DEBUG ===")
end

-- DEBUG FUNCTION: Deep dive into class restrictions for a specific source
function DOKI:DebugClassRestrictions(sourceID, appearanceID)
	print(string.format("|cffff69b4DOKI|r === CLASS RESTRICTION DEBUG: Source %d, Appearance %d ===", sourceID,
		appearanceID))
	local restrictions = self:GetClassRestrictionsForSource(sourceID, appearanceID)
	if restrictions then
		print("Results from GetClassRestrictionsForSource:")
		print(string.format("  Valid classes: %s", table.concat(restrictions.validClasses, ", ")))
		print(string.format("  Armor type: %s", tostring(restrictions.armorType)))
		print(string.format("  Has class restriction: %s", tostring(restrictions.hasClassRestriction)))
		print(string.format("  Faction: %s", tostring(restrictions.faction)))
		print(string.format("  Has faction restriction: %s", tostring(restrictions.hasFactionRestriction)))
	else
		print("Could not get restrictions")
	end

	print("|cffff69b4DOKI|r === END CLASS RESTRICTION DEBUG ===")
end

-- DEBUG FUNCTION: Test faction detection for specific source
function DOKI:DebugSourceRestrictions(sourceID)
	if not sourceID then
		print("|cffff69b4DOKI|r Usage: /doki source <sourceID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === SOURCE RESTRICTION DEBUG: %d ===", sourceID))
	local restrictions = self:GetClassRestrictionsForSource(sourceID, nil)
	if restrictions then
		print("Results from GetClassRestrictionsForSource:")
		print(string.format("  Valid classes: %s", table.concat(restrictions.validClasses, ", ")))
		print(string.format("  Armor type: %s", tostring(restrictions.armorType)))
		print(string.format("  Has class restriction: %s", tostring(restrictions.hasClassRestriction)))
		print(string.format("  Faction: %s", tostring(restrictions.faction)))
		print(string.format("  Has faction restriction: %s", tostring(restrictions.hasFactionRestriction)))
	else
		print("Could not get restrictions")
	end

	print("|cffff69b4DOKI|r === END SOURCE DEBUG ===")
end

-- DEBUG FUNCTION: Simple item analysis
function DOKI:DebugItemInfo(itemID)
	if not itemID then
		print("|cffff69b4DOKI|r Usage: /doki item <itemID>")
		return
	end

	print(string.format("|cffff69b4DOKI|r === ITEM INFO DEBUG: %d ===", itemID))
	-- Get all available item info
	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemTexture, sellPrice, classID, subClassID, bindType, expacID, setID, isCraftingReagent = C_Item
			.GetItemInfo(itemID)
	print(string.format("Name: %s", itemName or "Unknown"))
	print(string.format("Type: %s (%d), SubType: %s (%d)", itemType or "nil", classID or 0, itemSubType or "nil",
		subClassID or 0))
	print(string.format("Equip Loc: %s", itemEquipLoc or "nil"))
	-- Check if this gives us any class restriction hints
	local _, _, _, _, _, _, instantClassID, instantSubClassID = C_Item.GetItemInfoInstant(itemID)
	print(string.format("Instant: Class %d, SubClass %d", instantClassID or 0, instantSubClassID or 0))
	print("|cffff69b4DOKI|r === END ITEM DEBUG ===")
end
