---@diagnostic disable

-- Shared helpers for test cases

local helpers = {}

-- Collects failures instead of aborting on the first one, so a single run reports every mismatch
function helpers.collector()
    local failures = {}

    return {
        check = function(condition, message)
            if not condition then table.insert(failures, message) end
        end,
        done = function()
            if #failures > 0 then
                error(string.format("%d checks failed:\n    ", #failures)
                    .. table.concat(failures, "\n    "), 0)
            end
        end
    }
end

-- True if the two numbers are equal up to floating point noise
function helpers.approx(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) <= 1e-6 * math.max(1, math.abs(b))
end

-- Machines are filed under combined category names, so a lookup by the original
-- category only works when some recipe uses exactly that one. Scanning by name
-- sidesteps that; the proto's own .category field carries the original category.
function helpers.find_machine(name)
    for _, category in pairs(storage.prototypes.machines) do
        for _, member in pairs(category.members) do
            if member.name == name then return member end
        end
    end
end

-- Checks one machine's category, speed, fuel category, and further burner fields
function helpers.check_machine(c, name, expected)
    local proto = helpers.find_machine(name)
    if not proto then
        c.check(false, name .. ": machine missing entirely")
        return nil
    end

    if expected.category then
        c.check(proto.category == expected.category, string.format(
            "%s: expected category %s, got %s", name, expected.category, proto.category))
    end
    if expected.speed then
        c.check(helpers.approx(proto.speed, expected.speed),
            string.format("%s: expected speed %g, got %g", name, expected.speed, proto.speed))
    end
    if expected.fuel_category then
        c.check(proto.burner ~= nil and proto.burner.categories[expected.fuel_category] ~= nil,
            name .. ": missing fuel category " .. expected.fuel_category)
    end
    for key, value in pairs(expected.burner or {}) do
        local actual = proto.burner and proto.burner[key]
        -- Prototype values can pass through 32-bit floats, so compare numbers loosely
        local matches = (type(value) == "number") and helpers.approx(actual, value) or (actual == value)
        c.check(matches, string.format("%s: burner.%s expected %s, got %s",
            name, key, tostring(value), tostring(actual)))
    end

    return proto
end

return helpers
