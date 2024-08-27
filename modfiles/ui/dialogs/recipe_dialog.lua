local Line = require("backend.data.Line")

-- ** LOCAL UTIL **
-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter and, if there
-- is only one that matches, to return a recipe name that can be added directly without the modal dialog
local function run_preliminary_checks(player, modal_data)
    local force_recipes, force_technologies = player.force.recipes, player.force.technologies
    local preferences = util.globals.preferences(player)

    local relevant_recipes = {}
    local user_disabled_recipe = false
    local counts = {disabled = 0, hidden = 0, disabled_hidden = 0}

    local map = RECIPE_MAPS[modal_data.production_type][modal_data.category_id][modal_data.product_id]
    if map ~= nil then  -- this being nil means that the item has no recipes
        for recipe_id, _ in pairs(map) do
            local recipe = prototyper.util.find("recipes", recipe_id, nil)
            local force_recipe = force_recipes[recipe.name]

            if recipe.custom then  -- Add custom recipes by default
                table.insert(relevant_recipes, {proto=recipe, enabled=true})
                -- These are always enabled and non-hidden, so no need to tally them
                -- They can also not be disabled by user preference

            elseif force_recipe ~= nil then  -- only add recipes that exist on the current force
                local user_disabled = (preferences.ignore_barreling_recipes and recipe.barreling)
                    or (preferences.ignore_recycling_recipes and recipe.recycling)
                user_disabled_recipe = user_disabled_recipe or user_disabled

                if not user_disabled then  -- only add recipes that are not disabled by the user
                    local recipe_enabled, recipe_hidden = force_recipe.enabled, recipe.hidden
                    local recipe_should_show = recipe.enabled_from_the_start or recipe_enabled

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

                    if recipe_should_show then
                        table.insert(relevant_recipes, {proto=recipe, enabled=recipe_enabled})

                        if not recipe_enabled and recipe_hidden then counts.disabled_hidden = counts.disabled_hidden + 1
                        elseif not recipe_enabled then counts.disabled = counts.disabled + 1
                        elseif recipe_hidden then counts.hidden = counts.hidden + 1 end
                    end
                end
            end
        end
    end

    -- Set filters to try and show at least one recipe, should one exist, incorporating user preferences
    local filters = {}
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

    -- Return result, format: return recipe, error-message, filters
    if relevant_recipes_count == 0 then
        local error = (user_disabled_recipe) and {"fp.error_no_enabled_recipe"} or {"fp.error_no_relevant_recipe"}
        return nil, error, nil

    elseif relevant_recipes_count == 1 then
        local chosen_recipe = relevant_recipes[1]
        return chosen_recipe.proto.id, nil, nil

    else  -- 2+ relevant recipes
        return relevant_recipes, nil, filters
    end
end

-- Tries to add the given recipe to the current floor, then exiting the modal dialog
local function attempt_adding_line(player, recipe_id, modal_data)
    local recipe_proto = prototyper.util.find("recipes", recipe_id, nil)
    local line = Line.init(recipe_proto, modal_data.production_type)

    -- If finding a machine fails, this line is invalid
    if line:change_machine_to_default(player) == false then
        util.messages.raise(player, "error", {"fp.error_no_compatible_machine"}, 1)
    else
        local floor = util.context.get(player, "Floor")  --[[@as Floor]]
        local relative_object = OBJECT_INDEX[modal_data.add_after_line_id]  --[[@as LineObject]]
        floor:insert(line, relative_object, "next")  -- if not relative, insert uses last line

        if not (recipe_proto.custom or player.force.recipes[recipe_proto.name].enabled) then
            util.messages.raise(player, "warning", {"fp.warning_recipe_disabled", recipe_proto.localised_name}, 2)
        end

        -- Set machine and beacon up as their default
        line.machine:reset(player)
        line:setup_beacon(player)

        solver.update(player)
        util.raise.refresh(player, "factory")
    end
end


local function create_filter_box(modal_data)
    local bordered_frame = modal_data.modal_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}

    local table_filters = bordered_frame.add{type="table", column_count=2}
    table_filters.style.horizontal_spacing = 16

    local label_filters = table_filters.add{type="label", caption={"fp.show"}}
    label_filters.style.top_margin = 2
    label_filters.style.left_margin = 4

    local flow_filter_switches = table_filters.add{type="flow", direction="vertical"}
    util.gui.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="disabled"},
        modal_data.filters.disabled, {"fp.unresearched_recipes"}, nil, false)
    util.gui.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="hidden"},
        modal_data.filters.hidden, {"fp.hidden_recipes"}, nil, false)
end

local function create_recipe_group_box(modal_data, relevant_group, translations)
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

    flow_group.add{type="empty-widget", style="flib_horizontal_pusher"}
    local frame_recipes = flow_group.add{type="frame", direction="horizontal", style="fp_frame_light_slots"}
    frame_recipes.style.width = MAGIC_NUMBERS.recipes_per_row * 40
    local table_recipes = frame_recipes.add{type="table", column_count=MAGIC_NUMBERS.recipes_per_row,
        style="slot_table"}

    for _, recipe in pairs(relevant_group.recipes) do
        local recipe_proto = recipe.proto
        local recipe_name = recipe_proto.name

        local style = "flib_slot_button_green"
        if not recipe.enabled then style = "flib_slot_button_yellow"
        elseif recipe_proto.hidden then style = "flib_slot_button_default" end

        local button_tags = {mod="fp", on_gui_click="pick_recipe", recipe_proto_id=recipe_proto.id}
        local button_recipe = nil

        button_recipe = table_recipes.add{type="sprite-button", tags=button_tags, style=style,
            sprite=recipe_proto.sprite, mouse_button_filter={"left"}}
        if recipe_proto.custom then button_recipe.tooltip = recipe_proto.tooltip
        else button_recipe.elem_tooltip = {type="recipe", name=recipe_name} end

        -- Figure out the translated name here so search doesn't have to repeat the work for every character
        local translated_name = (translations) and translations["recipe"][recipe_name] or nil
        translated_name = (translated_name) and translated_name:lower() or recipe_name
        recipe_buttons[{name=recipe_name, translated_name=translated_name, hidden=recipe_proto.hidden}] = button_recipe
    end
end

local function create_dialog_structure(modal_data, translations)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame
    content_frame.style.width = 380

    create_filter_box(modal_data)

    local label_warning = content_frame.add{type="label", caption={"fp.error_message", {"fp.no_recipe_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = {8, 0, 0, 8}
    modal_elements.warning_label = label_warning

    modal_elements.groups = {}
    for _, group in ipairs(ORDERED_RECIPE_GROUPS) do
        local relevant_group = modal_data.recipe_groups[group.name]

        -- Only actually create this group if it contains any relevant recipes
        if relevant_group ~= nil then create_recipe_group_box(modal_data, relevant_group, translations) end
    end
end

local function apply_recipe_filter(player, search_term)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local disabled, hidden = modal_data.filters.disabled, modal_data.filters.hidden

    local any_recipe_visible, desired_scroll_pane_height = false, 64+24
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
        desired_scroll_pane_height = desired_scroll_pane_height + additional_height
    end

    modal_data.modal_elements.warning_label.visible = not any_recipe_visible

    local scroll_pane_height = math.min(desired_scroll_pane_height, modal_data.dialog_maximal_height)
    modal_data.modal_elements.content_frame.style.height = scroll_pane_height
end


local function handle_filter_change(player, tags, event)
    local boolean_state = util.gui.switch.convert_to_boolean(event.element.switch_state)
    util.globals.modal_data(player).filters[tags.filter_name] = boolean_state
    util.globals.preferences(player).recipe_filters[tags.filter_name] = boolean_state

    apply_recipe_filter(player, "")
end


-- Checks whether the dialog needs to be created at all
local function recipe_early_abort_check(player, modal_data)
    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local result, error, filters = run_preliminary_checks(player, modal_data)

    if error ~= nil then
        util.messages.raise(player, "error", error, 1)
        return true  -- signal that the dialog does not need to actually be opened

    else
        -- If one relevant recipe is found, try it straight away
        if type(result) == "number" then  -- the given number being the recipe_id
            attempt_adding_line(player, result, modal_data)
            return true  -- idem. above

        else  -- Otherwise, save the relevant data for the dialog opener
            modal_data.result = result
            modal_data.filters = filters
            return false  -- signal that the dialog should be opened
        end
    end
end

-- Handles populating the recipe dialog
local function open_recipe_dialog(player, modal_data)
    -- At this point, we're sure the dialog should be opened
    local recipe_groups = {}
    for _, recipe in pairs(modal_data.result) do
        local group_name = recipe.proto.group.name
        recipe_groups[group_name] = recipe_groups[group_name] or {proto=recipe.proto.group, recipes={}}
        recipe_groups[group_name].recipes[recipe.proto.name] = recipe
    end
    modal_data.recipe_groups = recipe_groups

    local translations = util.globals.player_table(player).translation_tables
    create_dialog_structure(modal_data, translations)
    apply_recipe_filter(player, "")
    modal_data.modal_elements.search_textfield.focus()
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "pick_recipe",
            timeout = 20,
            handler = (function(player, tags, _)
                local modal_data = util.globals.modal_data(player)
                attempt_adding_line(player, tags.recipe_proto_id, modal_data)
                util.raise.close_dialog(player, "cancel")
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "toggle_recipe_filter",
            handler = handle_filter_change
        }
    }
}

listeners.dialog = {
    dialog = "recipe",
    metadata = (function(modal_data)
        local product_proto = prototyper.util.find("items", modal_data.product_id, modal_data.category_id)
        return {
            caption = {"", {"fp.add"}, " ", {"fp.pl_recipe", 1}},
            subheader_text = {"fp.recipe_instruction", {"fp." .. modal_data.production_type},
                product_proto.localised_name},
            search_handler_name = "apply_recipe_filter"
        }
    end),
    early_abort_check = recipe_early_abort_check,
    open = open_recipe_dialog
}

listeners.global = {
    apply_recipe_filter = apply_recipe_filter
}

return { listeners }
