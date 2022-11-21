local LibQTip = LibStub('LibQTip-1.0')
local LibDataBroker = LibStub('LibDataBroker-1.1')
if not LibDataBroker or not LibQTip then return end
local L = LibStub:GetLibrary( "AceLocale-3.0" ):GetLocale("ShowDurability" )
local name = L["ShowDurability"]

local tooltip = nil

local Repair = {
	icon  = "Interface\\Icons\\Trade_BlackSmithing",
	label = L["Dur"],
	text  = "100%",
	type = "data source",
}

local headerColor = "|cFFFFFFFF";
local textColor   = "|cFFAAAAAA";

local refreshTooltip = 0
local equippedCost   = 0
local inventoryCost  = 0
local inventoryLine  = nil
local factionLine    = { }

local autoRepairLine  = nil
local guildRepairLine = nil
local factionRepairLine=nil

local GetInventorySlotInfo, GetContainerItemDurability, ipairs, print, UnitReaction, GetContainerNumSlots
	= GetInventorySlotInfo, GetContainerItemDurability, ipairs, print, UnitReaction, GetContainerNumSlots

if C_Container then
	if C_Container.GetContainerItemDurability then
		GetContainerItemDurability = C_Container.GetContainerItemDurability
	end
	if C_Container.GetContainerNumSlots then
		GetContainerNumSlots = C_Container.GetContainerNumSlots
	end
end

local print = function(msg) print("|cFF5555AA"..name..": |cFFAAAAFF"..msg) end

local WowVer = select(4, GetBuildInfo())
local IsClassic = WOW_PROJECT_ID and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

-- Stores equipped item info
local slots = { }
do
	local slotNames = { "Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "MainHand", "SecondaryHand" }
	if WowVer < 50000 then
		table.insert(slotNames, #slotNames, "Ranged")
	end
	for i,name in ipairs(slotNames) do
		slots[ i ] = {
			GetInventorySlotInfo(name.."Slot"), -- slotId
			name, -- slotName, used for translation
			-1,    -- Durability
			0,    -- Cost
			2     -- Tooltip line
		}
	end
end

-- States
local states = {
	autoRepair = {
		default = 1,
		[0] = {
			color     = "|cFFFF0000",
			status    = L["Disabled"],
			nextState = 1,
		},
		[1] = {
			color     = "|cFF00FF00",
			status    = L["Enabled"],
			nextState = 2,
		},
		[2] = {
			color     = "|cFFFFFF00",
			status    = L["Popup"],
			nextState = 0,
		},
	},
	guildRepair = {
		default = 0,
		[0] = {
			color     = "|cFFFF0000",
			status    = L["Disabled"],
			nextState = 1,
		},
		[1] = {
			color     = "|cFF00FF00",
			status    = L["Enabled"],
			nextState = 0,
		},
	},
	OnlyRepairReaction = {
		default = 0,
		[0] = {
			color     = "|cFFFF0000",
			status    = L["Disabled"],
			nextState = 4,
		},
		[4] = {
			color     = "|cFF00FF00",
			status    = FACTION_STANDING_LABEL4,
			nextState = 5,
		},
		[5] = {
			color     = "|cFF00FF00",
			status    = FACTION_STANDING_LABEL5,
			nextState = 6,
		},
		[6] = {
			color     = "|cFF00FF00",
			status    = FACTION_STANDING_LABEL6,
			nextState = 7,
		},
		[7] = {
			color     = "|cFF00FF00",
			status    = FACTION_STANDING_LABEL7,
			nextState = 8,
		},
		[8] = {
			color     = "|cFF00FF00",
			status    = FACTION_STANDING_LABEL8,
			nextState = 0,
		},
	},
}

function Repair:OnLoad()
	if not ShowDurabilityDB then
		ShowDurabilityDB = { }
	end
	for key,state in pairs(states) do
		-- Reset to known states
		if not ShowDurabilityDB[key] or not states[key][ ShowDurabilityDB[key] ] then
			ShowDurabilityDB[key] = state.default
		end
	end

	-- Clean up saved vars
	ShowDurabilityDB["useGuildBank"] = nil

	-- Update tooltip
	ShowDurability_Popup_Repair:SetText(L["Repair"])
	ShowDurability_Popup_Title:SetText(L["ShowDurability"])
	ShowDurability_Popup_GuildRepair:SetText(L["GuildRepair"])

	-- Register @ LibBrokers
	Repair = LibDataBroker:NewDataObject(name, Repair)
	ShowDurability = Repair -- Register globaly
end

---------------------------------
-- Support functions
---------------------------------
local DurabilityColor = function(perc)
	if not perc or perc < 0 then return "|cFF555555" end
	if perc == 1 then
		return "|cFF005500" -- Dark green
	elseif perc >= .9 then
		return "|cFF00AA00" -- Green
	elseif perc > .5 then
		return "|cFFFFFF00" -- Yellow
	elseif perc > .2 then
		return "|cFFFF9900" -- Orange
	else
		return "|cFFFF0000" -- Red
	end
end

local CopperToString = function(c)
	if c == 0 then return "" end

	local str = ""
	if not c or c < 0 then return str end
	if c >= 10000 then
		local g = math.floor(c/10000)
		c = c - g*10000
		str = str.."|cFFFFD800"..g.." |TInterface\\MoneyFrame\\UI-GoldIcon.blp:0:0:0:0|t "
	end
	if c >= 100 then
		local s = math.floor(c/100)
		c = c - s*100
		str = str.."|cFFC7C7C7"..s.." |TInterface\\MoneyFrame\\UI-SilverIcon.blp:0:0:0:0|t "
	end
	if c >= 0 then
		str = str.."|cFFEEA55F"..c.." |TInterface\\MoneyFrame\\UI-CopperIcon.blp:0:0:0:0|t "
	end
	return str
end

local DurabilityText = function(num)
	if type(num) == "number" and num >= 0 then
		return DurabilityColor(num)..math.floor(num*100).."%"
	else
		return DurabilityColor(-1).."-"
	end
end

---------------------------------
-- Durability updates and repair
---------------------------------
function Repair:CreateTooltipSkeleton()
	local line

	tooltip:AddHeader(headerColor..L["Equipped items"])
	for i,info in ipairs(slots) do
		-- Set the empty row
		info[5] = tooltip:AddLine(
			textColor..L[info[2]],   -- Slot
			"   ",                   -- Dur
			"           "            -- Cost
		)
	end

	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Inventory"])
	inventoryLine = tooltip:AddLine(
		textColor..L["Items in your bags"], -- Slot
		"..%",                              -- Dur
		L["Loading"]                        -- Cost
	)

	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Total cost"])

	for i=4, 8 do
		factionLine[i] = tooltip:AddLine(
			textColor.._G["FACTION_STANDING_LABEL"..i], -- Slot
			"   ",                                      -- Dur
			"       "                                   -- Cost
		)
	end

	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Auto repair:"])
	tooltip:AddLine(textColor..L["Force update"], " ", L["LeftMouse"])

	local autoRepairState  = Repair:GetState("autoRepair")
	local guildRepairState = Repair:GetState("guildRepair")
	local factionRepairState=Repair:GetState("OnlyRepairReaction")

	autoRepairLine  = tooltip:AddLine(autoRepairState.color ..L["Toggle auto-repair"],       " ", L["RightMouse"])
	if not IsClassic then
		guildRepairLine = tooltip:AddLine(guildRepairState.color..L["Toggle guild bank-repair"], " ", L["MiddleMouse"])
	end
	factionRepairLine=tooltip:AddLine(factionRepairState.color..L["Reputation requirement: "] .. factionRepairState.status, " ", L["Shift-RightMouse"])
end

do
	local i = 1
	local cost = 0
	local dur, durPerc, max
	local minDur = 1
	local f = CreateFrame("Frame")

	local UpdateEquippedItemsPartial = function()
		local endLoop = GetTime() + .01

		while slots[i] do
			local info = slots[i]

			durPerc = -1 -- Default: no item equipted
			if GetInventoryItemLink("player", info[1]) then
				dur, max = GetInventoryItemDurability(info[1])
				if dur and max > 0 then
					durPerc = dur/max
					if durPerc < minDur then minDur = durPerc end
				end
			end
			-- Update %
			info[3] = durPerc
			-- Update cost
			if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
				local tooltipData = C_TooltipInfo.GetInventoryItem("player", info[1])
				if tooltipData then
					TooltipUtil.SurfaceArgs(tooltipData)
					info[4] = tooltipData.repairCost and tooltipData.repairCost or 0
				end
			else
				ShowDurabilityScanner:ClearLines()
				info[4] = select(3, ShowDurabilityScanner:SetInventoryItem("player", info[1])) or 0
			end

			-- Add to total cost
			equippedCost = equippedCost + info[4]

			-- Make ready for the next round
			i = i + 1

			-- Stop loop
			if endLoop < GetTime() then
				return
			end
		end

		Repair.text = DurabilityText(minDur)
		Repair.RenderEquippedDurability()
		Repair.RenderTotalCost()
		f:SetScript("OnUpdate", nil)
	end

	function Repair:UpdateEquippedDurability()
		-- Start smal
		equippedCost = 0;

		-- Reset vars
		i = 1
		cost = 0
		minDur = 1

		f:SetScript("OnUpdate", UpdateEquippedItemsPartial)
	end
end

function Repair:RenderEquippedDurability()
	if not tooltip then return end
	for i,info in ipairs(slots) do
		tooltip:SetCell(info[5], 2, DurabilityText(info[3]))
		tooltip:SetCell(info[5], 3, CopperToString(info[4]))
	end
end

function Repair:RenderTotalCost()
	if not tooltip then return end
	local m = 1
	local cost = equippedCost + inventoryCost
	for i=4, 8 do
		tooltip:SetCell(factionLine[i], 3, CopperToString(math.floor(cost*m+.5)))
		m = m - .05
	end
end

local AutoRepair = function()
	if not ShowDurabilityDB.autoRepair or ShowDurabilityDB.autoRepair == 0 then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then return end

	-- Use guildbank to repair
	if ShowDurabilityDB.autoRepair == 1 then
		if ShowDurabilityDB.OnlyRepairReaction and ShowDurabilityDB.OnlyRepairReaction > 0 then
			local reaction = UnitReaction("target","player")
			if reaction and reaction < ShowDurabilityDB.OnlyRepairReaction then
				--print("Skipped auto-repair due to faction. is "..tostring(reaction).." want "..ShowDurabilityDB.OnlyRepairReaction)
				return
			end
		end

		local GuildBankWithdraw
		if GetGuildBankWithdrawMoney then
			GuildBankWithdraw = GetGuildBankWithdrawMoney()
		end
		if CanGuildBankRepair and CanGuildBankRepair() and ShowDurabilityDB.guildRepair == 1 and (GuildBankWithdraw == -1 or GuildBankWithdraw >= cost) and not GetGuildInfoText():match("%[noautorepair%]") then
			Repair:RepairWithGuildBank()
		else
			Repair:Repair()
		end
	else
		ShowDurability_Popup:Show()
		ShowDurability_Popup_Cost:SetText(CopperToString(cost))
	end
end

function Repair:Repair()
	local cost = GetRepairAllCost()
	if GetMoney() >= cost then
		RepairAllItems()
		print(L["Repaired for "]..CopperToString(cost))
	else
		print(L["Unable to AutoRepair, you need "]..CopperToString(cost - GetMoney()))
	end
end

function Repair:RepairWithGuildBank()
	local cost = GetRepairAllCost()
	local GuildBankWithdraw = GetGuildBankWithdrawMoney()
	if GuildBankWithdraw == -1 or GuildBankWithdraw >= cost then
		RepairAllItems(1)
		print(L["Repaired for "]..CopperToString(cost)..L[" (Guild bank)"])
	else
		print(L["Unable to AutoRepair, you need "]..CopperToString(cost - GuildBankWithdraw)..L[" (Guild bank)"])
	end
end

do -- Hide from the world
	local OnEvent
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(_, _, addon)
	if addon ~= name then return end
		Repair.OnLoad()
		f:SetScript("OnEvent", OnEvent)
		f:UnregisterEvent("ADDON_LOADED")
		f:RegisterEvent("PLAYER_DEAD")
		f:RegisterEvent("PLAYER_UNGHOST")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("UPDATE_INVENTORY_ALERTS")
		f:RegisterEvent("MERCHANT_SHOW")
		f:RegisterEvent("MERCHANT_CLOSED")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
	end)

	OnEvent = function(_, event, ...)
		if event ~= "MERCHANT_SHOW" then
			Repair.UpdateEquippedDurability()
			refreshTooltip = 0

			if event == "MERCHANT_CLOSED" then
				ShowDurability_Popup:Hide()
			end
		else
			AutoRepair()
			local updateDurTime = GetTime() + 1
			f:SetScript("OnUpdate", function()
				if updateDurTime < GetTime() then
					-- Update dur
					refreshTooltip = 0
					Repair.UpdateEquippedDurability()
					f:SetScript("OnUpdate", nil)
				end
			end)
		end
	end
end

---------------------------------
-- TOOLTIP
---------------------------------
local anchorTo
Repair.OnTooltipShowInternal = function(GameTooltip)
	--if refreshTooltip + 20 > GetTime() then return end

	-- Anchor
	--print("Anchor to: "..(anchorTo:GetName() or "nil.."))
	tooltip:SmartAnchorTo(anchorTo) -- ReAnchor

	-- Update information
	Repair.UpdateEquippedDurability()
	Repair.RenderEquippedDurability()
	Repair.UpdateInventoryCost()
	Repair.RenderTotalCost()

	refreshTooltip = GetTime()
end
--
function Repair:OnEnter()
	-- Create tooltip
	tooltip = LibQTip:Acquire("RepairTooltip", 3, "LEFT", "CENTER", "RIGHT")

	-- Skelet
	Repair:CreateTooltipSkeleton()

	anchorTo = self
	tooltip:Show()
	Repair.OnTooltipShowInternal()
end

function Repair:OnLeave()
	if not tooltip then
		return
	end

	LibQTip:Release(tooltip)
	tooltip:Hide()
	tooltip = nil
end

function Repair:GetState(key)
	assert(states[key], "Unknown state: "..(key or "nil"))
	local currentState = ShowDurabilityDB[key] or states[key].default
	return states[key][currentState]
end

function Repair:SetNextState(key)
	local currentState = Repair:GetState(key)
	ShowDurabilityDB[key] = currentState.nextState or 0
	return Repair:GetState(key)
end

function Repair:OnClick(button)
	if button == "RightButton" then
		if IsShiftKeyDown() then
			-- Update to next state, and return the new state
			local state = Repair:SetNextState("OnlyRepairReaction")

			-- Ex: Auto-repair [red]Disabled
			print(L["Faction repair "]..state.color..state.status)

			-- Update tooltip color
			if tooltip then
				tooltip:SetCell(factionRepairLine, 1, state.color..L["Reputation requirement: "] .. state.status)
			end
		else
			-- Update to next state, and return the new state
			local state = Repair:SetNextState("autoRepair")

			-- Ex: Auto-repair [red]Disabled
			print(L["Auto-repair "]..state.color..state.status)

			-- Update tooltip color
			if tooltip then
				tooltip:SetCell(autoRepairLine, 1, state.color..L["Toggle auto-repair"])
			end
		end
	elseif guildRepairLine and (button == "MiddleButton" or (IsShiftKeyDown() and button == "LeftButton")) then
		local state = Repair:SetNextState("guildRepair")

		-- Ex: Guild bank-repair [green]Enable
		print(L["Guild bank-repair "]..state.color..state.status)

		-- Update tooltip color
		if tooltip then
			tooltip:SetCell(guildRepairLine, 1, state.color..L["Toggle guild bank-repair"])
		end
	else
		print("|cFF00FF00"..L["Force durability check."])
		refreshTooltip = 0
		--Repair.OnEnter(anchorTo)
	end
end

Repair.PopupTooltip = function(self)
	local isGuild = self:GetName():match"Guild"
	local total
	local cost = GetRepairAllCost()
	if not isGuild or not GetGuildBankWithdrawMoney then
		total = GetMoney()
	else
		total = GetGuildBankWithdrawMoney()
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:AddDoubleLine("", "|c00000000|")
	GameTooltip:AddDoubleLine("|c00000000|", CopperToString(total))
	GameTooltip:AddDoubleLine("|cFFFFFFFF - ", CopperToString(cost))
	GameTooltip:AddDoubleLine("|cFFFFFFFF = ", CopperToString(total - cost))
	GameTooltip:Show()
end

--[[
	Initial code, needs refactoring
	Spreads load over time when scanning inventory
--]]
do
	local gSlot, gBag = 1, 0
	local cost, dur, maxDur = 0, 1, 1
	local f = CreateFrame("Frame")
	local updateRunning = false
	local nextUpdateInventory = 0

	local UpdatePartialInventoryCost = function()
		local endLoop = GetTime() + .01

		while gBag < 5 do

			-- Cost
			local _, repairCost
			if C_TooltipInfo and C_TooltipInfo.GetBagItem then
				local tooltipData = C_TooltipInfo.GetBagItem(gBag, gSlot)
				if tooltipData then
					TooltipUtil.SurfaceArgs(tooltipData)
					repairCost = tooltipData.repairCost
				end
			else
				ShowDurabilityScanner:ClearLines()
				_, repairCost = ShowDurabilityScanner:SetBagItem(gBag, gSlot)
			end

			if repairCost then cost = cost + repairCost end

			-- Dur
			d, m = GetContainerItemDurability(gBag, gSlot)
			if d and m then dur = dur + d; maxDur = maxDur + m end

			-- Make ready for the next round
			gSlot = gSlot + 1
			if gSlot > GetContainerNumSlots(gBag) then
				gBag = gBag + 1
				gSlot = 1
			end

			-- Stop loop
			if endLoop < GetTime() then
				return
			end
		end

		inventoryCost = cost

		if tooltip then
			tooltip:SetCell(inventoryLine, 2, DurabilityText(dur/maxDur))
			tooltip:SetCell(inventoryLine, 3, CopperToString(cost))
		end
		Repair.RenderTotalCost()

		updateRunning = false
		f:Hide()
	end

	function Repair:UpdateInventoryCost()
		if updateRunning or nextUpdateInventory > GetTime() then return end
		--nextUpdateInventory = GetTime() + 2 -- Max update every 2 sec
		updateRunning = true;

		-- Start smal
		inventoryCost = 0;

		tooltip:SetCell(inventoryLine, 2, "..%")
		tooltip:SetCell(inventoryLine, 3, L["Loading"])
		gSlot, gBag = 1, 0
		cost, dur, maxDur = 0, 1, 1

		local nextTime = GetTime()
		f:Show()
	end

	f:Hide()
	f:SetScript("OnUpdate", UpdatePartialInventoryCost)
end
