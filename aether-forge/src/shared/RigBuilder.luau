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
		local wb = parts[rig.weaponBone]
		for _, d in opts.weapon.parts do
			local p = attach(wb, d, d.cf)
			p.Name = "Blade_Detail"
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailBase"
		a0.Position = opts.weapon.trailBase
		a0.Parent = wb
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailTip"
		a1.Position = opts.weapon.trailTip
		a1.Parent = wb
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
