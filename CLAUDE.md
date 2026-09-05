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
# 3) run the CITY too — it has the cat/shop, so main.tscn alone misses those scripts
"$GD" --headless res://scenes/city.tscn --quit-after 200 2>&1 | grep -iE "SCRIPT ERROR|ERROR|Cannot"
```
**The editor `--quit-after` pass does NOT catch every parse error** (it missed an
undeclared variable in `cat.gd`). Only a scene that actually instantiates a script
compiles it — so run BOTH scenes. For a stronger gate, compile each script alone
(`--check-only --script res://scripts/X.gd`) and ignore the
`Identifier not found: Game|Fx|Sfx|Settings|SaveManager|Dialogue|DebugMenu` noise,
which is just autoloads being absent in that mode.
"N resources still in use at exit" on headless quit is harmless (audio streams).
Then relaunch the editor GUI for the user to playtest (run in background):
`"$GD" --editor --path <project>`. I write code/files; the **user clicks Play (F5)**
and does GUI work — the editor is a native app I can't click into.

**`main_scene` is `scenes/title.tscn`** (F5 boots the title, not the game).

## Architecture

**Autoloads** (globals, by name):
- `Game` — run state: score, `total_artifacts`, `collected_artifacts`,
  `exotic_matter`, `coins`, health, lives, `is_night`; signals `score_changed`/
  `exotic_changed`/`coins_changed`/`health_changed`/`lives_changed`/
  `all_artifacts_collected`/`game_over` (+ `artifact_collected`/`exotic_collected`
  which fire only on a real pickup, for toasts). `new_run(total)` resets a run;
  `collect(name)`, `collect_exotic()`, `collect_coin()`, `damage()`, `lose_life()`.
  **Artifacts** are the placed collectibles that gate the win; **Exotic Matter**
  (rare) and **coins** (common) are dropped by defeated heads and never gate the win.
  `is_night` is written by `main.gd` and read by enemies.
- `Fx` — `poof(pos, color, amount, power)` spawns a one-shot GPUParticles3D.
- `Sfx` — Kenney CC0 sounds. Player: `stomp/hit/artifact/exotic/coin/hurt/jump/footstep`. UI:
  `ui_move/ui_select`, `wire_button(b)`. Enemies grab `random_step()/random_weird()`
  for their own 3D players. **Swap a sound = change the base name in `sfx.gd`.**
- `Settings` — volume/sensitivity/fullscreen, persisted to `user://settings.cfg`;
  F toggles fullscreen (only works in a non-embedded window).
- `SaveManager` — 3 JSON slots (`user://save_N.json`): player pos/health/score/
  exotic matter/coins/quest-active/collected artifacts. `apply_pending()` (called by
  main.gd) waits 2 frames then applies.
- `Dialogue` — a text dialogue box (autoload scene `dialogue.tscn`). `start(speaker,
  lines)`, E/Space advances, `finished` signal; `active` is true while open. NPCs
  drive it. `Game.cinematic` (set by the NPC around dialogue + the finale) freezes the
  player, zooms the camera in, and makes enemies stand down.

**Scenes**: `title.tscn` (synthwave shader bg) → `main.tscn` (the island) →
`city.tscn` (level 2). **Both levels' roots are a `Main` node running `main.gd`** —
so day/night, enemy respawn and the quest wiring are shared; only the ground
differs (`island.gd` on `Island`, `city.gd` on `City`, both in group `"island"`
and both exposing `height_at`/`is_walkable`). Don't read `city.gd` expecting
level logic — it only builds terrain. Reusable
instances: `collectible.tscn` (artifact — group `"artifact"`), `exotic_matter.tscn`
(rare enemy drop — group `"exotic"`), `coin.tscn` (common enemy drop — group
`"coin"`), `npc.tscn` (quest-giver "Spencer" — group `"npc"`), `enemy.tscn`,
`launch_pad.tscn`, `moving_platform.tscn`, `platform.tscn`.
Pause menu + end screen live in `main.tscn`
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
- Groups used: `player`, `artifact`, `exotic`, `coin`, `enemy`, `npc`, `island`.
- **Spencer's script** (`npc.gd`): idle chatter floats over his head in a Label3D
  bubble whenever you're near (the E prompt sits at waist height below it); the
  quest intro is per-level `intro_lines`; pestering him mid-hunt picks a random
  `mid_quest_lines` entry with `{left}`/`{have}`/`{total}` filled in, and
  `{grapple}` resolves from the cat's actual `grapple_price` so the quoted price
  can't drift from the shop's. **Artifact cutaways** are live in-engine, not
  video: on `Dialogue.line_shown(cutaway_line)` a temporary Camera3D orbits real
  Artifacts for `cutaway_hold` each (`cutaway_high_first` picks the rooftop ones
  in the city), then hands the view back. Artifacts are hidden before the quest
  starts, so the filmed ones are revealed for the shot and re-hidden after.
- **Quest gating**: artifacts hide + disable pickup until `Game.quest_active` (set by
  the Elder's first conversation, which emits `quest_started`). The win no longer
  fires on collecting the last artifact — the NPC calls `Game.complete_quest()` after
  its backflip. Save restores `quest_active` and re-emits `quest_started`.
- **Drops step out of buildings**: a head can die inside a building footprint,
  and a drop's landing height comes from `height_at()`, which is the STREET
  height and knows nothing about walls — so loot could settle where nobody can
  reach it, player included. `PickupUtil.nudge_into_the_open()` looks for a
  ceiling overhead (streets and island terrain have open sky; tree canopies
  aren't colliders) and walks it out to the nearest open spot.
- **Enemy drops** (`exotic_matter.gd`, `coin.gd`) spawn mid-air and **pop out in an
  arc** (`_vel` + `drop_gravity`, integrated in `_process` until they reach
  `height_at()`), then can't be collected for `arm_delay` seconds — so drops are
  visible before you sweep them up instead of vacuuming instantly under the kill.
- Enemies are on **collision layer 2**, player only collides with layer 1, so the
  player passes through enemies; the enemy's Detector Area handles the stomp.
- **Hero melee** (`player.gd`): LMB/J punch, RMB/K kick (airborne = flying kick).
  `AttackHitbox` (Area3D in front of Player, mask 2) is sampled after a per-attack
  `*_windup`; each hit calls `enemy.hit_by_player(from_pos, knockback, dmg)` →
  knockback + front/back hit reaction + retaliate; `max_hp` melee hits to kill
  (stomp still one-shots). Attack clips are one-shots played via `_play_oneshot`
  (speed + `kick_anim_start` seek); combat/emote clip names are `@export`s.
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
- **The lantern (L)** (`player.gd`): an OmniLight3D **above his head** — inside the
  model it would be boxed in by his own mesh and light nothing — plus a glowing
  duplicate of his material swapped in while lit. Enemies ask `lantern_is_on()`
  and **flee** it (`enemy.gd` `State.FLEE`, `light_fear_range`/`flee_speed`) —
  including from the CAR, which carries the lamp on its roof while you drive and
  keeps the hidden hero at its own position, so the fear distance just works.
  A fleeing head runs *straight* away — water and all — so you can **herd it into
  the sea**, where it drowns (`drown_depth`). `fearless_scale` > 0 lets giant
  kaiju ignore the light. Heads only wander onto walkable ground, so they never
  drown on their own.
- **Heads always report in when lost.** `_fall_out()` (below `fall_limit`, e.g.
  off the world — the water is a mesh with no collider) and `_drown()` both emit
  `died` so the level respawns them; neither drops loot, so scaring heads off a
  ledge can't be farmed. Drowning is island-only in practice — the city is dry
  ground everywhere — but falling off the world works in both.
- **The blaster** (`weapon.gd`, a Node3D player.gd builds in code): bought from the
  cat (`gun_price`), **1** draws/holsters, **hold LMB** streams visible pellets
  (`bullet.gd`, also code-built — no .tscn), **Shift** scopes (FOV + look speed + the barrel locks onto the reticle — hip
  fire leaves the gun riding the hand animation, which wobbles up to ~36 deg
  because there is no aim pose; `_aim_gun_at_reticle` ramps a 0..1 blend rather
  than easing exponentially, since the hand moves every frame and an ease would
  chase a target that never stops moving).
  Pellets move by SWEPT RAYCAST, not Area3D overlap — at 44 m/s a pellet covers
  more ground per frame than its own diameter (it would tunnel through thin
  walls), and a ray reports the surface normal the `bouncy` upgrade bounces
  off. Fire behaviour is entirely `weapon.gd MODES`
  (`pellet`/`rapid`/`heavy`/`laser`/`bouncy`
  — `laser` sets `beam: true` and holds a raycast beam instead of spawning
  pellets, damaging on the mode's interval); a
  `weapon_upgrade.gd` pickup just swaps `Game.weapon_mode`, so a new upgrade is a
  new dictionary row. Ammo is per-level (`Game.starting_ammo` on `new_run`),
  refilled by scattered `ammo_pickup.gd` crates or bought from the cat.
  `main.gd _scatter_pickups()` places crates + upgrades procedurally on walkable
  ground, so both levels get them with no scene edits. **You can shoot while
  driving**: `weapon._rig()`/`_aim_camera()` switch to the car + its ChaseCam,
  bullets ignore the `vehicle` group, and the crosshair updates from the player's
  `_process` (the car disables his `_physics_process`).
- **The shop** (`shop_menu.gd`, code-built CanvasLayer the cat spawns): talking to
  Biscuit opens a selectable window — each row is a real `Button`, which is what
  gives arrow-key focus movement, hover and clicking for free. `cat._stock()`
  rebuilds the list after every purchase so prices/affordability stay honest.
  Talking to her plays a greeting (zoomed-in dialogue) and then a 3-way menu:
  **Enter shop** / **Take Biscuit for a walk** / **Leave**. The shop sells the
  hook, the blaster, ammo, a full refill, and a **Standard Barrel** that strips a
  weapon upgrade back to `pellet`.
- **Taking Biscuit for a walk** (`cat.gd` `_following`): she trots at heel
  (`follow_speed`/`follow_distance`, teleporting to catch up past
  `follow_teleport_dist`) and hoovers up coins, Exotic Matter and ammo within
  `fetch_radius`, giving up on anything she can't reach after `fetch_give_up`
  seconds of no progress and blacklisting it (a coin behind a wall would
  otherwise loop her for ever — the stuck rescue below never covered this,
  because the fetch branch returns before it). She calls each pickup's public
  `collect()` — the same path
  walking over it takes — so fetching can never drift from normal pickup
  behaviour. Artifacts are excluded unless `fetch_artifacts` is on. Because the
  menu lives on her, a walk also means a **portable shop**. She has **no
  collision body** (plain Node3D moved by hand), so walls are found with a
  forward raycast and the ground with a downward one — **not** `building_top_at`,
  which is per-BLOCK (it reports a roof height across a whole block, pavement
  included) and useless as a wall test. Avoidance is local only, so a
  no-progress timer (`stuck_time`) teleports her to your heel rather than
  pathfinding; launch pads fling her (`_check_launch_pads`, she can't trigger
  their Area3D herself) and can't re-fire until she steps off — unless you're
  stood by the pad too, in which case you can both keep bouncing.
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

**Props (guns, crates) — NOT the character pipeline.** No A-Pose/rig/animation:
generate, remesh to ~10K, export glb, rigging off. Meshy ships **4096px** textures
regardless (its texture tool's floor is 2048 and the download panel offers no
size option), which makes a 1-inch prop weigh 30-130 MB — GitHub hard-rejects
anything over 100 MB. Fix it locally:

```bash
python3 tools/shrink_glb_textures.py assets/models/gun-eyeball-model-remesh-10k.glb \
    assets/models/gun_eyeball.glb --max 1024      # 32.5 MB -> 1.1 MB, geometry untouched
```
Raw `gun-*-model*` exports are gitignored; only the shrunk `gun_*.glb` are committed.

**Holding a prop**: `weapon.gd _setup_gun_visual()` hangs the model off a
`BoneAttachment3D` on the hero's `RightHand` (24-bone rig). Meshy bakes a ~100x
scale into that rig, so `_fit_gun()` divides the bone's world scale back out —
which is why `gun_length` is a true measurement in metres. `gun_offset` /
`gun_rotation_deg` are for nudging it into the grip by eye.

**Outside animations (Mixamo, mocap) — `tools/retarget_mixamo.gd`.** His 24 bones
use standard humanoid names, so Mixamo clips retarget onto him with no Blender:

```bash
Godot --headless --path . --script tools/retarget_mixamo.gd ++ \
    "res://assets/models/Sneak Walk.fbx" mixamo_com res://assets/animations/sneak_walk.res
```

Three things that are easy to get wrong, and were:
- Bone tracks must address the skeleton NODE (`Armature/Skeleton3D:Hips`).
  `.:Hips` binds to nothing — the clip plays and the rig only wobbles.
- The rotation delta must be converted BETWEEN the two rigs' bone frames or he
  turns inside out: `C = Hg⁻¹·Sg`, `hero_local = hero_rest·(C·delta·C⁻¹)`.
- Hips POSITION has to come across too (scaled, X/Z pinned) or the pelvis stays
  frozen while the legs flail. Retargeted clips therefore load **after**
  `_strip_root_motion()`, which would otherwise freeze exactly that.

Do NOT "fix" this via `hero_anim_merged.glb.import` — a BoneMap/Rest Fixer
mistake there breaks all 15 working clips. And note **Fix Silhouette cannot lower
his raised arms**: with a BoneMap it retargets tracks to PRESERVE the look, which
is the opposite of what's wanted. `scripts/arm_droop.gd` does that instead —
a plain node at `process_priority` 500, *not* a `SkeletonModifier3D`, whose
writes the AnimationPlayer overwrites because it poses the skeleton afterwards.

**Wind** (`assets/materials/foliage_sway.gdshader` + `scripts/foliage.gd`): the
foliage is MultiMesh, so nothing can be animated per-instance — a vertex shader
moves them all for free, and the shadow pass reuses it so shadows sway too. Two
details make it read as wind: the offset is masked by height SQUARED (trunks stay
planted, canopies move) and the phase comes from `MODEL_MATRIX[3]`, each
instance's world position, so neighbours are out of step. `Foliage.apply_sway()`
WRAPS each existing surface material rather than setting a `material_override`,
which would flatten a tree's trunk and canopy to one colour. Rocks are excluded
on purpose.

**Never edit a `.tscn`/`.tres` from the shell while the editor is OPEN.** Godot
holds its own in-memory copy and rewrites the file when it saves, silently
dropping external edits (this ate Spencer's island `intro_lines` once). Kill
Godot, edit, then relaunch — and grep the property back out to confirm. A
wholesale re-save is recognisable in a diff: `load_steps` changes, `uid=` appears
on every ext_resource, `anchors_preset` becomes `layout_mode`. Separately, Godot
omits properties that equal their script default, so a value vanishing from a
`.tscn` isn't always a loss — check the script's default first.

**Textures must be imported VRAM Compressed, not Lossless.** Godot imports a
texture as Lossless with `detect_3d/compress_to=1`, meaning "the first time I'm
rendered in 3D, silently reimport me". That reimport happens **while the game is
running from the editor**, swapping the resource underneath it — the asset renders
solid black until the process is restarted. It's intermittent (per texture, on
first sight), affects anything from Biscuit to the ground, and is EDITOR-ONLY:
`detect_3d` never runs in an exported build. All 3D textures are now
`compress/mode=2` with `detect_3d/compress_to=0`, so there's nothing left to
auto-detect. Check new imports with:

```bash
grep -l "detect_3d/compress_to=1" $(find . -name '*.import' ! -path './.godot/*')
```

## Gotchas

- `.ogg`/`.wav` default to looping on import — SFX force loop off in `sfx.gd`.
- Scaling a CharacterBody3D node (the giant enemy) is fine, but ground-snap must use
  the world-space half-height (`model_height*0.5*scale.y`).
- Save/load resets enemies to spawn (live enemy state isn't saved yet).
- **Modal UI must respect two things**: `PauseLayer` is `layer = 10`, so a modal
  has to sit BELOW it (a full-screen dim above it swallows the pause menu's
  clicks — you can pause but not press anything), and `pause_menu.gd` grabs
  `ui_cancel` in `_input`, so a modal must consume Esc in `_input` too and set
  a flag (`Game.shop_open`) that pause_menu checks — otherwise Esc pauses the
  game *behind* the modal instead of closing it.
- **Never mutate the hero's imported material in place.** It ships with
  `emission_enabled = true` (black emission ADDed over an emissive texture) and
  `metallic = 1.0`; turning that emission off unmasks his specular and he reads as
  weirdly shiny. The lantern (`player.gd`) instead keeps a glowing *duplicate* and
  swaps the whole material in/out, so unlit he is pixel-identical to the import.

## Status

Complete loop: title → play → talk to the Elder (quest-giver) → collect all 8
artifacts → turn them in (he celebrates) = win / lose (3 lives) → replay. Has:
hero movement (run/double-jump/sprint/roll) + **melee combat** (punch/kick/flying
kick, dances), 6 AI enemies (wander/chase/attack) with HP + knockback
that **respawn** and get **more aggressive at night**, artifacts + rare Exotic
Matter + coin drops (arc-pop pickups), pickup toasts, HUD (live 3D head portrait),
particles + full audio, a long-day/
short-night cycle, launch pads / moving + static platforms, settings, 3-slot
save/load.
Next ideas: more props (Meshy), deploy to itch.io (export → web build). See
`docs/ROADMAP.md`.
