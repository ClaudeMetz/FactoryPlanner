utility_dialog = {}

-- ** LOCAL UTIL **
-- Adds a box with title and optional scope switch for the given type of utility
local function add_utility_box(player, ui_elements, type, show_tooltip, show_switch)
    local bordered_frame = ui_elements.content_frame.add{type="frame", direction="vertical", style="bordered_frame"}
    ui_elements[type .. "_box"] = bordered_frame

    local flow_titlebar = bordered_frame.add{type="flow", direction="horizontal"}
    flow_titlebar.style.vertical_align = "center"
    flow_titlebar.style.margin = {2, 8, 4, 0}

    -- Title
    local caption = (show_tooltip) and {"fp.info_label", {"fp.utility_title_".. type}} or {"fp.utility_title_".. type}
    local tooltip = (show_tooltip) and {"fp.utility_title_" .. type .. "_tt"}
    local label_title = flow_titlebar.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}
    label_title.style.top_margin = -2

    -- Empty flow for custom controls
    flow_titlebar.add{type="empty-widget", style="flib_horizontal_pusher"}
    local flow_custom = flow_titlebar.add{type="flow"}
    flow_custom.style.right_margin = 12

    -- Scope switch
    local scope_switch = nil
    if show_switch then
        local utility_scope = data_util.get("preferences", player).utility_scopes[type]
        local switch_state = (utility_scope == "Subfactory") and "left" or "right"
        scope_switch = flow_titlebar.add{type="switch", name=("fp_switch_utility_scope_" .. type),
          switch_state=switch_state, left_label_caption={"fp.pu_subfactory", 1}, right_label_caption={"fp.pu_floor", 1}}
    end

    return bordered_frame, flow_custom, scope_switch
end


local utility_structures = {}

local function update_request_button(player, modal_data, subfactory)
    local ui_elements = modal_data.ui_elements

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
        local logistics_research = player.force.technologies["logistic-robotics"]

        if not logistics_research.researched then
            tooltip = {"fp.request_logistics_not_researched", logistics_research.localised_name}
            button_enabled = false
        elseif table_size(modal_data.missing_items) == 0 then
            tooltip = {"fp.request_no_items_necessary", scope_string}
            button_enabled = false
        end
    end

    ui_elements.request_button.caption = caption
    ui_elements.request_button.tooltip = tooltip
    ui_elements.request_button.style.font_color = font_color
    ui_elements.request_button.enabled = button_enabled
    ui_elements.scope_switch.enabled = switch_enabled
end

function utility_structures.components(player, modal_data)
    local scope = data_util.get("preferences", player).utility_scopes.components
    local lower_scope = scope:lower()
    local context = data_util.get("context", player)
    local ui_elements = modal_data.ui_elements

    if ui_elements.components_box == nil then
        local components_box, custom_flow, scope_switch = add_utility_box(player, modal_data.ui_elements,
          "components", true, true)
        ui_elements.components_box = components_box
        ui_elements.scope_switch = scope_switch

        local button_request = custom_flow.add{type="button", name="fp_button_utility_request_items",
          style="rounded_button", mouse_button_filter={"left"}}
        button_request.style.width = 115
        button_request.style.height = 26
        ui_elements.request_button = button_request

        local table_components = components_box.add{type="table", column_count=2}
        table_components.style.horizontal_spacing = 24
        table_components.style.vertical_spacing = 8

        local function add_component_row(type)
            local label = table_components.add{type="label", caption={"fp.pu_" .. type, 2}}
            label.style.font = "heading-3"

            local flow = table_components.add{type="flow", direction="horizontal"}
            ui_elements["components_" .. type .. "_flow"] = flow
        end

        add_component_row("machine")
        add_component_row("module")
    end


    local function refresh_component_flow(type)
        local component_row = ui_elements["components_" .. type .. "_flow"]
        component_row.clear()

        local inventory_contents = modal_data.inventory_contents
        local component_data = _G[scope].get_component_data(context[lower_scope], nil)

        local frame_components = component_row.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
        local table_components = frame_components.add{type="table", column_count=10, style="filter_slot_table"}

        for _, component in pairs(component_data[type .. "s"]) do
            if component.amount > 0 then
                local amount_in_inventory = inventory_contents[component.proto.name] or 0
                local amount_missing = component.amount - amount_in_inventory

                if amount_missing > 0 then modal_data.missing_items[component.proto.name] = amount_missing end

                local button_style = nil
                if amount_in_inventory == 0 then button_style = "flib_slot_button_red"
                elseif amount_missing > 0 then button_style = "flib_slot_button_yellow"
                else button_style = "flib_slot_button_green" end

                local second_line = {"fp.components_needed_tt", amount_in_inventory, component.amount}
                local tooltip = {"", component.proto.localised_name, "\n", second_line}

                table_components.add{type="sprite-button", sprite=component.proto.sprite, number=component.amount,
                  tooltip=tooltip, style=button_style, mouse_button_filter={"middle"}}
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
    local utility_box = add_utility_box(player, modal_data.ui_elements, "notes", false, false)

    local notes = data_util.get("context", player).subfactory.notes
    local text_box = utility_box.add{type="text-box", name="fp_text-box_subfactory_notes", text=notes}
    text_box.style.width = 500
    text_box.style.height = 250
    text_box.word_wrap = true
    text_box.style.top_margin = -2
end


local function handle_scope_change(player, element)
    local scope_type = string.gsub(element.name, "fp_switch_utility_scope_", "")
    local utility_scope = (element.switch_state == "left") and "Subfactory" or "Floor"
    data_util.get("preferences", player).utility_scopes[scope_type] = utility_scope
    utility_structures.components(player, data_util.get("modal_data", player))
end

local function handle_item_request(player)
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

utility_dialog.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_utility_request_items",
            timeout = 20,
            handler = (function(player, _, _)
                handle_item_request(player)
            end)
        }
    },
    on_gui_switch_state_changed = {
        {
            pattern = "^fp_switch_utility_scope_[a-z]+$",
            handler = (function(player, element)
                handle_scope_change(player, element)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_text-box_subfactory_notes",
            handler = (function(player, element)
                data_util.get("context", player).subfactory.notes = element.text
            end)
        }
    }
}

utility_dialog.misc_events = {
    on_player_main_inventory_changed = (function(player, _)
        handle_inventory_change(player)
    end)
}

function utility_dialog.open(player, modal_data)
    -- Add the players' relevant inventory components to modal_data
    modal_data.inventory_contents = player.get_main_inventory().get_contents()

    utility_structures.components(player, modal_data)
    utility_structures.notes(player, modal_data)
end

function utility_dialog.close(player, _)
    local subfactory = data_util.get("context", player).subfactory
    info_pane.refresh_utility_table(player, subfactory)
end