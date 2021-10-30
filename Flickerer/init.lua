local util = require("util")
local getopt = require("getopt")

local usage = "flickerer.lua <-m <module> ...> -d <duration> -n <delay host> [-f <frame delay>] [-r <resolution>] [-s] [-i] [-l]"

local helpText = usage .. [[

Generates module flicker sequences.

Options:
	-m Which module to flicker. Specify multiple if you want multiple modules.
	-d How long to go for.
	-n ID of the delay host.
	-f (Delay between updates)^-1. Frame delay will be 1/(provided value). Defaults to 60.
	-r Resolution of the delay attribute (i.e. how many digits after the decimal point). Defaults to 2.
	-s If specified, the modules will flicker together. Otherwise, they're independant.
	-i If specified, the modules are assumed to be hidden before starting.
	-l If specified, the modules will be locked

(Option parse mode: POSIX)]]

local opts, argv = getopt.parse(util.pack(...), function(optname, ctx)
	if optname == "m" then
		local modules = ctx.optval("modules")
		if modules == nil then
			modules = {}
		end
		table.insert(modules, ctx.arg())
		return "modules", modules
	elseif optname == "d" then
		local val = ctx.arg()
		local num = tonumber(val)
		if num == nil then
			error("'" .. val .. "' is not a valid number", 0)
		end
		return "duration", num
	elseif optname == "n" then
		return "host", ctx.arg()
	elseif optname == "f" then
		local val = ctx.arg()
		local num = tonumber(val)
		if num == nil then
			error("'" .. val .. "' is not a valid number", 0)
		end
		return "framedelay", num
	elseif optname == "r" then
		local val = ctx.arg()
		local num = tonumber(val, 10)
		if num == nil then
			error("'" .. val .. "' is not a valid number", 0)
		end
		return "resolution", num
	elseif optname == "s" then
		return "sync", true
	elseif optname == "i" then
		return "initial", true
	elseif optname == "l" then
		return "lock", true
	elseif optname == "h" or optname == "?" then
		error(nil)
	else
		error("unknown option '" .. optname .. "'")
	end
end, getopt.parse_modes.posix)

if opts == nil then
	if argv == nil then
		-- help requested
		io.stderr:write(helpText .. "\n")
	else
		io.stderr:write("error parsing options: " .. argv .. "\n" .. usage .. "\n")
	end
	return 2
end

if opts.duration == nil then
	io.stderr:write("error: no duration specified\n" .. usage .. "\n")
	return 2
end

if opts.modules == nil then
	io.stderr:write("error: no modules specified\n" .. usage .. "\n")
	return 2
end

if opts.host == nil then
	io.stderr:write("error: no DelayHost specified\n" .. usage .. "\n")
	return 2
end

opts.framedelay = 1 / util.def(opts.framedelay, 60)
opts.resolution = util.def(opts.resolution, 2)

if opts.framedelay > opts.duration then
	io.stderr:write("framedelay > duration -- no content written.\n")
	return 1
end

local state = {}

if opts.sync then
	state = not opts.initial
else
	for _,v in ipairs(opts.modules) do
		state[v] = not opts.initial
	end
end

math.randomseed(os.time())

local out = ""

local function writeSetLock(modname, state, delay)
	out = out .. string.format('<SetLock DelayHost="%s" Delay="%.' .. string.format("%d", opts.resolution) .. 'f" Module="%s" IsLocked="%s" IsHidden="%s" />\n',
		opts.host,
		delay,
		modname,
		tostring(not not opts.lock),
		tostring(state)
	)
end

for current=0,opts.duration,opts.framedelay do
	if opts.sync then
		local newState = math.random() > ( current / opts.duration )
		if state ~= newState then
			for _, v in ipairs(opts.modules) do
				writeSetLock(v, newState, current)
			end
		end
		state = newState
	else
		for _, v in ipairs(opts.modules) do
			local newState = math.random() > ( current / opts.duration )
			if state[v] ~= newState then
				writeSetLock(v, newState, current)
			end
			state[v] = newState
		end
	end
end

print(out)
