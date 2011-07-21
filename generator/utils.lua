local pathsep       = package.config:sub(1,1)
local scriptpath    = string.match(arg[0], '(.*'..pathsep..')[^%'..pathsep..']+') or ''

-- exports
local _M = {}

_M.pathsep       = pathsep
_M.scriptpath    = scriptpath

function _M.verbose()
end

function _M.ignore(name)
    assert(require 'types'.fullnames()[name]).ignore = true
end

function _M.setverbose(b)
    verbose = b and io.stderr.write or function() end
    function ignore(name, cause, context)
        assert(require 'types'.fullnames()[name]).ignore = true
        ignore_file:write(name, ';', cause, ';', (context or ''), '\n')
    end
end

function _M.ToString(v, lvl)
    local tt = type(v)
    if tt == 'string' then
        return ('%q'):format(v)

    elseif tt == 'table' then
        lvl = lvl or 0
        local tt = {"{\n"}
        local lvls = ('  '):rep(lvl)
        local lvls2 = ('  '):rep(lvl+1)
        local ToString = ToString
        for key, val in pairs(v) do
            local cur = #tt
            tt[cur+1] = lvls2
            tt[cur+2] = "["
            tt[cur+3] = ToString(key, lvl+1)
            tt[cur+4] = "]="
            tt[cur+5] = ToString(val, lvl+1)
            tt[cur+6] = ",\n"
        end
        tt[#tt+1] = lvls
        tt[#tt+1] = "}"
        return table.concat(tt, "")
    end
    return tostring(v)
end

function _M.template(text, tbl)
    return string.gsub(text, "${%w+}", tbl)
end

return _M
