---@diagnostic disable

-- Runs alongside the regular base game, for cases that need its prototypes.
-- Cases consist of data stage setup and runtime checks: setup runs via the test
-- mod's data.lua, check runs in the main mod's environment.

local function assert_nil(value)
    if value ~= nil then
        error("Expected nil, got " .. tostring(value))
    end
end

return {
    cases = {
        testOffshorePumpWithNoFilter = {
            setup = function()
                local copy = lib.flib.deep_copy(data.raw["offshore-pump"]["offshore-pump"])
                copy.name = "offshore-pump-no-filter"
                copy.fluid_box.filter = nil
                data:extend{ copy }
            end,
            check = function()
                local recipes = storage.prototypes.recipes
                assert_nil(recipes["offshore-pump-no-filter"])
            end
        }
    }
}
