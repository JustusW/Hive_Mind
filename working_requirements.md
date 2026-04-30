# Hive Mind Reworked — Working requirements

In-flight design notes for changes that haven't yet been promoted to
[requirements.md](requirements.md) (player-facing intent)
and [design.md](design.md) (implementation choices). Once an item
here ships and stabilises, fold it into those two docs and delete it from
this file.

## 1. Time-gated recruitment + uncapped attack groups

### Player-facing intent

Without pollution the hive still grows, but slowly — a steady trickle of
biters wanders in from anywhere within recruit range. With pollution, the
intake scales: every biter the engine spawned into a pollution-funded
attack group is recruited the moment it enters range, in addition to the
trickle.

### Behaviour

- A network drains at most `R` "free" (non-attack-group) biters per second,
  pooled across all hives and nodes in the network. Free biters are local
  defenders, wanderers, leftover stragglers — anything whose
  `commandable.group` is `nil`.
- Any unit whose `commandable.group ≠ nil` (engine attack group, by
  construction pollution-driven) is recruited immediately on the tick the
  scan sees it, with no token cost.
- Pheromone overrides keep working: the destination switches to the
  pheromone player, but the bucket still gates non-group units.
- Hive workers are still excluded by the existing `is_for_role` check.

### Confirmed knobs

| Knob | Value | Notes |
|---|---|---|
| `trickle_per_second` | 0.5 | 1 biter every 2s per network |
| `bucket_cap_factor` | 5 | bucket caps at `5 × R` ⇒ 10s of saved-up draw |
| `gate_attack_groups` | false | pollution-driven biters bypass the bucket |
| Bucket scope | per network | matches "connected hives share one resource pool" rule |

### Implementation outline

`script/creatures.lua` + a new `state.recruit_buckets[network_key]` field
in `script/state.lua` + new `shared.recruit` table in `shared.lua`.

1. `state.recruit_buckets[key] = { tokens, last_tick }`. Network key is the
   smallest `unit_number` among hive + node entities in the resolved
   network (deterministic, save/load-safe). Stale keys pruned on
   `on_configuration_changed`.
2. On each `tick_recruitment` call, compute `dt = (tick - last_tick) / 60`,
   refill `tokens = min(cap, tokens + R * dt)`, store `last_tick`.
3. Resolve every hive's network once per tick; aggregate the candidate
   set per network so a single bucket gates the whole network rather than
   each hive racing the same pool.
4. For each candidate:
   - `is_group = unit.commandable and unit.commandable.group and
      unit.commandable.group.valid`.
   - If `is_group`: recruit unconditionally, no token cost.
   - Else: if `tokens >= 1`, decrement and recruit; otherwise skip cleanly
     (don't flip force, don't issue command).
5. Force flip + command issue stay atomic per unit so we never end up with
   a hive-force unit standing around with no destination.

### Telemetry

Append to `script-output/hm-debug.txt` per recruit tick:

```
[recruit] tick=12345 networks=3 tokens=[2.5,4.0,1.0] group=7 trickle=3 skipped=12
```

`networks` = how many distinct networks scanned; `tokens` = remaining
bucket levels per network in scan order; `group` = attack-group recruits
this tick; `trickle` = bucket-spent recruits; `skipped` = candidates
declined for empty bucket. Fields chosen so a single line tells the tuning
story: are we starving on tokens, drowning in group recruits, or both.

The line is gated on the existing `Debug` module's enable flag (which
already controls hm-debug.txt output today). No new switch.

### Edge cases

- **Long pause then resume**: bucket is capped at `bucket_cap_factor × R`,
  so an idle network can't accumulate infinite tokens and dump a giant
  burst on resume.
- **Network split / merge**: when a hive is destroyed and the network
  splits, the old bucket key may go stale. On recruit-tick, if the key
  doesn't resolve to an existing network, drop it. Resolved-but-new keys
  start at full cap (not zero) so a freshly-formed network isn't
  rate-limited from t=0.
- **Multiplayer**: the bucket is per network, not per player, so a second
  hive director joining the same network doesn't double the rate.

---

## 2. Lag-reduction proposals

Today's per-tick cost is dominated by `find_entities_filtered` calls in
recruitment and absorption, plus the supremacy scan added in 0.8.0.

### 2a. Absorb at nodes too (suggested by user)

- Today: nodes recruit but only redirect units toward the nearest hive,
  where absorption happens.
- Proposed: nodes also absorb. Path: a unit recruited from a node walks to
  *that node*, stands in its tile, and `tick_absorption` running over
  every node sweeps it into the network's combined storage (nodes don't
  own a chest, so they insert into the **nearest hive's** chest, or the
  network's elected primary chest).
- Lag win: shorter walks (nodes are denser than hives), less time
  flailing in pathing, less time the unit is alive and being scanned over.

### 2b. Cache nearest-hive-on-surface per node

- Today: `nearest_hive_on_surface(node, hives)` runs every recruit tick,
  scanning every hive on the surface. With many nodes that's
  O(nodes × hives) per tick.
- Proposed: cache `node_data.nearest_hive_unit_number`. Invalidate on
  hive build / death and on configuration change. Recompute lazily on the
  next recruit tick if the cached unit number has gone stale.

### 2c. Combine recruitment + absorption sweeps

- Today: two independent `find_entities_filtered` passes per hive (recruit
  every 120 ticks, absorb every 30 ticks).
- Proposed: a single pass per hive on a shared cadence, classifying each
  found unit into "recruit" vs "absorb" by distance from hive centre.
  Saves one find call per hive per tick on the absorb cadence.

### 2d. Sample, don't sweep, in supremacy scan

- Today: `find_entities_filtered{ area = full hive box, force = ... }`
  every second per hive. A 100×100 box can return hundreds of entities.
- Proposed: each tick, scan only one of K = 4 quadrants of the hive box
  on a rotating index. Quadruples the effective lifetime of trees and
  buildings on creep but cuts per-tick scan cost by 4×. Tune K to balance
  responsiveness vs. cost; 2 is probably the sweet spot.

### 2e. Drop the per-entity `surface.get_tile` in supremacy

- Today: every candidate from `find_entities_filtered` triggers a
  `surface.get_tile(pos.x, pos.y)` to confirm it's on creep.
- Proposed: pre-cache the set of creep-positive chunks on each hive's
  growth tick. Only test entities whose chunk hash is in that set. For
  most early-game hives this skips the per-entity tile lookup entirely.

### 2f. Lazy worker dispatch ticking

- Today: `Workers.tick()` runs every 6 ticks regardless of whether any
  jobs are pending.
- Proposed: skip the tick when both `state.worker_jobs` is empty and no
  ghosts on the hive force exist. Cheap O(1) precheck; saves the
  per-job iteration on idle networks.

### 2g. Aggregate by surface, not by hive

- Today: many subsystems (recruit, absorb, supremacy, creep) iterate
  hives one at a time and call `surface.find_entities_filtered` per hive.
- Proposed: pre-bucket hives by surface once per tick; do one combined
  scan per surface and dispatch results to hives in code. Reduces engine
  ↔ Lua boundary crossings, which are the per-call hot cost.

Pick whichever combination matches the lag profile when we measure it
(see telemetry). Best to add a quick `[perf] tick=N recruit_ms=… absorb_ms=…
supremacy_ms=…` line gated on Debug before tuning, otherwise we're guessing.

---

## 3. Deployment nodes — feasibility

### Concept

A new buildable, similar to a hive node but acting as an outflow valve
rather than an inflow valve. The player marks a target; the deployment
node disgorges hive units from local network storage and dispatches them
as an attack group toward the target.

### Engine support — yes, this is feasible

- `surface.create_entity{ name = "<biter>", force = hivemind, position = … }`
  is already used in pheromone disgorge. The unit comes out alive on the
  hive force.
- `LuaSurface.create_unit_group{ position = node_pos, force = hivemind }`
  returns a `LuaCommandable` (formerly `LuaUnitGroup`).
- `group:add_member(unit)` attaches each freshly created unit to the
  group. Same mechanism the engine uses for pollution-funded attack
  groups.
- `group:set_command{ type = defines.command.attack_area, destination,
  radius }` or `defines.command.go_to_location` for non-aggressive
  dispatch. The engine handles pathing, regrouping, and combat from
  there.
- `group:start_moving()` releases the group toward the target.

API confirmed against Factorio 2.0 docs (LuaCommandable replaced the old
LuaUnitGroup; spawner ownership moved to LuaCommandable.spawner).

### Building shape

- Item `hm-deployment-node`, ghost `hm-deployment-node-ghost`. Tech
  prerequisite `hm-hive-spawners`.
- Visual: tinted spitter-spawner (red/orange) so it reads "outgoing" vs.
  the green of biter spawners and the teal of hive nodes.
- Footprint: 5×5 collision; no creep growth from it; no recruitment box.
- Built-in storage: none. Pulls from the resolved network's combined
  storage on dispatch.

### Targeting

Three options, in order of effort:

1. **Player ping**: the player carries a "deployment marker" item; a
   right-click drops a target render-object at that position with a
   timeout. Each deployment node within network range fires a group at
   the marker. Simple, direct, no GUI.
2. **Map marker**: a custom signal entity placed on the map. Deployment
   nodes targeting that signal fire at it. Persistent, multi-target,
   needs a tiny GUI for "set / clear".
3. **Auto-aggression**: deployment nodes scan for non-hive entities
   within radius R and dispatch to the nearest one. No player input.
   Aggressive default; would surprise people. Probably ship as off-by-
   default or a per-node toggle.

Recommend (1) for v1, (2) as a follow-up.

### Group composition

- Per dispatch, the player sets a "size" (small / medium / large = 5 /
  15 / 30 units, say). The node draws that many `hm-creature-*` items
  from network storage, prefers the largest creature first (behemoth →
  big → medium → small → spitter equivalents).
- If storage doesn't have enough, dispatch what's available; print a
  warning if zero.
- Cost: the network already paid pollution to absorb them; dispatching
  is "free". A pollution surcharge could be added later if balance
  demands.

### Risks / open questions

- **Pathing collapse on long dispatch**: groups can dissolve if pathing
  fails (water, void, very long routes). Mitigate by capping dispatch
  range (`shared.deployment.max_range`, default 200 tiles?) and refusing
  out-of-range targets with the now-standard error message.
- **Friendly fire**: hive force is friend with enemy and spectator. An
  attack group with `attack_area` will fire at vanilla biters too unless
  we explicitly exclude them. Need to verify whether `force.set_friend`
  semantics suppress targeting in attack-area, or whether we have to
  set per-command target filters. Test before shipping.
- **Group despawn / redirect**: if the target is destroyed mid-flight,
  the engine's default behaviour is the group sits on its rendezvous and
  waits. Add a 60s timeout: if the group hasn't engaged by then, return
  to nearest hive and re-absorb.
- **Storage drain race**: if two deployment nodes fire on the same tick
  from the same network, both will try to draw from the same chests.
  Resolve by serialising dispatches per network within a tick or
  pre-claiming items.
- **UI for dispatch**: simplest is a custom-input keybind that pings
  under the cursor. Drives feature parity with pheromone-style direct
  control.

### Verdict

Feasible for v1 with player-ping targeting and a fixed size dropdown.
Estimated effort: ~1 day of code + a session of balance tuning. Most of
the engine support is already exercised by the pheromone disgorge path,
so we're reusing tested machinery rather than introducing new
LuaCommandable surface area.

---

## Open questions for the user

1. Do you want the time-gated recruitment changes shipped first (v0.9.0)
   and deployment nodes as a follow-up (v0.10.0), or bundled?
2. Lag-reduction items 2a–2g — pick the ones to do alongside recruitment
   gating, or measure first via the `[perf]` line and decide?
3. Deployment node targeting — confirm option (1) player-ping for v1?
