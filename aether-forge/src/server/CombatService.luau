--!nonstrict
-- CombatService: validates what clients claim and applies the results.
--   Action        records parry/dash timestamps (used to verify parry and dodge claims) and mirrors
--                 the move onto the character for other clients' animation
--   Hit           player hitbox results -> enemy damage / crystal chips (range + rate checked)
--   StrikeReport  forwarded to EnemyService
--   Debug         Studio-only commands from the tuning panel

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Moves = require(Shared.Moves)
local MathUtil = require(Shared.MathUtil)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(Shared.Net)

local CombatService = {}

local ctx

local VALID_ACTIONS = {
	Light1 = true,
	Light2 = true,
	Light3 = true,
	Heavy = true,
	Dash = true,
	Parry = true,
	Riposte = true,
}

local function now()
	return workspace:GetServerTimeNow()
end

local function onAction(player, kind, t)
	if typeof(kind) ~= "string" or not VALID_ACTIONS[kind] or typeof(t) ~= "number" then
		return
	end
	local st = ctx.Characters.state[player]
	if not st or not ctx.Characters.isAlive(player) then
		return
	end
	local n = now()
	-- trust the client's timestamp only within a sane window around our own clock
	t = math.clamp(t, n - 1, n + 0.1)
	if kind == "Parry" then
		st.lastParryT = t
	elseif kind == "Dash" then
		st.lastDashT = t
	end
	local char = player.Character
	if char then
		char:SetAttribute("Act", kind)
		char:SetAttribute("ActT", t)
	end
end

local function reachOf(move, targetRadius)
	local h = move.hit
	if h.shape == "arc" then
		return h.range + targetRadius
	end
	return (h.offset or 0) + h.radius + targetRadius
end

local function onHit(player, moveName, swingId, targets)
	local move = Moves[moveName]
	if not move or not move.hit or typeof(swingId) ~= "number" or typeof(targets) ~= "table" then
		return
	end
	local st = ctx.Characters.state[player]
	local root = ctx.Characters.rootOf(player)
	if not st or not root or not ctx.Characters.isAlive(player) then
		return
	end
	local n = now()

	-- a new swing has to respect the move's minimum interval
	if swingId ~= st.swingId then
		local minGap = (Moves.MinSwingInterval[move.kind] or 0.1) * 0.7
		if n - (st.lastSwingStart[move.kind] or -100) < minGap then
			return
		end
		st.lastSwingStart[move.kind] = n
		st.swingId = swingId
		st.swingMove = moveName
		st.swingHits = {}
	elseif st.swingMove ~= moveName then
		return
	end

	local riposte = n < st.riposteUntil
	local dmgMult = if riposte then Config.Player.RiposteDamageMult else 1
	local origin = root.Position
	local facing = root.CFrame.LookVector
	local center = origin
	if move.hit.shape == "circle" then
		center = origin + MathUtil.flatUnit(facing) * (move.hit.offset or 0)
	end

	local count = 0
	for _, target in targets do
		count += 1
		if count > 12 then
			break
		end
		if typeof(target) ~= "Instance" or st.swingHits[target] then
			continue
		end
		local parent = target.Parent
		if parent == workspace.Enemies then
			local e = ctx.Enemies.list[target]
			if e and e.state ~= "Dead" then
				local tpos = e.root.Position
				local flat = Vector3.new(tpos.X - origin.X, 0, tpos.Z - origin.Z)
				if flat.Magnitude <= reachOf(move, e.cfg.Radius) + Moves.ServerRangeTolerance then
					st.swingHits[target] = true
					local knockDir = MathUtil.flatUnit(tpos - center, MathUtil.flatUnit(facing))
					ctx.Enemies.damage(e, move.damage * dmgMult, player, {
						knockDir = knockDir,
						knockback = move.knockback,
						launch = move.launch,
						stagger = move.stagger,
						breaksWindup = move.breaksWindup,
						hitstop = Config.Feel[move.hitstop] or 0,
					})
				end
			end
		elseif parent == workspace.Crystals then
			local c = ctx.Crystals.list[target]
			if c and target.PrimaryPart then
				local tpos = target.PrimaryPart.Position
				local flat = Vector3.new(tpos.X - origin.X, 0, tpos.Z - origin.Z)
				if flat.Magnitude <= reachOf(move, 2) + Moves.ServerRangeTolerance then
					st.swingHits[target] = true
					ctx.Crystals.damage(target, move.crystalDamage or 1, player)
				end
			end
		end
	end
end

local function onStrikeReport(player, enemyModel, strikeId, outcome)
	if typeof(enemyModel) ~= "Instance" then
		return
	end
	ctx.Enemies.report(player, enemyModel, strikeId, outcome)
end

local function onDebug(player, cmd, arg)
	if not RunService:IsStudio() then
		return
	end
	if cmd == "SpawnBrute" then
		local root = ctx.Characters.rootOf(player)
		local pos = ArenaLayout.Portals[math.random(1, #ArenaLayout.Portals)]
		if root then
			pos = root.Position + root.CFrame.LookVector * 16
			pos = Vector3.new(pos.X, 0, pos.Z)
			if pos.Magnitude > ArenaLayout.Radius - 6 then
				pos = pos.Unit * (ArenaLayout.Radius - 8)
			end
		end
		ctx.Enemies.spawn("Brute", pos, math.max(1, workspace:GetAttribute("Wave") or 1))
	elseif cmd == "Passive" then
		ctx.Enemies.passive = arg == true
		workspace:SetAttribute("EnemiesPassive", ctx.Enemies.passive)
	elseif cmd == "PauseWaves" then
		ctx.Waves.paused = arg == true
		workspace:SetAttribute("WavesPaused", ctx.Waves.paused)
	elseif cmd == "KillAll" then
		ctx.Enemies.killAll()
	elseif cmd == "Heal" then
		ctx.Characters.heal(player, 1000)
	elseif cmd == "ResetRun" then
		ctx.Waves.resetRun(true)
	elseif cmd == "God" then
		local st = ctx.Characters.state[player]
		if st then
			st.hurtUntil = if arg == true then math.huge else 0
		end
	end
end

function CombatService.init(context)
	ctx = context
	Net.Action.OnServerEvent:Connect(onAction)
	Net.Hit.OnServerEvent:Connect(onHit)
	Net.StrikeReport.OnServerEvent:Connect(onStrikeReport)
	Net.Debug.OnServerEvent:Connect(onDebug)
end

return CombatService
