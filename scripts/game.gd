extends Node
# The "Game brain" — a global singleton (autoload) any script can reach by the
# name `Game`. It holds score + health and shouts signals when they change, so
# the HUD can update without every object needing to know about every other one.

signal score_changed(score: int, total: int)
signal health_changed(health: int, max_health: int)
signal all_gems_collected()

var total_gems: int = 0   # how many gems exist in the level (counted at startup)
var score: int = 0        # how many you've picked up
var max_health: int = 3
var health: int = 3

# Each gem calls this in its _ready() so we know the total.
func register_gem() -> void:
	total_gems += 1

func add_score(amount: int = 1) -> void:
	score += amount
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
