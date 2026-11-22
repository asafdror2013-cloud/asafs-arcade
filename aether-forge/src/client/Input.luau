--!nonstrict
-- Input: binds the four core moves for mouse+keyboard, gamepad and touch, buffers presses, and
-- works out the aim direction.
--   Light  LMB / ButtonX / touch       Heavy  RMB / ButtonY / touch
--   Dash   Space or Shift / ButtonA    Parry  F / ButtonB or R1 / touch

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherForge").Config)

local Input = {}
Input.buffer = {} -- { action, time }
Input.usingMouse = true
Input.listeners = {}

local clock -- set in init (Clock module) so buffering uses real time

local function push(action)
	table.insert(Input.buffer, { action = action, time = clock.real })
	for _, fn in Input.listeners do
		fn(action)
	end
end

local function bind(name, action, title, position, ...)
	ContextActionService:BindActionAtPriority(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			push(action)
		end
		return Enum.ContextActionResult.Sink
	end, true, 3000, ...)
	ContextActionService:SetTitle(name, title)
	ContextActionService:SetPosition(name, position)
end

function Input.init(clockModule)
	clock = clockModule
	bind("AF_Light", "Light", "Slash", UDim2.new(1, -170, 1, -120), Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
	bind("AF_Heavy", "Heavy", "Slam", UDim2.new(1, -95, 1, -190), Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonY)
	bind("AF_Dash", "Dash", "Dash", UDim2.new(1, -95, 1, -115), Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonA)
	bind("AF_Parry", "Parry", "Parry", UDim2.new(1, -170, 1, -195), Enum.KeyCode.F, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR1)

	UserInputService.LastInputTypeChanged:Connect(function(t)
		if t == Enum.UserInputType.Touch or t.Name:sub(1, 7) == "Gamepad" then
			Input.usingMouse = false
		elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Keyboard then
			Input.usingMouse = true
		end
	end)
end

-- Take the oldest buffered press of `action` that is still fresh.
function Input.peek(action)
	local now = clock.real
	for i = #Input.buffer, 1, -1 do
		if now - Input.buffer[i].time > Config.Feel.InputBuffer then
			table.remove(Input.buffer, i)
		end
	end
	for _, b in Input.buffer do
		if action == nil or b.action == action then
			return b
		end
	end
	return nil
end

function Input.consume(entry)
	local i = table.find(Input.buffer, entry)
	if i then
		table.remove(Input.buffer, i)
	end
end

function Input.clear()
	table.clear(Input.buffer)
end

-- World-space flat aim direction from the character root.
-- Mouse: toward the cursor on the floor. Gamepad/touch: the stick direction, else current facing.
function Input.aimDirection(rootPos, moveDir, facing)
	if Input.usingMouse then
		local cam = workspace.CurrentCamera
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		local floorY = rootPos.Y - 3
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (floorY - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				local hit = ray.Origin + ray.Direction * t
				local d = Vector3.new(hit.X - rootPos.X, 0, hit.Z - rootPos.Z)
				if d.Magnitude > 0.5 then
					return d.Unit
				end
			end
		end
	end
	if moveDir and moveDir.Magnitude > 0.1 then
		return Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	end
	return facing
end

function Input.player()
	return Players.LocalPlayer
end

return Input
