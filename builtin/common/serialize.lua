--- Lua module to serialize values as Lua code.
-- From: https://github.com/appgurueu/modlib/blob/master/luon.lua
-- License: MIT

local next, rawget, pairs, pcall, error, type, setfenv, loadstring
	= next, rawget, pairs, pcall, error, type, setfenv, loadstring

local table_concat, string_dump, string_format, string_match, math_huge
	= table.concat, string.dump, string.format, string.match, math.huge

local registered_mt_serialization = {}
local registered_mt_deserialization = {}

local primitive_types = {
	boolean = true,
	number = true,
	string = true,
	["nil"] = true,
}
local function is_primitive_type(typename)
	return primitive_types[typename] or false
end

-- Recursively
-- (1) prepares objects with custom metatables for serialization;
-- (2) counts occurrences of objects (non-primitives including strings) in a table.
local function prepare_objects(value)
	local counts = {}
	local serialized = {}
	local type_lookup = {}
	local object_order = {}
	if value == nil then
		-- Early return for nil; tables can't contain nil
		return counts, serialized, type_lookup, object_order
	end
	local function count_values(val, disallow)
		local type_ = type(val)
		if disallow[val] then
			error("unsupported recursive data structure")
		end
		if type_ == "boolean" or type_ == "number" then
			return
		end
		local count = counts[val]
		counts[val] = (count or 0) + 1
		local mt = getmetatable(val)
		if mt and registered_mt_serialization[mt] then
			if not count then
				local data, typename = registered_mt_serialization[mt](val)
				serialized[val] = data
				type_lookup[val] = typename
				if disallow[data] then
					error("unsupported recursive data structure")
				end
				if rawequal(data, val) then
					if type_ == "table" then
						for k, v in pairs(val) do
							count_values(k, disallow)
							count_values(v, disallow)
						end
					elseif not is_primitive_type(type_) then
						error(("serialization of %s resulted in unsupported type: %s"):format(typename, type_))
					end
				else
					if not is_primitive_type(type(val)) then
						disallow[val] = true
					end
					count_values(data, disallow)
					disallow[val] = nil
				end
				count_values(typename, disallow)
				object_order[#object_order+1] = val
			end
		elseif type_ == "table" then
			if not count then
				for k, v in pairs(val) do
					count_values(k, disallow)
					count_values(v, disallow)
				end
				object_order[#object_order+1] = val
			end
		elseif type_ ~= "string" and type_ ~= "function" then
			error("unsupported type: " .. type_)
		end
	end
	count_values(value, {})
	return counts, serialized, type_lookup, object_order
end

-- Build a "set" of Lua keywords. These can't be used as short key names.
-- See https://www.lua.org/manual/5.1/manual.html#2.1
local keywords = {}
for _, keyword in pairs({
	"and", "break", "do", "else", "elseif",
	"end", "false", "for", "function", "if",
	"in", "local", "nil", "not", "or",
	"repeat", "return", "then", "true", "until", "while",
	"goto" -- LuaJIT, Lua 5.2+
}) do
	keywords[keyword] = true
end

local function quote(string)
	return string_format("%q", string)
end

local function dump_func(func)
	return string_format("loadstring(%q)", string_dump(func))
end

-- Serializes Lua nil, booleans, numbers, strings, tables and even functions
-- Tables are referenced by reference, strings are referenced by value. Supports circular tables.
local function serialize(value, write)
	local reference, refnum = "1", 1
	-- [object] = reference
	local references = {}
	-- Circular tables that must be filled using `table[key] = value` statements
	local to_fill = {}
	local counts, serialized, typenames, object_order = prepare_objects(value)
	if next(serialized) ~= nil then
		write "local D = D or function(tbl) return tbl end;"
	end
	for object, count in pairs(counts) do
		local type_ = type(object)
		-- Object must appear more than once. If it is a string, the reference has to be shorter than the string.
		if count >= 2 and (type_ ~= "string" or #reference + 5 < #object) then
			if refnum == 1 then
				write"local _={};" -- initialize reference table
			end
			local ser = serialized[object]
			local delay_assignment = ser ~= nil and not rawequal(ser, object)
			if not delay_assignment then
				write"_["
				write(reference)
				write("]=")
				if type_ == "table" then
					write("{}")
				elseif type_ == "function" then
					write(dump_func(object))
				elseif type_ == "string" then
					write(quote(object))
				end
				write(";")
			end
			if type_ ~= "string" then
				to_fill[object] = reference
			end
			references[object] = reference
			refnum = refnum + 1
			reference = ("%d"):format(refnum)
		end
	end
	-- Used to decide whether we should do "key=..."
	local function use_short_key(key)
		return not references[key] and type(key) == "string" and (not keywords[key]) and string_match(key, "^[%a_][%a%d_]*$")
	end
	local function dump(value, skip_mt)
		-- Primitive types
		if value == nil then
			return write("nil")
		end
		if value == true then
			return write("true")
		end
		if value == false then
			return write("false")
		end
		local type_ = type(value)
		if type_ == "number" then
			if value ~= value then -- nan
				return write"0/0"
			elseif value == math_huge then
				return write"1/0"
			elseif value == -math_huge then
				return write"-1/0"
			else
				return write(string_format("%.17g", value))
			end
		end
		-- Reference types: table, function and string
		local ref = references[value]
		if ref then
			write"_["
			write(ref)
			return write"]"
		end
		if (not skip_mt) and serialized[value] then
			local data = serialized[value]
			write "D("
			dump(serialized[value], rawequal(data, value))
			write ","
			dump(typenames[value])
			write ")"
			return
		end
		if type_ == "string" then
			return write(quote(value))
		end
		if type_ == "function" then
			return write(dump_func(value))
		end
		if type_ == "table" then
			write("{")
			-- First write list keys:
			-- Don't use the table length #value here as it may horribly fail
			-- for tables which use large integers as keys in the hash part;
			-- stop at the first "hole" (nil value) instead
			local len = 0
			local first = true -- whether this is the first entry, which may not have a leading comma
			while true do
				local v = rawget(value, len + 1) -- use rawget to avoid metatables like the vector metatable
				if v == nil then break end
				if first then first = false else write(",") end
				dump(v)
				len = len + 1
			end
			-- Now write map keys ([key] = value)
			for k, v in next, value do
				-- We have written all non-float keys in [1, len] already
				if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > len then
					if first then first = false else write(",") end
					if use_short_key(k) then
						write(k)
					else
						write("[")
						dump(k)
						write("]")
					end
					write("=")
					dump(v)
				end
			end
			write("}")
			return
		end
	end
	-- Write the statements to fill circular tables
	for _, table in ipairs(object_order) do
		local ref = to_fill[table]
		if ref then
			local ser = serialized[table]
			if ser == nil or rawequal(ser, table) then
				for k, v in pairs(table) do
					write("_[")
					write(ref)
					write("]")
					if use_short_key(k) then
						write(".")
						write(k)
					else
						write("[")
						dump(k)
						write("]")
					end
					write("=")
					dump(v)
					write(";")
				end
			end
			if ser ~= nil then
				local typename = typenames[table]
				write("_[")
				write(ref)
				write("]=D(")
				dump(ser)
				write(",")
				dump(typename)
				write(");")
			end
		end
	end
	write("return ")
	dump(value)
end

function core.register_serializable(typename, mt, serialize, deserialize)
	assert(type(typename) == "string", ("attempt to use %s value as metatable name"):format(type(typename)))
	assert(type(mt) == "table", ("attempt to register a %s value as metatable"):format(type(mt)))
	assert(not registered_mt_serialization[mt], "metatable already registered for serialization")
	assert(not registered_mt_deserialization[typename], ("%s already registered as serializable"):format(typename))
	if type(serialize) ~= "function" then
		serialize = function(tbl)
			return tbl
		end
	end
	if type(deserialize) ~= "function" then
		deserialize = function(tbl)
			return setmetatable(tbl, mt)
		end
	end
	registered_mt_serialization[mt] = function(tbl)
		return serialize(tbl), typename
	end
	registered_mt_deserialization[typename] = deserialize
end

function core.serialize(value)
	local rope = {}
	serialize(value, function(text)
		 -- Faster than table.insert(rope, text) on PUC Lua 5.1
		rope[#rope + 1] = text
	end)
	return table_concat(rope)
end

local function dummy_func() end

local function deserialize_object(obj, typename)
	local d = registered_mt_deserialization[typename]
	if d then
		return d(obj)
	end
	return obj
end

function core.deserialize(str, safe)
	-- Backwards compatibility
	if str == nil then
		core.log("deprecated", "minetest.deserialize called with nil (expected string).")
		return nil, "Invalid type: Expected a string, got nil"
	end
	local t = type(str)
	if t ~= "string" then
		error(("minetest.deserialize called with %s (expected string)."):format(t))
	end

	local func, err = loadstring(str)
	if not func then return nil, err end

	-- math.huge was serialized to inf and NaNs to nan by Lua in Minetest 5.6, so we have to support this here
	local env = {inf = math_huge, nan = 0/0, D = deserialize_object}
	if safe then
		env.loadstring = dummy_func
	else
		env.loadstring = function(str, ...)
			local func, err = loadstring(str, ...)
			if func then
				setfenv(func, env)
				return func
			end
			return nil, err
		end
	end
	setfenv(func, env)
	local success, value_or_err = pcall(func)
	if success then
		return value_or_err
	end
	return nil, value_or_err
end

if ItemStack then
	local empty_stack = ItemStack()
	core.register_serializable("__builtin:itemstack", getmetatable(empty_stack), empty_stack.to_string, ItemStack)
end
