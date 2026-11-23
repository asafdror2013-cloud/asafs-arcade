--!nonstrict
-- Extra bot behaviour for the smoke test: during breathers, walk to the anvil and forge.
return function(Emu, player, stats)
	local waitUntil = 0
	stats.forgedSeen = 0
	Emu.spawnIn("client", function()
		local net = Emu.game:GetService("ReplicatedStorage"):WaitForChild("AetherNet")
		net.Forge.OnClientEvent:Connect(function(kind, data)
			if kind == "Forged" then
				stats.forgedSeen += 1
				stats.lastForged = data.id .. " -> " .. tostring(data.weapon)
			elseif kind == "Denied" then
				stats.denied = (stats.denied or 0) + 1
			end
		end)
	end)
	Emu.onBotStep = function(p, char, st)
		local phase = Emu.workspace:GetAttribute("Phase")
		local ore = p:GetAttribute("Ore") or 0
		local cost = 5 + 3 * st.forgedSeen
		if phase ~= "Breather" or ore < cost then
			return nil
		end
		local root = char.PrimaryPart
		local to = Vector3.new(-root.Position.X, 0, -root.Position.Z)
		if to.Magnitude > 7 then
			return to.Unit
		end
		if Emu.time > waitUntil then
			waitUntil = Emu.time + 0.6
			local prompt = Emu.workspace.Arena.AnvilFace.ForgePrompt
			Emu.getSignal(prompt, "Triggered"):FireCtx("server", p)
			Emu.task.delay(0.3, function()
				Emu.pressKey(if math.random() < 0.5 then "One" else "Two")
			end)
		end
		return Vector3.new(0, 0, 0)
	end
	Emu.summary = function(st)
		print(string.format("forged %d (last: %s), denied %d, build '%s', weapon %s", st.forgedSeen, tostring(st.lastForged), st.denied or 0, tostring(player:GetAttribute("Build")), tostring(player:GetAttribute("Weapon"))))
	end
end
