-- Just basic utility functions


function fstr(o)
    -- Attempts to pretty-print while sanely handling factorio API types
    if type(o) == "number" then
        return tostring(o)
    elseif type(o) == "string" then
        return o
    elseif type(o) == "table" then
        if o.valid ~= nil then
            if not o.valid then
                return "<invalid>"
            elseif not pcall(function() return o.unit_number ~= nil and o.type ~= nil end) then
                return "<non-entity>"
            else
                return "<" .. o.type .. "/" .. fstr(o.unit_number) .. ">"
            end
        else
            local a = {}
            for k,v in pairs(o) do
                table.insert(a, fstr(k) .. " = " .. fstr(v))
            end
            return "{" .. table.concat(a, ", ") .. "}"
        end
    elseif type(o) == "nil" then
        return "<nil>"
    else
        return tostring(o)
    end
end


function compare_dictionaries(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end

    for k, v in pairs(b) do
        if a[k] ~= v then
            return false
        end
    end

    return true
end
