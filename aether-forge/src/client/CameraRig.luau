--!nonstrict
-- CameraRig: angled arena camera that follows the player, with game-feel layers:
--   trauma shake (strength grows with trauma squared, smooth noise), directional kick (spring),
--   FOV punch (spring), slight lead toward where you move/aim, mouse-wheel zoom.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AetherForge")
local Config = require(Shared.Config)
local MathUtil = require(Shared.MathUtil)

local CameraRig = {}

local trauma = 0
local focus = nil
local focusVel = Vector3.zero
local kick, kickVel = Vector3.zero, Vector3.zero
local fov, fovVel = 0, 0
local lead = Vector3.zero
local zoom = 0 -- mouse-wheel offset on top of Config.Camera.Distance
local t = 0
local getTarget -- function() -> (position, leadDir)

function CameraRig.shake(amount)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- Push the camera along a world direction (it springs back).
function CameraRig.kick(dir, strength)
	kickVel += dir * strength * 60
end

-- Negative = zoom in for a moment.
function CameraRig.punch(amount)
	fovVel += amount * 60
end

local function update(dt)
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	t += dt
	local cfg = Config.Camera
	local pos, leadDir = getTarget()
	if not pos then
		return
	end
	lead = MathUtil.damp(lead, (leadDir or Vector3.zero) * cfg.Lead, 4, dt)
	local goal = pos + lead
	if not focus then
		focus = goal
	end
	focus, focusVel = MathUtil.spring(focus, focusVel, goal, cfg.FollowSharpness, dt)

	kick, kickVel = MathUtil.spring(kick, kickVel, Vector3.zero, 22, dt)
	fov, fovVel = MathUtil.spring(fov, fovVel, 0, 18, dt)
	trauma = math.max(0, trauma - cfg.TraumaDecay * dt)

	local pitch = math.rad(cfg.Pitch)
	local distance = math.clamp(cfg.Distance + zoom, cfg.MinDistance, cfg.MaxDistance)
	zoom = distance - cfg.Distance
	local back = Vector3.new(0, math.sin(pitch), math.cos(pitch)) * distance
	local cf = CFrame.lookAt(focus + back + kick, focus + kick)

	local s = trauma * trauma
	if s > 0 then
		local f = cfg.ShakeFrequency
		local ox = MathUtil.noise1(t * f, 1) * cfg.ShakeMaxOffset * s
		local oy = MathUtil.noise1(t * f, 2) * cfg.ShakeMaxOffset * s
		local roll = MathUtil.noise1(t * f, 3) * math.rad(cfg.ShakeMaxRoll) * s
		cf = cf * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, roll)
	end
	cam.CFrame = cf
	cam.FieldOfView = math.clamp(cfg.FOV + fov, 20, 100)
end

function CameraRig.init(targetFn)
	getTarget = targetFn
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom -= input.Position.Z * 3
		end
	end)
	RunService:BindToRenderStep("AetherCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

function CameraRig.snap()
	focus = nil
end

return CameraRig
