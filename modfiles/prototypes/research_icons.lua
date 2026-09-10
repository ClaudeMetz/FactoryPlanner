---@diagnostic disable

-- Composes the research items' icons: the science flask with the research time badged
-- top-right, one sprite per distinct time in the technology tree. Runs from
-- data-final-fixes to see other mods' technology changes, with the optional
-- pypostprocessing dependency ordering it after py's; a time introduced after this
-- point falls back to the unbadged flask.

local SHEET = "__factoryplanner__/graphics/glyphs.png"
local CELL_WIDTH = 80
-- Cropped to the ink's own rows, so the cells' transparent padding doesn't count
-- towards the layer bounds and shrink the base icon
local CELL_CROP_Y, CELL_CROP_HEIGHT = 18, 80
-- Sheet index and advance width per glyph, in sheet pixels
local glyphs = {
    ["0"] = {0, 52}, ["1"] = {1, 52}, ["2"] = {2, 52}, ["3"] = {3, 52},
    ["4"] = {4, 52}, ["5"] = {5, 52}, ["6"] = {6, 52}, ["7"] = {7, 52},
    ["8"] = {8, 52}, ["9"] = {9, 52}, ["."] = {10, 24}, ["s"] = {11, 43},
    ["m"] = {12, 77}
}

-- Badges the text into the top-right corner of a 64px icon, or nil if the sheet
-- can't spell it. Shifts are in raw source pixels rather than 32px tiles, which is
-- how the engine reads them for sprites drawn into GUI buttons.
local function text_layers(text, max_scale)
    local total_width = 0
    for i = 1, #text do
        local glyph = glyphs[text:sub(i, i)]
        if glyph == nil then return nil end
        total_width = total_width + glyph[2]
    end

    local scale = math.min(max_scale, 60 / total_width)
    local left = 31 - total_width * scale
    local vertical = CELL_CROP_HEIGHT * scale / 2 - 31

    local layers, cursor = {}, 0
    for i = 1, #text do
        local glyph = glyphs[text:sub(i, i)]
        table.insert(layers, {
            filename = SHEET,
            width = CELL_WIDTH, height = CELL_CROP_HEIGHT,
            x = glyph[1] * CELL_WIDTH, y = CELL_CROP_Y,
            scale = scale,
            shift = {left + (cursor + glyph[2] / 2) * scale, vertical},
            flags = {"gui-icon"}
        })
        cursor = cursor + glyph[2]
    end
    return layers
end


-- Kept in sync with research_time(), which names what these badges label
local function time_label(seconds)
    if seconds >= 120 then
        local minutes = seconds / 60
        if minutes % 1 == 0 then return minutes .. "m" end
        if (minutes * 10) % 1 == 0 then return string.format("%.1f", minutes) .. "m" end
    end
    return seconds .. "s"
end

local FLASK_LAYER = {filename = "__base__/graphics/icons/science.png",
    size = 64, mipmap_count = 4, tint = {1.0, 0.85, 0.35}, flags = {"gui-icon"}}

-- The fallback for research items whose time got no badge
data:extend{{type = "sprite", name = "fp_research", layers = {FLASK_LAYER}}}

local seen = {}
for _, tech in pairs(data.raw.technology) do
    local unit = (not tech.hidden) and tech.unit or nil
    local time = unit and unit.time or nil
    if time and time > 0 and unit.ingredients and #unit.ingredients > 0 then
        local sprite_name = "fp_research_" .. (time * 60)
        if not seen[sprite_name] then
            seen[sprite_name] = true

            local layers = {FLASK_LAYER}
            local time_badge = text_layers(time_label(time), 0.30)
            for _, layer in ipairs(time_badge or {}) do table.insert(layers, layer) end
            data:extend{{type = "sprite", name = sprite_name, layers = layers}}
        end
    end
end
