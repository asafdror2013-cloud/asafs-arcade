--!nonstrict
-- CharacterService: builds the warrior-smith StarterCharacter, spawns players, owns player HP.
--
-- Player attributes (replicated): HP, MaxHP, Ore, Dead
-- Server-only per-player combat state lives in CharacterService.state[player].

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Rigs = require(Shared.Rigs)
local RigBuilder = require(Shared.RigBuilder)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(Shared.Net)

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
		if char.Parent then
			char:PivotTo(CFrame.new(spawnPoint(player)))
		end
	end)
end

function CharacterService.resetPlayer(player)
	player:SetAttribute("MaxHP", Config.Player.MaxHP)
	player:SetAttribute("HP", Config.Player.MaxHP)
	player:SetAttribute("Ore", 0)
	player:SetAttribute("Dead", false)
	CharacterService.state[player] = {
		lastParryT = -100,
		lastDashT = -100,
		hurtUntil = 0,
		riposteUntil = 0,
		swingId = -1,
		swingMove = nil,
		swingHits = {},
		lastSwingStart = { Light = -100, Heavy = -100 },
	}
end

function CharacterService.spawn(player)
	CharacterService.resetPlayer(player)
	player:LoadCharacter()
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

function CharacterService.addOre(player, amount)
	player:SetAttribute("Ore", (player:GetAttribute("Ore") or 0) + amount)
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
