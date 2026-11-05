local helpers	= require "lib.helpers"
local html		= require "lib.htmlua"
local style		= require("lib.style"):new("style/casino.css")
local money		= require "casino.money"

---@class CasinoDisplay
local CasinoDisplay = {
	style	= style;
	html	= html;
}

local function test()
	local e = html.div {
	html.div {
			style = style:classes("outer");
			"asd"
		}
	}
	print(e)
end

---@param ... any
---@return string
function CasinoDisplay:outer(...)
	return self.html.div {
		style = style:classes("outer");
		...
	}
end

---@param symbol SlotSymbol
---@param active boolean
---@param win boolean
---@return string
function CasinoDisplay:slotitem(symbol, active, win)
	local slotclasses = {"slotitem"}
	if not active then
		table.insert(slotclasses, "inactive")
	elseif win then
		table.insert(slotclasses, "win")
	end
	return self.html.div {
		style = self.style:classest(slotclasses);
		self.html.img {
			style = self.style:classes("sloticon");
			src = symbol.icon;
		}
	}
end

---@param grid SlotGrid
---@param x integer amount of active rows 1|3|7
---@return string
function CasinoDisplay:slotgrid(grid, x)
	local winners = grid:getwinners(x)
	return self.html.div {
		style = style:classes("slotbox");
		table.map(grid.symbols, function (symboli, symbol)
			return self:slotitem(
				symbol,
				table.any(grid:getslottrackindices(symboli), function (_, tracki)
					return x >= tracki
				end),
				table.any(grid:getslottrackindices(symboli), function (_, tracki)
					return table.contains(table.map(winners, function (_, winner)
						return winner.track
					end), tracki)
				end)
			)
		end)
	}
end

---@param grid SlotGrid
---@param x integer
---@param bet Money
---@param winnings Money
---@param prevmoney Money
---@return string
function CasinoDisplay:slotroll(grid, x, bet, winnings, prevmoney)
	local diff = winnings.raw - bet.raw
	return self:outer(
		self.html.div {
			style = style:classes("hbox");
			self.html.div {
				self.html.p { ("Previous balance: %s"):format(prevmoney) },
				self.html.p { ("Total bet: %s"):format(bet) },
			},
			self:slotgrid(grid, x),
			self.html.div {
				self.html.p { ("Total difference: %s"):format(money:new(diff)) },
				self.html.p { ("New balance: %s"):format(money:new(prevmoney.raw + diff)) },
			}
		}
	)
end

return CasinoDisplay