module('properties', package.seeall)

local function get_variables(class)
    local vars = {}
    local function traverse(c)
        for i, var in ipairs(c) do
            if var.type == "Variable" and var.access == "public" then
                table.insert(vars, var)
            end
        end
        for _, b in ipairs(c.bases or {}) do
            local base = fullnames[b]
            if base then traverse(base) end
        end
    end
    traverse(class)
    return vars
end

function fill_properties(classes)
    for c in pairs(classes) do
        local props = {}
        local vars = get_variables(c)
        for i, var in ipairs(vars) do
            local targetType = typesystem[var.type_name]
            if targetType then
                local sget = typesystem[c.fullname..'*'].get(1)
                local getter =
                  '  ' .. c.fullname .. '* self = ' .. sget .. ';\n' ..
                  '  lqtL_selfcheck(L, self, "'..c.fullname..'");\n' ..
                  '  ' .. targetType.push('self->'..var.name) .. ';\n' ..
                  '  return 1;\n'
                
                local setter
                if not var.type_constant then
                    setter = 
                  '  ' .. c.fullname .. '* self = ' .. sget .. ';\n' ..
                  '  lqtL_selfcheck(L, self, "'..c.fullname..'");\n' ..
                  '  self->' .. var.name .. ' = ' .. targetType.get(3) .. ';\n' ..
                  '  return 0;\n'
                end

                table.insert(props, { class=c.cname, name = var.name, type = var.type_name,
                    getter = getter, setter = setter })
            end
        end
        if next(props) then
            local properties = ''
            local getters, setters = {}, {}
            for i, p in ipairs(props) do
                properties = properties .. 'static int '..p.class..'_get_'..p.name..'(lua_State *L) {\n'..p.getter..'}\n'
                table.insert(getters, p)
                if p.setter then
                    properties = properties .. 'static int '..p.class..'_set_'..p.name..'(lua_State *L) {\n'..p.setter..'}\n'
                    table.insert(setters, p)
                end
            end
            -- there can be less setters than getters, due to 'const'
            for i,g in ipairs(getters) do
                getters[i] = '  {"'..g.name..'", '..g.class..'_get_'..g.name..'},'
            end
            for i,s in ipairs(setters) do
                setters[i] = '  {"'..s.name..'", '..s.class..'_set_'..s.name..'},'
            end
            c.properties = properties..'\n'..
                'static luaL_Reg lqt_getters_'..c.id..'[] = {\n'..table.concat(getters, '\n')..'  {NULL, NULL}\n};\n\n' ..
                'static luaL_Reg lqt_setters_'..c.id..'[] = {\n'..table.concat(setters, '\n')..'  {NULL, NULL}\n};\n\n'
        end
    end
end
