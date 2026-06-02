---@diagnostic disable

local function assert_nil(value)
    if value ~= nil then
        error("Expected nil, got " .. tostring(value))
    end
end

-- Test cases consist of data stage setup and runtime checks
-- Setup is run via the test mod, check is run in the main mod's environment

return {
    testOffshorePumpWithNoFilter = {
        setup = function()
            local copy = util.flib.deep_copy(data.raw["offshore-pump"]["offshore-pump"])
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
