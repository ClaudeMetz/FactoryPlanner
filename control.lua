require("data.init")
require("ui.dialogs.main_dialog")


-- Returns string of given table, used for debugging
function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
            if not string.find(k, "^__[a-z-]+$") then
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..'] = ' .. dump(v) .. ','
            end
            -- log(k)
        end
        return s .. '} '
    else
        return tostring(o)
    end
end