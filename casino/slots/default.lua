local slots		= require "casino.slots"

local smallluckb	= 0.05
local payoutbonus	= 1.5
local ret = {}

---@param s SlotSymbol
local function _reg(s)
	slots:registersymbol(s)
	ret[s.name] = s
end

_reg {
	name		= "cherry";
	luckbonus	= -smallluckb * 2;
	payout		= 4 * payoutbonus;
	weight		= 10;
	icon		= "https://cdn.imgchest.com/files/84f32eafe9b8.png";
}

_reg {
	name		= "eggplant";
	luckbonus	= -smallluckb;
	payout		= 6 * payoutbonus;
	weight		= 8;
	icon		= "https://cdn.imgchest.com/files/30f4901b7d8e.png";
}

_reg {
	name		= "cigarette";
	luckbonus	= smallluckb * 2;
	payout		= 9 * payoutbonus;
	weight		= 7;
	icon		= "https://cdn.imgchest.com/files/ec7674f49ebe.png";
}

_reg {
	name		= "hypnospiral";
	luckbonus	= smallluckb;
	payout		= 15 * payoutbonus;
	weight		= 5;
	icon		= "https://cdn.imgchest.com/files/c343e392cde0.png";
}

_reg {
	name		= "transflag";
	luckbonus	= smallluckb * 3;
	payout		= 50 * payoutbonus;
	weight		= 2.5;
	icon		= "https://cdn.imgchest.com/files/c0af49c65768.png";
}

return ret