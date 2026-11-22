--!nonstrict
-- Combat: the local player's controller. Owns the move state machine and all the moment-to-moment
-- feel: buffered inputs, combo chains, cancels, lunges with aim assist, hit detection, hitstop,
-- dash i-frames, parry -> riposte, and how enemy strikes resolve against you.
--
-- States: Free | Attack | Dash | Parry | Riposte | Hurt | Dead
-- Move timings come from Moves.luau; feel numbers from Config.Feel (live-tunable).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Moves = require(Shared.Moves)
local Rigs = require(Shared.Rigs)
local Clips = require(Shared.Clips)
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)

local RigAnimator = require(script.Parent.RigAnimator)
local Effects = require(script.Parent.Effects)
local Sfx = require(script.Parent.Sfx)
local Clock = require(script.Parent.Clock)
local Input = require(script.Parent.Input)
local CameraRig = require(script.Parent.CameraRig)
local EnemyViews = require(script.Parent.EnemyViews)

local Combat = {}
Combat.hooks = {} -- onHits(count, total), onParry(), onHurt(), onRiposte(untilServerT)
Combat.debugHitbox = false

local player = Players.LocalPlayer
local AETHER = Config.Palette.Aether
local GOLD = Config.Palette.Gold
local UP = Vector3.yAxis

-- character refs
local char, root, humanoid, anim, drive, face, trail

-- state
local state = "Free"
local move = nil
local moveT = 0
local swingId = 0
local hitSet = {}
local attackYaw, facingYaw = 0, 0
local lockTarget = nil -- { pos = fn, radius = n }
local comboNext, comboExpire = nil, 0
local lastDashReal, lastParryReal = -100, -100
local dashDir = Vector3.new(0, 0, -1)
local dashServerT, parryServerT = -100, -100
local hurtIFramesUntil = 0
local riposteUntil = 0
local knockVel = Vector3.zero
local lastAfterimage = 0
local swingSoundDone, slamDone = false, false
local comboCount, comboTimer = 0, 0
local lastPredictedHurt = -100
local prevVel = Vector3.zero
local leanCF = CFrame.identity
local debugParts = {}

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function facingDir()
	return MathUtil.dirFromYaw(facingYaw)
end

local function stunned(model)
	return model:GetAttribute("State") == "Stunned"
end

------------------------------------------------------------------------ targeting

local function crystalTargets()
	local list = {}
	local folder = workspace:FindFirstChild("Crystals")
	if folder then
		for _, m in folder:GetChildren() do
			if m:GetAttribute("Alive") and m.PrimaryPart then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- Best target inside the aim-assist cone: enemies first, crystals if no enemy fits.
local function findLock(aimDir)
	local rp = root.Position
	local best, bestScore = nil, math.huge
	local range, maxAng = Config.Feel.SoftLockRange, Config.Feel.SoftLockAngle
	local function consider(model, pos, radius, bias)
		local d = flat(pos - rp)
		local dist = d.Magnitude
		if dist > range + radius or dist < 0.05 then
			return
		end
		local ang = math.deg(math.acos(math.clamp(aimDir:Dot(d / dist), -1, 1)))
		if ang > maxAng then
			return
		end
		local score = ang / maxAng + dist / range * 0.7 + bias
		if score < bestScore then
			best, bestScore = { model = model, part = model.PrimaryPart, radius = radius }, score
		end
	end
	for _, view in EnemyViews.alive() do
		consider(view.model, view.root.Position, view.cfg.Radius, 0)
	end
	for _, m in crystalTargets() do
		consider(m, m.PrimaryPart.Position, 2, 0.35)
	end
	return best
end

local function aimFor(useLock)
	local aim = Input.aimDirection(root.Position, humanoid.MoveDirection, facingDir())
	aim = MathUtil.flatUnit(aim, facingDir())
	lockTarget = nil
	if useLock then
		lockTarget = findLock(aim)
		if lockTarget and lockTarget.part then
			aim = MathUtil.flatUnit(lockTarget.part.Position - root.Position, aim)
		end
	end
	return aim
end

------------------------------------------------------------------------ hitboxes

local function inHitbox(m, pos, radius)
	local rp = root.Position
	if math.abs(pos.Y - rp.Y) > 8 then
		return false
	end
	local f = MathUtil.dirFromYaw(attackYaw)
	local h = m.hit
	if h.shape == "arc" then
		local d = flat(pos - rp)
		local dist = d.Magnitude
		if dist - radius > h.range then
			return false
		end
		if dist < radius + 1 then
			return true
		end
		local ang = math.deg(math.acos(math.clamp(f:Dot(d / dist), -1, 1)))
		local widen = math.deg(math.asin(math.clamp(radius / dist, 0, 1)))
		return ang <= h.arc / 2 + widen
	else
		local c = rp + f * (h.offset or 0)
		return flat(pos - c).Magnitude - radius <= h.radius
	end
end

local function cutAcross(m, f)
	local across = f:Cross(UP)
	if m.name == "Light1" then
		return (across + UP * 0.3).Unit
	elseif m.name == "Light2" then
		return (across - UP * 0.3).Unit
	elseif m.kind == "Heavy" then
		return (UP + across * 0.25).Unit
	end
	return across
end

local function detectHits()
	local m = move
	if not m or not m.hit or moveT < m.active[1] or moveT > m.active[2] then
		return
	end
	local newEnemies, newCrystals, models = {}, {}, {}
	for _, view in EnemyViews.alive() do
		if not hitSet[view.model] and inHitbox(m, view.root.Position, view.cfg.Radius) then
			hitSet[view.model] = true
			table.insert(newEnemies, view)
			table.insert(models, view.model)
		end
	end
	for _, c in crystalTargets() do
		if not hitSet[c] and inHitbox(m, c.PrimaryPart.Position, 2) then
			hitSet[c] = true
			table.insert(newCrystals, c)
			table.insert(models, c)
		end
	end
	if #models == 0 then
		return
	end
	Net.Hit:FireServer(m.name, swingId, models)

	local f = MathUtil.dirFromYaw(attackYaw)
	local isBig = m.kind == "Heavy" or m.name == "Light3"
	local riposte = Clock.server() < riposteUntil
	if #newEnemies > 0 then
		local hs = Config.Feel[m.hitstop] or 0.05
		Clock.hitstop(hs)
		CameraRig.shake(Config.Feel[m.shake] or 0.2)
		CameraRig.kick(f, if isBig then 0.6 else 0.25)
		if isBig then
			CameraRig.punch(-4)
			Effects.grade(0.1, 0.25, 0.04, 0.2)
		end
		for _, view in newEnemies do
			local epos = view.root.Position
			local dir = MathUtil.flatUnit(epos - root.Position, f)
			local dmg = m.damage * (if riposte then Config.Player.RiposteDamageMult else 1) * (if stunned(view.model) then 1.25 else 1)
			EnemyViews.onLocalHit(view.model, hs, dir, dmg, isBig or riposte)
			local impact = epos + UP * 1.2 - dir * 1.4
			local color = if riposte then GOLD else AETHER
			Effects.sparks(impact, (-dir + UP * 0.4).Unit, color, if isBig then 28 else 16, if isBig then 1.4 else 1)
			Effects.flash(impact, Color3.new(1, 1, 1), if isBig then 7 else 3.6, 0.1)
			Effects.cutLine(impact, cutAcross(m, f), color, if isBig then 10 else 7, 0.16)
		end
		Sfx.play(if isBig then "HitBig" else "Hit")
		comboCount += #newEnemies
		comboTimer = 2.4
		if Combat.hooks.onHits then
			Combat.hooks.onHits(#newEnemies, comboCount)
		end
	end
	for _, c in newCrystals do
		local cpos = c.PrimaryPart.Position
		local dir = MathUtil.flatUnit(cpos - root.Position, f)
		if #newEnemies == 0 then
			Clock.hitstop(Config.Feel.HitstopCrystal)
			CameraRig.shake(0.14)
		end
		local color = c.PrimaryPart:FindFirstChildOfClass("PointLight") and c.PrimaryPart:FindFirstChildOfClass("PointLight").Color or AETHER
		Effects.sparks(cpos - dir * 1.5, (-dir + UP).Unit, color, 14, 0.9)
		Effects.flash(cpos - dir * 1.2, color, 3, 0.1)
		Sfx.play("CrystalHit")
	end
end

local function drawDebugHitbox()
	for _, p in debugParts do
		p.Transparency = 1
	end
	if not Combat.debugHitbox or not move or not move.hit or state ~= "Attack" then
		return
	end
	local active = moveT >= move.active[1] and moveT <= move.active[2]
	local f = MathUtil.dirFromYaw(attackYaw)
	local rp = Vector3.new(root.Position.X, 0.3, root.Position.Z)
	local h = move.hit
	local n = 28
	for i = 1, n do
		local p = debugParts[i]
		if not p then
			p = Effects.newPart("Block", Vector3.new(0.5, 0.1, 0.5), Color3.new(1, 0, 0))
			debugParts[i] = p
		end
		local pos
		if h.shape == "arc" then
			local a = attackYaw - math.rad(h.arc / 2) + (i - 1) / (n - 1) * math.rad(h.arc)
			pos = rp + MathUtil.dirFromYaw(a) * h.range
		else
			local a = (i - 1) / n * math.pi * 2
			pos = rp + f * (h.offset or 0) + Vector3.new(math.sin(a), 0, math.cos(a)) * h.radius
		end
		p.CFrame = CFrame.new(pos)
		p.Color = if active then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 200, 60)
		p.Transparency = 0.2
	end
end

------------------------------------------------------------------------ moves

local function setTrail(on, gold)
	if not trail then
		return
	end
	if on and not trail.Enabled then
		local c = if gold then GOLD else AETHER
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), c)
	end
	trail.Enabled = on
end

local function startAttack(name)
	move = Moves[name]
	state = "Attack"
	moveT = 0
	swingId += 1
	hitSet = {}
	swingSoundDone, slamDone = false, false
	local aim = aimFor(true)
	attackYaw = MathUtil.yawFromDir(aim)
	facingYaw = attackYaw
	anim:play(move.clip, { fadeIn = 0.035 })
	Net.Action:FireServer(name, Clock.server())
	comboNext = move.next
	comboExpire = Clock.sim + move.length + (move.comboGrace or 0)
end

local function startDash()
	local md = humanoid.MoveDirection
	if md.Magnitude > 0.1 then
		dashDir = MathUtil.flatUnit(md)
	else
		dashDir = aimFor(false)
	end
	move = Moves.Dash
	state = "Dash"
	moveT = 0
	facingYaw = MathUtil.yawFromDir(dashDir)
	lastDashReal = Clock.real
	dashServerT = Clock.server()
	Net.Action:FireServer("Dash", dashServerT)
	anim:play("Dash", { fadeIn = 0.02 })
	setTrail(false)
	Sfx.play("Dash")
	CameraRig.punch(3)
	Effects.afterimage(char, AETHER, 0.3)
	Effects.dust(Vector3.new(root.Position.X, 0.3, root.Position.Z), 6)
	lastAfterimage = Clock.real
end

local function startParry()
	local aim = aimFor(true)
	facingYaw = MathUtil.yawFromDir(aim)
	move = Moves.Parry
	state = "Parry"
	moveT = 0
	lastParryReal = Clock.real
	parryServerT = Clock.server()
	Net.Action:FireServer("Parry", parryServerT)
	anim:play("Parry", { fadeIn = 0.025 })
	setTrail(false)
end

local function canDashCancel()
	if state == "Free" or state == "Riposte" then
		return true
	end
	if state == "Attack" then
		local dc = move.dashCancel
		if dc == "any" then
			return true
		end
		if type(dc) == "table" then
			for _, w in dc do
				if moveT >= w[1] and moveT <= w[2] then
					return true
				end
			end
		end
		return false
	end
	if state == "Hurt" then
		return moveT >= Config.Player.HurtStun
	end
	return false
end

local function tryAction(action)
	if state == "Dead" then
		return false
	end
	if state == "Hurt" and moveT < Config.Player.HurtStun then
		return false
	end
	if action == "Dash" then
		if Clock.real - lastDashReal < Moves.Dash.cooldown or not canDashCancel() then
			return false
		end
		startDash()
		return true
	elseif action == "Light" then
		local nextName = "Light1"
		if comboNext and Clock.sim <= comboExpire then
			nextName = comboNext
		end
		if state == "Free" or state == "Riposte" or state == "Hurt" then
			startAttack(nextName)
			return true
		elseif state == "Attack" then
			if moveT >= move.chainFrom then
				startAttack(if move.next then move.next else "Light1")
				return true
			end
		elseif state == "Dash" then
			if moveT >= Moves.Dash.attackFrom then
				startAttack("Light1")
				return true
			end
		end
		return false
	elseif action == "Heavy" then
		local can = state == "Free"
			or state == "Riposte"
			or state == "Hurt"
			or (state == "Attack" and move.kind == "Light" and moveT >= move.chainFrom)
			or (state == "Dash" and moveT >= Moves.Dash.attackFrom)
		if can then
			startAttack("Heavy")
		end
		return can
	elseif action == "Parry" then
		if Clock.real - lastParryReal < Moves.Parry.cooldown then
			return false
		end
		local can = state == "Free"
			or state == "Riposte"
			or state == "Hurt"
			or (state == "Attack" and move.kind == "Light" and moveT >= move.active[2])
		if can then
			startParry()
		end
		return can
	end
	return false
end

local function processInput()
	local i = 1
	while i <= #Input.buffer do
		local entry = Input.buffer[i]
		if Clock.real - entry.time > Config.Feel.InputBuffer then
			table.remove(Input.buffer, i)
		elseif tryAction(entry.action) then
			table.remove(Input.buffer, i)
			-- one new action per frame keeps buffered chains readable
			return
		else
			i += 1
		end
	end
end

------------------------------------------------------------------------ incoming strikes

local function parrySuccess(view)
	comboNext = nil
	state = "Riposte"
	move = Moves.Riposte
	moveT = 0
	anim:play("Riposte", { fadeIn = 0 })
	riposteUntil = Clock.server() + Config.Player.RiposteDuration
	Clock.hitstop(Config.Feel.HitstopParry)
	Clock.slowmo(Config.Feel.ParrySlowmoScale, Config.Feel.ParrySlowmoDuration)
	local epos = view.root.Position
	local mid = root.Position:Lerp(epos, 0.45) + UP * 1.5
	Effects.sparks(mid, UP, GOLD, 40, 1.5)
	Effects.sparks(mid, MathUtil.flatUnit(root.Position - epos), Color3.new(1, 1, 1), 20, 1.2)
	Effects.flash(mid, Color3.new(1, 1, 1), 7, 0.16)
	Effects.screenFlash(Color3.new(1, 1, 1), 0.35, 0.2)
	Effects.grade(-0.75, 0.25, 0.05, Config.Feel.ParrySlowmoDuration + 0.25)
	Effects.shockwave(Vector3.new(epos.X, 0, epos.Z), 9, GOLD, 0.4)
	Effects.callout(epos, "PARRY!", GOLD)
	CameraRig.shake(Config.Feel.ShakeParry)
	CameraRig.punch(-8)
	EnemyViews.onLocalHit(view.model, Config.Feel.HitstopParry + 0.05, MathUtil.flatUnit(epos - root.Position), nil, true)
	Sfx.play("Parry")
	setTrail(true, true)
	if Combat.hooks.onParry then
		Combat.hooks.onParry(riposteUntil)
	end
end

local function takeHit(fromPos)
	state = "Hurt"
	move = Moves.Hurt
	moveT = 0
	anim:play("Hurt", { fadeIn = 0 })
	setTrail(false)
	hurtIFramesUntil = Clock.server() + Config.Player.HurtIFrames
	local dir = if fromPos then MathUtil.flatUnit(root.Position - fromPos, -facingDir()) else -facingDir()
	knockVel = dir * Config.Player.HurtKnockback
	Clock.hitstop(0.06)
	Effects.vignette(Config.Palette.Danger, 0.65, 0.55)
	Effects.screenFlash(Config.Palette.Danger, 0.78, 0.14)
	Effects.sparks(root.Position + UP, dir, Config.Palette.Danger, 14, 1)
	CameraRig.shake(Config.Feel.ShakeHurt)
	CameraRig.kick(dir, 0.5)
	Sfx.play("Hurt")
	lastPredictedHurt = Clock.real
	Input.clear()
	if Combat.hooks.onHurt then
		Combat.hooks.onHurt()
	end
end

-- Called by EnemyViews the moment an enemy's strike lands (server-scheduled StrikeT).
function Combat.onStrike(view, strikeId)
	if not root or state == "Dead" then
		return
	end
	local model = view.model
	local cfg = view.cfg
	local origin = view.root.Position
	local f = MathUtil.flatUnit(view.root.CFrame.LookVector)
	local range = cfg.AttackRange + Config.Player.BodyRadius
	local d = flat(root.Position - origin)
	local dist = d.Magnitude
	local inArc = dist <= range and (dist < 1.5 or math.deg(math.acos(math.clamp(f:Dot(d / dist), -1, 1))) <= cfg.AttackArc / 2)
	if not inArc then
		if dist < range + 10 then
			Net.StrikeReport:FireServer(model, strikeId, "miss")
		end
		return
	end
	local strikeT = model:GetAttribute("StrikeT") or Clock.server()
	local sinceParry = strikeT - parryServerT
	local sinceDash = strikeT - dashServerT
	-- a press up to 50ms after impact still counts (latency + frame timing grace)
	if sinceParry >= -0.05 and sinceParry <= Moves.Parry.active[2] + 0.02 then
		parrySuccess(view)
		Net.StrikeReport:FireServer(model, strikeId, "parry")
	elseif sinceDash >= -0.03 and sinceDash <= Moves.Dash.iframes[2] + 0.02 then
		Net.StrikeReport:FireServer(model, strikeId, "dodge")
		Effects.afterimage(char, Color3.new(1, 1, 1), 0.35)
		Effects.callout(root.Position, "DODGE", Color3.new(1, 1, 1))
	elseif Clock.server() < hurtIFramesUntil then
		Net.StrikeReport:FireServer(model, strikeId, "dodge")
	else
		takeHit(origin)
		Net.StrikeReport:FireServer(model, strikeId, "hurt")
	end
end

------------------------------------------------------------------------ per-frame

local function stepState(simDt)
	moveT += simDt
	if state == "Attack" then
		local m = move
		if not swingSoundDone and moveT >= m.active[1] - 0.03 then
			swingSoundDone = true
			Sfx.play(m.swingSound or "Swing")
		end
		if m.kind == "Heavy" and not slamDone and moveT >= m.active[1] then
			slamDone = true
			local f = MathUtil.dirFromYaw(attackYaw)
			local pos = Vector3.new(root.Position.X, 0, root.Position.Z) + f * m.hit.offset
			Effects.shockwave(pos, m.hit.radius + 3, AETHER, 0.42, 7)
			Effects.dust(pos + UP * 0.3, 16)
			Effects.sparks(pos + UP * 0.4, UP, AETHER, 26, 1.3)
			Effects.flash(pos + UP, AETHER, 8, 0.14)
			CameraRig.shake(Config.Feel.ShakeSlamWhiff)
			CameraRig.punch(-6)
			Sfx.play("Slam")
		end
		local tw = m.trail
		setTrail(tw ~= nil and moveT >= tw[1] and moveT <= tw[2], Clock.server() < riposteUntil)
		detectHits()
		if moveT >= m.length then
			state = "Free"
			move = nil
			setTrail(false)
		end
	elseif state == "Dash" then
		if Clock.real - lastAfterimage > 0.045 and moveT < Moves.Dash.length * 0.85 then
			lastAfterimage = Clock.real
			Effects.afterimage(char, AETHER, 0.25)
		end
		if moveT >= Moves.Dash.length then
			state = "Free"
			move = nil
		end
	elseif state == "Parry" then
		if moveT >= Moves.Parry.length then
			state = "Free"
			move = nil
		end
	elseif state == "Riposte" then
		setTrail(moveT >= 0.02 and moveT <= 0.14, true)
		if moveT >= Moves.Riposte.length then
			state = "Free"
			move = nil
			setTrail(false)
		end
	elseif state == "Hurt" then
		knockVel *= math.exp(-9 * simDt)
		if moveT >= Moves.Hurt.length then
			state = "Free"
			move = nil
		end
	end
end

local function controlBody(simDt)
	local ts = Clock.scale()
	local walk = Config.Player.WalkSpeed
	local driveVel = nil
	if state == "Free" then
		humanoid.WalkSpeed = walk * ts
		local md = humanoid.MoveDirection
		if md.Magnitude > 0.1 then
			facingYaw = MathUtil.dampAngle(facingYaw, MathUtil.yawFromDir(md), Config.Player.TurnSharpness, simDt)
		end
	elseif state == "Attack" then
		humanoid.WalkSpeed = Config.Player.AttackWalkSpeed * ts
		facingYaw = attackYaw
		local l = move.lunge
		if l and moveT >= l.from and moveT <= l.to then
			local speed = l.speed
			if lockTarget and lockTarget.part and lockTarget.part.Parent then
				local gap = flat(lockTarget.part.Position - root.Position).Magnitude - lockTarget.radius - 2.4
				local left = math.max(l.to - moveT, 0.02)
				if gap > Config.Feel.LungeMagnet then
					speed = l.speed
				else
					speed = math.clamp(gap / left, 0, l.speed * 1.6)
				end
			end
			driveVel = MathUtil.dirFromYaw(attackYaw) * speed
		end
	elseif state == "Dash" then
		humanoid.WalkSpeed = 0
		local k = MathUtil.Ease.outQuad(math.clamp(moveT / Moves.Dash.length, 0, 1))
		local speed = Moves.Dash.speedStart + (Moves.Dash.speedEnd - Moves.Dash.speedStart) * k
		driveVel = dashDir * speed
	elseif state == "Hurt" then
		humanoid.WalkSpeed = 0
		driveVel = knockVel
	else -- Parry, Riposte, Dead: planted
		humanoid.WalkSpeed = 0
		driveVel = Vector3.zero
	end
	if Clock.inHitstop() and driveVel == nil then
		driveVel = Vector3.zero
	end
	if driveVel then
		drive.Enabled = true
		local v = driveVel * ts
		drive.PlaneVelocity = Vector2.new(v.X, v.Z)
	else
		drive.Enabled = false
	end
	face.CFrame = CFrame.Angles(0, facingYaw, 0)

	-- soft body: slide out of enemies instead of walking through them (not while dashing)
	if state ~= "Dash" then
		local rp = root.Position
		local push = Vector3.zero
		for _, view in EnemyViews.alive() do
			local d = flat(rp - view.root.Position)
			local minD = Config.Player.BodyRadius + view.cfg.Radius
			local m = d.Magnitude
			if m < minD and m > 1e-3 then
				push += d / m * (minD - m)
			end
		end
		if push.Magnitude > 0.01 then
			root.CFrame += push * 0.35
		end
	end
end

local function animate(dt, simDt)
	local vel = flat(root.AssemblyLinearVelocity)
	local speed = vel.Magnitude
	local moveLocal = if speed > 0.5 then root.CFrame:VectorToObjectSpace(vel / speed) else Vector3.new(0, 0, -1)
	-- lean into acceleration
	if dt > 0 then
		local accel = (vel - prevVel) / dt
		local a = root.CFrame:VectorToObjectSpace(accel)
		local k = 0.0022
		local target = CFrame.Angles(math.clamp(a.Z * k, -0.18, 0.18), 0, math.clamp(-a.X * k, -0.18, 0.18))
		if state ~= "Free" then
			target = CFrame.identity
		end
		leanCF = leanCF:Lerp(target, math.clamp(dt * 10, 0, 1))
	end
	prevVel = vel
	anim.lean = leanCF
	local frozen = Clock.inHitstop()
	if frozen and not anim.frozen then
		anim:freeze(true, 0.08)
	elseif not frozen and anim.frozen then
		anim:freeze(false)
	end
	anim:update(simDt, { speed = if state == "Free" then speed else speed * 0.3, moveLocal = Vector3.new(moveLocal.X, 0, moveLocal.Z) })
end

function Combat.update(dt, simDt)
	if not char or not root or not root.Parent or not humanoid then
		return
	end
	if player:GetAttribute("Dead") == true and state ~= "Dead" then
		state = "Dead"
		move = nil
		setTrail(false)
		anim:play("Hurt", { fadeIn = 0.05, hold = true })
		anim.lean = CFrame.new(0, -0.6, 0) * CFrame.Angles(0.5, 0, 0)
	end
	if state ~= "Dead" then
		processInput()
	end
	stepState(simDt)
	controlBody(simDt)
	animate(dt, simDt)
	drawDebugHitbox()
	if comboTimer > 0 then
		comboTimer -= dt
		if comboTimer <= 0 then
			comboCount = 0
			if Combat.hooks.onHits then
				Combat.hooks.onHits(0, 0)
			end
		end
	end
end

------------------------------------------------------------------------ setup

local function onCharacter(c)
	char = c
	root = c:WaitForChild("HumanoidRootPart")
	humanoid = c:WaitForChild("Humanoid")
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	anim = RigAnimator.new(c, Rigs.Player, Clips.Player)

	local att = root:FindFirstChild("RootAttachment") or Instance.new("Attachment")
	att.Name = "RootAttachment"
	att.Parent = root

	drive = Instance.new("LinearVelocity")
	drive.Name = "AF_Drive"
	drive.Attachment0 = att
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.MaxForce = 1e6
	drive.Enabled = false
	drive.Parent = root

	face = Instance.new("AlignOrientation")
	face.Name = "AF_Face"
	face.Mode = Enum.OrientationAlignmentMode.OneAttachment
	face.Attachment0 = att
	face.RigidityEnabled = true
	face.Parent = root

	local weapon = c:WaitForChild("Weapon")
	trail = Instance.new("Trail")
	trail.Attachment0 = weapon:WaitForChild("TrailBase")
	trail.Attachment1 = weapon:WaitForChild("TrailTip")
	trail.Lifetime = 0.13
	trail.MinLength = 0.02
	trail.FaceCamera = false
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), AETHER)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.35) })
	trail.Enabled = false
	trail.Parent = weapon

	state = "Free"
	move = nil
	moveT = 0
	comboNext = nil
	knockVel = Vector3.zero
	hurtIFramesUntil = 0
	riposteUntil = 0
	facingYaw = 0
	Input.clear()
	CameraRig.snap()

end

function Combat.state()
	return state
end

function Combat.root()
	return root
end

function Combat.riposteUntil()
	return riposteUntil
end

function Combat.dashReady()
	return math.clamp((Clock.real - lastDashReal) / Moves.Dash.cooldown, 0, 1)
end

function Combat.init()
	local lastHp = player:GetAttribute("HP") or 100
	player:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = player:GetAttribute("HP") or 0
		if hp < lastHp and root and Clock.real - lastPredictedHurt > 0.6 and state ~= "Dead" then
			-- the server landed a hit we did not predict (late report / lag)
			local nearest, nd = nil, math.huge
			for _, view in EnemyViews.alive() do
				local dd = (view.root.Position - root.Position).Magnitude
				if dd < nd then
					nearest, nd = view, dd
				end
			end
			takeHit(nearest and nearest.root.Position or nil)
		end
		lastHp = hp
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Combat
