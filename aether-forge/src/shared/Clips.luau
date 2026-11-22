--!nonstrict
-- Clips: hand-authored keyframe animation for the player and the Brute, plus the procedural
-- idle/run/walk cycles. Angles are degrees: Joint = { x, y, z, px, py, pz }.
--   arms/legs: x+ swings forward,   torso/head/root: x+ leans back
--   y+ turns left, z+ raises the right arm out (left arm: z-)
-- Feet: LFoot/RFoot = { x, y, z } offset of the foot target from rest (y+ lifts, z- steps forward).
-- The player's arms and wrist are IK-driven: keys give hand positions and the blade direction
-- (see AnimCore). The Brute is posed with joint angles only.
-- Timings line up with Moves.luau (each slash crosses the front inside the move's active window).

local AnimCore = require(script.Parent.AnimCore)
local MathUtil = require(script.Parent.MathUtil)

local Clips = {}

local sin, cos, abs = math.sin, math.cos, math.abs
local P = AnimCore.pose

------------------------------------------------------------------------------------------------
-- Player
------------------------------------------------------------------------------------------------
local Player = {}
Clips.Player = Player

local C = AnimCore.cyl

-- Merge authoring tables (later ones win).
local function with(...)
	local out = {}
	for _, t in { ... } do
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

-- Hands are positions relative to the root part (y = 0 is about belt height, the floor is y = -3.1).
-- C(angle, radius, height) places a hand around the body: angle 0 = in front, + = to the left.
-- Blade = { pitch (+ up), yaw (+ left), roll }.
local READY = {
	Root = { 0, -14, 0, 0, -0.22, 0 },
	Waist = { -4, 8, 0 },
	Neck = { 2, 6, 0 },
	RHand = C(-24, 1.55, -0.35),
	Blade = { 28, 10, 0 },
	LHand = C(18, 1.35, -0.15),
	Hilt = 0,
	LFoot = { -0.18, 0, -0.55 },
	RFoot = { 0.18, 0, 0.5 },
}

-- Combat-ready stance: left foot forward, blade held forward and up.
Player.Ready = P(READY)

local raw = {}

-- Light 1: horizontal slash, right to left.
raw.Light1 = {
	length = 0.34,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { 0, -28, 0, 0, -0.3, 0.1 }, Waist = { -6, -24, 0 }, Neck = { 0, 36, 0 },
			RHand = C(-112, 1.5, 0.85), Blade = { 14, -132, -70 }, LHand = C(30, 1.4, 0.0),
			LFoot = { -0.2, 0, -0.6 }, RFoot = { 0.2, 0, 0.55 },
		} },
		{ t = 0.06, ease = "outQuad", pose = {
			Root = { 0, -32, 0, 0, -0.32, 0.1 }, RHand = C(-118, 1.5, 0.9), Blade = { 16, -140, -70 },
		} },
		{ t = 0.11, ease = "outQuad", arc = true, pose = {
			Root = { -6, 20, 0, 0, -0.38, -0.25 }, Waist = { -10, 26, 0 }, Neck = { 0, -30, 0 },
			RHand = C(25, 2.15, 0.15), Blade = { -4, 60, -85 }, LHand = C(120, 1.3, -0.3),
			LFoot = { -0.15, 0, -1.05 }, RFoot = { 0.2, 0, 0.7 },
		} },
		{ t = 0.19, ease = "outQuad", arc = true, pose = {
			Root = { -4, 26, 0, 0, -0.34, -0.25 }, Waist = { -8, 32, 0 }, Neck = { 0, -40, 0 },
			RHand = C(72, 1.85, -0.05), Blade = { -12, 118, -85 },
		} },
		{ t = 0.34, ease = "inOut", arc = true, pose = {
			Root = { 0, 4, 0, 0, -0.26, -0.1 }, Waist = { -5, 14, 0 }, Neck = { 0, -12, 0 },
			RHand = C(20, 1.6, -0.3), Blade = { 22, 40, -30 }, LHand = C(30, 1.3, -0.15),
		} },
	},
}

-- Light 2: backhand slash, left to right.
raw.Light2 = {
	length = 0.34,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { 0, 28, 0, 0, -0.3, -0.1 }, Waist = { -6, 26, 0 }, Neck = { 0, -36, 0 },
			RHand = C(70, 1.15, 0.75), Blade = { 16, 150, 75 }, LHand = C(130, 1.2, -0.2),
			LFoot = { -0.15, 0, -0.9 }, RFoot = { 0.2, 0, 0.65 },
		} },
		{ t = 0.06, ease = "outQuad", pose = {
			Root = { 0, 32, 0, 0, -0.32, -0.1 }, RHand = C(78, 1.1, 0.8), Blade = { 18, 160, 75 },
		} },
		{ t = 0.11, ease = "outQuad", arc = true, pose = {
			Root = { -6, -22, 0, 0, -0.38, -0.3 }, Waist = { -10, -26, 0 }, Neck = { 0, 34, 0 },
			RHand = C(-30, 2.15, 0.1), Blade = { -4, -62, 85 }, LHand = C(40, 1.4, -0.1),
			LFoot = { -0.25, 0, -0.75 }, RFoot = { 0.15, 0, 1.0 },
		} },
		{ t = 0.19, ease = "outQuad", arc = true, pose = {
			Root = { -4, -28, 0, 0, -0.34, -0.3 }, Waist = { -8, -32, 0 }, Neck = { 0, 42, 0 },
			RHand = C(-80, 1.95, 0.0), Blade = { -12, -122, 85 },
		} },
		{ t = 0.34, ease = "inOut", arc = true, pose = {
			Root = { 0, -16, 0, 0, -0.26, -0.1 }, Waist = { -5, -4, 0 }, Neck = { 0, 16, 0 },
			RHand = C(-36, 1.65, -0.3), Blade = { 22, -10, 30 }, LHand = C(18, 1.35, -0.15),
		} },
	},
}

-- Light 3: crouch, then a hopping 360 spin slash (finisher).
raw.Light3 = {
	length = 0.56,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { -8, -40, 0, 0, -0.55, 0 }, Waist = { -14, -26, 0 }, Neck = { 6, 46, 0 },
			RHand = C(-140, 1.5, -0.2), Blade = { -4, -168, -80 }, LHand = C(40, 1.4, 0.1),
			LFoot = { -0.4, 0, -0.7 }, RFoot = { 0.4, 0, 0.6 },
		} },
		{ t = 0.12, ease = "outQuad", pose = {
			Root = { -10, -46, 0, 0, -0.62, 0 }, RHand = C(-146, 1.5, -0.2), Blade = { -4, -174, -80 },
		} },
		{ t = 0.17, ease = "linear", arc = true, pose = {
			Root = { -6, 60, 0, 0, 0.1, 0 }, Waist = { -6, 10, 0 }, Neck = { 0, 0, 0 },
			RHand = C(-70, 2.15, 0.15), Blade = { -6, -80, -85 }, LHand = C(110, 1.5, 0.3),
			LFoot = { -0.4, 0.35, -0.3 }, RFoot = { 0.4, 0.55, 0.3 },
		} },
		{ t = 0.21, ease = "linear", pose = { Root = { -6, 180, 0, 0, 0.35, 0 } } },
		{ t = 0.25, ease = "linear", pose = { Root = { -6, 300, 0, 0, 0.25, 0 } } },
		{ t = 0.29, ease = "outQuad", arc = true, pose = {
			Root = { -12, 372, 0, 0, -0.45, 0 }, Waist = { -12, 14, 0 },
			RHand = C(-10, 2.0, 0.0), Blade = { -10, 5, -85 },
			LFoot = { -0.45, 0, -0.75 }, RFoot = { 0.45, 0, 0.65 },
		} },
		{ t = 0.56, ease = "inOut", arc = true, pose = with(READY, { Root = { 0, -10, 0, 0, -0.26, 0 } }) },
	},
}

-- Heavy Slam: drop, rise with the blade overhead in both hands, hang, then slam into the floor.
raw.Heavy = {
	length = 0.92,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { -10, 0, 0, 0, -0.5, 0.1 }, Waist = { -16, 0, 0 }, Neck = { 10, 0, 0 },
			RHand = { 0.45, -1.0, -1.0 }, Blade = { -40, -4, 0 }, Hilt = 1,
			LFoot = { -0.3, 0, -0.5 }, RFoot = { 0.3, 0, 0.5 },
		} },
		{ t = 0.16, ease = "outCubic", pose = {
			Root = { 4, 0, 0, 0, 0.12, 0.15 }, Waist = { 8, 0, 0 }, Neck = { -4, 0, 0 },
			RHand = { 0.25, 2.35, 0.55 }, Blade = { 128, 0, 0 },
			LFoot = { -0.25, 0, -0.45 }, RFoot = { 0.25, 0, 0.55 },
		} },
		{ t = 0.33, ease = "linear", pose = {
			Root = { 5, 0, 0, 0, 0.18, 0.2 }, Waist = { 11, 0, 0 },
			RHand = { 0.25, 2.45, 0.75 }, Blade = { 138, 0, 0 },
		} },
		{ t = 0.37, ease = "inCubic", pose = {
			Root = { -4, 0, 0, 0, -0.1, -0.2 }, Waist = { -8, 0, 0 },
			RHand = { 0.25, 2.1, -1.5 }, Blade = { 70, 0, 0 },
		} },
		{ t = 0.4, ease = "linear", pose = {
			Root = { -14, 0, 0, 0, -0.7, -0.6 }, Waist = { -34, 0, 0 }, Neck = { 26, 0, 0 },
			RHand = { 0.25, -1.45, -2.05 }, Blade = { -20, 0, 0 },
			LFoot = { -0.3, 0, -1.25 }, RFoot = { 0.3, 0, 0.95 },
		} },
		{ t = 0.6, ease = "linear", pose = {
			Root = { -13, 0, 0, 0, -0.72, -0.6 }, Waist = { -32, 0, 0 },
		} },
		{ t = 0.92, ease = "inOut", pose = READY },
	},
}

-- Dash: squash down, stretch forward low with arms swept back, then land.
raw.Dash = {
	length = 0.27,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { -30, 0, 0, 0, -0.55, 0.2 }, Waist = { -12, 0, 0 }, Neck = { 22, 0, 0 },
			RHand = { 1.1, -0.7, 1.1 }, Blade = { -25, -165, 0 }, LHand = { -1.1, -0.6, 1.0 },
			LFoot = { -0.2, 0.25, -0.5 }, RFoot = { 0.2, 0.6, 1.0 },
		} },
		{ t = 0.12, ease = "outQuad", pose = {
			Root = { -38, 0, 0, 0, -0.25, -0.2 }, Waist = { -10, 0, 0 },
			RHand = { 1.15, -0.5, 1.4 }, LHand = { -1.15, -0.4, 1.3 },
			LFoot = { -0.2, 0.45, -0.2 }, RFoot = { 0.2, 0.7, 1.2 },
		} },
		{ t = 0.27, ease = "inOut", pose = with(READY, {
			Root = { -12, -8, 0, 0, -0.4, 0 }, Waist = { -8, 4, 0 }, Neck = { 6, 4, 0 },
			LFoot = { -0.2, 0, -0.6 }, RFoot = { 0.2, 0, 0.6 },
		}) },
	},
}

-- Parry: snap into a braced guard with the blade angled across the body.
local PARRY = {
	Root = { 4, 18, 0, 0, -0.38, 0.15 }, Waist = { 0, 20, 0 }, Neck = { -4, -30, 0 },
	RHand = { 0.55, -0.05, -1.35 }, Blade = { 52, 38, 75 }, LHand = { -0.35, 0.35, -1.45 },
	LFoot = { -0.3, 0, -0.45 }, RFoot = { 0.3, 0, 0.6 },
}
raw.Parry = {
	length = 0.46,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = PARRY },
		{ t = 0.17, ease = "linear", pose = { Root = { 6, 18, 0, 0, -0.4, 0.2 } } },
		{ t = 0.46, ease = "inOut", pose = READY },
	},
}

-- Riposte: the deflect flick that plays right after a successful parry.
raw.Riposte = {
	length = 0.32,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = PARRY },
		{ t = 0.07, ease = "outExpo", arc = true, pose = {
			Root = { -4, -20, 0, 0, -0.34, -0.1 }, Waist = { -6, -22, 0 }, Neck = { 0, 28, 0 },
			RHand = C(-15, 2.1, 0.25), Blade = { 8, -40, -70 }, LHand = C(90, 1.2, -0.3),
		} },
		{ t = 0.32, ease = "inOut", pose = READY },
	},
}

-- Hurt: knocked back off balance.
raw.Hurt = {
	length = 0.32,
	keys = {
		{ t = 0.0, ease = "outExpo", pose = {
			Root = { 20, 0, 0, 0, -0.3, 0.35 }, Waist = { 18, 0, 0 }, Neck = { 22, 0, 0 },
			RHand = { 1.6, 0.1, 0.2 }, Blade = { 45, -70, 0 }, LHand = { -1.6, 0.1, 0.2 },
			LFoot = { -0.25, 0, -0.2 }, RFoot = { 0.25, 0, 0.6 },
		} },
		{ t = 0.32, ease = "inOut", pose = READY },
	},
}

Player.clips = {}
for name, r in raw do
	Player.clips[name] = AnimCore.compile(r, Player.Ready)
end

-- Run pose pieces that do not depend on phase: lean in, blade trailing low behind.
local RUN_BASE = P({
	Root = { -12, 0, 0, 0, -0.32, 0 },
	Waist = { -6, 0, 0 },
	Neck = { 10, 0, 0 },
	RHand = { 1.05, -0.75, 0.35 },
	Blade = { -28, -160, 0 },
	LHand = { -1.05, -0.5, -0.3 },
}, Player.Ready)

-- st = { t, speed, moveLocal (unit vector in root space), phase }
-- Returns the locomotion pose (idle breathing blended with the run cycle).
function Player.locomotion(st)
	local breathe = sin(st.t * 2.2)
	local idle = AnimCore.copy(Player.Ready)
	AnimCore.addPre(idle, "Waist", CFrame.Angles(math.rad(breathe * 1.4), 0, 0))
	AnimCore.addPre(idle, "Root", CFrame.new(0, breathe * 0.03, 0))
	idle.hand.R = idle.hand.R + Vector3.new(0, breathe * 0.04, 0)
	idle.blade = idle.blade + Vector3.new(breathe * 1.5, 0, 0)

	local run01 = math.clamp(st.speed / 20, 0, 1)
	if run01 < 0.02 then
		return idle
	end

	local ph = st.phase
	local mv = st.moveLocal
	local stride = 1.35
	local lift = 0.75
	local run = AnimCore.copy(RUN_BASE)
	local cL, cR = cos(ph), cos(ph + math.pi)
	local sL, sR = sin(ph), sin(ph + math.pi)
	local mvFlat = Vector3.new(mv.X, 0, mv.Z)
	run.feet.L = Vector3.new(-0.05, lift * math.max(0, -sL), 0) + mvFlat * (stride * cL)
	run.feet.R = Vector3.new(0.05, lift * math.max(0, -sR), 0) + mvFlat * (stride * cR)
	local bob = abs(cL) * 0.16
	AnimCore.addPre(run, "Root", CFrame.new(0, bob, 0) * CFrame.Angles(0, math.rad(cL * 6), 0))
	AnimCore.addPre(run, "Waist", CFrame.Angles(0, math.rad(-cL * 10), 0))
	run.hand.L = run.hand.L + Vector3.new(0, 0.2 * abs(cL), 0.75 * cL)
	run.hand.R = run.hand.R + Vector3.new(0, 0.1 * abs(cR), 0.25 * cR)
	return AnimCore.blend(idle, run, run01)
end

-- How far (studs) the body travels per full run cycle.
Player.cycleDistance = 7.2

------------------------------------------------------------------------------------------------
-- Brute
------------------------------------------------------------------------------------------------
local Brute = {}
Clips.Brute = Brute

Brute.Idle = P({
	Root = { 0, 0, 0 },
	Waist = { -16, 0, 0 },
	Neck = { 14, 0, 0 },
	RShoulder = { 8, 0, 8 },
	RElbow = { 16, 0, 0 },
	LShoulder = { 8, 0, -8 },
	LElbow = { 16, 0, 0 },
	RHip = { 0, 0, 0 },
	LHip = { 0, 0, 0 },
})

local braw = {}

-- Windup is normalized to length 1: the client maps the real windup time onto it.
braw.Windup = {
	length = 1,
	keys = {
		{ t = 0.0, ease = "outQuad", pose = {
			Root = { 0, 0, 0, 0, -0.3, 0 }, Waist = { -24, 0, 0 },
			RShoulder = { 20, 0, 20 }, LShoulder = { 20, 0, -20 },
		} },
		{ t = 0.45, ease = "outCubic", pose = {
			Root = { 8, 0, 0, 0, 0.35, 0.3 }, Waist = { 14, 0, 0 }, Neck = { -4, 0, 0 },
			RShoulder = { 160, -12, 26 }, RElbow = { 34, 0, 0 },
			LShoulder = { 160, 12, -26 }, LElbow = { 34, 0, 0 },
			RHip = { -8, 0, 4 }, LHip = { 12, 0, -4 },
		} },
		{ t = 1.0, ease = "linear", pose = {
			Root = { 10, 0, 0, 0, 0.45, 0.4 }, Waist = { 18, 0, 0 },
			RShoulder = { 168, -12, 26 }, RElbow = { 40, 0, 0 },
			LShoulder = { 168, 12, -26 }, LElbow = { 40, 0, 0 },
		} },
	},
}

braw.Strike = {
	length = 0.25,
	keys = {
		{ t = 0.0, ease = "linear", pose = {
			Root = { 10, 0, 0, 0, 0.45, 0.4 }, Waist = { 18, 0, 0 }, Neck = { -4, 0, 0 },
			RShoulder = { 168, -12, 26 }, RElbow = { 40, 0, 0 },
			LShoulder = { 168, 12, -26 }, LElbow = { 40, 0, 0 },
			RHip = { -8, 0, 4 }, LHip = { 12, 0, -4 },
		} },
		{ t = 0.07, ease = "inQuart", pose = {
			Root = { -14, 0, 0, 0, -0.9, -0.9 }, Waist = { -42, 0, 0 }, Neck = { 30, 0, 0 },
			RShoulder = { 62, -16, 10 }, RElbow = { 4, 0, 0 },
			LShoulder = { 62, 16, -10 }, LElbow = { 4, 0, 0 },
			RHip = { -14, 0, 6 }, LHip = { 24, 0, -6 },
		} },
		{ t = 0.25, ease = "linear", pose = {
			Root = { -13, 0, 0, 0, -0.85, -0.85 }, Waist = { -40, 0, 0 },
		} },
	},
}

braw.Recover = {
	length = 0.75,
	keys = {
		{ t = 0.0, ease = "linear", pose = {
			Root = { -13, 0, 0, 0, -0.85, -0.85 }, Waist = { -40, 0, 0 }, Neck = { 30, 0, 0 },
			RShoulder = { 62, -16, 10 }, RElbow = { 4, 0, 0 },
			LShoulder = { 62, 16, -10 }, LElbow = { 4, 0, 0 },
			RHip = { -14, 0, 6 }, LHip = { 24, 0, -6 },
		} },
		{ t = 0.45, ease = "inOut", pose = {
			Root = { -8, 0, 0, 0, -0.6, -0.5 }, Waist = { -32, 0, 0 },
			RShoulder = { 40, -10, 10 }, LShoulder = { 40, 10, -10 },
		} },
		{ t = 0.75, ease = "inOut", pose = {
			Root = { 0, 0, 0 }, Waist = { -16, 0, 0 }, Neck = { 14, 0, 0 },
			RShoulder = { 8, 0, 8 }, RElbow = { 16, 0, 0 },
			LShoulder = { 8, 0, -8 }, LElbow = { 16, 0, 0 },
			RHip = { 0, 0, 0 }, LHip = { 0, 0, 0 },
		} },
	},
}

-- Spawn: climbs up out of the portal.
braw.Spawn = {
	length = 1.0,
	keys = {
		{ t = 0.0, ease = "linear", pose = {
			Root = { -30, 0, 0, 0, -2.6, 0 }, Waist = { -30, 0, 0 }, Neck = { 30, 0, 0 },
			RShoulder = { 90, 0, 30 }, LShoulder = { 90, 0, -30 },
		} },
		{ t = 0.7, ease = "outCubic", pose = {
			Root = { 6, 0, 0, 0, 0.2, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 },
			RShoulder = { 40, 0, 60 }, RElbow = { 60, 0, 0 },
			LShoulder = { 40, 0, -60 }, LElbow = { 60, 0, 0 },
		} },
		{ t = 1.0, ease = "inOut", pose = {
			Root = { 0, 0, 0 }, Waist = { -16, 0, 0 }, Neck = { 14, 0, 0 },
			RShoulder = { 8, 0, 8 }, RElbow = { 16, 0, 0 },
			LShoulder = { 8, 0, -8 }, LElbow = { 16, 0, 0 },
		} },
	},
}

Brute.clips = {}
for name, r in braw do
	Brute.clips[name] = AnimCore.compile(r, Brute.Idle)
end

-- st = { t, speed, phase }
function Brute.locomotion(st)
	local breathe = sin(st.t * 1.6)
	local p = AnimCore.copy(Brute.Idle)
	AnimCore.addPre(p, "Waist", CFrame.Angles(math.rad(breathe * 2.5), 0, 0))
	AnimCore.addPre(p, "Root", CFrame.new(0, breathe * 0.05, 0))
	local w = math.clamp(st.speed / 12, 0, 1)
	if w > 0.02 then
		local ph = st.phase
		local s = sin(ph)
		AnimCore.addPre(p, "RHip", CFrame.Angles(math.rad(s * 28 * w), 0, 0))
		AnimCore.addPre(p, "LHip", CFrame.Angles(math.rad(-s * 28 * w), 0, 0))
		AnimCore.addPre(p, "RShoulder", CFrame.Angles(math.rad(-s * 22 * w), 0, 0))
		AnimCore.addPre(p, "LShoulder", CFrame.Angles(math.rad(s * 22 * w), 0, 0))
		AnimCore.addPre(p, "Root", CFrame.new(0, abs(cos(ph)) * 0.25 * w - 0.1 * w, 0) * CFrame.Angles(0, 0, math.rad(s * 5 * w)))
		AnimCore.addPre(p, "Waist", CFrame.Angles(math.rad(-6 * w), math.rad(s * 8 * w), 0))
	end
	return p
end

Brute.cycleDistance = 9

-- Stunned: dazed wobble (procedural, loops).
function Brute.stunned(t)
	local p = AnimCore.copy(Brute.Idle)
	p.j.Root = CFrame.new(0, -0.5, 0.3) * CFrame.Angles(math.rad(8), 0, math.rad(sin(t * 5) * 6))
	p.j.Waist = CFrame.Angles(math.rad(-30 + sin(t * 3) * 4), math.rad(sin(t * 2.4) * 12), 0)
	p.j.Neck = CFrame.Angles(math.rad(30), math.rad(sin(t * 4.2) * 25), math.rad(cos(t * 3.3) * 15))
	p.j.RShoulder = CFrame.Angles(math.rad(-4 + sin(t * 3) * 6), 0, math.rad(4))
	p.j.LShoulder = CFrame.Angles(math.rad(-4 - sin(t * 3) * 6), 0, math.rad(-4))
	p.j.RElbow = CFrame.Angles(math.rad(8), 0, 0)
	p.j.LElbow = CFrame.Angles(math.rad(8), 0, 0)
	return p
end

-- Keep MathUtil referenced for consumers that use Clips as their only animation import.
Clips.MathUtil = MathUtil

return Clips
