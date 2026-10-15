quality_selector = {}


---@class SelectQualityTags
---@field proto_name string

---@alias QualitySelectorModalData PickerDialogModalData|RecipeDialogModalData

---@param parent LuaGuiElement
---@param modal_data QualitySelectorModalData
function quality_selector.add_flow(parent, modal_data)
    if not QUALITY_ENABLED then return end

    local flow = parent.add{type = "flow", direction = "horizontal"}
    local buttons = {}  ---@type table<string, LuaGuiElement>
    flow.style.horizontal_spacing = 0

    for _, proto in ipairs(storage.prototypes.qualities) do
        local button = flow.add{
            type = "sprite-button",
            style = "tool_button",
            sprite = proto.sprite,
            tooltip = {"", {"fp.quality"}, ": ", proto.localised_name},
            tags = {mod = "fp", on_gui_click = "select_quality", proto_name = proto.name}  ---@type SelectQualityTags
        }
        buttons[proto.name] = button
    end

    modal_data.modal_elements.quality_buttons = buttons
    quality_selector.refresh_element(modal_data)
end

---@param modal_data QualitySelectorModalData
function quality_selector.refresh_element(modal_data)
    if not QUALITY_ENABLED then return end

    local buttons = modal_data.modal_elements.quality_buttons  ---@type table<string, LuaGuiElement>
    local enabled = true

    if modal_data.item_proto and modal_data.item_proto.type ~= "item" 
            or modal_data.recipe_proto and not modal_data.recipe_proto.can_set_quality then
        modal_data.quality_proto = nil
        enabled = false
    elseif not modal_data.quality_proto then
        modal_data.quality_proto = defaults.get_fallback("qualities").proto  ---@as FPQualityPrototype
    end

    for _, button in pairs(buttons) do
        button.enabled = enabled
        button.toggled = false
    end

    local item_button = modal_data.modal_elements.item_choice_button  ---@type LuaGuiElement?
    if modal_data.quality_proto then
        buttons[modal_data.quality_proto.name].toggled = true
        if item_button then item_button.quality = modal_data.quality_proto.name end
    else
        if item_button then item_button.quality = nil end
    end
end

---@param player LuaPlayer
---@param tags Tags
local function handle_select_quality(player, tags, _)
    ---@cast tags SelectQualityTags
    local modal_data = lib.globals.modal_data(player)  ---@as QualitySelectorModalData
    modal_data.quality_proto = prototyper.util.find("qualities", tags.proto_name)
    quality_selector.refresh_element(modal_data)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "select_quality",
            handler = handle_select_quality,
        }
    }
}

return { listeners }
