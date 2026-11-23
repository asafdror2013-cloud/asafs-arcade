--!nonstrict
-- CrystalService: glowing crystal nodes you mine under pressure.
-- Light hits chip them, the Heavy Slam shatters common ones in one hit. Breaking one pays ore to the
-- player who broke it, and a new node grows at another spot a few seconds later.
-- Common (Aether) nodes grow on the inner rings; elemental (Fire / Storm / Frost) nodes grow at the
-- risky arena edge between the portals.
--
-- Crystal model attributes: HP, MaxHP, Tier, Alive, Radius

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local RigBuilder = require(Shared.RigBuilder)
local Net = require(Shared.Net)

local CrystalService = {}
CrystalService.list = {} -- [model] = crystal

local ctx
local folder
local occupied = { common = {}, elemental = {} } -- [set][spotIndex] = model
local ELEMENTS = { "Fire", "Storm", "Frost" }

local ROCK = Color3.fromRGB(58, 52, 62)

local function buildNode(tierName, pos)
	local tier = Config.Crystal[tierName]
	local model = Instance.new("Model")
	model.Name = "Crystal"

	local core = RigBuilder.makePart("Block", Vector3.new(3.4, 4.6, 3.4), Color3.new(1, 1, 1), "SmoothPlastic")
	core.Name = "Core"
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = true
	core.CollisionGroup = "Crystal"
	core.CFrame = CFrame.new(pos + Vector3.new(0, 2.3, 0))
	core.Parent = model

	local function piece(shape, size, cf, color, material, glow)
		local p = RigBuilder.makePart(shape, size, color, material)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(pos) * cf
		if glow then
			p.CastShadow = false
		end
		p.Parent = model
		return p
	end

	-- rocky base
	piece("Block", Vector3.new(3.6, 0.8, 3.2), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0.4, 0.05), ROCK, "Basalt")
	piece("Block", Vector3.new(2.4, 0.7, 2.6), CFrame.new(0.6, 0.55, -0.3) * CFrame.Angles(0.1, 1.1, 0), ROCK, "Basalt")
	-- crystal shards (tall main spire + a cluster around it)
	local shards = {
		{ Vector3.new(1.1, 4.4, 1.1), CFrame.new(0, 2.5, 0) * CFrame.Angles(0.08, 0.7, -0.06) },
		{ Vector3.new(0.8, 3.0, 0.8), CFrame.new(1.0, 1.9, 0.4) * CFrame.Angles(0.2, 0.2, -0.45) },
		{ Vector3.new(0.75, 2.6, 0.75), CFrame.new(-1.0, 1.7, -0.2) * CFrame.Angles(-0.15, 1.2, 0.5) },
		{ Vector3.new(0.6, 2.0, 0.6), CFrame.new(0.2, 1.4, -1.1) * CFrame.Angles(-0.5, 0.4, 0.1) },
		{ Vector3.new(0.55, 1.7, 0.55), CFrame.new(-0.4, 1.3, 1.0) * CFrame.Angles(0.5, 0.9, 0.2) },
	}
	for i, s in shards do
		local p = piece("Block", s[1], s[2] * CFrame.Angles(0, math.rad(45), 0), tier.Color, "Neon", true)
		p.Name = "Shard" .. i
		-- pointed tip
		local tip = piece("Wedge", Vector3.new(s[1].X, s[1].X * 0.9, s[1].Z), s[2] * CFrame.new(0, s[1].Y / 2 + s[1].X * 0.45, 0) * CFrame.Angles(0, math.rad(45), 0), tier.Color, "Neon", true)
		tip.Name = "Tip" .. i
	end
	RigBuilder.addLight(core, { color = tier.Color, range = 14, brightness = 2.2 })

	model.PrimaryPart = core
	model:SetAttribute("Tier", tierName)
	model:SetAttribute("MaxHP", tier.HP)
	model:SetAttribute("HP", tier.HP)
	model:SetAttribute("Alive", true)
	model:SetAttribute("Radius", 2.0)
	return model
end

local function spotsOf(set)
	return if set == "elemental" then ArenaLayout.RiskySpots else ArenaLayout.CrystalSpots
end

local function freeSpot(set)
	local options = {}
	for i, spot in spotsOf(set) do
		if not occupied[set][i] then
			local clear = true
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character.PrimaryPart
				if root and (root.Position - spot).Magnitude < 7 then
					clear = false
				end
			end
			if clear then
				table.insert(options, i)
			end
		end
	end
	if #options == 0 then
		return nil
	end
	return options[math.random(1, #options)]
end

function CrystalService.spawnOne(set)
	set = set or "common"
	local idx = freeSpot(set)
	if not idx then
		return nil
	end
	local spot = spotsOf(set)[idx]
	local tierName = if set == "elemental" then ELEMENTS[math.random(1, #ELEMENTS)] else "Common"
	local model = buildNode(tierName, spot)
	model:SetAttribute("Element", Config.Crystal[tierName].element)
	model.Parent = folder
	occupied[set][idx] = model
	local c = { model = model, spot = idx, set = set, tier = tierName, hp = Config.Crystal[tierName].HP }
	CrystalService.list[model] = c
	return c
end

local function wanted(set)
	if set == "common" then
		return Config.Crystal.Spots
	end
	local wave = workspace:GetAttribute("Wave") or 0
	return if wave >= 4 then Config.Crystal.ElementalSpotsLate else Config.Crystal.ElementalSpots
end

local function activeIn(set)
	local n = 0
	for _, c in CrystalService.list do
		if c.set == set then
			n += 1
		end
	end
	return n
end

local function scheduleRespawn(set, delay)
	task.delay(delay, function()
		if activeIn(set) < wanted(set) then
			if not CrystalService.spawnOne(set) then
				scheduleRespawn(set, 1.5)
			elseif activeIn(set) < wanted(set) then
				scheduleRespawn(set, 2)
			end
		end
	end)
end

-- Called when a wave starts: late waves grow a second elemental node.
function CrystalService.onWave()
	if activeIn("elemental") < wanted("elemental") then
		scheduleRespawn("elemental", 1)
	end
end

function CrystalService.damage(model, amount, player)
	local c = CrystalService.list[model]
	if not c then
		return false
	end
	c.hp -= amount
	model:SetAttribute("HP", math.max(0, c.hp))
	if c.hp > 0 then
		return true
	end
	-- shatter
	local tier = Config.Crystal[c.tier]
	CrystalService.list[model] = nil
	occupied[c.set][c.spot] = nil
	model:SetAttribute("Alive", false)
	local ore = tier.Ore
	if player then
		ore += ctx.Characters.statsOf(player).oreBonus
		ctx.Characters.addOre(player, ore, tier.element)
		local run = ctx.Characters.runStats(player)
		if run then
			run.crystals += 1
		end
	end
	Net.Fx:FireAllClients("CrystalBreak", {
		pos = model.PrimaryPart.Position,
		color = tier.Color,
		ore = ore,
		element = tier.element,
		player = player,
	})
	task.delay(0.05, function()
		model:Destroy()
	end)
	scheduleRespawn(c.set, tier.Respawn)
	return true
end

function CrystalService.reset()
	for model in CrystalService.list do
		model:Destroy()
	end
	table.clear(CrystalService.list)
	table.clear(occupied.common)
	table.clear(occupied.elemental)
	for _ = 1, Config.Crystal.Spots do
		CrystalService.spawnOne("common")
	end
	for _ = 1, Config.Crystal.ElementalSpots do
		CrystalService.spawnOne("elemental")
	end
end

function CrystalService.init(context)
	ctx = context
	folder = workspace:WaitForChild("Crystals")
	CrystalService.reset()
end

return CrystalService
