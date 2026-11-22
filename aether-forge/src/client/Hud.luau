--!nonstrict
-- Hud: HP bar (with a trailing damage bar), riposte badge, dash meter, ore counter, wave info,
-- combo counter, big center banners and the controls hint (H toggles it).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local MathUtil = require(Shared.MathUtil)

local Clock = require(script.Parent.Clock)

local Hud = {}

local player = Players.LocalPlayer
local P = Config.Palette

local gui
local hpFill, hpTrail, hpText, hpTrailFrac = nil, nil, nil, 1
local riposte, riposteBar
local dashFill
local oreText, oreIcon, orePop = nil, nil, 0
local waveText, waveSub
local comboNum, comboLabel, comboPop, comboShown = nil, nil, 0, 0
local banner, bannerSub, bannerT, bannerDur = nil, nil, 99, 2
local hint
local combat

local function label(parent, text, size, font, color, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	if props then
		for k, v in props do
			l[k] = v
		end
	end
	l.Parent = parent
	return l
end

local function stroke(inst, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1.5
	s.Color = color or Color3.new(0, 0, 0)
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = inst
	return c
end

local function frame(parent, size, pos, color, transparency)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundColor3 = color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AF_Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- HP block (top-left)
	local hpBox = frame(gui, UDim2.fromOffset(300, 62), UDim2.fromOffset(18, 14), Color3.new(0, 0, 0), 1)
	label(hpBox, "WARRIOR-SMITH", 12, Enum.Font.GothamBlack, Color3.fromRGB(200, 210, 230), {
		Size = UDim2.fromOffset(200, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local hpBack = frame(hpBox, UDim2.fromOffset(300, 18), UDim2.fromOffset(0, 18), Color3.fromRGB(16, 14, 24), 0.15)
	corner(hpBack, 4)
	stroke(hpBack, 1.5, Color3.fromRGB(120, 130, 160), 0.4)
	hpTrail = frame(hpBack, UDim2.fromScale(1, 1), nil, Color3.new(1, 1, 1), 0.1)
	corner(hpTrail, 4)
	hpFill = frame(hpBack, UDim2.fromScale(1, 1), nil, P.Aether)
	corner(hpFill, 4)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(110, 255, 220), P.AetherDeep)
	grad.Parent = hpFill
	hpText = label(hpBack, "100 / 100", 13, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = hpText
	stroke(hpText, 1.2)

	-- dash meter
	local dashBack = frame(hpBox, UDim2.fromOffset(120, 5), UDim2.fromOffset(0, 42), Color3.fromRGB(16, 14, 24), 0.2)
	corner(dashBack, 2)
	dashFill = frame(dashBack, UDim2.fromScale(1, 1), nil, Color3.fromRGB(220, 240, 255))
	corner(dashFill, 2)
	label(hpBox, "DASH", 10, Enum.Font.GothamBlack, Color3.fromRGB(170, 180, 200), {
		Size = UDim2.fromOffset(40, 10),
		Position = UDim2.fromOffset(126, 39),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- riposte badge
	riposte = frame(gui, UDim2.fromOffset(170, 26), UDim2.fromOffset(18, 70), P.Gold, 0.15)
	corner(riposte, 4)
	label(riposte, "RIPOSTE  x" .. Config.Player.RiposteDamageMult, 14, Enum.Font.GothamBlack, Color3.fromRGB(40, 26, 6), {
		Size = UDim2.fromScale(1, 1),
	})
	riposteBar = frame(riposte, UDim2.new(1, 0, 0, 3), UDim2.new(0, 0, 1, -3), Color3.new(1, 1, 1))
	riposte.Visible = false

	-- ore (top-right)
	local oreBox = frame(gui, UDim2.fromOffset(170, 48), UDim2.new(1, -188, 0, 12), Color3.new(0, 0, 0), 1)
	oreIcon = frame(oreBox, UDim2.fromOffset(22, 22), UDim2.fromOffset(14, 12), P.Aether)
	oreIcon.Rotation = 45
	stroke(oreIcon, 2, Color3.fromRGB(10, 40, 60))
	oreText = label(oreBox, "0", 34, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.fromOffset(90, 40),
		Position = UDim2.fromOffset(46, 2),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	stroke(oreText, 2)
	label(oreBox, "ORE", 12, Enum.Font.GothamBlack, Color3.fromRGB(150, 220, 240), {
		Size = UDim2.fromOffset(40, 12),
		Position = UDim2.fromOffset(122, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- wave (top-center)
	waveText = label(gui, "", 28, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.fromOffset(300, 32),
		Position = UDim2.new(0.5, -150, 0, 8),
	})
	stroke(waveText, 2)
	waveSub = label(gui, "", 14, Enum.Font.GothamBold, Color3.fromRGB(200, 205, 225), {
		Size = UDim2.fromOffset(300, 18),
		Position = UDim2.new(0.5, -150, 0, 40),
	})
	stroke(waveSub, 1.5)

	-- combo (right-center)
	comboNum = label(gui, "", 64, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.fromOffset(200, 70),
		Position = UDim2.new(1, -230, 0.38, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	stroke(comboNum, 3)
	comboLabel = label(gui, "HIT COMBO", 16, Enum.Font.GothamBlack, P.Aether, {
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.new(1, -230, 0.38, 66),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	stroke(comboLabel, 2)

	-- banner (center)
	banner = label(gui, "", 72, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.new(0, 0, 0.26, 0),
		TextTransparency = 1,
	})
	stroke(banner, 4, Color3.new(0, 0, 0), 1)
	bannerSub = label(gui, "", 22, Enum.Font.GothamBold, Color3.fromRGB(220, 225, 240), {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0.26, 88),
		TextTransparency = 1,
	})
	stroke(bannerSub, 2, Color3.new(0, 0, 0), 1)

	-- controls hint (bottom-left)
	hint = frame(gui, UDim2.fromOffset(250, 126), UDim2.new(0, 18, 1, -146), Color3.fromRGB(10, 10, 18), 0.35)
	corner(hint, 6)
	local lines = {
		{ "LMB", "Slash combo (3 hits)" },
		{ "RMB", "Heavy Slam" },
		{ "SPACE / SHIFT", "Dash (i-frames)" },
		{ "F", "Parry (on the flash)" },
		{ "WHEEL", "Zoom" },
		{ "H", "Hide this" },
	}
	for i, l in lines do
		label(hint, l[1], 12, Enum.Font.GothamBlack, P.Aether, {
			Size = UDim2.fromOffset(100, 18),
			Position = UDim2.fromOffset(10, 6 + (i - 1) * 19),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(hint, l[2], 12, Enum.Font.GothamBold, Color3.fromRGB(215, 220, 235), {
			Size = UDim2.fromOffset(140, 18),
			Position = UDim2.fromOffset(108, 6 + (i - 1) * 19),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	hint.Visible = not UserInputService.TouchEnabled
end

function Hud.banner(text, sub, color, duration)
	banner.Text = text
	banner.TextColor3 = color or Color3.new(1, 1, 1)
	bannerSub.Text = sub or ""
	bannerT = 0
	bannerDur = duration or 2.2
end

function Hud.combo(count)
	if count > 0 then
		comboShown = 2.4
		comboPop = 1
		comboNum.Text = tostring(count)
		comboLabel.Text = if count >= 10 then "BRUTAL COMBO" elseif count >= 5 then "HIT COMBO" else "HITS"
	end
end

function Hud.orePulse()
	orePop = 1
end

function Hud.update(dt)
	if not gui then
		return
	end
	-- HP
	local hp = player:GetAttribute("HP") or 0
	local maxHp = player:GetAttribute("MaxHP") or Config.Player.MaxHP
	local frac = math.clamp(hp / maxHp, 0, 1)
	hpFill.Size = UDim2.fromScale(frac, 1)
	if hpTrailFrac < frac then
		hpTrailFrac = frac
	else
		hpTrailFrac = MathUtil.damp(hpTrailFrac, frac, 3.5, dt)
	end
	hpTrail.Size = UDim2.fromScale(hpTrailFrac, 1)
	hpText.Text = string.format("%d / %d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))
	if frac < 0.3 then
		hpFill.BackgroundColor3 = P.Danger:Lerp(Color3.new(1, 1, 1), 0.3 + 0.3 * math.sin(Clock.real * 10))
		hpFill:FindFirstChildOfClass("UIGradient").Enabled = false
	else
		hpFill:FindFirstChildOfClass("UIGradient").Enabled = true
		hpFill.BackgroundColor3 = Color3.new(1, 1, 1)
	end

	-- riposte + dash
	if combat then
		local left = combat.riposteUntil() - Clock.server()
		riposte.Visible = left > 0
		if left > 0 then
			riposteBar.Size = UDim2.new(math.clamp(left / Config.Player.RiposteDuration, 0, 1), 0, 0, 3)
		end
		local d = combat.dashReady()
		dashFill.Size = UDim2.fromScale(d, 1)
		dashFill.BackgroundColor3 = if d >= 1 then Color3.fromRGB(220, 240, 255) else Color3.fromRGB(90, 100, 130)
	end

	-- ore
	oreText.Text = tostring(player:GetAttribute("Ore") or 0)
	orePop = math.max(0, orePop - dt * 4)
	oreText.TextSize = 34 * (1 + 0.35 * orePop)
	oreIcon.Rotation = 45 + orePop * 90

	-- wave info
	local wave = workspace:GetAttribute("Wave") or 0
	local phase = workspace:GetAttribute("Phase")
	local ends = workspace:GetAttribute("PhaseEnds") or 0
	local left = math.max(0, math.ceil(ends - Clock.server()))
	waveText.Text = if wave > 0 then "WAVE " .. wave else "AETHER FORGE"
	if workspace:GetAttribute("WavesPaused") then
		waveSub.Text = "waves paused (training)"
	elseif phase == "Wave" then
		local n = workspace:GetAttribute("EnemiesLeft") or 0
		waveSub.Text = n .. (if n == 1 then " brute left" else " brutes left")
	elseif phase == "Breather" then
		waveSub.Text = "next wave in " .. left
	elseif phase == "Countdown" then
		waveSub.Text = "starting in " .. left
	elseif phase == "Defeat" then
		waveSub.Text = "restarting in " .. left
	else
		waveSub.Text = ""
	end

	-- combo
	comboShown -= dt
	comboPop = math.max(0, comboPop - dt * 6)
	local cv = comboShown > 0
	comboNum.Visible = cv
	comboLabel.Visible = cv
	comboNum.TextSize = 64 * (1 + 0.3 * comboPop)
	comboNum.Rotation = -4 * comboPop

	-- banner
	bannerT += dt
	local a
	if bannerT < 0.15 then
		a = bannerT / 0.15
	elseif bannerT < bannerDur - 0.4 then
		a = 1
	else
		a = math.clamp((bannerDur - bannerT) / 0.4, 0, 1)
	end
	local tr = 1 - a
	banner.TextTransparency = tr
	bannerSub.TextTransparency = tr
	banner:FindFirstChildOfClass("UIStroke").Transparency = tr
	bannerSub:FindFirstChildOfClass("UIStroke").Transparency = tr
	banner.TextSize = 72 * (1 + 0.25 * math.max(0, 1 - bannerT / 0.15))
end

function Hud.init(combatModule)
	combat = combatModule
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	build()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.H then
			hint.Visible = not hint.Visible
		end
	end)
end

return Hud
