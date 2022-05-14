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

local function add_cost_line(parent, type, name, constraints, default_cost)
    local flow = parent.add{type="flow", direction="horizontal", tags={name=name, type=type}}

    local sprite = flow.add{type="sprite", sprite=(type .. "/" .. name), tooltip={type .. "-name." .. name}}
    sprite.resize_to_sprite = false
    sprite.style.size = 32

    local allow_ingredient = false
    if constraints.allow_ingredient ~= nil then allow_ingredient = constraints.allow_ingredient end
    local ingredient_style = (allow_ingredient) and "flib_selected_tool_button" or "tool_button"
    flow.add{type="button", name="button_allow_ingredient", caption="I", style=ingredient_style,
      tags={mod="fp", on_gui_click="toggle_allow", allow=allow_ingredient},
      tooltip={"fp.solver_allow_as_ingredient"}, mouse_button_filter={"left"}}

    local allow_byproduct = true
    if constraints.allow_byproduct ~= nil then allow_byproduct = constraints.allow_byproduct end
    local byproduct_style = (allow_byproduct) and "flib_selected_tool_button" or "tool_button"
    flow.add{type="button", name="button_allow_byproduct", caption="B", style=byproduct_style,
      tags={mod="fp", on_gui_click="toggle_allow", allow=allow_byproduct},
      tooltip={"fp.solver_allow_as_byproduct"}, mouse_button_filter={"left"}}

    local cost = constraints.cost
    local textfield = flow.add{type="textfield", text=(cost or default_cost), name="textfield_cost",
      tags={mod="fp", on_gui_text_changed="solver_cost", default_cost=default_cost}}
    textfield.style.width = 60
    ui_util.setup_numeric_textfield(textfield, false, false)

    local enabled = (cost~=nil and cost~=default_cost)
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
            local constraints = subfactory.solver_costs[type][name] or {}
            local default = nil
            if name == "water" then default = default_costs.water
            elseif type == "fluid" then default = default_costs.fluid
            else default = default_costs.item end
            add_cost_line(table_items, type, name, constraints, default)
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
            local default_cost = flow["textfield_cost"].tags.default_cost
            local cost = tonumber(flow["textfield_cost"].text)
            local allow_ingredient = flow["button_allow_ingredient"].tags.allow
            local allow_byproduct = flow["button_allow_byproduct"].tags.allow

            local constraints = { cost = (default_cost ~= cost) and cost or nil }
            -- Only set these when they are different than their default
            if allow_ingredient then constraints.allow_ingredient = true end
            if not allow_byproduct then constraints.allow_byproduct = false end

            if table_size(constraints) > 0 then
                solver_costs[flow.tags.type][flow.tags.name] = constraints
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
        },
        {
            name = "toggle_allow",
            handler = (function(_, tags, event)
                tags.allow = not tags.allow
                event.element.tags = tags  -- one has to write the whole table
                event.element.style = (tags.allow) and "flib_selected_tool_button" or "tool_button"
            end)
        }
    }
}
