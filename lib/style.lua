local helpers	= require "lib.helpers"
local zss		= require "lib.zss"
local fs		= require "lib.fs"

---@class CBStyle
local CBStyle = {
	inner	= nil;	---@type ZSS
}

---@param ... string
---@return CBStyle
function CBStyle:new(...)
	local o = {
		inner	= zss:new {};
	}--[[@as CBStyle]]
	for _, value in pairs({...}) do
		o.inner:load(fs.join(fs.join(fs.parent(BasePath), "carrion-bots"), tostring(value)))
	end
	return setmetatable(o, { __index = self })
end

function CBStyle:match(opt)
	return self.inner:match(opt)
end

---@param classes table<integer, string>
---@return string
function CBStyle:classest(classes)
	local tags = table.mapk(classes, function (k, v)
		return v, true
	end)
	local vals = self:match { tags = tags }
	return table.concat(table.map(vals, function (k, v)
		return ("%s: %s"):format(k, tostring(v))
	end), ";")
end

---@param ... string
---@return string
function CBStyle:classes(...)
	local classes = {...}
	return self:classest(classes)	
end

return CBStyle