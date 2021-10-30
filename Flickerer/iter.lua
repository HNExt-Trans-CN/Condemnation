local utf8 = require("utf8")
local util = require("util")
local debug = require("debug") -- debug.getmetatable

--- @class iter
local iter = {}

local function iter_indexed(fun, perm)
	return function(perm, prev)
		local now = prev + 1
		local ret = util.pack(fun(perm, now))
		if ret.n == 0 or ret[1] == nil then return nil end
		return now, table.unpack(ret)
	end, perm, 0
end

function iter.iter(thing, ...)
	local mt = debug.getmetatable(thing)
	if mt ~= nil and mt.__iter ~= nil then
		return mt.__iter(thing, ...)
	end
	if type(thing) == "string" then
		return iter.string(thing) 
	end
	error("attempt to iterate " .. thing)
end

function iter.utf8(str)
	local iter, perm, idx = utf8.codes(str)
	return function(perm, idx)
		local idx, code = iter(perm, idx)
		return idx, utf8.char(code)
	end, perm, idx
end

function iter.utf8codes(str)
	return utf8.codes(str) -- lol
end

function iter.utf8both(str)
	local iter, perm, idx = utf8.codes(str)
	return function(perm, idx)
		local idx, code = iter(perm, idx)
		return idx, code, utf8.char(code)
	end, perm, idx
end

function iter.string(str)
	return iter_indexed(function(str, now)
		local sub = string.sub(str, now, now)
		if sub == "" then return nil else return sub end
	end, str)
end

function iter.stringbytes(str)
	return iter_indexed(function(str, now)
		return string.byte(str, now, now + 1)
	end, str)
end

function iter.stringboth(str)
	return iter_indexed(function(str, now)
		local byte = string.byte(str, now, now + 1)
		local sub = string.sub(str, now, now)
		if sub == "" then return nil else return byte, sub end
	end, str)
end

function iter.collect(...)
	return iter.packed(table.pack(...))
end

function iter.packed(tbl)
	return function(tbl, idx)
		if idx == tbl.n then return nil end
		return idx+1, tbl[idx+1]
	end, tbl, 0
end

-- iterator for a standardized array ("packed") or sequence
function iter.array(tbl)
	if tbl.n == nil then
		-- sequence
		return pairs(tbl)
	else
		return iter.packed(tbl)
	end
end

return iter
