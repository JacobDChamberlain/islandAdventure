# Island Adventure — Prototype Roadmap

A 3D platformer / collectathon in the spirit of Jak & Daxter, Ratchet & Clank,
Spyro, and Sly Cooper. Built in **Godot 4.5**. Art generated with **Meshy.ai**,
tweaked in **Blender** only when needed.

## Guiding principle: greybox first
Build the whole game with ugly placeholder blocks and get it *fun*, THEN swap in
art. Never make art for a game that isn't fun to play yet.

## Phases
- [x] **1. Movement greybox** — capsule hero runs & jumps around a placeholder
      island with a follow camera. Tuned: fast run, snappy jump, double-jump,
      air-momentum.
- [x] **2. Game loop** — 8 spinning gems + score counter, patrolling enemies you
      stomp (bounce off head) or get hit by, HP + respawn + invulnerability, HUD.
- [x] **3. The hero** — generated an edgy adventurer in Meshy, imported the
      textured .glb, auto-fit + swapped it in for the capsule. Movement unchanged.
      NOTE: Meshy & Tripo both paywall model *downloads*; subscribed to Meshy to
      export. Free AI-3D download alt if needed later: Hunyuan3D on Hugging Face.
- [~] **4. The world** —
      [x] Procedural organic island terrain (`island.gd`): noise coastline, hills,
          beach→grass→forest→rock coloring, surrounding water, trimesh collision.
          Player/gems/enemies snap to it via `height_at()`.
      [x] Scatter foliage via MultiMesh in `island.gd`: procedural low-poly pines
          (+ a few giants), bushes, rocks, grass; placed by elevation/slope; grass
          shadows off + bounded shadow distance for perf. Swap in CC0/Meshy meshes later.
      [x] Enemies = user's rigged "nightmare head" (nightmare.glb, 20 clips) with a
          wander/pause/react state machine; 5 roaming + 1 giant. Trees & rocks have
          per-instance static collision.
      [x] Enemy AI: chase the player on sight, telegraphed attack animations
          (kicks/stomps/slams) that deal damage; player health raised to 5.
      [x] Juice: particle poofs (Fx autoload) on stomp/gem, red damage flash.
      [x] Audio (Sfx autoload, Kenney CC0): player stomp/gem/hurt/jump + paced
          footsteps; enemies have positional 3D footsteps (louder/deeper by size)
          and play random sci-fi "weird noises" on idle/attack. Sounds are easily
          swappable (change the base names / folders in sfx.gd).
      [x] Title screen (synthwave shader bg) + pause menu; menu nav/select sounds.
      [x] Settings (volume/sensitivity/fullscreen, persisted, F toggles fullscreen)
          and Save/Load with 3 JSON slots (player pos/health/gems; enemies reset).
      [x] Win/lose loop: collect all gems = YOU WIN; 3 lives, death (enemy or
          water) costs one, 0 lives = GAME OVER. End screen: Play Again / Quit.
      [x] Day/night cycle (animated sun/sky/ambient); launch pads, moving platforms
          (footprint-aware terrain clearance), static climb platforms; gems re-scattered
          (3 float high above pads, 1 tops the climb, 4 on ground). Added CLAUDE.md.
      [ ] More props (Meshy); crouch clip + Shift-crouch; nicer SFX; deploy to itch.
- [x] **5. Animation** — regenerated the hero in Meshy with **A-Pose** (Pro
      perk; rigs far cleaner than a dynamic pose). Remeshed to 30K, auto-rigged,
      applied 7 clips (Idle_6, Running, RunFast, Walking, Jump_with_Arms_Open,
      Run_and_Jump, Run_and_Leap). Exported one .glb (Rigged Character + All
      Added + Single file) = `assets/models/hero_anim_merged.glb`. player.gd has
      a simple state machine (idle/run/jump) via `_update_animation`.
- [ ] **6. Polish** — sound, particles, collectible sparkle, a goal, a title
      screen.

## Folder layout
- `scenes/`   — Godot scenes (`.tscn`). `main.tscn` is the whole level for now.
- `scripts/`  — GDScript code (`.gd`).
- `assets/models/`     — 3D models imported from Meshy (`.glb`).
- `assets/materials/`  — textures & materials.
- `docs/`     — this roadmap, plus Meshy prompt notes as we go.

## Controls (current)
WASD move · mouse look · Space jump · Esc frees the mouse (click to recapture).
