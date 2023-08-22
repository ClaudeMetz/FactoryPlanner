---@diagnostic disable

local parts = {}

-- This likely requires a system to define custom prototypes as well, since the vanilla ones
--      don't cover nearly all use cases. It'll also allow some conveniences like easier numbers
--      (ex. machine speed of 1), and make it independent of any vanilla prototype changes.
--      Could define real prototypes, but that has quite a few downsides, and also makes the
--      generator part of the test net, which I'd like to avoid. So a system to create fake
--      internal prototype definitions similar to this one could work.
-- Also, these parts are missing lots of things (like the line missing its beacon, for example)

function parts.export_string(setup)
    return game.table_to_json({
        export_modset = {
            base = "1.1.80",
            flib = "0.12.6",
            factoryplanner = "1.1.64"
        },
        subfactories = {
            setup
        }
    })
end

function parts.subfactory(members)
    return {
        name = "Test",
        timescale = 1,
        notes = "",
        blueprints = {},
        Product = {
            objects = {
                members.products
            },
            class = "Collection"
        },
        top_floor = {
            Line = {
                objects = {
                    members.lines
                },
                class = "Collection"
            },
            level = 1,
            class = "Floor"
        },
        class = "Subfactory"
    }
end

function parts.top_level_product(type, name, amount)
    return {
        proto = {
            name = name,
            simplified = true,
            type = type
        },
        --amount = amount,
        required_amount = {
            defined_by = "amount",
            amount = amount,
            belt_proto = false
        },
        top_level = true,
        class = "Product"
    }
end

function parts.line(members)
    return {
        class = "Line",
        recipe = members.recipe,
        active = true,
        done = false,
        percentage = members.percentage or 100,
        machine = members.machine,
        --[[ Product = {
            objects = { {
                proto = {
                    name = "iron-plate",
                    simplified = true,
                    type = "item"
                },
                amount = 10,
                top_level = false,
                class = "Product"
            } },
            class = "Collection"
        } ]]
    }
end

function parts.recipe(category, name)
    return {
        proto = {
            name = name,
            simplified = true,
            category = category
        },
        production_type = "produce",
        class = "Recipe"
    }
end

function parts.machine(category, name, members)
    return {
        proto = {
            name = name,
            simplified = true,
            category = category
        },
        force_limit = true,
        fuel = members.fuel,
        module_set = members.module_set,
        class = "Machine"
    }
end

function parts.fuel(category, name)
    return {
        proto = {
            name = name,
            simplified = true,
            category = category
        },
        --amount = 0.72,
        class = "Fuel"
    }
end

function parts.module_set(modules)
    return {
        modules = {
            objects = modules,
            class = "Collection"
        },
        --module_count = 0,
        --empty_slots = 0,
        class = "ModuleSet"
    }
end

return parts
