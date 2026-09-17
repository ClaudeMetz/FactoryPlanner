---@diagnostic disable

local helpers = require("helpers")

-- Separate configuration so non-neutral normal-quality capacity doesn't change
-- the ordinary research fixtures
return {
    setup = function()
        local deepcopy = require("util").table.deepcopy
        data.raw.quality.normal.tool_durability_multiplier = 3
        data.raw.quality.normal.science_capacity_multiplier = 2

        local basic = deepcopy(data.raw.item["automation-science-pack"])
        basic.name = "test-durability-basic"
        local dense = deepcopy(basic)
        dense.name = "test-durability-dense"
        dense.science_capacity = 4
        local tool = deepcopy(basic)
        tool.name = "test-durability-tool"
        tool.type = "tool"
        tool.durability = 5
        tool.science_capacity = 99  -- Tools must ignore the ordinary item capacity

        local lab = deepcopy(data.raw.lab.lab)
        lab.name = "test-durability-lab"
        lab.inputs = {basic.name, dense.name, tool.name}
        lab.next_upgrade = nil
        local tech = deepcopy(data.raw.technology.automation)
        tech.name = "test-durability-tech"
        tech.prerequisites = nil
        tech.effects = nil
        tech.unit = {count = 10, time = 17,
            ingredients = {{basic.name, 1}, {dense.name, 1}, {tool.name, 2}}}
        data:extend{basic, dense, tool, lab, tech}
    end,

    check = function()
        local c = helpers.collector()
        -- Bucketing and recipe identity still use the technology's original amounts
        local recipe = prototyper.util.find("recipes", "impostor-research-"
            .. "test-durability-basic-test-durability-dense-test-durability-tool"
            .. "-1020-test-durability-tool-2")
        c.check(recipe ~= nil, "durability: research recipe missing or renamed")
        if recipe then
            local expected = {
                ["test-durability-basic"] = 0.5,
                ["test-durability-dense"] = 0.125,
                ["test-durability-tool"] = 2 / 15
            }
            c.check(#recipe.ingredients == 3, "durability: expected all three ingredients")
            for _, ingredient in pairs(recipe.ingredients) do
                c.check(helpers.approx(ingredient.amount, expected[ingredient.name]),
                    ingredient.name .. ": incorrect consumption per research unit")
            end
            c.check(recipe.energy == 17, "durability: research time changed")
            c.check(#recipe.products == 1 and recipe.products[1].amount == 1,
                "durability: research output changed")
        end
        c.done()
    end
}
