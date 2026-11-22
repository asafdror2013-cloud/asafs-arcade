--!nonstrict
-- AnimCore: the procedural animation engine (pure math, no Roblox instances).
--
-- A pose holds:
--   j      Motor6D.Transform values for directly-posed joints (Root, Waist, Neck, ...)
--   feet   { L, R } foot-target offsets from the rest ankle            (legs are solved with IK)
--   hand   { L, R } hand targets, absolute, relative to the root part   (arms are solved with IK)
--   pole   { L, R } which way each elbow should point
--   blade  Vector3(pitch, yaw, roll) in degrees: where the weapon points (the wrist is solved)
--   hilt   0..1, how much the left hand grips the hilt (two-handed moves)
-- feet/hand/pole/blade live in "root-yaw space": they turn with the Root joint's yaw (so spins carry
-- the body around) but ignore its pitch and height (so leans and crouches keep feet planted).
-- Rigs without `legs`/`arms` (the Brute) are posed purely by joint angles.
--
-- Clips are keyframes. Joint = { x, y, z, px, py, pz } degrees/studs; RHand/LHand = { x, y, z };
-- RPole/LPole = { x, y, z }; Blade = { pitch, yaw, roll }; Hilt = number. Anything missing in a key
-- holds the previous key (or the clip's base pose). A key with arc = true moves the hands along an
-- arc around the body instead of a straight line (use it for slashes).

local MathUtil = require(script.Parent.MathUtil)

local AnimCore = {}

local rad = math.rad
local Ease = MathUtil.Ease
local ZERO = Vector3.new(0, 0, 0)

function AnimCore.angles(a)
	local c = CFrame.fromEulerAnglesYXZ(rad(a[1] or 0), rad(a[2] or 0), rad(a[3] or 0))
	if a[4] or a[5] or a[6] then
		c = CFrame.new(a[4] or 0, a[5] or 0, a[6] or 0) * c
	end
	return c
end

function AnimCore.newPose()
	return {
		j = {},
		feet = { L = ZERO, R = ZERO },
		hand = {},
		pole = {},
		blade = nil,
		hilt = 0,
	}
end

function AnimCore.copy(p)
	return {
		j = table.clone(p.j),
		feet = { L = p.feet.L, R = p.feet.R },
		hand = { L = p.hand.L, R = p.hand.R },
		pole = { L = p.pole.L, R = p.pole.R },
		blade = p.blade,
		hilt = p.hilt,
	}
end

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- Build a pose from an authoring table (on top of an optional base pose).
function AnimCore.pose(def, base)
	local p = if base then AnimCore.copy(base) else AnimCore.newPose()
	for name, v in def do
		if name == "LFoot" then
			p.feet.L = v3(v)
		elseif name == "RFoot" then
			p.feet.R = v3(v)
		elseif name == "RHand" then
			p.hand.R = v3(v)
		elseif name == "LHand" then
			p.hand.L = v3(v)
		elseif name == "RPole" then
			p.pole.R = v3(v)
		elseif name == "LPole" then
			p.pole.L = v3(v)
		elseif name == "Blade" then
			p.blade = v3(v)
		elseif name == "Hilt" then
			p.hilt = v
		else
			p.j[name] = AnimCore.angles(v)
		end
	end
	return p
end

-- Cylindrical helper for authoring: angle (deg, 0 = in front, + = to the left), radius, height.
function AnimCore.cyl(a, r, h)
	local ar = rad(a)
	return { -math.sin(ar) * r, h, -math.cos(ar) * r }
end

local function lerpArc(a, b, w)
	-- interpolate around the vertical axis (angle, radius, height) so hands travel on an arc
	local aa = math.atan2(-a.X, -a.Z)
	local ab = math.atan2(-b.X, -b.Z)
	local d = MathUtil.angleDiff(aa, ab)
	local ang = aa + d * w
	local ra = math.sqrt(a.X * a.X + a.Z * a.Z)
	local rb = math.sqrt(b.X * b.X + b.Z * b.Z)
	local r = ra + (rb - ra) * w
	return Vector3.new(-math.sin(ang) * r, a.Y + (b.Y - a.Y) * w, -math.cos(ang) * r)
end

local function lerpV(a, b, w, arc)
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	if arc then
		return lerpArc(a, b, w)
	end
	return a:Lerp(b, w)
end

-- raw = { length = n, loop = bool?, keys = { { t = n, ease = "outCubic"?, arc = bool?, pose = {...} } } }
function AnimCore.compile(raw, base)
	local keys = {}
	local prev = base or AnimCore.newPose()
	for i, k in raw.keys do
		local p = AnimCore.pose(k.pose, prev)
		local ease = Ease[k.ease or "inOut"]
		assert(ease, "unknown ease " .. tostring(k.ease))
		keys[i] = { t = k.t, ease = ease, arc = k.arc, pose = p }
		prev = p
	end
	return { length = raw.length, loop = raw.loop, keys = keys }
end

function AnimCore.blend(a, b, w, arc)
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local out = AnimCore.newPose()
	for name, ca in a.j do
		local cb = b.j[name]
		out.j[name] = if cb then ca:Lerp(cb, w) else ca
	end
	for name, cb in b.j do
		if out.j[name] == nil then
			out.j[name] = cb
		end
	end
	out.feet.L = a.feet.L:Lerp(b.feet.L, w)
	out.feet.R = a.feet.R:Lerp(b.feet.R, w)
	out.hand.R = lerpV(a.hand.R, b.hand.R, w, arc)
	out.hand.L = lerpV(a.hand.L, b.hand.L, w, arc)
	out.pole.R = lerpV(a.pole.R, b.pole.R, w)
	out.pole.L = lerpV(a.pole.L, b.pole.L, w)
	out.blade = lerpV(a.blade, b.blade, w)
	out.hilt = (a.hilt or 0) + ((b.hilt or 0) - (a.hilt or 0)) * w
	return out
end

function AnimCore.sample(clip, t)
	local keys = clip.keys
	if clip.loop and clip.length > 0 then
		t = t % clip.length
	end
	if t <= keys[1].t then
		return keys[1].pose
	end
	for i = 2, #keys do
		local k = keys[i]
		if t < k.t then
			local a = keys[i - 1]
			local span = k.t - a.t
			local u = if span > 0 then (t - a.t) / span else 1
			return AnimCore.blend(a.pose, k.pose, k.ease(u), k.arc)
		end
	end
	return keys[#keys].pose
end

-- Pre-multiply additive offsets (lean, flinch, jitter) onto a joint, in place.
function AnimCore.addPre(pose, joint, c)
	local cur = pose.j[joint] or CFrame.identity
	pose.j[joint] = c * cur
end

function AnimCore.addPost(pose, joint, c)
	local cur = pose.j[joint] or CFrame.identity
	pose.j[joint] = cur * c
end

local function yawOf(c)
	local look = c.LookVector
	if math.abs(look.Y) > 0.999 then
		return 0
	end
	return math.atan2(-look.X, -look.Z)
end
AnimCore.yawOf = yawOf

-- Two-bone IK in the parent's space. Returns the upper bone rotation and the middle joint angle.
-- Legs: the knee is pushed toward `pole` and bends with a negative angle.
-- Arms (flip = true): same geometry, but the frame is turned so the elbow bends with a positive
-- angle and the upper arm keeps its outward side facing out.
local function solve2Bone(root, target, pole, a, b, flip)
	local toT = target - root
	local dist = toT.Magnitude
	local dir = if dist > 1e-5 then toT / dist else Vector3.new(0, -1, 0)
	local d = math.clamp(dist, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local axis = dir:Cross(pole)
	if axis.Magnitude < 1e-4 then
		axis = Vector3.new(if flip then -1 else 1, 0, 0)
	else
		axis = axis.Unit
	end
	local cosA = (a * a + d * d - b * b) / (2 * a * d)
	local alpha = math.acos(math.clamp(cosA, -1, 1))
	local upperDir = MathUtil.rotateAround(dir, axis, alpha)
	local cosK = (a * a + b * b - d * d) / (2 * a * b)
	local inner = math.acos(math.clamp(cosK, -1, 1))
	local bend = -(math.pi - inner)
	local Y = -upperDir
	local X = axis
	if flip then
		X = -axis
		bend = -bend
	end
	local Z = X:Cross(Y)
	return CFrame.fromMatrix(ZERO, X, Y, Z), bend
end
AnimCore.solve2Bone = solve2Bone

local function boneNamed(rig, jointName)
	for _, b in rig.bones do
		if b.joint == jointName then
			return b
		end
	end
	return nil
end

-- Precompute what the IK needs from a rig definition.
function AnimCore.ikInfo(rig, joints)
	local rootPos = rig.root.pos
	local info = { legs = nil, arms = nil, grip = nil }
	if rig.legs then
		info.legs = {}
		for side, leg in rig.legs do
			info.legs[side] = {
				hip = leg.hip,
				knee = leg.knee,
				ankle = leg.ankle,
				thigh = leg.thigh,
				shin = leg.shin,
				hipPivot = joints[leg.hip].c0.Position, -- in hips space
				restAnkle = boneNamed(rig, leg.ankle).pivot - rootPos, -- in root space
			}
		end
	end
	if rig.arms then
		info.arms = {}
		for side, arm in rig.arms do
			info.arms[side] = {
				shoulder = arm.shoulder,
				elbow = arm.elbow,
				upper = arm.upper,
				fore = arm.fore,
				pivot = joints[arm.shoulder].c0.Position, -- in chest space
				defaultPole = arm.pole,
			}
		end
		info.grip = rig.grip
	end
	return info
end

local function inParent(joints, name, t)
	local j = joints[name]
	return j.c0 * t * j.c1:Inverse()
end

local HILT_OFFSET = Vector3.new(0, 0, 0.55)

-- Elbow direction that never lines up with the arm: elbows point down-and-out when the hand is
-- raised or level, and back-and-out when the hand is low. `dir` = shoulder->hand (root-yaw space).
local function autoPole(dir, side)
	local down = math.clamp((-dir.Y - 0.3) / 0.6, 0, 1)
	down = down * down * (3 - 2 * down)
	local high = Vector3.new(side * 0.5, -1, 0.25)
	local low = Vector3.new(side * 0.5, -0.2, 1)
	return high:Lerp(low, down).Unit
end
AnimCore.autoPole = autoPole

-- Final transforms for a rig: copies pose.j and fills in IK-driven joints.
function AnimCore.solve(pose, joints, ik)
	local out = table.clone(pose.j)
	if not ik or (not ik.legs and not ik.arms) then
		return out
	end
	local rootT = out.Root or CFrame.identity
	local hipsInRoot = inParent(joints, "Root", rootT)
	local yawC = CFrame.Angles(0, yawOf(rootT), 0)

	if ik.legs then
		local hipsRot = hipsInRoot.Rotation
		local poleRoot = yawC.LookVector
		for side, leg in ik.legs do
			local target = yawC * (leg.restAnkle + pose.feet[side])
			local targetInHips = hipsInRoot:PointToObjectSpace(target)
			local pole = hipsInRoot:VectorToObjectSpace(poleRoot)
			local hipRot, kneeAngle = solve2Bone(leg.hipPivot, targetInHips, pole, leg.thigh, leg.shin, false)
			local kneeRot = CFrame.Angles(kneeAngle, 0, 0)
			out[leg.hip] = hipRot
			out[leg.knee] = kneeRot
			out[leg.ankle] = (hipsRot * hipRot * kneeRot):Inverse() * yawC
		end
	end

	if ik.arms and pose.hand.R then
		local chestInRoot = hipsInRoot * inParent(joints, "Waist", out.Waist or CFrame.identity)
		local chestRot = chestInRoot.Rotation
		local bladeLocal = nil
		if pose.blade then
			local b = pose.blade
			bladeLocal = CFrame.fromEulerAnglesYXZ(rad(b.X), rad(b.Y), rad(b.Z))
		end
		for side, arm in ik.arms do
			local handLocal = pose.hand[side]
			if side == "L" and bladeLocal and pose.hilt > 0 and pose.hand.R then
				local hiltPos = pose.hand.R + bladeLocal:VectorToWorldSpace(HILT_OFFSET)
				handLocal = if handLocal then handLocal:Lerp(hiltPos, pose.hilt) else hiltPos
			end
			if handLocal then
				local target = yawC * handLocal
				local poleLocal = pose.pole[side]
				if not poleLocal then
					local shoulderYaw = yawC:PointToObjectSpace(chestInRoot * arm.pivot)
					local toHand = handLocal - shoulderYaw
					local dir = if toHand.Magnitude > 1e-4 then toHand.Unit else Vector3.new(0, -1, 0)
					poleLocal = autoPole(dir, if side == "R" then 1 else -1)
				end
				local poleRoot = yawC:VectorToWorldSpace(poleLocal)
				local targetInChest = chestInRoot:PointToObjectSpace(target)
				local poleInChest = chestInRoot:VectorToObjectSpace(poleRoot)
				local upRot, elbowAngle = solve2Bone(arm.pivot, targetInChest, poleInChest, arm.upper, arm.fore, true)
				out[arm.shoulder] = upRot
				out[arm.elbow] = CFrame.Angles(elbowAngle, 0, 0)
				if side == "R" and bladeLocal and ik.grip then
					local foreRot = chestRot * upRot * out[arm.elbow]
					out[ik.grip] = foreRot:Inverse() * yawC * bladeLocal
				end
			end
		end
	end
	return out
end

-- Root-space CFrames of every bone for a set of transforms (preview tool and debug views).
function AnimCore.boneWorld(rig, joints, transforms, rootCF)
	local world = { [rig.root.name] = rootCF }
	-- bones are listed parent-first in the rig definitions
	for _, b in rig.bones do
		local j = joints[b.joint]
		local t = transforms[b.joint] or CFrame.identity
		world[b.name] = world[b.parent] * j.c0 * t * j.c1:Inverse()
	end
	return world
end

return AnimCore
