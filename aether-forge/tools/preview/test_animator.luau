--!nonstrict
-- Runs the real client RigAnimator against fake Motor6Ds and checks a full combo for NaNs and pops.
-- usage: luaurun test_animator.luau <repo>/aether-forge

local ROOT = ARGS[1]
VERBOSE = ARGS[2] == "-v"
local Shim = loadchunk(readfile(ROOT .. "/tools/preview/shim.luau"), "shim")()
Shim.install(_G)

-- fake services: ReplicatedStorage:WaitForChild("AetherForge") -> the shared folder
local sharedProxy = Shim.module -- placeholder to keep the shim loaded
local function folderProxy(path)
	return setmetatable({}, {
		__index = function(_, k)
			if k == "WaitForChild" then
				return function(_, name)
					if name == "AetherForge" then
						return Shim.proxy(ROOT .. "/src/shared")
					end
					return Shim.proxy(path .. "/" .. name)
				end
			end
			return Shim.proxy(path .. "/" .. k)
		end,
	})
end
_G.game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return folderProxy(ROOT .. "/src")
		end
		error("service " .. name .. " not faked")
	end,
}
_ = sharedProxy

local Rigs = Shim.module(ROOT .. "/src/shared/Rigs")
local Clips = Shim.module(ROOT .. "/src/shared/Clips")
local RigAnimator = Shim.module(ROOT .. "/src/client/RigAnimator")

-- fake model with one Motor6D per joint
local joints = Rigs.computeJoints(Rigs.Player)
local motors = {}
for name in joints do
	table.insert(motors, {
		Name = name,
		Transform = CFrame.identity,
		IsA = function(_, cls)
			return cls == "Motor6D"
		end,
	})
end
local model = {
	GetDescendants = function()
		return motors
	end,
}

local anim = RigAnimator.new(model, Rigs.Player, Clips.Player)
local dt = 1 / 60
local prev = {}
local worst, worstAt = 0, ""
local nan = false
local t = 0
local schedule = {
	{ 0.0, "Light1" },
	{ 0.17, "Light2" },
	{ 0.34, "Light3" },
	{ 1.0, "Heavy" },
	{ 1.95, "Dash" },
	{ 2.25, "Parry" },
	{ 2.4, "Riposte" },
	{ 2.75, "Hurt" },
}
local nextIdx = 1
local function angleBetween(a, b)
	local rel = a:Inverse() * b
	local _, _, _, r00, _, _, _, r11, _, _, _, r22 = rel:GetComponents()
	local c = math.clamp((r00 + r11 + r22 - 1) / 2, -1, 1)
	return math.deg(math.acos(c))
end
local current = "idle"
local AnimCore = Shim.module(ROOT .. "/src/shared/AnimCore")
local rootCF = CFrame.new(Rigs.Player.root.pos)
local prevHand = nil
local flips = 0
for frame = 1, 240 do
	t = frame * dt
	while schedule[nextIdx] and t >= schedule[nextIdx][1] do
		current = schedule[nextIdx][2]
		anim:play(current, { fadeIn = if current == "Riposte" or current == "Hurt" then 0 else 0.035 })
		nextIdx += 1
	end
	local speed = if t > 3.2 then 20 else 0
	anim:update(dt, { speed = speed, moveLocal = Vector3.new(0, 0, -1) })
	local tf = {}
	for _, m in motors do
		tf[m.Name] = m.Transform
	end
	local world = AnimCore.boneWorld(Rigs.Player, joints, tf, rootCF)
	local hand = world.Weapon.Position
	local handMove = if prevHand then (hand - prevHand).Magnitude else 0
	prevHand = hand
	for _, m in motors do
		local c = m.Transform
		local comps = { c:GetComponents() }
		for _, v in comps do
			if v ~= v then
				nan = true
			end
		end
		if prev[m.Name] then
			local d = angleBetween(prev[m.Name], c)
			-- the spin finisher legitimately turns the root fast; Grip/elbow snaps on hard cuts are expected
			if not (current == "Light3" and m.Name == "Root") and d > worst then
				worst = d
				worstAt = string.format("%s frame %d (t=%.2f, %s)", m.Name, frame, t, current)
			end
			if (m.Name == "RShoulder" or m.Name == "LShoulder") and d > 60 and handMove < 0.6 then
				flips += 1
				print(string.format("  FLIP? %s %.0f deg while hand moved %.2f (frame %d t=%.2f %s)", m.Name, d, handMove, frame, t, current))
			end
			if d > 25 and not (current == "Light3" and m.Name == "Root") and VERBOSE then
				print(string.format("  jump %5.1f deg  %-9s frame %3d t=%.2f %s", d, m.Name, frame, t, current))
			end
		end
		prev[m.Name] = c
	end
end
print("suspected IK flips: " .. flips)
print(string.format("NaN: %s   largest per-frame joint rotation: %.1f deg at %s", tostring(nan), worst, worstAt))
