--!nonstrict
-- RigBuilder: turns a rig definition from Rigs.luau into real Parts, Motor6Ds and welds.
-- Used by the server (player StarterCharacter, Brutes) and by the client (afterimage ghosts).

local Rigs = require(script.Parent.Rigs)

local RigBuilder = {}

local function makePart(shape, size, color, material)
	local p
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		p = Instance.new("CornerWedgePart")
	else
		p = Instance.new("Part")
		if shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
	end
	p.Size = size
	p.Color = color or Color3.new(1, 1, 1)
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end
RigBuilder.makePart = makePart

local function addLight(part, light)
	local l = Instance.new("PointLight")
	l.Color = light.color
	l.Range = light.range or 8
	l.Brightness = light.brightness or 1
	l.Shadows = false
	l.Parent = part
	return l
end
RigBuilder.addLight = addLight

-- Builds the model at the origin (feet on y = 0, facing -Z).
-- opts = { name, weapon = weaponDef?, collisionGroup = string? }
-- Returns model, { parts = {[name] = BasePart}, motors = {[jointName] = Motor6D} }
function RigBuilder.build(rig, opts)
	opts = opts or {}
	local joints, rest = Rigs.computeJoints(rig)
	local model = Instance.new("Model")
	model.Name = opts.name or "Rig"

	local parts = {}
	local root = makePart("Block", rig.root.size, Color3.new(1, 1, 1), "SmoothPlastic")
	root.Name = rig.root.name
	root.Transparency = 1
	root.CFrame = rest[rig.root.name]
	root.CanCollide = true
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	parts[rig.root.name] = root

	for _, b in rig.bones do
		local p = makePart(b.shape or "Block", b.size, b.color, b.material)
		p.Name = b.name
		p.CFrame = rest[b.name]
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		if b.invisible then
			p.Transparency = 1
			p.CastShadow = false
		end
		p.Parent = model
		parts[b.name] = p
	end

	local motors = {}
	for name, j in joints do
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parts[j.part0]
		m.Part1 = parts[j.part1]
		m.C0 = j.c0
		m.C1 = j.c1
		m.Parent = parts[j.part1]
		motors[name] = m
	end

	local function attach(bone, d, offset)
		local p = makePart(d.shape, d.size, d.color, d.material)
		p.Name = bone.Name .. "_Detail"
		p.CFrame = bone.CFrame * offset
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		if d.material == "Neon" then
			p.CastShadow = false
		end
		local w = Instance.new("Weld")
		w.Part0 = bone
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
		p.Parent = model
		if d.light then
			addLight(p, d.light)
		end
		return p
	end

	for _, d in rig.decor do
		attach(parts[d.bone], d, Rigs.decorOffset(rest, d))
	end

	if opts.weapon and rig.weaponBone then
		RigBuilder.attachWeapon(model, rig, opts.weapon)
	end

	if opts.collisionGroup then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = opts.collisionGroup
			end
		end
	end

	model.PrimaryPart = root
	return model, { parts = parts, motors = motors }
end

local FX = {
	Fire = { texture = "rbxasset://textures/particles/fire_main.dds", color = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 80, 20) }, rate = 26, size = { 0.7, 0.1 }, speed = { 1, 3 }, life = { 0.25, 0.5 }, accel = Vector3.new(0, 6, 0), emission = 1 },
	Storm = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 120, 255) }, rate = 14, size = { 0.35, 0 }, speed = { 3, 7 }, life = { 0.08, 0.2 }, accel = Vector3.new(0, 0, 0), emission = 1 },
	Frost = { texture = "rbxasset://textures/particles/smoke_main.dds", color = { Color3.fromRGB(230, 245, 255), Color3.fromRGB(150, 220, 255) }, rate = 10, size = { 0.5, 1.4 }, speed = { 0.3, 1 }, life = { 0.6, 1.1 }, accel = Vector3.new(0, -1, 0), emission = 0.3 },
}

-- Put a weapon on a rig's weapon bone, replacing whatever blade was there.
-- Keeps the TrailBase/TrailTip attachments (moved to the new blade) so client trails keep working.
function RigBuilder.attachWeapon(model, rig, weapon)
	local wb = model:FindFirstChild(rig.weaponBone)
	if not wb then
		return
	end
	for _, d in model:GetChildren() do
		if d.Name == "Blade_Detail" then
			d:Destroy()
		end
	end
	local longest, longestLen = nil, 0
	for _, d in weapon.parts do
		local p = makePart(d.shape, d.size, d.color, d.material)
		p.Name = "Blade_Detail"
		p.CFrame = wb.CFrame * d.cf
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.CollisionGroup = wb.CollisionGroup
		if d.transparency then
			p.Transparency = d.transparency
		end
		if d.material == "Neon" then
			p.CastShadow = false
		end
		local w = Instance.new("Weld")
		w.Part0 = wb
		w.Part1 = p
		w.C0 = d.cf
		w.Parent = p
		p.Parent = model
		if d.size.Z > longestLen and d.cf.Position.Z < -1 then
			longest, longestLen = p, d.size.Z
		end
	end
	local a0 = wb:FindFirstChild("TrailBase") or Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = weapon.trailBase
	a0.Parent = wb
	local a1 = wb:FindFirstChild("TrailTip") or Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = weapon.trailTip
	a1.Parent = wb
	local fx = weapon.fx and FX[weapon.fx]
	if fx and longest then
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "WeaponFx"
		pe.Texture = fx.texture
		pe.Color = ColorSequence.new(fx.color[1], fx.color[2])
		pe.Rate = fx.rate
		pe.Size = NumberSequence.new(fx.size[1], fx.size[2])
		pe.Speed = NumberRange.new(fx.speed[1], fx.speed[2])
		pe.Lifetime = NumberRange.new(fx.life[1], fx.life[2])
		pe.Acceleration = fx.accel
		pe.LightEmission = fx.emission
		pe.LightInfluence = 0
		pe.Transparency = NumberSequence.new(0.2, 1)
		pe.SpreadAngle = Vector2.new(30, 30)
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.Parent = longest
	end
	model:SetAttribute("WeaponGlow", weapon.glow)
end

-- Collect Motor6Ds of an existing model by joint name.
function RigBuilder.findMotors(model)
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return motors
end

return RigBuilder
