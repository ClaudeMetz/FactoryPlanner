-- Handles populating the utility modal dialog
function open_utility_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"fp.utilities"}
    
    refresh_utility_components_structure(flow_modal_dialog)
    create_utility_notes_structure(flow_modal_dialog)
end

-- Handles closing of the utility dialog
function close_utility_dialog(flow_modal_dialog, action, data)
    if action == "submit" then
        local player = game.get_player(flow_modal_dialog.player_index)
        get_context(player).subfactory.notes = data.notes
    end
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_utility_condition_instructions()
    return {
        data = {
            notes = (function(flow_modal_dialog) return flow_modal_dialog["flow_notes"]["text-box_notes"].text end)
        },
        conditions = nil
    }
end

-- Adds a titlebar for the given type of utility, optionally including a scope switch
local function add_utility_titlebar(flow, type, tooltip, scope)
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

        local context = get_context(game.get_player(flow.player_index))
        local state = Subfactory.get_scope(context.subfactory, type, true)
        local switch = flow_titlebar.add{type="switch", name=("fp_switch_utility_scope_" .. type), switch_state=state,
          left_label_caption={"fp.csubfactory"}, right_label_caption={"fp.floor"}}
    end
end

-- Handles the changing of the given scope by the user
function handle_utility_scope_change(player, type, state)
    Subfactory.set_scope(get_context(player).subfactory, type, state)

    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    _G["refresh_utility_" .. type .. "_structure"](flow_modal_dialog)
end


-- Refreshes the flow displaying the appropriate subfactory/floor components
function refresh_utility_components_structure(flow_modal_dialog)
    local flow = flow_modal_dialog["flow_components"]
    if flow == nil then
        flow = flow_modal_dialog.add{type="flow", name="flow_components", direction="vertical"}
        flow.style.bottom_margin = 12
        add_utility_titlebar(flow, "components", true, true)
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
                local button = table_components.add{type="sprite-button", name=("sprite-button_" ..
                  component.proto.name), sprite=component.proto.sprite, tooltip=component.proto.localised_name,
                  style="fp_button_icon_medium_blank", enabled=false}
                button.number = component.amount
            end
        end

        if table_size(table_components.children_names) == 0 then
            table_components.add{type="label", caption={"fp.no_components", {"fp." .. name}}}
        end
    end

    local context = get_context(game.get_player(flow_modal_dialog.player_index))
    local scope = Subfactory.get_scope(context.subfactory, "components", false)
    local data = _G[scope].get_component_data(context[scope:lower()], nil)

    add_row("machines", data.machines)
    add_row("modules", data.modules)    
end

-- Creates the flow containing this subfactories notes
function create_utility_notes_structure(flow_modal_dialog)
    local flow = flow_modal_dialog.add{type="flow", name="flow_notes", direction="vertical"}

    add_utility_titlebar(flow, "notes", false, false)
    
    local subfactory = get_context(game.get_player(flow_modal_dialog.player_index)).subfactory
    local text_box = flow.add{type="text-box", name="text-box_notes", text=subfactory.notes}
    text_box.style.width = 500
    text_box.style.height = 250
    text_box.word_wrap = true
end