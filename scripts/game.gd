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
signal game_over()

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

# Called by main.gd when a level loads: sets a fresh run with `total` artifacts.
func new_run(total: int) -> void:
	total_artifacts = total
	score = 0
	collected_artifacts = []
	exotic_matter = 0
	coins = 0
	health = max_health
	lives = max_lives
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
	score_changed.emit(score, total_artifacts)
	artifact_collected.emit(score, total_artifacts)
	if total_artifacts > 0 and score >= total_artifacts:
		all_artifacts_collected.emit()

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
