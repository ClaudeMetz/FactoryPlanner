utility_dialog = {}

-- ** LOCAL UTIL **
-- Adds a box with title and optional scope switch for the given type of utility
local function add_utility_box(player, ui_elements, type, show_tooltip, show_switch)
    local bordered_frame = ui_elements.content_frame.add{type="frame", direction="vertical", style="bordered_frame"}
    bordered_frame.style.bottom_margin = 6
    ui_elements[type .. "_box"] = bordered_frame

    local flow_titlebar = bordered_frame.add{type="flow", direction="horizontal"}
    flow_titlebar.style.vertical_align = "center"
    flow_titlebar.style.margin = {2, 8, 4, 0}

    -- Title
    local caption = (show_tooltip) and {"fp.info_label", {"fp.utility_title_".. type}} or {"fp.utility_title_".. type}
    local tooltip = (show_tooltip) and {"fp.utility_title_" .. type .. "_tt"}
    local label_title = flow_titlebar.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}
    label_title.style.top_margin = -2

    -- Scope switch
    if show_switch then
        flow_titlebar.add{type="empty-widget", style="flib_horizontal_pusher"}

        local utility_scope = data_util.get("preferences", player).utility_scopes[type]
        local switch_state = (utility_scope == "Subfactory") and "left" or "right"
        flow_titlebar.add{type="switch", name=("fp_switch_utility_scope_" .. type), switch_state=switch_state,
          left_label_caption={"fp.pu_subfactory", 1}, right_label_caption={"fp.pu_floor", 1}}
    end

    return bordered_frame
end


local utility_structures = {}

function utility_structures.components(player, modal_data)
    local scope = data_util.get("preferences", player).utility_scopes.components
    local context = data_util.get("context", player)
    local ui_elements = modal_data.ui_elements

    if ui_elements.components_box == nil then
        ui_elements.components_box = add_utility_box(player, modal_data.ui_elements, "components", true, true)

        local table_components = ui_elements.components_box.add{type="table", column_count=2}
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
        local component_data = _G[scope].get_component_data(context[scope:lower()], nil)

        local frame_components = component_row.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
        local table_components = frame_components.add{type="table", column_count=10, style="filter_slot_table"}

        for _, component in pairs(component_data[type .. "s"]) do
            if component.amount > 0 then
                local amount_in_inventory = inventory_contents[component.proto.name] or 0
                local button_style = nil

                if amount_in_inventory == 0 then button_style = "flib_slot_button_red"
                elseif amount_in_inventory < component.amount then button_style = "flib_slot_button_yellow"
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

    refresh_component_flow("machine")
    refresh_component_flow("module")
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


-- ** TOP LEVEL **
utility_dialog.dialog_settings = (function(_) return {
    caption = {"fp.utilities"}
} end)

utility_dialog.events = {
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
    },
}

function utility_dialog.open(player, _, modal_data)
    -- Add the players' relevant inventory components to modal_data
    modal_data.inventory_contents = player.get_main_inventory().get_contents()

    local ui_elements = modal_data.ui_elements
    ui_elements.content_frame = ui_elements.flow_modal_dialog.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}
    ui_elements.content_frame.style.bottom_padding = 6

    utility_structures.components(player, modal_data)
    utility_structures.notes(player, modal_data)
end

function utility_dialog.close(player, _, _)
    local subfactory = data_util.get("context", player).subfactory
    info_pane.refresh_utility_table(player, subfactory)
end