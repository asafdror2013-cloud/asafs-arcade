--!nonstrict
-- Upgrades: the forge's roguelite modifiers. Shared so server and client derive identical stats from
-- the same build. A build is { [upgradeId] = level }, replicated as the player attribute "Build"
-- ("edge:2,ignite:1").
--
-- Elemental upgrades need ore of their element (mined from the rarer crystals at the arena's edge).
-- Taking two or more levels of one element evolves your weapon into that element's form.

local Upgrades = {}

local rgb = Color3.fromRGB
Upgrades.ElementColors = {
	Aether = rgb(70, 225, 255),
	Fire = rgb(255, 110, 40),
	Storm = rgb(190, 120, 255),
	Frost = rgb(150, 220, 255),
}
Upgrades.OreAttribute = { Aether = "Ore", Fire = "OreFire", Storm = "OreStorm", Frost = "OreFrost" }

local roman = { "I", "II", "III", "IV" }
Upgrades.roman = roman

-- desc(level) describes what the NEXT level gives
Upgrades.list = {
	{ id = "edge", name = "Tempered Edge", element = "Aether", max = 3, weight = 10, desc = function()
		return "Light slashes deal +20% damage."
	end },
	{ id = "hammer", name = "Heavier Strike", element = "Aether", max = 3, weight = 9, desc = function()
		return "Heavy Slam deals +25% damage and hits a 15% wider area."
	end },
	{ id = "grip", name = "Quickened Grip", element = "Aether", max = 3, weight = 9, desc = function()
		return "All attacks are 10% faster."
	end },
	{ id = "reach", name = "Longer Blade", element = "Aether", max = 3, weight = 8, desc = function()
		return "Your blade grows: +12% reach on every attack."
	end },
	{ id = "wave", name = "Shockwave Finisher", element = "Aether", max = 2, weight = 8, desc = function(l)
		return if l == 0 then "Your 3rd combo hit fires a cutting shockwave forward." else "Shockwave damage +50% and it travels further."
	end },
	{ id = "core", name = "Aether Core", element = "Aether", max = 3, weight = 7, desc = function()
		return "+25 max HP and heal to full."
	end },
	{ id = "wind", name = "Second Wind", element = "Aether", max = 1, weight = 6, desc = function()
		return "+1 dash charge and dashes recharge 15% faster."
	end },
	{ id = "riposte", name = "Riposte Mastery", element = "Aether", max = 2, weight = 6, desc = function()
		return "Parry window +0.03s and riposte damage +40%."
	end },
	{ id = "leech", name = "Vampiric Steel", element = "Aether", max = 2, weight = 6, desc = function()
		return "Heal 1 HP for every enemy you hit."
	end },
	{ id = "magnet", name = "Ore Sense", element = "Aether", max = 2, weight = 5, desc = function()
		return "+1 ore from every crystal you break."
	end },
	{ id = "ember_dash", name = "Ember Trail", element = "Fire", max = 2, weight = 8, desc = function(l)
		return if l == 0 then "Dashing leaves a trail of fire that burns enemies." else "Ember Trail burns twice as hot."
	end },
	{ id = "ignite", name = "Inferno Edge", element = "Fire", max = 2, weight = 8, desc = function(l)
		return if l == 0 then "Hits set enemies on fire (burn over 2s)." else "Burns deal +50% damage."
	end },
	{ id = "storm_parry", name = "Stormcaller", element = "Storm", max = 2, weight = 8, desc = function(l)
		return if l == 0 then "Parries call lightning down on up to 3 nearby enemies." else "Stormcaller lightning +50% damage, hits 5 enemies."
	end },
	{ id = "chain", name = "Arc Edge", element = "Storm", max = 2, weight = 8, desc = function()
		return "Hits have a 20% chance to arc lightning to 2 nearby enemies."
	end },
	{ id = "frost_slam", name = "Glacial Slam", element = "Frost", max = 2, weight = 8, desc = function(l)
		return if l == 0 then "Heavy Slam freezes enemies solid for 1.5s. Frozen enemies take +25% damage." else "Freeze lasts 0.75s longer."
	end },
	{ id = "frost_edge", name = "Frost Bite", element = "Frost", max = 1, weight = 7, desc = function()
		return "Hits chill enemies: 35% slower movement and attacks for 2s."
	end },
}
Upgrades.byId = {}
for _, u in Upgrades.list do
	Upgrades.byId[u.id] = u
end

-- Ore costs: Aether always, plus element ore for elemental upgrades.
Upgrades.BaseCost = 5
Upgrades.CostStep = 3
Upgrades.ElementCost = 2

function Upgrades.cost(forgeCount, element)
	local c = { Aether = Upgrades.BaseCost + forgeCount * Upgrades.CostStep }
	if element and element ~= "Aether" then
		c[element] = Upgrades.ElementCost
	end
	return c
end

function Upgrades.canAfford(ores, cost)
	for el, n in cost do
		if (ores[el] or 0) < n then
			return false
		end
	end
	return true
end

function Upgrades.encode(build)
	local parts = {}
	for _, u in Upgrades.list do
		local l = build[u.id]
		if l and l > 0 then
			table.insert(parts, u.id .. ":" .. l)
		end
	end
	return table.concat(parts, ",")
end

function Upgrades.parse(s)
	local build = {}
	if type(s) ~= "string" then
		return build
	end
	for id, l in string.gmatch(s, "([%w_]+):(%d+)") do
		if Upgrades.byId[id] then
			build[id] = math.clamp(tonumber(l) or 0, 0, Upgrades.byId[id].max)
		end
	end
	return build
end

function Upgrades.count(build)
	local n = 0
	for _, l in build do
		n += l
	end
	return n
end

function Upgrades.elementLevels(build)
	local e = { Fire = 0, Storm = 0, Frost = 0 }
	for id, l in build do
		local u = Upgrades.byId[id]
		if u and e[u.element] then
			e[u.element] += l
		end
	end
	return e
end

-- Which weapon the build has forged.
function Upgrades.weaponFor(build)
	local e = Upgrades.elementLevels(build)
	local best, bestN = nil, 1
	for _, el in { "Fire", "Storm", "Frost" } do
		if e[el] > bestN then
			best, bestN = el, e[el]
		end
	end
	if best == "Fire" then
		return "FlameGreatsword"
	elseif best == "Storm" then
		return "StormCleaver"
	elseif best == "Frost" then
		return "FrostFang"
	end
	if Upgrades.count(build) >= 3 then
		return "AetherReaver"
	end
	return "EmberBlade"
end

-- Derived combat stats for a build.
function Upgrades.stats(build)
	local function l(id)
		return build[id] or 0
	end
	return {
		lightMult = 1 + 0.2 * l("edge"),
		heavyMult = 1 + 0.25 * l("hammer"),
		slamRadius = 1 + 0.15 * l("hammer"),
		attackSpeed = 1 + 0.1 * l("grip"),
		reach = 1 + 0.12 * l("reach"),
		shockwave = l("wave"),
		maxHpBonus = 25 * l("core"),
		dashCharges = 1 + l("wind"),
		dashCooldownMult = if l("wind") > 0 then 0.85 else 1,
		parryBonus = 0.03 * l("riposte"),
		riposteBonus = 0.4 * l("riposte"),
		leech = l("leech"),
		oreBonus = l("magnet"),
		emberDash = l("ember_dash"),
		ignite = l("ignite"),
		stormParry = l("storm_parry"),
		chain = l("chain"),
		frostSlam = l("frost_slam"),
		frostEdge = l("frost_edge"),
	}
end

-- Pick up to `count` distinct offers the player could take. `rand(n)` returns 1..n.
function Upgrades.roll(build, ores, forgeCount, rand, count)
	count = count or 3
	local pool, total = {}, 0
	for _, u in Upgrades.list do
		local lvl = build[u.id] or 0
		if lvl < u.max then
			local cost = Upgrades.cost(forgeCount, u.element)
			local elementalOk = u.element == "Aether" or (ores[u.element] or 0) >= (cost[u.element] or 0)
			if elementalOk then
				-- elemental upgrades you can afford show up more: you risked the edge for that ore
				local w = u.weight * (if u.element ~= "Aether" then 1.6 else 1)
				table.insert(pool, { id = u.id, w = w })
				total += w
			end
		end
	end
	local picks = {}
	while #picks < count and #pool > 0 do
		local r = rand(1000) / 1000 * total
		local acc = 0
		for i, p in pool do
			acc += p.w
			if r <= acc or i == #pool then
				table.insert(picks, p.id)
				total -= p.w
				table.remove(pool, i)
				break
			end
		end
	end
	return picks
end

return Upgrades
