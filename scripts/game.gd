extends Node
# The "Game brain" — a global singleton (autoload) any script can reach by the
# name `Game`. It holds score + health and shouts signals when they change, so
# the HUD can update without every object needing to know about every other one.

signal score_changed(score: int, total: int)
signal exotic_changed(count: int)
signal coins_changed(count: int)
signal artifact_collected(score: int, total: int)   # fires only on an actual pickup
signal exotic_collected(count: int)                  # fires only on an actual pickup
signal health_changed(health: int, max_health: int)
signal lives_changed(lives: int, max_lives: int)
signal all_artifacts_collected()
signal quest_started()          # the Elder's artifact hunt has begun
signal game_over()
signal ammo_changed(ammo: int, max_ammo: int)
signal weapon_mode_changed(mode: String)
signal gun_acquired()            # so levels can put blaster pickups out

var total_artifacts: int = 0   # how many artifacts exist in the level
var score: int = 0             # how many you've picked up
var collected_artifacts: Array = []   # node names of collected artifacts (for saving)
var exotic_matter: int = 0     # rare pickup dropped by defeated heads
var coins: int = 0             # common currency dropped by defeated heads
var max_health: int = 5
var health: int = 5
var max_lives: int = 3
var lives: int = 3
var is_night: bool = false      # set by main.gd's day/night cycle; enemies read it
var quest_active: bool = false  # artifacts stay hidden until the Elder starts the hunt
var quest_done: bool = false    # THIS world's hunt is finished (its portal stays open)
# What survives a trip through a portal, and what doesn't:
#   GLOBAL  — coins, Exotic Matter, the shop unlocks. They're yours, everywhere.
#   PER-MAP — artifacts, quest progress, whether the portal has been opened.
# world_state keeps a record per scene path so the island remembers its own hunt
# while you're off in the city, and vice versa.
var world_state: Dictionary = {}
var current_world: String = ""
var cinematic: bool = false     # true during a scripted moment (dialogue/finale): freeze the player
var driving: bool = false        # true while the player is driving the vehicle
var has_grapple: bool = false    # bought from the shop; persistent unlock (survives new_run)
# --- Blaster: bought from the shop (persistent), ammo + fire mode are per-run ---
var has_gun: bool = false        # persistent unlock, like has_grapple
# True while Biscuit's shop window is up. The pause menu checks this so Esc
# closes the shop instead of pausing underneath it.
var shop_open: bool = false
var max_ammo: int = 999
var ammo: int = 0
var starting_ammo: int = 500     # topped up to this whenever a level loads
var weapon_mode: String = "pellet"   # pellet | rapid | heavy — upgrades found on the map

# Spend coins on a shop item. Returns true if the purchase went through.
func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true

# Called by main.gd when a level loads: sets a fresh run with `total` artifacts.
# Arriving in a world: restore ITS progress, keep your wallet. Called on every
# level load, including coming back through a portal.
func enter_world(path: String, total: int) -> void:
	current_world = path
	total_artifacts = total
	var st: Dictionary = world_state.get(path, {})
	score = int(st.get("score", 0))
	collected_artifacts = (st.get("collected", []) as Array).duplicate()
	quest_active = bool(st.get("quest_active", false))
	quest_done = bool(st.get("quest_done", false))
	save_world()
	driving = false
	health = max_health
	lives = max_lives
	ammo = starting_ammo if has_gun else 0
	weapon_mode = "pellet"
	ammo_changed.emit(ammo, max_ammo)
	weapon_mode_changed.emit(weapon_mode)
	score_changed.emit(score, total_artifacts)
	exotic_changed.emit(exotic_matter)
	coins_changed.emit(coins)
	health_changed.emit(health, max_health)
	lives_changed.emit(lives, max_lives)

# Write this world's progress back into the record. Called whenever any of it
# changes, so a portal can be taken at any moment without losing anything.
func save_world() -> void:
	if current_world == "":
		return
	world_state[current_world] = {
		"score": score,
		"collected": collected_artifacts.duplicate(),
		"quest_active": quest_active,
		"quest_done": quest_done,
	}

# A genuinely fresh start: wipes every world AND the wallet (debug "Reset run").
func new_run(total: int) -> void:
	world_state = {}
	exotic_matter = 0
	coins = 0
	quest_done = false
	total_artifacts = total
	score = 0
	collected_artifacts = []
	quest_active = false
	driving = false
	health = max_health
	lives = max_lives
	# Ammo + fire mode are per-level: you start each level stocked with the basic
	# blaster, and any upgrade you found stays behind with the level you found it in.
	ammo = starting_ammo if has_gun else 0
	weapon_mode = "pellet"
	ammo_changed.emit(ammo, max_ammo)
	weapon_mode_changed.emit(weapon_mode)
	score_changed.emit(score, total_artifacts)
	exotic_changed.emit(exotic_matter)
	coins_changed.emit(coins)
	health_changed.emit(health, max_health)
	lives_changed.emit(lives, max_lives)

# Player died. Returns true if that was the last life (game over).
func lose_life() -> bool:
	lives -= 1
	lives_changed.emit(lives, max_lives)
	if lives <= 0:
		game_over.emit()
		return true
	health = max_health
	health_changed.emit(health, max_health)
	return false

# An artifact was picked up (records its name so saves know which are gone).
func collect(artifact_name: String) -> void:
	score += 1
	if not collected_artifacts.has(artifact_name):
		collected_artifacts.append(artifact_name)
	save_world()
	score_changed.emit(score, total_artifacts)
	artifact_collected.emit(score, total_artifacts)
	# NOTE: winning no longer fires here — you must return to the Elder to finish
	# the quest (he celebrates, then complete_quest() ends the run).

# Called by the Elder once you turn in a full set of artifacts (after his backflip).
func complete_quest() -> void:
	quest_done = true          # this world's portal stays open from now on
	save_world()
	all_artifacts_collected.emit()

func artifacts_all_found() -> bool:
	return total_artifacts > 0 and score >= total_artifacts

# A blob of Exotic Matter was picked up (dropped by a defeated head).
func collect_exotic(amount: int = 1) -> void:
	exotic_matter += amount
	exotic_changed.emit(exotic_matter)
	exotic_collected.emit(exotic_matter)

# A coin was picked up. No toast (coins are frequent) — just the counter + sound.
func collect_coin(amount: int = 1) -> void:
	coins += amount
	coins_changed.emit(coins)

# Returns true if this hit brought the player to 0 health.
func damage(amount: int = 1) -> bool:
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	return health <= 0

func revive() -> void:
	health = max_health
	health_changed.emit(health, max_health)

# The Elder gives the quest: reveal the artifacts.
func begin_quest() -> void:
	if quest_active:
		return
	quest_active = true
	save_world()
	quest_started.emit()

# --- Blaster ------------------------------------------------------------------

# Always grant the blaster through here — the signal is what makes ammo crates
# and weapon upgrades appear in the level.
func grant_gun() -> void:
	if has_gun:
		return
	has_gun = true
	ammo = maxi(ammo, starting_ammo)
	ammo_changed.emit(ammo, max_ammo)
	gun_acquired.emit()

func collect_ammo(amount: int) -> void:
	ammo = mini(ammo + amount, max_ammo)
	ammo_changed.emit(ammo, max_ammo)

func spend_ammo(amount: int = 1) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	ammo_changed.emit(ammo, max_ammo)
	return true

func set_weapon_mode(mode: String) -> void:
	weapon_mode = mode
	weapon_mode_changed.emit(mode)
