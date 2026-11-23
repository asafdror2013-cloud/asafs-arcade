--!nonstrict
-- Config: every tuning number for the vertical slice lives here.
-- The in-game tuning panel (press T in Studio) edits the "Feel" and "Camera" values live on the client.
-- Values the server uses (enemy timings, damage) need a restart of the play session after editing.
-- All times are in seconds, distances in studs.

local Config = {}

Config.Player = {
	MaxHP = 100,
	WalkSpeed = 21,
	-- Walk speed kept while an attack plays (small drift keeps it from feeling sticky).
	AttackWalkSpeed = 4,
	-- How fast the character turns to face its move direction (higher = snappier).
	TurnSharpness = 28,
	-- After taking a hit: short stun, then mercy invulnerability.
	HurtStun = 0.32,
	HurtIFrames = 0.75,
	HurtKnockback = 34,
	-- Soft body radius used to keep the player from walking into enemies.
	BodyRadius = 1.4,
	-- Riposte: bonus damage window after a successful parry.
	RiposteDuration = 1.6,
	RiposteDamageMult = 1.5,
}

-- Game-feel values the tuning panel exposes.
Config.Feel = {
	HitstopLight = 0.06,
	HitstopFinisher = 0.11,
	HitstopHeavy = 0.17,
	HitstopCrystal = 0.07,
	HitstopParry = 0.09,
	-- Camera trauma added per event (0..1, shake strength grows with trauma squared).
	ShakeLight = 0.22,
	ShakeFinisher = 0.4,
	ShakeHeavy = 0.72,
	ShakeParry = 0.42,
	ShakeHurt = 0.5,
	ShakeSlamWhiff = 0.3,
	-- The enemy "glint" (flash + ping) appears this long before a strike lands. Reacting to it
	-- (~0.2s human reaction) lands your parry inside the parry window.
	GlintLead = 0.38,
	-- Parry slow-motion (real seconds and time scale).
	ParrySlowmoScale = 0.22,
	ParrySlowmoDuration = 0.38,
	-- Aim assist: attacks snap toward the best enemy inside this cone.
	SoftLockRange = 15,
	SoftLockAngle = 60,
	-- Light attacks pull you toward a locked target when it is within this distance.
	LungeMagnet = 9,
	-- Inputs pressed slightly early are remembered for this long.
	InputBuffer = 0.2,
	-- Global client time scale, for inspecting animations (tuning panel "Slow-mo").
	DebugTimeScale = 1,
}

Config.Camera = {
	Distance = 40,
	MinDistance = 26,
	MaxDistance = 58,
	Pitch = 54, -- degrees down from horizontal
	FOV = 52,
	FollowSharpness = 9,
	-- The camera leads slightly toward where you are moving / aiming.
	Lead = 3.5,
	ShakeMaxOffset = 1.1,
	ShakeMaxRoll = 2.6, -- degrees
	ShakeFrequency = 22,
	TraumaDecay = 1.9,
}

-- Every enemy attack has the same timeline shape: windup (telegraph) -> strike -> recover.
Config.Enemy = {
	Brute = {
		MaxHP = 120,
		MoveSpeed = 12.5,
		TurnSharpness = 7,
		Radius = 2.0,
		Mass = 30, -- only used for knockback feel scaling (bigger = flies less)
		AttackRange = 7.5, -- strike reach from its center
		AttackArc = 110, -- degrees
		Engage = 6.2, -- starts the windup when this close
		Windup = 0.72,
		-- During the last part of the windup the brute stops turning, so you can read and dodge it.
		TrackUntil = 0.55, -- fraction of the windup
		Recover = 0.75,
		Cooldown = 1.1,
		Damage = 18,
		-- Hits with less stagger than this don't interrupt it (light slashes only make it shudder),
		-- so you can't stun-lock a Brute: use the finisher, the Heavy Slam or a parry.
		StaggerThreshold = 0.5,
		ParryStun = 1.7,
		SpawnTime = 1.0,
		XP = 10,
	},
	-- Seconds the server waits for a client to report how an incoming strike resolved.
	StrikeReportTimeout = 0.45,
	-- How long enemies stay slowed when someone parries nearby.
	ParrySlowRadius = 36,
}

-- Crystal nodes. Common (Aether) crystals sit on the inner rings; elemental crystals grow at the
-- risky arena edge and pay the ore that elemental upgrades need.
Config.Crystal = {
	Common = { element = "Aether", HP = 3, Ore = 3, Color = Color3.fromRGB(80, 230, 255), Respawn = 9 },
	Fire = { element = "Fire", HP = 5, Ore = 3, Color = Color3.fromRGB(255, 96, 36), Respawn = 13 },
	Storm = { element = "Storm", HP = 5, Ore = 3, Color = Color3.fromRGB(190, 120, 255), Respawn = 13 },
	Frost = { element = "Frost", HP = 5, Ore = 3, Color = Color3.fromRGB(160, 225, 255), Respawn = 13 },
	Spots = 3, -- common nodes alive at once
	ElementalSpots = 1, -- elemental nodes alive at once (2 from wave 4)
	ElementalSpotsLate = 2,
}

Config.Waves = {
	FirstDelay = 3.5,
	Breather = 12, -- time to mine and forge between waves
	SpawnInterval = 1.1,
	-- Enemies per wave = Base + (wave - 1) * Growth, capped.
	Base = 1,
	Growth = 1,
	Max = 7,
	HPScale = 0.1, -- +10% HP per wave
	WindupScale = 0.03, -- windups get 3% faster per wave
	MinWindup = 0.5,
}

Config.Arena = {
	Radius = 60,
}

-- Colors used across the game so the palette stays consistent.
Config.Palette = {
	Aether = Color3.fromRGB(70, 225, 255),
	AetherDeep = Color3.fromRGB(30, 120, 255),
	Ember = Color3.fromRGB(255, 136, 48),
	Molten = Color3.fromRGB(255, 78, 34),
	Gold = Color3.fromRGB(255, 214, 102),
	Danger = Color3.fromRGB(255, 60, 60),
	White = Color3.fromRGB(255, 255, 255),
}

return Config
