local generator_util = {}

-- ** LOCAL UTIL **
-- Determines the actual amount of items that a recipe product or ingredient equates to
local function generate_formatted_item(base_item, type)
    local base_amount = 0
    if base_item.amount_max ~= nil and base_item.amount_min ~= nil then
        base_amount = (base_item.amount_max + base_item.amount_min) / 2
    else
        base_amount = base_item.amount
    end

    local probability, proddable_amount = (base_item.probability or 1), nil
    if type == "product" then
        proddable_amount = (base_amount - (base_item.catalyst_amount or 0)) * probability
    end

    -- This will probably screw up the main_product detection down the line
    if base_item.temperature ~= nil then
        base_item.name = base_item.name .. "-" .. base_item.temperature
    end

    return {
        name = base_item.name,
        type = base_item.type,
        amount = (base_amount * probability),
        proddable_amount = proddable_amount,
        temperature = base_item.temperature
    }
end

-- Combines items that occur more than once into one entry
local function combine_identical_products(item_list)
    local touched_items = {item = {}, fluid = {}, entity = {}}

    for index=#item_list, 1, -1 do
        local item = item_list[index]
        if item.temperature == nil then  -- don't care to deal with temperature crap
            local touched_item = touched_items[item.type][item.name]
            if touched_item ~= nil then
                touched_item.amount = touched_item.amount + item.amount
                if touched_item.proddable_amount then
                    touched_item.proddable_amount = touched_item.proddable_amount + item.proddable_amount
                end

                -- Using the table.remove function to preserve array-format
                table.remove(item_list, index)
            else
                touched_items[item.type][item.name] = item
            end
        end
    end
end

-- Converts the given list to a list[type][name]-format
local function create_type_indexed_list(item_list)
    local indexed_list = {item = {}, fluid = {}, entity = {}}

    for index, item in pairs(item_list) do
        indexed_list[item.type][item.name] = {index = index, item = fancytable.shallow_copy(item)}
    end

    return indexed_list
end

-- Determines the type_count for the given recipe prototype
local function determine_item_type_counts(indexed_items)
    return {
        items = table_size(indexed_items.item),
        fluids = table_size(indexed_items.fluid)
    }
end


-- ** TOP LEVEL **
-- Formats the products/ingredients of a recipe for more convenient use
function generator_util.format_recipe_products_and_ingredients(recipe_proto)
    local ingredients = {}
    for _, base_ingredient in pairs(recipe_proto.ingredients) do
        local formatted_ingredient = generate_formatted_item(base_ingredient, "ingredient")

        if formatted_ingredient.amount > 0 then
            -- Productivity applies to all ingredients by default, some exceptions apply (ex. satellite)
            -- Also add proddable_amount so productivity bonus can be un-applied later in the model
            if base_ingredient.ignore_productivity then
                formatted_ingredient.ignore_productivity = true
                formatted_ingredient.proddable_amount = formatted_ingredient.amount
            end

            table.insert(ingredients, formatted_ingredient)
        end
    end

    local indexed_ingredients = create_type_indexed_list(ingredients)
    recipe_proto.type_counts.ingredients = determine_item_type_counts(indexed_ingredients)


    local products = {}
    for _, base_product in pairs(recipe_proto.products) do
        local formatted_product = generate_formatted_item(base_product, "product")

        if formatted_product.amount > 0 then
            table.insert(products, formatted_product)

            -- Update the main product as well, if present
            if recipe_proto.main_product ~= nil
                    and formatted_product.type == recipe_proto.main_product.type
                    and formatted_product.name == recipe_proto.main_product.name then
                recipe_proto.main_product = formatted_product
            end
        end
    end

    combine_identical_products(products)  -- only needed products, ingredients can't have duplicates
    local indexed_products = create_type_indexed_list(products)
    recipe_proto.type_counts.products = determine_item_type_counts(indexed_products)


    -- Reduce item amounts for items that are both an ingredient and a product
    for _, items_of_type in pairs(indexed_ingredients) do
        for _, ingredient in pairs(items_of_type) do
            local peer_product = indexed_products[ingredient.item.type][ingredient.item.name]

            if peer_product then
                local difference = ingredient.item.amount - peer_product.item.amount

                if difference < 0 then
                    ingredients[ingredient.index].amount = nil
                    products[peer_product.index].amount = -difference
                elseif difference > 0 then
                    ingredients[ingredient.index].amount = difference
                    products[peer_product.index].amount = nil
                else
                    ingredients[ingredient.index].amount = nil
                    products[peer_product.index].amount = nil
                end
            end
        end
    end

    -- Remove items after the fact so the iteration above doesn't break
    for _, item_table in pairs{ingredients, products} do
        for i = #item_table, 1, -1 do
            if item_table[i].amount == nil then table.remove(item_table, i) end
        end
    end

    recipe_proto.ingredients = ingredients
    recipe_proto.products = products
end


-- Multiplies recipe products and ingredients by the given amount
function generator_util.multiply_recipe(recipe_proto, factor)
    local function multiply_items(item_list)
        for _, item in pairs(item_list) do
            item.amount = item.amount * factor
            if item.proddable_amount ~= nil then
                item.proddable_amount = item.proddable_amount * factor
            end
        end
    end

    multiply_items(recipe_proto.products)
    multiply_items(recipe_proto.ingredients)
    recipe_proto.energy = recipe_proto.energy * factor
end

-- Adds the additional proto's ingredients, products and energy to the main proto
function generator_util.combine_recipes(main_proto, additional_proto)
    local function add_items_to_main_proto(item_category)
        for _, item in pairs(additional_proto[item_category]) do
            table.insert(main_proto[item_category], item)
        end
        combine_identical_products(main_proto[item_category])
    end

    add_items_to_main_proto("products")
    add_items_to_main_proto("ingredients")
    main_proto.energy = main_proto.energy + additional_proto.energy
end


-- Active mods table needed for the funtions below
local active_mods = script.active_mods

-- Determines whether this recipe is a recycling one or not
local recycling_recipe_mods = {
    ["IndustrialRevolution"] = {"^scrap%-.*"},
    ["space-exploration"] = {"^se%-recycle%-.*"},
    ["angelspetrochem"] = {"^converter%-.*"},
    ["reverse-factory"] = {"^rf%-.*"},
    ["ZRecycling"] = {"^dry411srev%-.*"}
}

local active_recycling_recipe_mods = {}
for modname, patterns in pairs(recycling_recipe_mods) do
    for _, pattern in pairs(patterns) do
        if active_mods[modname] then
            table.insert(active_recycling_recipe_mods, pattern)
        end
    end
end

function generator_util.is_recycling_recipe(proto)
    for _, pattern in pairs(active_recycling_recipe_mods) do
        if string.match(proto.name, pattern) then return true end
    end
    return false
end


-- Determines whether the given recipe is a barreling or stacking one
local compacting_recipe_mods = {
    ["base"] = {"^fill%-.*", "^empty%-.*"},
    ["deadlock-beltboxes-loaders"] = {"^deadlock%-stacks%-.*", "^deadlock%-packrecipe%-.*",
                                      "^deadlock%-unpackrecipe%-.*"},
    ["DeadlockCrating"] = {"^deadlock%-packrecipe%-.*", "^deadlock%-unpackrecipe%-.*"},
    ["IntermodalContainers"] = {"^ic%-load%-.*", "^ic%-unload%-.*"},
    ["space-exploration"] = {"^se%-delivery%-cannon%-pack%-.*"},
    ["Satisfactorio"] = {"^packaged%-.*", "^unpack%-.*"}
}

local active_compacting_recipe_mods = {}
for modname, patterns in pairs(compacting_recipe_mods) do
    for _, pattern in pairs(patterns) do
        if active_mods[modname] then
            table.insert(active_compacting_recipe_mods, pattern)
        end
    end
end

function generator_util.is_compacting_recipe(proto)
    for _, pattern in pairs(active_compacting_recipe_mods) do
        if string.match(proto.name, pattern) then return true end
    end
    return false
end


-- Determines whether this recipe is irrelevant or not and should thus be excluded
local irrelevant_recipe_categories = {
    ["Transport_Drones"] = {"transport-drone-request", "transport-fluid-request"},
    ["Mining_Drones"] = {"mining-depot"},
    ["Deep_Storage_Unit"] = {"deep-storage-item", "deep-storage-fluid",
                             "deep-storage-item-big", "deep-storage-fluid-big",
                             "deep-storage-item-mk2/3", "deep-storage-fluid-mk2/3"},
    ["Satisfactorio"] = {"craft-bench", "equipment", "awesome-shop",
                             "resource-scanner", "object-scanner", "building",
                             "hub-progressing", "space-elevator", "mam"}
}

local irrelevant_recipe_categories_lookup = {}
for mod, categories in pairs(irrelevant_recipe_categories) do
    for _, category in pairs(categories) do
        if active_mods[mod] then
            irrelevant_recipe_categories_lookup[category] = true
        end
    end
end

function generator_util.is_irrelevant_recipe(recipe)
    return irrelevant_recipe_categories_lookup[recipe.category]
end


-- Determines whether this machine is irrelevant or not and should thus be excluded
local irrelevant_machine_mods = {
    ["GhostOnWater"] = {"waterGhost%-.*"}
}

local irrelevant_machines_lookup = {}
for modname, patterns in pairs(irrelevant_machine_mods) do
    for _, pattern in pairs(patterns) do
        if active_mods[modname] then
            table.insert(irrelevant_machines_lookup, pattern)
        end
    end
end

function generator_util.is_irrelevant_machine(proto)
    for _, pattern in pairs(irrelevant_machines_lookup) do
        if string.match(proto.name, pattern) then return true end
    end
    return false
end


-- Finds a sprite for the given entity prototype
function generator_util.determine_entity_sprite(proto)
    local entity_sprite = "entity/" .. proto.name
    if game.is_valid_sprite_path(entity_sprite) then
        return entity_sprite
    end

    local items_to_place_this = proto.items_to_place_this
    if items_to_place_this and next(items_to_place_this) then
        local item_sprite = "item/" .. items_to_place_this[1].name
        if game.is_valid_sprite_path(item_sprite) then
            return item_sprite
        end
    end

    return nil
end

-- Determines how long a rocket takes to launch for the given rocket silo prototype
-- These stages mirror the in-game progression and timing exactly. Most steps take an additional tick (+1)
-- due to how the game code is written. If one stage is completed, you can only progress to the next one
-- in the next tick. No stages can be skipped, meaning a minimal sequence time is around 10 ticks long.
---@param silo_proto LuaEntityPrototype
---@return number? launch_sequence_time
function generator_util.determine_launch_sequence_time(silo_proto)
    local rocket_proto = silo_proto.rocket_entity_prototype
    if not rocket_proto then return nil end  -- meaning this isn't a rocket silo proto

    local rocket_flight_threshold = 0.5  -- hardcoded in the game files
    local launch_steps = {
        lights_blinking_open = (1 / silo_proto.light_blinking_speed) + 1,
        doors_opening = (1 / silo_proto.door_opening_speed) + 1,
        doors_opened = silo_proto.rocket_rising_delay + 1,
        rocket_rising = (1 / rocket_proto.rising_speed) + 1,
        rocket_ready = 14,  -- estimate for satellite insertion delay
        launch_started = silo_proto.launch_wait_time + 1,
        engine_starting = (1 / rocket_proto.engine_starting_speed) + 1,
        -- This calculates a fractional amount of ticks. Also, math.log(x) calculates the natural logarithm
        rocket_flying = math.log(1 + rocket_flight_threshold * rocket_proto.flying_acceleration
            / rocket_proto.flying_speed) / math.log(1 + rocket_proto.flying_acceleration),
        lights_blinking_close = (1 / silo_proto.light_blinking_speed) + 1,
        doors_closing = (1 / silo_proto.door_opening_speed) + 1
    }

    local total_ticks = 0
    for _, ticks_taken in pairs(launch_steps) do
        total_ticks = total_ticks + ticks_taken
    end

    return (total_ticks / 60)  -- retured value is in seconds
end

---@alias AllowedEffects { [string]: boolean }?

-- Returns nil if no effect is true, returns the effects otherwise
---@param allowed_effects AllowedEffects
---@return AllowedEffects? allowed_effects
function generator_util.format_allowed_effects(allowed_effects)
    if allowed_effects == nil then return nil end
    for _, allowed in pairs(allowed_effects) do
        if allowed == true then return allowed_effects end
    end
    return nil  -- all effects are false
end


-- Returns the appropriate prototype name for the given item, incorporating temperature
function generator_util.format_temperature_name(item, name)
    -- Optionally two dashes to account for negative temperatures
    return (item.temperature) and string.gsub(name, "%-+[0-9]+$", "") or name
end

-- Returns the appropriate localised string for the given item, incorporating temperature
function generator_util.format_temperature_localised_name(item, proto)
    if item.temperature then
        return {"", proto.localised_name, " (", item.temperature, " ", {"fp.unit_celsius"}, ")"}
    else
        return proto.localised_name
    end
end


-- Adds the tooltip for the given recipe
---@param recipe FPRecipePrototype
function generator_util.add_recipe_tooltip(recipe)
    local tooltip = {"", {"fp.tt_title", recipe.localised_name}}
    local current_table, next_index = tooltip, 3

    if recipe.energy ~= nil then
        current_table, next_index = data_util.build_localised_string(
            {"", "\n  ", {"fp.crafting_time"}, ": ", recipe.energy}, current_table, next_index)
    end

    for _, item_type in ipairs{"ingredients", "products"} do
        local locale_key = (item_type == "ingredients") and "fp.pu_ingredient" or "fp.pu_product"
        current_table, next_index = data_util.build_localised_string(
            {"", "\n  ", {locale_key, 2}, ":"}, current_table, next_index)
        if not next(recipe[item_type]) then
            current_table, next_index = data_util.build_localised_string({
                "\n    ", {"fp.none"}}, current_table, next_index)
        else
            for _, item in ipairs(recipe[item_type]) do
                local name = generator_util.format_temperature_name(item, item.name)
                local proto = game[item.type .. "_prototypes"][name]
                local localised_name = generator_util.format_temperature_localised_name(item, proto)
                current_table, next_index = data_util.build_localised_string({("\n    " .. "[" .. item.type .. "="
                    .. name .. "] " .. item.amount .. "x "), localised_name}, current_table, next_index)
            end
        end
    end

    recipe.tooltip = tooltip
end

---@class ItemGroup
---@field name string
---@field localised_name LocalisedString
---@field order string
---@field valid boolean

-- Generates a table imitating LuaGroup to avoid lua-cpp bridging
---@param group LuaGroup
---@return ItemGroup group_table
function generator_util.generate_group_table(group)
    return {name=group.name, localised_name=group.localised_name, order=group.order, valid=true}
end

return generator_util
