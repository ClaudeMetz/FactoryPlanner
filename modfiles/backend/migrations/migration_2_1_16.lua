---@diagnostic disable

local FactoryItem = require("backend.data.FactoryItem")
local migration = {}

local function floor_lines(floor)
    if floor.lines then return floor.lines end
    local lines = {}
    for line in floor:iterator() do lines[#lines + 1] = line end
    return lines
end

local function clear_machine_limits(lines)
    for _, line in ipairs(lines) do
        if line.class == "Floor" then
            clear_machine_limits(floor_lines(line))
        elseif line.machine then
            line.machine.limit = nil
            line.machine.force_limit = nil
        end
    end
end

local function migrate_machine_limits(products, lines)
    local line = lines[1]
    if line and line.class == "Floor" then line = floor_lines(line)[1] end
    local machine = line and line.machine
    local proto = line and line.recipe and prototyper.util.find("recipes", line.recipe.proto.name)

    -- Preserve only an exact count on the first recipe when its sole output is a desired product
    if proto and #proto.products == 1 and machine and machine.force_limit
            and machine.limit and machine.limit > 0 and machine.limit < math.huge then
        local output = proto.products[1]
        for _, product in ipairs(products) do
            if product.proto.name == output.name and (product.proto.type or product.proto.category) == output.type
                    and product.definition.type ~= "machines" then
                product.definition = {type="machines", machine_count=machine.limit}
                break
            end
        end
    end

    clear_machine_limits(lines)
end

local function migrate_definition(item)
    if item.required_amount == nil then return end

    if item.defined_by == "belts" then
        item.definition = {type="belts", belt_count=item.required_amount,
            belt_proto=item.belt_proto, belt_stack=item.belt_stack}
    else
        item.definition = {type="amount", amount=item.required_amount}
    end
    item.defined_by, item.required_amount = nil, nil
    item.belt_proto, item.belt_stack = nil, nil
end

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                local item = product
                if product.class == "TLProduct" then
                    item = FactoryItem.init(product.proto)
                    item.defined_by = product.defined_by
                    item.required_amount = product.required_amount
                    item.belt_proto = product.belt_proto
                    item.belt_stack = product.belt_stack
                    item.amount = product.amount
                    factory:replace(product, item)
                end
                migrate_definition(item)
            end
            migrate_machine_limits(factory:as_list(), floor_lines(factory.top_floor))
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        if product.class == "TLProduct" then
            product.class = "FactoryItem"
        end
        migrate_definition(product)
    end
    migrate_machine_limits(packed_factory.products, packed_factory.top_floor.lines)
end

return migration
