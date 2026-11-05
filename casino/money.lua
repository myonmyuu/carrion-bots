local currency_symbol_pre	= "$"
local currency_symbol_post	= ""
local _nomoney = nil ---@type Money

---@param n any
---@return integer
local function sanitizenumber(n)
	if type(n) ~= "number" then
		return 0
	end
	return math.floor(n)
end

---@class Money
local Money = {
	SymbolPre	= currency_symbol_pre;
	SymbolPost	= currency_symbol_post;
	raw			= 0;	---@type integer
}

local function _money(amt)
	return Money:new(amt)
end

---@param raw integer
---@return Money
function Money:new(raw)
	raw = sanitizenumber(raw)
	return setmetatable({
		raw = raw;
	}, {
		__index		= self;
		__tostring	= function (t)
			local r = tostring(t.raw)
			if r:len() < 3 then
				return currency_symbol_pre.."0."..r..currency_symbol_post
			end
			r = r:gsub("(-?%d+)(%d%d)", currency_symbol_pre .. "%1.%2" .. currency_symbol_post)
			return r
		end;
	})
end


---@param str string
---@return boolean
---@return Money
function Money:tryfromstr(str)
	if not str then
		return false, _nomoney
	end
	local parts = str
		:gsub(currency_symbol_pre, "")
		:gsub(currency_symbol_post, "")
		:split("%p")
	local sanitized = ""
	if #parts == 1 then
		table.insert(parts, "00")
	end
	for i, value in ipairs(parts) do
		if i > 0 and i == #parts then
			if value:len() > 2 then
				value = value:sub(1, 2)
			elseif value:len() < 2 then
				value = value .. "0"
			end
		end
		sanitized = sanitized..value
	end
	local num = tonumber(sanitized:match("(%d+)"))
	return num ~= nil, _money(num and math.floor(num) or 0)
	-- if #parts == 1 then
	-- 	local num = tonumber(parts[1]:match("(%d+)"))
	-- 	return num ~= nil, _money(num and math.floor(num) or 0)
	-- end
	-- return Money:new()
end

---@param str string
---@return Money?
function Money:fromstr(str)
	local ok, res = self:tryfromstr(str)
	return (ok and {res} or {nil})[1]
end

---@param nosica Nosica
---@param user CasinoPlayer
function Money:clamptouser(nosica, user)
	local max = nosica:getplayermoney(user)
	self.raw = math.min(self.raw, max.raw)
end

return Money