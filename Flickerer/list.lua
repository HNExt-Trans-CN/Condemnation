local arg = require("arg")
local util = require("util")
local cls = require("cls")

--- @class list
local list = {}

--- @vararg any
--- @return list
function list.new(...)
	local data, n = util.packn(...)
	--- @type list
	local out = setmetatable({ data = data, n = n }, list.__meta)
	out:compact()
	return out
end

function list.iter(self, begin, stop)
	arg.checktype(self, 0, "table")
	arg.checkmeta(self, 0, list.__meta)
	arg.checktype(begin, 1, "number", true)
	arg.checktype(stop, 2, "number", true)
	begin = util.def(begin, 1)
	stop = util.def(stop, #self)
	return function(l, oldi)
		local i = oldi + 1
		if i > stop then return nil end
		return i, l[i]
	end, self, begin - 1
end

--- @param k string | number
--- @return number
local function indexXform(k)
	local nk
	if type(k) == "string" then
		nk = tonumber(k, 10)
	elseif type(k) == "number" then
		nk = k
	end
	if nk == nil then
		arg.raiseerror("bad index: " .. k, 1, 2)
	end
	return nk
end

--- ensure proper list length.
--- scans the list from list.n to firstidx (backwards)
--- in search of the first non-nil element.
--- @param self list
--- @param firstidx number | nil
--- @return number new list length
function list.compact(self, firstidx)
	arg.checktype(self, 0, "table")
	arg.checkmeta(self, 0, list.__meta)
	arg.checktype(firstidx, 1, "number", true)
	firstidx = util.def(firstidx, 1)
	if self.n < firstidx then
		-- nope. our caller's off. or the list is empty.
		return self.n
	end
	for i = self.n, firstidx, -1 do
		if self.data[i] ~= nil then
			self.n = i
			return i
		end
	end
	self.n = firstidx
	return firstidx
end

--- join another list to the end of this one
--- modifies this list
--- @param self list this list
--- @param other list another list
--- @return list this list
function list.join(self, other)
	arg.checktype(self, 0, "table")
	arg.checkmeta(self, 0, list.__meta)
	arg.checktype(other, 1, "table")
	arg.checkmeta(other, 1, list.__meta)
	local startlen = #self
	for i, v in other:iter() do
		-- support holes
		self[startlen + i] = v
	end
	return self
end

local metafns = cls(list, nil, true)

list.__meta = {
	__index = function(t, k)
		if metafns[k] ~= nil then
			return metafns[k]
		end
		return t.data[indexXform(k)]
	end,
	__newindex = function(t, k, v)
		local nk = indexXform(k)
		if v ~= nil and nk > t.n then
			-- increment size
			t.n = nk
		end
		t.data[nk] = v
		if v == nil and nk <= t.n then
			list.compact(t)
		end
		return v
	end,
	__len = function(t)
		return t.n
	end,
	__name = "list",
	__pairs = list.iter,
	__iter = list.iter,
	__repr = function(l, depth, indent, cont)
		local out = tostring(l) .. " (" .. #l .. ") = [ \n"
		local depIn = string.rep(indent, depth + 1)
		for i=1,l.n do
			out = out .. depIn .. cont(l[i])
			if i < l.n then
				out = out .. ",\n"
			end
		end
		return out .. "\n" .. string.rep(indent, depth) .. "]"
	end
}

return list
