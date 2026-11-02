---@diagnostic disable

local fixtures = require("fixtures")
local fixture = fixtures.target_item
local target_definition = fixtures.definition

local tests = {}

-- Definitions and categories
local function arrange(context)
    local player, factory, product = fixture(context)
    local FactoryItem = context.classes.FactoryItem
    local function add(name, category)
        local item = FactoryItem.init(prototyper.util.find("items", name, "item"), category)
        factory:insert(item)
        return item
    end
    local ingredient = add("iron-ore", "ingredient")
    local second_product = add("copper-plate", "product")
    local second_ingredient = add("copper-ore", "ingredient")
    ingredient.definition = {type="machines", machine_count=2.5}
    second_ingredient.definition = {type="belts", belt_count=2, belt_stack=1,
        belt_proto=prototyper.util.find("belts", "transport-belt")}
    second_product.active = false
    return player, factory, product, ingredient, second_product, second_ingredient
end

tests.testFactoryItemCategories = {check=function(context)
    local player, factory, product, ingredient, second_product, second_ingredient = arrange(context)
    assert(product.category == "product")
    assert(factory:count() == 4, "Factory must contain all four targets")
    assert(factory:count({category="ingredient"}) == 2, "Ingredient filtering must count only the two ingredients")
    assert(factory:find({proto=ingredient.proto}) == ingredient)
    assert(factory:find({proto=ingredient.proto, category="product"}) == nil)
    factory:shift(second_product, "previous", 1)
    factory:shift(ingredient, "next", 1)
    local products = factory:as_list({category="product"})
    local ingredients = factory:as_list({category="ingredient"})
    assert(products[1] == second_product, "Shifting must move the second product ahead of the first")
    assert(products[2] == product, "The original product must follow the shifted product")
    assert(ingredients[1] == second_ingredient, "Shifting must move the second ingredient ahead of the first")
    assert(ingredients[2] == ingredient, "The original ingredient must follow the shifted ingredient")
    assert(factory:find({category="ingredient"}, product.next, "next") == second_ingredient)
    assert(factory:find({category="product"}, ingredient.previous, "previous") == product)
end}

tests.testFactoryCategoryRoundTrip = {check=function(context)
    local player, factory, product, ingredient, second_product, second_ingredient = arrange(context)
    factory:shift(second_product, "previous", 1)
    factory:shift(ingredient, "next", 1)
    local packed = factory:pack(false)
    assert(packed.products == nil, "Current-format packing must not emit the legacy products field")
    assert(#packed.items == 4, "Packing must preserve all four targets")
    local restored = context.classes.Factory.unpack(packed)
    assert(restored:validate(player), "The unpacked object must validate")
    assert(restored:count({category="product"}) == 2, "Unpacking must preserve both products")
    assert(restored:count({category="ingredient"}) == 2, "Unpacking must preserve both ingredients")
    local restored_products = restored:as_list({category="product"})
    local restored_ingredients = restored:as_list({category="ingredient"})
    assert(restored_products[1].proto == second_product.proto, "Unpacking must preserve product order")
    assert(not restored_products[1].active, "Unpacking must preserve the disabled product")
    assert(restored_ingredients[1].proto == second_ingredient.proto, "Unpacking must preserve ingredient order")
    assert(restored_ingredients[1]:get_defined_amount() == second_ingredient:get_defined_amount(), "Unpacking must preserve the belt-defined ingredient amount")
    assert(restored_ingredients[2].definition.machine_count == 2.5, "Unpacking must preserve the machine-defined ingredient count")
    local clone = factory:clone(player)
    assert(clone:find({proto=ingredient.proto}).category == "ingredient", "Cloning must preserve the ingredient category")
end}

tests.testFactoryItemShiftBoundaries = {check=function(context)
    local _, factory, product, ingredient, second_product, second_ingredient = arrange(context)
    factory:shift(second_product, "next", 1)
    assert(second_product.next == second_ingredient, "Do not cross filtered trailing items")
    factory:shift(ingredient, "previous", 1)
    assert(ingredient.previous == product, "Do not cross filtered leading items")
    factory:shift(product, "next")
    assert(product.previous == second_product and product.next == second_ingredient)
    factory:shift(product, "next")
    assert(product.previous == second_product and product.next == second_ingredient, "Already last means no move")
end}

tests.testFactoryItemPasteCategories = {check=function(context)
    local player, factory, product, ingredient, second_product, second_ingredient = arrange(context)
    local function copy(item)
        local result = context.classes.FactoryItem.unpack(item:pack(true))
        assert(result:validate(player))
        return result
    end
    local success, reason = ingredient:paste(copy(second_product))
    assert(not success and reason == "already_exists_as_product",
        "Disabled targets on the other side must still prevent duplicates")
    local source = context.classes.FactoryItem.init(prototyper.util.find("items", "coal", "item"), "product")
    source.definition = {type="machines", machine_count=3}
    source.active = false
    assert(ingredient:paste(copy(source)))
    local pasted = factory:find({proto=source.proto})
    assert(pasted.category == "ingredient", "Pasting a product onto an ingredient must retain the destination category")
    assert(not pasted.active, "Pasting must preserve the disabled state")
    assert(pasted.definition.machine_count == 3, "Pasting must preserve the machine count")
    assert(source.category == "product", "Pasting must not change the source category")
    factory:remove(pasted)
    assert(product:paste(copy(pasted)))
    assert(factory:find({proto=source.proto}).category == "product",
        "Pasting must preserve the destination category in both directions")
end}

for _, kind in ipairs{"amount", "belts", "machines"} do
    tests["testFactoryItemDefinition_" .. kind] = {check=function(context)
        local player, factory, item = fixture(context)
        local belt = prototyper.util.find("belts", "transport-belt")
        local definitions = {
            amount={type="amount", amount=90},
            belts={type="belts", belt_count=2, belt_proto=belt, belt_stack=2},
            machines={type="machines", machine_count=2.5}
        }
        local definition = definitions[kind]
        item.definition = definition
        local expected
        if definition.type == "amount" then expected = 90
        elseif definition.type == "belts" then expected = 4 * belt.throughput end
        assert(item:get_defined_amount() == expected)
        local packed_factory = factory:pack(false)
        local factory_copy = context.classes.Factory.unpack(packed_factory)
        assert(factory_copy:validate(player), "The unpacked factory must validate")
        assert(factory_copy.first.definition.type == definition.type, "Factory packing must preserve the definition type")
        assert(factory_copy.first:get_defined_amount() == expected, "Factory packing must preserve the defined amount")
        assert(factory_copy.first.definition.machine_count == definition.machine_count, "Factory packing must preserve the machine count")
        local packed = item:pack(true)
        local restored = context.classes.FactoryItem.unpack(packed)
        assert(restored:validate(player), "The unpacked object must validate")
        assert(restored.definition.type == definition.type, "Item packing must preserve the definition type")
        assert(restored:get_defined_amount() == expected, "Item packing must preserve the defined amount")
        assert(restored.definition.machine_count == definition.machine_count, "Item packing must preserve the machine count")
        restored.definition.type = "amount"
        assert(packed.definition.type == definition.type, "Unpacking must not mutate the snapshot")
        lib.clipboard.copy(player, item)
        assert(lib.clipboard.paste(player, item), "Pasting the copied target must succeed")
        item = factory.first
        assert(item.definition.type == definition.type, "Clipboard paste must preserve the definition type")
        assert(item.definition.machine_count == definition.machine_count, "Clipboard paste must preserve the machine count")
        item:add_defined_amount(30)
        if definition.type == "machines" then
            assert(item:get_defined_amount() == nil, "Adding an amount must not create an amount for a machine-defined target")
            assert(item.definition.machine_count == 2.5, "Adding an amount must preserve the machine count")
        else
            assert(item:get_defined_amount() == expected + 30)
        end
    end}
end
tests.testFactoryItemBeltStackNormalization = {check=function(context)
    local player, factory, item = fixture(context)
    local belt = prototyper.util.find("belts", "transport-belt")
    local max_stack = prototypes.utility_constants.max_belt_stack_size
    item.definition = {type="belts", belt_count=2, belt_proto=belt, belt_stack=max_stack * 2}
    local expected = item:get_defined_amount()
    assert(item:validate(player), "An excessive belt stack must normalize successfully")
    assert(item:get_defined_amount() == expected, "Belt stack normalization must preserve the defined amount")
    assert(item.definition.belt_stack == max_stack, "Normalization must clamp the stack to the maximum")
    assert(item.definition.belt_count == 4, "Normalization must compensate with four belts")
end}

-- Disabled target persistence
for _, kind in ipairs{"amount", "belts", "machines"} do
    tests["testDisabledTargetPersistence_" .. kind] = {check=function(context)
        local player, factory, item = fixture(context)
        local definition = target_definition(kind)
        item.definition, item.active = definition, false
        local packed = factory:pack(false)
        local restored = context.classes.Factory.unpack(packed)
        assert(restored:validate(player), "A factory with a disabled target must validate after unpacking")
        assert(restored.first.active == false, "Factory packing must preserve the disabled target")
        lib.clipboard.copy(player, item)
        assert(lib.clipboard.paste(player, item), "Pasting the copied target must succeed")
        item = factory.first
        assert(item.active == false, "Clipboard paste must preserve the disabled target")
        assert(item.definition.type == definition.type, "Clipboard paste must preserve the disabled target definition")
    end}
end

return tests
