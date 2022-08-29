data:extend({
    {
        type = "custom-input",
        name = "fp_toggle_interface",
        key_sequence = "CONTROL + R",
        consuming = "game-only",
        order = "a"
    },
    {
        type = "custom-input",
        name = "fp_toggle_compact_view",
        key_sequence = "CONTROL + SHIFT + R",
        consuming = "game-only",
        order = "b"
    },
    {
        type = "custom-input",
        name = "fp_toggle_pause",
        key_sequence = "CONTROL + P",
        consuming = "none",
        order = "c"
    },
    {
        type = "custom-input",
        name = "fp_refresh_production",
        key_sequence = "R",
        consuming = "none",
        order = "d"
    },
    {
        type = "custom-input",
        name = "fp_cycle_production_views",
        key_sequence = "TAB",
        consuming = "none",
        order = "e"
    },
    {
        type = "custom-input",
        name = "fp_reverse_cycle_production_views",
        key_sequence = "CONTROL + TAB",
        consuming = "none",
        order = "f"
    },
    {
        type = "custom-input",
        name = "fp_confirm_dialog",
        key_sequence = "ENTER",
        alternative_key_sequence = "KP_ENTER",
        consuming = "none",
        order = "g"
    },
    {
        type = "custom-input",
        name = "fp_confirm_gui",
        key_sequence = "",
        linked_game_control = "confirm-gui"
    },
    {
        type = "custom-input",
        name = "fp_focus_searchfield",
        key_sequence = "",
        linked_game_control = "focus-search"
    }
})
