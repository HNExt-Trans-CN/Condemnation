local arg = require("arg")
local iter = require("iter")
local util = require("util")
local fifo = require("fifo")
local stack = require("stack")
local list = require("list")

local getopt = {}

-- for `chaos` = false:
--      '--' supported, opt args must follow opt directly.
--      `long` specifies if long options are supported
--      `argopt` specifies if arguments that "look like" options are permitted (for instance, '-- -a').
--      `order` may be
--              * "first": options must precede arguments
--              * "any": options can be anywhere, mixed with other args
--              * "clump": options can be anywhere, but must be together
--	'dashmode` may be
--		* "stop": '--' stops opt processing
--		* "skip": '--' skips arg for opt processing
-- for `chaos` = true
--      '--' not supported. opt args can be anywhere.
--      if an opt requests an arg, it is fetched according to the value of `stack`
--      if `stack` is true, the last arg is given (and removed)
--      if `stack` is false, the first arg is given (and removed)
--      all unused args go to argv, in the order they appear.
local parse_modes = {
	posix = {
		chaos = false,
		long = false,
		argopt = true,
		order = "first",
		dashmode = "stop"
	},
	strict = {
		chaos = false,
		long = true,
		argopt = false,
		order = "first",
		dashmode = "stop"
	},
	gnu = {
		chaos = false,
		long = true,
		argopt = true,
		order = "any",
		dashmode = "stop"
	},
	clumped = {
		chaos = false,
		long = true,
		argopt = false,
		order = "clump",
		dashmode = "skip"
	},
	chaos_fifo = {
		chaos = true,
		stack = false,
	},
	chaos_stacked = {
		chaos = true,
		stack = true,
	}
}
getopt.parse_modes = parse_modes

local stopret = {}

local function adjustRet(optname, ret, extra)
	if ret == nil and extra == nil then
		return optname, true
	elseif extra == nil then
		return optname, ret
	elseif ret == nil then
		return nil, "rtfunc api violation"
	else
		return ret, extra
	end
end

local function makeCtx(optname, optout, consumer, isLong)
	return {
		optval = function(opt)
			opt = util.def(opt, optname)
			return optout[opt]
		end,
		arg = consumer,
		is_long = isLong
	}
end

local function processStarter(str)
	if string.sub(str, 1, 2) == "--" then
		if #str == 2 then -- actual '--' argument
			return "stop"
		else
			return "long", string.sub(str, 3)
		end
	elseif string.sub(str, 1, 1) == "-" then
		if #str == 1 then -- actual '-' argument
			return "arg", "-"
		else
			return "short", string.sub(str, 2)
		end
	else
		return "arg", str
	end
end

local function nonChaosShortParser(inval, inqueue, rtfunc, state)
	local curStr = inval
	local function consumer()
		if curStr == "" then
			return inqueue:take()
		else
			local o = curStr
			curStr = ""
			return o
		end
	end
	repeat
		local curOpt = string.sub(curStr, 1, 1)
		curStr = string.sub(curStr, 2)
		local success, ret, extra = pcall(rtfunc, curOpt, makeCtx(
			curOpt, state.optout, consumer, false
		))
		if not success then
			return false, ret
		else
			local optkey, optval = adjustRet(curOpt, ret, extra)
			if optkey == nil then
				return false, optval
			end
			state.optout[optkey] = optval
		end
	until curStr == ""
	return true
end

local function nonChaosLongParser(inval, inqueue, rtfunc, state)
	local optname, remain
	local equalPos = string.find(inval, "=", 1, true)
	if equalPos ~= nil then
		optname = string.sub(inval, 1, equalPos - 1)
		remain = string.sub(inval, equalPos + 1)
	else
		optname = inval
		remain = ""
	end
	local function consumer()
		if remain == "" then
			return inqueue:take()
		else
			-- parse a bit of remain
			local commaPos = string.find(remain, ",", 1, true)
			local out
			if commaPos == nil then
				out = remain
				remain = ""
			else
				out = string.sub(remain, 1, commaPos - 1)
				remain = string.sub(remain, commaPos + 1)
			end
		end
	end
	local success, ret, extra = pcall(rtfunc, optname, makeCtx(
		optname, state.optout, consumer, true
	))
	if not success then
		return false, ret
	else
		local optkey, optval = adjustRet(optname, ret, extra)
		if optkey == nil then
			return false, optval
		end
		state.optout[optkey] = optval
	end
	return true
end

local function nonChaosParser(inqueue, rtfunc, state, mode)
	local type, val = processStarter(inqueue:take())
	if type == "stop" then
		if mode.dashmode == "skip" then
			if not inqueue:empty() then
				state.argv:push(inqueue:take())
			end
			return true
		else
			return false, stopret
		end
	elseif type == "arg" then
		state.argv:push(val)
		if mode.order == "clump" then
			return not state.hasopt, nil
		end
		return mode.order == "any", nil
	elseif type == "long" then
		if not mode.long then
			return false, "unknown option -- -"
		elseif mode.order == "clump" then
			state.hasopt = true
		end
		return nonChaosLongParser(val, inqueue, rtfunc, state)
	elseif type == "short" then
		if mode.order == "clump" then
			state.hasopt = true
		end
		return nonChaosShortParser(val, inqueue, rtfunc, state)
	else
		error("should never get here, type = " .. tostring(type))
	end
end

local argReq = {}

local function chaosBeginOpt(optname, rtfunc, state, isLong)
	-- create a context for the opt parser
	-- i feel bad about the 640 bytes used for the stack here...
	local co = coroutine.create(rtfunc)
	-- first call: pass in 'optname', 'ctx'
	local ok, msg, extra = coroutine.resume(co, optname, 
			makeCtx(
				optname, state.optout, function()
					return coroutine.yield(argReq)
			end, isLong)
	)
	if not ok then
		return false, msg
	else
		if coroutine.status(co) == "dead" then
			-- already done.
			local optkey, optval = adjustRet(optname, msg, extra)
			if optkey == nil then
				return false, optval
			end
			state.optout[optkey] = optval
		elseif msg ~= argReq then
			return false, "invalid yield from rtfunc"
		else
			state.co:push({ co = co, optname = optname })
		end
	end
	return true
end

local function chaosParser(inqueue, rtfunc, state, _)
	local type, val = processStarter(inqueue:take())
	if type == "stop" then
		return false, "not enough entropy: '--' provided."
	elseif type == "arg" then
		state.argv:push(val)
		return true
	elseif type == "long" then
		local equalPos = string.find(val, "=", 1, true)
		if equalPos ~= nil then
			return false, "not enough entropy: direct option assignment"
		end
		return chaosBeginOpt(val, rtfunc, state, true)
	elseif type == "short" then
		for _, v in iter.string(val) do
			local ok, msg = chaosBeginOpt(v, rtfunc, state, false)
			if not ok then
				return false, msg
			end
		end
		return true
	else
		error("should never get here, type = " .. tostring(type))
	end
end

--- adjustable getopt-like parser.
--- @param input table the arguments to parse.
--- @param rtfunc function the function that translates the options and retrieves optargs
--- @param mode table | nil configuration options
--- @return table, list the parsed options and the remaining arguments.
function getopt.parse(input, rtfunc, mode)
	arg.checktype(input, 1, "table")
	arg.checktype(rtfunc, 2, { "function", "table" })
	arg.checktype(mode, 3, "table", true)
	mode = util.def(mode, parse_modes.gnu)
	local state, func = { optout = {} }, nil
	--- @type stack | fifo
	state.argv = util.cond(mode.chaos and mode.stack, stack(), fifo())
	if mode.chaos then state.co = fifo() end
	func = util.cond(mode.chaos, chaosParser, nonChaosParser)
	local inqueue = fifo(util.unpack(input))
	while #inqueue > 0 do
		local ok, msg = func(inqueue, rtfunc, state, mode)
		if not ok then
			if msg == stopret then
				-- switch to arg-only parser
				break
			else
				return nil, msg
			end
		end
	end
	if not mode.chaos then
		-- non-chaos post-processing: add remaining arguments
		while #inqueue > 0 do
			if mode.argopt then
				-- passthru
				state.argv:push(inqueue:take())
			else
				local type, val = processStarter(inqueue:take())
				if type == "stop" and mode.dashmode == "skip" then
					if not inqueue:empty() then
						state.argv:push(inqueue:take())
					end
				elseif type ~= "arg" then
					local msg = "unexpected "
					if type == "stop" then
						msg = msg .. "'--'"
					elseif type == "long" then
						msg = msg .. "long option '" .. val .. "'"
					elseif type == "short" then
						msg = msg .. "short option" .. util.cond(#val > 1, "(s)", "") .. " '" .. val .. "'"
					end
					return nil, msg .. " in arguments part"
				else
					state.argv:push(val)
				end

			end
		end
	else
		-- chaos post-processing: distribute arguments
		while #state.co > 0 do
			if #state.argv == 0 then
				return false, "not enough option arguments"
			end
			local dat = state.co:peek()
			local ok, msg, extra = coroutine.resume(dat.co, state.argv:pop())
			if not ok then
				return false, msg
			else
				if coroutine.status(dat.co) == "dead" then
					-- done
					local optkey, optval = adjustRet(dat.optname, msg, extra)
					if optkey == nil then
						return false, optval
					end
					state.optout[optkey] = optval
					state.co:take()
				elseif msg ~= argReq then
					return false, "invalid yield from rtfunc"
				end
			end
		end
	end
	return state.optout, list(util.unpack(state.argv))
end

return getopt
