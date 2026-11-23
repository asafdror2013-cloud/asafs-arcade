--!nonstrict
-- Minimal re-implementation of the Roblox math types (Vector3, CFrame, Color3) plus a `script`/require
-- emulation, so the game's pure shared modules (Rigs, AnimCore, Clips, Arena) run outside Roblox.
-- Matches Roblox semantics for everything those modules use.

local Shim = {}

------------------------------------------------------------------------ Vector3
local V3 = {}
V3.__index = function(v, k)
	if k == "X" then
		return rawget(v, 1)
	elseif k == "Y" then
		return rawget(v, 2)
	elseif k == "Z" then
		return rawget(v, 3)
	elseif k == "Magnitude" then
		return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	elseif k == "Unit" then
		local m = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
		return V3.new(v[1] / m, v[2] / m, v[3] / m)
	end
	local f = V3[k]
	if f == nil then
		error(tostring(k) .. " is not a valid member of Vector3", 2)
	end
	return f
end
function V3.new(x, y, z)
	return setmetatable({ x or 0, y or 0, z or 0 }, V3)
end
local vnew = V3.new
local function isV(v)
	return type(v) == "table" and getmetatable(v) == V3
end
V3.__add = function(a, b)
	return vnew(a[1] + b[1], a[2] + b[2], a[3] + b[3])
end
V3.__sub = function(a, b)
	return vnew(a[1] - b[1], a[2] - b[2], a[3] - b[3])
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return vnew(a * b[1], a * b[2], a * b[3])
	elseif type(b) == "number" then
		return vnew(a[1] * b, a[2] * b, a[3] * b)
	end
	return vnew(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return vnew(a[1] / b, a[2] / b, a[3] / b)
	end
	return vnew(a[1] / b[1], a[2] / b[2], a[3] / b[3])
end
V3.__unm = function(a)
	return vnew(-a[1], -a[2], -a[3])
end
V3.__eq = function(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
V3.__tostring = function(a)
	return string.format("%.3f, %.3f, %.3f", a[1], a[2], a[3])
end
function V3.Dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
function V3.Cross(a, b)
	return vnew(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
end
function V3.Lerp(a, b, t)
	return vnew(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
end
function V3.Abs(a)
	return vnew(math.abs(a[1]), math.abs(a[2]), math.abs(a[3]))
end
function V3.Max(a, b)
	return vnew(math.max(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3]))
end
function V3.Min(a, b)
	return vnew(math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3]))
end
function V3.Angle(a, b)
	local d = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / (math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) * math.sqrt(b[1] * b[1] + b[2] * b[2] + b[3] * b[3]))
	return math.acos(math.clamp(d, -1, 1))
end
function V3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a[1] - b[1]) < eps and math.abs(a[2] - b[2]) < eps and math.abs(a[3] - b[3]) < eps
end
local Vector3 = setmetatable({ new = vnew }, {
	__index = function(_, k)
		if k == "zero" then
			return vnew(0, 0, 0)
		elseif k == "one" then
			return vnew(1, 1, 1)
		elseif k == "xAxis" then
			return vnew(1, 0, 0)
		elseif k == "yAxis" then
			return vnew(0, 1, 0)
		elseif k == "zAxis" then
			return vnew(0, 0, 1)
		end
		return nil
	end,
})
Shim.Vector3 = Vector3

------------------------------------------------------------------------ CFrame
-- fields: p (Vector3) and r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } row-major
local CF = {}
local function cfraw(px, py, pz, r)
	return setmetatable({ px = px, py = py, pz = pz, r = r }, CF)
end
CF.__index = function(c, k)
	local r = rawget(c, "r")
	if k == "Position" or k == "p" then
		return vnew(c.px, c.py, c.pz)
	elseif k == "X" then
		return c.px
	elseif k == "Y" then
		return c.py
	elseif k == "Z" then
		return c.pz
	elseif k == "RightVector" or k == "XVector" then
		return vnew(r[1], r[4], r[7])
	elseif k == "UpVector" or k == "YVector" then
		return vnew(r[2], r[5], r[8])
	elseif k == "LookVector" then
		return vnew(-r[3], -r[6], -r[9])
	elseif k == "ZVector" then
		return vnew(r[3], r[6], r[9])
	elseif k == "Rotation" then
		return cfraw(0, 0, 0, r)
	end
	local f = CF[k]
	if f == nil then
		error(tostring(k) .. " is not a valid member of CFrame", 2)
	end
	return f
end

local function matmul(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end
local IDR = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

CF.__mul = function(a, b)
	local r = a.r
	if isV(b) then
		return vnew(
			r[1] * b[1] + r[2] * b[2] + r[3] * b[3] + a.px,
			r[4] * b[1] + r[5] * b[2] + r[6] * b[3] + a.py,
			r[7] * b[1] + r[8] * b[2] + r[9] * b[3] + a.pz
		)
	end
	local bp = b
	return cfraw(
		r[1] * bp.px + r[2] * bp.py + r[3] * bp.pz + a.px,
		r[4] * bp.px + r[5] * bp.py + r[6] * bp.pz + a.py,
		r[7] * bp.px + r[8] * bp.py + r[9] * bp.pz + a.pz,
		matmul(r, b.r)
	)
end
CF.__add = function(a, v)
	return cfraw(a.px + v[1], a.py + v[2], a.pz + v[3], a.r)
end
CF.__sub = function(a, v)
	return cfraw(a.px - v[1], a.py - v[2], a.pz - v[3], a.r)
end

function CF.Inverse(c)
	local r = c.r
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	local px, py, pz = c.px, c.py, c.pz
	return cfraw(
		-(t[1] * px + t[2] * py + t[3] * pz),
		-(t[4] * px + t[5] * py + t[6] * pz),
		-(t[7] * px + t[8] * py + t[9] * pz),
		t
	)
end
function CF.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CF.ToWorldSpace(a, b)
	return a * b
end
function CF.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CF.PointToWorldSpace(a, v)
	return a * v
end
function CF.VectorToWorldSpace(a, v)
	return a.Rotation * v
end
function CF.VectorToObjectSpace(a, v)
	return a.Rotation:Inverse() * v
end
function CF.GetComponents(c)
	local r = c.r
	return c.px, c.py, c.pz, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
function CF.ToEulerAnglesYXZ(c)
	local r = c.r
	local x = math.asin(math.clamp(-r[6], -1, 1))
	local y = math.atan2(r[3], r[9])
	local z = math.atan2(r[4], r[5])
	return x, y, z
end

-- quaternion helpers for Lerp
local function toQuat(r)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = table.unpack(r)
	local tr = m00 + m11 + m22
	local w, x, y, z
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w = 0.25 * s
		x = (m21 - m12) / s
		y = (m02 - m20) / s
		z = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		w = (m21 - m12) / s
		x = 0.25 * s
		y = (m01 + m10) / s
		z = (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		w = (m02 - m20) / s
		x = (m01 + m10) / s
		y = 0.25 * s
		z = (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		w = (m10 - m01) / s
		x = (m02 + m20) / s
		y = (m12 + m21) / s
		z = 0.25 * s
	end
	return w, x, y, z
end
local function fromQuat(w, x, y, z)
	local n = math.sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / n, x / n, y / n, z / n
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
	}
end
function CF.Lerp(a, b, t)
	local aw, ax, ay, az = toQuat(a.r)
	local bw, bx, by, bz = toQuat(b.r)
	local dot = aw * bw + ax * bx + ay * by + az * bz
	if dot < 0 then
		bw, bx, by, bz = -bw, -bx, -by, -bz
		dot = -dot
	end
	local w, x, y, z
	if dot > 0.9995 then
		w, x, y, z = aw + (bw - aw) * t, ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t
	else
		local th = math.acos(dot)
		local s = math.sin(th)
		local wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
		w, x, y, z = aw * wa + bw * wb, ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb
	end
	return cfraw(a.px + (b.px - a.px) * t, a.py + (b.py - a.py) * t, a.pz + (b.pz - a.pz) * t, fromQuat(w, x, y, z))
end

local CFrame = {}
function CFrame.new(a, b, c, ...)
	if a == nil then
		return cfraw(0, 0, 0, IDR)
	end
	if isV(a) then
		if b ~= nil then
			return CFrame.lookAt(a, b)
		end
		return cfraw(a[1], a[2], a[3], IDR)
	end
	local rest = { ... }
	if #rest == 9 then
		return cfraw(a, b, c, rest)
	end
	return cfraw(a, b, c, IDR)
end
function CFrame.Angles(rx, ry, rz)
	return cfraw(0, 0, 0, matmul(matmul(rotX(rx), rotY(ry)), rotZ(rz)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return cfraw(0, 0, 0, matmul(matmul(rotY(ry), rotX(rx)), rotZ(rz)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cfraw(pos[1], pos[2], pos[3], { vx[1], vy[1], vz[1], vx[2], vy[2], vz[2], vx[3], vy[3], vz[3] })
end
function CFrame.lookAt(at, target, up)
	up = up or vnew(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = vnew(1, 0, 0)
	else
		right = right.Unit
	end
	local upv = right:Cross(look).Unit
	return CFrame.fromMatrix(at, right, upv, -look)
end
function CFrame.fromAxisAngle(axis, a)
	local u = axis.Unit
	local s = math.sin(a / 2)
	return cfraw(0, 0, 0, fromQuat(math.cos(a / 2), u[1] * s, u[2] * s, u[3] * s))
end
setmetatable(CFrame, {
	__index = function(_, k)
		if k == "identity" then
			return cfraw(0, 0, 0, IDR)
		end
		return nil
	end,
})
Shim.CFrame = CFrame

------------------------------------------------------------------------ Color3
local C3 = {}
C3.__index = function(c, k)
	local f = rawget(C3, k)
	if f == nil then
		error(tostring(k) .. " is not a valid member of Color3", 2)
	end
	return f
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
local Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function C3.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end
function C3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
Shim.Color3 = Color3

------------------------------------------------------------------------ script / require
local cache = {}
local function dirname(p)
	return string.match(p, "^(.*)/[^/]*$") or "."
end
local makeProxy
local function proxyRequire(proxy)
	local path = rawget(proxy, "__path")
	if cache[path] ~= nil then
		return cache[path]
	end
	local src = readfile(path .. ".luau")
	local fn = loadchunk(src, path)
	local env = setmetatable({ script = proxy }, { __index = getfenv(1) })
	setfenv(fn, env)
	local result = fn()
	cache[path] = result
	return result
end
makeProxy = function(path)
	return setmetatable({ __path = path }, {
		__index = function(_, k)
			if k == "Parent" then
				return makeProxy(dirname(path))
			end
			return makeProxy(path .. "/" .. k)
		end,
	})
end

-- typeof() support for the emulator
function Shim.tag()
	rawset(V3, "__type", "Vector3")
	rawset(CF, "__type", "CFrame")
	rawset(C3, "__type", "Color3")
end

function Shim.install(env)
	env.Vector3 = Vector3
	env.CFrame = CFrame
	env.Color3 = Color3
	env.require = proxyRequire
end

function Shim.module(path)
	return proxyRequire(makeProxy(path))
end

function Shim.proxy(path)
	return makeProxy(path)
end

return Shim
