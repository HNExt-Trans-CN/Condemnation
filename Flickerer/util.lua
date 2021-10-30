-- mt access
local debug = require("debug")
--- @class util
local util = {}

--- `cond ? trueVal : falseVal`
--- ...sort of. evaluation order is different.
---@param cond boolean Condition to check
---@param trueVal any Value to return when true
---@param falseVal any Value to return when false
---@return any
function util.cond(cond, trueVal, falseVal)
	if cond then
		return trueVal
	else
		return falseVal
	end
end

--- default collapse. return `default` if `value` is nil.
--- @param value any Value to collapse
--- @param default any Default value
--- @return any
function util.def(value, default)
	return util.cond(value == nil, default, value)
end

--- pack values, separating `n` from the packed table.
--- @vararg any
--- @return table, number
function util.packn(...)
	local pack = table.pack(...)
	local n = pack.n
	pack.n = nil
	return pack, n
end

util.packmeta = {
	__len = function(t) return t.n end
}

--- pack values, applying a metatable to correct the length operation.
--- @return table
function util.pack(...)
	return setmetatable(
		table.pack(...),
		util.packmeta
	)
end

--- convert any number of parameters (or a table) into a packed table.
--- if a table is passed, assumes that it can be unpacked.
--- @vararg any
--- @return table
function util.topacked(...)
	local pack = util.pack(...)
	if pack.n == 1 and type(pack[1]) == "table" then
		-- only one parameter, and it's a table.
		-- convert it to a pack.
		return util.pack(util.unpack((...)))
	end
	return pack
end

--- a customizable unpack.
--- variable return values.
--- @param tab table | userdata thing to unpack
--- @return any
function util.unpack(tab)
	local mt = debug.getmetatable(tab)
	if mt ~= nil and mt.__unpack ~= nil then
		-- have unpack, use it
		return mt.__unpack(tab)
	elseif mt ~= nil and mt.__len == nil then
		-- no unpack, but have length. normal unpack can deal with that.
		return table.unpack(tab)
	else
		-- no usable metamethods.
		-- check for n field
		if tab.n == nil then
			-- nope. fallback to default
			return table.unpack(tab)
		else
			-- use length
			return table.unpack(tab, 1, tab.n)
		end
	end
end

--- vararg table.concat
--- @vararg string | number
--- @return string
function util.concatvar(sep, ...)
	return table.concat(util.pack(...), sep)
end


return util
