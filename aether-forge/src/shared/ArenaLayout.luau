--!nonstrict
-- ArenaLayout: the floating arena as pure data. The server builds Parts from this list; the preview
-- tool renders the same list. Floor top is y = 0, the anvil sits at the origin, the camera looks
-- toward -Z.
--
-- Part spec: { name, shape, size, cf, color, material, transparency?, collide?, group?, light?,
--              castShadow?, kind? }

local ArenaLayout = {}

local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local RADIUS = 60
ArenaLayout.Radius = RADIUS

local FLOOR = rgb(46, 46, 58)
local FLOOR_INNER = rgb(58, 56, 70)
local ROCK = rgb(40, 36, 46)
local ROCK2 = rgb(58, 52, 62)
local BRONZE = rgb(200, 134, 66)
local STEEL = rgb(70, 74, 90)
local AETHER = rgb(70, 225, 255)
local AETHER_DEEP = rgb(40, 110, 255)
local MOLTEN = rgb(255, 86, 36)

-- Vertical cylinder whose top face sits at `top`.
local function disc(list, name, radius, top, height, color, material, extra)
	local p = {
		name = name,
		shape = "Cylinder",
		size = V(height, radius * 2, radius * 2),
		cf = CFrame.new(0, top - height / 2, 0) * CFrame.Angles(0, 0, rad(90)),
		color = color,
		material = material,
		collide = true,
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	table.insert(list, p)
	return p
end

local function discAt(list, name, pos, radius, top, height, color, material, extra)
	local p = disc(list, name, radius, top, height, color, material, extra)
	p.cf = CFrame.new(pos.X, top - height / 2, pos.Z) * CFrame.Angles(0, 0, rad(90))
	return p
end

local function block(list, name, size, cf, color, material, extra)
	local p = { name = name, shape = "Block", size = size, cf = cf, color = color, material = material, collide = true }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	table.insert(list, p)
	return p
end

local function wedge(list, name, size, cf, color, material, extra)
	local p = block(list, name, size, cf, color, material, extra)
	p.shape = "Wedge"
	return p
end

-- Small deterministic PRNG so the arena decoration is identical every run.
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		local u = s / 2147483648
		return a + (b - a) * u
	end
end

local function polar(r, deg, y)
	local a = rad(deg)
	return V(math.sin(a) * r, y or 0, -math.cos(a) * r)
end
ArenaLayout.polar = polar

-- Gameplay points ---------------------------------------------------------------------------
ArenaLayout.PlayerSpawn = V(0, 4, 20)
ArenaLayout.AnvilPos = V(0, 0, 0)
ArenaLayout.AnvilRadius = 4.6 -- enemies steer around this circle
ArenaLayout.KillY = -60

ArenaLayout.Portals = {}
for i, deg in { 45, 135, 225, 315 } do
	ArenaLayout.Portals[i] = polar(46, deg)
end

ArenaLayout.CrystalSpots = {}
for _, deg in { 0, 90, 180, 270 } do
	table.insert(ArenaLayout.CrystalSpots, polar(24, deg))
end
for _, deg in { 22.5, 112.5, 202.5, 292.5 } do
	table.insert(ArenaLayout.CrystalSpots, polar(38, deg))
end

-- Geometry -----------------------------------------------------------------------------------
function ArenaLayout.build()
	local list = {}
	local r = rng(7)

	-- floor slab and the engraved rings (layered discs with tiny height offsets)
	disc(list, "Floor", RADIUS, 0, 4, FLOOR, "Slate")
	disc(list, "RingOuterGlow", RADIUS - 2.2, 0.02, 0.2, AETHER_DEEP, "Neon", { castShadow = false })
	disc(list, "RingOuterFill", RADIUS - 2.8, 0.04, 0.2, FLOOR, "Slate")
	disc(list, "RingMidGlow", 34.6, 0.06, 0.2, AETHER_DEEP, "Neon", { castShadow = false })
	disc(list, "RingMidFill", 34.0, 0.08, 0.2, FLOOR, "Slate")
	disc(list, "InnerPlate", 14.5, 0.1, 0.2, FLOOR_INNER, "Slate")
	disc(list, "RingInnerGlow", 13.6, 0.12, 0.2, AETHER, "Neon", { castShadow = false })
	disc(list, "RingInnerFill", 13.0, 0.14, 0.2, FLOOR_INNER, "Slate")

	-- rune spokes between the inner and mid rings
	for i = 0, 7 do
		local deg = i * 45 + 22.5
		local mid = polar(24.3, deg, 0.1)
		block(list, "Spoke", V(0.3, 0.2, 19), CFrame.new(mid) * CFrame.Angles(0, -rad(deg), 0), AETHER_DEEP, "Neon", { castShadow = false, collide = false, transparency = 0.25 })
	end

	-- floor tiles: a ring of slightly raised stone slabs near the edge for texture
	for i = 0, 35 do
		local deg = i * 10 + 5
		local pos = polar(RADIUS - 6.5, deg, 0.06)
		block(list, "Tile", V(7.2, 0.2, 5.2), CFrame.new(pos) * CFrame.Angles(0, -rad(deg), 0), if i % 2 == 0 then FLOOR_INNER else FLOOR, "Slate")
	end

	-- broken rim stones around the edge (decor only, enemies can still be knocked off)
	for i = 0, 47 do
		local deg = i * 7.5 + r(-1.5, 1.5)
		local h = r(0.5, 1.6)
		local pos = polar(RADIUS - 0.6, deg, h / 2 - 0.2)
		if i % 6 ~= 0 then
			block(list, "Rim", V(r(3, 4.5), h, 1.6), CFrame.new(pos) * CFrame.Angles(0, -rad(deg), rad(r(-6, 6))), ROCK2, "Basalt", { collide = false })
		end
	end

	-- island underside: stacked tapering rock
	local layers = { { 57, -4, 6 }, { 48, -10, 7 }, { 36, -17, 8 }, { 23, -25, 9 }, { 12, -34, 10 }, { 5, -44, 10 } }
	for i, l in layers do
		disc(list, "Underside" .. i, l[1], l[2], l[3], if i % 2 == 0 then ROCK else ROCK2, "Basalt", { collide = false })
	end
	-- jagged hanging rocks and glowing veins
	for i = 0, 15 do
		local deg = i * 22.5 + r(-8, 8)
		local rr = r(18, 50)
		local depth = -6 - (60 - rr) * 0.55
		local pos = polar(rr, deg, depth)
		local s = r(5, 10)
		wedge(list, "Jag", V(s, s * 1.6, s), CFrame.new(pos) * CFrame.Angles(rad(180), rad(r(0, 360)), rad(r(-15, 15))), ROCK, "Basalt", { collide = false })
		if i % 3 == 0 then
			block(list, "Vein", V(0.6, s * 1.2, 0.6), CFrame.new(pos + V(0, -s * 0.4, 0)) * CFrame.Angles(rad(r(-20, 20)), 0, rad(r(-20, 20))), AETHER, "Neon", { collide = false, castShadow = false })
		end
	end

	-- the forge anvil at the center
	discAt(list, "AnvilPedestal", V(0, 0, 0), 3.4, 1.2, 1.2, STEEL, "DiamondPlate")
	discAt(list, "AnvilRune", V(0, 0, 0), 4.1, 0.16, 0.2, MOLTEN, "Neon", { castShadow = false, collide = false })
	discAt(list, "AnvilRuneFill", V(0, 0, 0), 3.7, 0.18, 0.2, FLOOR_INNER, "Slate", { collide = false })
	block(list, "AnvilBase", V(2.6, 0.7, 2.0), CFrame.new(0, 1.55, 0), STEEL, "Metal")
	block(list, "AnvilWaist", V(1.6, 1.0, 1.3), CFrame.new(0, 2.4, 0), STEEL, "Metal")
	block(list, "AnvilFace", V(4.2, 0.7, 1.9), CFrame.new(0.3, 3.25, 0), rgb(96, 100, 118), "Metal")
	wedge(list, "AnvilHorn", V(1.9, 0.7, 1.6), CFrame.new(-2.75, 3.25, 0) * CFrame.Angles(0, rad(90), 0), rgb(96, 100, 118), "Metal")
	block(list, "AnvilHeel", V(0.8, 0.5, 1.5), CFrame.new(2.6, 3.0, 0), rgb(96, 100, 118), "Metal")
	block(list, "AnvilGlow", V(3.6, 0.08, 0.5), CFrame.new(0.3, 3.62, 0), MOLTEN, "Neon", { castShadow = false, collide = false, light = { color = MOLTEN, range = 16, brightness = 2 } })
	block(list, "AnvilBand", V(1.7, 0.2, 1.4), CFrame.new(0, 2.0, 0), BRONZE, "Metal")
	block(list, "ForgeCore", V(1.4, 1.4, 1.4), CFrame.new(0, 7.2, 0) * CFrame.Angles(rad(45), rad(45), 0), AETHER, "Neon", { castShadow = false, collide = false, kind = "ForgeCore", light = { color = AETHER, range = 22, brightness = 2.2 } })

	-- spawn portals
	for i, p in ArenaLayout.Portals do
		discAt(list, "PortalGlow" .. i, p, 4.4, 0.16, 0.2, MOLTEN, "Neon", { castShadow = false, collide = false })
		discAt(list, "PortalFill" .. i, p, 3.8, 0.18, 0.2, rgb(26, 20, 28), "Basalt", { collide = false })
		discAt(list, "PortalCore" .. i, p, 1.4, 0.2, 0.2, MOLTEN, "Neon", { castShadow = false, collide = false, transparency = 0.4, kind = "Portal", light = { color = MOLTEN, range = 10, brightness = 1 } })
		for k = 0, 2 do
			local deg = k * 120 + i * 30
			local sp = p + polar(5.4, deg, 1.4)
			block(list, "PortalStone", V(1.0, 2.8, 1.0), CFrame.new(sp) * CFrame.Angles(rad(8), rad(-deg), 0), ROCK2, "Basalt", { collide = false })
			block(list, "PortalStoneGlow", V(1.04, 0.2, 1.04), CFrame.new(sp + V(0, 0.9, 0)) * CFrame.Angles(rad(8), rad(-deg), 0), MOLTEN, "Neon", { castShadow = false, collide = false })
		end
	end

	-- floating obelisks framing the arena (outside the floor)
	for i = 0, 5 do
		local deg = i * 60 + 30
		local base = polar(70, deg, -2)
		disc(list, "ObeliskRock", 5, -1, 5, ROCK2, "Basalt", { collide = false }).cf = CFrame.new(base + V(0, -2.5, 0)) * CFrame.Angles(0, 0, rad(90))
		block(list, "Obelisk", V(3, 18, 3), CFrame.new(base + V(0, 8, 0)) * CFrame.Angles(0, rad(deg + 45), 0), ROCK, "Basalt", { collide = false })
		block(list, "ObeliskRune", V(3.1, 0.4, 3.1), CFrame.new(base + V(0, 13, 0)) * CFrame.Angles(0, rad(deg + 45), 0), AETHER, "Neon", { castShadow = false, collide = false })
		block(list, "ObeliskCrystal", V(2, 3.4, 2), CFrame.new(base + V(0, 20.5, 0)) * CFrame.Angles(rad(45), rad(deg), rad(45)), AETHER, "Neon", { castShadow = false, collide = false, kind = "Spin", light = { color = AETHER, range = 24, brightness = 1.6 } })
	end

	-- distant floating rocks to sell the "sky island" feel
	for i = 0, 17 do
		local deg = i * 20 + r(-8, 8)
		local pos = polar(r(105, 170), deg, r(-45, 25))
		local s = r(7, 22)
		block(list, "FarRock", V(s, s * 0.7, s * 0.9), CFrame.new(pos) * CFrame.Angles(rad(r(-20, 20)), rad(r(0, 90)), rad(r(-20, 20))), ROCK2, "Basalt", { collide = false })
		wedge(list, "FarRockBottom", V(s * 0.8, s * 1.2, s * 0.7), CFrame.new(pos + V(0, -s * 0.9, 0)) * CFrame.Angles(rad(180), rad(r(0, 90)), 0), ROCK, "Basalt", { collide = false })
		if i % 2 == 0 then
			block(list, "FarCrystal", V(1.6, s * 0.4, 1.6), CFrame.new(pos + V(0, s * 0.5, 0)) * CFrame.Angles(rad(r(-25, 25)), 0, rad(r(-25, 25))), if i % 4 == 0 then AETHER else MOLTEN, "Neon", { collide = false, castShadow = false })
		end
	end

	return list
end

-- Invisible ring wall that keeps players on the island (enemies are not blocked, so heavy slams
-- can knock them off the edge).
function ArenaLayout.barrier()
	local list = {}
	local n = 40
	for i = 0, n - 1 do
		local deg = i * 360 / n
		local pos = polar(RADIUS + 0.5, deg, 6)
		local width = 2 * math.pi * (RADIUS + 0.5) / n + 0.6
		block(list, "Barrier", V(width, 14, 1), CFrame.new(pos) * CFrame.Angles(0, -rad(deg), 0), rgb(0, 0, 0), "SmoothPlastic", { transparency = 1, group = "PlayerBarrier", castShadow = false })
	end
	return list
end

return ArenaLayout
