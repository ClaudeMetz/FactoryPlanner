---@diagnostic disable

-- This directly uses class methods, which is inherently fragile, but there's no
-- good way around it. The minimum migration version will need to be moved past
-- this is there ever is a large change related to this again.
local District = require("backend.data.District")
local Factory = require("backend.data.Factory")
local Product = require("backend.data.Product")
local Floor = require("backend.data.Floor")
local Line = require("backend.data.Line")
local Machine = require("backend.data.Machine")
local Fuel = require("backend.data.Fuel")

local migration = {}

function migration.global()
    global.current_ID = 0
    global.mod_version = nil
end

function migration.player_table(player_table)
    player_table.district = District.init()
    player_table.context = {
        object_id = 2,  -- set to first floor preemptively
        cache = {main = nil, archive = nil, factory = {}}
    }

    for _, factory_name in pairs({"factory", "archive"}) do
        for _, subfactory in pairs(player_table[factory_name].Subfactory.datasets) do
            local factory = Factory.init(subfactory.name, subfactory.timescale)
            factory.archived = (factory_name == "archive")

            factory.mining_productivity = subfactory.mining_productivity
            factory.matrix_free_items = subfactory.matrix_free_items
            factory.blueprints = subfactory.blueprints
            factory.notes = subfactory.notes

            factory.tick_of_deletion = subfactory.tick_of_deletion
            factory.item_request_proxy = subfactory.item_request_proxy
            factory.last_valid_modset = subfactory.last_valid_modset

            for _, product in pairs(subfactory.Product.datasets) do
                local new_product = Product.init(product.proto)
                new_product.defined_by = product.required_amount.defined_by
                new_product.required_amount = product.required_amount.amount
                new_product.belt_proto = product.required_amount.belt_proto
                factory:insert(new_product)
            end

            local function convert_floor(floor)
                local new_floor = Floor.init(floor.level)
                for _, line in pairs(floor.Line.datasets) do
                    if line.subfloor then
                        local subfloor = convert_floor(line.subfloor)
                        new_floor:insert(subfloor)
                    else
                        local new_line = Line.init(line.recipe.proto, line.recipe.production_type)
                        new_line.done = line.done
                        new_line.active = line.active
                        new_line.percentage = line.percentage

                        local new_machine = Machine.init(line.machine.proto, new_line)
                        new_machine.limit = line.machine.limit
                        new_machine.force_limit = line.machine.force_limit
                        if line.machine.fuel then
                            new_machine.fuel = Fuel.init(line.machine.fuel.proto, new_machine)
                        end
                        new_line.machine = new_machine

                        if line.beacon then
                            local new_beacon = Beacon.init(line.beacon.proto, new_line)
                            new_beacon.amount = line.beacon.amount
                            new_beacon.total_amount = line.beacon.total_amount
                            new_line.beacon = new_beacon
                        end

                        new_line.priority_product = line.priority_product_proto
                        new_line.comment = line.comment

                        new_floor:insert(new_line)
                    end
                end
                return new_floor
            end
            factory.top_floor = convert_floor(subfactory.Floor.datasets[1])

            player_table.district:insert(factory)
        end
    end

    player_table.index = nil
    player_table.mod_version = nil
    player_table.factory = nil
    player_table.archive = nil
end

function migration.packed_subfactory(packed_subfactory)
    -- Most things just carry over as-is here, only the structure changes

    packed_subfactory.products = {}
    for _, product in pairs(packed_subfactory.Product.objects) do
        table.insert(packed_subfactory.products, {
            proto = product.proto,
            defined_by = product.required_amount.defined_by,
            required_amount = product.required_amount.amount,
            belt_proto = product.required_amount.belt_proto,
            class = "Product"
        })
    end

    local function convert_floor(packed_floor)
        local new_floor = {level = packed_floor.level, lines = {}, class = "Floor"}
        for _, line in pairs(packed_floor.Line.objects) do
            if line.subfloor then
                table.insert(new_floor.lines, convert_floor(line.subfloor))
            else
                table.insert(new_floor.lines, {
                    recipe_proto = line.recipe.proto,
                    production_type = line.recipe.production_type,
                    done = line.done,
                    active = line.active,
                    percentage = line.percentage,
                    machine = {
                        proto = line.machine.proto,
                        limit = line.machine.limit,
                        force_limit = line.machine.force_limit,
                        fuel = line.machine.fuel,
                        class = "Machine"
                    },
                    beacon = line.beacon and {
                        proto = line.beacon.proto,
                        amount = line.beacon.amount,
                        total_amount = line.beacon.total_amount,
                        class = "Beacon"
                    },
                    priority_product = line.priority_product_proto,
                    comment = line.comment,
                    class = "Line"
                })
            end
        end
        return new_floor
    end
    packed_subfactory.top_floor = convert_floor(packed_subfactory.top_floor)
end

return migration
