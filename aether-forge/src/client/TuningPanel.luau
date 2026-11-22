--!nonstrict
-- TuningPanel (Studio only, press T): change game-feel numbers live while you play, flip debug
-- helpers, and print the current values so you can paste them back into Config.luau.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local Moves = require(Shared.Moves)
local Net = require(Shared.Net)

local Sfx = require(script.Parent.Sfx)

local TuningPanel = {}

-- { label, getter, setter, step, min, max }
local function cfgRow(label, tbl, key, step, min, max)
	return {
		label = label,
		get = function()
			return tbl[key]
		end,
		set = function(v)
			tbl[key] = v
		end,
		step = step,
		min = min,
		max = max,
	}
end

local ROWS = {
	{ header = "HITSTOP (seconds)" },
	cfgRow("Light hit", Config.Feel, "HitstopLight", 0.01, 0, 0.3),
	cfgRow("Finisher hit", Config.Feel, "HitstopFinisher", 0.01, 0, 0.3),
	cfgRow("Heavy hit", Config.Feel, "HitstopHeavy", 0.01, 0, 0.4),
	cfgRow("Crystal hit", Config.Feel, "HitstopCrystal", 0.01, 0, 0.3),
	cfgRow("Parry", Config.Feel, "HitstopParry", 0.01, 0, 0.3),
	{ header = "SCREEN SHAKE (trauma)" },
	cfgRow("Light", Config.Feel, "ShakeLight", 0.04, 0, 1),
	cfgRow("Finisher", Config.Feel, "ShakeFinisher", 0.04, 0, 1),
	cfgRow("Heavy", Config.Feel, "ShakeHeavy", 0.04, 0, 1),
	cfgRow("Parry", Config.Feel, "ShakeParry", 0.04, 0, 1),
	cfgRow("Getting hit", Config.Feel, "ShakeHurt", 0.04, 0, 1),
	{ header = "TIMING" },
	{
		label = "Parry window",
		get = function()
			return Moves.Parry.active[2]
		end,
		set = function(v)
			Moves.Parry.active[2] = v
		end,
		step = 0.01,
		min = 0.05,
		max = 0.3,
	},
	{
		label = "Dash i-frames",
		get = function()
			return Moves.Dash.iframes[2]
		end,
		set = function(v)
			Moves.Dash.iframes[2] = v
		end,
		step = 0.01,
		min = 0.05,
		max = 0.35,
	},
	cfgRow("Glint lead (parry cue)", Config.Feel, "GlintLead", 0.02, 0.1, 0.8),
	cfgRow("Parry slow-mo scale", Config.Feel, "ParrySlowmoScale", 0.05, 0.05, 1),
	cfgRow("Parry slow-mo time", Config.Feel, "ParrySlowmoDuration", 0.05, 0, 1.5),
	cfgRow("Input buffer", Config.Feel, "InputBuffer", 0.02, 0, 0.5),
	{ header = "AIM ASSIST + CAMERA" },
	cfgRow("Lock angle", Config.Feel, "SoftLockAngle", 5, 0, 120),
	cfgRow("Lock range", Config.Feel, "SoftLockRange", 1, 0, 40),
	cfgRow("Camera distance", Config.Camera, "Distance", 2, 20, 70),
	cfgRow("Camera pitch", Config.Camera, "Pitch", 2, 25, 85),
	cfgRow("Camera FOV", Config.Camera, "FOV", 2, 30, 90),
	cfgRow("Walk speed", Config.Player, "WalkSpeed", 1, 8, 40),
}

local TOGGLES = {
	{ label = "Slow-mo x0.25", key = "slowmo" },
	{ label = "Show hitboxes", key = "hitbox" },
	{ label = "Pause waves", key = "pause" },
	{ label = "Passive enemies", key = "passive" },
	{ label = "God mode", key = "god" },
}

local BUTTONS = {
	{ label = "Spawn Brute", cmd = "SpawnBrute" },
	{ label = "Kill all", cmd = "KillAll" },
	{ label = "Heal", cmd = "Heal" },
	{ label = "Reset run", cmd = "ResetRun" },
}

local function fmt(v, step)
	if step >= 1 then
		return string.format("%d", v)
	end
	return string.format("%.2f", v)
end

local function printValues()
	local lines = { "-- Aether Forge tuning (paste into Config.luau / Moves.luau)" }
	for _, r in ROWS do
		if r.get then
			table.insert(lines, string.format("%-22s = %s", r.label, fmt(r.get(), r.step)))
		end
	end
	print(table.concat(lines, "\n"))
end

function TuningPanel.init(combat)
	if not RunService:IsStudio() then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AF_Tuning"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("ScrollingFrame")
	panel.Size = UDim2.new(0, 300, 1, -140)
	panel.Position = UDim2.new(1, -316, 0, 70)
	panel.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 6
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = panel

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local function text(parent, t, size, color, font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = t
		l.TextSize = size
		l.Font = font or Enum.Font.GothamBold
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = parent
		return l
	end

	local function button(parent, t, size, pos, color, onClick)
		local b = Instance.new("TextButton")
		b.Size = size
		b.Position = pos
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.Text = t
		b.TextSize = 13
		b.Font = Enum.Font.GothamBlack
		b.TextColor3 = Color3.new(1, 1, 1)
		b.AutoButtonColor = true
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 4)
		cc.Parent = b
		b.Parent = parent
		b.MouseButton1Click:Connect(function()
			Sfx.play("UI")
			onClick(b)
		end)
		return b
	end

	local title = text(panel, "TUNING  (T to close)", 15, Config.Palette.Aether, Enum.Font.GothamBlack)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.LayoutOrder = nextOrder()

	for _, r in ROWS do
		if r.header then
			local h = text(panel, r.header, 12, Color3.fromRGB(150, 160, 190), Enum.Font.GothamBlack)
			h.Size = UDim2.new(1, 0, 0, 20)
			h.LayoutOrder = nextOrder()
		else
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundTransparency = 1
			row.LayoutOrder = nextOrder()
			row.Parent = panel
			local l = text(row, r.label, 13)
			l.Size = UDim2.new(1, -110, 1, 0)
			local value = text(row, fmt(r.get(), r.step), 13, Color3.fromRGB(255, 220, 120), Enum.Font.GothamBlack)
			value.Size = UDim2.fromOffset(46, 24)
			value.Position = UDim2.new(1, -78, 0, 0)
			value.TextXAlignment = Enum.TextXAlignment.Center
			local function change(d)
				local v = math.clamp(r.get() + d, r.min, r.max)
				v = math.floor(v / r.step + 0.5) * r.step
				r.set(v)
				value.Text = fmt(v, r.step)
			end
			button(row, "-", UDim2.fromOffset(26, 22), UDim2.new(1, -108, 0, 1), Color3.fromRGB(60, 60, 84), function()
				change(-r.step)
			end)
			button(row, "+", UDim2.fromOffset(26, 22), UDim2.new(1, -28, 0, 1), Color3.fromRGB(60, 60, 84), function()
				change(r.step)
			end)
		end
	end

	local h = text(panel, "DEBUG", 12, Color3.fromRGB(150, 160, 190), Enum.Font.GothamBlack)
	h.Size = UDim2.new(1, 0, 0, 20)
	h.LayoutOrder = nextOrder()

	local toggles = {}
	for _, t in TOGGLES do
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 26)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = nextOrder()
		holder.Parent = panel
		toggles[t.key] = false
		button(holder, t.label .. ": OFF", UDim2.new(1, 0, 1, -2), UDim2.new(), Color3.fromRGB(50, 50, 70), function(b)
			local on = not toggles[t.key]
			toggles[t.key] = on
			b.Text = t.label .. (if on then ": ON" else ": OFF")
			b.BackgroundColor3 = if on then Color3.fromRGB(30, 120, 150) else Color3.fromRGB(50, 50, 70)
			if t.key == "slowmo" then
				Config.Feel.DebugTimeScale = if on then 0.25 else 1
			elseif t.key == "hitbox" then
				combat.debugHitbox = on
			elseif t.key == "pause" then
				Net.Debug:FireServer("PauseWaves", on)
			elseif t.key == "passive" then
				Net.Debug:FireServer("Passive", on)
			elseif t.key == "god" then
				Net.Debug:FireServer("God", on)
			end
		end)
	end

	for _, bdef in BUTTONS do
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 26)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = nextOrder()
		holder.Parent = panel
		button(holder, bdef.label, UDim2.new(1, 0, 1, -2), UDim2.new(), Color3.fromRGB(110, 60, 40), function()
			Net.Debug:FireServer(bdef.cmd)
		end)
	end

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 26)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = nextOrder()
	holder.Parent = panel
	button(holder, "Print values to Output", UDim2.new(1, 0, 1, -2), UDim2.new(), Color3.fromRGB(40, 110, 70), printValues)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.T then
			gui.Enabled = not gui.Enabled
		end
	end)
end

return TuningPanel
