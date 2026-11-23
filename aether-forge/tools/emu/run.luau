--!nonstrict
-- Headless smoke test: boots the real server + client scripts in the emulator and lets a bot play.
-- usage: luaurun run.luau <aether-forge dir> <api.luau> <tree.luau> [seconds] [bot style]

local ROOT, API_PATH, TREE_PATH = ARGS[1], ARGS[2], ARGS[3]
local SECONDS = tonumber(ARGS[4] or "60")
local STYLE = ARGS[5] or "good"

local Emu = loadchunk(readfile(ROOT .. "/tools/emu/roblox.luau"), "emu")()
local game = Emu.init(API_PATH, ROOT .. "/tools/preview/shim.luau")
local Enum = Emu.Enum
local workspace = Emu.workspace
local NOT_SCRIPTABLE = { Technology = true }
Emu.quiet = os.getenv and os.getenv("EMU_VERBOSE") == nil

-- build the place from the Rojo project mirror
local tree = loadchunk(readfile(TREE_PATH), "tree")()
local scripts = {}
local function applyProps(inst, props)
	if not props then
		return
	end
	for k, v in props do
		if NOT_SCRIPTABLE[k] then
			continue
		end
		local value = v
		if type(v) == "table" and v.enumOrString then
			local m = Emu.lookupMember(inst.ClassName, k)
			if m and string.sub(m.type, 1, 2) == "e:" then
				value = Enum[string.sub(m.type, 3)][v.enumOrString]
			else
				value = v.enumOrString
			end
		elseif type(v) == "table" and v.color3 then
			value = Color3.new(v.color3[1], v.color3[2], v.color3[3])
		end
		Emu.internalWrite = true
		local ok, err = pcall(function()
			inst[k] = value
		end)
		Emu.internalWrite = false
		if not ok then
			Emu.report("project property " .. inst.ClassName .. "." .. k .. ": " .. tostring(err))
		end
	end
end
local function build(node, parent)
	local inst
	if node.class == "DataModel" then
		inst = game
	elseif parent == game then
		inst = game:GetService(node.class)
	else
		if node.class == "Script" or node.class == "LocalScript" or node.class == "ModuleScript" then
			inst = Emu.scriptInstance(node.class, node.name, node.source)
			if node.class == "Script" then
				table.insert(scripts, inst)
			end
		elseif node.class == "StarterPlayerScripts" or node.class == "StarterCharacterScripts" then
			inst = parent:FindFirstChildOfClass(node.class)
		else
			inst = Emu.Instance.new(node.class)
			inst.Name = node.name
		end
		if inst.Parent ~= parent then
			inst.Parent = parent
		end
	end
	applyProps(inst, node.props)
	for _, c in node.children do
		build(c, inst)
	end
	return inst
end
build(tree, nil)

local services = Emu.services
-- run server scripts
for _, s in scripts do
	if s:IsDescendantOf(services.ServerScriptService) or s:IsDescendantOf(services.Workspace) then
		Emu.runScript(s, "server")
	end
end
local DT = 1 / 60
for _ = 1, 10 do
	Emu.step(DT)
end

-- join a player and start their LocalScripts
local player = Emu.addPlayer("Tester", 1)
for _ = 1, 3 do
	Emu.step(DT)
end
for _, s in services.StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts"):GetChildren() do
	local c = s:Clone()
	c.Parent = player.PlayerScripts
	if c.ClassName == "LocalScript" then
		Emu.runScript(c, "client")
	end
end
for _, s in services.StarterGui:GetChildren() do
	s:Clone().Parent = player.PlayerGui
end

------------------------------------------------------------------------ bot
local stats = { lights = 0, heavies = 0, dashes = 0, parries = 0, maxWave = 0, kills = 0, frames = 0, forged = 0 }
local lastPress = {}
local function press(action, cooldown)
	local t = Emu.time
	if lastPress[action] and t - lastPress[action] < cooldown then
		return
	end
	lastPress[action] = t
	Emu.pressAction(action)
	return true
end

local function serverNow()
	return Emu.time + 1000
end

local seenEnemies = {}
local function botStep()
	local char = player.Character
	if not char or not char.PrimaryPart then
		return
	end
	local root = char.PrimaryPart
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local pos = root.Position
	local enemies = workspace.Enemies:GetChildren()
	for _, e in enemies do
		if not seenEnemies[e] then
			seenEnemies[e] = true
		end
	end
	local best, bestD = nil, math.huge
	for _, e in enemies do
		if e:GetAttribute("State") ~= "Dead" and e.PrimaryPart then
			local d = (e.PrimaryPart.Position - pos).Magnitude
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	local target = best and best.PrimaryPart
	if not target then
		-- go mine
		for _, c in workspace.Crystals:GetChildren() do
			if c.PrimaryPart then
				local d = (c.PrimaryPart.Position - pos).Magnitude
				if d < bestD then
					target, bestD = c.PrimaryPart, d
				end
			end
		end
	end
	-- scenario hooks can take over movement (e.g. walking to the anvil to forge)
	if Emu.onBotStep then
		local override = Emu.onBotStep(player, char, stats)
		if override then
			Emu.internalWrite = true
			hum.MoveDirection = override
			Emu.internalWrite = false
			return
		end
	end
	local move = Vector3.new(0, 0, 0)
	if target then
		local to = target.Position - pos
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude > 6 then
			move = flat.Unit
		end
		local cam = workspace.CurrentCamera
		local sp = cam:WorldToViewportPoint(target.Position)
		Emu.mouse = Emu.DT.Vector2.new(sp.X, sp.Y)
		if flat.Magnitude < 9 then
			if press("AF_Light", 0.14) then
				stats.lights += 1
			end
			if math.random() < 0.01 and press("AF_Heavy", 2) then
				stats.heavies += 1
			end
		end
	end
	-- defend
	for _, e in enemies do
		local st = e:GetAttribute("State")
		local strikeT = e:GetAttribute("StrikeT")
		if st == "Windup" and strikeT and e.PrimaryPart and (e.PrimaryPart.Position - pos).Magnitude < 12 then
			local left = strikeT - serverNow()
			if STYLE == "good" and left > 0.04 and left < 0.12 then
				if math.random() < 0.65 then
					if press("AF_Parry", 0.6) then
						stats.parries += 1
					end
				elseif press("AF_Dash", 0.5) then
					stats.dashes += 1
				end
			end
		end
	end
	Emu.internalWrite = true
	hum.MoveDirection = move
	Emu.internalWrite = false
end

-- count gameplay events as the client sees them
stats.hurts, stats.defeats, stats.resets, stats.waveClears, stats.crystals, stats.parried = 0, 0, 0, 0, 0, 0
Emu.spawnIn("client", function()
	local net = game:GetService("ReplicatedStorage"):WaitForChild("AetherNet")
	net.Fx.OnClientEvent:Connect(function(kind, data)
		if kind == "PlayerHurt" then
			stats.hurts += 1
		elseif kind == "CrystalBreak" then
			stats.crystals += 1
		elseif kind == "Parried" then
			stats.parried += 1
		end
	end)
	net.Run.OnClientEvent:Connect(function(kind)
		if kind == "Defeat" then
			stats.defeats += 1
		elseif kind == "Reset" then
			stats.resets += 1
		elseif kind == "WaveCleared" then
			stats.waveClears += 1
		end
	end)
end)

-- optional extra scenario hooks
local extra = ROOT .. "/tools/emu/scenario.luau"
local okExtra, scenario = pcall(function()
	return loadchunk(readfile(extra), "scenario")()
end)
if okExtra and type(scenario) == "function" then
	scenario(Emu, player, stats)
end

local frames = math.floor(SECONDS / DT)
for f = 1, frames do
	if f % 2 == 0 then
		Emu.spawnIn("client", botStep)
	end
	Emu.step(DT)
	stats.maxWave = math.max(stats.maxWave, workspace:GetAttribute("Wave") or 0)
	stats.frames = f
	if #Emu.errors > 30 then
		print("too many errors, stopping")
		break
	end
end
for e in seenEnemies do
	if e:GetAttribute("State") == "Dead" or e.Parent == nil then
		stats.kills += 1
	end
end

print(string.format(
	"\n== smoke test: %.0fs simulated, %d frames ==\nwave reached %d | enemies seen %d, dead %d | lights %d heavies %d parries %d dashes %d\nplayer HP %s/%s ore %s dead %s",
	stats.frames * DT,
	stats.frames,
	stats.maxWave,
	(function()
		local n = 0
		for _ in seenEnemies do
			n += 1
		end
		return n
	end)(),
	stats.kills,
	stats.lights,
	stats.heavies,
	stats.parries,
	stats.dashes,
	tostring(player:GetAttribute("HP")),
	tostring(player:GetAttribute("MaxHP")),
	tostring(player:GetAttribute("Ore")),
	tostring(player:GetAttribute("Dead"))
))
print(string.format("hurts %d | server-confirmed parries %d | crystals broken %d | waves cleared %d | defeats %d | resets %d",
	stats.hurts, stats.parried, stats.crystals, stats.waveClears, stats.defeats, stats.resets))
if Emu.summary then
	Emu.summary(stats)
end
for _, w in Emu.warnings do
	print("[warning] " .. w)
end
print(string.format("errors: %d, warnings: %d", #Emu.errors, #Emu.warnings))
