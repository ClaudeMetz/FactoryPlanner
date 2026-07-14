local Line = require("backend.data.Line")

---@class RecipeDialogModalData: ModalData
---@field recipe_id ObjectID?
---@field fuel_id ObjectID?
---@field add_after_line_id ObjectID?
---@field production_type RecipeProductionType
---@field category_id integer
---@field product_id integer
---@field relevant_recipes RelevantRecipe[]
---@field filters RecipeDialogFilters
---@field base_fluid FPItemPrototype?
---@field annotation LocalisedString?
---@field applicable_values float[]?
---@field temperature float?
---@field translations TranslationTables
---@field recipe_groups RecipeDialogGroups

---@alias RelevantRecipe {proto: FPRecipePrototype, enabled: boolean}
---@alias RecipeDialogFilters {disabled: boolean, hidden: boolean}

-- ** LOCAL UTIL **
-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter
-- and finding any recipes that produce the given prototype
---@param player any
---@param modal_data any
---@param proto any
---@return RelevantRecipe[]? relevant_recipes
---@return LocalisedString? error
---@return RecipeDialogFilters filters
local function match_recipes(player, modal_data, proto)
    local force_recipes, force_technologies = player.force.recipes, player.force.technologies
    local preferences = lib.globals.preferences(player)

    local relevant_recipes = {}
    local user_disabled_recipe = false
    local counts = {disabled = 0, hidden = 0, disabled_hidden = 0}

    local map = RECIPE_MAPS[modal_data.production_type][proto.category_id][proto.id]
    local overwrite_recipe_picker = storage.integrations.overwrite_recipe_picker or {}

    if map ~= nil then  -- this being nil means that the item has no recipes
        for recipe_id, _ in pairs(map) do
            local recipe = prototyper.util.find("recipes", recipe_id, nil)  ---@as FPRecipePrototype
            local force_recipe = force_recipes[recipe.name]

            if recipe.custom then
                -- These are always enabled and non-hidden, so no need to tally them
                table.insert(relevant_recipes, {proto=recipe, enabled=true})

            elseif force_recipe ~= nil then  -- only add recipes that exist on the current force
                local recipe_enabled, recipe_hidden = force_recipe.enabled, recipe.hidden
                local overwrite = overwrite_recipe_picker[recipe.name]
                local recipe_should_show = overwrite

                if overwrite == nil then  -- run this in the normal case
                    local user_disabled = (preferences.ignore_barreling_recipes and recipe.barreling)
                        or (preferences.ignore_recycling_recipes and recipe.recycling)
                    user_disabled_recipe = user_disabled_recipe or user_disabled

                    if not user_disabled then  -- only add recipes that are not disabled by the user
                        recipe_should_show = recipe.enabled_from_the_start or recipe_enabled

                        -- If the recipe is not enabled, it has to be made sure that there is at
                        -- least one enabled technology that could potentially enable it
                        if not recipe_should_show and recipe.enabling_technologies ~= nil then
                            for _, technology_name in pairs(recipe.enabling_technologies) do
                                local force_tech = force_technologies[technology_name]
                                if force_tech and (force_tech.enabled or force_tech.visible_when_disabled) then
                                    recipe_should_show = true
                                    break
                                end
                            end
                        end
                    end
                end

                if recipe_should_show then
                    table.insert(relevant_recipes, {proto=recipe, enabled=recipe_enabled})

                    if not recipe_enabled and recipe_hidden then counts.disabled_hidden = counts.disabled_hidden + 1
                    elseif not recipe_enabled then counts.disabled = counts.disabled + 1
                    elseif recipe_hidden then counts.hidden = counts.hidden + 1 end
                end
            end
        end
    end

    -- Set filters to try and show at least one recipe, should one exist, incorporating user preferences
    local filters = {}  ---@type RecipeDialogFilters
    local user_prefs = preferences.recipe_filters
    local relevant_recipes_count = #relevant_recipes

    if relevant_recipes_count - counts.disabled - counts.hidden - counts.disabled_hidden > 0 then
        filters.disabled = user_prefs.disabled or false
        filters.hidden = user_prefs.hidden or false
    elseif relevant_recipes_count - counts.hidden - counts.disabled_hidden > 0 then
        filters.disabled = true
        filters.hidden = user_prefs.hidden or false
    else
        filters.disabled = true
        filters.hidden = true
    end

    if relevant_recipes_count == 0 then
        local issue = (user_disabled_recipe) and {"fp.no_recipe_enabled"} or {"fp.no_recipe_existing"}
        local production_type = {"fp.no_recipe_" .. modal_data.production_type}
        local error = {"fp.error_no_usable_recipe", proto.localised_name, issue, production_type}
        return nil, error, filters
    else
        return relevant_recipes, nil, filters
    end
end

-- Tries to add the given recipe to the current floor, then exiting the modal dialog
---@param player LuaPlayer
---@param recipe_id integer
---@param modal_data RecipeDialogModalData
local function attempt_adding_line(player, recipe_id, modal_data)
    local recipe_proto = prototyper.util.find("recipes", recipe_id, nil)  ---@as FPRecipePrototype
    local line = Line.init(recipe_proto, modal_data.production_type)
    local recipe_name = recipe_proto.localised_name

    -- If finding a machine fails, this line is invalid
    if line:change_machine_to_default(player) == false then
        lib.messages.raise(player, "error", {"fp.error_no_compatible_machine", recipe_name}, 1)
    else
        local floor = lib.context.get(player, "Floor")  ---@as Floor
        local relative_object = OBJECT_INDEX[modal_data.add_after_line_id--[[@cast -nil]]]  ---@as LineObject?
        floor:insert(line, relative_object, "next")  -- if not relative, insert uses last line

        -- Apply defaults as appropriate
        line.recipe:apply_temperature_defaults(player)
        line.machine:reset(player)
        line:setup_beacon(player)

        -- Set ingredient temperature if this is a base_fluid dialog
        if modal_data.temperature then
            if modal_data.recipe_id then
                local fluid_name = modal_data.base_fluid--[[@cast -nil]].name
                local recipe = OBJECT_INDEX[modal_data.recipe_id]  ---@as Recipe
                recipe.temperatures[fluid_name] = modal_data.temperature
            elseif modal_data.fuel_id then
                local fuel = OBJECT_INDEX[modal_data.fuel_id]  ---@as Fuel
                fuel.temperature = modal_data.temperature
            end
        end

        -- Set ingredient temperature to match byproduct recipe
        if modal_data.production_type == "consume" then
            local proto = prototyper.util.find("items", modal_data.product_id, modal_data.category_id)
            ---@cast proto FPItemPrototype
            if proto.temperature then line.recipe.temperatures[proto.base_name] = proto.temperature end
        end

        if not line:is_temperature_fully_configured() then
            lib.messages.raise(player, "warning", {"fp.warning_temperature_not_configured", recipe_name}, 1)
        end

        if not (recipe_proto.custom or player.force--[[@as LuaForce]].recipes[recipe_proto.name].enabled) then
            lib.messages.raise(player, "warning", {"fp.warning_recipe_disabled", recipe_name}, 1)
        end

        if not line:get_surface_compatibility().overall then
            lib.messages.raise(player, "warning", {"fp.warning_surface_not_compatible", recipe_name}, 1)
        end

        solver.update(player)
        lib.gui.run_refresh(player, "production")
    end
end

---@param player LuaPlayer
---@param tags PickRecipeTags
---@param event EventData.on_gui_click
local function handle_recipe_click(player, tags, event)
    if event.shift then
        local recipe_proto = prototyper.util.find("recipes", tags.recipe_proto_id, nil)  ---@as FPRecipePrototype
        if not recipe_proto.enabling_technologies then return end
        player.open_technology_gui(recipe_proto.enabling_technologies[1])
    else
        local modal_data = lib.globals.modal_data(player)  ---@as RecipeDialogModalData
        attempt_adding_line(player, tags.recipe_proto_id, modal_data)
        lib.gui.close_dialog(player, "cancel")
    end
end


---@param modal_data RecipeDialogModalData
local function create_filter_box(modal_data)
    local content_frame =  modal_data.modal_elements.content_frame
    local bordered_frame = content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    bordered_frame.style.left_padding = 12

    local table_filters = bordered_frame.add{type="table", column_count=2}
    table_filters.style.horizontal_spacing = 16

    local label_filters = table_filters.add{type="label", caption={"fp.show"}}
    label_filters.style.top_margin = 2

    ---@class ToggleRecipeFilterTags
    ---@field filter_name "disabled" | "hidden"

    local flow_filter_switches = table_filters.add{type="flow", direction="vertical"}
    lib.gui.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="disabled"},
        modal_data.filters.disabled, {"fp.unresearched_recipes"}, nil, false)
    lib.gui.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="hidden"},
        modal_data.filters.hidden, {"fp.hidden_recipes"}, nil, false)

    if modal_data.temperature then  ---@cast modal_data.applicable_values -nil
        bordered_frame.add{type="line", direction="horizontal"}
        local flow_temperature = bordered_frame.add{type="flow", direction="horizontal"}
        flow_temperature.style.vertical_align = "center"
        flow_temperature.add{type="label", caption={"fp.compatible_temperatures"}}

        local annotation = flow_temperature.add{type="label", caption=modal_data.annotation}
        annotation.style.left_margin = 16

        local table_temperatures = bordered_frame.add{type="table", column_count=#modal_data.applicable_values}
        table_temperatures.style.horizontal_spacing = 0
        table_temperatures.style.top_margin = 8

        for _, temperature in pairs(modal_data.applicable_values) do
            local toggled = (temperature == modal_data.temperature)
            ---@class ChangeRecipeTemperatureTags
            ---@field temperature float
            local tags = {mod="fp", on_gui_click="change_recipe_temperature", temperature=temperature}
            table_temperatures.add{type="button", tags=tags, caption={"fp.temperature_value", temperature},
                style="fp_button_push", toggled=toggled, mouse_button_filter={"left"}}
        end
    end
end

---@param modal_data RecipeDialogModalData
---@param relevant_group RecipeDialogGroup
local function create_recipe_group_box(modal_data, relevant_group)
    local modal_elements = modal_data.modal_elements
    local bordered_frame = modal_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}
    bordered_frame.style.padding = 8

    local next_index = #modal_elements.groups + 1
    modal_elements.groups[next_index] = {name=relevant_group.proto.name, frame=bordered_frame, recipe_buttons={}}
    local recipe_buttons = modal_elements.groups[next_index].recipe_buttons

    local flow_group = bordered_frame.add{type="flow", direction="horizontal"}
    flow_group.style.vertical_align = "center"

    local group_sprite = flow_group.add{type="sprite-button", sprite=("item-group/" .. relevant_group.proto.name),
        tooltip=relevant_group.proto.localised_name, style="transparent_slot"}
    group_sprite.style.size = 64
    group_sprite.style.right_margin = 16

    flow_group.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local frame_recipes = flow_group.add{type="frame", direction="horizontal", style="fp_frame_light_slots"}
    frame_recipes.style.width = MAGIC_NUMBERS.recipes_per_row * 40
    local table_recipes = frame_recipes.add{type="table", column_count=MAGIC_NUMBERS.recipes_per_row,
        style="slot_table"}

    for _, recipe in pairs(relevant_group.recipes) do
        local recipe_proto = recipe.proto
        local recipe_name = recipe_proto.name

        local style = "fflib_slot_button_green"
        if not recipe.enabled then style = "fflib_slot_button_yellow"
        elseif recipe_proto.hidden then style = "fflib_slot_button_default" end

        ---@class PickRecipeTags
        ---@field recipe_proto_id integer
        local button_tags = {mod="fp", on_gui_click="pick_recipe", recipe_proto_id=recipe_proto.id}
        local button_recipe = nil

        local tooltip = {""}
        if recipe_proto.custom then table.insert(tooltip, recipe_proto.tooltip) end
        if not recipe.enabled and recipe_proto.enabling_technologies then
            local technology = prototypes.technology[recipe_proto.enabling_technologies[1]]
            table.insert(tooltip, {"fp.recipe_unlocked_by", technology.localised_name})
        end

        button_recipe = table_recipes.add{type="sprite-button", tags=button_tags, style=style,
            sprite=recipe_proto.sprite, tooltip=tooltip, mouse_button_filter={"left"}}
        if not recipe_proto.custom then button_recipe.elem_tooltip = {type="recipe", name=recipe_name} end

        -- Figure out the translated name here so search doesn't have to repeat the work for every character
        local translations = modal_data.translations
        local translated_name = (translations) and translations["recipe"][recipe_name] or nil
        translated_name = (translated_name) and helpers.multilingual_to_lower(translated_name) or recipe_name
        recipe_buttons[{name=recipe_name, translated_name=translated_name, hidden=recipe_proto.hidden}] = button_recipe
    end
end

---@alias RecipeDialogGroups table<string, RecipeDialogGroup>
---@alias RecipeDialogGroup {proto: ItemGroup, recipes: table<string, RelevantRecipe>}

---@param modal_data RecipeDialogModalData
local function build_dialog_structure(modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame
    content_frame.clear()

    create_filter_box(modal_data)

    local label_warning = content_frame.add{type="label", caption={"fp.error_message", {"fp.no_recipe_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = {8, 0, 0, 8}
    modal_elements.warning_label = label_warning

    local recipe_groups = {}  ---@type RecipeDialogGroups
    for _, recipe in pairs(modal_data.relevant_recipes) do
        local group_name = recipe.proto.group.name
        recipe_groups[group_name] = recipe_groups[group_name] or {proto=recipe.proto.group, recipes={}}
        recipe_groups[group_name].recipes[recipe.proto.name] = recipe
    end
    modal_data.recipe_groups = recipe_groups  -- used by filter

    modal_elements.groups = {}
    for _, group in ipairs(ORDERED_RECIPE_GROUPS) do
        local relevant_group = modal_data.recipe_groups[group.name]  ---@as RecipeDialogGroup

        -- Only actually create this group if it contains any relevant recipes
        if relevant_group ~= nil then create_recipe_group_box(modal_data, relevant_group) end
    end
end

---@param player LuaPlayer
---@param search_term string
local function apply_recipe_filter(player, search_term)
    local modal_data = lib.globals.modal_data(player)  ---@as RecipeDialogModalData
    local disabled, hidden = modal_data.filters.disabled, modal_data.filters.hidden

    local any_recipe_visible, added_scroll_pane_height = false, 0
    for _, group in ipairs(modal_data.modal_elements.groups) do
        local group_data = modal_data.recipe_groups[group.name]
        local any_group_recipe_visible = false

        for recipe_data, button in pairs(group.recipe_buttons) do
            local recipe_name = recipe_data.name
            local recipe_enabled = group_data.recipes[recipe_name].enabled

            -- Can only get to this if translations are complete, as the textfield is disabled otherwise
            local found = (search_term == recipe_name) or string.find(recipe_data.translated_name, search_term, 1, true)
            local visible = found and (disabled or recipe_enabled) and (hidden or not recipe_data.hidden) or false

            button.visible = visible
            any_group_recipe_visible = any_group_recipe_visible or visible
        end

        group.frame.visible = any_group_recipe_visible
        any_recipe_visible = any_recipe_visible or any_group_recipe_visible

        local button_table_height = math.ceil(table_size(group.recipe_buttons) / MAGIC_NUMBERS.recipes_per_row) * 40
        local additional_height = math.max(88, button_table_height + 24) + 4
        added_scroll_pane_height = added_scroll_pane_height + additional_height
    end

    modal_data.modal_elements.warning_label.visible = not any_recipe_visible

    added_scroll_pane_height = math.max(added_scroll_pane_height, 42)  -- set minimum when no recipe matches
    local base_scroll_pane_height = (modal_data.temperature) and (64+24)+70 or 64+24
    local desired_scroll_pane_height = base_scroll_pane_height + added_scroll_pane_height
    local bounded_scroll_pane_height = math.min(desired_scroll_pane_height, modal_data.dialog_maximal_height - 80)
    modal_data.modal_elements.content_frame.style.height = bounded_scroll_pane_height
end


---@param player LuaPlayer
---@param tags ToggleRecipeFilterTags
---@param event EventData.on_gui_switch_state_changed
local function handle_filter_change(player, tags, event)
    local boolean_state = lib.gui.switch.convert_to_boolean(event.element.switch_state)
    local modal_data = lib.globals.modal_data(player)  ---@as RecipeDialogModalData
    modal_data.filters[tags.filter_name] = boolean_state
    lib.globals.preferences(player).recipe_filters[tags.filter_name] = boolean_state

    modal_dialog.run_search(player)
end

---@param player LuaPlayer
---@param temperature float
local function apply_temperature(player, temperature)
    local modal_data = lib.globals.modal_data(player)  ---@as RecipeDialogModalData
    modal_data.temperature = temperature

    local name = modal_data.base_fluid--[[@cast -nil]].name .. "-" .. temperature
    local proto = prototyper.util.find("items", name, "fluid")
    local relevant_recipes, _, filters = match_recipes(player, modal_data, proto)
    modal_data.relevant_recipes = relevant_recipes or {}  -- no match for a given temperature is fine
    modal_data.filters = filters
end


-- Checks whether the dialog needs to be created at all
---@param player LuaPlayer
---@param modal_data RecipeDialogModalData
---@return boolean
local function recipe_early_abort_check(player, modal_data)
    local proto = prototyper.util.find("items", modal_data.product_id, modal_data.category_id)
    ---@cast proto FPItemPrototype

    local base_fluid = (proto.type == "fluid" and proto.temperature == nil)
    if base_fluid then return false end  -- proceed to opening the dialog right away

    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local relevant_recipes, error, filters = match_recipes(player, modal_data, proto)

    if error ~= nil then
        lib.messages.raise(player, "error", error, 1)
        return true  -- signal that the dialog does not need to actually be opened

    else  ---@cast relevant_recipes -nil
        if #relevant_recipes == 1 then  -- if one relevant recipe is found, try it straight away
            attempt_adding_line(player, relevant_recipes[1]--[[@cast -nil]].proto.id, modal_data)
            return true  -- idem above

        else  -- Otherwise, save the relevant data for the dialog opener
            modal_data.relevant_recipes = relevant_recipes
            modal_data.filters = filters
            return false  -- signal that the dialog should be opened
        end
    end
end

-- Handles populating the recipe dialog
---@param player LuaPlayer
---@param modal_data RecipeDialogModalData
local function open_recipe_dialog(player, modal_data)
    -- At this point, we're sure there's more than one recipe choice
    if modal_data.relevant_recipes == nil then  -- this is a base_fluid dialog
        modal_data.base_fluid = prototyper.util.find("items", modal_data.product_id, modal_data.category_id)
        ---@cast modal_data.base_fluid FPItemPrototype

        local temperature_data  ---@type TemperatureData
        if modal_data.recipe_id then
            local recipe = OBJECT_INDEX[modal_data.recipe_id]  ---@as Recipe
            temperature_data = recipe.temperature_data[modal_data.base_fluid.name]
        elseif modal_data.fuel_id then
            local fuel = OBJECT_INDEX[modal_data.fuel_id]  ---@as Fuel
            temperature_data = fuel.temperature_data
        end

        modal_data.annotation = temperature_data.annotation
        modal_data.applicable_values = temperature_data.applicable_values
        apply_temperature(player, modal_data.applicable_values[1]--[[@as -nil]])
    end

    modal_data.translations = lib.globals.player_table(player).translation_tables
    build_dialog_structure(modal_data)
    modal_dialog.run_search(player)
    modal_data.modal_elements.search_textfield.focus()
end

-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "pick_recipe",
            timeout = 20,
            handler = handle_recipe_click
        },
        {
            name = "change_recipe_temperature",
            handler = function(player, tags, _)
                ---@cast tags ChangeRecipeTemperatureTags
                apply_temperature(player, tags.temperature)

                local modal_data = lib.globals.modal_data(player)  ---@as RecipeDialogModalData
                build_dialog_structure(modal_data)
                modal_dialog.run_search(player)
            end
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_recipe_filter",
            handler = handle_filter_change
        }
    }
}  ---@as GUIListenerDefinition

listeners.dialog = {
    dialog = "recipe",
    metadata = function(modal_data)
        ---@cast modal_data RecipeDialogModalData
        local product_proto = prototyper.util.find("items", modal_data.product_id, modal_data.category_id)
        return {
            caption = {"", {"fp.add"}, " ", {"fp.pl_recipe", 1}},
            subheader_text = {"fp.recipe_instruction", {"fp." .. modal_data.production_type},
                product_proto--[[@as FPItemPrototype]].localised_name},
            search_handler_name = "apply_recipe_filter"
        }  ---@as ModalDialogSettings
    end,
    early_abort_check = recipe_early_abort_check,
    open = open_recipe_dialog
}

listeners.global = {
    apply_recipe_filter = apply_recipe_filter
}

return { listeners }
