--!nonstrict
-- Rigs: geometric low-poly models for the player (warrior-smith), the Brute enemy and weapons.
--
-- Everything is authored in "rest space": standing on the ground at the origin (y = 0), facing -Z,
-- the character's right hand on +X. Bones are parts joined by Motor6Ds that the procedural animator
-- drives; decor parts are welded to a bone. Weapon parts are authored in grip space (grip at the
-- origin, blade pointing along -Z).
--
-- Joint pivots use world-aligned frames, so pose angles read naturally:
--   x = pitch (arms/legs: + swings forward; torso/head: + leans back)
--   y = yaw   (+ turns left)
--   z = roll  (right arm: + raises out to the side; left arm: - raises out)

local Rigs = {}

local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local function cf(pos, rot)
	if rot then
		return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(rad(rot[1]), rad(rot[2]), rad(rot[3]))
	end
	return CFrame.new(pos)
end

-- part(bone, shape, size, pos, color, material, rot?, extra?)
local function part(bone, shape, size, pos, color, material, rot, extra)
	local p = { bone = bone, shape = shape, size = size, cf = cf(pos, rot), color = color, material = material }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function swapSide(name)
	if string.sub(name, 1, 1) == "R" then
		return "L" .. string.sub(name, 2)
	elseif string.sub(name, 1, 1) == "L" then
		return "R" .. string.sub(name, 2)
	end
	return name
end

-- Mirror decor across the YZ plane (right side -> left side).
local function mirrored(list)
	local out = {}
	for _, p in list do
		local pos = p.cf.Position
		local rx, ry, rz = p.cf:ToEulerAnglesYXZ()
		local m = table.clone(p)
		m.bone = swapSide(p.bone)
		m.cf = CFrame.new(V(-pos.X, pos.Y, pos.Z)) * CFrame.fromEulerAnglesYXZ(rx, -ry, -rz)
		table.insert(out, m)
	end
	return out
end

local function append(dst, src)
	for _, v in src do
		table.insert(dst, v)
	end
	return dst
end

------------------------------------------------------------------------------------------------
-- Palette
------------------------------------------------------------------------------------------------
local STEEL = rgb(58, 62, 78)
local STEEL_LIGHT = rgb(132, 140, 160)
local BRONZE = rgb(200, 134, 66)
local LEATHER = rgb(96, 60, 40)
local CLOTH = rgb(38, 38, 50)
local SCARF = rgb(200, 58, 44)
local AETHER = rgb(70, 225, 255)

local OBSIDIAN = rgb(42, 38, 48)
local ROCK = rgb(78, 70, 78)
local MOLTEN = rgb(255, 86, 36)

------------------------------------------------------------------------------------------------
-- Player: the warrior-smith
------------------------------------------------------------------------------------------------
do
	local bones = {
		{ name = "Hips", parent = "HumanoidRootPart", joint = "Root", size = V(1.7, 0.7, 1.05), pos = V(0, 2.75, 0), pivot = V(0, 2.75, 0), color = CLOTH, material = "Fabric" },
		{ name = "Chest", parent = "Hips", joint = "Waist", size = V(2.1, 1.0, 1.15), pos = V(0, 4.15, 0), pivot = V(0, 3.2, 0), color = STEEL, material = "Metal" },
		{ name = "Head", parent = "Chest", joint = "Neck", size = V(0.95, 1.0, 1.0), pos = V(0, 5.25, 0), pivot = V(0, 4.72, 0), color = STEEL, material = "Metal" },

		{ name = "RUpperArm", parent = "Chest", joint = "RShoulder", size = V(0.66, 1.1, 0.7), pos = V(1.42, 4.0, 0), pivot = V(1.42, 4.45, 0), color = LEATHER, material = "Leather" },
		{ name = "RForearm", parent = "RUpperArm", joint = "RElbow", size = V(0.7, 1.0, 0.72), pos = V(1.42, 2.97, 0), pivot = V(1.42, 3.45, 0), color = BRONZE, material = "Metal" },
		{ name = "Weapon", parent = "RForearm", joint = "Grip", size = V(0.2, 0.2, 0.2), pos = V(1.42, 2.2, 0), pivot = V(1.42, 2.2, 0), invisible = true },
		{ name = "LUpperArm", parent = "Chest", joint = "LShoulder", size = V(0.66, 1.1, 0.7), pos = V(-1.42, 4.0, 0), pivot = V(-1.42, 4.45, 0), color = LEATHER, material = "Leather" },
		{ name = "LForearm", parent = "LUpperArm", joint = "LElbow", size = V(0.7, 1.0, 0.72), pos = V(-1.42, 2.97, 0), pivot = V(-1.42, 3.45, 0), color = BRONZE, material = "Metal" },

		{ name = "RThigh", parent = "Hips", joint = "RHip", size = V(0.74, 1.1, 0.8), pos = V(0.45, 1.95, 0), pivot = V(0.45, 2.5, 0), color = CLOTH, material = "Fabric" },
		{ name = "RShin", parent = "RThigh", joint = "RKnee", size = V(0.66, 1.0, 0.72), pos = V(0.45, 0.9, 0), pivot = V(0.45, 1.4, 0), color = STEEL, material = "Metal" },
		{ name = "RFoot", parent = "RShin", joint = "RAnkle", size = V(0.78, 0.42, 1.2), pos = V(0.45, 0.21, -0.16), pivot = V(0.45, 0.4, 0), color = LEATHER, material = "Leather" },
		{ name = "LThigh", parent = "Hips", joint = "LHip", size = V(0.74, 1.1, 0.8), pos = V(-0.45, 1.95, 0), pivot = V(-0.45, 2.5, 0), color = CLOTH, material = "Fabric" },
		{ name = "LShin", parent = "LThigh", joint = "LKnee", size = V(0.66, 1.0, 0.72), pos = V(-0.45, 0.9, 0), pivot = V(-0.45, 1.4, 0), color = STEEL, material = "Metal" },
		{ name = "LFoot", parent = "LShin", joint = "LAnkle", size = V(0.78, 0.42, 1.2), pos = V(-0.45, 0.21, -0.16), pivot = V(-0.45, 0.4, 0), color = LEATHER, material = "Leather" },
	}

	local right = {
		-- pauldron + trim
		part("RUpperArm", "Block", V(1.0, 0.42, 1.0), V(1.52, 4.62, 0), STEEL_LIGHT, "Metal", { 0, 0, -14 }),
		part("RUpperArm", "Block", V(1.03, 0.1, 1.03), V(1.5, 4.4, 0), BRONZE, "Metal", { 0, 0, -14 }),
		-- gauntlet cuff, fist, knuckles
		part("RForearm", "Block", V(0.84, 0.36, 0.86), V(1.42, 3.22, 0), BRONZE, "Metal"),
		part("RForearm", "Block", V(0.62, 0.5, 0.66), V(1.42, 2.22, 0), STEEL, "Metal"),
		part("RForearm", "Block", V(0.66, 0.22, 0.2), V(1.42, 2.27, -0.32), BRONZE, "Metal"),
		-- hip tasset
		part("Hips", "Block", V(0.42, 0.62, 0.92), V(0.97, 2.6, 0), STEEL, "Metal", { 0, 0, 10 }),
		-- knee cop, greave, toe cap
		part("RShin", "Block", V(0.6, 0.42, 0.26), V(0.45, 1.42, -0.42), STEEL_LIGHT, "Metal"),
		part("RShin", "Block", V(0.58, 0.66, 0.12), V(0.45, 0.9, -0.38), STEEL_LIGHT, "Metal"),
		part("RFoot", "Block", V(0.82, 0.3, 0.36), V(0.45, 0.16, -0.66), STEEL, "Metal"),
		-- helmet cheek guard
		part("Head", "Block", V(0.12, 0.62, 0.72), V(0.52, 5.1, -0.06), STEEL_LIGHT, "Metal"),
	}

	local decor = {
		-- torso
		part("Chest", "Block", V(1.55, 0.75, 0.95), V(0, 3.45, 0), LEATHER, "Leather"),
		part("Chest", "Block", V(1.9, 0.72, 0.26), V(0, 4.32, -0.6), STEEL_LIGHT, "Metal", { -12, 0, 0 }),
		part("Chest", "Block", V(0.36, 0.36, 0.12), V(0, 4.12, -0.76), AETHER, "Neon", { 0, 0, 45 }, { light = { color = AETHER, range = 9, brightness = 1.4 } }),
		part("Chest", "Block", V(1.9, 0.9, 0.2), V(0, 4.3, 0.62), STEEL, "Metal"),
		part("Chest", "Block", V(1.26, 0.32, 1.26), V(0, 4.76, 0), SCARF, "Fabric"),
		part("Chest", "Block", V(0.5, 0.95, 0.08), V(0.36, 4.25, 0.73), SCARF, "Fabric", { 10, 0, -8 }),
		-- helmet
		part("Head", "Block", V(1.05, 0.25, 1.1), V(0, 5.72, 0), STEEL_LIGHT, "Metal"),
		part("Head", "Block", V(0.74, 0.1, 0.06), V(0, 5.3, -0.51), AETHER, "Neon"),
		part("Head", "Block", V(0.86, 0.36, 0.08), V(0, 4.98, -0.52), STEEL_LIGHT, "Metal"),
		part("Head", "Wedge", V(0.16, 0.6, 1.2), V(0, 6.07, 0.1), BRONZE, "Metal"),
		-- belt, buckle, apron (it is a smith after all)
		part("Hips", "Block", V(1.8, 0.24, 1.12), V(0, 3.0, 0), LEATHER, "Leather"),
		part("Hips", "Block", V(0.36, 0.26, 0.08), V(0, 3.0, -0.6), BRONZE, "Metal"),
		part("Hips", "Block", V(1.15, 1.0, 0.1), V(0, 2.4, -0.6), LEATHER, "Leather", { 4, 0, 0 }),
		part("Hips", "Block", V(1.25, 0.85, 0.1), V(0, 2.45, 0.58), LEATHER, "Leather", { -4, 0, 0 }),
	}
	append(decor, right)
	append(decor, mirrored(right))

	Rigs.Player = {
		root = { name = "HumanoidRootPart", size = V(2, 2, 1), pos = V(0, 3.1, 0) },
		bones = bones,
		decor = decor,
		hipHeight = 2.1,
		-- Two-bone leg IK: thigh = hip->knee, shin = knee->ankle. Foot targets are in root space.
		legs = {
			R = { hip = "RHip", knee = "RKnee", ankle = "RAnkle", thigh = 1.1, shin = 1.0 },
			L = { hip = "LHip", knee = "LKnee", ankle = "LAnkle", thigh = 1.1, shin = 1.0 },
		},
		-- Two-bone arm IK: upper = shoulder->elbow, fore = elbow->grip point. Poles = default elbow
		-- direction (back and slightly out), in root space.
		arms = {
			R = { shoulder = "RShoulder", elbow = "RElbow", upper = 1.0, fore = 1.25, pole = V(0.35, -0.3, 0.9) },
			L = { shoulder = "LShoulder", elbow = "LElbow", upper = 1.0, fore = 1.25, pole = V(-0.35, -0.3, 0.9) },
		},
		grip = "Grip",
		weaponBone = "Weapon",
	}
end

------------------------------------------------------------------------------------------------
-- Weapons (grip space: grip at origin, blade along -Z, blade flat faces +-X)
------------------------------------------------------------------------------------------------
Rigs.Weapons = {}

Rigs.Weapons.EmberBlade = {
	displayName = "Ember Blade",
	glow = AETHER,
	trailBase = V(0, 0, -0.9),
	trailTip = V(0, 0, -4.75),
	parts = {
		part("Weapon", "Block", V(0.17, 0.17, 0.95), V(0, 0, 0.05), LEATHER, "Leather"),
		part("Weapon", "Block", V(0.3, 0.3, 0.3), V(0, 0, 0.64), BRONZE, "Metal", { 45, 0, 0 }),
		part("Weapon", "Block", V(0.24, 1.15, 0.26), V(0, 0, -0.52), BRONZE, "Metal"),
		part("Weapon", "Block", V(0.27, 0.2, 0.2), V(0, 0.52, -0.52), AETHER, "Neon"),
		part("Weapon", "Block", V(0.27, 0.2, 0.2), V(0, -0.52, -0.52), AETHER, "Neon"),
		part("Weapon", "Block", V(0.12, 0.46, 3.5), V(0, 0, -2.4), STEEL_LIGHT, "Metal"),
		part("Weapon", "Wedge", V(0.12, 0.46, 0.75), V(0, 0, -4.525), STEEL_LIGHT, "Metal"),
		part("Weapon", "Block", V(0.14, 0.07, 3.45), V(0, -0.21, -2.4), AETHER, "Neon"),
		part("Weapon", "Block", V(0.14, 0.05, 2.4), V(0, 0.06, -2.1), AETHER, "Neon"),
	},
}

local IRON = rgb(52, 44, 44)
local MOLTEN_W = rgb(255, 96, 30)
local EMBER_W = rgb(255, 160, 60)
local STORM = rgb(190, 120, 255)
local STORM_HOT = rgb(255, 240, 150)
local ICE = rgb(185, 230, 255)
local FROST = rgb(150, 220, 255)

-- Reforged after 3+ upgrades without an element: longer, double-edged, winged guard.
Rigs.Weapons.AetherReaver = {
	displayName = "Aether Reaver",
	glow = AETHER,
	trailBase = V(0, 0, -1.0),
	trailTip = V(0, 0, -5.4),
	parts = {
		part("Weapon", "Block", V(0.18, 0.18, 1.0), V(0, 0, 0.05), LEATHER, "Leather"),
		part("Weapon", "Block", V(0.3, 0.3, 0.3), V(0, 0, 0.68), AETHER, "Neon", { 45, 0, 45 }),
		part("Weapon", "Block", V(0.26, 1.45, 0.3), V(0, 0, -0.55), STEEL, "Metal"),
		part("Weapon", "Wedge", V(0.24, 0.5, 0.55), V(0, 0.92, -0.42), STEEL_LIGHT, "Metal", { -90, 0, 0 }),
		part("Weapon", "Wedge", V(0.24, 0.5, 0.55), V(0, -0.92, -0.42), STEEL_LIGHT, "Metal", { 90, 0, 0 }),
		part("Weapon", "Block", V(0.3, 0.3, 0.3), V(0, 0, -0.55), AETHER, "Neon", { 0, 0, 45 }),
		part("Weapon", "Block", V(0.14, 0.56, 4.0), V(0, 0, -2.7), STEEL_LIGHT, "Metal"),
		part("Weapon", "Wedge", V(0.14, 0.56, 0.9), V(0, 0, -5.15), STEEL_LIGHT, "Metal"),
		part("Weapon", "Block", V(0.16, 0.06, 3.9), V(0, -0.27, -2.7), AETHER, "Neon"),
		part("Weapon", "Block", V(0.16, 0.06, 3.9), V(0, 0.27, -2.7), AETHER, "Neon"),
		part("Weapon", "Block", V(0.16, 0.08, 3.0), V(0, 0, -2.4), rgb(40, 110, 255), "Neon"),
	},
}

-- Fire: a broad, heavy greatsword with a molten channel and flames.
Rigs.Weapons.FlameGreatsword = {
	displayName = "Flame Greatsword",
	glow = MOLTEN_W,
	fx = "Fire",
	trailBase = V(0, 0, -1.0),
	trailTip = V(0, 0, -5.95),
	parts = {
		part("Weapon", "Block", V(0.2, 0.2, 1.2), V(0, 0, 0.15), IRON, "Leather"),
		part("Weapon", "Block", V(0.36, 0.36, 0.36), V(0, 0, 0.86), MOLTEN_W, "Neon", { 45, 0, 45 }),
		part("Weapon", "Block", V(0.32, 1.75, 0.36), V(0, 0, -0.6), IRON, "Metal"),
		part("Weapon", "Wedge", V(0.3, 0.6, 0.5), V(0, 1.0, -0.45), MOLTEN_W, "Neon", { -90, 0, 0 }),
		part("Weapon", "Wedge", V(0.3, 0.6, 0.5), V(0, -1.0, -0.45), MOLTEN_W, "Neon", { 90, 0, 0 }),
		part("Weapon", "Block", V(0.18, 0.9, 4.4), V(0, 0, -2.98), rgb(72, 56, 52), "Metal"),
		part("Weapon", "Wedge", V(0.18, 0.9, 1.0), V(0, 0, -5.68), rgb(72, 56, 52), "Metal"),
		part("Weapon", "Block", V(0.2, 0.28, 4.0), V(0, 0.05, -2.85), MOLTEN_W, "Neon"),
		part("Weapon", "Block", V(0.2, 0.08, 4.3), V(0, -0.44, -2.95), EMBER_W, "Neon"),
	},
}

-- Storm: a jagged zig-zag cleaver crackling with violet lightning.
Rigs.Weapons.StormCleaver = {
	displayName = "Storm Cleaver",
	glow = STORM,
	fx = "Storm",
	trailBase = V(0, 0, -1.0),
	trailTip = V(0, 0, -5.4),
	parts = {
		part("Weapon", "Block", V(0.18, 0.18, 1.0), V(0, 0, 0.05), rgb(40, 36, 60), "Leather"),
		part("Weapon", "Block", V(0.3, 0.3, 0.3), V(0, 0, 0.68), STORM, "Neon", { 45, 0, 45 }),
		part("Weapon", "Block", V(0.26, 1.3, 0.28), V(0, 0, -0.52), STEEL, "Metal"),
		part("Weapon", "Block", V(0.3, 0.3, 0.3), V(0, 0, -0.52), STORM_HOT, "Neon", { 0, 0, 45 }),
		part("Weapon", "Block", V(0.13, 0.62, 1.55), V(0, 0.05, -1.4), rgb(110, 100, 140), "Metal", { 6, 0, 0 }),
		part("Weapon", "Block", V(0.13, 0.62, 1.55), V(0, -0.08, -2.85), rgb(110, 100, 140), "Metal", { -6, 0, 0 }),
		part("Weapon", "Block", V(0.13, 0.58, 1.45), V(0, 0.05, -4.25), rgb(110, 100, 140), "Metal", { 6, 0, 0 }),
		part("Weapon", "Wedge", V(0.13, 0.58, 0.8), V(0, 0.08, -5.35), rgb(110, 100, 140), "Metal"),
		part("Weapon", "Block", V(0.15, 0.07, 1.5), V(0, -0.28, -1.4), STORM, "Neon", { 18, 0, 0 }),
		part("Weapon", "Block", V(0.15, 0.07, 1.5), V(0, -0.36, -2.85), STORM_HOT, "Neon", { -18, 0, 0 }),
		part("Weapon", "Block", V(0.15, 0.07, 1.4), V(0, -0.26, -4.25), STORM, "Neon", { 18, 0, 0 }),
	},
}

-- Frost: a translucent ice-crystal blade with a glowing core.
Rigs.Weapons.FrostFang = {
	displayName = "Frost Fang",
	glow = FROST,
	fx = "Frost",
	trailBase = V(0, 0, -1.0),
	trailTip = V(0, 0, -5.25),
	parts = {
		part("Weapon", "Block", V(0.18, 0.18, 1.0), V(0, 0, 0.05), rgb(200, 225, 240), "Leather"),
		part("Weapon", "Block", V(0.32, 0.32, 0.32), V(0, 0, 0.68), FROST, "Neon", { 45, 0, 45 }),
		part("Weapon", "Wedge", V(0.22, 0.7, 0.5), V(0, 0.45, -0.5), ICE, "Glass", { -100, 0, 0 }, { transparency = 0.2 }),
		part("Weapon", "Wedge", V(0.22, 0.7, 0.5), V(0, -0.45, -0.5), ICE, "Glass", { 100, 0, 0 }, { transparency = 0.2 }),
		part("Weapon", "Block", V(0.15, 0.62, 4.0), V(0, 0, -2.65), ICE, "Glass", nil, { transparency = 0.25 }),
		part("Weapon", "Wedge", V(0.15, 0.62, 0.9), V(0, 0, -5.1), ICE, "Glass", nil, { transparency = 0.25 }),
		part("Weapon", "Block", V(0.08, 0.22, 3.8), V(0, 0, -2.6), FROST, "Neon"),
		part("Weapon", "Wedge", V(0.12, 0.5, 0.6), V(0, 0.42, -1.2), ICE, "Glass", { -30, 0, 0 }, { transparency = 0.2 }),
		part("Weapon", "Wedge", V(0.12, 0.45, 0.5), V(0, -0.4, -2.1), ICE, "Glass", { 30, 0, 0 }, { transparency = 0.2 }),
	},
}

-- Scale a weapon's blade (everything past the guard) along its length.
function Rigs.scaledWeapon(def, scale)
	if scale == 1 then
		return def
	end
	local out = table.clone(def)
	out.parts = {}
	local GUARD = -0.5
	local function sz(z)
		return if z < GUARD then GUARD + (z - GUARD) * scale else z
	end
	for _, p in def.parts do
		local pos = p.cf.Position
		local np = table.clone(p)
		if pos.Z < GUARD then
			np.cf = CFrame.new(pos.X, pos.Y, sz(pos.Z)) * p.cf.Rotation
			np.size = V(p.size.X, p.size.Y, p.size.Z * scale)
		end
		table.insert(out.parts, np)
	end
	out.trailTip = V(def.trailTip.X, def.trailTip.Y, sz(def.trailTip.Z))
	return out
end

------------------------------------------------------------------------------------------------
-- Enemy: Shard Brute (hulking obsidian golem with molten crystals)
------------------------------------------------------------------------------------------------
do
	local bones = {
		{ name = "Hips", parent = "Root", joint = "Root", size = V(2.6, 1.1, 2.0), pos = V(0, 2.65, 0.15), pivot = V(0, 2.65, 0.1), color = OBSIDIAN, material = "Basalt" },
		{ name = "Chest", parent = "Hips", joint = "Waist", size = V(4.1, 2.5, 2.7), pos = V(0, 4.55, 0.25), pivot = V(0, 3.25, 0.15), color = OBSIDIAN, material = "Basalt" },
		{ name = "Head", parent = "Chest", joint = "Neck", size = V(1.35, 1.15, 1.35), pos = V(0, 5.55, -1.35), pivot = V(0, 5.3, -0.9), color = OBSIDIAN, material = "Basalt" },
		{ name = "RUpperArm", parent = "Chest", joint = "RShoulder", size = V(1.4, 2.0, 1.45), pos = V(2.75, 4.55, 0.1), pivot = V(2.6, 5.4, 0.1), color = ROCK, material = "Slate" },
		{ name = "RFist", parent = "RUpperArm", joint = "RElbow", size = V(1.85, 2.2, 1.95), pos = V(2.85, 2.5, 0.0), pivot = V(2.75, 3.6, 0.1), color = OBSIDIAN, material = "Basalt" },
		{ name = "LUpperArm", parent = "Chest", joint = "LShoulder", size = V(1.4, 2.0, 1.45), pos = V(-2.75, 4.55, 0.1), pivot = V(-2.6, 5.4, 0.1), color = ROCK, material = "Slate" },
		{ name = "LFist", parent = "LUpperArm", joint = "LElbow", size = V(1.85, 2.2, 1.95), pos = V(-2.85, 2.5, 0.0), pivot = V(-2.75, 3.6, 0.1), color = OBSIDIAN, material = "Basalt" },
		{ name = "RLeg", parent = "Hips", joint = "RHip", size = V(1.45, 2.15, 1.55), pos = V(1.05, 1.3, 0.15), pivot = V(1.05, 2.35, 0.15), color = ROCK, material = "Slate" },
		{ name = "LLeg", parent = "Hips", joint = "LHip", size = V(1.45, 2.15, 1.55), pos = V(-1.05, 1.3, 0.15), pivot = V(-1.05, 2.35, 0.15), color = ROCK, material = "Slate" },
	}

	local right = {
		part("Chest", "Block", V(1.9, 0.6, 2.0), V(2.35, 5.78, 0.15), ROCK, "Slate", { 0, 0, -14 }),
		part("Chest", "Wedge", V(0.6, 1.9, 0.9), V(0.75, 6.15, 1.0), MOLTEN, "Neon", { -25, 0, -15 }),
		part("Head", "Block", V(0.28, 0.14, 0.06), V(0.33, 5.6, -2.04), MOLTEN, "Neon"),
		part("Head", "Wedge", V(0.28, 0.8, 0.3), V(0.55, 6.25, -1.25), MOLTEN, "Neon", { 0, 0, -25 }),
		part("RFist", "Block", V(2.0, 0.42, 2.1), V(2.85, 3.05, 0), ROCK, "Slate"),
		part("RFist", "Block", V(1.95, 0.62, 0.42), V(2.85, 1.78, -0.95), ROCK, "Slate"),
		part("RFist", "Wedge", V(0.5, 1.1, 0.6), V(3.25, 3.5, 0.45), MOLTEN, "Neon", { -20, 0, -20 }),
		part("RLeg", "Block", V(1.7, 0.5, 2.1), V(1.05, 0.25, -0.2), ROCK, "Slate"),
	}

	local decor = {
		part("Chest", "Wedge", V(0.5, 1.4, 0.7), V(-0.95, 5.95, 1.1), MOLTEN, "Neon", { -32, 0, 20 }),
		part("Chest", "Wedge", V(0.45, 1.15, 0.6), V(0.05, 6.35, 0.6), MOLTEN, "Neon", { -15, 0, 0 }),
		part("Chest", "Block", V(0.62, 0.62, 0.1), V(0, 4.62, -1.13), MOLTEN, "Neon", { 0, 0, 45 }, { light = { color = MOLTEN, range = 11, brightness = 1.6 } }),
		part("Chest", "Block", V(0.15, 1.4, 0.1), V(0.55, 4.45, -1.12), MOLTEN, "Neon", { 0, 0, 20 }),
		part("Chest", "Block", V(0.12, 0.9, 0.1), V(-0.62, 4.2, -1.12), MOLTEN, "Neon", { 0, 0, -30 }),
		part("Chest", "Block", V(3.0, 1.0, 0.3), V(0, 3.62, -0.95), ROCK, "Slate"),
		part("Head", "Block", V(1.45, 0.35, 0.5), V(0, 5.95, -1.6), ROCK, "Slate"),
		part("Head", "Block", V(1.1, 0.4, 0.4), V(0, 5.1, -1.72), ROCK, "Slate"),
	}
	append(decor, right)
	append(decor, mirrored(right))

	Rigs.Brute = {
		root = { name = "Root", size = V(3.6, 5.6, 3.6), pos = V(0, 2.8, 0) },
		bones = bones,
		decor = decor,
	}
end

------------------------------------------------------------------------------------------------
-- Derived joint data (C0/C1) shared by the builder, the animator and the preview tool.
------------------------------------------------------------------------------------------------

-- Returns { [jointName] = { part0, part1, c0, c1 } } and { [partName] = restCFrame }.
function Rigs.computeJoints(rig)
	local rest = {}
	rest[rig.root.name] = CFrame.new(rig.root.pos)
	for _, b in rig.bones do
		rest[b.name] = CFrame.new(b.pos)
	end
	local joints = {}
	for _, b in rig.bones do
		local pivot = CFrame.new(b.pivot)
		joints[b.joint] = {
			part0 = b.parent,
			part1 = b.name,
			c0 = rest[b.parent]:Inverse() * pivot,
			c1 = rest[b.name]:Inverse() * pivot,
		}
	end
	return joints, rest
end

-- Decor offset relative to its bone (decor is authored in rest space).
function Rigs.decorOffset(rest, d)
	return rest[d.bone]:Inverse() * d.cf
end

return Rigs
