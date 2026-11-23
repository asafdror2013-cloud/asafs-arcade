--!nonstrict
-- WaveService: the run loop. Countdown -> wave (Brutes pour out of the portals) -> breather -> next.
-- When every player is down the run ends, then everything resets.
--
-- workspace attributes (replicated): Wave, Phase ("Countdown" | "Wave" | "Breather" | "Defeat"),
-- EnemiesLeft, PhaseEnds (server time), WavesPaused

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(Shared.Net)

local WaveService = {}
WaveService.paused = false

local ctx
local runId = 0
local toSpawn = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function setPhase(phase, duration)
	workspace:SetAttribute("Phase", phase)
	workspace:SetAttribute("PhaseEnds", if duration then now() + duration else 0)
end

local function updateLeft()
	workspace:SetAttribute("EnemiesLeft", ctx.Enemies.count() + toSpawn)
end

-- Pick the portal farthest from the players so enemies never pop out on top of someone.
local function pickPortal()
	local best, bestScore = ArenaLayout.Portals[1], -math.huge
	for _, portal in ArenaLayout.Portals do
		local score = math.random() * 12
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character.PrimaryPart
			if root then
				score += math.min((root.Position - portal).Magnitude, 40)
			end
		end
		if score > bestScore then
			best, bestScore = portal, score
		end
	end
	return best
end

local function anyAlive()
	return #ctx.Characters.alivePlayers() > 0
end

function WaveService.onEnemyDied(_e)
	task.defer(updateLeft)
end

function WaveService.onPlayerDied(_player)
	-- the run loop polls for defeat
end

local function waitWhile(cond, myRun)
	while cond() and runId == myRun do
		task.wait(0.1)
	end
	return runId == myRun
end

-- End-of-run summary for one player.
local function summaryFor(player, wave)
	local run = ctx.Characters.runStats(player) or {}
	local data = {
		wave = wave,
		kills = run.kills or 0,
		damage = math.floor(run.damage or 0),
		bestCombo = run.bestCombo or 0,
		crystals = run.crystals or 0,
		ore = run.ore or {},
		parries = run.parries or 0,
		forged = run.forged or 0,
		build = player:GetAttribute("Build") or "",
		weapon = player:GetAttribute("Weapon") or "EmberBlade",
		time = math.floor(now() - (run.started or now())),
	}
	if ctx.Meta then
		local ok, err = pcall(function()
			data.meta = ctx.Meta.onRunEnd(player, data)
		end)
		if not ok then
			warn("[Aether Forge] meta save failed: ", err)
		end
	end
	return data
end

function WaveService.resetRun(respawnPlayers)
	runId += 1
	toSpawn = 0
	ctx.Enemies.killAll()
	ctx.Crystals.reset()
	ctx.Forge.reset()
	ctx.Procs.reset()
	workspace:SetAttribute("Wave", 0)
	updateLeft()
	if respawnPlayers then
		for _, p in Players:GetPlayers() do
			ctx.Characters.spawn(p)
		end
	end
	Net.Run:FireAllClients("Reset", {})
	local myRun = runId
	task.spawn(function()
		WaveService.loop(myRun)
	end)
end

function WaveService.loop(myRun)
	-- wait for someone to be in the arena
	if not waitWhile(function()
		return not anyAlive()
	end, myRun) then
		return
	end
	setPhase("Countdown", Config.Waves.FirstDelay)
	Net.Run:FireAllClients("Countdown", { duration = Config.Waves.FirstDelay })
	task.wait(Config.Waves.FirstDelay)

	local wave = 0
	while runId == myRun do
		if not waitWhile(function()
			return WaveService.paused
		end, myRun) then
			return
		end
		wave += 1
		local count = math.min(Config.Waves.Max, Config.Waves.Base + (wave - 1) * Config.Waves.Growth)
		workspace:SetAttribute("Wave", wave)
		setPhase("Wave")
		toSpawn = count
		updateLeft()
		Net.Run:FireAllClients("Wave", { wave = wave, count = count })
		ctx.Crystals.onWave()

		for _ = 1, count do
			if runId ~= myRun or not anyAlive() then
				break
			end
			ctx.Enemies.spawn("Brute", pickPortal(), wave)
			toSpawn -= 1
			updateLeft()
			task.wait(Config.Waves.SpawnInterval)
		end
		toSpawn = 0

		-- fight until the wave is gone or everyone is down
		if not waitWhile(function()
			return ctx.Enemies.count() > 0 and anyAlive()
		end, myRun) then
			return
		end

		if not anyAlive() then
			setPhase("Defeat", 9)
			Net.Run:FireAllClients("Defeat", { wave = wave })
			for _, p in Players:GetPlayers() do
				Net.Run:FireClient(p, "Summary", summaryFor(p, wave))
			end
			task.wait(9)
			if runId == myRun then
				WaveService.resetRun(true)
			end
			return
		end

		setPhase("Breather", Config.Waves.Breather)
		Net.Run:FireAllClients("WaveCleared", { wave = wave, breather = Config.Waves.Breather })
		for _, p in ctx.Characters.alivePlayers() do
			ctx.Characters.heal(p, 15)
		end
		task.wait(Config.Waves.Breather)
	end
end

function WaveService.init(context)
	ctx = context
	workspace:SetAttribute("WavesPaused", false)
	task.defer(WaveService.resetRun, false)
end

return WaveService
