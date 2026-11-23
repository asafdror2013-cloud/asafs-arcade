--!nonstrict
-- ForgeUI: the three upgrade cards the Aether Anvil offers. Click a card or press 1 / 2 / 3.
-- Esc (or walking away) closes it. The server validates and applies the choice.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Upgrades = require(Shared.Upgrades)
local ArenaLayout = require(Shared.ArenaLayout)
local Rigs = require(Shared.Rigs)
local Net = require(Shared.Net)

local Sfx = require(script.Parent.Sfx)
local Clock = require(script.Parent.Clock)

local ForgeUI = {}
ForgeUI.isOpen = false

local player = Players.LocalPlayer
local gui, title, sub, cardsFrame, leaveButton
local cards = {}
local current = nil
local openedAt = 0
local busy = false
local hud

local ELEMENT_LABEL = { Aether = "AETHER", Fire = "FIRE", Storm = "STORM", Frost = "FROST" }

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

local function costText(cost)
	local parts = {}
	for _, el in { "Aether", "Fire", "Storm", "Frost" } do
		if cost[el] then
			table.insert(parts, cost[el] .. " " .. el)
		end
	end
	return table.concat(parts, "  +  ")
end

local function makeCard(i)
	local b = Instance.new("TextButton")
	b.Name = "Card" .. i
	b.Size = UDim2.fromOffset(230, 300)
	b.BackgroundColor3 = Color3.fromRGB(16, 16, 26)
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = i
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 8)
	band.BorderSizePixel = 0
	band.Parent = b
	local gem = Instance.new("Frame")
	gem.Size = UDim2.fromOffset(34, 34)
	gem.Position = UDim2.new(0.5, -17, 0, 30)
	gem.Rotation = 45
	gem.BorderSizePixel = 0
	gem.Parent = b
	local gemStroke = Instance.new("UIStroke")
	gemStroke.Thickness = 2
	gemStroke.Color = Color3.new(1, 1, 1)
	gemStroke.Transparency = 0.4
	gemStroke.Parent = gem
	local key = label(b, tostring(i), 14, Enum.Font.GothamBlack, Color3.fromRGB(150, 150, 170), {
		Size = UDim2.fromOffset(24, 20),
		Position = UDim2.fromOffset(8, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local element = label(b, "", 11, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 78),
	})
	local name = label(b, "", 21, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 94),
	})
	local level = label(b, "", 13, Enum.Font.GothamBlack, Color3.fromRGB(255, 220, 120), {
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 146),
	})
	local desc = label(b, "", 14, Enum.Font.GothamMedium, Color3.fromRGB(210, 214, 230), {
		Size = UDim2.new(1, -24, 0, 80),
		Position = UDim2.fromOffset(12, 170),
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local cost = label(b, "", 13, Enum.Font.GothamBlack, Color3.fromRGB(180, 230, 255), {
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 10, 1, -30),
	})
	b.MouseEnter:Connect(function()
		if current then
			scale.Scale = 1.05
		end
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	b.MouseButton1Click:Connect(function()
		ForgeUI.pick(i)
	end)
	b.Parent = cardsFrame
	return { button = b, stroke = stroke, scale = scale, band = band, gem = gem, key = key, element = element, name = name, level = level, desc = desc, cost = cost }
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AF_Forge"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.BorderSizePixel = 0
	dim.Parent = gui

	title = label(gui, "THE AETHER ANVIL", 34, Enum.Font.GothamBlack, Color3.fromRGB(255, 214, 120), {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.5, -230),
	})
	local ts = Instance.new("UIStroke")
	ts.Thickness = 3
	ts.Parent = title
	sub = label(gui, "Choose one to forge", 16, Enum.Font.GothamBold, Color3.fromRGB(210, 215, 235), {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0.5, -188),
	})

	cardsFrame = Instance.new("Frame")
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Size = UDim2.fromOffset(740, 310)
	cardsFrame.Position = UDim2.new(0.5, -370, 0.5, -155)
	cardsFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 20)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = cardsFrame
	for i = 1, 3 do
		cards[i] = makeCard(i)
	end

	leaveButton = Instance.new("TextButton")
	leaveButton.Size = UDim2.fromOffset(160, 36)
	leaveButton.Position = UDim2.new(0.5, -80, 0.5, 175)
	leaveButton.BackgroundColor3 = Color3.fromRGB(40, 40, 58)
	leaveButton.BorderSizePixel = 0
	leaveButton.Text = "Leave (Esc)"
	leaveButton.TextSize = 15
	leaveButton.Font = Enum.Font.GothamBlack
	leaveButton.TextColor3 = Color3.new(1, 1, 1)
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, 6)
	lc.Parent = leaveButton
	leaveButton.Parent = gui
	leaveButton.MouseButton1Click:Connect(function()
		ForgeUI.close(true)
	end)
end

function ForgeUI.open(data)
	current = data
	busy = false
	openedAt = Clock.real
	local ores = {}
	for el, attr in Upgrades.OreAttribute do
		ores[el] = player:GetAttribute(attr) or 0
	end
	for i, c in cards do
		local offer = data.offers[i]
		c.button.Visible = offer ~= nil
		if offer then
			local u = Upgrades.byId[offer.id]
			local color = Upgrades.ElementColors[u.element]
			c.stroke.Color = color
			c.band.BackgroundColor3 = color
			c.gem.BackgroundColor3 = color
			c.element.Text = ELEMENT_LABEL[u.element]
			c.element.TextColor3 = color
			c.name.Text = u.name
			c.level.Text = if offer.level == 0 then "NEW" else Upgrades.roman[offer.level] .. "  ->  " .. Upgrades.roman[offer.level + 1]
			c.desc.Text = u.desc(offer.level)
			c.cost.Text = costText(offer.cost)
			local ok = Upgrades.canAfford(ores, offer.cost)
			c.cost.TextColor3 = if ok then Color3.fromRGB(180, 230, 255) else Color3.fromRGB(255, 110, 110)
			c.button.BackgroundTransparency = if ok then 0.05 else 0.35
			c.scale.Scale = 0.6
		end
	end
	sub.Text = "Forge #" .. (data.forgeCount + 1) .. "  ·  choose one"
	gui.Enabled = true
	ForgeUI.isOpen = true
	Sfx.play("Wave", 0.6)
end

function ForgeUI.pick(i)
	if not current or busy or Clock.real - openedAt < 0.25 then
		return
	end
	local offer = current.offers[i]
	if not offer then
		return
	end
	busy = true
	Sfx.play("UI")
	Net.Forge:FireServer("Pick", i)
end

function ForgeUI.close(tellServer)
	if not ForgeUI.isOpen then
		return
	end
	if tellServer then
		Net.Forge:FireServer("Close")
	end
	current = nil
	gui.Enabled = false
	ForgeUI.isOpen = false
end

function ForgeUI.update(dt)
	if not ForgeUI.isOpen then
		return
	end
	-- cards pop in one after another
	local t = Clock.real - openedAt
	for i, c in cards do
		local k = math.clamp((t - (i - 1) * 0.06) / 0.18, 0, 1)
		local target = 0.6 + 0.4 * (1 - (1 - k) ^ 3)
		if c.scale.Scale < 1.04 then
			c.scale.Scale = math.max(c.scale.Scale, target)
		end
	end
	-- walking away closes it
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local d = Vector3.new(root.Position.X - ArenaLayout.AnvilPos.X, 0, root.Position.Z - ArenaLayout.AnvilPos.Z)
		if d.Magnitude > 16 then
			ForgeUI.close(true)
		end
	end
	_ = dt
end

function ForgeUI.init(hudModule)
	hud = hudModule
	build()
	Net.Forge.OnClientEvent:Connect(function(kind, data)
		if kind == "Offer" then
			ForgeUI.open(data)
		elseif kind == "Denied" then
			busy = false
			if hud then
				hud.toast(data.reason or "Can't forge right now", Color3.fromRGB(255, 120, 120))
			end
		elseif kind == "Forged" then
			ForgeUI.close(false)
			local u = Upgrades.byId[data.id]
			if hud and u then
				local w = Rigs.Weapons[data.weapon]
				hud.banner(u.name .. " " .. Upgrades.roman[data.level], if w then w.displayName else "", Upgrades.ElementColors[u.element], 2)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not ForgeUI.isOpen or processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.One then
			ForgeUI.pick(1)
		elseif k == Enum.KeyCode.Two then
			ForgeUI.pick(2)
		elseif k == Enum.KeyCode.Three then
			ForgeUI.pick(3)
		elseif k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then
			ForgeUI.close(true)
		end
	end)
	Net.Run.OnClientEvent:Connect(function(kind)
		if kind == "Reset" or kind == "Defeat" then
			ForgeUI.close(false)
		end
	end)
end

return ForgeUI
