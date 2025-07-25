local generator_util = {}

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

    local probability = (product.probability or 1)
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
        indexed_list[item.type][item.name] = {index = index, item = ftable.shallow_copy(item)}
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
function generator_util.format_recipe(recipe_proto, products, main_product, ingredients)
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
        if base_product.type ~= "research-progress" then
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
                    local item = ftable.shallow_copy(ingredient.item)
                    item.amount = peer_product.item.amount + difference
                    recipe_proto.catalysts.ingredients[item.name] = item

                    ingredients[ingredient.index].amount = nil
                    formatted_products[peer_product.index].amount = -difference
                elseif difference > 0 then
                    local item = ftable.shallow_copy(peer_product.item)
                    item.amount = ingredient.item.amount - difference
                    recipe_proto.catalysts.products[item.name] = item

                    ingredients[ingredient.index].amount = difference
                    formatted_products[peer_product.index].amount = nil
                else
                    -- Nilled-out items are just shown as ingredient catalysts
                    local item = ftable.shallow_copy(ingredient.item)
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


-- Active mods table needed for the funtions below
local active_mods = script.active_mods

-- Determines whether this recipe is a recycling one or not
local recycling_recipe_mods = {
    ["base"] = {".*%-recycling$"},
    --[[ ["IndustrialRevolution"] = {"^scrap%-.*"},
    ["space-exploration"] = {"^se%-recycle%-.*"},
    ["angelspetrochem"] = {"^converter%-.*"},
    ["reverse-factory"] = {"^rf%-.*"},
    ["ZRecycling"] = {"^dry411srev%-.*"} ]]
}

local active_recycling_recipe_mods = {}  ---@type string[]
for modname, patterns in pairs(recycling_recipe_mods) do
    for _, pattern in pairs(patterns) do
        if active_mods[modname] then
            table.insert(active_recycling_recipe_mods, pattern)
        end
    end
end

---@param proto LuaRecipePrototype
---@return boolean
function generator_util.is_recycling_recipe(proto)
    for _, pattern in pairs(active_recycling_recipe_mods) do
        if string.match(proto.name, pattern) and proto.hidden then return true end
    end
    return false
end


-- Determines whether the given recipe is a barreling or stacking one
local compacting_recipe_mods = {
    ["base"] = {patterns = {"^fill%-.*", "^empty%-.*"}, item = "barrel"},
    ["pycoalprocessing"] = {patterns = {"^fill%-.*%-canister$", "^empty%-.*%-canister$"}}
    --[[ ["deadlock-beltboxes-loaders"] = {"^deadlock%-stacks%-.*", "^deadlock%-packrecipe%-.*",
                                      "^deadlock%-unpackrecipe%-.*"},
    ["DeadlockCrating"] = {"^deadlock%-packrecipe%-.*", "^deadlock%-unpackrecipe%-.*"},
    ["IntermodalContainers"] = {"^ic%-load%-.*", "^ic%-unload%-.*"},
    ["space-exploration"] = {"^se%-delivery%-cannon%-pack%-.*"},
    ["Satisfactorio"] = {"^packaged%-.*", "^unpack%-.*"} ]]
}

---@param proto LuaRecipePrototype
---@return boolean
function generator_util.is_compacting_recipe(proto)
    for mod, filter_data in pairs(compacting_recipe_mods) do
        if active_mods[mod] then
            for _, pattern in pairs(filter_data.patterns) do
                if string.match(proto.name, pattern) then
                    if not filter_data.item then
                        return true
                    else
                        for _, product in pairs(proto.products) do
                            if product.name == filter_data.item then return true end
                        end
                        for _, ingredient in pairs(proto.ingredients) do
                            if ingredient.name == filter_data.item then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end


-- Determines whether this recipe is irrelevant or not and should thus be excluded
local irrelevant_recipe_categories = {
    ["Transport_Drones_Meglinge_Fork"] = {"transport-drone-request", "transport-fluid-request"},
    --[[ ["Mining_Drones"] = {"mining-depot"},
    ["Deep_Storage_Unit"] = {"deep-storage-item", "deep-storage-fluid",
                             "deep-storage-item-big", "deep-storage-fluid-big",
                             "deep-storage-item-mk2/3", "deep-storage-fluid-mk2/3"},
    ["Satisfactorio"] = {"craft-bench", "equipment", "awesome-shop",
                             "resource-scanner", "object-scanner", "building",
                             "hub-progressing", "space-elevator", "mam"} ]]
}

local irrelevant_recipe_categories_lookup = {}  ---@type { [string] : true }
for mod, categories in pairs(irrelevant_recipe_categories) do
    for _, category in pairs(categories) do
        if active_mods[mod] then
            irrelevant_recipe_categories_lookup[category] = true
        end
    end
end

---@param recipe LuaRecipePrototype
---@return boolean
function generator_util.is_irrelevant_recipe(recipe)
    return irrelevant_recipe_categories_lookup[recipe.category]
end


-- Determines whether this machine is irrelevant or not and should thus be excluded
local irrelevant_machine_mods = {
    --[[ ["GhostOnWater"] = {"waterGhost%-.*"} ]]
}

local irrelevant_machines_lookup = {}  ---@type string[]
for modname, patterns in pairs(irrelevant_machine_mods) do
    for _, pattern in pairs(patterns) do
        if active_mods[modname] then
            table.insert(irrelevant_machines_lookup, pattern)
        end
    end
end

---@param proto LuaEntityPrototype
---@return boolean
function generator_util.is_irrelevant_machine(proto)
    for _, pattern in pairs(irrelevant_machines_lookup) do
        if string.match(proto.name, pattern) then return true end
    end
    return false
end


-- Finds a sprite for the given entity prototype
---@param proto LuaEntityPrototype
---@return SpritePath | nil
function generator_util.determine_entity_sprite(proto)
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

-- This is wrong now that silos can have two rockets in progress at once
--[[
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
end ]]


---@param proto FPMachinePrototype
function generator_util.check_machine_effects(proto)
    local any_positives = false
    for _, effect in pairs(proto.allowed_effects) do
        if effect == true then any_positives = true; break end
    end

    if proto.module_limit == 0 or not any_positives then
        proto.effect_receiver.uses_module_effects = false
    end
    if proto.module_limit == 0 then
        proto.effect_receiver.uses_beacon_effects = false
    end
end

---@param effects ModuleEffects
---@return ModuleEffects
function generator_util.formatted_effects(effects)
    effects = effects or {}
    if effects["quality"] then  -- fix base game weirdness
        effects["quality"] = effects["quality"] / 10
    end
    return effects
end

--- Needs to be weird because ordering of non-integer keys depends on insertion order
---@param proto FPMachinePrototype
function generator_util.sort_machine_burner_categories(proto)
    if not proto.burner then return end

    local category_list = {}
    for category, _ in pairs(proto.burner.categories) do
        table.insert(category_list, category)
    end
    table.sort(category_list)

    local category_index = {}
    for _, category in ipairs(category_list) do
        category_index[category] = true
    end
    proto.burner.categories = category_index
end


-- Adds the tooltip for the given recipe
---@param recipe FPRecipePrototype
---@return LocalisedString
function generator_util.recipe_tooltip(recipe)
    local tooltip = {"", {"fp.recipe_title", recipe.sprite, recipe.localised_name}}  ---@type LocalisedString
    local current_table, next_index = tooltip, 3

    if recipe.energy ~= nil then
        local energy_line = {"fp.recipe_crafting_time", recipe.energy}
        current_table, next_index = util.build_localised_string(energy_line, current_table, next_index)
    end

    local item_protos = storage.prototypes.items
    for _, item_type in ipairs{"ingredients", "products"} do
        local locale_key = (item_type == "ingredients") and "fp.pu_ingredient" or "fp.pu_product"
        local header_line = {"fp.recipe_header", {locale_key, 2}}
        current_table, next_index = util.build_localised_string(header_line, current_table, next_index)
        if not next(recipe[item_type]) then
            current_table, next_index = util.build_localised_string({"fp.recipe_none"}, current_table, next_index)
        else
            local items = recipe[item_type]
            for _, item in ipairs(items) do
                local proto = item_protos[item.type].members[item.name]
                local item_line = {"fp.recipe_item", proto.sprite, item.amount, proto.localised_name}
                current_table, next_index = util.build_localised_string(item_line, current_table, next_index)
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
function generator_util.generate_group_table(group)
    return {name=group.name, localised_name=group.localised_name, order=group.order, valid=true}
end

---@param proto FPItemPrototype | FPRecipePrototype
function generator_util.add_default_groups(proto)
    proto.group = generator_util.generate_group_table(prototypes.item_group["other"])
    proto.subgroup = generator_util.generate_group_table(prototypes.item_subgroup["other"])
end


---@param text LocalisedString
---@param color Color
---@return LocalisedString
function generator_util.colored_rich_text(text, color)
    return {"", "[color=", color.r, ",", color.g, ",", color.b, "]", text, "[/color]"}
end

return generator_util
