--!nonstrict
-- Aether Forge server entry point.
-- Builds the arena and the player character, then starts the services.

local ArenaBuilder = require(script.ArenaBuilder)
local CharacterService = require(script.CharacterService)
local EnemyService = require(script.EnemyService)
local CrystalService = require(script.CrystalService)
local WaveService = require(script.WaveService)
local CombatService = require(script.CombatService)

ArenaBuilder.setupCollisionGroups()
ArenaBuilder.setupLighting()
ArenaBuilder.build()

local ctx = {
	Characters = CharacterService,
	Enemies = EnemyService,
	Crystals = CrystalService,
	Waves = WaveService,
	Combat = CombatService,
}

CharacterService.init(ctx)
EnemyService.init(ctx)
CrystalService.init(ctx)
CombatService.init(ctx)
WaveService.init(ctx)

print("[Aether Forge] server ready")
