-- Startup settings.
--
-- Both default to false: the post-0.9.16 commitment / pacing mechanics are
-- opt-in. With both off the mod plays the way it did at 0.9.16: the Hive
-- recipe is always available, placement is instant, the hive is minable
-- (re-placing destroys the previous one), and node placement is unbounded.
--
-- These are read at runtime via shared.feature_enabled("hm-...") in the
-- few code paths that branch on them (Force.configure, Build.on_built,
-- Director.join, Death.on_removed).

data:extend(
{
  {
    type          = "bool-setting",
    name          = "hm-anchor-binding",
    setting_type  = "startup",
    default_value = false,
    order         = "a"
  },
  {
    type          = "bool-setting",
    name          = "hm-evolution-gate",
    setting_type  = "startup",
    default_value = false,
    order         = "b"
  },
  -- Debug telemetry. When off, Telemetry.flush_* is a no-op and the
  -- script-output/hm-debug.txt file stays untouched. Default off so end
  -- users get a quiet save folder; turn on for tuning sessions.
  --
  -- Runtime-global so the toggle takes effect mid-session — flipping a
  -- startup setting requires reloading and waiting through any on_init
  -- migrations, which is painful when you're trying to catch a lag spike.
  {
    type          = "bool-setting",
    name          = "hm-debug-telemetry",
    setting_type  = "runtime-global",
    default_value = false,
    order         = "z"
  }
})
