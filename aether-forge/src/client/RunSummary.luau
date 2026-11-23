--!nonstrict
-- RunSummary: the end-of-run screen (wave reached, kills, damage, best combo, parries, ore, forged
-- build, weapon) plus what the run earned toward permanent progress.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Upgrades = require(Shared.Upgrades)
local Rigs = require(Shared.Rigs)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Clock = require(script.Parent.Clock)

local RunSummary = {}

local player = Players.LocalPlayer
local gui, panel, waveLabel, statsLabel, buildLabel, metaLabel, footer
local shownAt, endsAt = 0, 0

local function label(parent, text, size, font, color, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextWrapped = true
	if props then
		for k, v in props do
			l[k] = v
		end
	end
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AF_Summary"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(6, 4, 12)
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Parent = gui

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(560, 470)
	panel.Position = UDim2.new(0.5, -280, 0.5, -235)
	panel.BackgroundColor3 = Color3.fromRGB(14, 14, 24)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = panel
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Config.Palette.Danger
	st.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Name = "Pop"
	sc.Parent = panel

	label(panel, "RUN OVER", 40, Enum.Font.GothamBlack, Config.Palette.Danger, {
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.fromOffset(0, 16),
	})
	waveLabel = label(panel, "", 20, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 64),
	})
	statsLabel = label(panel, "", 16, Enum.Font.GothamBold, Color3.fromRGB(220, 225, 240), {
		Size = UDim2.new(0.5, -30, 0, 200),
		Position = UDim2.fromOffset(30, 104),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
	})
	buildLabel = label(panel, "", 14, Enum.Font.GothamBold, Color3.fromRGB(220, 225, 240), {
		Size = UDim2.new(0.5, -30, 0, 220),
		Position = UDim2.new(0.5, 10, 0, 104),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
	})
	metaLabel = label(panel, "", 18, Enum.Font.GothamBlack, Config.Palette.Gold, {
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.new(0, 20, 1, -110),
		RichText = true,
	})
	footer = label(panel, "", 14, Enum.Font.GothamBold, Color3.fromRGB(160, 165, 190), {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -40),
	})
end

local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function show(data)
	waveLabel.Text = "You reached wave " .. data.wave
	local m, s = math.floor(data.time / 60), data.time % 60
	local ore = data.ore or {}
	local lines = {
		string.format("Enemies shattered   <b>%d</b>", data.kills),
		string.format("Damage dealt   <b>%d</b>", data.damage),
		string.format("Best combo   <b>%d</b>", data.bestCombo),
		string.format("Parries   <b>%d</b>", data.parries),
		string.format("Crystals mined   <b>%d</b>", data.crystals),
		string.format(
			"Ore   <b>%d</b> <font color=\"%s\">%d</font> <font color=\"%s\">%d</font> <font color=\"%s\">%d</font>",
			ore.Aether or 0,
			hex(Upgrades.ElementColors.Fire),
			ore.Fire or 0,
			hex(Upgrades.ElementColors.Storm),
			ore.Storm or 0,
			hex(Upgrades.ElementColors.Frost),
			ore.Frost or 0
		),
		string.format("Time   <b>%d:%02d</b>", m, s),
	}
	statsLabel.Text = table.concat(lines, "\n")

	local w = Rigs.Weapons[data.weapon]
	local blines = { string.format('<font color="%s"><b>%s</b></font>', hex(w and w.glow or Config.Palette.Aether), string.upper(w and w.displayName or "Ember Blade")) }
	local b = Upgrades.parse(data.build)
	for _, u in Upgrades.list do
		local l = b[u.id]
		if l and l > 0 then
			table.insert(blines, string.format('<font color="%s">◆</font> %s %s', hex(Upgrades.ElementColors[u.element]), u.name, Upgrades.roman[l]))
		end
	end
	if #blines == 1 then
		table.insert(blines, "No upgrades forged. Mine ore and visit the anvil!")
	end
	buildLabel.Text = table.concat(blines, "\n")

	local meta = data.meta
	if meta then
		local extra = if meta.newBest then "   ·   NEW BEST WAVE!" else ""
		metaLabel.Text = string.format("+%d Aether Shards   (total %d)%s", meta.earned or 0, meta.shards or 0, extra)
	else
		metaLabel.Text = ""
	end
	shownAt = Clock.real
	endsAt = Clock.server() + 9
	panel.Pop.Scale = 0.7
	gui.Enabled = true
end

function RunSummary.update()
	if not gui or not gui.Enabled then
		return
	end
	local t = Clock.real - shownAt
	local k = math.clamp(t / 0.25, 0, 1)
	panel.Pop.Scale = 0.7 + 0.3 * (1 - (1 - k) ^ 3)
	footer.Text = "next run in " .. math.max(0, math.ceil(endsAt - Clock.server()))
end

function RunSummary.hide()
	if gui then
		gui.Enabled = false
	end
end

function RunSummary.init()
	build()
	Net.Run.OnClientEvent:Connect(function(kind, data)
		if kind == "Summary" then
			show(data)
		elseif kind == "Reset" then
			RunSummary.hide()
		end
	end)
end

return RunSummary
