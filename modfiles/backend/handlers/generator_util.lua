local _util = {}

-- ** LOCAL UTIL **
---@alias RecipeItem FormattedProduct | Ingredient
---@alias IndexedItemList { [ItemType]: { [ItemName]: { index: number, item: RecipeItem } } }
---@alias ItemList { [ItemType]: { [ItemName]: RecipeItem } }
---@alias ItemTypeCounts { items: number, fluids: number }

---@class FormattedProduct
---@field name string
---@field type string
---@field amount number
---@field temperature float?
---@field base_name string?
---@field proddable_amount number?

---@param product Product
---@return FormattedProduct
local function generate_formatted_product(product)
    local base_amount, proddable_amount = 0, 0
    local catalyst_amount = product.ignored_by_productivity or 0

    if product.amount_min ~= nil and product.amount_max ~= nil then
        local min, max = product.amount_min, product.amount_max
        base_amount = (min + max) / 2 + (product.extra_count_fraction or 0)

        -- When a recipe has a random output affected by prod and with a catalyst specified,
        -- prod only applies when the output rolls above the catalyst amount
        local cat_min = math.max(min - catalyst_amount, 0)
        local cat_max = math.max(max - catalyst_amount, 0)
        proddable_amount = (cat_min + cat_max) / 2

        -- If the catalyst is at least the minimum amount, the prod part must be multiplied by
        -- the probability that it rolls at least the catalyst amount
        if cat_min == 0 then proddable_amount = proddable_amount * (cat_max + 1) / (max - min + 1) end
    else
        base_amount = product.amount + (product.extra_count_fraction or 0)
        proddable_amount = math.max(base_amount - catalyst_amount, 0)
    end

    -- These need defaults for products that are manually defined by FP
    local shared_probability = product.shared_probability or {min = 0, max = 1}
    local independent_probability = product.independent_probability or 1
    local probability = independent_probability * (shared_probability.max - shared_probability.min)

    local formatted_product = {
        name = product.name,
        type = product.type,
        amount = base_amount * probability,
        proddable_amount = proddable_amount * probability
    }

    if product.type == "fluid" then
        local fluid = prototypes.fluid[product.name]
        formatted_product.temperature = product.temperature or fluid.default_temperature
        formatted_product.name = product.name .. "-" .. formatted_product.temperature
        formatted_product.base_name = product.name
    end

    return formatted_product
end

-- Combines items that occur more than once into one entry
---@param item_list RecipeItem[]
local function combine_identical_products(item_list)
    local touched_items = {item = {}, fluid = {}, entity = {}}  ---@type ItemList

    for index=#item_list, 1, -1 do
        local item = item_list[index]
        local touched_item = touched_items[item.type][item.name]
        if touched_item ~= nil then
            touched_item.amount = touched_item.amount + item.amount
            if touched_item.proddable_amount then
                touched_item.proddable_amount = touched_item.proddable_amount + item.proddable_amount
            end

            -- Using the table.remove function to preserve array formatting
            table.remove(item_list, index)
        else
            touched_items[item.type][item.name] = item
        end
    end
end

---@param item_list RecipeItem[]
---@return IndexedItemList
local function create_type_indexed_list(item_list)
    local indexed_list = {item = {}, fluid = {}, entity = {}}  ---@type IndexedItemList

    for index, item in pairs(item_list) do
        indexed_list[item.type][item.name] = {index = index, item = lib.flib.shallow_copy(item)}
    end

    return indexed_list
end

---@param indexed_items IndexedItemList
---@return ItemTypeCounts
local function determine_item_type_counts(indexed_items)
    return {
        items = table_size(indexed_items.item),
        fluids = table_size(indexed_items.fluid)
    }
end


-- ** TOP LEVEL **
-- Formats the products/ingredients of a recipe for more convenient use
---@param recipe_proto FPRecipePrototype
---@param products Product[]
---@param main_product Product?
---@param ingredients Ingredient[]
function _util.format_recipe(recipe_proto, products, main_product, ingredients)
    local temperature_limit = 3.4e+38

    for _, base_ingredient in pairs(ingredients) do
        if base_ingredient.type == "fluid" then
            local min_temp = base_ingredient.minimum_temperature or base_ingredient.temperature
            local max_temp = base_ingredient.maximum_temperature or base_ingredient.temperature
            base_ingredient.temperature = nil  -- remove as to not confuse it with a product

            -- Adjust temperature ranges for easy handling - nil means unlimited
            min_temp = (min_temp and min_temp > -temperature_limit) and min_temp or nil
            max_temp = (max_temp and max_temp < temperature_limit) and max_temp or nil

            base_ingredient.minimum_temperature = min_temp
            base_ingredient.maximum_temperature = max_temp
        end
    end

    local indexed_ingredients = create_type_indexed_list(ingredients)
    recipe_proto.type_counts.ingredients = determine_item_type_counts(indexed_ingredients)


    local formatted_products = {}  ---@type FormattedProduct[]
    for _, base_product in pairs(products) do
        local formatted_product = generate_formatted_product(base_product)

        if formatted_product.amount > 0 then
            table.insert(formatted_products, formatted_product)

            -- Update the main product as well, if present
            if main_product ~= nil
                    and formatted_product.type == main_product.type
                    and formatted_product.name == main_product.name then
                recipe_proto.main_product = formatted_product
            end
        end
    end

    combine_identical_products(formatted_products)
    local indexed_products = create_type_indexed_list(formatted_products)
    recipe_proto.type_counts.products = determine_item_type_counts(indexed_products)


    -- Reduce item amounts for items that are both an ingredient and a product
    for _, items_of_type in pairs(indexed_ingredients) do
        for _, ingredient in pairs(items_of_type) do
            local peer_product = indexed_products[ingredient.item.type][ingredient.item.name]

            if peer_product then
                local difference = ingredient.item.amount - peer_product.item.amount

                if difference < 0 then
                    local item = lib.flib.shallow_copy(ingredient.item)
                    item.amount = peer_product.item.amount + difference
                    recipe_proto.catalysts.ingredients[item.name] = item

                    ingredients[ingredient.index].amount = nil
                    formatted_products[peer_product.index].amount = -difference
                elseif difference > 0 then
                    local item = lib.flib.shallow_copy(peer_product.item)
                    item.amount = ingredient.item.amount - difference
                    recipe_proto.catalysts.products[item.name] = item

                    ingredients[ingredient.index].amount = difference
                    formatted_products[peer_product.index].amount = nil
                else
                    -- Nilled-out items are just shown as ingredient catalysts
                    local item = lib.flib.shallow_copy(ingredient.item)
                    recipe_proto.catalysts.ingredients[item.name] = item

                    ingredients[ingredient.index].amount = nil
                    formatted_products[peer_product.index].amount = nil
                end
            end
        end
    end

    -- Remove items after the fact so the iteration above doesn't break
    for _, item_table in pairs{ingredients, formatted_products} do
        for i = #item_table, 1, -1 do
            if item_table[i].amount == nil then table.remove(item_table, i) end
        end
    end

    recipe_proto.ingredients = ingredients
    recipe_proto.products = formatted_products
end


---@param normal_quality_value number
---@return number base_value
function _util.get_base_value(normal_quality_value)
    if normal_quality_value == nil then return nil end
    return normal_quality_value / prototypes.quality["normal"].default_multiplier
end

-- Finds a sprite for the given entity prototype
---@param proto LuaEntityPrototype
---@return SpritePath | nil
function _util.determine_entity_sprite(proto)
    local entity_sprite = "entity/" .. proto.name  ---@type SpritePath
    if helpers.is_valid_sprite_path(entity_sprite) then
        return entity_sprite
    end

    local items_to_place_this = proto.items_to_place_this
    if items_to_place_this and next(items_to_place_this) then
        local item_sprite = "item/" .. items_to_place_this[1].name  ---@type SpritePath
        if helpers.is_valid_sprite_path(item_sprite) then
            return item_sprite
        end
    end

    return nil
end


-- Determines the tick count and energy consumption of launching a rocket for the given silo
-- This does not take into account the full launch cycle, but instead calculates the fastest
-- possible one, using the quick follow-up rocket mechanic, as that's the limiting case.
-- The tick results are seemingly off by a handful of ticks, but it's close enough.
-- Power consumption results might be low by 10% or so from light empirical testing.
---@param silo_proto LuaEntityPrototype
---@return number launch_time
---@return number energy_usage
function _util.determine_launch_data(silo_proto)
    local power = silo_proto.active_energy_usage
    local rocket_proto = silo_proto.rocket_entity_prototype

    -- These values are not accessible in the API
    local frame_count, inverse_speed = 32, 1 / 0.3
    local arm_move_offset = rocket_proto.rising_speed * frame_count * inverse_speed
    local rocket_flight_threshold = 0.1  -- hardcoded in the game files

    -- Cycle starts here
    local launch_ticks, energy_usage = 0, 0

    local doors_opened = 1
    launch_ticks = launch_ticks + doors_opened

    local rocket_rising_threshold = 1 - silo_proto.rocket_quick_relaunch_start_offset - arm_move_offset
    local rocket_rising = rocket_rising_threshold / rocket_proto.rising_speed
    launch_ticks = launch_ticks + rocket_rising
    energy_usage = energy_usage + (rocket_rising * power)

    local arms_advance = arm_move_offset / rocket_proto.rising_speed
    launch_ticks = launch_ticks + arms_advance
    energy_usage = energy_usage + (arms_advance * power)

    local launch_starting = 1
    launch_ticks = launch_ticks + launch_starting

    local launch_started = silo_proto.launch_wait_time
    launch_ticks = launch_ticks + launch_started

    local engine_starting = 1 / rocket_proto.engine_starting_speed
    launch_ticks = launch_ticks + engine_starting
    energy_usage = energy_usage + (engine_starting * power)

    local arms_retract = arm_move_offset / rocket_proto.rising_speed
    launch_ticks = launch_ticks + arms_retract
    energy_usage = energy_usage + (arms_retract * power)

    -- I'm not exactly sure why this behaves as the game code does, *but it do*
    local rocket_flying = math.log(1 + rocket_flight_threshold * rocket_proto.flying_acceleration
        / rocket_proto.flying_speed) / math.log(1 + rocket_proto.flying_acceleration)
    launch_ticks = launch_ticks + rocket_flying - arms_retract

    return (launch_ticks / 60), (energy_usage / launch_ticks)
end


---@param effects ModuleEffects?
---@return IntegerModuleEffects
function _util.formatted_effects(effects)
    if effects == nil then return {} end

    -- This turns effects into an integer, multiplying by effect_precision for 0.01% precision
    -- The values need to then be divided by effect_precision and floored for calculation
    for name, value in pairs(effects) do
        -- The API provides effects as values with only two decimals already
        effects[name] = value * MAGIC_NUMBERS.effect_precision
    end

    return effects
end

---@param proto LuaEntityPrototype
---@return boolean
function _util.is_any_effect_viable(proto)
    local allowed_categories = proto.allowed_module_categories
    if allowed_categories ~= nil and table_size(allowed_categories) == 0 then
        return false
    end

    local allowed_effects = proto.allowed_effects
    if allowed_effects == nil then return false end

    for _, effect in pairs(allowed_effects or {}) do
        if effect == true then return true end
    end

    return false
end

---@class FormattedEffectReceiver
---@field base_effect ModuleEffects
---@field uses_module_effects boolean
---@field uses_beacon_effects boolean
---@field uses_surface_effects boolean
---@field limits { [ModuleEffectName]: EffectValueRange }

---@param proto LuaEntityPrototype
---@return FormattedEffectReceiver effect_receiver
function _util.format_effect_receiver(proto)
    local effect_receiver = proto.effect_receiver
    if effect_receiver == nil then
        effect_receiver = {
            base_effect = {},
            uses_module_effects = false,
            uses_beacon_effects = false,
            uses_surface_effects = false,
            consumption_limits = {low = -0.8, high = 1000},
            speed_limits = {low = -0.8, high = 1000},
            productivity_limits = {low = -0.8, high = 1000},
            pollution_limits = {low = -0.8, high = 1000},
            quality_limits = {low = 0, high = 1000}
        }
    else
        local base_effect = effect_receiver.base_effect  -- can be nil
        effect_receiver.base_effect = _util.formatted_effects(base_effect)
    end

    local module_limit = proto.module_inventory_size
    if module_limit == nil or module_limit == 0 then
        effect_receiver.uses_module_effects = false
        -- Beacons can still be used even if the machine can't have modules
    end

    if not _util.is_any_effect_viable(proto) then
        effect_receiver.uses_module_effects = false
        effect_receiver.uses_beacon_effects = false
    end

    -- Adjust limits format to be more convenient
    effect_receiver.limits = {}
    for name, _ in pairs(lib.effects.blank) do
        effect_receiver.limits[name] = effect_receiver[name .. "_limits"]
        effect_receiver[name .. "_limits"] = nil
    end

    return effect_receiver
end


---@param proto LuaEntityPrototype
---@return string? category
---@return LuaFluidBoxPrototype? input
---@return LuaFluidBoxPrototype? output
function _util.get_boiler_data(proto)
    local input, output = nil, nil  -- need to find these manually
    for _, fluid_box in pairs(proto.fluidbox_prototypes) do
        if fluid_box.production_type == "input-output" or fluid_box.production_type == "input" then
            input = fluid_box
        elseif fluid_box.production_type == "output" then
            output = fluid_box
        end
    end

    if input == nil then return nil, nil, nil end

    local category = "boiler"
    if proto.boiler_mode == "output-to-separate-pipe" then
        category = category .. "-target-" .. proto.target_temperature
    end
    if output.filter ~= nil then
        category = category .. "-output-" .. output.filter.name
    end
    if input.filter ~= nil then
        category = category .. "-filter-" .. input.filter.name
    end

    return category, input, output
end


---@param proto FPRecipePrototype | MachineBurner
---@param combined_list { string: string[] }
---@param used_categories { string: [FPMachinePrototype | FPFuelPrototype] }
function _util.format_category_data(proto, combined_list, used_categories)
    local list = {}

    for category, _ in pairs(proto.categories) do
        if used_categories[category] then
            table.insert(list, category)
        else  -- remove categories that don't have any valid uses
            proto.categories[category] = nil
        end
    end

    table.sort(list)  -- canonicalize the category order
    proto.combined_category = table.concat(list, "|")

    combined_list[proto.combined_category] = list
end

---@param combined_list { string: string[] }
---@param used_categories { string: [FPMachinePrototype | FPFuelPrototype] }
---@param final_list NamedPrototypesWithCategory<FPMachinePrototype | FPFuelPrototype>
---@param insert_function function
function _util.fill_categories(combined_list, used_categories, final_list, insert_function)
    for combined_category, list in pairs(combined_list) do
        for _, category in pairs(list) do
            for _, proto in pairs(used_categories[category]) do
                local copy = lib.flib.deep_copy(proto)
                copy.combined_category = combined_category
                insert_function(final_list, copy, combined_category)
            end
        end
    end
end


-- Adds the tooltip for the given recipe
---@param recipe FPRecipePrototype
---@return LocalisedString
function _util.recipe_tooltip(recipe)
    local tooltip = {"", {"fp.recipe_title", recipe.sprite, recipe.localised_name}}  ---@type LocalisedString
    local current_table, next_index = tooltip, 3

    if recipe.energy ~= nil then
        local energy_line = {"fp.recipe_crafting_time", recipe.energy}
        current_table, next_index = lib.build_localised_string(energy_line, current_table, next_index)
    end

    local item_protos = storage.prototypes.items
    for _, item_type in ipairs{"ingredients", "products"} do
        local locale_key = (item_type == "ingredients") and "fp.pu_ingredient" or "fp.pu_product"
        local header_line = {"fp.recipe_header", {locale_key, 2}}
        current_table, next_index = lib.build_localised_string(header_line, current_table, next_index)
        if not next(recipe[item_type]) then
            current_table, next_index = lib.build_localised_string({"fp.recipe_none"}, current_table, next_index)
        else
            local items = recipe[item_type]
            for _, item in ipairs(items) do
                local proto = item_protos[item.type].members[item.name]
                local item_line = {"fp.recipe_item", proto.sprite, item.amount, proto.localised_name}
                current_table, next_index = lib.build_localised_string(item_line, current_table, next_index)
            end
        end
    end

    return tooltip
end

---@class ItemGroup
---@field name string
---@field localised_name LocalisedString
---@field order string
---@field valid boolean

-- Generates a table imitating LuaGroup to avoid lua-cpp bridging
---@param group LuaGroup
---@return ItemGroup group_table
function _util.generate_group_table(group)
    return {name=group.name, localised_name=group.localised_name, order=group.order, valid=true}
end

---@param proto FPItemPrototype | FPRecipePrototype
function _util.add_default_groups(proto)
    proto.group = _util.generate_group_table(prototypes.item_group["other"])
    proto.subgroup = _util.generate_group_table(prototypes.item_subgroup["other"])
end


---@param text LocalisedString
---@param color Color
---@return LocalisedString
function _util.colored_rich_text(text, color)
    return {"", "[color=", color.r, ",", color.g, ",", color.b, "]", text, "[/color]"}
end

return _util
