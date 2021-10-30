local arg = require("arg")
local util = require("util")
local cls = require("cls")

--- @class stack
local stack = {}

--- @vararg any
--- @return stack
function stack.new(...)
	local dat, n = util.packn(...)
	return setmetatable({n = n, data = dat}, stack.__meta)
end

--- @param t stack
--- @param e any
function stack.push(t, e)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, stack.__meta)
	t.n = t.n + 1
	t.data[t.n] = e
end

--- @param t stack
--- @return any
function stack.pop(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, stack.__meta)
	local e = t.data[t.n]
	t.data[t.n] = nil
	t.n = t.n - 1
	return e
end

--- @param t stack
--- @return any
function stack.peek(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, stack.__meta)
	return t.data[t.n]
end

--- simple transfer routine.
--- inverts order of values. basically simulates bunch of
--- pop+push operations. use xplant if you want to keep order instead.
function stack.xfer(src, dest, n)
	arg.checktype(src, 1, "table")
	arg.checktype(dest, 2, "table")
	arg.checktype(n, 3, "number", true)
	arg.checkmeta(src, 1, stack.__meta)
	arg.checkmeta(dest, 2, stack.__meta)
	n = util.def(n, src.n)
	if src.n - n + 1 < 0 then
		arg.raiseerror("not enough values, " .. n .. " requested, have " .. src.n, -1)
	end
	for i=0,n - 1 do
		dest.data[dest.n + i + 1] = src.data[src.n - i]
		src.data[src.n - i] = nil
	end
	dest.n = dest.n + n
	src.n = src.n - n
end

--- order-preserving transfer routine.
--- "transplants" the top `n` values of `src` on top of `dest`
function stack.xplant(src, dest, n)
	arg.checktype(src, 1, "table")
	arg.checktype(dest, 2, "table")
	arg.checktype(n, 3, "number", true)
	arg.checkmeta(src, 1, stack.__meta)
	arg.checkmeta(dest, 2, stack.__meta)
	n = util.def(n, src.n)
	local srcBegin = src.n - n + 1
	if srcBegin < 0 then
		arg.raiseerror("not enough values, " .. n .. " requested, have " .. src.n, -1)
	end
	for i=0,n - 1 do
		dest.data[dest.n + i + 1] = src.data[srcBegin + i]
		src.data[srcBegin + i] = nil
	end
	dest.n = dest.n + n
	src.n = src.n - n
end


local metafns = cls(stack, { "xfer", "xplant" }, true)

stack.__meta = {
	__index = metafns,
	__len = function(t)
		return t.n
	end,
	__name = "stack",
	__unpack = function(t)
		return table.unpack(t.data, 1, t.n)
	end
}

return stack
