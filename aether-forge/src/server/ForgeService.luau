--!nonstrict
-- ForgeService: the Aether Anvil. Walk up to it and press E (a ProximityPrompt): the server rolls
-- three upgrades you can afford, your client shows them as cards, you pick one and pay the ore.
-- Costs climb with every forge; elemental upgrades also cost that element's ore.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Upgrades = require(Shared.Upgrades)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(Shared.Net)

local ForgeService = {}

local ctx
local pending = {} -- [player] = { offers = { ids } }

local function now()
	return workspace:GetServerTimeNow()
end

local function nearAnvil(player)
	local root = ctx.Characters.rootOf(player)
	if not root then
		return false
	end
	local d = Vector3.new(root.Position.X - ArenaLayout.AnvilPos.X, 0, root.Position.Z - ArenaLayout.AnvilPos.Z)
	return d.Magnitude <= 16
end

local function offerPayload(st, offers)
	local list = {}
	for _, id in offers do
		local u = Upgrades.byId[id]
		table.insert(list, {
			id = id,
			level = st.build[id] or 0,
			cost = Upgrades.cost(st.forgeCount, u.element),
		})
	end
	return { offers = list, forgeCount = st.forgeCount }
end

local function onTriggered(player)
	if not ctx.Characters.isAlive(player) then
		return
	end
	local st = ctx.Characters.state[player]
	if not st then
		return
	end
	local p = pending[player]
	if p then
		Net.Forge:FireClient(player, "Offer", offerPayload(st, p.offers))
		return
	end
	local ores = ctx.Characters.oreOf(player)
	local base = Upgrades.cost(st.forgeCount, nil)
	if ores.Aether < base.Aether then
		Net.Forge:FireClient(player, "Denied", { reason = "Need " .. base.Aether .. " Aether ore (you have " .. ores.Aether .. ")" })
		return
	end
	local offers = Upgrades.roll(st.build, ores, st.forgeCount, function(n)
		return math.random(1, n)
	end, 3)
	if #offers == 0 then
		Net.Forge:FireClient(player, "Denied", { reason = "Your build is fully forged." })
		return
	end
	pending[player] = { offers = offers, at = now() }
	Net.Forge:FireClient(player, "Offer", offerPayload(st, offers))
end

local function onClient(player, kind, data)
	if kind == "Close" then
		pending[player] = nil
		return
	end
	if kind ~= "Pick" or typeof(data) ~= "number" then
		return
	end
	local p = pending[player]
	local st = ctx.Characters.state[player]
	if not p or not st or not ctx.Characters.isAlive(player) then
		return
	end
	local id = p.offers[math.floor(data)]
	if not id then
		return
	end
	if not nearAnvil(player) then
		Net.Forge:FireClient(player, "Denied", { reason = "Too far from the anvil." })
		return
	end
	local u = Upgrades.byId[id]
	local cost = Upgrades.cost(st.forgeCount, u.element)
	if not Upgrades.canAfford(ctx.Characters.oreOf(player), cost) then
		Net.Forge:FireClient(player, "Denied", { reason = "Not enough ore." })
		return
	end
	if (st.build[id] or 0) >= u.max then
		return
	end
	ctx.Characters.spendOre(player, cost)
	st.build[id] = (st.build[id] or 0) + 1
	st.forgeCount += 1
	st.run.forged += 1
	pending[player] = nil
	ctx.Characters.applyBuild(player)
	if id == "core" then
		ctx.Characters.heal(player, 10000)
	end
	Net.Forge:FireClient(player, "Forged", { id = id, level = st.build[id], weapon = player:GetAttribute("Weapon") })
	Net.Fx:FireAllClients("Forged", { player = player, element = u.element })
end

function ForgeService.reset()
	table.clear(pending)
end

function ForgeService.init(context)
	ctx = context
	local anvil = workspace:WaitForChild("Arena"):WaitForChild("AnvilFace")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ForgePrompt"
	prompt.ActionText = "Forge"
	prompt.ObjectText = "Aether Anvil"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonL1
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = anvil
	prompt.Triggered:Connect(onTriggered)
	Net.Forge.OnServerEvent:Connect(onClient)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		pending[p] = nil
	end)
end

return ForgeService
