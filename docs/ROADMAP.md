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
- [~] **7. Collectibles & economy rework** —
      [x] Renamed gems → **Artifacts** (the win-gating pickup) everywhere (group
          `"artifact"`, `Game.total_artifacts/collected_artifacts`, save keys, HUD).
      [x] **Exotic Matter** — rare violet pickup (`exotic_matter.tscn`) that heads
          sometimes drop when defeated (`exotic_drop_chance`, bigger heads likelier).
          Own counter (`Game.exotic_matter`), saved, does NOT gate the win.
      [x] Heads **respawn** after `enemy_respawn_delay` (main.gd re-instances them).
      [x] Day/night reweighted to a **long day / short night** (`day_fraction` 0.75);
          heads get **more aggressive at night** (detect/lose range + chase speed).
      [x] **HUD redesign** — bigger portrait, dark backing panel, large outlined
          color-coded worded labels (Artifacts / Exotic Matter / Lives).
      Art direction (both pickups): **ancient lost-civilization "natural tech"** —
      carved weathered stone + glowing gemstone power core + etched runes. Artifact
      = refined/stable (warm amber-gold glow, matches HUD); Exotic Matter = the raw,
      unstable version of the same energy (violet glow). Form = a geode: cracked
      stone orb revealing a glowing gem core.
      [x] **Meshy: Artifact model** (`artifact.glb`) — carved stone geode; script
          brightens albedo + adds texture-modulated warm-gold emission + a gold halo
          light so it glows as a power source while keeping stone detail.
      [x] **Meshy: Exotic Matter model** (`exotic_matter.glb`) — violet energy shard;
          uses the baked Meshy look + a violet halo light.
          (Both auto-fit to `model_size` ≈0.9 m via a runtime AABB measure.)
      [x] **Coins** (`coin.tscn`) — heads scatter a random handful (`coin_min/max`,
          more from bigger heads) per kill; each pops out in its own arc, spins/bobs,
          "ching" SFX. Counter in HUD + saved; no toast (too frequent). Currency for
          the future shop.
- [~] **8. Hero combat re-animation (Meshy)** — re-exported the hero with a combat
      set (`hero_anim_merged.glb`, 15 clips).
      [x] Melee: LMB/J punch (alternates Punch_Combo/Punch_Combo_1), RMB/K High_Kick
          on the ground, Rising_Flying_Kick in the air; AttackHitbox (front of player,
          mask 2) hits enemies after a per-attack wind-up; impactPunch hit SFX.
          Per-attack `*_anim_speed` / `*_windup` / `kick_anim_start` tune the feel.
      [x] Enemies: `max_hp` (melee hits; stomp still one-shots), `hit_by_player()`
          applies knockback (mass-scaled) + front/back Hit reaction + retaliation.
          Running into an enemy no longer flinches it — reactions are attack-only.
      [x] Player: Hit_Reaction on taking a hit, Dead on death, G/H dance emotes
          (All_Night_Dance / Breakdance_1990), cancelled by moving.
      [ ] Shoot — no shoot clip in this export yet; add projectile + wire when ready.
- [x] **9. NPC quest-giver (Meshy)** — "Spencer" (`npc.glb`: Idle_3, Electrocution_
      Reaction, Excited_Walk_M, Backflip, +locomotion). Stand near → world-space "Press
      E to talk" billboard → `Dialogue` autoload text box (E/Space to advance).
      - First talk starts the quest → artifacts appear (hidden/non-collectible until
        then, via `Game.quest_active` + `quest_started` signal; gated in collectible.gd).
      - Talking mid-quest plays the shock reaction + a "keep going" line; talking with
        the full set plays excited-walk → backflip (crossfaded, no pause) → `complete_
        quest()` ends the run. Collecting the last artifact no longer auto-wins.
      - `Game.cinematic` freezes the player + zooms the camera in during dialogue/finale
        and makes enemies stand down. Dialogue = text; audio later.
- [ ] **10. Shop & reality-bending weapons** — a vendor NPC where you spend
      **coins + Exotic Matter** to craft weapons that either have a ridiculous
      kill or a **reality-bending effect** on the world. Example idea: shoot an
      area and it turns "HD"/re-skins/warps. (Design + build later — placeholder
      note so we don't lose it.)
- [ ] **11. Level 2 & the portal** — finishing the artifact quest opens a
      **portal**; entering it plays a loading screen / cutscene, then loads a
      **much bigger Level 2** (to be designed together).

## Folder layout
- `scenes/`   — Godot scenes (`.tscn`). `main.tscn` is the whole level for now.
- `scripts/`  — GDScript code (`.gd`).
- `assets/models/`     — 3D models imported from Meshy (`.glb`).
- `assets/materials/`  — textures & materials.
- `docs/`     — this roadmap, plus Meshy prompt notes as we go.

## Controls (current)
WASD move · mouse look · Space jump · Esc frees the mouse (click to recapture).
