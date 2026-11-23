--!nonstrict
-- Bakes rig poses into JSON for the three.js preview.
-- usage: luaurun bake.luau <repo>/aether-forge <out.json> [sheet names...]

local ROOT = ARGS[1]
local OUT = ARGS[2]
local Shim = loadchunk(readfile(ROOT .. "/tools/preview/shim.luau"), "shim")()
Shim.install(_G)

local SHARED = ROOT .. "/src/shared"
local Rigs = Shim.module(SHARED .. "/Rigs")
local AnimCore = Shim.module(SHARED .. "/AnimCore")
local Clips = Shim.module(SHARED .. "/Clips")
local Arena = Shim.module(SHARED .. "/ArenaLayout")
local Moves = Shim.module(SHARED .. "/Moves")

local want = {}
for i = 3, #ARGS do
	want[ARGS[i]] = true
end
local function wanted(name)
	return next(want) == nil or want[name]
end

local function num(x)
	return string.format("%.4f", x)
end

local parts -- current frame's part list (array of json strings)

local function emit(shape, size, cf, color, material, transparency)
	local c = { cf:GetComponents() }
	local m = {}
	for i = 1, 12 do
		m[i] = num(c[i])
	end
	table.insert(
		parts,
		string.format(
			'{"s":"%s","z":[%s,%s,%s],"m":[%s],"c":[%s,%s,%s],"t":"%s","a":%s}',
			shape,
			num(size.X),
			num(size.Y),
			num(size.Z),
			table.concat(m, ","),
			num(color.R),
			num(color.G),
			num(color.B),
			material or "SmoothPlastic",
			num(transparency or 0)
		)
	)
end

local function rigFrame(rig, joints, rest, legInfo, pose, rootCF, weapon)
	local transforms = AnimCore.solve(pose, joints, legInfo)
	local world = AnimCore.boneWorld(rig, joints, transforms, rootCF)
	for _, b in rig.bones do
		if not b.invisible then
			emit(b.shape or "Block", b.size, world[b.name], b.color, b.material)
		end
	end
	for _, d in rig.decor do
		emit(d.shape, d.size, world[d.bone] * Rigs.decorOffset(rest, d), d.color, d.material)
	end
	if weapon then
		for _, p in weapon.parts do
			emit(p.shape, p.size, world[rig.weaponBone] * p.cf, p.color, p.material)
		end
	end
end

local sheets = {}
local function sheet(title, frames)
	table.insert(sheets, string.format('{"title":"%s","frames":[%s]}', title, table.concat(frames, ",")))
end

local function frameJson(label, fn)
	parts = {}
	fn()
	return string.format('{"label":"%s","parts":[%s]}', label, table.concat(parts, ","))
end

-- Player
local pj, prest = Rigs.computeJoints(Rigs.Player)
local pleg = AnimCore.ikInfo(Rigs.Player, pj)
local pRoot = CFrame.new(Rigs.Player.root.pos)
local blade = Rigs.Weapons.EmberBlade

-- Blade tip path over the trail window plus the hitbox outline on the ground.
local function overlays(clipName, clip)
	local move = Moves[clipName]
	if not move then
		return
	end
	local tipLocal = blade.trailTip
	local from, to = 0, clip.length
	if move.trail then
		from, to = move.trail[1], move.trail[2]
	end
	local t = from
	while t <= to + 1e-6 do
		local transforms = AnimCore.solve(AnimCore.sample(clip, t), pj, pleg)
		local world = AnimCore.boneWorld(Rigs.Player, pj, transforms, pRoot)
		local tip = world.Weapon * tipLocal
		local base = world.Weapon * blade.trailBase
		local active = move.active and t >= move.active[1] and t <= move.active[2]
		local len = (tip - base).Magnitude
		emit("Block", Vector3.new(0.06, 0.06, len), CFrame.lookAt((tip + base) / 2, tip), if active then Color3.fromRGB(255, 220, 80) else Color3.fromRGB(80, 200, 255), "Neon")
		t += 0.01
	end
	local hit = move.hit
	if hit then
		local function ring(center, radius, a0, a1)
			for i = 0, 40 do
				local a = math.rad(a0 + (a1 - a0) * i / 40)
				local p = center + Vector3.new(-math.sin(a) * radius, 0.05, -math.cos(a) * radius)
				emit("Block", Vector3.new(0.25, 0.05, 0.25), CFrame.new(p), Color3.fromRGB(255, 60, 60), "Neon")
			end
		end
		if hit.shape == "arc" then
			ring(Vector3.new(0, 0, 0), hit.range, -hit.arc / 2, hit.arc / 2)
		else
			ring(Vector3.new(0, 0, -(hit.offset or 0)), hit.radius, 0, 360)
		end
	end
end

local function playerSheet(clipName, times)
	if not wanted(clipName) then
		return
	end
	local clip = Clips.Player.clips[clipName]
	local frames = {}
	for _, t in times do
		table.insert(
			frames,
			frameJson(string.format("%s t=%.2f", clipName, t), function()
				rigFrame(Rigs.Player, pj, prest, pleg, AnimCore.sample(clip, t), pRoot, blade)
				overlays(clipName, clip)
			end)
		)
	end
	sheet("Player " .. clipName, frames)
end

if wanted("Ready") then
	sheet("Player Ready / Run", {
		frameJson("Ready", function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.Ready, pRoot, blade)
		end),
		frameJson("Rest (T=identity)", function()
			rigFrame(Rigs.Player, pj, prest, pleg, AnimCore.newPose(), pRoot, blade)
		end),
		frameJson("Run 0", function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.locomotion({ t = 0, speed = 21, moveLocal = Vector3.new(0, 0, -1), phase = 0 }), pRoot, blade)
		end),
		frameJson("Run 90", function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.locomotion({ t = 0, speed = 21, moveLocal = Vector3.new(0, 0, -1), phase = math.pi / 2 }), pRoot, blade)
		end),
		frameJson("Run 180", function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.locomotion({ t = 0, speed = 21, moveLocal = Vector3.new(0, 0, -1), phase = math.pi }), pRoot, blade)
		end),
		frameJson("Run 270", function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.locomotion({ t = 0, speed = 21, moveLocal = Vector3.new(0, 0, -1), phase = math.pi * 1.5 }), pRoot, blade)
		end),
	})
end

if wanted("Weapons") then
	local frames = {}
	for _, id in { "EmberBlade", "AetherReaver", "FlameGreatsword", "StormCleaver", "FrostFang" } do
		table.insert(frames, frameJson(id, function()
			rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.Ready, pRoot, Rigs.Weapons[id])
		end))
	end
	table.insert(frames, frameJson("FlameGreatsword reach III", function()
		rigFrame(Rigs.Player, pj, prest, pleg, Clips.Player.Ready, pRoot, Rigs.scaledWeapon(Rigs.Weapons.FlameGreatsword, 1.36))
	end))
	sheet("Weapons", frames)
end

playerSheet("Light1", { 0, 0.06, 0.09, 0.12, 0.16, 0.2, 0.27, 0.34 })
playerSheet("Light2", { 0, 0.06, 0.09, 0.12, 0.16, 0.2, 0.27, 0.34 })
playerSheet("Light3", { 0, 0.12, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.29, 0.4, 0.56 })
playerSheet("Heavy", { 0, 0.08, 0.16, 0.3, 0.36, 0.4, 0.6, 0.75, 0.92 })
playerSheet("Dash", { 0, 0.06, 0.12, 0.2, 0.27 })
playerSheet("Parry", { 0, 0.17, 0.3, 0.46 })
playerSheet("Riposte", { 0, 0.07, 0.15, 0.32 })
playerSheet("Hurt", { 0, 0.1, 0.32 })

-- Brute
local bj, brest = Rigs.computeJoints(Rigs.Brute)
local bRoot = CFrame.new(Rigs.Brute.root.pos)
local function bruteSheet(name, sampler, times)
	if not wanted("Brute" .. name) then
		return
	end
	local frames = {}
	for _, t in times do
		table.insert(
			frames,
			frameJson(string.format("Brute %s %.2f", name, t), function()
				rigFrame(Rigs.Brute, bj, brest, nil, sampler(t), bRoot, nil)
			end)
		)
	end
	sheet("Brute " .. name, frames)
end
bruteSheet("Idle", function()
	return Clips.Brute.Idle
end, { 0 })
bruteSheet("Walk", function(t)
	return Clips.Brute.locomotion({ t = 0, speed = 12, phase = t })
end, { 0, math.pi / 2, math.pi, math.pi * 1.5 })
bruteSheet("Windup", function(t)
	return AnimCore.sample(Clips.Brute.clips.Windup, t)
end, { 0, 0.25, 0.45, 1 })
bruteSheet("Strike", function(t)
	return AnimCore.sample(Clips.Brute.clips.Strike, t)
end, { 0, 0.04, 0.07, 0.25 })
bruteSheet("Recover", function(t)
	return AnimCore.sample(Clips.Brute.clips.Recover, t)
end, { 0, 0.45, 0.75 })
bruteSheet("Stun", function(t)
	return Clips.Brute.stunned(t)
end, { 0, 0.4, 0.8 })
bruteSheet("Spawn", function(t)
	return AnimCore.sample(Clips.Brute.clips.Spawn, t)
end, { 0, 0.35, 0.7, 1 })

-- Arena (single frame, rendered with a wide camera)
if wanted("Arena") then
	local frames = {
		frameJson("Arena", function()
			for _, p in Arena.build() do
				emit(p.shape, p.size, p.cf, p.color, p.material, p.transparency)
			end
		end),
	}
	sheet("Arena", frames)
end

writefile(OUT, "[" .. table.concat(sheets, ",") .. "]")
print("baked " .. #sheets .. " sheets -> " .. OUT)
