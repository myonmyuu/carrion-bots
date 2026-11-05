local carrion 	= require "lib.carrion"
local helpers 	= require "lib.helpers"
local ser		= require "lib.serialize"
local fs		= require "lib.fs"
local display	= require "casino.display"
local money		= require "casino.money"

local slots		= require "casino.slots"
--- register symbols
require "casino.slots.default"

local savefolder = fs.join("save", "nosica")
local savepath = fs.join(savefolder, "save.lua")

local casinochannel = "chan-casino@conference.carrion.chat"


local sperm				= 60
local mspers			= 1000
local msperm			= mspers * sperm

local dollarpercent		= 100
local userupdatetime	= 1 * msperm

local warncache			= {}	---@type Carrion.CharID[]

---@param n integer
---@return integer
local function _dollar(n)
	return (n or 0) * dollarpercent
end

local estimatedcharacters	= 70

local playerstartmoney		= _dollar(200)

local startbank				= estimatedcharacters * playerstartmoney * 2
local startreservoir		= startbank * 10
local maxborrowdebt				= playerstartmoney * 5

local debtrelieveperupdate	= math.floor(_dollar(100) / msperm * userupdatetime)
local mindebtpercent		= 0.25
local maxdebtpercent		= 0.75
local mindebtspeed			= 0.25
local maxdebtspeed			= 1

local command_symbol		= "!"


local INTERNAL_CMD_VAL		= "_internal"
local nl					= "\n"


local function _money(amt)
	return money:new(amt)
end

---@class CasinoData
local CasinoData = {
	bank		= 0;
	reservoir	= 0;
	invested	= 0;
	players		= nil;	---@type table<Carrion.CharID, CasinoPlayer>
	mods		= nil;	---@type Carrion.CharID[]
}

---@return CasinoData
local function newcasinodata()
	---@type CasinoData
	local res = {
		bank		= startbank;
		reservoir	= startreservoir;
		invested	= 0;
		players		= {};
		mods		= {};
	}
	return res
end

---@class CasinoPlayer
local PlayerData = {
	casinorelative		= 0;
	reservoirrelative	= 0;
	debt				= 0;
	invested			= 0;
	userrelative		= {};	---@type table<Carrion.CharID, integer>
	updatetime			= 0;
	luck				= 0;
}

---@class Nosica : BotIdentity, CarrionSSEEvents
local Nosica = {
	casinodata	= nil;	---@type CasinoData
	mscache		= {};	---@type table<Carrion.CharID, integer>
}

local print = function (...)
	Nosica.log:debug(...)
end

do --- setup
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
		self.log.level = Logger.levels.debug
		self:request(
			carrion.Api.presence.subscribe,
			carrion:makehttpcontent {
				rooms = {
					casinochannel,
				};
			}
		)

		carrion.Events.cmd:register(self, function (cmd)
			self:parsecommand({
				message		= command_symbol..tostring(cmd);
				is_dm		= true;
				room_id		= INTERNAL_CMD_VAL;
				sender		= {
					avatar	= INTERNAL_CMD_VAL;
					badges	= {};
					id		= -1;
					name	= INTERNAL_CMD_VAL;
				};
				tab_id		= INTERNAL_CMD_VAL;
				timestamp	= INTERNAL_CMD_VAL;
				type		= INTERNAL_CMD_VAL;
			})
		end)

		self:subtodms()
	end
end

do --- messaging
	---@param to CarrionMessage
	---@param f string
	---@param ... any
	function Nosica:replyF(to, f, ...)
		self:reply(to, f:format(...))
	end
	---@param message string
	---@param replyto CarrionMessage
	function Nosica:reply(replyto, message)
		self.log:debugF("replying with '%s'", message:sub(1, math.min(50, message:len())))

		local ok, err = pcall(function ()
			if replyto.is_dm then
				self:senddm(message, nil, replyto.sender.name, replyto.sender.id, replyto.tab_id)
			else
				self:request(
					carrion.Api.channels.send(replyto.room_id),
					carrion:makehttpcontent {
						body	= message;
						tab_id	= replyto.tab_id;
					}
				)
			end
		end)

		if not ok then
			self.log:warningF("unable to reply to user '%s': '%s'", replyto.sender.name, tostring(err))
		end
	end

	---@param message CarrionMessage
	---@return boolean
	function Nosica:handlemessage(message)
		if message.sender.id == self.id then
			return true
		end
		self.log:infoF("%s (%i): %s", message.sender.name, message.sender.id, message.message)
		return self:parsecommand(message)
	end
end

do --- player management
	---@param id Carrion.CharID
	---@return boolean
	function Nosica:ismod(id)
		return id == -1 or table.contains(self.casinodata.mods, id)
	end

	function Nosica:requiremod(id)
		if not self:ismod(id) then
			error("no authentication")
		end
	end

	---@param id Carrion.CharID
	---@return boolean, CasinoPlayer
	function Nosica:trygetplayer(id)
		local player = self.casinodata.players[id]
		if player then
			return true, player
		end
---@diagnostic disable-next-line: return-type-mismatch
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
			userrelative		= {};
			debt				= 0;
			invested			= 0;
			updatetime			= carrion:gettimems();
		}
		self.casinodata.players[id] = newplayer
		return newplayer
	end

	---@param user CasinoPlayer
	---@param id Carrion.CharID
	function Nosica:updateplayer(user, id)
		local mes = ("updating user id (%i)."):format(id)
		if user.debt > 0 then
			local recspeed = self:getdebtrecoverspeed(user)
			local debtrecamt = _money(debtrelieveperupdate * recspeed)
			mes = mes .. (" recovery speed: %f (%s)"):format(recspeed, debtrecamt)
			self:removedebt(user, debtrecamt)
		end
		self.log:verbose(mes)
	end

	function Nosica:updateplayers()
		local time = carrion:gettimems()

		for id, user in pairs(self.casinodata.players) do
			if time < user.updatetime then
				goto continue
			end

			self:updateplayer(user, id)
			user.updatetime = user.updatetime + userupdatetime

		    ::continue::
		end
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

	---@param from CasinoPlayer
	---@param to CasinoPlayer
	---@param amt Money
	function Nosica:transfermoneybetween(from, to, amt)
		self:ensurerelativevaluesfor(from, to)
		self:ensurerelativevaluesfor(to, from)

		from.userrelative[to] = from.userrelative[to] - amt.raw
		to.userrelative[from] = to.userrelative[from] + amt.raw
	end

	---@param user CasinoPlayer
	---@param other CasinoPlayer
	function Nosica:ensurerelativevaluesfor(user, other)
		user.userrelative = user.userrelative or {}
		local value = user.userrelative[other]
		if not value then
			value = 0
			user.userrelative[other] = value
		end
		return value
	end

	---@param user CasinoPlayer
	---@param amt Money|integer
	function Nosica:drainreservoir(user, amt)
		if type(amt) == "number" then
			amt = _money(amt)
		end

		self.casinodata.reservoir = self.casinodata.reservoir - amt.raw
		user.reservoirrelative = user.reservoirrelative + amt.raw
	end

	---@param user CasinoPlayer
	---@param amt Money|integer
	function Nosica:paydebt(user, amt)
		if type(amt) == "number" then
			amt = _money(amt)
		end
		---@cast amt Money

		amt:clamptouser(self, user)

		self.casinodata.reservoir = self.casinodata.reservoir + amt.raw
		user.reservoirrelative = user.reservoirrelative - amt.raw
		self:removedebt(user, amt)
	end

	---@param user CasinoPlayer
	---@param amt Money
	function Nosica:removedebt(user, amt)
		user.debt = math.max(0, user.debt - amt.raw)
	end

	---@param user CasinoPlayer
	---@param amt Money|integer
	function Nosica:adddebt(user, amt)
		if type(amt) == "number" then
			amt = _money(amt)
		end
		---@cast amt Money
		user.debt = user.debt + amt.raw
	end

	---@param user CasinoPlayer
	---@return Money
	function Nosica:getplayermoney(user)
		local userrelative = 0
		for _, value in pairs(user.userrelative) do
			userrelative = userrelative + value
		end
		return _money(user.casinorelative + user.reservoirrelative + userrelative - user.invested)
	end

	---@param user CasinoPlayer
	---@param amt Money
	function Nosica:invest(user, amt)
		if user.debt > 0 then
			self.log:warning("tried to invest on a indebted user")
			return
		end

		amt:clamptouser(self, user)
		if amt.raw < 0 then
			self.log:warning("tried to invest a negative amount")
			return
		end

		self.casinodata.invested = self.casinodata.invested + amt.raw
		user.invested = user.invested + amt.raw
	end

	---@param user CasinoPlayer
	function Nosica:getdebtrecoverspeed(user)
		local percent = user.debt / maxborrowdebt

		if percent >= maxdebtpercent then
			return maxdebtspeed
		elseif percent <= mindebtpercent then
			return mindebtspeed
		end

		local t = (percent - mindebtpercent) / (maxdebtpercent - mindebtpercent)

		return math.lerp(mindebtspeed, maxdebtspeed, t)
	end
end

do --- commands
	local Commands = {
		private	= {};	---@type table<string, fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer?)>
		user	= {};	---@type table<string, fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer)>
		public	= {};	---@type table<string, fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer?)>
		help	= {};	---@type table<string, fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer):string|nil>
	}
	---@param mes CarrionMessage
	---@return boolean
	function Nosica:parsecommand(mes)
		self.log:verbose(("parsing for command: '%s'"):format(mes.message))
		local commandname = mes.message:match(command_symbol .. "(%w+)")
		if not commandname then
			self.log:verbose("no possible command name")
			return false
		end
		local command
		for _, value in pairs({
			Commands.private,
			Commands.user,
			Commands.public,
		}) do
			command = value[commandname]
			if command then
				break
			end
		end

		if not command then
			self.log:verbose("no command found")
			return false
		end

		local ok, err = pcall(command, self, mes, self.casinodata.players[mes.sender.id])
		if not ok then
			self.log:warningF("error running command %s: '%s'", commandname, tostring(err))
		end
		return true
	end

	----
	local cmds
	---@param name string
	---@param f fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer)
	---@param h? fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer):string|nil
	local function newcmd(name, f, h)
		if not cmds then
			print("cmds is nil on cmd setup")
			return
		end
		cmds[name] = f
		Commands.help[name] = h
	end

	do ---- public
		cmds = Commands.public
		newcmd("help", function (nosica, mes, user)
			-- if (not mes.is_dm) and (not nosica:ismod(mes.sender.id)) then
			-- 	nosica:reply(mes, "Ask again in a DM!")
			-- 	return
			-- end

			local r = "Here's your available commands;"..nl
			---@param t table<string, fun(nosica:Nosica, mes:CarrionMessage, user: CasinoPlayer?)>
			local function _appendhelpfor(t)
				for name, f in pairs(t) do
					local h = Commands.help[name]
					if h then
						local hres = h(nosica, mes, user)
						if hres then
							r = r .. ([[- `!%s`: %s]]):format(name, hres) .. nl
						end
					end
				end
			end

			if nosica:ismod(mes.sender.id) then
				_appendhelpfor(Commands.private)
			end

			if user then
				_appendhelpfor(Commands.user)
			end

			_appendhelpfor(Commands.public)

			nosica:reply(mes, r)
		end, function (...)
			return "Show this info."
		end)
		newcmd("start", function (nosica, mes, user)
			if user then
				nosica:reply(mes, "You're already a user!")
				return
			end

			local moni = _money(playerstartmoney)
			nosica:replyF(
				mes,
				"Welcome to THE Casino, %s! You have been awarded a one-time beginner bonus of %s!",
				mes.sender.name,
				moni
			)
			user = nosica:createplayer(mes.sender.id)
			nosica:transfermoneyto(user, moni)
		end, function (nosica, mes, user)
			local res = "Create a Nosica user profile to gain access to all of the casino's functionality!"
			if not user then
				res = ("{color:gray}(Already registered) %s{/color}"):format(res)
			end
			return res
		end)
		newcmd("bank", function (nosica, mes, user)
			nosica:replyF(
				mes,
				"Our humble bank currently holds %s!",
				_money(nosica.casinodata.bank)
			)
		end, function (nosica, mes, user)
			return "Show how much money the casino's bank holds."
		end)
		newcmd("world", function (nosica, mes, user)
			local bank		= ("The casino bank holds %s."):format(_money(nosica.casinodata.bank))
			local reserve	= ("The global money reserves are at %s."):format(_money(nosica.casinodata.reservoir))
			local invested	= nosica.casinodata.invested > 0
				and ("%s has been invested!"):format(_money(nosica.casinodata.invested))
				or "Nobody has invested money yet."

			local r = ("%s %s\n%s"):format(bank, reserve, invested)

			nosica:reply(mes, r)
		end, function (nosica, mes, user)
			return "Show what state the Nosica-world financial state is at."
		end)
	end

	do ---- user
		cmds = Commands.user
		newcmd("funds", function (nosica, mes, user)
			print("getting user funds for "..mes.sender.id)

			local replymessage = ([[%s, you currently have %s available in funds!]])
				:format(mes.sender.name, nosica:getplayermoney(user))

			if user.debt > 0 then
				replymessage = replymessage .. (([[ You are %s in debt.]]):format(_money(user.debt)))
			end

			nosica:reply(mes, replymessage)
		end, function (nosica, mes, user)
			return "Show how much money and debt you have currently."
		end)

		newcmd("rub", function (nosica, mes, user)
			
		end)

		newcmd("send", function (nosica, mes, user)
			local other_name, amount = mes.message:match([[^.-!send%s+"(.-)"%s+([%w%p]+)]])
			if not other_name or not amount then
				nosica:replyF(mes, [[Unable to transfer money, check amount formatting or user name. Make sure to wrap the name in `"`s!]])
				return
			end
			local idok, id = pcall(carrion.getuserid, carrion, other_name, nosica)
			if not idok then
				nosica:replyF(mes, [[Unable to find character with the name '%s'.]], other_name)
				return
			end
			local plrok, other = nosica:trygetplayer(id)
			if not plrok then
				nosica:replyF(mes, [[@[%s] has not registered with the casino!]], other_name)
				return
			end
			local moniok, moni = money:tryfromstr(amount)
			if not moniok then
				nosica:reply(mes, [[Unable to parse transfer amount, double check your formatting.]])
			end
			moni:clamptouser(nosica, user)
			nosica:transfermoneybetween(user, other, moni)
			nosica:replyF(mes, [[Transferred %s from @[%s] to @[%s].]], moni, mes.sender.name, other_name)
		end, function (nosica, mes, user)
			return ([[Send money to another registered user. Pass along both the name (in "s) and the amount. Ex; `!send "%s" 100.54`]]):format(mes.sender.name)
		end)

		newcmd("borrow", function (nosica, mes, user)
			local amount = mes.message:match([[^.-!borrow%s+(.+)]])

			local moni = money:fromstr(amount)
			print("moni amount for borrow: ", moni, amount)
			if not moni then
				-- nosica:reply(mes, [[Unable to parse amount of money.]])
				-- return
				moni = _money(maxborrowdebt)
			end

			moni.raw = math.min(moni.raw, maxborrowdebt - user.debt)
			if moni.raw <= 0 then
				nosica:reply(mes, [[Sorry, you've borrowed as much as allowed! Wait a bit and repay your debt first.]])
				return
			end

			nosica:adddebt(user, moni)
			nosica:drainreservoir(user, moni)
			nosica:replyF(mes, [[You've borrowed %s. The same amount was added to your debt.]], moni)
		end, function (nosica, mes, user)
			return ("Borrow money from the Nosica-verse money reserve. This money is added as debt that dereases over time (limit is %s)"):format(_money(maxborrowdebt))
		end)

		newcmd("invest", function (nosica, mes, user)
			if user.debt > 0 then
				nosica:replyF(mes, "Take care of your debt first! You owe the banks %s!", _money(user.debt))
				return
			end

			local amount = mes.message:match [[^.-!invest%s(.+)]]
			local moniok, moni = money:tryfromstr(amount)
			if not moniok then
				nosica:reply(mes, "I need a correctly-formatted number for the investment amount!")
				return
			elseif moni.raw <= 0 then
				nosica:reply(mes, "The invested amount needs to be greater than zero!")
				return
			end

			nosica:invest(user, moni)
			nosica:replyF(mes, [[An investment of %s was confirmed!]], moni)
		end, function (nosica, mes, user)
			return [[Take money out of the economy by "investing" it! Pass along an amount.]]
		end)

		newcmd("slots", function (nosica, mes, user)
			local grid = slots:randomgrid(user.luck)

			local x, monistr = mes.message:match("^.-slots%s(%d)%s([^%s]+)")
			if not x then
				nosica:reply(mes, "You need to tell me how many tracks you want to have active!")
				return
			end

			x = tonumber(x)
			if not x then
				nosica:reply(mes, "Your given track count was not a number...")
				return
			end

			if x <= 0 or x > 5 then
				nosica:reply(mes, "You need to choose between one and five tracks!")
				return
			end

			if not monistr then
				nosica:reply(mes, "You need to choose your bet!")
				return
			end
			local ok, moni = money:tryfromstr(monistr)
			if not ok then
				nosica:reply(mes, "That wasn't a properly formatted bet number...")
				return
			end

			local totalbet = _money(moni.raw * x)

			local usermoney = nosica:getplayermoney(user)
			if totalbet.raw > usermoney.raw then
				nosica:replyF(mes, "You don't have the %s for that spin. You need %s more.", totalbet, _money(totalbet.raw - usermoney.raw))
				return
			end

			nosica:transfermoneyfrom(user, totalbet)
			local winners = grid:getwinners(x)
			local winamt = 0
			for _, value in pairs(winners) do
				winamt = winamt + (value.symbol.payout * moni.raw)
			end
			if winamt > 0 then
				nosica:transfermoneyto(user, _money(winamt))
			end

			-- local res = display:outer(
			-- 	display:slotgrid(grid, x)
			-- )
			nosica:reply(
				mes,
				display:slotroll(
					grid,
					x,
					totalbet,
					_money(winamt),
					usermoney
				)
			)
		end, function (nosica, mes, user)
			return [[Play the slots! Supply a number for the active tracks and a bet. Ex:
	`!slots 3 50` - roll the first three tracks for $50 each.
	`!slots 5 30.30` - roll all tracks for $30.30 each.
	<sub>The first three tracks are the horizontal ones; middle, top, bottom. 4 is top-left to bottom-right and 5 is bottom-left to top-right.</sub>]]
		end)
	end

	do ---- private
		cmds = Commands.private
		newcmd("querydms", function (nosica, mes)
			nosica:readdms()
		end)
		newcmd("reset", function (nosica, mes)
			nosica:reset()
		end)

		newcmd("setbank", function (nosica, mes)
			local target, amount = mes.message:match([[^.-!setbank%s+(%w)%s+(%w+)]])
			if not target or not amount then
				nosica.log:warning("unable to get amount or target for setbank:", target, amount)
				return
			end

			local amt = tonumber(amount)
			if not amt then
				nosica.log:warningF("unable to parse '%s' to number for setbank", amount)
				return
			end
			amt = math.floor(amt)

			if target == "b" then
				nosica.casinodata.bank = amt
			elseif target == "r" then
				nosica.casinodata.reservoir = amt
			else
				nosica.log:warningF("invalid target '%s' for setbank", target)
			end
		end)

		newcmd("slotstest", function (nosica, mes, user)
			local winners = {} ---@type SlotWinner[]
			local rollcount = tonumber(mes.message:match("^.-slotstest%s(%w+)")) or 100
			local winningrolls = 0
			local winvalue = 0
			local losestreak = 0
			local maxlosestreak = 0
			local jackpots = 0
			for i = 1, rollcount do
				local grid = slots:randomgrid(user.luck)
				local rollwinners = grid:getwinners(5)
				local rollworth = 0
				for key, value in pairs(rollwinners) do
					table.insert(winners, value)
					rollworth = rollworth + value.symbol.payout
				end
				winvalue = winvalue + rollworth
				if rollworth > 45 then
					jackpots = jackpots + 1
				end
				if #rollwinners > 0 then
					winningrolls = winningrolls + 1
					losestreak = 0
				else
					losestreak = losestreak + 1
					if losestreak > maxlosestreak then
						maxlosestreak = losestreak
					end
				end
			end
			nosica:replyF(mes, "Won rolls: %i/%i Total winners: %i, percent: %.2f%%, value/spin: %.2f, total value: %i, max lose streak: %i, jackpots: %i",
				winningrolls, rollcount,
				#winners,
				(winningrolls / rollcount) * 100,
				winvalue / rollcount,
				winvalue,
				maxlosestreak,
				jackpots
			)
			-- nosica:replyF(mes, "Slots;\n%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s", table.unpack(table.map(grid.symbols, function (k, v)
			-- 	return v.name
			-- end)))
		end, function (nosica, mes, user)
			return "Test the slots!"
		end)
	end

	----

	do ---- command guards
		for name, cmd in pairs(Commands.private) do
			Commands.private[name] = function (nosica, mes, ...)
				nosica:requiremod(mes.sender.id)
				cmd(nosica, mes, ...)
			end
		end

		for name, cmd in pairs(Commands.user) do
			Commands.user[name] = function (nosica, mes, user)
				if not user then
					nosica:reply(mes, "You need to be a registered user! use `!start` in the channel!")
					return
				end
				cmd(nosica, mes, user)
			end
		end
	end
end

do --- sse
	---@param data sse.EventData.channel_message
	function Nosica:channel_message(data)
		self:handlemessage(carrion:unifychatmessage(data))
	end

	---@param message string
	---@param ev sse.EventData.dm_message
	function Nosica:dm(message, ev)
		local chmes = carrion:unifychatmessage(ev, message)
		local succ = self:handlemessage(chmes)
		if (not succ) and not table.contains(warncache, ev.from_id) then
			self:reply(chmes, "I'm a bot; Run `!help` for my commands!")
			table.insert(warncache, ev.from_id)
		end
	end

	---@param room string
	---@param user carrionuser
	---@param role ChannelRole
	function Nosica:userjoined(room, user, role)
		if (not role) or role == "participant" then
			-- we do not care
			return
		end
		-- self.log:verbose("saw mod;", helpers.topstring(data))
		if room ~= casinochannel then
			self.log:verbose("isn't in our channel-")
			return
		end
		local id = user.id
		if table.contains(self.casinodata.mods, id) then
			self.log:verbose("is already modded")
			return
		end
		self.log:infoF("registering mod '%s' (%i)", user.name, id)
		table.insert(self.casinodata.mods, id)
	end
end

do --- events
	function Nosica:heartbeat(dt)
		carrion.BotIdentity.heartbeat(self, dt)

		self:updateplayers()
		self:savedata()
	end
end

return Nosica