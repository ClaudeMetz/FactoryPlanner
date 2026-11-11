local BADGE_SIZE = 24

local shift_dist = (64 - BADGE_SIZE) / 2
local badge = {
    filename = "__core__/graphics/icons/technology/effect-constant/effect-constant-mining.png",
    x = 32, y = 32,
    width = 32, height = 32,
    scale = BADGE_SIZE / 32,
    shift = {-shift_dist, shift_dist}
}  ---@type data.Sprite

---@param resource data.ResourceEntityPrototype
local function create_sprite(resource)
    data:extend{{
        type = "sprite", name = "fp_resource_" .. resource.name,
        layers = {
            {filename=resource.icon, width=64, height=64},
            badge
        },
        flags = {"gui-icon"}
    }}
end

for _, resource in pairs(data.raw.resource) do
    if not resource.category or resource.category == "basic-solid" then create_sprite(resource) end
end
