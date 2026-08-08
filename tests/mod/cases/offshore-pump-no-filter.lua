---@diagnostic disable

-- An offshore pump whose fluid box has no filter, which must land in the generic
-- category rather than a fluid-specific one.

return {
    setup = function()
        local copy = lib.flib.deep_copy(data.raw["offshore-pump"]["offshore-pump"])
        copy.name = "offshore-pump-no-filter"
        copy.fluid_box.filter = nil
        data:extend{ copy }
    end,

    check = function()
        assert(prototyper.util.find("machines", "offshore-pump-no-filter", "offshore-pump"),
            "pump missing from the generic offshore-pump category")
        assert(prototyper.util.find("machines", "offshore-pump-no-filter", "offshore-pump-water") == nil,
            "pump must not appear in a fluid-specific category")
    end
}
