--!nonstrict
-- MathUtil: easing curves, smoothing, springs and angle helpers shared by client, server and the preview tool.
-- Pure Luau (no Roblox services) so it can also run outside Roblox.

local MathUtil = {}

local TAU = math.pi * 2

function MathUtil.lerp(a, b, t)
	return a + (b - a) * t
end

-- 0..1 position of v between a and b, clamped.
function MathUtil.remap01(a, b, v)
	if b == a then
		return if v >= b then 1 else 0
	end
	return math.clamp((v - a) / (b - a), 0, 1)
end

-- Frame-rate independent exponential smoothing: higher sharpness = snappier.
function MathUtil.damp(current, target, sharpness, dt)
	return current + (target - current) * (1 - math.exp(-sharpness * dt))
end

-- Shortest signed difference b - a for angles in radians.
function MathUtil.angleDiff(a, b)
	return (b - a + math.pi) % TAU - math.pi
end

function MathUtil.dampAngle(current, target, sharpness, dt)
	return current + MathUtil.angleDiff(current, target) * (1 - math.exp(-sharpness * dt))
end

-- Yaw (radians, about +Y) whose CFrame.Angles(0, yaw, 0).LookVector points along dir (X/Z only).
function MathUtil.yawFromDir(dir)
	return math.atan2(-dir.X, -dir.Z)
end

function MathUtil.dirFromYaw(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function MathUtil.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

-- Implicit-Euler critically damped spring. Works for numbers and Vector3.
-- omega ~ responsiveness (rad/s). Returns new position, new velocity.
function MathUtil.spring(x, v, target, omega, dt)
	local f = 1 + 2 * dt * omega
	local oo = omega * omega
	local hoo = dt * oo
	local hhoo = dt * hoo
	local detInv = 1 / (f + hhoo)
	local nx = (x * f + v * dt + target * hhoo) * detInv
	local nv = (v + (target - x) * hoo) * detInv
	return nx, nv
end

-- Easing functions, t in 0..1 -> 0..1
local Ease = {}
Ease.linear = function(t)
	return t
end
Ease.inQuad = function(t)
	return t * t
end
Ease.outQuad = function(t)
	return 1 - (1 - t) * (1 - t)
end
Ease.inOut = function(t)
	return if t < 0.5 then 2 * t * t else 1 - ((-2 * t + 2) ^ 2) / 2
end
Ease.inCubic = function(t)
	return t * t * t
end
Ease.outCubic = function(t)
	return 1 - (1 - t) ^ 3
end
Ease.inOutCubic = function(t)
	return if t < 0.5 then 4 * t * t * t else 1 - ((-2 * t + 2) ^ 3) / 2
end
Ease.outQuart = function(t)
	return 1 - (1 - t) ^ 4
end
Ease.inQuart = function(t)
	return t ^ 4
end
Ease.outExpo = function(t)
	return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
end
Ease.inExpo = function(t)
	return if t <= 0 then 0 else 2 ^ (10 * t - 10)
end
Ease.outBack = function(t)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
-- Hold the previous key, then jump at the very end (for snaps).
Ease.step = function(t)
	return if t >= 1 then 1 else 0
end
MathUtil.Ease = Ease

-- 1D smooth noise in -1..1 used for camera shake, seeded per channel.
function MathUtil.noise1(t, seed)
	return math.noise(t, seed * 13.37, 0.5) * 2
end

-- Rotate vector v around unit axis k by angle a (Rodrigues).
function MathUtil.rotateAround(v, k, a)
	local c, s = math.cos(a), math.sin(a)
	return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
end

return MathUtil
