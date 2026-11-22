--!nonstrict
-- ArenaBuilder: creates the floating arena Parts from ArenaLayout, sets up lighting and the
-- collision groups.

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local ArenaLayout = require(Shared.ArenaLayout)
local RigBuilder = require(Shared.RigBuilder)

local ArenaBuilder = {}

-- Collision groups used across the game.
--   Player        player characters
--   Enemy         enemy colliders (pass through players, each other and crystals; can fall off)
--   PlayerBarrier invisible ring that only stops players
--   Crystal       crystal nodes (block players, not enemies)
--   Fx            client-side debris (only touches the floor)
function ArenaBuilder.setupCollisionGroups()
	local groups = { "Player", "Enemy", "PlayerBarrier", "Crystal", "Fx" }
	for _, g in groups do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	local function set(a, b, v)
		PhysicsService:CollisionGroupSetCollidable(a, b, v)
	end
	set("Player", "Enemy", false)
	set("Player", "Player", false)
	set("Enemy", "Enemy", false)
	set("Enemy", "PlayerBarrier", false)
	set("Enemy", "Crystal", false)
	set("Fx", "Player", false)
	set("Fx", "Enemy", false)
	set("Fx", "Fx", false)
	set("Fx", "PlayerBarrier", false)
	set("Fx", "Crystal", false)
end

function ArenaBuilder.setupLighting()
	-- Lighting.Technology = Future is set in the place file (scripts cannot change it).
	Lighting.ClockTime = 0.2
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(28, 26, 44)
	Lighting.OutdoorAmbient = Color3.fromRGB(52, 50, 82)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.15

	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end

	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.36
	atmo.Offset = 0.25
	atmo.Color = Color3.fromRGB(96, 74, 150)
	atmo.Decay = Color3.fromRGB(34, 22, 70)
	atmo.Glare = 0.2
	atmo.Haze = 1.4
	atmo.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.75
	bloom.Size = 28
	bloom.Threshold = 1.15
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Contrast = 0.14
	cc.Saturation = 0.12
	cc.TintColor = Color3.fromRGB(255, 248, 246)
	cc.Parent = Lighting
end

local function buildPart(spec, parent)
	local p = RigBuilder.makePart(spec.shape, spec.size, spec.color, spec.material)
	p.Name = spec.name or "Part"
	p.CFrame = spec.cf
	p.Anchored = true
	p.CanCollide = spec.collide == true
	p.CanTouch = false
	if spec.transparency then
		p.Transparency = spec.transparency
	end
	if spec.castShadow == false then
		p.CastShadow = false
	end
	if spec.group then
		p.CollisionGroup = spec.group
	end
	if spec.light then
		RigBuilder.addLight(p, spec.light)
	end
	if spec.kind then
		p:SetAttribute("Kind", spec.kind)
	end
	p.Parent = parent
	return p
end

function ArenaBuilder.build()
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	for _, spec in ArenaLayout.build() do
		buildPart(spec, arena)
	end
	for _, spec in ArenaLayout.barrier() do
		buildPart(spec, arena)
	end
	arena.Parent = workspace

	for _, name in { "Enemies", "Crystals" } do
		if not workspace:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = workspace
		end
	end
	return arena
end

return ArenaBuilder
