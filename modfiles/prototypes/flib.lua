-- Raiguard does not keep the flib API stable, so I copy the stuff I need here
-- Styles & Sprites prefixed with fflib, to avoid clobbering any upstream changes
---@diagnostic disable

--[[
MIT License

Copyright (c) 2020 raiguard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local data_util = {dark_red_button_tileset = "__factoryplanner__/graphics/flib/dark-red-button.png"}

local styles = data.raw["gui-style"].default

-- SLOT BUTTON STYLES

local slot_tileset = "__factoryplanner__/graphics/flib/slots.png"

local function gen_slot(x, y, default_offset)
  default_offset = default_offset or 0
  return {
    type = "button_style",
    parent = "slot",
    size = 40,
    clicked_vertical_offset = 0,
    default_graphical_set = {
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
    },
    hovered_graphical_set = {
      base = { border = 4, position = { x + 80, y }, size = 80, filename = slot_tileset },
    },
    clicked_graphical_set = {
      base = { border = 4, position = { x + 160, y }, size = 80, filename = slot_tileset },
    },
    disabled_graphical_set = { -- identical to default graphical set
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
    },
  }
end

local function gen_slot_button(x, y, default_offset, glow)
  default_offset = default_offset or 0
  return {
    type = "button_style",
    parent = "slot_button",
    size = 40,
    clicked_vertical_offset = 0,
    default_graphical_set = {
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_2_rounded_corners_glow(default_dirt_color),
    },
    hovered_graphical_set = {
      base = { border = 4, position = { x + 80, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_2_rounded_corners_glow(default_dirt_color),
      glow = offset_by_2_rounded_corners_glow(glow),
    },
    clicked_graphical_set = {
      base = { border = 4, position = { x + 160, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_2_rounded_corners_glow(default_dirt_color),
    },
    disabled_graphical_set = { -- identical to default graphical set
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_2_rounded_corners_glow(default_dirt_color),
    },
  }
end

local function gen_standalone_slot_button(x, y, default_offset)
  default_offset = default_offset or 0
  return {
    type = "button_style",
    parent = "slot_button",
    size = 40,
    clicked_vertical_offset = 0,
    default_graphical_set = {
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_4_rounded_corners_shallow_inset,
    },
    hovered_graphical_set = {
      base = { border = 4, position = { x + 80, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_4_rounded_corners_shallow_inset,
    },
    clicked_graphical_set = {
      base = { border = 4, position = { x + 160, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_4_rounded_corners_shallow_inset,
    },
    disabled_graphical_set = { -- identical to default graphical set
      base = { border = 4, position = { x + default_offset, y }, size = 80, filename = slot_tileset },
      shadow = offset_by_4_rounded_corners_shallow_inset,
    },
  }
end

local slot_data = {
  { name = "default", y = 0, glow = default_glow_color },
  { name = "grey", y = 80, glow = default_glow_color },
  { name = "red", y = 160, glow = { 230, 135, 135 } },
  { name = "orange", y = 240, glow = { 216, 169, 122 } },
  { name = "yellow", y = 320, glow = { 230, 218, 135 } },
  { name = "green", y = 400, glow = { 153, 230, 135 } },
  { name = "cyan", y = 480, glow = { 135, 230, 230 } },
  { name = "blue", y = 560, glow = { 135, 186, 230 } },
  { name = "purple", y = 640, glow = { 188, 135, 230 } },
  { name = "pink", y = 720, glow = { 230, 135, 230 } },
}

for _, data in pairs(slot_data) do
  styles["fflib_slot_" .. data.name] = gen_slot(0, data.y)
  styles["fflib_selected_slot_" .. data.name] = gen_slot(0, data.y, 80)
  styles["fflib_slot_button_" .. data.name] = gen_slot_button(240, data.y, 0, data.glow)
  styles["fflib_selected_slot_button_" .. data.name] = gen_slot_button(240, data.y, 80, data.glow)
  styles["fflib_standalone_slot_button_" .. data.name] = gen_standalone_slot_button(240, data.y)
  styles["fflib_selected_standalone_slot_button_" .. data.name] = gen_standalone_slot_button(240, data.y, 80)
end

-- BUTTON STYLES

styles.fflib_selected_frame_action_button = {
  type = "button_style",
  parent = "frame_action_button",
  default_font_color = button_hovered_font_color,
  default_graphical_set = {
    base = { position = { 225, 17 }, corner_size = 8 },
    shadow = { position = { 440, 24 }, corner_size = 8, draw_type = "outer" },
  },
  hovered_font_color = button_hovered_font_color,
  hovered_graphical_set = {
    base = { position = { 369, 17 }, corner_size = 8 },
    shadow = { position = { 440, 24 }, corner_size = 8, draw_type = "outer" },
  },
  clicked_font_color = button_hovered_font_color,
  clicked_graphical_set = {
    base = { position = { 352, 17 }, corner_size = 8 },
    shadow = { position = { 440, 24 }, corner_size = 8, draw_type = "outer" },
  },
  -- Simulate clicked-vertical-offset
  top_padding = 1,
  bottom_padding = -1,
  clicked_vertical_offset = 0,
}

local btn = styles.button

styles.fflib_selected_tool_button = {
  type = "button_style",
  parent = "tool_button",
  default_font_color = btn.selected_font_color,
  default_graphical_set = btn.selected_graphical_set,
  hovered_font_color = btn.selected_hovered_font_color,
  hovered_graphical_set = btn.selected_hovered_graphical_set,
  clicked_font_color = btn.selected_clicked_font_color,
  clicked_graphical_set = btn.selected_clicked_graphical_set,
  -- Simulate clicked-vertical-offset
  top_padding = 1,
  bottom_padding = -1,
  clicked_vertical_offset = 0,
}

styles.fflib_tool_button_light_green = {
  type = "button_style",
  parent = "item_and_count_select_confirm",
  padding = 2,
  top_margin = 0,
  tooltip = "",
}

styles.fflib_tool_button_dark_red = {
  type = "button_style",
  parent = "tool_button",
  default_graphical_set = {
    base = { filename = data_util.dark_red_button_tileset, position = { 0, 0 }, corner_size = 8 },
    shadow = default_dirt,
  },
  hovered_graphical_set = {
    base = { filename = data_util.dark_red_button_tileset, position = { 17, 0 }, corner_size = 8 },
    shadow = default_dirt,
    glow = default_glow({ 236, 130, 130, 127 }, 0.5),
  },
  clicked_graphical_set = {
    base = { filename = data_util.dark_red_button_tileset, position = { 34, 0 }, corner_size = 8 },
    shadow = default_dirt,
  },
}

-- EMPTY-WIDGET STYLES

styles.fflib_dialog_footer_drag_handle = {
  type = "empty_widget_style",
  parent = "draggable_space",
  height = 32,
  horizontally_stretchable = "on",
}

styles.fflib_dialog_footer_drag_handle_no_right = {
  type = "empty_widget_style",
  parent = "fflib_dialog_footer_drag_handle",
  right_margin = 0,
}

styles.fflib_dialog_titlebar_drag_handle = {
  type = "empty_widget_style",
  parent = "fflib_titlebar_drag_handle",
  right_margin = 0,
}

styles.fflib_horizontal_pusher = {
  type = "empty_widget_style",
  horizontally_stretchable = "on",
}

styles.fflib_titlebar_drag_handle = {
  type = "empty_widget_style",
  parent = "draggable_space",
  left_margin = 4,
  right_margin = 4,
  height = 24,
  horizontally_stretchable = "on",
}

styles.fflib_vertical_pusher = {
  type = "empty_widget_style",
  vertically_stretchable = "on",
}

-- FLOW STYLES

styles.fflib_indicator_flow = {
  type = "horizontal_flow_style",
  vertical_align = "center",
}

styles.fflib_titlebar_flow = {
  type = "horizontal_flow_style",
  horizontal_spacing = 8,
}

-- FRAME STYLES

styles.fflib_shallow_frame_in_shallow_frame = {
  type = "frame_style",
  parent = "frame",
  padding = 0,
  graphical_set = {
    base = {
      position = { 85, 0 },
      corner_size = 8,
      center = { position = { 76, 8 }, size = { 1, 1 } },
      draw_type = "outer",
    },
    shadow = default_inner_shadow,
  },
  vertical_flow_style = {
    type = "vertical_flow_style",
    vertical_spacing = 0,
  },
}

-- IMAGE STYLES

styles.fflib_indicator = {
  type = "image_style",
  size = 16,
  stretch_image_to_widget_size = true,
}

-- LABEL STYLES

styles.fflib_frame_title = {
  type = "label_style",
  parent = "frame_title",
  bottom_padding = 3,
  top_margin = -3,
}

-- LINE STYLES

styles.fflib_subheader_horizontal_line = {
  type = "line_style",
  horizontally_stretchable = "on",
  left_margin = -8,
  right_margin = -8,
  top_margin = -2,
  bottom_margin = -2,
  border = {
    border_width = 8,
    horizontal_line = { filename = "__factoryplanner__/graphics/flib/subheader-line.png", size = { 1, 8 } },
  },
}

styles.fflib_titlebar_separator_line = {
  type = "line_style",
  top_margin = -2,
  bottom_margin = 2,
}

-- SCROLL-PANE STYLES

styles.fflib_naked_scroll_pane = {
  type = "scroll_pane_style",
  extra_padding_when_activated = 0,
  padding = 12,
  graphical_set = {
    shadow = default_inner_shadow,
  },
}

styles.fflib_naked_scroll_pane_under_tabs = {
  type = "scroll_pane_style",
  parent = "fflib_naked_scroll_pane",
  graphical_set = {
    base = {
      top = { position = { 93, 0 }, size = { 1, 8 } },
      draw_type = "outer",
    },
    shadow = default_inner_shadow,
  },
}

styles.fflib_naked_scroll_pane_no_padding = {
  type = "scroll_pane_style",
  parent = "fflib_naked_scroll_pane",
  padding = 0,
}

styles.fflib_shallow_scroll_pane = {
  type = "scroll_pane_style",
  padding = 0,
  graphical_set = {
    base = { position = { 85, 0 }, corner_size = 8, draw_type = "outer" },
    shadow = default_inner_shadow,
  },
}

-- TABBED PANE STYLES

styles.fflib_tabbed_pane_with_no_padding = {
  type = "tabbed_pane_style",
  tab_content_frame = {
    type = "frame_style",
    top_padding = 0,
    bottom_padding = 0,
    left_padding = 0,
    right_padding = 0,
    graphical_set = {
      base = {
        -- Same as tabbed_pane_graphical_set - but without bottom
        top = { position = { 76, 0 }, size = { 1, 8 } },
        center = { position = { 76, 8 }, size = { 1, 1 } },
      },
      shadow = top_shadow,
    },
  },
}

-- TEXTFIELD STYLES

styles.fflib_widthless_textfield = {
  type = "textbox_style",
  width = 0,
}

styles.fflib_widthless_invalid_textfield = {
  type = "textbox_style",
  parent = "invalid_value_textfield",
  width = 0,
}

styles.fflib_titlebar_search_textfield = {
  type = "textbox_style",
  top_margin = -2,
  bottom_margin = 1,
  width = 150,
}


data:extend({
  {
    type = "sprite",
    name = "fflib_settings_black",
    filename = "__factoryplanner__/graphics/flib/frame-action-icons.png",
    position = { 0, 32 },
    size = 32,
    flags = { "gui-icon" },
  }
})
