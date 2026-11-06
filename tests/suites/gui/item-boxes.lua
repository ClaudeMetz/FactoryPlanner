---@diagnostic disable

local helpers = require("helpers")
local gui = require("helpers").gui
local fixture = require("fixtures").target_item
local dispatch = gui.dispatch
local SimpleItem = script and require("__factoryplanner__.backend.data.SimpleItem")

local function arrange(context)
    local player, factory, product = fixture(context)
    local function add(name, category)
        local item = context.classes.FactoryItem.init(category, prototyper.util.find("items", name, "item"))
        item.definition = {type="amount", amount=10}
        factory:insert(item)
        return item
    end
    product.definition = {type="amount", amount=10}
    local ingredient = add("iron-ore", "ingredient")
    local second_product = add("copper-plate", "product")
    local second_ingredient = add("copper-ore", "ingredient")
    main_dialog.rebuild(player, false)
    compact_dialog.rebuild(player, false)

    local function buttons(category)
        return lib.globals.main_elements(player).item_boxes[category .. "_item_table"].children
    end
    local function button(item)
        for _, candidate in pairs(buttons(item.category)) do
            if candidate.tags.item_id == item.id then return candidate end
        end
        error("Missing target button for " .. item.proto.name)
    end
    local function click(element, overrides) gui.click(player, element, overrides) end
    local function menu(item)
        click(button(item), {button=defines.mouse_button_type.right})
        local actions = {}
        for _, action in pairs(lib.globals.ui_state(player).context_menu.children[1].children) do
            actions[action.tags.action] = action
        end
        return actions
    end
    return {player=player, factory=factory, product=product, ingredient=ingredient, second_product=second_product, second_ingredient=second_ingredient, add=add, buttons=buttons, button=button, click=click, menu=menu}
end

return {
    testIngredientTargetOrdering = {check=function(context)
        local f = arrange(context)
        local factory = f.factory
        local product = f.product
        local ingredient = f.ingredient
        local second_product = f.second_product
        local second_ingredient = f.second_ingredient
        local buttons = f.buttons
        local button = f.button
        local click = f.click
        local menu = f.menu
        for _, category in ipairs{"product", "ingredient"} do
            local list = buttons(category)
            assert(#list == 3 and list[3].tags.on_gui_click == "add_top_level_item")
            assert(list[3].tags.item_category == category)
            assert(not list[1].tags.flags.move_left and list[1].tags.flags.move_right)
            assert(list[2].tags.flags.move_left and not list[2].tags.flags.move_right)
            for i = 1, 2 do
                assert(OBJECT_INDEX[list[i].tags.item_id].category == category)
                assert(list[i].tags.flags.consume == (category == "ingredient"))
            end
        end
        local actions = menu(ingredient)
        for _, name in ipairs{"edit", "toggle", "delete", "copy", "paste", "cut", "move_left", "move_right"} do
            assert(actions[name], "Ingredient targets must offer " .. name)
        end
        assert(not actions.move_left.enabled and actions.move_right.enabled)
        click(actions.move_right)
        local ingredients = factory:as_list({category="ingredient"})
        local products = factory:as_list({category="product"})
        assert(ingredients[1] == second_ingredient and ingredients[2] == ingredient)
        assert(products[1] == product and products[2] == second_product)
        assert(not button(ingredient).tags.flags.move_right)
    end},
    testIngredientTargetEditing = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local ingredient = f.ingredient
        local button = f.button
        local click = f.click
        local menu = f.menu
        click(menu(ingredient).toggle)
        assert(not ingredient.active and button(ingredient).style.name == "fflib_slot_button_red")
        click(menu(ingredient).edit)
        assert(lib.globals.modal_data(player).item_category == "ingredient")
        local elements = lib.globals.modal_elements(player)
        elements.item_amount_textfield.text = "60"
        dispatch(player, elements.item_amount_textfield, defines.events.on_gui_text_changed)
        lib.gui.close_dialog(player, "submit")
        assert(ingredient:get_defined_amount() == 60 / lib.globals.preferences(player).timescale)
        assert(ingredient.category == "ingredient")
    end},
    testIngredientTargetCutPaste = {check=function(context)
        local f = arrange(context)
        local factory = f.factory
        local ingredient = f.ingredient
        local buttons = f.buttons
        local click = f.click
        local menu = f.menu
        ingredient.active = false
        click(menu(ingredient).cut)
        assert(not factory:find({proto=ingredient.proto}))
        local list = buttons("ingredient")
        click(list[#list], {shift=true})
        ingredient = factory:find({proto=ingredient.proto})
        assert(ingredient and ingredient.category == "ingredient" and not ingredient.active)
    end},
    testIngredientTargetPickerEligibility = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local factory = f.factory
        local product = f.product
        local ingredient = f.ingredient
        local buttons = f.buttons
        local click = f.click
        local list = buttons("ingredient")
        click(list[#list])
        assert(lib.globals.modal_data(player).item_category == "ingredient")
        local stone_button
        for _, group in pairs(lib.globals.modal_elements(player).groups) do
            for _, subgroup in pairs(group.subgroup_tables) do
                for _, candidate in pairs(subgroup) do
                    local proto = prototyper.util.find("items", candidate.tags.item_id, candidate.tags.category_id)
                    if proto == product.proto then
                        assert(not candidate.tags.enabled)
                        local tooltip = candidate.tooltip
                        assert(tooltip[#tooltip][1] == "fp.picker_already_selected_product",
                            "Duplicate tooltips must identify the existing side")
                    end
                    if proto.name == "stone" then stone_button = candidate end
                end
            end
        end
        assert(stone_button and stone_button.tags.enabled)
        click(stone_button)
        local elements = lib.globals.modal_elements(player)
        elements.item_amount_textfield.text = "120"
        dispatch(player, elements.item_amount_textfield, defines.events.on_gui_text_changed)
        lib.gui.close_dialog(player, "submit")
        local stone = factory:find({proto=prototyper.util.find("items", "stone", "item")})
        assert(stone and stone.category == "ingredient")
    end},
    testIngredientTargetRecipeSelection = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local factory = f.factory
        local ingredient = f.ingredient
        local add = f.add
        local button = f.button
        local click = f.click
        click(button(ingredient))
        if factory.top_floor:count() == 0 then
            local modal_data = lib.globals.modal_data(player)
            assert(modal_data.production_type == "consume")
            lib.gui.close_dialog(player, "cancel")
        else
            local consumes_ore = false
            for _, input in pairs(factory.top_floor.first.recipe.proto.ingredients) do
                if input.name == "iron-ore" then consumes_ore = true end
            end
            assert(consumes_ore, "Ingredient targets must add consuming recipes")
        end
    end},
    testIngredientTargetConversion = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local factory = f.factory
        local product = f.product
        local ingredient = f.ingredient
        local buttons = f.buttons
        local button = f.button
        local click = f.click
        local menu = f.menu
        local coal = prototyper.util.find("items", "coal", "item")
        product.active = false
        local spawnable = prototyper.util.find("items", "test-spawnable-input", "item")
        assert(spawnable and lib.availability.has_productive_recipe(spawnable, "consume"))
        factory.top_floor.ingredients = {SimpleItem.init(nil, product.proto, nil, 3), SimpleItem.init(nil, coal, nil, 7),
            SimpleItem.init(nil, spawnable, nil, 1)}
        lib.gui.run_refresh(player, "item_boxes")
        local calculated
        for _, candidate in pairs(buttons("ingredient")) do
            if candidate.tags.item_index == 1 then
                click(candidate, {button=defines.mouse_button_type.right})
                local conversion
                for _, action in pairs(lib.globals.ui_state(player).context_menu.children[1].children) do
                    if action.tags.action == "convert_to_target" then conversion = action end
                end
                assert(conversion and not conversion.enabled, "Duplicate conversion must remain visible but disabled")
                assert(conversion.tooltip[2][1] == "fp.item_already_defined_product")
                modal_dialog.close_context_menu(player)
                local count = factory:count()
                click(candidate, {control=true})
                assert(factory:count() == count, "The conversion shortcut must also reject duplicates")
            elseif candidate.tags.item_index == 2 then
                calculated = candidate
                assert(candidate.tags.flags.top_floor and not candidate.tags.flags.consume)
            elseif candidate.tags.item_index == 3 then
                click(candidate, {button=defines.mouse_button_type.right})
                local conversion
                for _, action in pairs(lib.globals.ui_state(player).context_menu.children[1].children) do
                    if action.tags.action == "convert_to_target" then conversion = action end
                end
                assert(conversion and not conversion.enabled, "Ineligible conversion must remain visible but disabled")
                assert(conversion.tooltip[2][1] == "fp.item_cannot_be_defined")
                modal_dialog.close_context_menu(player)
                click(candidate, {control=true})
                assert(not factory:find({proto=spawnable}), "Conversion must not bypass picker eligibility")
            end
        end
        assert(calculated)
        click(calculated, {control=true})
        local converted = factory:find({proto=coal})
        assert(converted and converted.category == "ingredient" and converted:get_defined_amount() == 7)
        click(menu(converted).delete)
        assert(not factory:find({proto=coal}))
    end},
    testBlueprintImportPreservesIngredientTargets = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local product = f.product
        local ingredient = f.ingredient
        local add = f.add
        local buttons = f.buttons
        local click = f.click
        local furnace = add("stone-furnace", "product")
        local assembler = add("assembling-machine-1", "ingredient")
        player.cursor_stack.set_stack{name="blueprint", count=1}
        player.cursor_stack.set_blueprint_entities{
            {entity_number=1, name="stone-furnace", position={0, 0}},
            {entity_number=2, name="assembling-machine-1", position={4, 0}}
        }
        lib.gui.run_refresh(player, "item_boxes")
        local list = buttons("ingredient")
        click(list[#list])
        assert(lib.globals.modal_data(player).item_category == "ingredient",
            "Holding a blueprint must still open the ingredient picker")
        assert(furnace:get_defined_amount() == 10 and assembler:get_defined_amount() == 10)
        lib.gui.close_dialog(player, "cancel")
        list = buttons("product")
        click(list[#list])
        assert(furnace:get_defined_amount() == 10 + 1 / lib.globals.preferences(player).timescale)
        assert(assembler:get_defined_amount() == 10, "Blueprint imports must not modify ingredient targets")
        player.clear_cursor()
    end},
    testArchivedTargetAddButtons = {check=function(context)
        local f = arrange(context)
        local player = f.player
        local factory = f.factory
        local product = f.product
        local ingredient = f.ingredient
        local add = f.add
        local buttons = f.buttons
        factory.archived = true
        lib.gui.run_refresh(player, "item_boxes")
        for _, category in ipairs{"product", "ingredient"} do
            local list = buttons(category)
            assert(not list[#list].enabled, "Archived factories must disable both add buttons")
        end
    end},
}
