extends Node
# The "Game brain" — a global singleton (autoload) any script can reach by the
# name `Game`. It holds score + health and shouts signals when they change, so
# the HUD can update without every object needing to know about every other one.

signal score_changed(score: int, total: int)
signal health_changed(health: int, max_health: int)
signal lives_changed(lives: int, max_lives: int)
signal all_gems_collected()
signal game_over()

var total_gems: int = 0   # how many gems exist in the level
var score: int = 0        # how many you've picked up
var collected_gems: Array = []   # node names of collected gems (for saving)
var max_health: int = 5
var health: int = 5
var max_lives: int = 3
var lives: int = 3

# Called by main.gd when a level loads: sets a fresh run with `total` gems.
func new_run(total: int) -> void:
	total_gems = total
	score = 0
	collected_gems = []
	health = max_health
	lives = max_lives
	score_changed.emit(score, total_gems)
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

# A gem was picked up (records its name so saves know which are gone).
func collect(gem_name: String) -> void:
	score += 1
	if not collected_gems.has(gem_name):
		collected_gems.append(gem_name)
	score_changed.emit(score, total_gems)
	if total_gems > 0 and score >= total_gems:
		all_gems_collected.emit()

# Returns true if this hit brought the player to 0 health.
func damage(amount: int = 1) -> bool:
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	return health <= 0

func revive() -> void:
	health = max_health
	health_changed.emit(health, max_health)
