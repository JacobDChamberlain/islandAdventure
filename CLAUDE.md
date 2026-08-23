# CLAUDE.md — Island Adventure

A 3D platformer/collectathon prototype (Jak & Daxter vibe) built in **Godot 4.5**.
Solo/hobby project. Art from **Meshy.ai**, tweaked in Blender only if needed (not
installed). Approach: **greybox first** — gameplay before polish.

## Run / build / verify (do this every change)

Godot is at `/Users/jacob/Downloads/Godot.app` (NOT /Applications).

Note on the `pkill` dance: it's an artifact of *this automated workflow only* —
running headless validation processes while the editor GUI is also open means two
Godot instances share the same `.godot/` import cache and can clash, so kill first.
Normal single-editor use (what the user does) never has this problem; it's not an
install issue.

```bash
GD="/Users/jacob/Downloads/Godot.app/Contents/MacOS/Godot"
pkill -f "Godot.app/Contents/MacOS/Godot"; sleep 1
# 1) import + parse-check (grep for real errors)
"$GD" --headless --editor --quit-after 250 2>&1 | grep -iE "SCRIPT ERROR|ERROR|parse|invalid|shader" | grep -viE "Total|reimport|in use at exit"
# 2) actually run a scene headlessly to catch runtime errors
"$GD" --headless res://scenes/main.tscn --quit-after 200 2>&1 | grep -iE "SCRIPT ERROR|ERROR|Cannot|null instance"
```
"N resources still in use at exit" on headless quit is harmless (audio streams).
Then relaunch the editor GUI for the user to playtest (run in background):
`"$GD" --editor --path <project>`. I write code/files; the **user clicks Play (F5)**
and does GUI work — the editor is a native app I can't click into.

**`main_scene` is `scenes/title.tscn`** (F5 boots the title, not the game).

## Architecture

**Autoloads** (globals, by name):
- `Game` — run state: score, `total_artifacts`, `collected_artifacts`,
  `exotic_matter`, health, lives, `is_night`; signals `score_changed`/
  `exotic_changed`/`health_changed`/`lives_changed`/`all_artifacts_collected`/
  `game_over`. `new_run(total)` resets a run; `collect(name)`, `collect_exotic()`,
  `damage()`, `lose_life()`. **Artifacts** are the placed collectibles that gate the
  win; **Exotic Matter** is a rare pickup dropped by defeated heads (its own counter,
  never gates the win). `is_night` is written by `main.gd` and read by enemies.
- `Fx` — `poof(pos, color, amount, power)` spawns a one-shot GPUParticles3D.
- `Sfx` — Kenney CC0 sounds. Player: `stomp/artifact/exotic/hurt/jump/footstep`. UI:
  `ui_move/ui_select`, `wire_button(b)`. Enemies grab `random_step()/random_weird()`
  for their own 3D players. **Swap a sound = change the base name in `sfx.gd`.**
- `Settings` — volume/sensitivity/fullscreen, persisted to `user://settings.cfg`;
  F toggles fullscreen (only works in a non-embedded window).
- `SaveManager` — 3 JSON slots (`user://save_N.json`): player pos/health/score/
  exotic matter/collected artifacts. `apply_pending()` (called by main.gd) waits 2
  frames then applies.

**Scenes**: `title.tscn` (synthwave shader bg) → `main.tscn` (the level). Reusable
instances: `collectible.tscn` (artifact — group `"artifact"`), `exotic_matter.tscn`
(rare enemy drop — group `"exotic"`), `enemy.tscn`, `launch_pad.tscn`,
`moving_platform.tscn`, `platform.tscn`. Pause menu + end screen live in `main.tscn`
on `process_mode = ALWAYS` CanvasLayers so they run while the tree is paused.

**The island** (`island.gd` on the `Island` node) is fully procedural: noise-shaped
terrain + water + MultiMesh foliage, generated in `_ready`. It's in group `"island"`
and exposes **`height_at(x, z)`** — the source of truth for ground height.

## Key patterns / conventions

- **Snap to ground** via `island.height_at(x,z)`, NOT a physics raycast (raycast
  runs before terrain collision is ready → fall-through). Artifacts/exotic/enemies/
  pads/platforms all `await get_tree().process_frame` then set `global_position.y`.
  Artifacts support `extra_height` (float high, for launch-pad targets) +
  `snap_to_ground`.
- **Fitting a rigged model** (`player.gd _fit_aabb`, `enemy.gd _fit_model`): measure
  the **Skeleton3D bone extent**, not `mesh.get_aabb()` — Meshy bakes a ~100× scale
  into the rig, so the mesh AABB is tiny and makes the model gigantic.
- **In-place animations**: `_strip_root_motion()` freezes every POSITION_3D track to
  frame 0, so clips play in place and movement comes only from code velocity.
- **Terrain triangle winding must face up** (`island._tri` winds `a,c,b`/`a,d,c`)
  or `is_on_floor` fails and rays pass through.
- Groups used: `player`, `artifact`, `exotic`, `enemy`, `island`.
- Enemies are on **collision layer 2**, player only collides with layer 1, so the
  player passes through enemies; the enemy's Detector Area handles stomp vs bump.
- **Enemy respawn**: `enemy.gd` emits `died()` on stomp; `main.gd` captures each
  head's placement (`transform` + `model_yaw_offset_deg` + `roam_radius`) at start,
  and on `died` re-instances `enemy.tscn` at that config after `enemy_respawn_delay`.
  Heads are root-level children of `Main`, so local `transform` == world — set it
  (and the export overrides) **before** `add_child`, since `_ready` reads them.
- **Exotic Matter drops**: `enemy._die()` rolls `exotic_drop_chance` (bigger heads
  slightly likelier) and spawns `exotic_matter.tscn` under the level, then emits
  `died` + `queue_free`s. The drop is parented to `get_parent()`, not the dying head.
- **Day/night** (`main.gd`): a warped time-of-day curve keeps the sun up for
  `day_fraction` (0.75) of the cycle — long day, short night. `_sun_height()` remaps
  `_tod` into a half-sine per phase; `Game.is_night` is set when daylight < 0.15.
- **Night aggro**: enemies scale `detect_range`/`lose_range` by `night_detect_mult`
  and `chase_speed` by `night_speed_mult` whenever `Game.is_night` (see the
  `_detect_range()`/`_lose_range()`/`_chase_speed()` helpers in `enemy.gd`).
- Moving platforms are `AnimatableBody3D` (sync_to_physics carries the player);
  they sit above the **max** terrain height along their path so they never sink.

## Asset pipeline (Meshy)

Meshy paywalls downloads — user has **Meshy Pro**. To get an animated character:
generate with **A-Pose** (Pro), remesh to ~30K (free), rig, apply motions, then
**Export: glb + Rigged Character ON + Animation "All Added" + Single file ON**.
That downloads a zip; use the `..._Merged_Animations.glb` inside (mesh + 24-bone
skeleton + all clips). Hero = `assets/models/hero_anim_merged.glb`; the enemy is the
user's rigged head-bust `assets/models/nightmare.glb`. Raw zips are gitignored.

## Gotchas

- `.ogg`/`.wav` default to looping on import — SFX force loop off in `sfx.gd`.
- Scaling a CharacterBody3D node (the giant enemy) is fine, but ground-snap must use
  the world-space half-height (`model_height*0.5*scale.y`).
- Save/load resets enemies to spawn (live enemy state isn't saved yet).

## Status

Complete loop: title → play → win (all 8 artifacts) / lose (3 lives) → replay. Has:
hero movement (run/double-jump/sprint/roll), 6 AI enemies (wander/chase/attack)
that **respawn** and get **more aggressive at night**, artifacts + rare Exotic
Matter drops, HUD (live 3D head portrait), particles + full audio, a long-day/
short-night cycle, launch pads / moving + static platforms, settings, 3-slot
save/load.
Next ideas: more props (Meshy), deploy to itch.io (export → web build). See
`docs/ROADMAP.md`.
