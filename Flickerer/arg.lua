-- required debug functions:
-- debug.getinfo, debug.getmetatable, debug.getregistry
local debug = require("debug")
--- @class arg
local arg = {}

local function verifyType(actual, expected)
	if expected == "integer" or expected == "float" then
		return math.type(actual) == expected
	else
		return type(actual) == expected
	end
end

-- internal function that checks
-- `actual` against `expected`.
-- both arguments are treated as trusted.
local function verifyTypes(actual, expected)
	if type(expected) == "string" then
		return verifyType(actual, expected)
	else -- type(expected) == "table"
		if type(expected) ~= "table" then
			error("impl problem. expected = " .. expected)
		end
		for _, el in pairs(expected) do
			if verifyType(actual, el) then
				return true
			end
		end
		return false
	end
end

local function findField(needle, haystack, level, stack)
	level = require("util").def(level, 2)
	stack = require("util").def(stack, {})
	if level == 0 or type(haystack) ~= "table" or stack[haystack] then
		return nil
	end
	stack[haystack] = true
	for k, v in pairs(haystack) do
		if type(k) == "string" then
			if rawequal(v, needle) then
				stack[haystack] = false
				return k
			else
				local inner = findField(needle, v, level - 1, stack)
				if inner ~= nil then
					stack[haystack] = false
					return k .. "." .. inner
				end
			end
		end
	end
	stack[haystack] = nil
	return nil
end

local function getGlobalName(value)
	-- find global name
	local name = findField(value, debug.getregistry()._LOADED, 5)
	if name ~= nil then
		if string.sub(name, 1, 3) == "_G." then
			name = string.sub(name, 4)
		end
		if string.sub(name, 1, 14) == "package.loaded" then
			name = string.sub(name, 15)
		end
	end
	return name
end

local function fmtArg(argspec)
	if type(argspec) == "number" then
		return "#" .. argspec
	else
		return argspec
	end
end

local function fmtErrorHead(argspec, funspec)
	funspec = require("util").def(funspec, 1) + 1
	local funcname
	do
		local info = debug.getinfo(funspec, "nf")
		if info.name == nil then
			funcname = getGlobalName(info.func)
		else
			funcname = info.name
		end
	end
	if argspec == 0 or argspec == "self" then
		if funcname == nil then
			return "calling function on bad self"
		else
			return "calling '" .. funcname .. "' on bad self"
		end
	else
		local out
		if argspec == -1 then
			out = "bad arguments"
		else
			out = "bad argument " .. fmtArg(argspec)
		end
		if funcname ~= nil then
			return out .. " to '" .. funcname .. "'"
		else
			return out
		end
	end		
end

local function fmtExpected(expect, opt)
	if type(expect) == "string" then
		return expect .. require("util").cond(opt, " or nil", "")
	else -- type(expect) == "table"
		local out = ""
		local last
		for _, v in pairs(expect) do
			if out == "" then
				out = v
			else
				if last ~= nil then
					out = out .. ", " .. last
				end
				last = v
			end
		end
		if opt then
			if last ~= nil then
				out = out .. ", " .. last
			end
			last = "nil"
		end
		if last ~= nil then
			out = out .. " or " .. last
		end
		if out == "" then
			return "an impossibility"
		else
			return out
		end
	end
end

local function fmtActual(value)
	local tt = type(value)
	if tt == "number" then
		return math.type(value)
	else
		return tt
	end
end

local function checkType(value, argspec, expect, funspec, opt)
	if not verifyTypes(value, expect) then
		arg.raiseerror(
			fmtExpected(expect, opt)
			.. " expected, got " ..
			fmtActual(value),
			argspec,
			require("util").def(funspec, 1) + 1
		)
	end
end

--- raise an error about function arguments.
--- this function never returns
--- @param msg string the error message
--- @param argspec number | string the argument specification
--- @param funspec number | function function specification. a number signifies "this many stack frames up".
--- @noreturn
function arg.raiseerror(msg, argspec, funspec)
	funspec = require("util").def(funspec, 1) + 1
	error(
		fmtErrorHead(
			argspec,
			funspec
		) .. " (" .. msg .. ")",
		funspec
	)
end

--- verify argument type
--- @param value any the actual value received
--- @param argspec number | string thee argument specification
--- @param expect string | table the expected type(s). if a table, all fields are checked (via pairs)
--- @param optional boolean | nil if the given argument is optional. if it is, `nil` is an acceptable `value` input, no matter what `expect` is.
function arg.checktype(value, argspec, expect, optional)
	checkType(argspec, 2, {"integer", "string"})
	checkType(expect, 3, {"string", "table"})
	checkType(optional, 4, {"boolean", "nil"})
	if optional and value == nil then
		return
	end
	checkType(value, argspec, expect, 2, optional)
end

local function getMetaName(meta)
	if meta == nil then
		return "(no metatable)"
	end
	if meta.__name then
		return meta.__name
	end
	local name = getGlobalName(meta)
	if name ~= nil then
		return name
	end
	return "(unique: " .. tostring(meta) .. ")"
end

--- verify argument metatable
--- @param value any the actual value received
--- @param argspec number | string the argument specificiation
--- @param expectmeta table the expected metatable
function arg.checkmeta(value, argspec, expectmeta)
	checkType(argspec, 2, {"integer", "string"})
	checkType(expectmeta, 3, "table")
	local valuemeta = debug.getmetatable(value)
	if expectmeta ~= valuemeta then
		local expectname = getMetaName(expectmeta)
		local valuename = getMetaName(valuemeta)
		if expectname == valuename then
			-- cool, this is totally not confusing.
			arg.raiseerror("expected one " .. expectname .. ", got another " .. expectname, argspec, 2)
		end
		arg.raiseerror("expected ".. expectname ..", got ".. valuename, argspec, 2)
	end
end

--- verify variadic argument types
--- @param firstspec number the first argument specification. incremented as required per argument.
--- @param expect string | table the expected type(s). see checktype.
--- @vararg any the actual values received
function arg.checkvar(firstspec, expect, ...)
	checkType(firstspec, 2, "integer")
	checkType(expect, 3, {"string", "table"})
	local values = table.pack(...)
	for i=1,values.n do
		checkType(values[i], firstspec + 1, expect, 2)
	end
end

local function checkRange(value, rangestart, rangeend, funspec, argspec)
	funspec = funspec + 1
	checkType(value, argspec, "number", funspec)
	if value < rangestart or value > rangeend then
		local startname = rangestart .. ""
		local endname = rangeend .. ""
		if rangestart == math.mininteger then
			startname = "MIN_INT"
		end
		if rangeend == math.maxinteger then
			endname = "MAX_INT"
		end
		arg.raiseerror("expected a value in range ".. startname .."..".. endname ..", got ".. value, argspec, funspec)
	end
end

--- verify argument range
--- @param value number the actual value received
--- @param argspec number | string the argument specification
--- @param rangestart number the beginning of the numeric range
--- @param rangeend number the end of the numeric range
function arg.checkrange(value, argspec, rangestart, rangeend)
	checkType(argspec, 2, {"integer", "string"})
	checkType(rangestart, 3, "number")
	checkType(rangeend, 4, "number")
	checkRange(value, rangestart, rangeend, 2, argspec)
end

-- arg.checkoption(value, argspec, options, [[,rangestart, rangeend],default])
-- yes, this means args #4, #5 and #6 are a little ambiguous.
-- (#4 can be 'default', if #5 and #6 aren't specified)

--- verify and convert options
--- @param value any the actual value received
--- @param argspec number | string the argument specification
--- @param options table a mapping table of string options to numeric types
--- @param rangestart number | function | nil the beginning of the permitted range (or `default`)
--- @param rangeend number | nil the end of the permitted range
--- @param default string | number | nil the default value. may also be parameter #4, if `rangeend` and `default` are not supplied.
--- @return number
function arg.checkoption(value, argspec, options, rangestart, rangeend, default)
	checkType(argspec, 2, {"integer", "string"})
	checkType(options, 3, "table")
	checkType(default, 6, {"integer", "string", "nil"})
	local defaultSpec = "#6 ('default')"
	if rangestart ~= nil then
		-- did they mean "default"?
		if rangeend == nil and default == nil then
			-- yep. check the types.
			defaultSpec = "#4 ('default')"
			checkType(rangestart, defaultSpec, {"integer", "string"})
			default = rangestart
			rangestart = nil
		elseif rangeend == nil then
			-- nope. they messed up.
			arg.raiseerror("#4 ('rangestart') and #6 ('default') provided, but no #5 ('rangeend')", -1)
		else
			checkType(rangestart, 4, "number")
			checkType(rangeend, 5, "number")
		end
	end

	-- check default (also precalculate for later)
	local dValue = default
	if default ~= nil then
		if type(default) == "string" then
			-- translate to number...
			dValue = options[default]
			if dValue == nil then
				arg.raiseerror("invalid default '" .. value .. "'", defaultSpec)
			elseif not verifyType(dValue, "integer") then
				arg.raiseerror("expected integer as the options table value for default, got " .. type(dValue), 3)
			end
		end
		-- check for range...
		if rangestart ~= nil then
			checkRange(dValue, rangestart, rangestart, 1, defaultSpec)
		end
	end

	local types = {"number", "string", "nil"}
	if default == nil then
		types[3] = nil
	end
	checkType(value, argspec, types, 2)
	if value == nil then
		return dValue
	end
	if type(value == "string") then
		-- translate to number according to table
		local nValue = options[value]
		if nValue == nil then
			arg.raiseerror("invalid option '" .. value .. "'", argspec, 2)
		elseif not verifyType(nValue, "integer") then
			arg.raiseerror("expected integer as the options table value, got " .. type(nValue), 3)
		end
		value = nValue
	end
	if rangestart ~= nil then
		checkRange(value, rangestart, rangeend, 2, argspec)
	else
		checkType(value, argspec, "integer", 2)
	end
	return value
end

return arg
