--!nonstrict
-- EnemyService: spawns Brutes and runs their AI on the server.
--
-- An enemy is a physics body (invisible collider "Root", pushed by a LinearVelocity, kept upright and
-- facing by an AlignOrientation) with a visual rig welded on. Clients animate the rig from replicated
-- attributes, so state changes are timestamped with server time:
--   State      Spawn | Chase | Windup | Strike | Recover | Stunned | Flinch | Dead
--   StateT     server time the state began
--   StrikeT    server time the current windup's strike lands (Windup only)
--   StrikeId   increments every windup; clients report how each strike resolved for them
--   HP / MaxHP, Kind
--
-- Strike resolution: the client of the targeted player decides parry / dodge / hurt at StrikeT (that
-- is what feels fair at any ping), reports it, and the server checks the claim against the actions it
-- saw (parry and dash timestamps). If no report arrives in time, the server checks range itself.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Moves = require(Shared.Moves)
local Rigs = require(Shared.Rigs)
local RigBuilder = require(Shared.RigBuilder)
local ArenaLayout = require(Shared.ArenaLayout)
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)

local EnemyService = {}
EnemyService.list = {} -- [model] = enemy
EnemyService.passive = false -- debug: enemies never attack

local ctx
local pendingStrikes = {}
local folder

local function now()
	return workspace:GetServerTimeNow()
end

local function setState(e, state, extra)
	e.state = state
	e.stateT = now()
	e.model:SetAttribute("State", state)
	e.model:SetAttribute("StateT", e.stateT)
	if extra then
		for k, v in extra do
			e.model:SetAttribute(k, v)
		end
	end
end

local function flatDir(from, to)
	return MathUtil.flatUnit(to - from)
end

function EnemyService.count()
	local n = 0
	for _, e in EnemyService.list do
		if e.state ~= "Dead" then
			n += 1
		end
	end
	return n
end

function EnemyService.spawn(kind, position, wave)
	kind = kind or "Brute"
	local cfg = Config.Enemy[kind]
	local scale = 1 + (math.max(1, wave or 1) - 1) * Config.Waves.HPScale
	local model, built = RigBuilder.build(Rigs[kind], { name = kind, collisionGroup = "Enemy" })
	local root = built.parts.Root
	root.CustomPhysicalProperties = PhysicalProperties.new(4, 0, 0, 1, 1)
	root.CanQuery = true

	local att = Instance.new("Attachment")
	att.Name = "RootAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "Drive"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.zero
	lv.MaxForce = 1e6
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "Face"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.MaxAngularVelocity = math.huge
	ao.Responsiveness = 60
	ao.Parent = root

	local toCenter = flatDir(position, Vector3.zero)
	local yaw = MathUtil.yawFromDir(toCenter)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, yaw, 0))
	ao.CFrame = CFrame.Angles(0, yaw, 0)

	local hp = math.floor(cfg.MaxHP * scale + 0.5)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("HP", hp)
	model:SetAttribute("StrikeId", 0)
	model:SetAttribute("Radius", cfg.Radius)
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local windup = math.max(Config.Waves.MinWindup, cfg.Windup * (1 - ((wave or 1) - 1) * Config.Waves.WindupScale))
	local e = {
		model = model,
		root = root,
		lv = lv,
		ao = ao,
		cfg = cfg,
		kind = kind,
		hp = hp,
		yaw = yaw,
		windup = windup,
		strikeId = 0,
		cooldownUntil = 0,
		knock = Vector3.zero,
		slowUntil = 0,
		flinchUntil = 0,
		stunUntil = 0,
		target = nil,
		earlyReports = {},
	}
	EnemyService.list[model] = e
	setState(e, "Spawn")
	return e
end

local function die(e, killer, reason)
	if e.state == "Dead" then
		return
	end
	setState(e, "Dead")
	e.model:SetAttribute("HP", 0)
	e.lv.PlaneVelocity = Vector2.zero
	Net.Fx:FireAllClients("EnemyDied", { pos = e.root.Position, reason = reason, kind = e.kind })
	if killer and ctx.Characters.state[killer] then
		ctx.Characters.addOre(killer, 1)
	end
	task.delay(0.8, function()
		EnemyService.list[e.model] = nil
		e.model:Destroy()
	end)
	if ctx.Waves then
		ctx.Waves.onEnemyDied(e)
	end
end

function EnemyService.killAll()
	for _, e in EnemyService.list do
		die(e, nil, "Debug")
	end
end

-- Player damage. `opts` = { knockDir, knockback, launch, stagger, breaksWindup, hitstop }
function EnemyService.damage(e, amount, player, opts)
	if e.state == "Dead" or e.state == "Spawn" then
		return false
	end
	if e.state == "Stunned" then
		amount *= 1.25
	end
	amount = math.floor(amount + 0.5)
	e.hp -= amount
	e.model:SetAttribute("HP", math.max(0, e.hp))
	if e.hp <= 0 then
		die(e, player, "Killed")
		-- dead bodies still get launched a bit so the shatter flies the right way
		e.knock = (opts.knockDir or Vector3.zero) * (opts.knockback or 0) * 0.5
		return true
	end

	-- Knockback lands after the attacker's hitstop so the freeze frame reads first.
	local delay = opts.hitstop or 0
	task.delay(delay, function()
		if e.state == "Dead" then
			return
		end
		local massScale = 30 / (e.cfg.Mass or 30)
		e.knock += (opts.knockDir or Vector3.zero) * (opts.knockback or 0) * massScale
		if opts.launch and opts.launch > 0 then
			local v = e.root.AssemblyLinearVelocity
			e.root.AssemblyLinearVelocity = Vector3.new(v.X, opts.launch * massScale, v.Z)
		end
	end)

	local stagger = opts.stagger or 0
	if e.state == "Windup" and not opts.breaksWindup then
		-- super armor: light hits do not interrupt a windup (parry or slam it instead)
		return true
	end
	if e.state == "Stunned" then
		return true
	end
	if stagger > 0 then
		e.flinchUntil = now() + stagger + delay
		if e.state ~= "Flinch" then
			setState(e, "Flinch")
		else
			e.model:SetAttribute("StateT", now())
		end
	end
	return true
end

local function slowNearby(pos, untilT)
	for _, other in EnemyService.list do
		if other.state ~= "Dead" and (other.root.Position - pos).Magnitude < Config.Enemy.ParrySlowRadius then
			other.slowUntil = math.max(other.slowUntil, untilT)
		end
	end
end

local function applyParry(e, player)
	if e.state == "Dead" then
		return
	end
	local t = now()
	e.stunUntil = t + e.cfg.ParryStun
	setState(e, "Stunned")
	local root = ctx.Characters.rootOf(player)
	if root then
		e.knock += flatDir(root.Position, e.root.Position) * 18
	end
	local st = ctx.Characters.state[player]
	if st then
		st.riposteUntil = t + Config.Player.RiposteDuration
	end
	slowNearby(e.root.Position, t + Config.Feel.ParrySlowmoDuration)
	Net.Fx:FireAllClients("Parried", { player = player, enemy = e.model })
end

local function inStrikeArc(origin, facing, pos, range, arc, slack)
	local d = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
	local dist = d.Magnitude
	if dist > range + slack then
		return false, dist
	end
	if dist < 1.5 then
		return true, dist
	end
	local ang = math.deg(math.acos(math.clamp(facing:Dot(d / dist), -1, 1)))
	return ang <= arc / 2 + slack * 4, dist
end

local function resolve(pending, player, outcome)
	if pending.resolved[player] then
		return
	end
	pending.resolved[player] = true
	local e = pending.enemy
	local st = ctx.Characters.state[player]
	if not st or not ctx.Characters.isAlive(player) or e.state == "Dead" then
		return
	end
	local strikeT = pending.t
	local root = ctx.Characters.rootOf(player)
	local range, arc = e.cfg.AttackRange + Config.Player.BodyRadius, e.cfg.AttackArc

	if outcome == "parry" then
		local d = strikeT - st.lastParryT
		if d >= -0.08 and d <= Moves.Parry.active[2] + 0.15 then
			applyParry(e, player)
			return
		end
		outcome = "hurt"
	elseif outcome == "dodge" then
		local d = strikeT - st.lastDashT
		if (d >= -0.08 and d <= Moves.Dash.iframes[2] + 0.15) or strikeT < st.hurtUntil + 0.1 then
			return
		end
		outcome = "hurt"
	elseif outcome == "miss" or outcome == "timeout" then
		if not root then
			return
		end
		-- Accept a miss unless the player is clearly deep inside the strike zone.
		local slack = if outcome == "timeout" then 0.5 else -range * 0.4
		local hitNow = inStrikeArc(pending.origin, pending.facing, root.Position, range, arc, slack)
		if not hitNow then
			return
		end
		local d = strikeT - st.lastDashT
		if d >= -0.08 and d <= Moves.Dash.iframes[2] + 0.15 then
			return
		end
		outcome = "hurt"
	end

	if outcome == "hurt" then
		ctx.Characters.damage(player, pending.damage, pending.origin)
	end
end

local function beginStrike(e)
	local origin = e.root.Position
	local facing = MathUtil.dirFromYaw(e.yaw)
	local pending = {
		enemy = e,
		id = e.strikeId,
		t = e.strikeT,
		origin = origin,
		facing = facing,
		damage = e.cfg.Damage,
		candidates = {},
		resolved = {},
	}
	local range = e.cfg.AttackRange + Config.Player.BodyRadius
	for _, p in ctx.Characters.alivePlayers() do
		local root = ctx.Characters.rootOf(p)
		if root and inStrikeArc(origin, facing, root.Position, range, e.cfg.AttackArc, 4) then
			pending.candidates[p] = true
		end
	end
	table.insert(pendingStrikes, pending)
	-- reports that arrived before the server reached StrikeT
	local early = e.earlyReports[e.strikeId]
	if early then
		for p, outcome in early do
			resolve(pending, p, outcome)
		end
		e.earlyReports[e.strikeId] = nil
	end
	setState(e, "Strike")
	-- small forward lurch with the slam
	e.knock += facing * 10
end

function EnemyService.report(player, model, strikeId, outcome)
	local e = EnemyService.list[model]
	if not e or typeof(strikeId) ~= "number" then
		return
	end
	if outcome ~= "parry" and outcome ~= "dodge" and outcome ~= "hurt" and outcome ~= "miss" then
		return
	end
	for _, pending in pendingStrikes do
		if pending.enemy == e and pending.id == strikeId then
			resolve(pending, player, outcome)
			return
		end
	end
	if strikeId == e.strikeId and e.state == "Windup" then
		e.earlyReports[strikeId] = e.earlyReports[strikeId] or {}
		e.earlyReports[strikeId][player] = outcome
	end
end

local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, p in ctx.Characters.alivePlayers() do
		local root = ctx.Characters.rootOf(p)
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best, bestD
end

-- Steering: seek the target, slide around the anvil, keep space between enemies.
local function steer(e, targetPos)
	local pos = e.root.Position
	local desired = flatDir(pos, targetPos)
	-- anvil avoidance
	local toAnvil = Vector3.new(ArenaLayout.AnvilPos.X - pos.X, 0, ArenaLayout.AnvilPos.Z - pos.Z)
	local anvilDist = toAnvil.Magnitude
	local avoidR = ArenaLayout.AnvilRadius + e.cfg.Radius + 1
	if anvilDist < avoidR + 6 and desired:Dot(toAnvil / math.max(anvilDist, 1e-3)) > 0.3 then
		local side = Vector3.new(-toAnvil.Z, 0, toAnvil.X).Unit
		if side:Dot(desired) < 0 then
			side = -side
		end
		local w = math.clamp((avoidR + 6 - anvilDist) / 6, 0, 1)
		desired = (desired * (1 - w) + side * w)
	end
	-- separation
	local sep = Vector3.zero
	for _, o in EnemyService.list do
		if o ~= e and o.state ~= "Dead" then
			local d = Vector3.new(pos.X - o.root.Position.X, 0, pos.Z - o.root.Position.Z)
			local m = d.Magnitude
			local minD = e.cfg.Radius + o.cfg.Radius + 1.5
			if m > 1e-3 and m < minD then
				sep += d / m * (minD - m) / minD
			end
		end
	end
	desired += sep * 1.6
	if desired.Magnitude > 1e-3 then
		desired = desired.Unit
	end
	return desired
end

local function update(e, dt)
	if e.state == "Dead" then
		e.knock *= math.exp(-4 * dt)
		e.lv.PlaneVelocity = Vector2.new(e.knock.X, e.knock.Z)
		return
	end
	local t = now()
	local timeScale = if t < e.slowUntil then 0.25 else 1
	local sdt = dt * timeScale
	local cfg = e.cfg
	local pos = e.root.Position
	local move = Vector3.zero
	local turnSharp = cfg.TurnSharpness

	if pos.Y < ArenaLayout.KillY then
		die(e, nil, "RingOut")
		return
	end

	local state = e.state
	if state == "Spawn" then
		if t - e.stateT >= cfg.SpawnTime then
			setState(e, "Chase")
		end
	elseif state == "Chase" then
		local target, dist = nearestPlayer(pos)
		e.target = target
		if target then
			local troot = ctx.Characters.rootOf(target)
			local tpos = troot.Position
			local faceDir = flatDir(pos, tpos)
			e.yaw = MathUtil.dampAngle(e.yaw, MathUtil.yawFromDir(faceDir), turnSharp, sdt)
			if dist > cfg.Engage then
				move = steer(e, tpos) * cfg.MoveSpeed
			else
				move = steer(e, pos) * cfg.MoveSpeed * 0.3 -- just separation when in range
			end
			if dist <= cfg.Engage and t >= e.cooldownUntil and not EnemyService.passive then
				e.strikeId += 1
				e.strikeT = t + e.windup
				setState(e, "Windup", { StrikeT = e.strikeT, StrikeId = e.strikeId, Target = target.UserId })
			end
		end
	elseif state == "Windup" then
		local progress = (t - e.stateT) / math.max(e.windup, 0.01)
		if progress < cfg.TrackUntil and e.target and ctx.Characters.isAlive(e.target) then
			local troot = ctx.Characters.rootOf(e.target)
			if troot then
				e.yaw = MathUtil.dampAngle(e.yaw, MathUtil.yawFromDir(flatDir(pos, troot.Position)), turnSharp * 0.8, sdt)
			end
		end
		if t >= e.strikeT then
			beginStrike(e)
		end
	elseif state == "Strike" then
		if t - e.stateT >= 0.25 then
			setState(e, "Recover")
		end
	elseif state == "Recover" then
		if t - e.stateT >= cfg.Recover then
			e.cooldownUntil = t + cfg.Cooldown * (0.7 + math.random() * 0.6)
			setState(e, "Chase")
		end
	elseif state == "Stunned" then
		if t >= e.stunUntil then
			e.cooldownUntil = t + 0.6
			setState(e, "Chase")
		end
	elseif state == "Flinch" then
		if t >= e.flinchUntil then
			setState(e, "Chase")
		end
	end

	-- slow time also stretches the state timers
	if timeScale < 1 then
		local lost = dt - sdt
		e.stateT += lost
		if e.strikeT and e.state == "Windup" then
			e.strikeT += lost
			e.model:SetAttribute("StrikeT", e.strikeT)
		end
		e.stunUntil += lost
		e.flinchUntil += lost
		e.model:SetAttribute("StateT", e.stateT)
	end

	e.knock *= math.exp(-6 * dt)
	if e.knock.Magnitude < 0.3 then
		e.knock = Vector3.zero
	end
	local v = move * timeScale + e.knock
	e.lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	e.ao.CFrame = CFrame.Angles(0, e.yaw, 0)
end

local function updatePending()
	local t = now()
	for i = #pendingStrikes, 1, -1 do
		local pending = pendingStrikes[i]
		if t - pending.t > Config.Enemy.StrikeReportTimeout then
			for p in pending.candidates do
				if not pending.resolved[p] then
					resolve(pending, p, "timeout")
				end
			end
			table.remove(pendingStrikes, i)
		end
	end
end

function EnemyService.init(context)
	ctx = context
	folder = workspace:WaitForChild("Enemies")
	RunService.Heartbeat:Connect(function(dt)
		for _, e in EnemyService.list do
			update(e, dt)
		end
		updatePending()
	end)
end

return EnemyService
