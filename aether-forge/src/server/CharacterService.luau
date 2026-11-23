--!nonstrict
-- CharacterService: builds the warrior-smith StarterCharacter, spawns players, owns player HP.
--
-- Player attributes (replicated): HP, MaxHP, Ore, OreFire, OreStorm, OreFrost, Dead, Build, Weapon
-- Server-only per-player combat state lives in CharacterService.state[player], including the run's
-- build (forged upgrades), forge count and run statistics for the end-of-run summary.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Rigs = require(Shared.Rigs)
local RigBuilder = require(Shared.RigBuilder)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Upgrades)

local CharacterService = {}
CharacterService.state = {} -- [player] = { lastParryT, lastDashT, hurtUntil, riposteUntil, swing... }

local ctx

function CharacterService.buildStarterCharacter()
	local old = StarterPlayer:FindFirstChild("StarterCharacter")
	if old then
		old:Destroy()
	end
	local model = RigBuilder.build(Rigs.Player, {
		name = "StarterCharacter",
		weapon = Rigs.Weapons.EmberBlade,
	})
	local root = model.PrimaryPart
	local attach = Instance.new("Attachment")
	attach.Name = "RootAttachment"
	attach.Parent = root

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.AutomaticScalingEnabled = false
	hum.HipHeight = Rigs.Player.hipHeight
	hum.WalkSpeed = Config.Player.WalkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.AutoRotate = false
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.MaxHealth = 100
	hum.Health = 100
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model

	model.Parent = StarterPlayer
	return model
end

local function spawnPoint(player)
	local list = Players:GetPlayers()
	local idx = table.find(list, player) or 1
	local offset = Vector3.new((idx - 1) % 4 * 5 - 7.5, 0, math.floor((idx - 1) / 4) * 5)
	return ArenaLayout.PlayerSpawn + offset
end

local function setupCharacter(player, char)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Player"
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Player"
		end
	end)
	task.defer(function()
		CharacterService.applyWeapon(player)
	end)
	task.defer(function()
		if char.Parent then
			char:PivotTo(CFrame.new(spawnPoint(player)))
		end
	end)
end

local function newRunStats()
	return {
		kills = 0,
		damage = 0,
		crystals = 0,
		ore = { Aether = 0, Fire = 0, Storm = 0, Frost = 0 },
		parries = 0,
		forged = 0,
		bestCombo = 0,
		combo = 0,
		comboAt = 0,
		started = workspace:GetServerTimeNow(),
	}
end

function CharacterService.resetPlayer(player)
	local maxHp = Config.Player.MaxHP + (CharacterService.metaHpBonus and CharacterService.metaHpBonus(player) or 0)
	player:SetAttribute("MaxHP", maxHp)
	player:SetAttribute("HP", maxHp)
	for _, attr in Upgrades.OreAttribute do
		player:SetAttribute(attr, 0)
	end
	player:SetAttribute("Dead", false)
	player:SetAttribute("Build", "")
	player:SetAttribute("Weapon", "EmberBlade")
	CharacterService.state[player] = {
		lastParryT = -100,
		lastDashT = -100,
		hurtUntil = 0,
		riposteUntil = 0,
		swingId = -1,
		swingMove = nil,
		swingHits = {},
		lastSwingStart = { Light = -100, Heavy = -100 },
		build = {},
		stats = Upgrades.stats({}),
		forgeCount = 0,
		run = newRunStats(),
	}
	if CharacterService.onReset then
		CharacterService.onReset(player)
	end
end

function CharacterService.statsOf(player)
	local st = CharacterService.state[player]
	return if st then st.stats else Upgrades.stats({})
end

-- Put the build's weapon (and blade length) on the player's current character.
function CharacterService.applyWeapon(player)
	local st = CharacterService.state[player]
	local char = player.Character
	if not st or not char then
		return
	end
	local id = Upgrades.weaponFor(st.build)
	local def = Rigs.scaledWeapon(Rigs.Weapons[id], st.stats.reach)
	RigBuilder.attachWeapon(char, Rigs.Player, def)
	player:SetAttribute("Weapon", id)
end

-- Recompute stats after the build changed.
function CharacterService.applyBuild(player)
	local st = CharacterService.state[player]
	if not st then
		return
	end
	local oldWeapon = player:GetAttribute("Weapon")
	local oldReach = st.stats.reach
	st.stats = Upgrades.stats(st.build)
	player:SetAttribute("Build", Upgrades.encode(st.build))
	local maxHp = Config.Player.MaxHP + st.stats.maxHpBonus + (CharacterService.metaHpBonus and CharacterService.metaHpBonus(player) or 0)
	player:SetAttribute("MaxHP", maxHp)
	if Upgrades.weaponFor(st.build) ~= oldWeapon or st.stats.reach ~= oldReach then
		CharacterService.applyWeapon(player)
	end
end

function CharacterService.oreOf(player)
	local ores = {}
	for el, attr in Upgrades.OreAttribute do
		ores[el] = player:GetAttribute(attr) or 0
	end
	return ores
end

function CharacterService.spendOre(player, cost)
	for el, n in cost do
		local attr = Upgrades.OreAttribute[el]
		player:SetAttribute(attr, (player:GetAttribute(attr) or 0) - n)
	end
end

function CharacterService.spawn(player)
	CharacterService.resetPlayer(player)
	-- LoadCharacterAsync is the current API; fall back for older engines
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		player:LoadCharacter()
	end
end

function CharacterService.isAlive(player)
	return player.Parent ~= nil
		and player:GetAttribute("Dead") ~= true
		and player.Character ~= nil
		and player.Character.PrimaryPart ~= nil
end

function CharacterService.rootOf(player)
	local char = player.Character
	return char and char.PrimaryPart
end

function CharacterService.alivePlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		if CharacterService.isAlive(p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Damage from an enemy. Returns true if it landed.
function CharacterService.damage(player, amount, fromPos)
	local st = CharacterService.state[player]
	if not st or not CharacterService.isAlive(player) then
		return false
	end
	local now = workspace:GetServerTimeNow()
	if now < st.hurtUntil then
		return false
	end
	st.hurtUntil = now + Config.Player.HurtIFrames
	local hp = math.max(0, (player:GetAttribute("HP") or 0) - amount)
	player:SetAttribute("HP", hp)
	Net.Fx:FireAllClients("PlayerHurt", { player = player, amount = amount, from = fromPos })
	if hp <= 0 then
		player:SetAttribute("Dead", true)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
		end
		Net.Fx:FireAllClients("PlayerDied", { player = player })
		if ctx and ctx.Waves then
			ctx.Waves.onPlayerDied(player)
		end
	end
	return true
end

function CharacterService.heal(player, amount)
	local max = player:GetAttribute("MaxHP") or Config.Player.MaxHP
	player:SetAttribute("HP", math.min(max, (player:GetAttribute("HP") or 0) + amount))
end

function CharacterService.addOre(player, amount, element)
	element = element or "Aether"
	local attr = Upgrades.OreAttribute[element]
	player:SetAttribute(attr, (player:GetAttribute(attr) or 0) + amount)
	local st = CharacterService.state[player]
	if st then
		st.run.ore[element] += amount
	end
end

-- Track a landed hit for the run summary (damage + best combo).
function CharacterService.noteHit(player, damage)
	local st = CharacterService.state[player]
	if not st then
		return
	end
	local run = st.run
	local now = workspace:GetServerTimeNow()
	run.damage += damage
	if now - run.comboAt > 2.4 then
		run.combo = 0
	end
	run.combo += 1
	run.comboAt = now
	run.bestCombo = math.max(run.bestCombo, run.combo)
end

function CharacterService.runStats(player)
	local st = CharacterService.state[player]
	return st and st.run
end

function CharacterService.init(context)
	ctx = context
	Players.CharacterAutoLoads = false
	CharacterService.buildStarterCharacter()

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(char)
			setupCharacter(player, char)
		end)
		CharacterService.spawn(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		CharacterService.state[player] = nil
	end)
end

return CharacterService
