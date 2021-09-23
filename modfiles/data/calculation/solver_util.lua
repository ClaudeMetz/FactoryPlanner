local calculation = calculation -- require "data.calculation.util"
local structures = structures -- require "data.calculation.structures"
local M = {}

local tolerance = MARGIN_OF_ERROR

local function create_item_node(item_proto, amount)
    return {
        name = item_proto.name,
        type = item_proto.type,
        amount_per_machine_by_second = amount,
        neighbor_recipe_lines = {},
    }
end

local function normalize_recipe_line(recipe_line, parent)
    local recipe_proto = recipe_line.recipe_proto
    local machine_proto = recipe_line.machine_proto
    local fuel_proto = recipe_line.fuel_proto
    local total_effects = recipe_line.total_effects
    
    -- Not per tick.
    local crafts_per_second = calculation.util.determine_crafts_per_tick(
        machine_proto, recipe_proto, total_effects
    )
    local energy_consumption_per_machine = calculation.util.determine_energy_consumption(
        machine_proto, 1, total_effects
    )
    local pollution_per_machine = calculation.util.determine_pollution(
        machine_proto, recipe_proto, fuel_proto, total_effects, energy_consumption_per_machine
    )
    local production_ratio_per_machine_by_second = calculation.util.determine_production_ratio(
        crafts_per_second, 1, 1, machine_proto.launch_sequence_time
    )
    local products = {}
    for _, v in pairs(recipe_proto.products) do
        local p_amount = calculation.util.determine_prodded_amount(
            v, crafts_per_second, total_effects
        )
        products[v.name] = create_item_node(v, p_amount * crafts_per_second)
    end
    
    local ingredients = {}
    for _, v in pairs(recipe_proto.ingredients) do
        ingredients[v.name] = create_item_node(v, v.amount * crafts_per_second)
    end
    
    local fuel_consumption_per_machine_by_second = 0
    if fuel_proto then
        fuel_consumption_per_machine_by_second = calculation.util.determine_fuel_amount(
            energy_consumption_per_machine, machine_proto.burner, fuel_proto.fuel_value, 1
        )
        local a = ingredients[fuel_proto.name]
        if a then
            a.amount_per_machine_by_second = a.amount_per_machine_by_second + fuel_consumption_per_machine_by_second
        else
            ingredients[fuel_proto.name] = create_item_node(fuel_proto, fuel_consumption_per_machine_by_second)
        end
    end
    if machine_proto.energy_type == "void" then
        energy_consumption_per_machine = 0
    end

    local maximum_machine_count, minimum_machine_count
    local machine_limit = recipe_line.machine_limit
    if machine_limit then
        maximum_machine_count = machine_limit.limit
        if machine_limit.force_limit then
            minimum_machine_count = machine_limit.limit
        end
    end
    
    return {
        type = "recipe_line",
        parent = parent,
        floor_id = parent.floor_id,
        line_id = recipe_line.id,
        normalized_id = "recipe_line@" .. parent.floor_id .. "." .. recipe_line.id,
        
        products = products,
        ingredients = ingredients,
        fuel_name = fuel_proto and fuel_proto.name,
        
        energy_consumption_per_machine = energy_consumption_per_machine,
        pollution_per_machine = pollution_per_machine,
        production_ratio_per_machine_by_second = production_ratio_per_machine_by_second,
        fuel_consumption_per_machine_by_second = fuel_consumption_per_machine_by_second,

        maximum_machine_count = maximum_machine_count,
        minimum_machine_count = minimum_machine_count,
    }
end

local function normalize_floor(floor, line_id, parent)
    local ret = {
        type = "floor",
        parent = parent,
        floor_id = floor.id,
        line_id = line_id,
        normalized_id = "floor@" .. floor.id,
        lines = {},
    }
    
    for _, v in ipairs(floor.lines) do
        local res
        if v.subfloor then
            res = normalize_floor(v.subfloor, v.id, ret)
        else
            res = normalize_recipe_line(v, ret)
        end
        table.insert(ret.lines, res)
    end
    
    return ret
end

local function link_products_to_ingredients(from, to)
    for _, a in pairs(from.products) do
        for _, b in pairs(to.ingredients) do
            if a.name == b.name then
                table.insert(a.neighbor_recipe_lines, to)
            end
        end
    end
end

local function link_ingredients_to_products(from, to)
    for _, a in pairs(from.ingredients) do
        for _, b in pairs(to.products) do
            if a.name == b.name then
                table.insert(a.neighbor_recipe_lines, to)
            end
        end
    end
end

local function make_prioritized_links(normalized_top_floor)
    for _, from in M.visit_priority_order(normalized_top_floor) do
        for _, to in M.visit_priority_order(from.parent) do
            link_products_to_ingredients(from, to)
            link_ingredients_to_products(from, to)
        end
    end
    return normalized_top_floor
end

function M.normalize(top_floor)
    local ret = normalize_floor(top_floor, nil, nil)
    return make_prioritized_links(ret)
end

function M.normalize_references(references, timescale)
    local ret = {}
    for _, v in ipairs(references) do
        local proto = v.proto
        ret[proto.name] = {
            name = proto.name,
            type = proto.type,
            amount_per_second = v.amount / timescale
        }
    end
    return ret
end

local function feedback_recipe_line(machine_counts, player_index, timescale, normalized_recipe_line)
    local nrl = normalized_recipe_line
    local machine_count = machine_counts[nrl.normalized_id]
    
    local energy_consumption = nrl.energy_consumption_per_machine * machine_count -- todo: energy_consumption when idle
    local pollution = nrl.pollution_per_machine * machine_count -- todo: pollution when idle
    local production_ratio = nrl.production_ratio_per_machine_by_second * machine_count * timescale
    local fuel_amount = nrl.fuel_consumption_per_machine_by_second * machine_count * timescale
    if nrl.fuel_name then
        energy_consumption = 0
    end
    
    local Product = structures.class.init()
    for _, v in pairs(nrl.products) do
        local amount = v.amount_per_machine_by_second * machine_count * timescale
        structures.class.add(Product, v, amount)
    end
    
    local Ingredient = structures.class.init()
    for k, v in pairs(nrl.ingredients) do
        local amount = v.amount_per_machine_by_second * machine_count * timescale
        if k == nrl.fuel_name then
            amount = amount - fuel_amount
        end
        structures.class.add(Ingredient, v, amount)
    end
    
    return {
        player_index = player_index,
        floor_id = nrl.parent.floor_id,
        line_id = nrl.line_id,
        machine_count = machine_count,
        energy_consumption = energy_consumption,
        pollution = pollution,
        production_ratio = production_ratio,
        uncapped_production_ratio = production_ratio, -- todo...?
        Product = Product,
        Byproduct = structures.class.init(),
        Ingredient = Ingredient,
        fuel_amount = fuel_amount
    }
end

local function class_add_all(to_class, from_class)
    for _, item in ipairs(structures.class.to_array(from_class)) do
        structures.class.add(to_class, item)
    end
end

local function class_counterbalance(class_a, class_b)
    for _, item in ipairs(structures.class.to_array(class_b)) do
        local t, n = item.type, item.name
        local depot_amount = class_a[t][n] or 0
        local counterbalance_amount = math.min(depot_amount, item.amount)
        structures.class.subtract(class_a, item, counterbalance_amount)
        if class_a[t][n] and class_a[t][n] <= tolerance then class_a[t][n] = nil end
        structures.class.subtract(class_b, item, counterbalance_amount)
        if class_b[t][n] and class_b[t][n] <= tolerance then class_b[t][n] = nil end
    end
end

local function feedback_floor(machine_counts, player_index, timescale, normalized_floor)
    local machine_count = 0
    local energy_consumption = 0
    local pollution = 0
    local Product = structures.class.init()
    local Byproduct = structures.class.init()
    local Ingredient = structures.class.init()
    
    for _, l in ipairs(normalized_floor.lines) do
        local res
        if l.type == "floor" then
            res = feedback_floor(machine_counts, player_index, timescale, l)
        elseif l.type == "recipe_line" then
            res = feedback_recipe_line(machine_counts, player_index, timescale, l)
        else
            assert()
        end
        calculation.interface.set_line_result(res)
        
        machine_count = machine_count + math.ceil(res.machine_count - tolerance)
        energy_consumption = energy_consumption + res.energy_consumption
        pollution = pollution + res.pollution
        class_add_all(Product, res.Product)
        class_add_all(Byproduct, res.Byproduct)
        class_add_all(Ingredient, res.Ingredient)
    end
    
    class_counterbalance(Ingredient, Product)
    class_counterbalance(Ingredient, Byproduct)
    
    return {
        player_index = player_index,
        floor_id = normalized_floor.parent and normalized_floor.parent.floor_id,
        line_id = normalized_floor.line_id,
        machine_count = machine_count,
        energy_consumption = energy_consumption,
        pollution = pollution,
        Product = Product,
        Byproduct = Byproduct,
        Ingredient = Ingredient,
    }
end

function M.feedback(machine_counts, player_index, timescale, normalized_top_floor)
    local res = feedback_floor(machine_counts, player_index, timescale, normalized_top_floor)
    local ReferencesMet = structures.class.init() -- todo
    calculation.interface.set_subfactory_result{
        player_index = player_index,
        energy_consumption = res.energy_consumption,
        pollution = res.pollution,
        Product = ReferencesMet,
        Byproduct = res.Product,
        Ingredient = res.Ingredient
    }
end

-- No coroutine? Damn it!
--
-- local function icoroutine(func, a1, a2, a3, a4, a5, a6, a7 ,a8, a9)
--     local success
--     return function(co)
--         success, a1, a2, a3, a4, a5, a6, a7 ,a8, a9 = coroutine.resume(co, a1, a2, a3, a4, a5, a6, a7 ,a8, a9)
--         if not success then
--             error(debug.traceback(co, a1), 2)
--         end
--         return a1, a2, a3, a4, a5, a6, a7 ,a8, a9
--     end, coroutine.create(func)
-- end
--
-- local function visit_priority_order(floor, prev_floor)
--     for _, v in ipairs(floor.lines) do
--         if v.type == "floor" then
--             if v ~= prev_floor then
--                 visit_priority_order(v, floor)
--             end
--         elseif v.type == "recipe_line" then
--             coroutine.yield(v)
--         else
--             assert(false)
--         end
--     end
--     local parent = floor.parent
--     if parent and parent ~= prev_floor then
--         visit_priority_order(parent, floor)
--     end
-- end

function M.visit_priority_order(start_floor)
    local floor_stack = {start_floor}
    local index_stack = {1}
    local mode_stack = {"recipe_line"}
    local function it()
        local top = #floor_stack
        if top == 0 then
            return nil
        end
        local floor, prev_floor = floor_stack[top], floor_stack[top - 1]
        local index, mode = index_stack[top], mode_stack[top]
        index_stack[top] = index + 1
        if index <= #floor.lines then
            local v = floor.lines[index]
            if v.type == "floor" and mode == "floor" then
                if v ~= prev_floor then
                    table.insert(floor_stack, v)
                    table.insert(index_stack, 1)
                    table.insert(mode_stack, "recipe_line")
                end
            elseif v.type == "recipe_line" and mode == "recipe_line"  then
                return v.normalized_id, v
            end
        else
            if mode == "recipe_line" then
                mode_stack[top] = "floor"
                index_stack[top] = 1
            elseif mode == "floor" then
                mode_stack[top] = "parent"
                local parent = floor.parent
                if parent and parent ~= prev_floor then
                    table.insert(floor_stack, parent)
                    table.insert(index_stack, 1)
                    table.insert(mode_stack, "recipe_line")
                end
            elseif mode == "parent" then
                table.remove(floor_stack)
                table.remove(index_stack)
                table.remove(mode_stack)
            end
        end
        return it()
    end
    return it
end

function M.iterate_recipe_lines(recipe_lines)
    if recipe_lines.type == "floor" then
        return M.visit_priority_order(recipe_lines)
    else
        return pairs(recipe_lines) -- by flat_recipe_lines.
    end
end

function M.to_flat_recipe_lines(normalized_top_floor)
    local ret = {}
    for k, v in M.visit_priority_order(normalized_top_floor) do
        ret[k] = v
    end
    return ret
end

return M
