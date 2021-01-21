utility_dialog = {}

-- ** LOCAL UTIL **
-- Adds a box with title and optional scope switch for the given type of utility
local function add_utility_box(player, modal_elements, type, show_tooltip, show_switch)
    local bordered_frame = modal_elements.content_frame.add{type="frame", direction="vertical",
      style="fp_frame_bordered_stretch"}
    modal_elements[type .. "_box"] = bordered_frame

    local flow_title_bar = bordered_frame.add{type="flow", direction="horizontal"}
    flow_title_bar.style.vertical_align = "center"
    flow_title_bar.style.margin = {2, 8, 4, 0}

    -- Title
    local caption = (show_tooltip) and {"fp.info_label", {"fp.utility_title_".. type}} or {"fp.utility_title_".. type}
    local tooltip = (show_tooltip) and {"fp.utility_title_" .. type .. "_tt"}
    local label_title = flow_title_bar.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}
    label_title.style.top_margin = -2

    -- Empty flow for custom controls
    flow_title_bar.add{type="empty-widget", style="flib_horizontal_pusher"}
    local flow_custom = flow_title_bar.add{type="flow"}
    flow_custom.style.right_margin = 12

    -- Scope switch
    local scope_switch = nil
    if show_switch then
        local utility_scope = data_util.get("preferences", player).utility_scopes[type]
        local switch_state = (utility_scope == "Subfactory") and "left" or "right"
        scope_switch = flow_title_bar.add{type="switch", tags={on_gui_switch_state_changed="utility_change_scope",
          utility_type=type}, switch_state=switch_state, left_label_caption={"fp.pu_subfactory", 1},
          right_label_caption={"fp.pu_floor", 1}}
    end

    return bordered_frame, flow_custom, scope_switch
end


local utility_structures = {}

local function update_request_button(player, modal_data, subfactory)
    local modal_elements = modal_data.modal_elements

    local button_enabled, switch_enabled = true, true
    local caption, tooltip, font_color = "", "", {}

    if subfactory.item_request_proxy ~= nil then
        caption = {"fp.cancel_request"}
        font_color = {0.8, 0, 0}
        switch_enabled = false

    else
        local scope = data_util.get("preferences", player).utility_scopes.components
        local scope_string = {"fp.pl_" .. scope:lower(), 1}
        caption, tooltip = {"fp.request_items"}, {"fp.request_items_tt", scope_string}

        if not player.force.character_logistic_requests then
            tooltip = {"fp.warning_with_icon", {"fp.request_logistics_not_researched"}}
            button_enabled = false
        elseif table_size(modal_data.missing_items) == 0 then
            tooltip = {"fp.warning_with_icon", {"fp.request_no_items_necessary", scope_string}}
            button_enabled = false
        end
    end

    modal_elements.request_button.caption = caption
    modal_elements.request_button.tooltip = tooltip
    modal_elements.request_button.style.font_color = font_color
    modal_elements.request_button.enabled = button_enabled
    modal_elements.scope_switch.enabled = switch_enabled
end

function utility_structures.components(player, modal_data)
    local scope = data_util.get("preferences", player).utility_scopes.components
    local lower_scope = scope:lower()
    local context = data_util.get("context", player)
    local modal_elements = modal_data.modal_elements

    if modal_elements.components_box == nil then
        local components_box, custom_flow, scope_switch = add_utility_box(player, modal_data.modal_elements,
          "components", true, true)
        modal_elements.components_box = components_box
        modal_elements.scope_switch = scope_switch

        local button_request = custom_flow.add{type="button", tags={on_gui_click="utility_request_items"},
          style="rounded_button", mouse_button_filter={"left"}}
        button_request.style.size = {115, 26}
        modal_elements.request_button = button_request

        local table_components = components_box.add{type="table", column_count=2}
        table_components.style.horizontal_spacing = 24
        table_components.style.vertical_spacing = 8

        local function add_component_row(type)
            local label = table_components.add{type="label", caption={"fp.pu_" .. type, 2}}
            label.style.font = "heading-3"

            local flow = table_components.add{type="flow", direction="horizontal"}
            modal_elements["components_" .. type .. "_flow"] = flow
        end

        add_component_row("machine")
        add_component_row("module")
    end


    local function refresh_component_flow(type)
        local component_row = modal_elements["components_" .. type .. "_flow"]
        component_row.clear()

        local inventory_contents = modal_data.inventory_contents
        local component_data = _G[scope].get_component_data(context[lower_scope], nil)

        local frame_components = component_row.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
        local table_components = frame_components.add{type="table", column_count=10, style="filter_slot_table"}

        for _, component in pairs(component_data[type .. "s"]) do
            if component.amount > 0 then
                local proto, required_amount = component.proto, component.amount
                local amount_in_inventory = inventory_contents[proto.name] or 0
                local missing_amount = required_amount - amount_in_inventory

                if missing_amount > 0 then modal_data.missing_items[proto.name] = missing_amount end

                local button_style = nil
                if amount_in_inventory == 0 then button_style = "flib_slot_button_red"
                elseif missing_amount > 0 then button_style = "flib_slot_button_yellow"
                else button_style = "flib_slot_button_green" end

                local tooltip = {"fp.components_needed_tt", proto.localised_name, amount_in_inventory, required_amount}

                table_components.add{type="sprite-button", sprite=proto.sprite, number=required_amount, tooltip=tooltip,
                  tags={on_gui_click="utility_craft_items", type=proto.type, name=proto.name,
                  missing_amount=missing_amount}, style=button_style, mouse_button_filter={"left-and-right"}}
            end
        end

        if #table_components.children_names == 0 then
            frame_components.visible = false
            local label = component_row.add{type="label", caption={"fp.no_components_needed", {"fp.pl_" .. type, 2}}}
            label.style.margin = {10, 0}
        end
    end

    modal_data.missing_items = {}  -- a flat structure works because there is no overlap between machines and modules
    refresh_component_flow("machine")
    refresh_component_flow("module")


    local subfactory = data_util.get("context", player).subfactory
    Subfactory.validate_item_request_proxy(subfactory)

    update_request_button(player, modal_data, subfactory)
end

function utility_structures.notes(player, modal_data)
    local utility_box = add_utility_box(player, modal_data.modal_elements, "notes", false, false)

    local notes = data_util.get("context", player).subfactory.notes
    local text_box = utility_box.add{type="text-box", tags={on_gui_text_changed="subfactory_notes"}, text=notes}
    text_box.style.size = {500, 250}
    text_box.word_wrap = true
    text_box.style.top_margin = -2
end


local function handle_scope_change(player, tags, metadata)
    local utility_scope = (metadata.switch_state == "left") and "Subfactory" or "Floor"
    data_util.get("preferences", player).utility_scopes[tags.utility_type] = utility_scope

    local modal_data = data_util.get("modal_data", player)
    utility_structures.components(player, modal_data)
end

local function handle_item_request(player, _, _)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    if subfactory.item_request_proxy then  -- if an item_proxy is set, cancel it
        Subfactory.destroy_item_request_proxy(subfactory)
    else
        -- This crazy way to request items actually works, and is way easier than setting logistic requests
        -- The advantage that is has is that the delivery is one-time, not a constant request
        -- The disadvantage is that it's weird to have construction bots bring you stuff
        subfactory.item_request_proxy = player.surface.create_entity{name="item-request-proxy",
          position=player.position, force=player.force, target=player.character,
          modules=ui_state.modal_data.missing_items}
    end

    update_request_button(player, ui_state.modal_data, subfactory)
end

local function handle_item_handcraft(player, tags, metadata)
    local recipes = RECIPE_MAPS["produce"][tags.type][tags.name]
    if not recipes then return end  -- no recipes craft this item

    local desired_amount = (metadata.click == "left") and 1 or 5
    local amount_to_craft = math.min(desired_amount, tags.missing_amount)

    for recipe_id, _ in pairs(recipes) do
        if amount_to_craft == 0 then break end

        local recipe_name = global.all_recipes.recipes[recipe_id].name
        local craftable_amount = player.get_craftable_count(recipe_name)

        if craftable_amount > 0 then
            local crafted_amount = math.min(amount_to_craft, craftable_amount)
            player.begin_crafting{count=crafted_amount, recipe=recipe_name}

            amount_to_craft = amount_to_craft - crafted_amount
        end
    end
end

local function handle_inventory_change(player)
    local ui_state = data_util.get("ui_state", player)

    if ui_state.modal_dialog_type == "utility" then
        ui_state.modal_data.inventory_contents = player.get_main_inventory().get_contents()
        utility_structures.components(player, ui_state.modal_data)
    end
end


-- ** TOP LEVEL **
utility_dialog.dialog_settings = (function(_) return {
    caption = {"fp.utilities"},
    create_content_frame = true
} end)

function utility_dialog.open(player, modal_data)
    -- Add the players' relevant inventory components to modal_data
    modal_data.inventory_contents = player.get_main_inventory().get_contents()

    utility_structures.components(player, modal_data)
    utility_structures.notes(player, modal_data)
end

function utility_dialog.close(player, _)
    main_dialog.refresh(player, "subfactory_info")
end


-- ** EVENTS **
utility_dialog.gui_events = {
    on_gui_click = {
        {
            name = "utility_request_items",
            timeout = 20,
            handler = handle_item_request
        },
        {
            name = "utility_craft_items",
            handler = handle_item_handcraft
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "utility_change_scope",
            handler = handle_scope_change
        }
    },
    on_gui_text_changed = {
        {
            name = "subfactory_notes",
            handler = (function(player, _, metadata)
                data_util.get("context", player).subfactory.notes = metadata.text
            end)
        }
    }
}

utility_dialog.misc_events = {
    on_player_main_inventory_changed = handle_inventory_change
}
