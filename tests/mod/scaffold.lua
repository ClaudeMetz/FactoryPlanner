---@diagnostic disable: incomplete-signature-doc, missing-global-doc

-- The minimal prototypes the engine demands when the base mod is disabled, plus
-- the pieces map creation needs. Only loaded for worlds without the base mod.
-- The set of engine-required prototypes is informed by
-- https://github.com/Bilka2/minimal-no-base-mod (MIT, by Bilka), which targeted 1.1;
-- missing ones are re-added as the game's own load errors point them out.

local sprite_filename = "__core__/graphics/empty.png"

local function icon(prototype)
  prototype.icon = sprite_filename
  prototype.icon_size = 1
  return prototype
end

local function sprite()
  return { filename = sprite_filename, size = 1 }
end

local function sound()
  return { filename = "__core__/sound/achievement-unlocked.ogg" }
end

local function rotated_animation()
  local animation = sprite()
  animation.direction_count = 1
  return animation
end

-- The utility constants are defined in the core mod. Removing this property means
--   trigger-target-types "common" and "ground-unit" do not have to be created.
data.raw["utility-constants"]["default"].default_trigger_target_mask_by_type = nil
-- The "x-unknown" prototypes are defined in the core mod. Setting the subgroup to
--   the one defined below means the default subgroup "fluid" does not have to be created.
data.raw["fluid"]["fluid-unknown"].subgroup = "other"

-- Miscellaneous prototypes that are required by the required prototypes
data:extend({
  icon{
    type = "item-group",
    name = "dummy-item-group"
  },
  {
    type = "item-subgroup",
    name = "other",  -- the default subgroup for several prototype types
    group = "dummy-item-group"
  },
  {
    type = "recipe-category",
    name = "crafting"
  },
  {
    type = "resource-category",
    name = "basic-solid"
  },
  {
    type = "fuel-category",
    name = "chemical"
  }
})

-- Core prototypes, which the game requires to always exist
data:extend({
  icon{
    type = "virtual-signal",
    name = "signal-everything",
    subgroup = "other"
  },
  icon{
    type = "virtual-signal",
    name = "signal-anything",
    subgroup = "other"
  },
  icon{
    type = "virtual-signal",
    name = "signal-each",
    subgroup = "other"
  },
  {
    type = "damage-type",
    name = "physical"
  },
  {
    type = "damage-type",
    name = "impact"
  },
  {
    type = "trivial-smoke",
    name = "smoke-building",
    animation = sprite(),
    duration = 1,
    cyclic = true
  },
  icon{
    type = "item",
    name = "copper-cable",
    stack_size = 1
  },
  {
    type = "character",
    name = "character",
    mining_speed = 1,
    running_speed = 1,
    distance_per_frame = 1,
    maximum_corner_sliding_distance = 1,
    heartbeat = sound(),
    eat = sound(),
    inventory_size = 1,
    build_distance = 1,
    drop_item_distance = 1,
    reach_distance = 1,
    reach_resource_distance = 1,
    item_pickup_distance = 1,
    loot_pickup_distance = 1,
    ticks_to_keep_gun = 1,
    ticks_to_keep_aiming_direction = 1,
    ticks_to_stay_in_combat = 1,
    damage_hit_tint = {1, 1, 1, 1},
    running_sound_animation_positions = {},
    mining_with_tool_particles_animation_positions = {},
    animations = {
      {
        idle = rotated_animation(),
        idle_with_gun = rotated_animation(),
        running = rotated_animation(),
        -- Needs 18 directions, which requires a source file that is at least 18px wide
        running_with_gun = { filename = "__core__/graphics/icons/unknown.png",
          size = 1, direction_count = 18 },
        mining_with_tool = rotated_animation()
      }
    }
  },
  {
    type = "entity-ghost",
    name = "entity-ghost"
  },
  {
    type = "tile-ghost",
    name = "tile-ghost"
  },
  {
    type = "deconstructible-tile-proxy",
    name = "deconstructible-tile-proxy"
  },
  {
    type = "item-request-proxy",
    name = "item-request-proxy",
    picture = sprite()
  },
  {
    type = "item-entity",
    name = "item-on-ground"
  },
  {
    type = "highlight-box",
    name = "highlight-box"
  }
})

-- The pieces needed for map creation to work: a tile that covers the terrain,
--   a planet to start on, and a default map-gen-preset
data:extend({
  {
    type = "tile",
    name = "dummy-ground",
    collision_mask = { layers = { ground_tile = true } },
    layer = 0,
    map_color = {0.42, 0.42, 0.39},
    autoplace = { probability_expression = 1 },
    variants = {
      main = {{ picture = "__factoryplanner-test__/graphics/tile.png", count = 1, size = 1 }},
      empty_transitions = true
    }
  },
  icon{
    type = "planet",
    name = "nauvis",
    subgroup = "other",
    distance = 15,
    orientation = 0.275,
    magnitude = 1,
    order = "a",
    map_gen_settings = {},
    gravity_pull = 10
  },
  {
    type = "map-gen-presets",
    name = "default",
    default = { order = "a" }
  }
})

-- The map settings are required, despite not being a core prototype.
--   These are a copy from the base mod, with the 2.x additions included.
data:extend({
  {
    type = "map-settings",
    name = "map-settings",

    pollution =
    {
      enabled = true,
      diffusion_ratio = 0.02,
      min_to_diffuse = 15,
      ageing = 1,
      expected_max_per_chunk = 150,
      min_to_show_per_chunk = 50,
      min_pollution_to_damage_trees = 60,
      pollution_with_max_forest_damage = 150,
      pollution_per_tree_damage = 50,
      pollution_restored_per_tree_damage = 10,
      max_pollution_to_restore_trees = 20,
      enemy_attack_pollution_consumption_modifier = 1
    },

    enemy_evolution =
    {
      enabled = true,
      time_factor = 0.000004,
      destroy_factor = 0.002,
      pollution_factor = 0.0000009
    },

    enemy_expansion =
    {
      enabled = true,
      max_expansion_distance = 7,
      friendly_base_influence_radius = 2,
      enemy_building_influence_radius = 2,
      building_coefficient = 0.1,
      other_base_coefficient = 2.0,
      neighbouring_chunk_coefficient = 0.5,
      neighbouring_base_chunk_coefficient = 0.4,
      min_expansion_distance = 2,
      evolution_group_size_factor = 1,
      build_base_unit_dispatch_cooldown = 60,
      max_colliding_tiles_coefficient = 0.9,
      settler_group_min_size = 5,
      settler_group_max_size = 20,
      min_expansion_cooldown = 4 * 3600,
      max_expansion_cooldown = 60 * 3600
    },

    unit_group =
    {
      min_group_gathering_time = 3600,
      max_group_gathering_time = 10 * 3600,
      max_wait_time_for_late_members = 2 * 3600,
      max_group_radius = 30.0,
      min_group_radius = 5.0,
      max_member_speedup_when_behind = 1.4,
      max_member_slowdown_when_ahead = 0.6,
      max_group_slowdown_factor = 0.3,
      max_group_member_fallback_factor = 3,
      member_disown_distance = 10,
      tick_tolerance_when_member_arrives = 60,
      max_gathering_unit_groups = 30,
      max_unit_group_size = 200
    },

    steering =
    {
      default =
      {
        radius = 1.2,
        separation_force = 0.005,
        separation_factor = 1.2,
        force_unit_fuzzy_goto_behavior = false
      },
      moving =
      {
        radius = 3,
        separation_force = 0.01,
        separation_factor = 3,
        force_unit_fuzzy_goto_behavior = false
      }
    },

    path_finder =
    {
      fwd2bwd_ratio = 5,
      goal_pressure_ratio = 2,
      max_steps_worked_per_tick = 1000,
      max_work_done_per_tick = 8000,
      use_path_cache = true,
      short_cache_size = 5,
      long_cache_size = 25,
      short_cache_min_cacheable_distance = 10,
      short_cache_min_algo_steps_to_cache = 50,
      long_cache_min_cacheable_distance = 30,
      cache_max_connect_to_cache_steps_multiplier = 100,
      cache_accept_path_start_distance_ratio = 0.2,
      cache_accept_path_end_distance_ratio = 0.15,
      negative_cache_accept_path_start_distance_ratio = 0.3,
      negative_cache_accept_path_end_distance_ratio = 0.3,
      cache_path_start_distance_rating_multiplier = 10,
      cache_path_end_distance_rating_multiplier = 20,
      stale_enemy_with_same_destination_collision_penalty = 30,
      ignore_moving_enemy_collision_distance = 5,
      enemy_with_different_destination_collision_penalty = 30,
      general_entity_collision_penalty = 10,
      general_entity_subsequent_collision_penalty = 3,
      extended_collision_penalty = 3,
      max_clients_to_accept_any_new_request = 10,
      max_clients_to_accept_short_new_request = 100,
      direct_distance_to_consider_short_request = 100,
      short_request_max_steps = 1000,
      short_request_ratio = 0.5,
      min_steps_to_check_path_find_termination = 2000,
      start_to_goal_cost_multiplier_to_terminate_path_find = 2000.0,
      overload_levels = {0, 100, 500},
      overload_multipliers = {2, 3, 4},
      negative_path_cache_delay_interval = 20
    },

    max_failed_behavior_count = 3,

    difficulty_settings =
    {
      technology_price_multiplier = 1,
      spoil_time_modifier = 1
    },

    asteroids =
    {
      spawning_rate = 1,
      max_ray_portals_expanded_per_tick = 100
    }
  }
})
