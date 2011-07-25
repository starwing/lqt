local pathsep       = package.config:sub(1,1)
local scriptpath    = string.match(arg[0], '(.*'..pathsep..')[^%'..pathsep..']+') or ''

local function ToString(v, lvl)
    local tt = type(v)
    if tt == 'string' then
        return ('%q'):format(v)

    elseif tt == 'table' then
        lvl = lvl or 0
        local tt = {"{\n"}
        local lvls = ('  '):rep(lvl)
        local lvls2 = ('  '):rep(lvl+1)
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

-- exports
local _M = {}

_M.pathsep       = pathsep
_M.scriptpath    = scriptpath
_M.verbose       = function() end
_M.ToString      = ToString

function _M.set_verbose(b)
    _M.verbose = b and io.stderr.write or function() end
end


function _M.template(text, default)
    if type(text) == 'table' then text = table.concat(text) end
    return function(tbl)
        return (string.gsub(text, "${(%w+)}", setmetatable(tbl, {
                __index = function(t, k) return default end
            })))
    end
end

return _M

