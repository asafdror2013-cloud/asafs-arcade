--!nonstrict
-- Sfx: sound effects. Sound is one of the biggest parts of game feel, and these placeholders use
-- sounds that ship inside Roblox itself. Swap any id for a Creator Store sound ("rbxassetid://123..."),
-- the Creator Store has hundreds of free sword, impact and crystal sounds uploaded by Roblox.
-- Each entry can layer several sounds; pitch is randomized a little so repeats don't sound robotic.

local SoundService = game:GetService("SoundService")

local Sfx = {}

local SLASH = "rbxasset://sounds/swordslash.wav"
local LUNGE = "rbxasset://sounds/swordlunge.wav"
local UNSHEATH = "rbxasset://sounds/unsheath.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local THUD = "rbxasset://sounds/action_jump_land.mp3"
local CLICK = "rbxasset://sounds/clickfast.wav"

-- name = { { id, volume, pitch, pitchJitter }, ... }
Sfx.defs = {
	Swing = { { SLASH, 0.55, 1.25, 0.08 } },
	SwingBig = { { SLASH, 0.7, 0.95, 0.05 }, { LUNGE, 0.35, 1.3, 0.05 } },
	SwingHeavy = { { LUNGE, 0.7, 0.8, 0.04 } },
	Hit = { { THUD, 0.9, 1.35, 0.1 }, { SLASH, 0.35, 1.7, 0.1 } },
	HitBig = { { THUD, 1.2, 0.85, 0.06 }, { LUNGE, 0.4, 1.5, 0.05 } },
	Slam = { { THUD, 1.6, 0.45, 0.03 }, { THUD, 0.8, 0.7, 0.05 } },
	Parry = { { UNSHEATH, 1.0, 1.7, 0.04 }, { PING, 0.6, 0.8, 0.02 }, { THUD, 0.6, 1.8, 0.02 } },
	Glint = { { PING, 0.45, 2.2, 0.02 } },
	Dash = { { LUNGE, 0.4, 1.8, 0.1 } },
	Hurt = { { THUD, 1.0, 0.75, 0.05 }, { SLASH, 0.3, 0.6, 0.05 } },
	CrystalHit = { { PING, 0.6, 1.5, 0.2 } },
	CrystalBreak = { { PING, 0.8, 0.9, 0.05 }, { PING, 0.5, 1.6, 0.05 }, { THUD, 0.7, 1.1, 0.05 } },
	Ore = { { PING, 0.25, 2.4, 0.15 } },
	EnemyDie = { { THUD, 1.2, 0.6, 0.05 }, { PING, 0.4, 0.5, 0.05 } },
	Wave = { { UNSHEATH, 0.6, 0.7, 0 } },
	UI = { { CLICK, 0.5, 1, 0.05 } },
}

local cache = {}

local function template(id)
	local s = cache[id]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = SoundService
		cache[id] = s
	end
	return s
end

function Sfx.play(name, volumeScale)
	local def = Sfx.defs[name]
	if not def then
		return
	end
	for _, layer in def do
		local s = template(layer[1]):Clone()
		s.Volume = layer[2] * (volumeScale or 1)
		s.PlaybackSpeed = layer[3] * (1 + (math.random() * 2 - 1) * (layer[4] or 0))
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
		task.delay(4, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
end

function Sfx.preload()
	for _, def in Sfx.defs do
		for _, layer in def do
			template(layer[1])
		end
	end
end

return Sfx
