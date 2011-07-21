#!/usr/bin/lua

--[[

Copyright (c) 2007-2009 Mauro Iazzi

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--]]

local utils = require 'utils'

-- Field explanation:
-- * push - push the instance of a class onto Lua stack
-- * get - retrieve the instance from Lua stack
-- * raw_test - true if the stack index is an instance
-- * test - true if the stack index is an instance, or if it is convertible to the type
-- * bound - true for generated classes (false for native types)
-- * foreign - comes from other module (like QtCore)

local can_convert = {}
local classes = {}
local functions = {}
local fullnames = {}
local typetable = {}


local function decl_type(onstack, get, push, test)
    local t = {
        onstack = onstack,
        get = get,
        push = push,
        test = test,
    }
    return t
end

local function format_type(onstack, d, get, push, test)
    local t = {onstack = onstack}
    t.get = type(get) ~= 'string' and get or function(arg) return get:format(tostring(arg)), d end
    t.push = type(push) ~= 'string' and push or function(arg) return push:format(tostring(arg)), d end
    t.test = type(test) ~= 'string' and test or function(arg) return test:format(tostring(arg)), d end
    return t
end

local function numeric_type(d, type)
    local t = format_type("number", 1,
        ("lua_to%s(L, %%s)"):format(type),
        ("lua_push%s(L, %%s)"):format(type),
        ("lqtL_is%s(L, %%s)"):format(type))
    t.defect = d
    return t
end

local function enum_type(en)
    local tn = string.gsub(en, '::', '.')

    local t = format_type(en, 1,
        ('static_cast<%s>(lqtL_toenum(L, %%s, "%s"))'):format(tn, tn),
        ('lqtL_pushenum(L, %%s, "%s")'):format(tn),
        ('lqtL_isenum(L, %%s, "%s")'):format(tn))
    t.defect = 10 -- check these last
    return t
end

local function class_instance_type(classname, foreign)
    local tn = string.gsub(classname, '::', '.')..'*'
    local t = format_type(tn, 1,
        ('*static_cast<%s*>(lqtL_toudata(L, %%s, "%s"))'):format(classname, tn),
        ('lqtL_copyudata(L, &%%s, "%s")'):format(tn),
        ('lqtL_isudata(L, %%s, "%s")'):format(tn))
    t.raw_test = function(arg) return ('lqtL_isudata(L, %s, "%s")'):match(arg, tn) end
    t.bound = true
    t.foreign = foreign
    return t
end

local function class_ptr_type(classname, foreign)
    local tn = string.gsub(classname, '::', '.')..'*'
    local t = format_type(tn, 1,
        ('static_cast<%s*>(lqtL_toudata(L, %%s, "%s"))'):format(classname, tn),
        ('lqtL_pushudata(L, %%s, "%s")'):format(tn),
        ('lqtL_isudata(L, %%s, "%s")'):format(tn))
    t.raw_test = function(arg) return ('lqtL_isudata(L, %s, "%s")'):match(arg, tn) end
    t.bound = true
    t.foreign = foreign
    return t
end

local function class_ref_type(classname, foreign)
    local tn = string.gsub(classname, '::', '.')..'*'
    local t = format_type(tn, 1,
        ('*static_cast<%s*>(lqtL_toudata(L, %%s, "%s"))'):format(classname, tn),
        ('lqtL_pushudata(L, &%%s, "%s")'):format(tn),
        ('lqtL_isudata(L, %%s, "%s")'):format(tn))
    t.raw_test = function(arg) return ('lqtL_isudata(L, %s, "%s")'):match(arg, tn) end
    t.bound = true
    t.foreign = foreign
    return t
end

local function class_const_ptr_type(classname, foreign)
    local tn = string.gsub(classname, '::', '.')..'*'
    local t = format_type(tn, 1,
        function(arg)
            local method = can_convert[classname] and 'convert' or 'toudata'
            return ('static_cast<%s*>(lqtL_%s(L, %s, "%s")'):format(classname, method, arg, tn), 1
        end,
        ('lqtL_pushudata(L, %%s, "%s")'):format(tn),
        function(arg)
            local method = can_convert[classname] and 'canconvert' or 'isudata'
            return ('lqtL_%s(L, %s, "%s")'):format(method, arg, tn), 1
        end)
    t.raw_test = function(arg) return ('lqtL_isudata(L, %s, "%s")'):match(arg, tn), 1 end
    t.bound = true
    t.foreign = foreign
    return t
end

local function class_const_ref_type(classname, foreign)
    local tn = string.gsub(classname, '::', '.')..'*'
    local t = format_type(tn, 1,
        function(arg)
            local method = can_convert[classname] and 'convert' or 'toudata'
            return ('*static_cast<%s*>(lqtL_%s(L, %s, "%s"))'):format(classname, method, arg, tn), 1
        end,
        ('lqtL_copyudata(L, &%%s, "%s")'):format(tn),
        function(arg)
            local method = can_convert[classname] and 'canconvert' or 'isudata'
            return ('lqtL_%s(L, %s, "%s")'):format(method, arg, tn), 1
        end)
    t.raw_test = function(arg) return ('lqtL_isudata(L, %s, "%s")'):match(arg, tn), 1 end
    t.bound = true
    t.foreign = foreign
    return t
end

local class_ptr_ref_type = class_ptr_type
local class_const_ptr_ref_type = class_const_ptr_type

-- type table
typetable['char'] = numeric_type(3, "integer")
typetable['unsigned char'] = numeric_type(3, "integer")
typetable['int'] = numeric_type(1, "integer")
typetable['unsigned'] = numeric_type(1, "integer")
typetable['unsigned int'] = numeric_type(1, "integer")
typetable['short'] = numeric_type(2, "integer")
typetable['short int'] = numeric_type(2, "integer")
typetable['unsigned short'] = numeric_type(2, "integer")
typetable['unsigned short int'] = numeric_type(2, "integer")
typetable['short unsigned int'] = numeric_type(2, "integer")
typetable['long'] = numeric_type(0, "integer")
typetable['unsigned long'] = numeric_type(0, "integer")
typetable['long int'] = numeric_type(0, "integer")
typetable['unsigned long int'] = numeric_type(0, "integer")
typetable['long unsigned int'] = numeric_type(0, "integer")
typetable['long long'] = numeric_type(0, "integer")
typetable['unsigned long long'] = numeric_type(0, "integer")
typetable['long long int'] = numeric_type(0, "integer")
typetable['unsigned long long int'] = numeric_type(0, "integer")
typetable['__int64'] = numeric_type(0, "integer")
typetable['unsigned __int64'] = numeric_type(0, "integer")
typetable['float'] = numeric_type(1, "number")
typetable['double'] = numeric_type(0, "number")
typetable['double const&'] = numeric_type(1, "number")
typetable['bool'] = numeric_type(1, "boolean")

for k in pairs(typetable) do
    typetable[k..' const'] = typetable[k]
end

typetable['bool*'] = format_type('boolean', 1,
    'lqtL_toboolref(L, %s)',
    'lua_pushboolean(L, *%s)',
    'lqtL_isboolean(L, %s)')

typetable['int&'] = format_type('integer', 1,
    'lqtL_tointref(L, %s)',
    'lua_pushinteger(L, %s)',
    'lqtL_isinteger(L, %s)')
typetable['unsigned int&'] = typetable['int&']
    
typetable['int*'] = format_type('integer', 1,
    'lqtL_tointref(L, %s)',
    'lua_pushinteger(L, *%s)',
    'lqtL_isinteger(L, %s)')

typetable['char**'] = format_type('char**', 1,
    'lqtL_toarguments(L, %s)',
    'lqtL_pusharguments(L, %s)',
    'lua_istable(L, %s)')

typetable['char const*'] = format_type('string', 1,
    'lua_tostring(L, %s)',
    'lua_pushstring(L, %s)',
    'lqtL_isstring(L, %s)')

typetable['char*'] = typetable['char const*']
typetable['char*&'] = typetable['char const*']

typetable['std::string const&'] = decl_type('string',
    function(i) return ('std::string(lua_tostring(L, %s), lua_objlen(L, %s))'):match(i, i), 1 end,
    function(i) return ('lua_pushlstring(L, %s.c_str(), %s.size())'):match(i, i), 1 end,
    function(i) return ('lua_isstring(L, %s)'):format(i), 1 end)
    
typetable['std::string'] = decl_type('string',
    function(i) return ('std::string(lua_tostring(L, %s), lua_objlen(L, %s))'):match(i, i), 1 end,
    function(i) return ('lua_pushlstring(L, %s.c_str(), %s.size())'):match(i, i), 1 end,
    function(i) return ('lua_isstring(L, %s)'):format(i), 1 end)


-- utils functions

-- Determines, if a class is public, requires fullnames
local function is_class_public(c)
    repeat
        if c.access ~= 'public' then return false end
        if not c.member_of_class then return true end

        c = assert(fullnames[c.member_of_class], 'member_of_class should exist')
        assert(c.label=='Class', 'member_of_class should be a class')
    until true
end

-- resolve name in context, return classinfo of name or nil, requires
-- fullnames
local function resolve(name, context)
    while not fullnames[context..'::'..name] and context~='' do
        context = string.match(context, '^(.*)::') or ''
    end
    return fullnames[context..'::'..name] or fullnames[name]
end

local function newtype(name, type)
    if not typetable[name] then
        typetable[name] = type
        return true
    end
end

local function newclass(name, foreign)
    if not typetable[name] then
        typetable[name]             = class_instance_type(name, foreign)
        typetable[name..' const']   = class_instance_type(name, foreign)

        typetable[name..'*']        = class_ptr_type(name, foreign)
        typetable[name..'&']        = class_ref_type(name, foreign)
        typetable[name..'*&']       = class_ptr_ref_type(name, foreign)
        typetable[name..' const*']  = class_const_ptr_type(name, foreign)
        typetable[name..' const&']  = class_const_ref_type(name, foreign)
        typetable[name..'* const&'] = class_const_ptr_ref_type(name, foreign)

        return true
    end
end

local function newenum(name)
    if not typetable[name] then
        typetable[name] = enum_type(name)
        return true
    end
end

local function register_ci(ci, fix_class, fix_function)
    -- fill fullnames
    for e in pairs(ci:allentries()) do
        if e.fullname then fullnames[e.fullname] = e end
    end

    -- get functions and classes
    for e in pairs(ci:allentries()) do
        if e.type == 'Class' then
            classes[e] = true
            e.cname = string.gsub(e.fullname, '::', '_LQT_')

            if not is_class_public(e) then
                utils.ignore(e.fullname, 'not public')
            elseif not e.fullname:match'%b<>' then
                classes[e] = true
                if fix_class then fix_class(e) end

            -- XXX don't support template now.
            --elseif templates.should_copy(e) then
                --templates.create(e, classes)
            end

        elseif e.type == 'Enum' then
            newenum(e.fullname)

        elseif e.type:match'^Function' then
            e.type = 'Function'
            functions[e] = true
            -- fix void arguments.
            if #e == 1 and e[1].type_name == 'void' then
                e[1] = nil
            end
            -- fix constructor and destructor
            if e.name == e.member_of_class then
                e.constructor = true
            elseif e.name:match '~' then
                e.destructor = true
            end

            if fix_function then fix_function(e) end
        end
    end

    -- process all classes
    for c in pairs(classes) do
        -- register it in typetable
        newclass(c.fullname)

        -- get can_convert table
        for _,f in ipairs(c) do
            if f.type == 'Function' then
                -- find non-explicit constructor, which has 1 argument of type different
                -- from class, i.e. an implicit conversion constructor
                if      f.constructor
                    and #f == 1
                    and (not f.access or f.access == "public")
                    and f[1].type_base ~= c.name
                    and not f[1].type_base:match('Private$')
                    -- and not f.explicit
                    and not c.abstract
                then
                    local classname = c.fullname
                    local from_type = f[1].type_base
                    can_convert[classname] = can_convert[classname] or { from = {}, class = c }
                    can_convert[classname].from[ from_type ] = f
                end
            end
        end
    end
end

local function typepair(tn, name)
    local ret
    if string.match(tn, '%(%*%)') then
        ret = string.gsub(tn, '%(%*%)', '(*'..name..')', 1)
    elseif string.match(tn, '%[.*%]') then
        ret = string.gsub(tn, '%s*(%[.*%])', ' '..name..'%1')
    else
        ret = tn .. ' ' .. name
    end
    return ret
end

--- Constructs the code that pushes arguments to the Lua stack.
-- Returns the code as a string, and stack increment. In case that an unknown
-- type is encountered, nil and the unknown type is returned.
local function print_pushargs(args)
    local codelines = {}
    local stack = 0

    for i, a in ipairs(args) do
        if not typetable[a.type_name] then return nil, a.type_name end
        local apush, an = typetable[a.type_name].push('arg'..i)
        table.insert(codelines, '    ' .. apush .. ';\n');
        stack = stack + an
    end

    return table.concat(codelines), stack
end

--- Constructs that code that get arguments from the Lua stack.
--Returns the code as a string, and the codelines for use these
--argument, and argument description used for overloads error
--messsage. In case that an unknown type in encountered, nil and the
--unknown type is returned.
local function print_getargs(args, stackn)
    local argdesc = {}
    local callline = {}
    local codelines = {}

    local argn = 1
    local stackn = stackn or 1

    local I, C = table.insert, table.concat
    for i, a in ipairs(args) do
        if not typetable[a.type_name] then return nil, a.type_name end

        I(argdesc, typetable[a.type_name].onstack)

        local argname = 'arg'..argn
        local aget, an, arg_as = typetable[a.type_name].get(stackn)

        I(codelines, '    ' .. typepair(arg_as or a.type_name, argname) .. ' = ')
        if a.default=='1' and an > 0 then
            local condt = {}
            for j = stackn, stackn+an-1 do
                I(condt, ('lua_isnoneornil(L, %d)'):match(j))
            end
            I(codelines, ("(%s) ? static_cast<%s>(%s) : "):format(
                C(condt, ' && '), a.type_name, a.defaultvalue))
        end
        I(codelines, aget..';\n')
        I(callline, argname)

        stackn = stackn + an
        argn = argn + 1
    end

    return C(codelines), '('..C(callline, ', ')..')', C(argdesc, ", ")
end

-- debug
setmetatable(typetable, {
    __newindex = function(t, k, v)
        utils.verbose('Added type: ', k)
        rawset(typetable, k, v)
    end,
    __index = function(t, k)
        utils.verbose("Unknown type: ", tostring(k), ret)
    end,
})

-- export functions
local _M = {}

_M.decl_type                = decl_type
_M.format_type              = format_type
_M.numeric_type             = numeric_type
_M.class_instance_type      = class_instance_type
_M.class_ptr_type           = class_ptr_type
_M.class_ref_type           = class_ref_type
_M.class_const_ptr_type     = class_const_ptr_type
_M.class_const_ref_type     = class_const_ref_type
_M.class_const_ptr_ref_type = class_const_ptr_ref_type

function _M.typesystem() return typetable end
function _M.classes()    return classes end
function _M.functions()  return functions end
function _M.fullnames()  return fullnames end

_M.newtype = newtype
_M.newclass = newclass
_M.register_ci = register_ci
_M.typepair = typepair
_M.print_pushargs = print_pushargs
_M.print_getargs = print_getargs

return _M
