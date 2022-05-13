recipe_dialog = {}

local recipes_per_row = 6

-- ** LOCAL UTIL **
-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter and, if there
-- is only one that matches, to return a recipe name that can be added directly without the modal dialog
local function run_preliminary_checks(player, product_proto, production_type)
    local force_recipes, force_technologies = player.force.recipes, player.force.technologies
    local preferences = data_util.get("preferences", player)

    local relevant_recipes = {}
    local user_disabled_recipe = false
    local counts = {disabled = 0, hidden = 0, disabled_hidden = 0}

    local map = RECIPE_MAPS[production_type][product_proto.type][product_proto.name]
    if map ~= nil then  -- this being nil means that the item has no recipes
        for recipe_id, _ in pairs(map) do
            local recipe = global.all_recipes.recipes[recipe_id]
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
                            local force_technology = force_technologies[technology_name]
                            if force_technology and force_technology.enabled then
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
    local show = { filters={} }
    local user_prefs = preferences.recipe_filters
    local relevant_recipes_count = #relevant_recipes

    -- (This logic is probably inefficient, but it's clear and way faster than the loop above anyways)
    if relevant_recipes_count - counts.disabled - counts.hidden - counts.disabled_hidden > 0 then
        show.filters.disabled = user_prefs.disabled or false
        show.filters.hidden = user_prefs.hidden or false

    elseif relevant_recipes_count - counts.hidden - counts.disabled_hidden > 0 then
        show.filters.disabled = true
        show.filters.hidden = user_prefs.hidden or false

    else
        show.filters.disabled = true
        show.filters.hidden = true
    end

    -- Return result, format: return recipe, error-message, show
    if relevant_recipes_count == 0 then
        local error = (user_disabled_recipe) and {"fp.error_no_enabled_recipe"} or {"fp.error_no_relevant_recipe"}
        return nil, error, nil

    elseif relevant_recipes_count == 1 then
        local chosen_recipe = relevant_recipes[1]
        return chosen_recipe.proto.id, nil, nil

    else  -- 2+ relevant recipes
        return relevant_recipes, nil, show
    end
end

-- Tries to add the given recipe to the current floor, then exiting the modal dialog
local function attempt_adding_line(player, recipe_id)
    local ui_state = data_util.get("ui_state", player)
    local recipe = Recipe.init_by_id(recipe_id, ui_state.modal_data.production_type)
    local line = Line.init(recipe)

    -- If finding a machine fails, this line is invalid
    if Line.change_machine_to_default(line, player) == false then  -- not sure this can even happen because generator
        title_bar.enqueue_message(player, {"fp.error_no_compatible_machine"}, "error", 1, false)

    else
        local add_after_position = ui_state.modal_data.add_after_position
        -- If add_after_position is given, insert it below that one, add it to the end otherwise
        if add_after_position == nil then
            Floor.add(ui_state.context.floor, line)
        else
            Floor.insert_at(ui_state.context.floor, (add_after_position + 1), line)
        end

        local message = nil
        if not (recipe.proto.custom or player.force.recipes[recipe.proto.name].enabled) then
            message = {text={"fp.warning_recipe_disabled"}, type="warning"}
        end
        local defaults_message = Line.apply_mb_defaults(line, player)
        if not message then message = defaults_message end  -- a bit silly

        calculation.update(player, ui_state.context.subfactory)
        main_dialog.refresh(player, "subfactory")
        if message ~= nil then title_bar.enqueue_message(player, message.text, message.type, 1, false) end
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
    ui_util.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="disabled"},
      modal_data.filters.disabled, {"fp.unresearched_recipes"}, nil, false)
    ui_util.switch.add_on_off(flow_filter_switches, "toggle_recipe_filter", {filter_name="hidden"},
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
    group_sprite.style.right_margin = 12

    local frame_recipes = flow_group.add{type="frame", direction="horizontal", style="fp_frame_deep_slots_small"}
    local table_recipes = frame_recipes.add{type="table", column_count=recipes_per_row, style="filter_slot_table"}

    for _, recipe in pairs(relevant_group.recipes) do
        local recipe_proto = recipe.proto
        local recipe_name = recipe_proto.name

        local style = "flib_slot_button_green_small"
        if not recipe.enabled then style = "flib_slot_button_yellow_small"
        elseif recipe_proto.hidden then style = "flib_slot_button_default_small" end

        local button_tags = {mod="fp", on_gui_click="pick_recipe", recipe_proto_id=recipe_proto.id}
        local button_recipe = nil

        if recipe_proto.custom then  -- can't use choose-elem-buttons for custom recipes
            button_recipe = table_recipes.add{type="sprite-button", tags=button_tags, style=style,
              sprite=recipe_proto.sprite, tooltip=recipe_proto.tooltip, mouse_button_filter={"left"}}
        else
            button_recipe = table_recipes.add{type="choose-elem-button", elem_type="recipe", tags=button_tags,
              style=style, recipe=recipe_name, mouse_button_filter={"left"}}
            button_recipe.locked = true
        end

        -- Figure out the translated name here so search doesn't have to repeat the work for every character
        local translated_name = (translations) and translations["recipe"][recipe_name]:lower() or nil
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

function SEARCH_HANDLERS.apply_recipe_filter(player, search_term)
    local modal_data = data_util.get("modal_data", player)
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
            local visible = found and (disabled or recipe_enabled) and (hidden or not recipe_data.hidden)

            button.visible = visible
            any_group_recipe_visible = any_group_recipe_visible or visible
        end

        group.frame.visible = any_group_recipe_visible
        any_recipe_visible = any_recipe_visible or any_group_recipe_visible

        local button_table_height = math.ceil(table_size(group.recipe_buttons) / recipes_per_row) * 36
        local additional_height = math.max(88, button_table_height + 24) + 4
        desired_scroll_pane_height = desired_scroll_pane_height + additional_height
    end

    modal_data.modal_elements.warning_label.visible = not any_recipe_visible

    local scroll_pane_height = math.min(desired_scroll_pane_height, modal_data.dialog_maximal_height)
    modal_data.modal_elements.content_frame.style.height = scroll_pane_height
end


local function handle_filter_change(player, tags, event)
    local boolean_state = ui_util.switch.convert_to_boolean(event.element.switch_state)
    data_util.get("modal_data", player).filters[tags.filter_name] = boolean_state
    data_util.get("preferences", player).recipe_filters[tags.filter_name] = boolean_state

    SEARCH_HANDLERS.apply_recipe_filter(player, "")
end


-- ** TOP LEVEL **
recipe_dialog.dialog_settings = (function(modal_data) return {
    caption = {"", {"fp.add"}, " ", {"fp.pl_recipe", 1}},
    subheader_text = {"fp.recipe_instruction", {"fp." .. modal_data.production_type},
      modal_data.product_proto.localised_name},
    search_handler_name = "apply_recipe_filter",
    create_content_frame = true
} end)

-- Checks whether the dialog needs to be created at all
function recipe_dialog.early_abort_check(player, modal_data)
    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local result, error, show = run_preliminary_checks(player, modal_data.product_proto, modal_data.production_type)

    if error ~= nil then
        title_bar.enqueue_message(player, error, "error", 1, false)
        return true  -- signal that the dialog does not need to actually be opened

    else
        -- If 1 relevant recipe is found, try it straight away
        if type(result) == "number" then  -- the given number being the recipe_id
            attempt_adding_line(player, result)
            return true  -- idem. above

        else  -- Otherwise, save the relevant data for the dialog opener
            modal_data.result = result
            modal_data.show = show
            return false  -- signal that the dialog should be opened
        end
    end
end

-- Handles populating the recipe dialog
function recipe_dialog.open(player, modal_data)
    -- At this point, we're sure the dialog should be opened
    local recipe_groups = {}
    for _, recipe in pairs(modal_data.result) do
        local group_name = recipe.proto.group.name
        recipe_groups[group_name] = recipe_groups[group_name] or {proto=recipe.proto.group, recipes={}}
        recipe_groups[group_name].recipes[recipe.proto.name] = recipe
    end

    modal_data.recipe_groups = recipe_groups
    modal_data.filters = modal_data.show.filters

    local translations = data_util.get("table", player).translation_tables
    create_dialog_structure(modal_data, translations)
    SEARCH_HANDLERS.apply_recipe_filter(player, "")
    modal_data.modal_elements.search_textfield.focus()

    -- Dispose of the temporary GUI-opening variables
    modal_data.result = nil
    modal_data.show = nil
end


-- ** EVENTS **
recipe_dialog.gui_events = {
    on_gui_click = {
        {
            name = "pick_recipe",
            timeout = 20,
            handler = (function(player, tags, _)
                attempt_adding_line(player, tags.recipe_proto_id)
                modal_dialog.exit(player, "cancel")
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
