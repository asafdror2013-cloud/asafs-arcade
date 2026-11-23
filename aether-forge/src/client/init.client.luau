--!nonstrict
-- Aether Forge client entry point: wires input, camera, combat, enemy views, effects, HUD and the
-- tuning panel into one frame loop, and turns server events into effects.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Clock = require(script.Clock)
local Sfx = require(script.Sfx)
local Effects = require(script.Effects)
local Input = require(script.Input)
local CameraRig = require(script.CameraRig)
local EnemyViews = require(script.EnemyViews)
local Combat = require(script.Combat)
local OtherPlayers = require(script.OtherPlayers)
local Hud = require(script.Hud)
local TuningPanel = require(script.TuningPanel)
local ForgeUI = require(script.ForgeUI)
local RunSummary = require(script.RunSummary)
local Upgrades = require(Shared.Upgrades)

local player = Players.LocalPlayer
local P = Config.Palette

Effects.init()
Sfx.preload()
Input.init(Clock)
EnemyViews.init()
Combat.init()
OtherPlayers.init()
Hud.init(Combat)
ForgeUI.init(Hud)
RunSummary.init()
TuningPanel.init(Combat)

Combat.hooks.onHits = function(_, total)
	Hud.combo(total)
end

CameraRig.init(function()
	local root = Combat.root()
	if not root or not root.Parent then
		return nil
	end
	local vel = root.AssemblyLinearVelocity
	local lead = Vector3.new(vel.X, 0, vel.Z) / math.max(Config.Player.WalkSpeed, 1)
	return root.Position - Vector3.new(0, 1.5, 0), lead
end)

------------------------------------------------------------------------ arena ambience
local spinners, cores, portals = {}, {}, {}
task.spawn(function()
	local arena = workspace:WaitForChild("Arena")
	local function scan(p)
		if p:IsA("BasePart") then
			local kind = p:GetAttribute("Kind")
			if kind == "Spin" then
				table.insert(spinners, { part = p, base = p.CFrame, speed = 0.6 + math.random() * 0.6 })
			elseif kind == "ForgeCore" then
				table.insert(cores, { part = p, base = p.CFrame })
			elseif kind == "Portal" then
				table.insert(portals, { part = p, base = p.Size })
			end
		end
	end
	for _, p in arena:GetChildren() do
		scan(p)
	end
	arena.ChildAdded:Connect(scan)
end)

local function updateAmbience()
	local t = Clock.real
	for _, s in spinners do
		s.part.CFrame = CFrame.new(s.base.Position + Vector3.new(0, math.sin(t * 1.2 + s.speed * 5) * 0.6, 0)) * CFrame.Angles(0, t * s.speed, 0) * s.base.Rotation
	end
	for _, c in cores do
		c.part.CFrame = CFrame.new(c.base.Position + Vector3.new(0, math.sin(t * 1.6) * 0.5, 0)) * CFrame.Angles(t * 0.7, t * 1.1, 0)
	end
	for i, p in portals do
		local s = 1 + 0.15 * math.sin(t * 3 + i)
		p.part.Size = Vector3.new(p.base.X, p.base.Y * s, p.base.Z * s)
	end
end

-- crystals grow in when they appear
task.spawn(function()
	local folder = workspace:WaitForChild("Crystals")
	folder.ChildAdded:Connect(function(model)
		if not model:IsA("Model") then
			return
		end
		task.defer(function()
			if not model.Parent then
				return
			end
			local ok = pcall(function()
				model:ScaleTo(0.15)
			end)
			if not ok then
				return
			end
			local t = 0
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				t += dt
				local k = math.clamp(t / 0.45, 0, 1)
				local e = 1 - (1 - k) ^ 3
				if model.Parent then
					pcall(function()
						model:ScaleTo(0.15 + 0.85 * e + math.sin(k * math.pi) * 0.12)
					end)
				end
				if k >= 1 or not model.Parent then
					conn:Disconnect()
					if model.Parent then
						pcall(function()
							model:ScaleTo(1)
						end)
					end
				end
			end)
		end)
	end)
end)

------------------------------------------------------------------------ server events
local function charRoot(p)
	local c = p and p.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

Net.Fx.OnClientEvent:Connect(function(kind, data)
	if kind == "CrystalBreak" then
		local pos = data.pos
		local color = data.color or P.Aether
		Effects.flash(pos, color, 7, 0.18)
		Effects.sparks(pos, Vector3.yAxis, color, 30, 1.2)
		Effects.debris(pos, { color }, 12, 0.7, 34)
		Effects.shockwave(Vector3.new(pos.X, 0, pos.Z), 7, color, 0.35)
		Sfx.play("CrystalBreak")
		local target = data.player
		Effects.oreFly(pos, function()
			local r = charRoot(target)
			return r and r.Position
		end, color, data.ore or 3, function()
			if target == player then
				Sfx.play("Ore")
				Hud.orePulse()
			end
		end)
	elseif kind == "EnemyDied" then
		if data.reason == "RingOut" then
			local p = data.pos
			local edge = Vector3.new(p.X, 0, p.Z)
			if edge.Magnitude > 1 then
				edge = edge.Unit * math.min(edge.Magnitude, Config.Arena.Radius - 4)
			end
			Effects.callout(edge, "RING OUT!", P.Ember)
		end
	elseif kind == "Parried" then
		if data.player ~= player and data.enemy and data.enemy.Parent then
			local root = data.enemy:FindFirstChild("Root")
			if root then
				Effects.sparks(root.Position + Vector3.new(0, 3, 0), Vector3.yAxis, P.Gold, 24, 1.2)
				Effects.flash(root.Position + Vector3.new(0, 3, 0), Color3.new(1, 1, 1), 5, 0.14)
				Sfx.play("Parry", 0.5)
			end
		end
	elseif kind == "Lightning" then
		for _, to in data.to do
			Effects.lightning(data.from, to, Upgrades.ElementColors.Storm, 0.24)
		end
		CameraRig.shake(0.18)
		Sfx.play("Parry", 0.35)
	elseif kind == "Shockwave" then
		local color = P.Aether
		local r = charRoot(data.player)
		if r and r.Parent and r.Parent:GetAttribute("WeaponGlow") then
			color = r.Parent:GetAttribute("WeaponGlow")
		end
		Effects.wave(data.origin, data.dir, data.speed, data.range, color)
		Sfx.play("SwingBig", 0.6)
	elseif kind == "Ember" then
		Effects.ember(data.points, data.duration)
	elseif kind == "Forged" then
		local anvil = Vector3.new(0, 4, 0)
		Effects.forgeBurst(anvil, Upgrades.ElementColors[data.element] or P.Aether)
		if data.player == player then
			CameraRig.shake(0.3)
			CameraRig.punch(-5)
		end
		Sfx.play("CrystalBreak")
	elseif kind == "PlayerHurt" then
		local r = charRoot(data.player)
		if r then
			Effects.number(r.Position + Vector3.new(0, 3, 0), "-" .. tostring(data.amount), P.Danger, false)
		end
		if data.player ~= player then
			OtherPlayers.hurt(data.player)
		end
	end
end)

Net.Run.OnClientEvent:Connect(function(kind, data)
	if kind == "Countdown" then
		Hud.banner("GET READY", "Smash crystals for ore. Parry on the flash.", P.Aether, 2.6)
	elseif kind == "Wave" then
		Hud.banner("WAVE " .. data.wave, data.count .. (if data.count == 1 then " Shard Brute" else " Shard Brutes"), Color3.new(1, 1, 1), 2)
		Sfx.play("Wave")
	elseif kind == "WaveCleared" then
		Hud.banner("WAVE CLEARED", "+15 HP  ·  the anvil is open (" .. data.breather .. "s)", P.Aether, 2.6)
	elseif kind == "Defeat" then
		Hud.banner("DEFEATED", "You reached wave " .. data.wave, P.Danger, 4.5)
	end
end)

------------------------------------------------------------------------ frame loop
RunService.PreSimulation:Connect(function(realDt)
	local simDt = Clock.step(realDt)
	Combat.update(realDt, simDt)
	EnemyViews.update(realDt, simDt, Combat.onStrike)
	OtherPlayers.update(realDt, simDt)
	Effects.update(realDt)
	updateAmbience()
	Hud.update(realDt)
	ForgeUI.update(realDt)
	RunSummary.update()
end)

print("[Aether Forge] client ready")
