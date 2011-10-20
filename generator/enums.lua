module("enums", package.seeall)

local print_enum = fprint(assert(io.open(module_name.._src..module_name..'_enum.cpp', 'w')))

local function filter(enum)
	local n = enum.name
	if n~=string.lower(n) and not string.match(n, '_') then
		return false
	end
	return true
end

local enum_list = {}

local function copy_enums(index)
	for e in pairs(index) do
		if e.type=='Enum'
			and not string.match(e.fullname, '%b<>') then
			if e.access=='public' and not filter(e) then
				enum_list[e.fullname] = e
			elseif e.access == 'protected' then
				-- register it anyway
				enum_list[e.fullname] = e
				local c = fullnames[e.context]
				assert(type(c) == "table" and c.type == "Class", "cannot find parent of enum "..e.fullname)
				if not c.protected_enums then c.protected_enums = {} end
				table.insert(c.protected_enums, e)
			end
		end
	end
end

local function fill_enum_values()
	for _,e in pairs(enum_list) do
		local values = {}
		for _, v in ipairs(e) do
			if v.type=='Enumerator' then
				table.insert(values, v)
			end
		end
		e.values = values
	end
end

function fill_enum_tables()
	for _,e in pairs(enum_list) do
		local table = 'lqt_Enum lqt_enum_'..e.id..'[] = {\n'
		for _,v in pairs(e.values) do
			table = table .. '  { "' .. v.name
				.. '", static_cast<int>('..v.fullname..') },\n'
		end
		table = table .. '  { 0, 0 }\n'
		table = table .. '};\n'
		e.enum_table = table
	end
end

function fill_typesystem(types)
	local etype = function(en)
		return {
			push = function(n)
				return 'lqtL_pushenum(L, '..n..', "'..string.gsub(en, '::', '.')..'")', 1
			end,
			get = function(n)
				return 'static_cast<'..en..'>'
				..'(lqtL_toenum(L, '..n..', "'..string.gsub(en, '::', '.')..'"))', 1
			end,
			test = function(n)
				return 'lqtL_isenum(L, '..n..', "'..string.gsub(en, '::', '.')..'")', 1
			end,
			onstack = string.gsub(en, '::', '.')..',',
			defect = 10, -- check these last
		}
	end
	for _,e in pairs(enum_list) do
		if not types[e.fullname] then
			types[e.fullname] = etype(e.fullname)
		else
			--io.stderr:write(e.fullname, ': already present\n')
		end
	end
end


function print_enum_tables()
	for _,e in pairs(enum_list) do
		if e.access == 'public' then print_enum('static ' .. e.enum_table) end
	end
	return enums
end

function print_enum_creator(mod)
	local out = 'static lqt_Enumlist lqt_enum_list[] = {\n'
	for _,e in pairs(enum_list) do
		if e.access == 'public' then
			out = out..'  { lqt_enum_'..e.id..', "'..string.gsub(e.fullname, "::", ".")..'" },\n'
		end
	end
	out = out..'  { 0, 0 },\n};\n'
	out = out .. 'void lqt_create_enums_'..mod..' (lua_State *L) {\n'
	out = out .. '  lqtL_createenumlist(L, lqt_enum_list);  return;\n}\n'
	print_enum(out)
end

---------------------------------------------------------------------

function preprocess(index)
	copy_enums(index)
end

function process(index, types)
	fill_enum_values()
	fill_enum_tables()
	fill_typesystem(types)
end

function output()
	print_enum(output_includes)
	print_enum_tables()
	print_enum_creator(module_name)
end
