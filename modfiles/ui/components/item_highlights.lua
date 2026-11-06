item_highlights = {}

---@alias ItemHighlightGroups table<string, {button: LuaGuiElement, proper_style: string}[]>
---@alias ItemHighlightContext "compact_dialog" | "production_table" | "item_boxes"
---@class ItemHighlightState
---@field groups table<ItemHighlightContext, ItemHighlightGroups>
---@field active_key string?
---@field hovered_button LuaGuiElement?

---@class ItemHighlightTags
---@field context ItemHighlightContext
---@field highlight_key string
---@field on_gui_hover string
---@field on_gui_leave string

---@param player LuaPlayer
---@param context ItemHighlightContext
---@return ItemHighlightState
local function get_state(player, context)
    local ui_state = lib.globals.ui_state(player)
    local elements = (context == "compact_dialog") and ui_state.compact_elements or ui_state.main_elements
    elements.item_highlights = elements.item_highlights or {groups={}}
    return elements.item_highlights
end

---@param state ItemHighlightState
---@param key string
---@param highlighted boolean
local function set_highlight(state, key, highlighted)
    for _, groups in pairs(state.groups) do
        for _, data in ipairs(groups[key] or {}) do
            if data.button.valid then
                data.button.style = highlighted and "fflib_slot_button_pink" or data.proper_style
            end
        end
    end
end

---@param state ItemHighlightState
local function clear_highlight(state)
    if not state.active_key then return end
    set_highlight(state, state.active_key, false)
    state.active_key, state.hovered_button = nil, nil
end

---@param player LuaPlayer
---@param context ItemHighlightContext
function item_highlights.reset(player, context)
    local state = get_state(player, context)
    -- A partial refresh can destroy the hovered button before its leave event
    clear_highlight(state)
    state.groups[context] = {}
end

---@param player LuaPlayer
---@param button LuaGuiElement
---@param item SimpleItem | Fuel
---@param name string?
function item_highlights.register(player, button, item, name)
    local tags = button.tags  ---@as ItemHighlightTags
    if tags.context ~= "compact_dialog" and not lib.globals.preferences(player).highlight_items then return end

    local proto = item.proto  ---@as FPItemPrototype | FPFuelPrototype
    local quality = item.quality_proto and item.quality_proto.name
    local raw_item = {name=name or proto.name, type=proto.type, quality=quality, amount=0}  ---@type SolverItem
    local key = solver.util.pack_item(raw_item)
    tags.highlight_key = key
    tags.on_gui_hover = "hover_item"
    tags.on_gui_leave = "leave_item"
    button.tags = tags

    local groups = get_state(player, tags.context).groups[tags.context]
    groups[key] = groups[key] or {}
    table.insert(groups[key], {button=button, proper_style=button.style.name})
end

---@param player LuaPlayer
---@param button LuaGuiElement
---@param line LineObject
---@param item SimpleItem
---@param category "products" | "ingredients"
function item_highlights.register_line_item(player, button, line, item, category)
    local name = item.proto.name
    if line.class == "Line" and category == "ingredients" then
        name = line--[[@as Line]].recipe:get_name_with_temperature(item.proto)
    end
    item_highlights.register(player, button, item, name)
end

---@param player LuaPlayer
---@param tags ItemHighlightTags
---@param event EventData.on_gui_hover | EventData.on_gui_leave
local function handle_hover_change(player, tags, event)
    local state = get_state(player, tags.context)
    if event.name == defines.events.on_gui_hover then
        if state.active_key ~= tags.highlight_key then
            clear_highlight(state)
            set_highlight(state, tags.highlight_key, true)
            state.active_key = tags.highlight_key
        end
        state.hovered_button = event.element
    elseif state.hovered_button == event.element then
        clear_highlight(state)
    end
end

-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_hover = {
        {
            name = "hover_item",
            handler = function(player, tags, event)
                ---@cast tags ItemHighlightTags
                ---@cast event EventData.on_gui_hover
                handle_hover_change(player, tags, event)
                main_dialog.set_tooltip(player, event.element)
            end
        }
    },
    on_gui_leave = {
        {
            name = "leave_item",
            handler = handle_hover_change
        }
    }
}  ---@as GUIListenerDefinition

return { listeners }
