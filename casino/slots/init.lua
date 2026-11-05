local helpers	= require "lib.helpers"
local logger	= require "lib.log"
local slotlog	= logger:spec("slots")
local function print(...) slotlog:debug(...) end

---@class SlotSymbol
local SlotSymbol = {
	name		= "";
	weight		= 1;
	payout		= 2;
	luckbonus	= 0;
	icon		= "https://cdn.imgchest.com/files/42de65cea545.png"; ---@type string?
};

---@param other SlotSymbol
---@return boolean
function SlotSymbol:fits(other)
	return other.name == self.name
end

---@class Slots
local Slots = {
	registeredsymbols	= {};	---@type table<string, SlotSymbol>
}

--[[
reel indices
1  2  3
4  5  6
7  8  9
]]

local wintracks = {
	[1] = { 4, 5, 6 }; ---- middle, straight
	[2] = { 1, 2, 3 }; ---- top, straight
	[3] = { 7, 8, 9 }; ---- bottom, straight
	[4] = { 1, 5, 9 }; ---- topleft to bottomright
	[5] = { 7, 5, 3 }; ---- bottomleft to topright
}
local trackindices = {
	{ 2, 4 };
	{ 2 };
	{ 2, 5 };
	{ 1 };
	{ 1, 4, 5 };
	{ 1 };
	{ 3, 5 };
	{ 3 };
	{ 3, 4 };
}

---@class SlotGrid
local SlotGrid = {
	symbols	= {};	---@type SlotSymbol[]
}

function SlotGrid:new()
	return setmetatable({
		symbols	= {};
	}, { __index = self })
end

---@param luck number?
---@return SlotSymbol
function Slots:rollsymbol(luck)
	local symbolname = table.weightedrandom(self.registeredsymbols, function (v)
		return math.max(0, v.weight + v.luckbonus * (luck or 0))
	end)
	if not symbolname then
		error("problem getting random weighted symbol")
	end
	return self.registeredsymbols[symbolname]
end

---@param s SlotSymbol
function Slots:registersymbol(s)
	s = setmetatable(s or {}, { __index = SlotSymbol })
	self.registeredsymbols[s.name] = s
	return s
end

---@param luck number?
---@return SlotGrid
function Slots:randomgrid(luck)
	local grid = SlotGrid:new()
	for _ = 1, 9 do
		table.insert(grid.symbols, self:rollsymbol(luck))
	end
	return grid
end

function SlotGrid:gettrack(i)
	if i > 5 or i <= 0 then
		slotlog:warningF("tried to get track with invalid index '%i'", i)
		i = math.max(0, math.min(i, 5))
	end
	return wintracks[i]
end

function SlotGrid:getslottrackindices(sloti)
	return trackindices[sloti] or {}
end

---@class SlotWinner
---@field track		integer
---@field symbol	SlotSymbol

---@param x integer active tracks
---@return SlotWinner[]
function SlotGrid:getwinners(x)
	local winners = {}	---@type SlotWinner[]
	if x > 5 or x <= 0 then
		slotlog:warningF("tried to get winners with invalid track count '%i'", x)
		x = math.max(0, math.min(x, 5))
	end
	for i = 1, x do
		local track = self:gettrack(i)
		local win
		for symboli = 1, 3 do
			local symbol	= self.symbols[track[symboli]]
			local other		= self.symbols[track[math.wrap(1, 3, symboli + 1)]]
			local ok		= symbol:fits(other) or other:fits(symbol)
			if not ok then
				win = nil
				break
			else
				local symbols = { symbol, other, win }
				table.sort(symbols, function (a, b)
					return a.payout > b.payout
				end)
				win = symbols[1]
			end
		end
		if win then
			table.insert(winners, {
				symbol	= win;
				track	= i;
			}--[[@as SlotWinner]])
		end
	end
	return winners
end

Slots.SlotSymbol	= SlotSymbol;
Slots.SlotGrid		= SlotGrid;
return Slots
