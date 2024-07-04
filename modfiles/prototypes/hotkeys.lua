---@diagnostic disable

local order_string = "abcdefghijklmnopqrstuvwxyz"
local order_counter = 0

local function add_hotkey(name, sequence, alternate, consuming, linked)
    order_counter = order_counter + 1
    data:extend{{
        type = "custom-input",
        name = "fp_" .. name,
        key_sequence = sequence,
        alternative_key_sequence = alternate,
        consuming = consuming,
        linked_game_control = linked,
        order = order_string:sub(order_counter, order_counter)
    }}
end

add_hotkey("toggle_interface", "CONTROL + R", nil, "game-only", nil)
add_hotkey("toggle_compact_view", "CONTROL + SHIFT + R", nil, "game-only", nil)
add_hotkey("toggle_pause", "CONTROL + P", nil, "none", nil)
add_hotkey("refresh_production", "R", nil, "none", nil)
add_hotkey("up_floor", "ALT + UP", nil, "none", nil)
add_hotkey("top_floor", "SHIFT + ALT + UP", nil, "none", nil)
add_hotkey("cycle_production_views", "CONTROL + RIGHT", nil, "none", nil)
add_hotkey("reverse_cycle_production_views", "CONTROL + LEFT", nil, "none", nil)
add_hotkey("confirm_dialog", "ENTER", "KP_ENTER", "none", nil)
add_hotkey("confirm_gui", "", nil, nil, "confirm-gui")
add_hotkey("focus_searchfield", "", nil, nil, "focus-search")
