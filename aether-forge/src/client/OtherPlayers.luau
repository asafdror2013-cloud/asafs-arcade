--!nonstrict
-- OtherPlayers: animates other players' characters on this client. Their moves arrive as the
-- character attributes Act/ActT (set by the server), their locomotion comes from their velocity.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Moves = require(Shared.Moves)
local Rigs = require(Shared.Rigs)
local Clips = require(Shared.Clips)

local RigAnimator = require(script.Parent.RigAnimator)
local Clock = require(script.Parent.Clock)

local OtherPlayers = {}
local views = {} -- [character] = view

local function attach(player, char)
	task.spawn(function()
		local root = char:WaitForChild("HumanoidRootPart", 10)
		local weapon = char:WaitForChild("Weapon", 10)
		if not root or not weapon then
			return
		end
		local trail = Instance.new("Trail")
		trail.Attachment0 = weapon:WaitForChild("TrailBase")
		trail.Attachment1 = weapon:WaitForChild("TrailTip")
		trail.Lifetime = 0.13
		trail.FaceCamera = false
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), Config.Palette.Aether)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Enabled = false
		trail.Parent = weapon
		views[char] = {
			player = player,
			char = char,
			root = root,
			trail = trail,
			anim = RigAnimator.new(char, Rigs.Player, Clips.Player),
			act = nil,
			actT = 0,
		}
	end)
end

local function onPlayer(player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(function(char)
		attach(player, char)
	end)
	if player.Character then
		attach(player, player.Character)
	end
end

function OtherPlayers.hurt(player)
	for _, v in views do
		if v.player == player then
			v.anim:play("Hurt", { fadeIn = 0 })
		end
	end
end

function OtherPlayers.update(_dt, simDt)
	local now = Clock.server()
	for char, v in views do
		if not char.Parent or not v.root.Parent then
			views[char] = nil
			continue
		end
		local act = char:GetAttribute("Act")
		local actT = char:GetAttribute("ActT") or 0
		if act and actT ~= v.actT then
			v.actT = actT
			v.act = act
			local move = Moves[act]
			if move and move.clip then
				v.anim:play(move.clip, { fadeIn = 0.03, startAt = math.clamp(now - actT, 0, 0.2) })
			end
		end
		local move = v.act and Moves[v.act]
		local t = now - v.actT
		v.trail.Enabled = move ~= nil and move.trail ~= nil and t >= move.trail[1] and t <= move.trail[2]
		local vel = v.root.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local speed = flat.Magnitude
		local moveLocal = if speed > 0.5 then v.root.CFrame:VectorToObjectSpace(flat / speed) else Vector3.new(0, 0, -1)
		v.anim:update(simDt, { speed = speed, moveLocal = Vector3.new(moveLocal.X, 0, moveLocal.Z) })
	end
end

function OtherPlayers.init()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return OtherPlayers
