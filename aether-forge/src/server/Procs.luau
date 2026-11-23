--!nonstrict
-- Procs: the server side of forged upgrade effects that live in the world.
--   Shockwave Finisher  a cutting wave that travels forward from your 3rd combo hit
--   Ember Trail         burning patches left behind by your dash
--   Lightning           Stormcaller (on parry) and Arc Edge (chance on hit)
-- Clients draw the visuals from Fx events; damage is applied here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)

local Procs = {}

local ctx
local waves = {}
local zones = {}

local function now()
	return workspace:GetServerTimeNow()
end

-- Lightning from `fromPos` to each enemy in `targets`.
function Procs.lightning(player, fromPos, targets, damage)
	local points = {}
	for _, e in targets do
		if e.state ~= "Dead" then
			table.insert(points, e.root.Position)
			ctx.Enemies.damage(e, damage, player, {
				knockDir = MathUtil.flatUnit(e.root.Position - fromPos),
				knockback = 8,
				stagger = 0.35,
				hitstop = 0,
				proc = true,
			})
		end
	end
	if #points > 0 then
		Net.Fx:FireAllClients("Lightning", { from = fromPos, to = points })
	end
end

-- Arc Edge: chance on hit to arc to nearby enemies.
function Procs.onHit(player, e, stats)
	if stats.chain > 0 and math.random() < 0.2 + 0.1 * (stats.chain - 1) then
		local near = ctx.Enemies.nearby(e.root.Position, 14, e, 2)
		if #near > 0 then
			Procs.lightning(player, e.root.Position + Vector3.new(0, 3, 0), near, 10 + 5 * stats.chain)
		end
	end
end

-- Stormcaller: lightning on nearby enemies when you parry.
function Procs.onParry(player, e)
	local stats = ctx.Characters.statsOf(player)
	if stats.stormParry > 0 then
		local count = if stats.stormParry >= 2 then 5 else 3
		local dmg = if stats.stormParry >= 2 then 30 else 20
		local near = ctx.Enemies.nearby(e.root.Position, 20, nil, count)
		Procs.lightning(player, e.root.Position + Vector3.new(0, 14, 0), near, dmg)
	end
end

function Procs.shockwave(player)
	local stats = ctx.Characters.statsOf(player)
	local lvl = stats.shockwave
	if lvl <= 0 then
		return
	end
	task.delay(0.16, function()
		local root = ctx.Characters.rootOf(player)
		if not root then
			return
		end
		local dir = MathUtil.flatUnit(root.CFrame.LookVector)
		local origin = Vector3.new(root.Position.X, 1.6, root.Position.Z) + dir * 1.5
		local w = {
			player = player,
			origin = origin,
			dir = dir,
			speed = 58,
			range = 22 + 10 * (lvl - 1),
			damage = 14 * (1 + 0.5 * (lvl - 1)) * stats.lightMult,
			t0 = now(),
			dist = 0,
			hit = {},
		}
		table.insert(waves, w)
		Net.Fx:FireAllClients("Shockwave", { origin = origin, dir = dir, speed = w.speed, range = w.range, player = player })
	end)
end

function Procs.emberTrail(player)
	local stats = ctx.Characters.statsOf(player)
	local lvl = stats.emberDash
	if lvl <= 0 then
		return
	end
	task.spawn(function()
		local points = {}
		for _ = 1, 7 do
			local root = ctx.Characters.rootOf(player)
			if root then
				local p = Vector3.new(root.Position.X, 0, root.Position.Z)
				table.insert(points, p)
				table.insert(zones, { pos = p, untilT = now() + 2.4, dmg = 5 * lvl, by = player, nextTick = 0 })
			end
			task.wait(0.045)
		end
		Net.Fx:FireAllClients("Ember", { points = points, duration = 2.4 })
	end)
end

local function updateWaves(dt)
	for i = #waves, 1, -1 do
		local w = waves[i]
		local prev = w.dist
		w.dist = math.min(w.range, w.dist + w.speed * dt)
		local a = w.origin + w.dir * prev
		local b = w.origin + w.dir * w.dist
		for _, e in ctx.Enemies.list do
			if e.state ~= "Dead" and not w.hit[e] then
				local p = Vector3.new(e.root.Position.X, w.origin.Y, e.root.Position.Z)
				local ab = b - a
				local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
				local closest = a + ab * t
				if (p - closest).Magnitude <= 3.6 + e.cfg.Radius then
					w.hit[e] = true
					ctx.Enemies.damage(e, w.damage, w.player, {
						knockDir = w.dir,
						knockback = 22,
						stagger = 0.4,
						hitstop = 0,
						proc = true,
					})
				end
			end
		end
		if w.dist >= w.range then
			table.remove(waves, i)
		end
	end
end

local function updateZones()
	local t = now()
	for i = #zones, 1, -1 do
		local z = zones[i]
		if t > z.untilT then
			table.remove(zones, i)
		elseif t >= z.nextTick then
			z.nextTick = t + 0.25
			for _, e in ctx.Enemies.list do
				if e.state ~= "Dead" then
					local d = Vector3.new(e.root.Position.X - z.pos.X, 0, e.root.Position.Z - z.pos.Z).Magnitude
					if d <= 2.8 + e.cfg.Radius * 0.5 then
						ctx.Enemies.damage(e, z.dmg, z.by, { stagger = 0, dot = true, proc = true })
					end
				end
			end
		end
	end
end

function Procs.reset()
	table.clear(waves)
	table.clear(zones)
end

function Procs.update(dt)
	updateWaves(dt)
	updateZones()
end

function Procs.init(context)
	ctx = context
	game:GetService("RunService").Heartbeat:Connect(Procs.update)
end

return Procs
