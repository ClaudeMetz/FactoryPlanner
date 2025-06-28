---@diagnostic disable

local function add_sprite(name, filename, size, mipmaps)
    data:extend{{
        type = "sprite", name = "fp_" .. name,
        filename = "__factoryplanner__/graphics/" .. (filename or (name .. ".png")),
        size = size, mipmap_count = mipmaps, flags = {"gui-icon"}
    }}
end

add_sprite("mod_gui", "shortcut_open_x56.png", 56, nil)
add_sprite("zone_selection", nil, 32, nil)
add_sprite("generic_assembler", nil, 64, 2)
add_sprite("white_square", nil, 8, 2)
add_sprite("warning_red", nil, 32, 2)
add_sprite("trash_red", nil, 32, 2)
add_sprite("archive", nil, 32, 2)
add_sprite("arrow_up", nil, 32, 2)
add_sprite("arrow_down", nil, 32, 2)
add_sprite("arrow_line_up", nil, 32, 2)
add_sprite("arrow_line_bar_up", nil, 32, 2)
add_sprite("pin", nil, 32, 2)
add_sprite("silo_rocket", nil, 120, 1)
add_sprite("agriculture_square", nil, 120, 1)
add_sprite("play", nil, 32, 2)
add_sprite("limited_up", nil, 20, 1)
add_sprite("limited_down", nil, 20, 1)
add_sprite("stack", nil, 64, 1)
add_sprite("calculator", nil, 64, 1)
add_sprite("history", nil, 32, 1)
add_sprite("plus", nil, 32, 1)
add_sprite("minus", nil, 32, 1)
add_sprite("multiply", nil, 32, 1)
add_sprite("divide", nil, 32, 1)
add_sprite("default", nil, 32, 1)
add_sprite("default_all", nil, 32, 1)
add_sprite("amount", nil, 32, 1)
add_sprite("dropup", nil, 32, 2)
add_sprite("fold_out_subfloors", nil, 32, 1)
add_sprite("universal_planet", nil, 64, 1)
add_sprite("collapse", nil, 32, 1)
add_sprite("expand", nil, 32, 1)


-- Base game sprites
data:extend{{
    type = "sprite", name = "fp_panel",
    filename = "__core__/graphics/icons/mip/expand-panel-black.png",
    size = 64, flags = {"gui-icon"}
}}
