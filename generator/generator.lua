#!/usr/bin/lua

--[[

Copyright (c) 2007-2009 Mauro Iazzi
Copyright (c)      2008 Peter K�mmel
Copyright (c)      2010 Michal Kottman
Copyright (c)      2011 Wang Xu

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

require 'utils'
require 'types'
require 'classinfo'

-- initial include paths
local includes = {
    'lqt_common.hpp',
}

-- inital process modules
local modules = {
    'mod_virtuals',
    'mod_enums',
    'mod_classes',
}


local modulename = "noname"
local filename = nil
local typefiles = {}


-- help text
local function help()
    print [[
usage: generator options filename
options:
    -c path     specifies the template file
    -h          show this message
    -i path     add a include path
    -m module   add a process module into translation
    -n name     module name
    -t path     add a typefiles
    -v          show more messages
]]
    os.exit(2)
end

-- process command line arguments.
do
    local i = 1
    local arg = {n = select('#', ...), ... }
    while i <= arg.n do
        local curarg = arg[i]
        local opt, argvalue = curarg:match('^-(.)(.*)$')
        i = i + 1

        if opt then
            if not argvalue then
                argvalue = arg[i + 1]
                i = i + 1
            end

            if opt == 'c' then
                template_file = argvalue
            elseif opt == 'h' then
                help()
            elseif opt == 'i' then
                table.insert(includes, argvalue)
            elseif opt == 'm' then
                table.insert(modules, 1, argvalue)
            elseif opt == 'n' then
                modulename = argvalue
            elseif opt == 't' then
                table.insert(typefiles, argvalue)
            elseif opt == 'v' then
                utils.setverbose(true)
            end
        else
            filename = filename and error'duplicate filename' or curarg
        end
    end

    if not filename then
        help()
    end
end

-- set output includes
do
    local my_includes = {}
    for _, i in ipairs(includes) do
        if string.match(i, '^<.+>$') then
            table.insert(my_includes, '#include '..i)
        elseif string.match(i, '^".+"$') then
            table.insert(my_includes, '#include '..i)
        else
            table.insert(my_includes, '#include "'..i..'"')
        end
    end
    table.insert(my_includes, '')
    includes = table.concat(my_includes, '\n')
    utils.verbose("includes = \n", includes, "\n\n")
end

-- load classinfo from filename.
local ci do
    io.input(filename)
    local t = assert(loadstring("return "..io.read'*a'))()
    io.input():close()

    ci = classinfo.new(t)

    -- XXX You can register more than one classinfo, Yes u can :)
    types.register_ci(ci)
end

----------------------------------------------------------------------------------

for i, ft in ipairs(typefiles) do
    assert(loadfile(ft))(types)
end

-- process classinfo
do
    for k, v in ipairs(modules) do
        modules[k] = require(v)
    end

    ------------- BEGIN PREPARE
    for k, v in ipairs(modules) do
        v.preprocess(ci)
    end

    ------------- BEGIN PROCESS
    for k, v in ipairs(modules) do
        v.process(ci)
    end

    ------------- BEGIN OUTPUT
    for k, v in ipairs(modules) do
        v.output(ci, modulename, includes)
    end
end

-- vim: set ft=lua nu et sw=4 ts=8:
