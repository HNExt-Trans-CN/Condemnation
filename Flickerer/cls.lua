-- Class Library Simple
local arg = require("arg")
local util = require("util")

local newmt = {
	__call = function(t, ...) return t.new(...) end
}

--- create class structures.
--- @param libtab table library table
--- @param excluded table | nil names of functions to be excluded
--- @param withNew boolean setup libtab metatable for call construction
--- **modifies `libtab`'s metatable if `withNew` is true**.
--- @return table A table, suitable for indexing for the functions provided in `fnnames`.
local function cls(libtab, excluded, withNew)
	arg.checktype(libtab, 1, "table")
	arg.checktype(excluded, 2, "table", true)
	arg.checktype(withNew, 3, "boolean", true)
	local excludedSet = {}
	if excluded ~= nil then
		for key, value in ipairs(excluded) do
			excludedSet[value] = true
		end
	end
	local metafns = {}
	for name, value in pairs(libtab) do
		if not (excludedSet[name] or (withNew and name == "new")) then
			metafns[name] = value
		end
	end
	if withNew then
		setmetatable(libtab, newmt)
	end
	return metafns
end

return cls
