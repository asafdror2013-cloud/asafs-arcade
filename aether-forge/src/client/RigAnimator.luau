--!nonstrict
-- RigAnimator: plays AnimCore clips on a built rig by writing Motor6D.Transform every frame.
-- Layers: locomotion (idle/run) -> one action clip with fade in/out -> additive overlays
-- (lean, flinch, hitstop jitter) -> IK (legs, arms, wrist).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local AnimCore = require(Shared.AnimCore)
local MathUtil = require(Shared.MathUtil)
local Rigs = require(Shared.Rigs)
local RigBuilder = require(Shared.RigBuilder)

local RigAnimator = {}
RigAnimator.__index = RigAnimator

-- clipSet = Clips.Player or Clips.Brute (needs .clips, .locomotion, .cycleDistance)
function RigAnimator.new(model, rig, clipSet)
	local self = setmetatable({}, RigAnimator)
	self.model = model
	self.rig = rig
	self.clipSet = clipSet
	self.motors = RigBuilder.findMotors(model)
	self.joints = Rigs.computeJoints(rig)
	self.ik = AnimCore.ikInfo(rig, self.joints)
	self.t = 0
	self.phase = 0
	self.action = nil
	self.cross = nil
	self.lastOutput = nil
	self.lean = CFrame.identity
	self.flinch = 0
	self.flinchDir = Vector3.zero
	self.jitter = 0
	self.lastPose = nil
	self.frozen = false
	return self
end

-- Play a clip from the clip set. opts = { fadeIn, speed, startAt, hold }
-- The new clip crossfades from whatever pose is on screen (so combo chains never pop).
-- hold = true keeps the final pose until stop() (used for enemy states driven by server time).
function RigAnimator:play(name, opts)
	opts = opts or {}
	local clip = self.clipSet.clips[name]
	if not clip then
		return
	end
	local fade = opts.fadeIn or 0.05
	self.action = {
		name = name,
		clip = clip,
		t = opts.startAt or 0,
		speed = opts.speed or 1,
		hold = opts.hold,
	}
	if self.lastOutput and fade > 0 then
		self.cross = { pose = self.lastOutput, time = fade, left = fade }
	else
		self.cross = nil
	end
end

-- Pose an arbitrary clip at an explicit time (server-time driven enemy states).
function RigAnimator:setTime(name, t)
	if not self.action or self.action.name ~= name then
		self:play(name, { fadeIn = 0.06, hold = true, speed = 0 })
	end
	self.action.t = t
end

-- Blend back to locomotion.
function RigAnimator:stop(fadeOut)
	if self.action then
		self.action = nil
		local fade = fadeOut or 0.12
		if self.lastOutput and fade > 0 then
			self.cross = { pose = self.lastOutput, time = fade, left = fade }
		end
	end
end

function RigAnimator:isPlaying(name)
	return self.action ~= nil and (name == nil or self.action.name == name)
end

function RigAnimator:addFlinch(dirLocal, amount)
	self.flinchDir = dirLocal
	self.flinch = math.max(self.flinch, amount)
end

-- loco = { speed = number, moveLocal = Vector3 }, custom = optional pose override (e.g. stunned)
function RigAnimator:update(dt, loco, custom)
	if self.frozen then
		self:write(self.lastPose, true)
		return
	end
	self.t += dt
	local speed = loco and loco.speed or 0
	self.phase = (self.phase + speed * dt / self.clipSet.cycleDistance * math.pi * 2) % (math.pi * 2)

	local pose = custom
	if not pose then
		pose = self.clipSet.locomotion({
			t = self.t,
			speed = speed,
			moveLocal = loco and loco.moveLocal or Vector3.new(0, 0, -1),
			phase = self.phase,
		})
	end

	local a = self.action
	if a then
		a.t += dt * a.speed
		pose = AnimCore.sample(a.clip, a.t)
		if a.t >= a.clip.length and not a.hold then
			self.lastOutput = pose
			self:stop(0.12)
		end
	end

	local c = self.cross
	if c then
		c.left -= dt
		local w = math.clamp(1 - c.left / c.time, 0, 1)
		pose = AnimCore.blend(c.pose, pose, MathUtil.Ease.outQuad(w))
		if c.left <= 0 then
			self.cross = nil
		end
	end
	self.lastOutput = pose

	pose = AnimCore.copy(pose)
	-- overlays
	if self.lean ~= CFrame.identity then
		AnimCore.addPre(pose, "Root", self.lean)
	end
	if self.flinch > 0.001 then
		local f = self.flinch
		local d = self.flinchDir
		AnimCore.addPre(pose, "Root", CFrame.new(d.X * 0.25 * f, 0, d.Z * 0.25 * f) * CFrame.Angles(d.Z * 0.35 * f, 0, -d.X * 0.35 * f))
		AnimCore.addPre(pose, "Waist", CFrame.Angles(d.Z * 0.3 * f, 0, -d.X * 0.3 * f))
		self.flinch *= math.exp(-14 * dt)
	end
	self.lastPose = pose
	self:write(pose, false)
end

function RigAnimator:write(pose, jitter)
	if not pose then
		return
	end
	local transforms = AnimCore.solve(pose, self.joints, self.ik)
	if jitter and self.jitter > 0 then
		local j = self.jitter
		transforms.Root = CFrame.new((math.random() - 0.5) * j, (math.random() - 0.5) * j * 0.5, (math.random() - 0.5) * j) * (transforms.Root or CFrame.identity)
	end
	for name, motor in self.motors do
		local t = transforms[name]
		if t then
			motor.Transform = t
		end
	end
end

-- Freeze the current pose (hitstop) with an optional shake amount in studs.
function RigAnimator:freeze(on, jitter)
	self.frozen = on
	self.jitter = jitter or 0
end

return RigAnimator
