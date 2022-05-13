solver_dialog = {}

-- ** LOCAL UTIL **
local function determine_relevant_items(subfactory)
    local relevant_items = {item = {}, fluid = {}}
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_all(floor, "Line")) do
            if line.subfloor == nil then
                for _, item_type in pairs({"products", "ingredients"}) do
                    for _, item in pairs(line.recipe.proto[item_type]) do
                        if item.type ~= "entity" then
                            relevant_items[item.type][item.name] = true
                        end
                    end
                end
            end
        end
    end
    return relevant_items
end

local function add_cost_line(parent, type, name, cost, default)
    local flow = parent.add{type="flow", direction="horizontal"}

    local sprite = flow.add{type="sprite", sprite=(type .. "/" .. name), tooltip={type .. "-name." .. name}}
    sprite.resize_to_sprite = false
    sprite.style.size = 32

    local textfield = flow.add{type="textfield", text=(cost or default), name="textfield_cost",
      tags={mod="fp", on_gui_text_changed="solver_cost", name=name, type=type, default=default}}
    textfield.style.width = 60
    ui_util.setup_numeric_textfield(textfield, false, false)

    local enabled = (cost~=nil and cost~=default)
    flow.add{type="sprite-button", sprite="utility/refresh", name="button_reset_cost", style="tool_button",
      tooltip={"fp.solver_reset_cost"}, tags={mod="fp", on_gui_click="reset_cost"}, enabled=enabled,
      mouse_button_filter={"left"}}
end


-- ** TOP LEVEL **
solver_dialog.dialog_settings = (function(_)
    return {
        caption = {"fp.solver_dialog_caption"},
        subheader_text = {"fp.solver_dialog_description"},
        create_content_frame = true,
        show_submit_button = true
    }
end)

function solver_dialog.open(player, modal_data)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory
    local relevant_items = determine_relevant_items(subfactory)

    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local table_items = content_frame.add{type="table", column_count=3}
    table_items.style.horizontal_spacing = 32
    table_items.style.vertical_spacing = 12
    modal_elements["items_table"] = table_items

    local default_costs = DEFAULT_SOLVER_COSTS
    for type, items in pairs(relevant_items) do
        for name, _ in pairs(items) do
            local cost = subfactory.solver_costs[type][name]
            local default = nil
            if name == "water" then default = default_costs.water
            elseif type == "fluid" then default = default_costs.fluid
            else default = default_costs.item end
            add_cost_line(table_items, type, name, cost, default)
        end
    end
end

function solver_dialog.close(player, action)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    if action == "submit" then
        local table_items = ui_state.modal_data.modal_elements.items_table
        local solver_costs = {item = {}, fluid = {}}

        for _, flow in pairs(table_items.children) do
            local tags = flow["textfield_cost"].tags
            local cost = tonumber(flow["textfield_cost"].text)
            if tags.default ~= cost then
                solver_costs[tags.type][tags.name] = cost
            end
        end

        subfactory.solver_costs = solver_costs
    end
end


-- ** EVENTS **
solver_dialog.gui_events = {
    on_gui_text_changed = {
        {
            name = "solver_cost",
            handler = (function(_, _, event)
                local cost = tonumber(event.element.text)
                local button = event.element.parent["button_reset_cost"]
                button.enabled = (cost ~= button.tags.default)
            end)
        }
    },
    on_gui_click = {
        {
            name = "reset_cost",
            handler = (function(_, _, event)
                local textfield = event.element.parent["textfield_cost"]
                textfield.text = tostring(textfield.tags.default)
                event.element.enabled = false
            end)
        }
    }
}
