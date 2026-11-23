--!nonstrict
-- Net: the RemoteEvents (declared in default.project.json under ReplicatedStorage.AetherNet).
--
-- Client -> Server
--   Action(kind, serverTime)                    a move started (for validation + other clients)
--   Hit(moveName, swingId, { targets })         the local hitbox touched these enemies/crystals
--   StrikeReport(enemy, strikeId, outcome)      how an enemy strike resolved for this player
--                                               ("parry" | "dodge" | "hurt" | "miss")
--   Debug(command, arg)                         Studio-only test commands (tuning panel)
-- Server -> Client
--   Fx(kind, data)                              effects other clients should see
--   Run(kind, data)                             wave / run flow (Wave, WaveCleared, Defeat, Reset, Summary)
-- Both ways
--   Forge(kind, data)                           anvil: Offer / Denied / Forged (server), Pick / Close (client)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("AetherNet")

return {
	Action = folder:WaitForChild("Action") :: RemoteEvent,
	Hit = folder:WaitForChild("Hit") :: RemoteEvent,
	StrikeReport = folder:WaitForChild("StrikeReport") :: RemoteEvent,
	Debug = folder:WaitForChild("Debug") :: RemoteEvent,
	Fx = folder:WaitForChild("Fx") :: RemoteEvent,
	Run = folder:WaitForChild("Run") :: RemoteEvent,
	Forge = folder:WaitForChild("Forge") :: RemoteEvent,
}
