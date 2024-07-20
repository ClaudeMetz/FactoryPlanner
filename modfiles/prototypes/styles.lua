---@diagnostic disable

local styles = data.raw["gui-style"].default

styles["fp_frame_deep_slots_small"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame",
    background_graphical_set = deep_slot_background_tiling(36, 36)
}

styles["fp_table_filter_slot_small"] = {
    type = "table_style",
    parent = "filter_slot_table",
    column_widths = {
        width = 36
    }
}

styles["fp_frame_bordered_stretch"] = {
    type = "frame_style",
    parent = "bordered_frame",
    right_padding = 8,
    horizontally_stretchable = "on"
}

styles["fp_frame_module"] = {
    type = "frame_style",
    parent = "fp_frame_bordered_stretch",
    padding = 8,
    horizontal_flow_style = {
        type = "horizontal_flow_style",
        horizontal_spacing = 8,
        vertical_align = "center"
    }
}

styles["fp_frame_semitransparent"] = {
    type = "frame_style",
    graphical_set = {
        base = {
            type = "composition",
            filename = "__factoryplanner__/graphics/semitransparent_pixel.png",
            corner_size = 1,
            position = {0, 0}
        }
    }
}

styles["fp_table_production"] = {
    type = "table_style",
    odd_row_graphical_set = {
        filename = "__core__/graphics/gui-new.png",
        position = {472, 25},
        size = 1
    }
}

styles["fp_drop-down_slim"] = {
    type = "dropdown_style",
    minimal_width = 0,
    height = 24,
    top_padding = -2,
    right_padding = 2,
    bottom_padding = 0,
    left_padding = 4
}

-- This style is hacked together from rounded-button and textbox
styles["fp_sprite-button_inset"] = {
    type = "button_style",
    size = 32,
    padding = 0,
    default_graphical_set = styles.textbox.default_background,
    hovered_graphical_set = styles.rounded_button.clicked_graphical_set,
    clicked_graphical_set = styles.textbox.active_background,
    disabled_graphical_set = styles.rounded_button.disabled_graphical_set
}

styles["fp_sprite-button_group_tab"] = {
    type = "button_style",
    parent = "filter_group_button_tab_slightly_larger",
    horizontally_stretchable = "on",
    width = 0,  -- allows stretching
    padding = 1
}

-- frame_action_button but correct
styles["fp_button_frame"] = {
    type = "button_style",
    parent = "frame_action_button",
    selected_graphical_set = styles.frame_button.clicked_graphical_set,
    selected_hovered_graphical_set = styles.frame_button.hovered_graphical_set,
    selected_clicked_graphical_set = styles.frame_button.default_graphical_set,
}

-- Text button in the style of icon tool buttons, for use in the title bar
styles["fp_button_frame_tool"] = {
    type = "button_style",
    parent = "frame_button",
    font = "heading-2",
    default_font_color = {0.9, 0.9, 0.9},
    minimal_width = 0,
    height = 24,
    right_padding = 8,
    left_padding = 8
}

styles["fp_sprite-button_rounded_mini"] = {
    type = "button_style",
    parent = "rounded_button",
    invert_colors_of_picture_when_disabled = true,
    size = 26,
    padding = 2
}

styles["fp_sprite-button_move"] = {
    type = "button_style",
    parent = "list_box_item",
    invert_colors_of_picture_when_hovered_or_toggled = true
}

-- Generate smaller versions of flib's slot buttons (size 36)
for _, color in pairs{"default", "grey", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"} do
    styles["flib_slot_button_" .. color .. "_small"] = {
        type = "button_style",
        parent = "flib_slot_button_" .. color,
        size = 36
    }
end

styles["flib_slot_button_transparent"] = {
    type = "button_style",
    parent = "flib_slot_button_default",
    default_graphical_set = {},
    disabled_graphical_set = {},
    padding = 4
}

styles["flib_slot_button_transparent_small"] = {
    type = "button_style",
    parent = "flib_slot_button_transparent",
    size = 36
}

styles["flib_slot_button_grayscale_small"] = {
    type = "button_style",
    parent = "flib_slot_button_default_small",
    draw_grayscale_picture = true
}

styles["flib_slot_button_transparent_grayscale_small"] = {
    type = "button_style",
    parent = "flib_slot_button_transparent_small",
    draw_grayscale_picture = true
}


styles["fp_label_module_error"] = {
    type = "label_style",
    font = "heading-2",
    padding = 2
}

styles["fp_label_frame_title"] = {
    type = "label_style",
    parent = "frame_title",
    top_margin = -3
}
