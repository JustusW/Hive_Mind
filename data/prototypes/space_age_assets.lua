local util = require("util")

local assets = {}

local mod_prefix = "__Hive_Mind_Reworked__/"
local entity_path = mod_prefix .. "graphics/entity/"
local sound_path = mod_prefix .. "sound/enemies/wriggler/"

assets.gleba_spawner_icon = mod_prefix .. "graphics/icons/gleba-spawner.png"
assets.gleba_spawner_small_icon = mod_prefix .. "graphics/icons/gleba-spawner-small.png"
assets.biolab_icon = mod_prefix .. "graphics/icons/biolab.png"
assets.small_wriggler_icon = mod_prefix .. "graphics/icons/small-wriggler.png"
assets.icon_size = 64

local function sprite(path, options)
  return util.sprite_load(entity_path .. path, options)
end

local function sound_variations(prefix, count, volume)
  local variations = {}
  for i = 1, count do
    variations[i] =
    {
      filename = sound_path .. prefix .. "-" .. i .. ".ogg",
      volume = volume
    }
  end
  return variations
end

local function lerp_color(a, b, amount)
  return
  {
    a[1] + amount * (b[1] - a[1]),
    a[2] + amount * (b[2] - a[2]),
    a[3] + amount * (b[3] - a[3]),
    a[4] + amount * (b[4] - a[4])
  }
end

local function fade(tint, amount)
  return lerp_color(tint, {1, 1, 1, 2}, amount)
end

local function grey_overlay(tint, amount)
  return lerp_color(tint, {127, 127, 127, 255}, amount)
end

local gleba_small_mask_tint = {103, 151, 11, 255}
local gleba_small_body_tint = {125, 124, 111, 255}
local small_wriggler_mask_tint = fade(lerp_color(gleba_small_mask_tint, {255, 200, 0, 255}, 0.1), 0.2)
local small_wriggler_body_tint = grey_overlay(lerp_color(gleba_small_body_tint, {255, 0, 0, 255}, 0.1), 0.2)

function assets.gleba_spawner_animation()
  return
  {
    layers =
    {
      sprite("gleba-spawner/spawner-upper-1",
      {
        frame_count = 16,
        scale = 0.5,
        animation_speed = 0.1,
        run_mode = "forward-then-backward",
        shift = util.by_pixel(12, -20)
      }),
      sprite("gleba-spawner/spawner-shadow-1",
      {
        frame_count = 16,
        scale = 0.5,
        animation_speed = 0.1,
        run_mode = "forward-then-backward",
        draw_as_shadow = true,
        shift = util.by_pixel(12, -20)
      })
    }
  }
end

function assets.gleba_spawner_small_animation()
  return
  {
    layers =
    {
      sprite("gleba-spawner/small/spawner-upper-small-1",
      {
        frame_count = 16,
        scale = 0.5,
        animation_speed = 0.1,
        run_mode = "forward-then-backward",
        shift = util.by_pixel(8, 0)
      }),
      sprite("gleba-spawner/small/spawner-shadow-small-1",
      {
        frame_count = 16,
        scale = 0.5,
        animation_speed = 0.1,
        run_mode = "forward-then-backward",
        draw_as_shadow = true,
        shift = util.by_pixel(8, 0)
      })
    }
  }
end

function assets.biolab_on_animation()
  return
  {
    layers =
    {
      sprite("biolab/biolab-anim",
      {
        frame_count = 32,
        scale = 0.5,
        animation_speed = 0.2
      }),
      sprite("biolab/biolab-lights",
      {
        frame_count = 32,
        draw_as_glow = true,
        blend_mode = "additive",
        scale = 0.5,
        animation_speed = 0.2
      }),
      sprite("biolab/biolab-shadow",
      {
        frame_count = 32,
        scale = 0.5,
        animation_speed = 0.2,
        draw_as_shadow = true
      })
    }
  }
end

function assets.biolab_off_animation()
  return
  {
    layers =
    {
      sprite("biolab/biolab-anim",
      {
        frame_count = 32,
        scale = 0.5,
        animation_speed = 0.2
      }),
      sprite("biolab/biolab-shadow",
      {
        frame_count = 32,
        scale = 0.5,
        animation_speed = 0.2,
        draw_as_shadow = true
      })
    }
  }
end

function assets.wriggler_run_animation()
  local scale = 0.6
  return
  {
    layers =
    {
      sprite("wriggler/wriggler-run",
      {
        slice = 5,
        frame_count = 21,
        direction_count = 16,
        scale = 0.5 * 1.2 * scale,
        animation_speed = 0.48,
        tint_as_overlay = true,
        tint = small_wriggler_body_tint
      }),
      sprite("wriggler/wriggler-run-tint",
      {
        slice = 5,
        frame_count = 21,
        direction_count = 16,
        scale = 0.5 * 1.2 * scale,
        animation_speed = 0.48,
        tint_as_overlay = true,
        tint = small_wriggler_mask_tint
      }),
      sprite("wriggler/wriggler-run-shadow",
      {
        slice = 5,
        frame_count = 21,
        direction_count = 16,
        scale = 0.5 * 1.2 * scale,
        animation_speed = 0.48,
        draw_as_shadow = true
      })
    }
  }
end

local function wriggler_sounds()
  return
  {
    working_sound =
    {
      sound =
      {
        category = "enemy",
        variations = sound_variations("wriggler-idle", 9, 0.5)
      },
      probability = 1 / (10 * 60),
      max_sounds_per_prototype = 2
    },
    walking_sound =
    {
      variations = sound_variations("wriggler-walk", 6, 0.2),
      aggregation = {max_count = 3, remove = true, count_already_playing = true}
    },
    dying_sound =
    {
      variations = sound_variations("wriggler-death", 8, 1.0),
      aggregation = {max_count = 2, remove = true, count_already_playing = true}
    },
    warcry =
    {
      variations = sound_variations("wriggler-warcry", 6, 0.6),
      aggregation = {max_count = 2, remove = true, count_already_playing = true}
    },
    attack_sound =
    {
      variations = sound_variations("wriggler-attack", 9, 0.25),
      aggregation = {max_count = 2, remove = true, count_already_playing = true}
    }
  }
end

function assets.apply_wriggler_unit(unit)
  local run_animation = assets.wriggler_run_animation()
  local sounds = wriggler_sounds()

  unit.icon = assets.small_wriggler_icon
  unit.icon_size = assets.icon_size
  unit.icons = nil
  unit.run_animation = run_animation
  unit.walking_sound = sounds.walking_sound
  unit.working_sound = sounds.working_sound
  unit.dying_sound = sounds.dying_sound
  unit.warcry = sounds.warcry
  unit.water_reflection =
  {
    pictures =
    {
      filename = entity_path .. "wriggler/wriggler-effect-map.png",
      height = 21,
      width = 32,
      scale = 2.5 * 0.6,
      variation_count = 1
    }
  }

  if unit.attack_parameters then
    unit.attack_parameters.animation = table.deepcopy(run_animation)
    unit.attack_parameters.sound = sounds.attack_sound
  end
end

return assets
