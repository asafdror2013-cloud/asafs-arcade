--!nonstrict
-- EnemyViews: everything the player sees of an enemy. Animation follows the server's timestamped
-- states (so every client agrees on when a strike lands) and adds local feel on top:
--   * ground telegraph: the strike zone fills up as the windup runs out
--   * glint: a bright flash + ping right as the parry window opens (parry on the flash)
--   * hit flash + hitstop freeze + flinch when you hit it
--   * stun stars, HP bar, death shatter

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Rigs = require(Shared.Rigs)
local Clips = require(Shared.Clips)
local MathUtil = require(Shared.MathUtil)

local RigAnimator = require(script.Parent.RigAnimator)
local Effects = require(script.Parent.Effects)
local Sfx = require(script.Parent.Sfx)
local Clock = require(script.Parent.Clock)

local EnemyViews = {}
EnemyViews.views = {} -- [model] = view

local TELE_SLICES = 9
local MOLTEN = Config.Palette.Molten
local DANGER = Config.Palette.Danger

local function makeTelegraph()
	local tg = { fill = {}, edge = {} }
	for i = 1, TELE_SLICES * 2 do
		local w = Effects.newPart("Wedge", Vector3.new(0.05, 1, 1), DANGER, Enum.Material.Neon)
		w.Transparency = 1
		tg.fill[i] = w
	end
	for i = 1, TELE_SLICES + 2 do
		local b = Effects.newPart("Block", Vector3.new(0.3, 0.08, 1), MOLTEN, Enum.Material.Neon)
		b.Transparency = 1
		tg.edge[i] = b
	end
	return tg
end

local function hideTelegraph(tg)
	for _, p in tg.fill do
		p.Transparency = 1
	end
	for _, p in tg.edge do
		p.Transparency = 1
	end
end

local function destroyTelegraph(tg)
	for _, p in tg.fill do
		p:Destroy()
	end
	for _, p in tg.edge do
		p:Destroy()
	end
end

-- Draw the strike sector: outline at full range, fill growing with progress.
local function drawTelegraph(tg, origin, yaw, range, arc, progress, hot)
	local y = 0.22
	local center = Vector3.new(origin.X, y, origin.Z)
	local half = math.rad(arc / 2)
	local fillR = range * MathUtil.Ease.outQuad(math.clamp(progress, 0, 1))
	local fillColor = if hot then Color3.fromRGB(255, 230, 200) else DANGER
	local fillT = if hot then 0.35 else 0.62 - 0.2 * progress
	for i = 1, TELE_SLICES do
		local a0 = yaw - half + (i - 1) / TELE_SLICES * half * 2
		local a1 = yaw - half + i / TELE_SLICES * half * 2
		local p0 = center + MathUtil.dirFromYaw(a0) * fillR
		local p1 = center + MathUtil.dirFromYaw(a1) * fillR
		local w1, w2 = tg.fill[i * 2 - 1], tg.fill[i * 2]
		if fillR > 0.2 then
			Effects.triangle(center, p0, p1, w1, w2, 0.05)
			w1.Color, w2.Color = fillColor, fillColor
			w1.Transparency, w2.Transparency = fillT, fillT
		else
			w1.Transparency, w2.Transparency = 1, 1
		end
	end
	-- outline: arc segments + two side edges
	for i = 1, TELE_SLICES do
		local a0 = yaw - half + (i - 1) / TELE_SLICES * half * 2
		local a1 = yaw - half + i / TELE_SLICES * half * 2
		local p0 = center + MathUtil.dirFromYaw(a0) * range
		local p1 = center + MathUtil.dirFromYaw(a1) * range
		local b = tg.edge[i]
		b.Size = Vector3.new(0.3, 0.08, (p1 - p0).Magnitude + 0.25)
		b.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
		b.Transparency = 0.1
	end
	for k = 0, 1 do
		local a = yaw + (if k == 0 then -half else half)
		local p1 = center + MathUtil.dirFromYaw(a) * range
		local b = tg.edge[TELE_SLICES + 1 + k]
		b.Size = Vector3.new(0.3, 0.08, range)
		b.CFrame = CFrame.lookAt((center + p1) / 2, p1)
		b.Transparency = 0.25
	end
end

local function makeHpBar(root)
	local bb = Instance.new("BillboardGui")
	bb.Name = "AF_HP"
	bb.Adornee = root
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(90, 9)
	bb.StudsOffset = Vector3.new(0, 5.2, 0)
	bb.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 16, 24)
	back.BorderSizePixel = 0
	back.Parent = bb
	local trail = Instance.new("Frame")
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = Color3.new(1, 1, 1)
	trail.BorderSizePixel = 0
	trail.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = MOLTEN
	fill.BorderSizePixel = 0
	fill.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = back
	bb.Parent = Effects.folder()
	return { gui = bb, fill = fill, trail = trail, shown = 0, trailFrac = 1 }
end

local function newView(model)
	local root = model:WaitForChild("Root", 5)
	if not root then
		return nil
	end
	local kind = model:GetAttribute("Kind") or "Brute"
	local view = {
		model = model,
		root = root,
		kind = kind,
		cfg = Config.Enemy[kind],
		anim = RigAnimator.new(model, Rigs[kind], Clips[kind]),
		telegraph = makeTelegraph(),
		hp = makeHpBar(root),
		highlight = Instance.new("Highlight"),
		lastState = nil,
		glintFor = -1,
		reportedStrike = model:GetAttribute("StrikeId") or 0,
		freezeUntil = 0,
		flashUntil = 0,
		stars = nil,
		dead = false,
		parts = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(view.parts, d)
		end
	end
	local h = view.highlight
	h.Adornee = model
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	return view
end

local function makeStars()
	local stars = {}
	for i = 1, 3 do
		local s = Effects.newPart("Block", Vector3.new(0.5, 0.5, 0.5), Config.Palette.Gold)
		stars[i] = s
	end
	return stars
end

local function removeStars(view)
	if view.stars then
		for _, s in view.stars do
			s:Destroy()
		end
		view.stars = nil
	end
end

local function shatter(view)
	if view.dead then
		return
	end
	view.dead = true
	hideTelegraph(view.telegraph)
	removeStars(view)
	view.hp.gui.Enabled = false
	local pos = view.root.Position
	for _, p in view.parts do
		p.LocalTransparencyModifier = 1
	end
	view.highlight.Enabled = false
	Effects.flash(pos + Vector3.new(0, 3, 0), MOLTEN, 9, 0.2)
	Effects.debris(pos + Vector3.new(0, 2, 0), { Color3.fromRGB(42, 38, 48), Color3.fromRGB(78, 70, 78) }, 14, 1.3, 38, Enum.Material.Basalt)
	Effects.debris(pos + Vector3.new(0, 3, 0), { MOLTEN }, 8, 0.6, 46)
	Effects.sparks(pos + Vector3.new(0, 3, 0), Vector3.yAxis, MOLTEN, 30, 1.3)
	Effects.shockwave(Vector3.new(pos.X, 0, pos.Z), 10, MOLTEN, 0.4)
	Sfx.play("EnemyDie")
end

-- The local player's hit landed on this enemy: flash white, freeze, flinch.
function EnemyViews.onLocalHit(model, hitstop, dirWorld, damage, isBig)
	local view = EnemyViews.views[model]
	if not view or view.dead then
		return
	end
	view.flashUntil = Clock.real + 0.07
	view.freezeUntil = Clock.real + hitstop
	view.anim:freeze(true, if isBig then 0.35 else 0.18)
	local local_ = view.root.CFrame:VectorToObjectSpace(dirWorld)
	view.anim:addFlinch(Vector3.new(local_.X, 0, local_.Z), if isBig then 1.2 else 0.7)
	view.hp.shown = 3
	if damage then
		local pos = view.root.Position + Vector3.new(0, 4, 0)
		Effects.number(pos, tostring(math.floor(damage + 0.5)), if isBig then Config.Palette.Gold else Color3.new(1, 1, 1), isBig)
	end
end

local function updateView(view, dt, simDt, onStrike)
	local model = view.model
	if not model.Parent then
		return false
	end
	local state = model:GetAttribute("State")
	if state == "Dead" then
		shatter(view)
		return true
	end
	local now = Clock.server()
	local stateT = model:GetAttribute("StateT") or now
	local elapsed = now - stateT
	local cfg = view.cfg

	-- state entry
	if state ~= view.lastState then
		if view.lastState == "Stunned" then
			removeStars(view)
		end
		if state == "Stunned" then
			view.stars = makeStars()
		end
		if state == "Strike" then
			Effects.dust(Vector3.new(view.root.Position.X, 0.3, view.root.Position.Z) + MathUtil.dirFromYaw(MathUtil.yawFromDir(view.root.CFrame.LookVector)) * 4, 10)
		end
		if state ~= "Windup" then
			hideTelegraph(view.telegraph)
		end
		-- clip-driven states restart their own clip via setTime; everything else blends back
		view.anim:stop(0.1)
		view.lastState = state
	end

	-- hitstop freeze
	if view.freezeUntil > Clock.real then
		view.anim:update(0)
	else
		if view.anim.frozen then
			view.anim:freeze(false)
		end
		local vel = view.root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local loco = { speed = speed }
		if state == "Spawn" then
			view.anim:setTime("Spawn", elapsed / cfg.SpawnTime)
			view.anim:update(simDt, loco)
		elseif state == "Windup" then
			local strikeT = model:GetAttribute("StrikeT") or (stateT + 1)
			local dur = math.max(strikeT - stateT, 0.05)
			local u = math.clamp(elapsed / dur, 0, 1)
			view.anim:setTime("Windup", u)
			-- tremble harder as the strike approaches
			view.anim.lean = CFrame.new((math.random() - 0.5) * 0.12 * u, 0, (math.random() - 0.5) * 0.12 * u)
			view.anim:update(simDt, { speed = 0 })
			-- glint marks the parry timing: react to it and the parry lands in the window
			local strikeId = model:GetAttribute("StrikeId") or 0
			local glintAt = strikeT - Config.Feel.GlintLead
			local yaw = MathUtil.yawFromDir(view.root.CFrame.LookVector)
			drawTelegraph(view.telegraph, view.root.Position, yaw, cfg.AttackRange, cfg.AttackArc, u, now >= glintAt)
			if now >= glintAt and view.glintFor ~= strikeId then
				view.glintFor = strikeId
				local head = view.root.Position + Vector3.new(0, 6.5, 0) + view.root.CFrame.LookVector * -1.2
				Effects.flash(head, Color3.new(1, 1, 1), 3.2, 0.14)
				Effects.sparks(head, Vector3.yAxis, Config.Palette.Gold, 10, 0.6)
				Sfx.play("Glint")
			end
			-- strike time: the local player decides parry / dodge / hurt
			if now >= strikeT and view.reportedStrike ~= strikeId then
				view.reportedStrike = strikeId
				onStrike(view, strikeId)
			end
		elseif state == "Strike" then
			view.anim.lean = CFrame.identity
			view.anim:setTime("Strike", elapsed)
			view.anim:update(simDt, { speed = 0 })
			-- if our clock was behind and we never saw StrikeT pass inside Windup
			local strikeId = model:GetAttribute("StrikeId") or 0
			if view.reportedStrike ~= strikeId then
				view.reportedStrike = strikeId
				onStrike(view, strikeId)
			end
		elseif state == "Recover" then
			view.anim:setTime("Recover", elapsed)
			view.anim:update(simDt, { speed = 0 })
		elseif state == "Stunned" then
			view.anim:update(simDt, loco, Clips.Brute.stunned(Clock.real))
		else
			view.anim.lean = CFrame.identity
			view.anim:update(simDt, loco)
		end
	end

	-- stun stars orbit the head
	if view.stars then
		local head = view.root.Position + Vector3.new(0, 7.2, 0)
		for i, s in view.stars do
			local a = Clock.real * 5 + i * math.pi * 2 / 3
			s.CFrame = CFrame.new(head + Vector3.new(math.cos(a) * 1.8, math.sin(a * 2) * 0.2, math.sin(a) * 1.8)) * CFrame.Angles(a, a, 0)
		end
	end

	-- highlight: white hit flash > windup glow > stun shimmer
	local h = view.highlight
	if Clock.real < view.flashUntil then
		h.FillColor = Color3.new(1, 1, 1)
		h.FillTransparency = 0.05
		h.OutlineTransparency = 1
	elseif state == "Windup" then
		local strikeT = model:GetAttribute("StrikeT") or now
		local u = math.clamp(1 - (strikeT - now) / 0.8, 0, 1)
		h.FillColor = MOLTEN
		h.OutlineColor = Color3.fromRGB(255, 200, 120)
		h.FillTransparency = 1 - 0.45 * u
		h.OutlineTransparency = 0.2
	elseif state == "Stunned" then
		h.FillColor = Config.Palette.Gold
		h.OutlineColor = Config.Palette.Gold
		h.FillTransparency = 0.75 + 0.15 * math.sin(Clock.real * 12)
		h.OutlineTransparency = 0.3
	else
		h.FillTransparency = 1
		h.OutlineTransparency = 1
	end

	-- HP bar
	local hp, maxHp = model:GetAttribute("HP") or 1, model:GetAttribute("MaxHP") or 1
	local frac = math.clamp(hp / maxHp, 0, 1)
	view.hp.shown -= dt
	view.hp.gui.Enabled = view.hp.shown > 0 or frac < 1
	view.hp.fill.Size = UDim2.fromScale(frac, 1)
	view.hp.trailFrac = MathUtil.damp(view.hp.trailFrac, frac, 5, dt)
	view.hp.trail.Size = UDim2.fromScale(view.hp.trailFrac, 1)
	return true
end

function EnemyViews.update(dt, simDt, onStrike)
	for model, view in EnemyViews.views do
		local ok, alive = pcall(updateView, view, dt, simDt, onStrike)
		if not ok then
			warn("[Aether Forge] enemy view error: ", alive)
		end
		if not ok or not alive then
			destroyTelegraph(view.telegraph)
			removeStars(view)
			view.hp.gui:Destroy()
			EnemyViews.views[model] = nil
		end
	end
end

-- Enemies close to the player (used for aim assist, soft collision and hit detection).
function EnemyViews.alive()
	local list = {}
	for model, view in EnemyViews.views do
		if not view.dead and model.Parent and model:GetAttribute("State") ~= "Dead" then
			table.insert(list, view)
		end
	end
	return list
end

function EnemyViews.init()
	local folder = workspace:WaitForChild("Enemies")
	local function add(model)
		task.spawn(function()
			local view = newView(model)
			if view then
				EnemyViews.views[model] = view
			end
		end)
	end
	folder.ChildAdded:Connect(add)
	for _, m in folder:GetChildren() do
		add(m)
	end
end

return EnemyViews
