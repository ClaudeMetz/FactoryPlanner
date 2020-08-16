recipe_dialog = {}

local recipes_per_row = 6

-- ** LOCAL UTIL **
-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter and, if there
-- is only one that matches, to return a recipe name that can be added directly without the modal dialog
local function run_preliminary_checks(player, product, production_type)
    local force_recipes, force_technologies = player.force.recipes, player.force.technologies
    local preferences = data_util.get("preferences", player)

    local relevant_recipes = {}
    local user_disabled_recipe = false
    local counts = {disabled = 0, hidden = 0, disabled_hidden = 0}

    local map = RECIPE_MAPS[production_type][product.proto.type][product.proto.name]
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
        return nil, error, show

    elseif relevant_recipes_count == 1 then
        local chosen_recipe = relevant_recipes[1]
        if not chosen_recipe.enabled then  -- Show warning if adding unresearched recipe
            show.message={text={"fp.warning_disabled_recipe"}, type="warning"}
        end
        return chosen_recipe.proto.id, nil, show

    else  -- 2+ relevant recipes
        return relevant_recipes, nil, show
    end
end

-- Tries to add the given recipe to the current floor, then exiting the modal dialog
local function attempt_adding_line(player, recipe_id)
    local ui_state = data_util.get("ui_state", player)

    local line = Line.init(Recipe.init_by_id(recipe_id, ui_state.modal_data.production_type))
    -- If changing the machine fails, this line is invalid
    if Line.change_machine(line, player, nil, nil) == false then
        titlebar.enqueue_message(player, {"fp.error_no_compatible_machine"}, "error", 1)

    else
        local add_after_position = ui_state.modal_data.add_after_position
        -- If add_after_position is given, insert it below that one, add it to the end otherwise
        if add_after_position == nil then
            Floor.add(ui_state.context.floor, line)
        else
            Floor.insert_at(ui_state.context.floor, (add_after_position + 1), line)
        end

        local message = ui_state.modal_data.message
        local preferences = data_util.get("preferences", player)
        local mb_defaults = preferences.mb_defaults

        -- Add default machine modules, if desired by the user
        local machine_module = mb_defaults.machine
        if machine_module ~= nil then
            if Machine.check_module_compatibility(line.machine, machine_module) then
                local new_module = Module.init_by_proto(machine_module, line.machine.proto.module_limit)
                Machine.add(line.machine, new_module)

            elseif message == nil then  -- don't overwrite previous message, if it exists
                message = {text={"fp.warning_module_not_compatible", {"fp.pl_module", 1}}, type="warning"}
            end
        end

        -- Add default beacon modules, if desired by the user
        local beacon_module_proto, beacon_count = mb_defaults.beacon, mb_defaults.beacon_count
        local beacon_proto = prototyper.defaults.get(player, "beacons")  -- this will always exist

        if beacon_module_proto ~= nil and beacon_count ~= nil then
            local blank_beacon = Beacon.blank_init(beacon_proto, beacon_count, line)

            if Beacon.check_module_compatibility(blank_beacon, beacon_module_proto) then
                local module = Module.init_by_proto(beacon_module_proto, beacon_proto.module_limit)
                Beacon.set_module(blank_beacon, module)

                Line.set_beacon(line, blank_beacon)

            elseif message == nil then  -- don't overwrite previous message, if it exists
                message = {text={"fp.warning_module_not_compatible", {"fp.pl_beacon", 1}}, type="warning"}
            end
        end

        if message ~= nil then titlebar.enqueue_message(player, message.text, message.type, 2) end
        calculation.update(player, ui_state.context.subfactory, true)
    end

    modal_dialog.exit(player, "cancel")
end


local function create_filter_box(modal_data)
    local bordered_frame = modal_data.ui_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}

    local table_filters = bordered_frame.add{type="table", column_count=2}
    table_filters.style.horizontal_spacing = 16

    local label_filters = table_filters.add{type="label", caption={"fp.show"}}
    label_filters.style.top_margin = 2
    label_filters.style.left_margin = 4

    local flow_filter_switches = table_filters.add{type="flow", direction="vertical"}
    ui_util.switch.add_on_off(flow_filter_switches, "recipe_filter_disabled", modal_data.filters.disabled,
      {"fp.unresearched_recipes"}, nil, false)
    ui_util.switch.add_on_off(flow_filter_switches, "recipe_filter_hidden", modal_data.filters.hidden,
      {"fp.hidden_recipes"}, nil, false)
end

local function create_recipe_group_box(modal_data, relevant_group)
    local ui_elements = modal_data.ui_elements
    local bordered_frame = ui_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}
    bordered_frame.style.padding = 8

    local next_index = #ui_elements.groups + 1
    ui_elements.groups[next_index] = {name=relevant_group.proto.name, frame=bordered_frame, recipe_buttons={}}
    local recipe_buttons = ui_elements.groups[next_index].recipe_buttons

    local flow_group = bordered_frame.add{type="flow", direction="horizontal"}
    flow_group.style.vertical_align = "center"

    local group_sprite = flow_group.add{type="sprite-button", sprite=("item-group/" .. relevant_group.proto.name),
      tooltip=relevant_group.proto.localised_name, style="transparent_slot"}
    group_sprite.style.height = 64
    group_sprite.style.width = 64
    group_sprite.style.right_margin = 12

    local frame_recipes = flow_group.add{type="frame", direction="horizontal", style="fp_frame_deep_slots_small"}
    local table_recipes = frame_recipes.add{type="table", column_count=recipes_per_row, style="filter_slot_table"}

    for _, recipe in pairs(relevant_group.recipes) do
        local recipe_proto = recipe.proto

        local style = "flib_slot_button_green"
        if not recipe.enabled then style = "flib_slot_button_yellow"
        elseif recipe_proto.hidden then style = "flib_slot_button_default" end

        local button_name = "fp_button_recipe_pick_" .. recipe_proto.id
        local button_recipe

        if recipe_proto.custom then  -- can't use choose-elem-buttons for custom recipes
            button_recipe = table_recipes.add{type="sprite-button", name=button_name, style=style,
              sprite=recipe_proto.sprite, tooltip=recipe_proto.tooltip, mouse_button_filter={"left"}}
        else
            button_recipe = table_recipes.add{type="choose-elem-button", elem_type="recipe", name=button_name,
              style=style, recipe=recipe_proto.name, mouse_button_filter={"left"}}
            button_recipe.locked = true
        end

        button_recipe.style.height = 36
        button_recipe.style.width = 36
        table.insert(recipe_buttons, {name=recipe_proto.name, button=button_recipe})
    end
end

-- Creates the unfiltered recipe structure
local function create_dialog_structure(modal_data)
    local ui_elements = modal_data.ui_elements
    local content_frame = ui_elements.content_frame
    content_frame.style.width = 380

    create_filter_box(modal_data)

    local label_warning = content_frame.add{type="label", caption={"fp.error_message", {"fp.no_recipe_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = {8, 0, 0, 8}
    ui_elements.warning_label = label_warning

    ui_elements.groups = {}
    for _, group in ipairs(ORDERED_RECIPE_GROUPS) do
        local relevant_group = modal_data.recipe_groups[group.name]

        -- Only actually create this group if it contains any relevant recipes
        if relevant_group ~= nil then create_recipe_group_box(modal_data, relevant_group) end
    end
end

-- Filters the current recipes according to the filters that have been set
local function apply_recipe_filter(player)
    local modal_data = data_util.get("modal_data", player)
    local disabled, hidden = modal_data.filters.disabled, modal_data.filters.hidden

    local any_recipe_visible, desired_scroll_pane_height = false, 72+24
    for _, group in ipairs(modal_data.ui_elements.groups) do
        local group_data = modal_data.recipe_groups[group.name]
        local any_group_recipe_visible = false

        for _, recipe in pairs(group.recipe_buttons) do
            local recipe_data = group_data.recipes[recipe.name]

            -- Boolean algebra is reduced here; to understand the intended meaning, take a look at this:
            local visible = (disabled or recipe_data.enabled) and (hidden or not recipe_data.proto.hidden)

            recipe.button.visible = visible
            any_group_recipe_visible = any_group_recipe_visible or visible
        end

        group.frame.visible = any_group_recipe_visible
        any_recipe_visible = any_recipe_visible or any_group_recipe_visible

        local button_table_height = math.ceil(#group.recipe_buttons / recipes_per_row) * 36
        local additional_height = math.max(88, button_table_height + 24) + 4
        desired_scroll_pane_height = desired_scroll_pane_height + additional_height
    end

    modal_data.ui_elements.warning_label.visible = not any_recipe_visible

    local scroll_pane_height = math.min(desired_scroll_pane_height, modal_data.dialog_maximal_height)
    modal_data.ui_elements.content_frame.style.height = scroll_pane_height
end


local function handle_filter_change(player, element)
    local filter_name = string.gsub(element.name, "fp_switch_recipe_filter_", "")
    local boolean_state = ui_util.switch.convert_to_boolean(element.switch_state)

    data_util.get("modal_data", player).filters[filter_name] = boolean_state
    data_util.get("preferences", player).recipe_filters[filter_name] = boolean_state

    apply_recipe_filter(player)
end


-- ** TOP LEVEL **
recipe_dialog.dialog_settings = (function(_) return {
    caption = {"fp.two_word_title", {"fp.add"}, {"fp.pl_recipe", 1}},
    create_content_frame = true,
    force_auto_center = true
} end)

recipe_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_button_recipe_pick_%d+$",
            timeout = 20,
            handler = (function(player, element, _)
                local recipe_id = tonumber(string.match(element.name, "%d+"))
                attempt_adding_line(player, recipe_id)
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            pattern = "^fp_switch_recipe_filter_[a-z]+$",
            handler = (function(player, element)
                handle_filter_change(player, element)
            end)
        }
    }
}


-- Handles populating the recipe dialog
function recipe_dialog.open(player, modal_data)
    local product = modal_data.product

    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local result, error, show = run_preliminary_checks(player, product, modal_data.production_type)

    if error ~= nil then
        titlebar.enqueue_message(player, error, "error", 1)
        modal_dialog.exit(player, "cancel")
        return true  -- let the modal dialog know that it was closed immediately

    else
        -- If 1 relevant recipe is found, add it immediately and exit dialog
        if type(result) == "number" then  -- the given number being the recipe_id
            modal_data.message = show.message
            attempt_adding_line(player, result)
            return true  -- idem above

        else  -- Otherwise, show the appropriately filtered dialog
            local recipe_groups = {}
            for _, recipe in pairs(result) do
                local group_name = recipe.proto.group.name
                recipe_groups[group_name] = recipe_groups[group_name] or {proto=recipe.proto.group, recipes={}}
                recipe_groups[group_name].recipes[recipe.proto.name] = recipe
            end

            modal_data.recipe_groups = recipe_groups
            modal_data.filters = show.filters

            create_dialog_structure(modal_data)
            apply_recipe_filter(player)
        end
    end
end