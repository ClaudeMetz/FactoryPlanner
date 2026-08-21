local Object = require("backend.data.Object")
local SimpleItem = require("backend.data.SimpleItem")

---@alias RecipeProductionType "produce" | "consume"
---@alias RecipeCatalysts { products: SimpleItem[], ingredients: SimpleItem[] }

---@class SurfaceCompatibility
---@field recipe boolean
---@field machine boolean
---@field overall boolean

---@class Recipe: Object, ObjectMethods
---@field class "Recipe"
---@field parent Line
---@field proto FPRecipePrototype | FPPackedPrototype
---@field production_type RecipeProductionType
---@field priority_item (FPItemPrototype | FPPackedPrototype)?
---@field temperatures table<string, float>
---@field temperature_data table<string, TemperatureData>
---@field ingredients Ingredient[]
---@field products FormattedProduct[]
---@field catalysts RecipeCatalysts
---@field effects IntegerModuleEffects?
local Recipe = Object.methods()
Recipe.__index = Recipe
script.register_metatable("Recipe", Recipe)

---@param parent Line
---@param proto (FPRecipePrototype | FPPackedPrototype)?
---@param production_type RecipeProductionType?
---@return Recipe
local function init(parent, proto, production_type)
    local this_proto = proto or {
        name = "",
        data_type = "recipes",
        simplified = true
    }
    local object = Object.init({
        proto = this_proto,
        production_type = production_type or "produce",
        priority_item = nil,
        temperatures = {},

        temperature_data = nil,
        ingredients = nil,
        products = nil,
        catalysts = nil,
        effects = nil,

        parent = parent
    }, "Recipe", Recipe)  ---@as Recipe

    if not this_proto.simplified then
        object:build_temperatures_data()
        object:build_items()
    end

    return object
end


function Recipe:index()
    OBJECT_INDEX[self.id] = self
end


function Recipe:build_temperatures_data()
    ---@cast self.proto FPRecipePrototype
    self.temperature_data = {}

    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" then
            -- Going in at the temperature a product of the same fluid comes out at would only
            -- cancel that product out, making the recipe useless, so it isn't offered at all
            local exclusive_maximum = false
            for _, product in pairs(self.proto.products) do
                if product.base_name == ingredient.name and ingredient.amount >= product.amount
                        and product.temperature == ingredient.maximum_temperature then
                    exclusive_maximum = true
                    break
                end
            end

            self.temperature_data[ingredient.name] =
                lib.temperature.generate_data(ingredient, nil, exclusive_maximum)
        end
    end
end

---@param player LuaPlayer
---@param produced FPItemPrototype?
function Recipe:apply_temperature_defaults(player, produced)
    ---@cast self.proto FPRecipePrototype
    self.temperatures = {}

    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" then
            local excluded = nil

            -- If the produced item is the same, temperature included, as this ingredient, it could
            -- end up cancelling out, which makes the recipe useless. Set a different default instead.
            if produced and produced.base_name == ingredient.name then
                for _, product in pairs(self.proto.products) do
                    if product.name == produced.name and ingredient.amount >= product.amount then
                        excluded = produced.temperature
                        break
                    end
                end
            end

            local applicable_values = self.temperature_data[ingredient.name].applicable_values
            self.temperatures[ingredient.name] = lib.temperature.determine_applicable_default(
                player, ingredient, applicable_values, excluded)
        end
    end

    self:build_items()
end

---@param fluid_name string
---@param temperature float?
function Recipe:set_temperature(fluid_name, temperature)
    self.temperatures[fluid_name] = temperature

    local priority_item = self.priority_item  -- priority is specific to one temperature
    if priority_item and (priority_item.base_name or priority_item.name) == fluid_name then
        self.priority_item = nil
    end

    self:build_items()
end


--- Determine net products and ingredients, while breaking out resulting catalysts. This needs
--- to be done dynamically based on user-picked fluid ingredient temperatures.
function Recipe:build_items()
    ---@cast self.proto FPRecipePrototype
    local products = self.proto.products

    ---@type table<ItemType, table<ItemName, number>>
    local indexed_products = {item={}, fluid={}, entity={}}
    local product_amounts = {}  ---@type table<number, number?>

    for index, product in pairs(products) do
        indexed_products[product.type][product.name] = index
        product_amounts[index] = product.amount
    end

    self.ingredients, self.products = {}, {}
    self.catalysts = {products={}, ingredients={}}

    for _, ingredient in pairs(self.proto.ingredients) do
        local peer_index = indexed_products[ingredient.type][self:get_name_with_temperature(ingredient)]
        local peer_product = (peer_index) and products[peer_index] or nil

        if peer_product == nil then
            table.insert(self.ingredients, ingredient)

        elseif ingredient.amount > peer_product.amount then
            -- The product cancels out entirely, leaving the ingredient with the difference
            local proto = prototyper.util.find("items", peer_product.name, peer_product.type)
            local item = SimpleItem.init(self.parent, proto--[[@as FPItemPrototype]], peer_product.amount)
            table.insert(self.catalysts.products, item)

            local remainder = lib.flib.shallow_copy(ingredient)
            remainder.amount = ingredient.amount - peer_product.amount
            table.insert(self.ingredients, remainder)

            product_amounts[peer_index] = nil

        else
            -- The ingredient cancels out entirely, leaving the product with the difference, if any
            local proto = prototyper.util.find("items", ingredient.name, ingredient.type)
            local item = SimpleItem.init(self.parent, proto--[[@as FPItemPrototype]], ingredient.amount)
            table.insert(self.catalysts.ingredients, item)

            local difference = peer_product.amount - ingredient.amount
            product_amounts[peer_index] = (difference > 0) and difference or nil
        end
    end

    for index, product in ipairs(products) do
        local amount = product_amounts[index]
        if amount ~= nil then
            local item = product
            if amount ~= product.amount then
                item = lib.flib.shallow_copy(product)
                item.amount = amount
            end
            table.insert(self.products, item)
        end
    end
end


---@param ingredient Ingredient | FPItemPrototype
---@return boolean
function Recipe:is_temperature_configured(ingredient)
    return (ingredient.type ~= "fluid" or self.temperatures[ingredient.name] ~= nil)
end

---@param ingredient Ingredient | FPItemPrototype
---@return string
function Recipe:get_name_with_temperature(ingredient)
    if ingredient.type ~= "fluid" then return ingredient.name--[[@as string]] end
    return lib.temperature.name_with(ingredient.name, self.temperatures[ingredient.name])
end

---@param ingredient Ingredient | FPItemPrototype
---@param temperature float
---@return boolean success
function Recipe:is_temperature_valid(ingredient, temperature)
    if ingredient.type == "fluid" and self.temperature_data[ingredient.name] then
        -- Check that the temperature to be set is a valid temperature
        for _, value in pairs(self.temperature_data[ingredient.name].applicable_values) do
            if temperature == value then return true end
        end
    end
    return false
end

---@param ingredient Ingredient | FPItemPrototype
---@return float?
function Recipe:get_temperature(ingredient)
    if ingredient.type == "fluid" then
        return self.temperatures[ingredient.name]
    end
    return nil
end


--- Called when the solver runs because it's the most convenient spot for it
---@param force LuaForce
---@param factory Factory
function Recipe:update_effects(force, factory)
    local machine_proto = self.parent.machine.proto

    local name = nil
    local drill = (machine_proto.prototype_category == "mining_drill")
    if drill and machine_proto.uses_force_mining_productivity_bonus then name = "custom-mining"
    elseif self.proto.productivity_recipe ~= nil then name = self.proto.productivity_recipe
    else return end  -- no recipe effects for custom recipes

    self.effects = {productivity = factory:get_productivity_bonus(force, name--[[@cast -nil]])}
    self.parent.machine:summarize_effects()  -- update machine to update its tooltip
end


---@class PackedRecipe: PackedObject
---@field class "Recipe"
---@field proto FPPackedPrototype
---@field production_type RecipeProductionType
---@field priority_item FPPackedPrototype?
---@field temperatures table<string, float>

---@param full boolean
---@return PackedRecipe packed_self
function Recipe:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
        production_type = self.production_type,
        priority_item = (self.priority_item) and
            prototyper.util.simplify_prototype(self.priority_item, "type") or nil,
        temperatures = self.temperatures
    }
end

---@param packed_self PackedRecipe
---@param parent Line
---@return Recipe Recipe
local function unpack(packed_self, parent)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(parent, packed_self.proto, packed_self.production_type)
    unpacked_self.priority_item = packed_self.priority_item

    -- Will be automatically unpacked by the validation process
    unpacked_self.temperatures = packed_self.temperatures

    return unpacked_self
end


---@param player LuaPlayer
---@return boolean valid
function Recipe:validate(player)
    self.proto = prototyper.util.validate_prototype_object(self.proto, nil)  ---@as FPRecipePrototype | FPPackedPrototype
    self.valid = (not self.proto.simplified)

    -- A recipe the force can't obtain at all is not valid, mirroring what the recipe picker offers
    if self.valid then
        local recipe_proto = self.proto  --[[@as FPRecipePrototype]]
        self.valid = lib.is_recipe_available(player.force--[[@as LuaForce]], recipe_proto)
    end

    -- A priority item that doesn't exist anymore is simply dropped, it doesn't invalidate the recipe
    self.priority_item = (self.priority_item) and
        prototyper.util.validate_prototype_object(self.priority_item, "type") or nil
    if self.priority_item and self.priority_item.simplified then self.priority_item = nil end

    -- An invalid temperature shouldn't invalidate the recipe
    if self.valid then  ---@cast self.proto FPRecipePrototype
        local previous_temperatures = self.temperatures
        self.temperatures = {}

        self:build_temperatures_data()

        for _, ingredient in pairs(self.proto.ingredients) do
            if ingredient.type == "fluid" then
                local applicable_values = self.temperature_data[ingredient.name].applicable_values
                local previous_temperature = previous_temperatures[ingredient.name]

                if #applicable_values == 1 then
                    self.temperatures[ingredient.name] = applicable_values[1]
                elseif previous_temperature ~= nil then
                    for _, temperature in pairs(applicable_values) do
                        if temperature == previous_temperature then
                            self.temperatures[ingredient.name] = previous_temperature
                            break
                        end
                    end
                end
            end
        end

        self:build_items()
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Recipe:repair(player)
    -- Neither a missing prototype nor a recipe the force can't obtain can be repaired
    return false
end

return {init = init, unpack = unpack}
