---@diagnostic disable

local helpers = require("helpers")

local fixtures = {
    {type = "assembling-machine", base = "assembling-machine-2", bonus = 3},
    {type = "mining-drill", base = "electric-mining-drill", bonus = 4},
    {type = "lab", base = "lab", bonus = 2},
    {type = "beacon", base = "beacon", bonus = 5}
}
local variants = {
    {name = "fixed", slots = 2, enabled = false},
    {name = "quality", slots = 2, enabled = true}
}

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy
        data.raw.quality.normal.crafting_machine_speed_multiplier = 1.5
        data.raw.quality.normal.crafting_machine_module_slots_bonus = 3
        data.raw.quality.normal.mining_drill_module_slots_bonus = 4
        data.raw.quality.normal.lab_module_slots_bonus = 2
        data.raw.quality.normal.beacon_module_slots_bonus = 5

        for _, fixture in ipairs(fixtures) do
            for _, variant in ipairs(variants) do
                local proto = deepcopy(data.raw[fixture.type][fixture.base])
                proto.name = "test-baseline-" .. fixture.type .. "-" .. variant.name
                proto.fast_replaceable_group = nil
                proto.next_upgrade = nil
                proto.module_slots = variant.slots
                proto.quality_affects_module_slots = variant.enabled
                if fixture.type == "assembling-machine" then
                    -- Entity overrides must take precedence over the quality's own multipliers.
                    proto.crafting_speed = 2
                    proto.crafting_speed_quality_multiplier = {normal = 2.5}
                    proto.module_slots_quality_bonus = {normal = 6}
                end
                data:extend{proto}
            end
        end
    end,

    check = function(context)
        local c = helpers.collector()
        for _, fixture in ipairs(fixtures) do
            for _, variant in ipairs(variants) do
                local name = "test-baseline-" .. fixture.type .. "-" .. variant.name
                local is_beacon = fixture.type == "beacon"
                local is_crafter = fixture.type == "assembling-machine"
                local proto = is_beacon and prototyper.util.find("beacons", name)
                    or helpers.find_machine(name)
                c.check(proto ~= nil, name .. ": missing prototype")
                if proto then
                    local class = is_beacon and context.classes.Beacon or context.classes.Machine
                    local object = class.init({}, proto)
                    local bonus = is_crafter and 6 or fixture.bonus
                    local expected = variant.slots + (variant.enabled and bonus or 0)
                    c.check(proto.module_limit == variant.slots, name .. ": incorrect slot baseline")
                    c.check(object:get_module_limit() == expected, name .. ": incorrect normal slot count")

                    if is_crafter then
                        c.check(helpers.approx(proto.speed, 2), name .. ": incorrect raw crafting speed")
                        c.check(helpers.approx(object:get_speed(), 5), name .. ": incorrect normal crafting speed")
                    end

                    -- Synthetic qualities exercise scalar arithmetic without enabling the quality mod.
                    object.proto = lib.flib.shallow_copy(proto)
                    object.proto.module_slots_quality_bonus = {synthetic = 7}
                    object.proto.crafting_speed_quality_multiplier = {synthetic = 4}
                    object.quality_proto = {
                        name = "synthetic", mining_drill_module_slots_bonus = 7,
                        lab_module_slots_bonus = 7, beacon_module_slots_bonus = 7
                    }
                    c.check(object:get_module_limit() == (variant.enabled and 9 or 2),
                        name .. ": normal bonus leaked into the selected quality")
                    if is_crafter then
                        c.check(helpers.approx(object:get_speed(), 8),
                            name .. ": normal multiplier leaked into the selected quality")
                    end
                end
            end
        end

        -- Also cover a crafter using the quality's default rather than an entity override.
        local crafter = helpers.find_machine("assembling-machine-2")
        c.check(crafter ~= nil, "default crafter: missing prototype")
        if crafter then
            local object = context.classes.Machine.init({}, crafter)
            c.check(helpers.approx(crafter.speed, 0.75), "default crafter: incorrect raw speed")
            c.check(helpers.approx(object:get_speed(), 1.125), "default crafter: incorrect normal speed")
        end
        c.done()
    end
}
