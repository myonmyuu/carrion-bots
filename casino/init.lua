local carrion 	= require "lib.carrion"

local Nosica = require "casino.nosica"

local casinolog = Logger:spec("Casino")

do --- startup
	casinolog:info("Casino starting...")

	local ok, token = GetToken("nosica")
	if not ok then
		casinolog:error("unable to get token for Nosica")
		return
	end

	local nosica = carrion.BotIdentity:create("Nosica", token, carrion, Nosica)

	nosica:loaddata()
	if table.contains(arg, "reset") then
		casinolog:info("reset requested, input 'y' to confirm")
		local conf = io.read()
		if conf == "y" then
			nosica:reset()
		end
	end

	nosica:login()
end