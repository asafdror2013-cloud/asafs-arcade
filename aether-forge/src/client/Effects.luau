--!nonstrict
-- Effects: client-side VFX, all local (nothing here replicates). Everything animates in Effects.update
-- with real time, so impacts keep sparking through hitstop freezes.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)

local Effects = {}

local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local folder, anchor, overlayGui, flashFrame, vignette, pulse
local active = {}

local function add(fn)
	table.insert(active, fn)
end

local function newPart(shape, size, color, material)
	local p
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end
Effects.newPart = newPart

local function frameAlong(pos, up)
	up = up.Unit
	local ref = if math.abs(up.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local right = ref:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up)
end

local function ns(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- Particle burst. props override the defaults below.
local function burst(pos, dir, count, props)
	local att = Instance.new("Attachment")
	att.CFrame = frameAlong(pos, dir or Vector3.yAxis)
	att.Parent = anchor
	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	pe.Texture = SPARK_TEX
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.EmissionDirection = Enum.NormalId.Top
	for k, v in props do
		pe[k] = v
	end
	pe.Parent = att
	pe:Emit(count)
	Debris:AddItem(att, 2)
	return pe
end
Effects.burst = burst

function Effects.sparks(pos, dir, color, count, speed)
	burst(pos, dir, count or 14, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Size = ns(0.45, 0),
		Speed = NumberRange.new((speed or 1) * 22, (speed or 1) * 52),
		SpreadAngle = Vector2.new(60, 60),
		Lifetime = NumberRange.new(0.12, 0.32),
		Drag = 7,
		Acceleration = Vector3.new(0, -45, 0),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Brightness = 4,
	})
end

function Effects.dust(pos, count, color, size)
	burst(pos, Vector3.yAxis, count or 10, {
		Texture = SMOKE_TEX,
		Color = ColorSequence.new(color or Color3.fromRGB(120, 110, 130)),
		LightEmission = 0,
		LightInfluence = 1,
		Size = ns(size or 1.2, (size or 1.2) * 3),
		Transparency = ns(0.35, 1),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(90, 10),
		Lifetime = NumberRange.new(0.35, 0.7),
		Drag = 5,
		RotSpeed = NumberRange.new(-90, 90),
		Rotation = NumberRange.new(0, 360),
	})
end

-- Bright expanding ball that fades fast: the core of every impact.
function Effects.flash(pos, color, size, duration)
	local p = newPart("Ball", Vector3.one * size * 0.3, color)
	p.CFrame = CFrame.new(pos)
	local t, T = 0, duration or 0.12
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		local s = size * (0.3 + 0.9 * (1 - (1 - k) ^ 3))
		p.Size = Vector3.one * s
		p.Transparency = k * k
		if k >= 1 then
			p:Destroy()
			return false
		end
		return true
	end)
end

-- A thin bright line across the target, like the blade's cut hanging in the air.
function Effects.cutLine(pos, across, color, length, duration)
	across = Vector3.new(across.X, across.Y, across.Z)
	if across.Magnitude < 1e-3 then
		across = Vector3.xAxis
	end
	local p = newPart("Block", Vector3.new(0.18, 0.18, 0.1), color)
	local base = CFrame.lookAt(pos, pos + across.Unit)
	local t, T = 0, duration or 0.16
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		local grow = math.clamp(k / 0.3, 0, 1)
		local thick = 0.32 * (1 - k)
		p.Size = Vector3.new(thick + 0.02, thick + 0.02, (length or 6) * (0.4 + 0.6 * grow))
		p.CFrame = base
		p.Transparency = k ^ 2
		if k >= 1 then
			p:Destroy()
			return false
		end
		return true
	end)
end

-- Expanding ring of neon segments on the floor + radial cracks (Heavy Slam, parries, deaths).
function Effects.shockwave(pos, radius, color, duration, cracks)
	local n = 28
	local segs = {}
	for i = 1, n do
		segs[i] = newPart("Block", Vector3.new(1, 0.25, 0.6), color)
	end
	local disc = newPart("Cylinder", Vector3.new(0.15, 1, 1), color)
	local t, T = 0, duration or 0.38
	local floorY = pos.Y
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		local e = 1 - (1 - k) ^ 3
		local r = 1 + (radius - 1) * e
		local segLen = 2 * math.pi * r / n * 1.08
		for i, s in segs do
			local a = (i / n) * math.pi * 2
			local p = Vector3.new(pos.X + math.sin(a) * r, floorY + 0.25, pos.Z + math.cos(a) * r)
			s.Size = Vector3.new(segLen, 0.3 * (1 - k) + 0.05, 0.9 * (1 - k) + 0.1)
			s.CFrame = CFrame.new(p) * CFrame.Angles(0, a, 0)
			s.Transparency = k ^ 1.5
		end
		local dr = r * 0.9
		disc.Size = Vector3.new(0.12, dr * 2, dr * 2)
		disc.CFrame = CFrame.new(pos.X, floorY + 0.1, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Transparency = 0.55 + 0.45 * k
		if k >= 1 then
			for _, s in segs do
				s:Destroy()
			end
			disc:Destroy()
			return false
		end
		return true
	end)
	if cracks then
		for i = 1, cracks do
			local a = (i / cracks) * math.pi * 2 + math.random() * 0.5
			local len = radius * (0.35 + math.random() * 0.35)
			local dir = Vector3.new(math.sin(a), 0, math.cos(a))
			local c = newPart("Block", Vector3.new(0.25, 0.12, len), color)
			c.CFrame = CFrame.lookAt(pos + dir * (len / 2 + 0.6) + Vector3.new(0, 0.12, 0), pos + dir * (len + 1) + Vector3.new(0, 0.12, 0))
			local ct = 0
			add(function(dt)
				ct += dt
				local k = math.clamp(ct / 1.1, 0, 1)
				c.Transparency = k ^ 2
				if k >= 1 then
					c:Destroy()
					return false
				end
				return true
			end)
		end
	end
end

-- Ghost copy of a character's current pose (dash afterimages).
function Effects.afterimage(model, color, duration)
	local ghosts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d.Name ~= "HumanoidRootPart" then
			local g = d:Clone()
			g:ClearAllChildren()
			g.Anchored = true
			g.CanCollide = false
			g.CanQuery = false
			g.CanTouch = false
			g.CastShadow = false
			g.Material = Enum.Material.Neon
			g.Color = color
			g.Transparency = 0.5
			g.CollisionGroup = "Fx"
			g.Parent = folder
			table.insert(ghosts, g)
		end
	end
	local t, T = 0, duration or 0.28
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		for _, g in ghosts do
			g.Transparency = 0.5 + 0.5 * k
		end
		if k >= 1 then
			for _, g in ghosts do
				g:Destroy()
			end
			return false
		end
		return true
	end)
end

-- Floating damage number.
function Effects.number(pos, text, color, big)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(160, 60)
	bb.StudsOffsetWorldSpace = pos
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.15
	label.TextSize = 1
	label.Parent = bb
	bb.Parent = folder
	local base = if big then 38 else 26
	local drift = Vector3.new((math.random() - 0.5) * 2, 0, 0)
	local t, T = 0, 0.8
	add(function(dt)
		t += dt
		local k = t / T
		local pop = if t < 0.08 then t / 0.08 * 1.6 else 1.6 - math.min(1, (t - 0.08) / 0.12) * 0.6
		label.TextSize = base * pop
		bb.StudsOffsetWorldSpace = pos + Vector3.new(0, 1.5 + t * 3, 0) + drift * t
		label.TextTransparency = math.clamp((k - 0.6) / 0.4, 0, 1)
		label.TextStrokeTransparency = 0.15 + 0.85 * math.clamp((k - 0.6) / 0.4, 0, 1)
		if k >= 1 then
			bb:Destroy()
			return false
		end
		return true
	end)
end

-- Big text that pops at a world position (PARRY!, RING OUT!).
function Effects.callout(pos, text, color)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(320, 80)
	bb.StudsOffsetWorldSpace = pos + Vector3.new(0, 7, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextSize = 1
	label.Rotation = -6
	label.Parent = bb
	bb.Parent = folder
	local t = 0
	add(function(dt)
		t += dt
		local pop = if t < 0.1 then t / 0.1 * 1.3 else math.max(1, 1.3 - (t - 0.1) * 3)
		label.TextSize = 48 * pop
		bb.StudsOffsetWorldSpace = pos + Vector3.new(0, 7 + t * 1.5, 0)
		local fade = math.clamp((t - 0.7) / 0.3, 0, 1)
		label.TextTransparency = fade
		label.TextStrokeTransparency = fade
		if t >= 1 then
			bb:Destroy()
			return false
		end
		return true
	end)
end

-- Full-screen flash.
function Effects.screenFlash(color, startTransparency, duration)
	flashFrame.BackgroundColor3 = color
	local t, T = 0, duration or 0.15
	local s = startTransparency or 0.5
	flashFrame.BackgroundTransparency = s
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		flashFrame.BackgroundTransparency = s + (1 - s) * k
		return k < 1
	end)
end

-- Red edges when you get hit.
function Effects.vignette(color, strength, duration)
	local t, T = 0, duration or 0.5
	for _, f in vignette do
		f.BackgroundColor3 = color
	end
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		local a = 1 - strength * (1 - k)
		for _, f in vignette do
			f.BackgroundTransparency = a
		end
		return k < 1
	end)
end

-- Brief color grade change (parry desaturates the world, heavy hits punch the contrast).
function Effects.grade(saturation, contrast, brightness, duration)
	local t, T = 0, duration or 0.3
	add(function(dt)
		t += dt
		local k = math.clamp(t / T, 0, 1)
		local w = (1 - k) ^ 2
		pulse.Saturation = saturation * w
		pulse.Contrast = contrast * w
		pulse.Brightness = brightness * w
		return k < 1
	end)
end

-- Chunks that fly out and bounce (enemy shatter, crystal break).
function Effects.debris(pos, colors, count, size, speed, material)
	for _ = 1, count do
		local s = size * (0.5 + math.random() * 0.8)
		local color = colors[math.random(1, #colors)]
		local p = newPart(if math.random() < 0.4 then "Wedge" else "Block", Vector3.new(s, s * (0.6 + math.random() * 0.8), s), color, material)
		p.CastShadow = true
		local dir = Vector3.new(math.random() - 0.5, 0.6 + math.random() * 0.8, math.random() - 0.5).Unit
		local vel = dir * speed * (0.5 + math.random() * 0.7)
		local rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		local cpos = pos + Vector3.new(math.random() - 0.5, math.random() * 2, math.random() - 0.5) * 2
		local life, maxLife = 0, 1.2 + math.random() * 0.8
		add(function(dt)
			life += dt
			vel += Vector3.new(0, -workspace.Gravity * 0.5, 0) * dt
			cpos += vel * dt
			if cpos.Y < s * 0.5 and cpos.Magnitude < Config.Arena.Radius then
				cpos = Vector3.new(cpos.X, s * 0.5, cpos.Z)
				vel = Vector3.new(vel.X * 0.6, math.abs(vel.Y) * 0.3, vel.Z * 0.6)
				spin *= 0.6
			end
			rot = rot * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			p.CFrame = CFrame.new(cpos) * rot
			local k = math.clamp((life - maxLife * 0.6) / (maxLife * 0.4), 0, 1)
			p.Transparency = k
			if life >= maxLife then
				p:Destroy()
				return false
			end
			return true
		end)
	end
end

-- Ore shards that arc out of a broken crystal and home into a character.
function Effects.oreFly(from, getTarget, color, count, onArrive)
	for i = 1, count do
		local p = newPart("Block", Vector3.new(0.5, 0.5, 0.5), color)
		local pos = from + Vector3.new(0, 2, 0)
		local vel = Vector3.new(math.random() - 0.5, 1.4, math.random() - 0.5).Unit * (26 + math.random() * 10)
		local t = -i * 0.04
		local done = false
		add(function(dt)
			t += dt
			if t < 0 then
				p.Transparency = 1
				return true
			end
			p.Transparency = 0
			local target = getTarget()
			if not target then
				p:Destroy()
				return false
			end
			local to = target - pos
			local pull = math.clamp(t * 3, 0, 1)
			vel = vel:Lerp(to.Unit * math.max(45, to.Magnitude * 6), pull * math.clamp(dt * 8, 0, 1))
			vel += Vector3.new(0, -60, 0) * dt * (1 - pull)
			pos += vel * dt
			p.CFrame = CFrame.new(pos) * CFrame.Angles(t * 9, t * 7, 0)
			if (to.Magnitude < 1.8 and t > 0.15) or t > 2.5 then
				if not done then
					done = true
					if onArrive then
						onArrive()
					end
				end
				p:Destroy()
				return false
			end
			return true
		end)
	end
end

-- Two wedges that form any triangle (used for the ground telegraphs).
function Effects.triangle(a, b, c, w1, w2, thickness)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab)
	if right.Magnitude < 1e-6 then
		w1.Transparency, w2.Transparency = 1, 1
		return
	end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	thickness = thickness or 0.05
	w1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

function Effects.update(dt)
	for i = #active, 1, -1 do
		local ok, alive = pcall(active[i], dt)
		if not ok or not alive then
			table.remove(active, i)
		end
	end
end

function Effects.folder()
	return folder
end

function Effects.init()
	folder = Instance.new("Folder")
	folder.Name = "AF_FX"
	folder.Parent = workspace

	anchor = Instance.new("Part")
	anchor.Name = "FxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.identity
	anchor.Parent = folder

	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "AF_Overlay"
	overlayGui.IgnoreGuiInset = true
	overlayGui.ResetOnSpawn = false
	overlayGui.DisplayOrder = 5
	overlayGui.Parent = pg

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = overlayGui

	vignette = {}
	local edges = {
		{ UDim2.new(0.22, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.22, 0, 1, 0), UDim2.fromScale(0.78, 0), 180 },
		{ UDim2.new(1, 0, 0.25, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.25, 0), UDim2.fromScale(0, 0.75), 270 },
	}
	for _, e in edges do
		local f = Instance.new("Frame")
		f.Size = e[1]
		f.Position = e[2]
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Config.Palette.Danger
		f.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Rotation = e[3]
		g.Transparency = ns(0, 1)
		g.Parent = f
		f.Parent = overlayGui
		table.insert(vignette, f)
	end

	pulse = Instance.new("ColorCorrectionEffect")
	pulse.Name = "AF_Pulse"
	pulse.Parent = Lighting
end

return Effects
