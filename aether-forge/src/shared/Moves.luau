--!nonstrict
-- Moves: frame data for the player's moveset. Times are seconds from the start of the move.
--
--   active        window in which the hitbox is live (checked every frame)
--   chainFrom     earliest time a buffered attack can cancel into the next combo hit
--   comboGrace    after the move ends, pressing Light within this time continues the combo
--   dashCancel    list of {from, to} windows where a dash can cancel the move ("any" = always)
--   lunge         forward drive during startup {from, to, speed}
--   trail         weapon trail on/off window
--   hit           hitbox: "arc" (range + arc degrees in front) or "circle" (offset forward + radius)
--   hitstop/shake keys into Config.Feel so the tuning panel changes them live
--
-- The server re-checks range with some tolerance, and damage numbers come from here on both sides.

local Moves = {}

Moves.Light1 = {
	name = "Light1",
	kind = "Light",
	clip = "Light1",
	length = 0.34,
	active = { 0.065, 0.15 },
	chainFrom = 0.16,
	comboGrace = 0.32,
	dashCancel = "any",
	next = "Light2",
	damage = 9,
	crystalDamage = 1,
	knockback = 13,
	stagger = 0.3,
	hit = { shape = "arc", range = 7.8, arc = 130 },
	lunge = { from = 0.0, to = 0.1, speed = 22 },
	trail = { 0.03, 0.2 },
	hitstop = "HitstopLight",
	shake = "ShakeLight",
	swingSound = "Swing",
}

Moves.Light2 = {
	name = "Light2",
	kind = "Light",
	clip = "Light2",
	length = 0.34,
	active = { 0.065, 0.15 },
	chainFrom = 0.16,
	comboGrace = 0.32,
	dashCancel = "any",
	next = "Light3",
	damage = 10,
	crystalDamage = 1,
	knockback = 14,
	stagger = 0.3,
	hit = { shape = "arc", range = 7.8, arc = 130 },
	lunge = { from = 0.0, to = 0.1, speed = 22 },
	trail = { 0.03, 0.2 },
	hitstop = "HitstopLight",
	shake = "ShakeLight",
	swingSound = "Swing",
}

-- Finisher: a full spin that clears space around you.
Moves.Light3 = {
	name = "Light3",
	kind = "Light",
	clip = "Light3",
	length = 0.56,
	active = { 0.13, 0.27 },
	chainFrom = 999, -- combo ends here
	comboGrace = 0,
	dashCancel = "any",
	next = nil,
	damage = 16,
	crystalDamage = 1,
	knockback = 40,
	launch = 10,
	stagger = 0.55,
	hit = { shape = "circle", offset = 0.5, radius = 8.2 },
	lunge = { from = 0.02, to = 0.16, speed = 16 },
	trail = { 0.08, 0.32 },
	hitstop = "HitstopFinisher",
	shake = "ShakeFinisher",
	swingSound = "SwingBig",
}

-- Heavy Slam: big anticipation, ground impact, shatters crystals and breaks enemy windups.
Moves.Heavy = {
	name = "Heavy",
	kind = "Heavy",
	clip = "Heavy",
	length = 0.92,
	active = { 0.4, 0.47 },
	chainFrom = 0.66,
	comboGrace = 0,
	dashCancel = { { 0, 0.36 }, { 0.62, 0.92 } },
	next = nil,
	damage = 30,
	crystalDamage = 99,
	knockback = 70,
	launch = 22,
	stagger = 0.75,
	breaksWindup = true,
	hit = { shape = "circle", offset = 4.6, radius = 7.2 },
	lunge = { from = 0.3, to = 0.4, speed = 26 },
	trail = { 0.3, 0.5 },
	hitstop = "HitstopHeavy",
	shake = "ShakeHeavy",
	swingSound = "SwingHeavy",
}

Moves.Dash = {
	name = "Dash",
	kind = "Dash",
	clip = "Dash",
	length = 0.27,
	iframes = { 0, 0.21 },
	speedStart = 90,
	speedEnd = 26,
	cooldown = 0.4,
	-- You can attack out of a dash after this time (dash -> Light1 feels great for closing distance).
	attackFrom = 0.14,
}

Moves.Parry = {
	name = "Parry",
	kind = "Parry",
	clip = "Parry",
	length = 0.46,
	active = { 0.0, 0.17 },
	cooldown = 0.5,
}

-- Played after a successful parry; can be cancelled into anything immediately.
Moves.Riposte = {
	name = "Riposte",
	kind = "Riposte",
	clip = "Riposte",
	length = 0.32,
}

Moves.Hurt = {
	name = "Hurt",
	kind = "Hurt",
	clip = "Hurt",
	length = 0.32,
}

-- Server-side sanity limits: minimum seconds between two different swings of the same kind.
Moves.MinSwingInterval = {
	Light = 0.12,
	Heavy = 0.55,
}

-- Extra reach the server allows on top of the hitbox to cover latency.
Moves.ServerRangeTolerance = 6

return Moves
