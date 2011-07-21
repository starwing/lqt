module ('classinfo', package.seeall)

-- classinfo root construct:
-- * every element(include root) has some fields as its hash-part
--   and has some children as its array-part.
-- * elements has serveral type, as its "type field":
--      - "File"        the root
--      - "Namespace"   a namespace
--      - "Class"       a struct or enum or class or class template
--      - "Enum"        a enum
--      - "Enumerator"  a enum member
--      - "Function"    a function or class method or function
--                      template
--      - "Argument"    a argument of function
--      - "Variable"    a global variable or data member of class
--      - "TypeAlias"   a typedef
-- * every element has these field:
--      - type          decription as above.
--      - id            the unique id in total file.
--      - name          the identify name of this element
--      - scope         the scope the name occurs.
--      - context       the context the name occurs.
--      - type_name     the type of this identify, or the return type
--                      of a function.
--      - type_base     the identify of type.
-- * there are some special fields in some element:
--      - fullname      the qualfied name of the element (not in
--                      Argument)
--      - class_type    "struct", "unique" or "class", 

function new(tbl)
    local self = setmetatable({ info = tbl }, {__index = _M})

    -- Remove duplicate entries (~4300/20000 for QtCore)
    do
        local allentries = allentries(self)
        local dups = {}
        local remove = {}
        for e in pairs(allentries) do
            if e.id and dups[e.id] then
                -- print('Duplicate!', dups[e.id], e.name, e.id)
                remove[e] = true
            end
            dups[e.id] = true
        end
        for e in pairs(remove) do
            allentries[e] = nil
        end
    end

    return self
end

function root(self)
    return self.info
end

function allentries(self)
    if not self.idtable then
        local idtable = {}
        function _dfs(t)
            idtable[t] = true
            for k, v in ipairs(t) do
                _dfs(v)
            end
        end
        _dfs(root(self))
        self.idtable = idtable
    end
    return self.idtable
end

function next_id(self)
    if not self.gen_id then
        local gen_id = 0
        for e in pairs(allentries(self)) do
            if e and e.id then
                local id = assert(tonumber(e.id))
                if id > gen_id then gen_id = id + 1 end
            end
        end 
        self.gen_id = gen_id
    end
    self.gen_id = self.gen_id + 1
    return "_" .. tostring(self.gen_id)
end

