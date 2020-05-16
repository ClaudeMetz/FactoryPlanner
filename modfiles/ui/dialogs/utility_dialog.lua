-- Handles populating the utility modal dialog
function open_utility_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"fp.utilities"}
    local context = get_context(game.get_player(flow_modal_dialog.player_index))
    
    refresh_utility_components_structure(flow_modal_dialog, context)
    create_utility_notes_structure(flow_modal_dialog, context)
end


-- Adds a titlebar for the given type of utility, optionally including a scope switch
local function add_utility_titlebar(flow, type, tooltip, scope, context)
    local flow_titlebar = flow.add{type="flow", name="flow_titlebar", direction="horizontal"}
    flow_titlebar.style.vertical_align = "center"

    -- Title
    local info = (tooltip) and " [img=info]" or ""
    local tt = (tooltip) and {"fp.type_" .. type .. "_tt"} or ""
    local label_title = flow_titlebar.add{type="label", caption={("fp.type_" .. type), ":", info}, tooltip=tt}
    label_title.style.font = "fp-font-semibold-16p"
    label_title.style.left_margin = 6

    -- Scope switch
    if scope then
        local spacer = flow_titlebar.add{type="flow", direction="horizontal"}
        spacer.style.horizontally_stretchable = true

        local state = Subfactory.get_scope(context.subfactory, type, true)
        local switch = flow_titlebar.add{type="switch", name=("fp_switch_utility_scope_" .. type), switch_state=state,
          left_label_caption={"fp.csubfactory"}, right_label_caption={"fp.floor"}}
    end
end

-- Refreshes the flow displaying the appropriate subfactory/floor components
function refresh_utility_components_structure(flow_modal_dialog, context)
    local flow = flow_modal_dialog["flow_components"]
    if flow == nil then
        flow = flow_modal_dialog.add{type="flow", name="flow_components", direction="vertical"}
        flow.style.bottom_margin = 12
        add_utility_titlebar(flow, "components", true, true, context)
        flow.add{type="table", name="table_components", column_count=2}
    end

    local table = flow["table_components"]
    table.style.margin = {6, 0, 0, 6}
    table.style.horizontal_spacing = 12
    table.style.vertical_spacing = 8
    table.clear()

    local function add_row(name, data)
        local label = table.add{type="label", caption={"", {"fp.c" .. name}, ":"}}
        label.style.font = "default-bold"
        
        local table_components = table.add{type="table", column_count=10}
        for _, component in pairs(data) do
            if component.amount > 0 then
                local singular_name = name:sub(1, -2)
                local component_text = (component.amount == 1) and {"fp." .. singular_name} or {"fp." .. name}
                local tooltip = {"", component.proto.localised_name, "\n" ..
                  ui_util.format_number(component.amount, 4) .. " ", component_text}

                local button = table_components.add{type="sprite-button", name=("sprite-button_" ..
                  component.proto.name), sprite=component.proto.sprite, tooltip=tooltip,
                  style="fp_button_icon_medium_blank", number=component.amount, enabled=false}
            end
        end

        if table_size(table_components.children_names) == 0 then
            table_components.add{type="label", caption={"fp.no_components", {"fp." .. name}}}
        end
    end

    local scope = Subfactory.get_scope(context.subfactory, "components", false)
    local data = _G[scope].get_component_data(context[scope:lower()], nil)

    add_row("machines", data.machines)
    add_row("modules", data.modules)    
end

-- Creates the flow containing this subfactories notes
function create_utility_notes_structure(flow_modal_dialog, context)
    local flow = flow_modal_dialog.add{type="flow", name="flow_notes", direction="vertical"}

    add_utility_titlebar(flow, "notes", false, false, context)
    
    local text_box = flow.add{type="text-box", name="fp_text-box_notes", text=context.subfactory.notes}
    text_box.style.width = 500
    text_box.style.height = 250
    text_box.word_wrap = true
end


-- Handles the changing of the given scope by the user
function handle_utility_scope_change(player, type, state)
    local context = get_context(player)
    Subfactory.set_scope(context.subfactory, type, state)

    local flow_modal_dialog = ui_util.find_modal_dialog(player)["flow_modal_dialog"]
    _G["refresh_utility_" .. type .. "_structure"](flow_modal_dialog, context)
end

-- Handles changes to the subfactory notes
function handle_notes_change(player, textbox)
    local subfactory = get_context(player).subfactory
    subfactory.notes = textbox.text
    refresh_utility_table(player, subfactory)
end