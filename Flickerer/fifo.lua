local arg = require("arg")
local util = require("util")
local cls = require("cls")
local list = require("list")

--- @class fifo
local fifo = {}

-- WARN: a fifo's blocks start with index 0
-- this does not affect the public interface, nor the
-- table containing the blocks. For Lua interface reasons.

--- @vararg any
--- @return fifo
function fifo.new(...)
	return fifo.withblocksize(1024, ...)
end

function fifo.withblocksize(blocksize, ...)
	local indat, n = util.packn(...)
	local data = {}
	local self = setmetatable({rd = 0, wd = n, data = {}, blocksize = blocksize}, fifo.__meta)
	for i=1, n do
		self:_set(i - 1, indat[i])
	end
	return self
end

function fifo:_getblock(idx)
	local blockNo = idx // self.blocksize
	local block = self.data[blockNo + 1]
	if block == nil then
		block = {}
		self.data[blockNo + 1] = block
	end
	return block
end

function fifo:_get(idx)
	if self.blocksize == 1 then return self.data[idx] end
	return self:_getblock(idx)[idx % self.blocksize]
end

function fifo:_set(idx, value)
	if self.blocksize == 1 then 
		self.data[idx] = value
		return 
	end
	self:_getblock(idx)[idx % self.blocksize] = value
end

--- @param t fifo
--- @param e any
function fifo.push(t, e)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	t:_set(t.wd, e)
	t.wd = t.wd + 1
end

--- @param t fifo
--- @return any
function fifo.peek(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	return t:_get(t.rd)
end

function fifo.peekn(t, n)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	local out = list()
	for i=0,n-1 do
		out[#out + 1] = t:_get(t.rd + i)
	end
	return out
end

--- @param t fifo
--- @return any
function fifo.take(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	if t.rd == t.wd then
		return nil
	end
	local e = t:_get(t.rd)
	t:_set(t.rd, nil) -- remove reference for gc
	t.rd = t.rd + 1
	if t.rd == t.wd then -- cool, end-of-the-queue. can 'compact' early.
		t.rd = 0
		t.wd = 0
	elseif t.rd == t.blocksize then
		-- compact a block
		t.rd = 0
		t.wd = t.wd - t.blocksize
		table.remove(t.data, 1)
	end
	return e
end

function fifo.taken(t, n)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	arg.checktype(n, 1, "integer")
	arg.checkrange(n, 1, 1, math.maxinteger)
	if t.rd == t.wd then
		return nil
	end
	local out = list()
	for i=0,n-1 do
		local e = t:_get(t.rd + i)
		t:_set(t.rd + i, nil)
		out[#out + 1] = e
	end
	t.rd = t.rd + n
	while t.rd > t.blocksize do
		-- compact a block
		t.rd = t.rd - t.blocksize
		t.wd = t.wd - t.blocksize
		table.remove(t.data, 1)
	end
	return out
end

fifo.pop = fifo.take
fifo.popn = fifo.taken

-- compact the fifo queue by moving everything back to the left (toward 0)
--- @param t fifo
function fifo.compact(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	return
	-- now a stub, since this takes *more* work with blocks
	--[[
	if t.rd == t.wd then
		-- nothing to do
		t.rd = 0
		t.wd = 0
		return
	end
	local j = 1
	for i=t.rd,t.wd do
		t.data[j] = t.data[i]
		j = j + 1
	end
	t.rd = 1
	t.wd = j
	]]--
end

function fifo.unpack(t)
	arg.checktype(t, 0, "table")
	arg.checkmeta(t, 0, fifo.__meta)
	local out = {}
	for i=t.rd,t.wd do
		out[i - t.rd + 1] = t:_get(i)
	end
	return table.unpack(out, 1, t.wd - t.rd)
end

local metafns = cls(fifo, { "withblocksize" }, true)

fifo.__meta = {
	__index = metafns,
	__len = function(t)
		return t.wd - t.rd
	end,
	__name = "fifo",
	__unpack = fifo.unpack,
--[[	__repr = function(self, depth, indent, cont)
		arg.checktype(self, 0, "table")
		arg.checkmeta(self, 0, fifo.__meta)
		local out = tostring(self) .. " (" .. #self .. ") = [ \n"
		local depIn = string.rep(indent, depth + 1)
		for i=self.rd,self.wd-1 do
			out = out .. depIn .. cont(self:_get(i))
			if i < self.wd-1 then
				out = out .. ",\n"
			end
		end
		return out .. "\n" .. string.rep(indent, depth) .. "]"
	end --]]
}

return fifo
