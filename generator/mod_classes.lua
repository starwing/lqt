local types = require 'types'
local utils = require 'utils'

-- fill default constructors/operator=/destructor
local function fill_defaults(c)
end

-- get overloads list in a single class
local function dispatcherlist(c)
    local dlist = {}
    for _, f in ipairs(c) do
        local entry = dlist[f.name]
        if not entry then
            entry = {}
            dlist[f.name] = entry
        end
        entry[f] = true
    end
    return dlist
end

-- fill a class destructor
local function print_destructor(c)
    assert(c.type == 'Function')
end

-- fill a bind function
local function print_bind(c)
    assert(c.type == 'Function', utils.ToString(c))--c.type)

    if c.destructor then
        return print_destructor(c)
    end

    local is_member = c.member_of_class and not c.static

    -- get callline: [rettype ret = ][self->]funcname([arglist]);
    local getargs, arglist, argdesc = types.print_getargs(c, is_member and 2 or 1)

    if not getargs then
        return types.ignore(c.name, c.context, "unknown type: "..arglist)
    elseif getargs ~= "" then
        getargs = getargs .. "    " -- prepare for callline after it
    end

    local callline = {}
    local retline = {}

    if c.constructor then
        callline[#callline+1] = ("%s* ret = new %s"):format(c.member_of_class, c.member_of_class)
        if arglist ~= "" then
            callline[#callline+1] = ("(%s)"):format(arglist)
        end

    else
        if c.type_name ~= 'void' then
            callline[#callline+1] = c.type_name .. " ret = "
        end

        if is_member then
            getargs = utils.template {
                "${clstype}* self = static_cast<${clstype}*>(lqtL_todata(L, 1, \"${metatype}\"));\n",
                "    lqtL_selfcheck(L, self, \"${metatype}\");\n\n",
                "    ", getargs,
            } {
                clstype = c.member_of_class,
                metatype = types.class_cname(c.member_of_class),
            }
            argdesc = ("%s, %s"):format(types.class_cname(c.member_of_class), argdesc)
            callline[#callline+1] = "self->"
        end

        callline[#callline+1] = ("%s(%s)"):format(c.name, arglist)
    end

    if c.type_name ~= 'void' then
        local typesystem = types.typesystem()
        if not typesystem[c.type_name] then
            return types.ignore(c.name, c.member_of_class, "unknown return type: "..c.type_name)
        end
        retline[#retline+1] = 'luaL_checkstack(L, 1, "cannot grow stack for return value")'
        retline[#retline+1] = typesystem[c.type_name].push"ret"
        retline[#retline+1] = "return 1"
    else
        retline[#retline+1] = "return 0"
    end

    return utils.template [[
static int lqt_bind_${id}(lua_State* L) {
    int oldtop = lua_gettop(L);

    ${body};

    lua_settop(L, oldtop);
    ${retline};
} 
]] {
        id = c.id,
        body = getargs .. table.concat(callline),
        retline = table.concat(retline, ";\n    "),
    }, argdesc
end

-- fill a dispatcher function
local function print_dispatcher(list)
end

-- exports
local _M = {}

_M.print_bind = print_bind

function _M.preprocess(ci)
end

function _M.process(ci)
end

function _M.output(ci, modulename, includes)
end

return _M
