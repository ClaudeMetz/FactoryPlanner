local styles = data.raw["gui-style"].default

-- Nomenclature: small = size 36; tiny = size 32

-- Imitates a listbox, but allowing for way more customisation by using real buttons
styles["fp_scroll-pane_fake_listbox"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane_with_dark_background_under_subheader",
    extra_right_padding_when_activated = -12,
    background_graphical_set = { -- rubber grid
        position = {282,17},
        corner_size = 8,
        overall_tiling_vertical_size = 22,
        overall_tiling_vertical_spacing = 6,
        overall_tiling_vertical_padding = 4,
        overall_tiling_horizontal_padding = 4
    },
    vertically_stretchable = "on",
    padding = 0,
    vertical_flow_style = {
        type = "vertical_flow_style",
        vertical_spacing = 0
    }
}

styles["fp_scroll-pane_slot_table"] = {
    type = "scroll_pane_style",
    parent = "filter_scroll_pane",
    bottom_margin = 0,
    bottom_padding = 0,
    extra_bottom_padding_when_activated = 0,
    graphical_set =
    {
        base = {position = {85, 0}, corner_size = 8, draw_type = "outer"},
        shadow = default_inner_shadow
    }
}

styles["fp_frame_slot_table"] = {
    type = "frame_style",
    parent = "filter_frame",
    top_padding = 4,
    bottom_padding = 12,
    graphical_set = table.deepcopy(styles.filter_frame.graphical_set)
}
styles["fp_frame_slot_table"].graphical_set.base.bottom = nil

-- Intended for buttons of size 36
styles["fp_frame_deep_slots_small"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame",
    background_graphical_set = {
        position = {282, 17},
        corner_size = 8,
        overall_tiling_vertical_size = 28,
        overall_tiling_vertical_spacing = 8,
        overall_tiling_vertical_padding = 4,
        overall_tiling_horizontal_size = 28,
        overall_tiling_horizontal_spacing = 8,
        overall_tiling_horizontal_padding = 4
    }
}

-- Intended for buttons of size 64hx73w
styles["fp_frame_deep_slots_crafting_groups"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame", -- "crafting_frame"
    background_graphical_set = {
        position = {282, 17},
        corner_size = 8,
        overall_tiling_vertical_size = 46,
        overall_tiling_vertical_spacing = 18,
        overall_tiling_vertical_padding = 9,
        overall_tiling_horizontal_size = 53,
        overall_tiling_horizontal_spacing = 20,
        overall_tiling_horizontal_padding = 10
    }
}

styles["fp_frame_bordered_stretch"] = {
    type = "frame_style",
    parent = "bordered_frame",
    horizontally_stretchable = "on"
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
    odd_row_graphical_set =
      {
        filename = "__core__/graphics/gui-new.png",
        position = {472, 25},
        size = 1
      }
}


-- This style is hacked together from rounded-button and textbox
styles["fp_sprite-button_inset"] = {
    type = "button_style",
    size = 40,
    padding = 0,
    default_graphical_set = styles.textbox.default_background,
    hovered_graphical_set = styles.rounded_button.clicked_graphical_set,
    clicked_graphical_set = styles.textbox.active_background,
    disabled_graphical_set = styles.rounded_button.disabled_graphical_set
}

styles["fp_sprite-button_inset_tiny"] = {
    type = "button_style",
    parent = "fp_sprite-button_inset",
    size = 32
}

styles["fp_sprite-button_inset_production"] = {
    type = "button_style",
    parent = "fp_sprite-button_inset_tiny",
    margin = 2,  -- used to offset the smaller size
    padding = 5  -- makes it so the plus doesn't look so stupid
}

styles["fp_sprite-button_group_tab"] = {
    type = "button_style",
    parent = "filter_group_button_tab",
    horizontally_stretchable = "on",
    width = 0,
    natural_width = 71,
    disabled_graphical_set = styles.button.selected_graphical_set
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

styles["fp_button_rounded_mini"] = {
    type = "button_style",
    parent = "rounded_button",
    height = 26,
    minimal_width = 0,
    left_padding = 4,
    right_padding = 4
}

-- Push-button style used for timescale and view_state buttons
styles["fp_button_push"] = {
    type = "button_style",
    parent = "button",
    height = 26,
    minimal_width = 0,
    padding = 0,
    disabled_font_color = {}  -- black
}

styles["fp_button_push_active"] = {
    type = "button_style",
    parent = "fp_button_push",
    default_graphical_set = styles.button.selected_graphical_set,
    hovered_graphical_set = styles.button.selected_hovered_graphical_set,
    clicked_graphical_set = styles.button.selected_clicked_graphical_set,
    disabled_font_color = {},  -- black
    disabled_graphical_set = styles.button.selected_graphical_set
}

-- A button that can be used in a fake listbox, but looks identical to the real thing
styles["fp_button_fake_listbox_item"] = {
    type = "button_style",
    parent = "list_box_item",
    left_padding = 4,
    right_padding = 8,
    horizontally_stretchable = "on",
    horizontally_squashable = "on"
}

-- The active style needs to be separate so the selected subfactory can still be clicked
styles["fp_button_fake_listbox_item_active"] = {
    type = "button_style",
    parent = "fp_button_fake_listbox_item",
    default_graphical_set = styles.button.selected_graphical_set,
    hovered_graphical_set = styles.button.selected_hovered_graphical_set,
    clicked_graphical_set = styles.button.selected_clicked_graphical_set,
    default_font_color = styles.button.selected_font_color,
    default_vertical_offset = styles.button.selected_vertical_offset
}

-- Generate smaller versions of flib's slot buttons (size 36)
for _, color in pairs{"default", "grey", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"} do
    styles["flib_slot_button_" .. color .. "_small"] = {
        type = "button_style",
        parent = "flib_slot_button_" .. color,
        size = 36
    }
end
