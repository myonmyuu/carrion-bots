local carrion 	= require "lib.carrion"
local helpers 	= require "lib.helpers"
local ser		= require "lib.serialize"
local fs		= require "lib.fs"

local savefolder = fs.join("save", "nosica")
local savepath = fs.join(savefolder, "save.lua")

local casinochannel = "chan-casino@conference.carrion.chat"

local startbank	= 200000000000
local startreservoir = 1000000000000
local playerstart = 2000

local INTERNAL_CMD_VAL = "_internal"

---@param n any
---@return integer
local function sanitizenumber(n)
	if type(n) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(n))
end

---@class Money
local Money = {
	raw	= 0;	---@type integer
}

---@param raw integer
---@return Money
function Money:new(raw)
	raw = sanitizenumber(raw)
	return setmetatable({
		raw = raw;
	}, {
		__index = self;
	})
end

---@class CasinoData
local CasinoData = {
	bank		= 0;
	reservoir	= 0;
	players		= nil;	---@type table<Carrion.CharID, CasinoPlayer>
	mods		= nil;	---@type Carrion.CharID[]
}

---@return CasinoData
local function newcasinodata()
	---@type CasinoData
	local res = {
		bank		= startbank;
		reservoir	= startreservoir;
		players		= {};
		mods		= {};
	}
	return res
end

---@class CasinoPlayer
local PlayerData = {
	casinorelative		= 0;
	reservoirrelative	= 0;

	luck				= 0;
}

---@class Nosica : BotIdentity, CarrionSSEEvents
local Nosica = {
	casinodata	= nil;	---@type CasinoData
}

function Nosica:reset()
	self.log:info("resetting data...")
	self.casinodata = newcasinodata()
end

function Nosica:loaddata()
	self.log:info("loading data...")
	---@type CasinoData?
	local data
	if fs.exists(savepath) then
		self.log:info("data exists, reading...")
		local str = fs.read(savepath)
		-- self.log:info(str)
		data = ser.load(str)
	end

	if not data then
		self.log:info("creating new data!")
		data = newcasinodata()
	end

	self.casinodata	= data
	self.casinodata.players = self.casinodata.players or {}
	self.casinodata.mods = self.casinodata.mods or {}
end

function Nosica:savedata()
	self.log:info("saving...")
	fs.create_directory(savefolder)
	fs.write(savepath, ser.tostring(self.casinodata))
end

function Nosica:shutdown()
	self:savedata()
end

function Nosica:postlogin()
	self:request(
		carrion.Api.presence.subscribe,
		carrion:makehttpcontent {
			rooms = {
				casinochannel,
			};
		}
	)

	carrion.Events.cmd:register(self, function (cmd)
		self:parsecommand {
			body		= cmd;
			message_id	= INTERNAL_CMD_VAL;
			room_jid	= INTERNAL_CMD_VAL;
			sender		= {
				avatar	= INTERNAL_CMD_VAL;
				badges	= {};
				id		= -1;
				name	= INTERNAL_CMD_VAL;
			};
			tab_id		= INTERNAL_CMD_VAL;
			timestamp	= INTERNAL_CMD_VAL;
			type		= INTERNAL_CMD_VAL;
		}
	end)
end

---@param id Carrion.CharID
---@return boolean
function Nosica:ismod(id)
	return id == -1 or table.contains(self.casinodata.mods, id)
end

do --- player management
	---@param id Carrion.CharID
	---@return boolean, CasinoPlayer?
	function Nosica:trygetplayer(id)
		local player = self.casinodata.players[id]
		if player then
			return true, player
		end
		return false, nil
	end
	---@param id Carrion.CharID
	---@return CasinoPlayer
	function Nosica:ensureplayer(id)
		local ok, plr = self:trygetplayer(id)
		if not ok then
			plr = self:createplayer(id)--[[@cast plr CasinoPlayer]]
		end
		return plr
	end
	---@param id Carrion.CharID
	---@return CasinoPlayer
	function Nosica:createplayer(id)
		---@type CasinoPlayer
		local newplayer = {
			luck	= 0;
			casinorelative		= 0;
			reservoirrelative	= 0;
		}
		self.casinodata.players[id] = newplayer
		return newplayer
	end
end

do --- money management
	---@param user CasinoPlayer
	---@param amt Money
	function Nosica:transfermoneyto(user, amt)
		self.casinodata.bank = self.casinodata.bank - amt.raw
		user.casinorelative = user.casinorelative + amt.raw
	end

	---@param user CasinoPlayer
	---@param amt Money
	function Nosica:transfermoneyfrom(user, amt)
		self.casinodata.bank = self.casinodata.bank + amt.raw
		user.casinorelative = user.casinorelative - amt.raw
	end

	---@param user CasinoPlayer
	---@return integer
	function Nosica:getplayermoney(user)
		return user.casinorelative + user.reservoirrelative
	end
end

do --- commands
	local Commands = {}	---@type table<string, fun(nosica:Nosica, mes:sse.EventData.channel_message)>
	---@param mes sse.EventData.channel_message
	function Nosica:parsecommand(mes)
		self.log:verbose(("parsing for command: '%s'"):format(mes.body))
		local commandname = mes.body:match("^.-([^ ]+).-")
		if not commandname then
			self.log:verbose("no possible command name")
			return
		end
		local command = Commands[commandname]
		if not command then
			self.log:verbose("no command found")
			return
		end

		command(self, mes)
	end

	function Commands.start(nosica, mes)
		
	end
	function Commands.querydms(nosica, mes)
		if not nosica:ismod(mes.sender.id) then return end
		nosica:readdms()
	end
	function Commands.reset(nosica, mes)
		if not nosica:ismod(mes.sender.id) then return end
		nosica:reset()
	end
end

do --- sse
	---@param data sse.EventData.channel_message
	function Nosica:channel_message(data)
		self.log:info(data.body)
		self:parsecommand(data)
	end

	-- function Nosica:dm_message(data)
	-- 	self.log:info("dm received:", helpers.topstring(data))
	-- end

	---@param message string
	---@param ev sse.EventData.dm_message
	function Nosica:dm(message, ev)
		self.log:infoF("got dm; '%s' from %s (%i)", message, ev.from, ev.from_id)
	end

	---@param data sse.EventData.user_joined_room
	function Nosica:sawmod(data)
		self.log:verbose("saw mod;", helpers.topstring(data))
		if data.room ~= casinochannel then
			self.log:verbose("isn't in our channel-")
			return
		end
		local id = self.carrion:getuserid(data.character, self)
		if table.contains(self.casinodata.mods, id) then
			self.log:verbose("is already modded")
			return
		end
		self.log:infoF("registering mod '%s' (%i)", data.character, id)
		table.insert(self.casinodata.mods, id)
	end
end

return Nosica