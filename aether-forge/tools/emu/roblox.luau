--!nonstrict
-- A small Roblox emulator for headless smoke tests. It runs the real server and client scripts in
-- one process with separate server/client contexts and module caches, and validates every
-- property/method/event access against Roblox's API dump (unknown members, read-only writes, wrong
-- value types and deprecated members are reported). Physics is a simple kinematic step.

local Emu = {}
Emu.errors = {}
Emu.warnings = {}
Emu.time = 0
Emu.frame = 0
Emu.context = "server"
local warned = {}

local API -- set by Emu.init

local seenErrors = {}
local function report(msg)
	local key = string.match(msg, "^[^\n]*") or msg
	if seenErrors[key] then
		seenErrors[key] += 1
		return
	end
	seenErrors[key] = 1
	table.insert(Emu.errors, msg)
	print("[EMU ERROR] " .. msg)
end
Emu.errorCounts = seenErrors
Emu.report = report

local function warnOnce(key, msg)
	if not warned[key] then
		warned[key] = true
		table.insert(Emu.warnings, msg)
	end
end

------------------------------------------------------------------------ datatypes
local Shim
local DT = {}

local function datatype(name, fields, mt)
	mt = mt or {}
	mt.__type = name
	mt.__index = mt.__index or mt
	return setmetatable(fields, mt)
end

local Vector2MT = { __type = "Vector2" }
Vector2MT.__index = function(v, k)
	if k == "X" then
		return rawget(v, "x")
	elseif k == "Y" then
		return rawget(v, "y")
	elseif k == "Magnitude" then
		return math.sqrt(v.x * v.x + v.y * v.y)
	elseif k == "Unit" then
		local m = math.sqrt(v.x * v.x + v.y * v.y)
		return DT.Vector2.new(v.x / m, v.y / m)
	elseif k == "Dot" then
		return function(a, b)
			return a.x * b.x + a.y * b.y
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			return DT.Vector2.new(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
		end
	end
	error("Vector2 has no member " .. tostring(k), 2)
end
Vector2MT.__add = function(a, b)
	return DT.Vector2.new(a.x + b.x, a.y + b.y)
end
Vector2MT.__sub = function(a, b)
	return DT.Vector2.new(a.x - b.x, a.y - b.y)
end
Vector2MT.__mul = function(a, b)
	if type(a) == "number" then
		return DT.Vector2.new(a * b.x, a * b.y)
	elseif type(b) == "number" then
		return DT.Vector2.new(a.x * b, a.y * b)
	end
	return DT.Vector2.new(a.x * b.x, a.y * b.y)
end
Vector2MT.__div = function(a, b)
	return DT.Vector2.new(a.x / b, a.y / b)
end
Vector2MT.__eq = function(a, b)
	return a.x == b.x and a.y == b.y
end
DT.Vector2 = setmetatable({
	new = function(x, y)
		return setmetatable({ x = x or 0, y = y or 0 }, Vector2MT)
	end,
}, {
	__index = function(t, k)
		if k == "zero" then
			return t.new(0, 0)
		elseif k == "one" then
			return t.new(1, 1)
		elseif k == "xAxis" then
			return t.new(1, 0)
		elseif k == "yAxis" then
			return t.new(0, 1)
		end
		error("Vector2." .. tostring(k) .. " does not exist", 2)
	end,
})

local function strictTable(name, t)
	return setmetatable(t, {
		__index = function(_, k)
			error(name .. "." .. tostring(k) .. " does not exist", 2)
		end,
	})
end

local UDimMT = { __type = "UDim" }
UDimMT.__index = UDimMT
DT.UDim = strictTable("UDim", {
	new = function(s, o)
		return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDimMT)
	end,
})
local UDim2MT = { __type = "UDim2" }
UDim2MT.__index = function(u, k)
	if k == "Width" then
		return u.X
	elseif k == "Height" then
		return u.Y
	elseif k == "Lerp" then
		return function(a, b, t)
			return DT.UDim2.new(
				a.X.Scale + (b.X.Scale - a.X.Scale) * t,
				a.X.Offset + (b.X.Offset - a.X.Offset) * t,
				a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
				a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
			)
		end
	end
	error("UDim2 has no member " .. tostring(k), 2)
end
UDim2MT.__add = function(a, b)
	return DT.UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2MT.__sub = function(a, b)
	return DT.UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
DT.UDim2 = strictTable("UDim2", {
	new = function(xs, xo, ys, yo)
		if type(xs) == "table" then
			return setmetatable({ X = xs, Y = xo }, UDim2MT)
		end
		return setmetatable({ X = DT.UDim.new(xs, xo), Y = DT.UDim.new(ys, yo) }, UDim2MT)
	end,
	fromScale = function(x, y)
		return setmetatable({ X = DT.UDim.new(x, 0), Y = DT.UDim.new(y, 0) }, UDim2MT)
	end,
	fromOffset = function(x, y)
		return setmetatable({ X = DT.UDim.new(0, x), Y = DT.UDim.new(0, y) }, UDim2MT)
	end,
})

local function checkNum(v, what)
	if type(v) ~= "number" then
		error(what .. " expects a number, got " .. typeof(v), 3)
	end
end

DT.NumberSequenceKeypoint = strictTable("NumberSequenceKeypoint", {
	new = function(t, v, e)
		checkNum(t, "NumberSequenceKeypoint.new")
		checkNum(v, "NumberSequenceKeypoint.new")
		return datatype("NumberSequenceKeypoint", { Time = t, Value = v, Envelope = e or 0 })
	end,
})
DT.NumberSequence = strictTable("NumberSequence", {
	new = function(a, b)
		local kps
		if type(a) == "number" then
			kps = { DT.NumberSequenceKeypoint.new(0, a), DT.NumberSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" and typeof(a) == "table" then
			kps = a
			if #kps < 2 or kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
				error("NumberSequence: keypoints must start at time 0 and end at time 1", 2)
			end
		else
			error("NumberSequence.new: bad argument " .. typeof(a), 2)
		end
		return datatype("NumberSequence", { Keypoints = kps })
	end,
})
DT.ColorSequenceKeypoint = strictTable("ColorSequenceKeypoint", {
	new = function(t, c)
		checkNum(t, "ColorSequenceKeypoint.new")
		if typeof(c) ~= "Color3" then
			error("ColorSequenceKeypoint.new expects a Color3", 2)
		end
		return datatype("ColorSequenceKeypoint", { Time = t, Value = c })
	end,
})
DT.ColorSequence = strictTable("ColorSequence", {
	new = function(a, b)
		local kps
		if typeof(a) == "Color3" then
			if b ~= nil and typeof(b) ~= "Color3" then
				error("ColorSequence.new: second argument must be a Color3", 2)
			end
			kps = { DT.ColorSequenceKeypoint.new(0, a), DT.ColorSequenceKeypoint.new(1, b or a) }
		elseif typeof(a) == "table" then
			kps = a
			if #kps < 2 or kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
				error("ColorSequence: keypoints must start at time 0 and end at time 1", 2)
			end
		else
			error("ColorSequence.new: bad argument " .. typeof(a), 2)
		end
		return datatype("ColorSequence", { Keypoints = kps })
	end,
})
DT.NumberRange = strictTable("NumberRange", {
	new = function(a, b)
		checkNum(a, "NumberRange.new")
		b = b or a
		if b < a then
			error("NumberRange: max must be >= min", 2)
		end
		return datatype("NumberRange", { Min = a, Max = b })
	end,
})
DT.PhysicalProperties = strictTable("PhysicalProperties", {
	new = function(d, f, e, fw, ew)
		if typeof(d) == "EnumItem" then
			return datatype("PhysicalProperties", { Density = 1, Friction = 0.3, Elasticity = 0.5 })
		end
		checkNum(d, "PhysicalProperties.new")
		return datatype("PhysicalProperties", { Density = d, Friction = f or 0.3, Elasticity = e or 0.5, FrictionWeight = fw or 1, ElasticityWeight = ew or 1 })
	end,
})
DT.Font = strictTable("Font", {
	new = function(family, weight, style)
		return datatype("Font", { Family = family, Weight = weight, Style = style })
	end,
	fromEnum = function(e)
		return datatype("Font", { Family = tostring(e) })
	end,
	fromName = function(n)
		return datatype("Font", { Family = n })
	end,
})
DT.TweenInfo = strictTable("TweenInfo", {
	new = function(time, style, dir, repeatCount, reverses, delay)
		return datatype("TweenInfo", { Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delay or 0 })
	end,
})
DT.Ray = strictTable("Ray", {
	new = function(o, d)
		return datatype("Ray", { Origin = o, Direction = d, Unit = nil })
	end,
})
DT.Rect = strictTable("Rect", {
	new = function(a, b, c, d)
		return datatype("Rect", { Min = DT.Vector2.new(a, b), Max = DT.Vector2.new(c, d) })
	end,
})
DT.RaycastParams = strictTable("RaycastParams", {
	new = function()
		return datatype("RaycastParams", { FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false, CollisionGroup = "Default" })
	end,
})
DT.OverlapParams = strictTable("OverlapParams", {
	new = function()
		return datatype("OverlapParams", { FilterDescendantsInstances = {}, FilterType = nil, MaxParts = 0, CollisionGroup = "Default" })
	end,
})
DT.Random = strictTable("Random", {
	new = function(seed)
		local s = seed or 1
		return datatype("Random", {
			NextNumber = function(_, a, b)
				s = (s * 1103515245 + 12345) % 2147483648
				local u = s / 2147483648
				if a then
					return a + (b - a) * u
				end
				return u
			end,
			NextInteger = function(_, a, b)
				s = (s * 1103515245 + 12345) % 2147483648
				return a + s % (b - a + 1)
			end,
		})
	end,
})

------------------------------------------------------------------------ typeof
local realTypeof = typeof
local function emuTypeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
		return "table"
	end
	if realTypeof then
		return realTypeof(v)
	end
	return type(v)
end
Emu.typeof = emuTypeof
typeof = emuTypeof

------------------------------------------------------------------------ enums
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = function(item, k)
	if k == "IsA" then
		return function(self, name)
			return rawget(self, "EnumType").Name == name
		end
	end
	error(tostring(k) .. " is not a valid member of EnumItem", 2)
end
EnumItemMT.__tostring = function(item)
	return "Enum." .. rawget(item, "EnumType").Name .. "." .. rawget(item, "Name")
end
local EnumTypeMT = { __type = "Enum" }
local enumCache = {}
EnumTypeMT.__index = function(et, k)
	if k == "GetEnumItems" then
		return function()
			local list = {}
			for _, it in rawget(et, "_items") do
				table.insert(list, it)
			end
			table.sort(list, function(a, b)
				return a.Value < b.Value
			end)
			return list
		end
	elseif k == "FromName" then
		return function(_, n)
			return rawget(et, "_items")[n]
		end
	elseif k == "FromValue" then
		return function(_, val)
			for _, it in rawget(et, "_items") do
				if it.Value == val then
					return it
				end
			end
			return nil
		end
	end
	local it = rawget(et, "_items")[k]
	if not it then
		error("'" .. tostring(k) .. "' is not a valid member of Enum." .. rawget(et, "Name"), 2)
	end
	return it
end
local function enumType(name)
	local et = enumCache[name]
	if et then
		return et
	end
	local items = API.enums[name]
	if not items then
		return nil
	end
	et = setmetatable({ Name = name, _items = {} }, EnumTypeMT)
	for _, pair in items do
		rawget(et, "_items")[pair[1]] = setmetatable({ Name = pair[1], Value = pair[2], EnumType = et }, EnumItemMT)
	end
	enumCache[name] = et
	return et
end
Emu.Enum = setmetatable({}, {
	__index = function(_, k)
		local et = enumType(k)
		if not et then
			error("Enum." .. tostring(k) .. " does not exist", 2)
		end
		return et
	end,
})

------------------------------------------------------------------------ scheduler
local ctxOf = setmetatable({}, { __mode = "k" })
local sleeping = {} -- { co, at, args }
local deferred = {}

local function resume(co, ...)
	if coroutine.status(co) == "dead" then
		return
	end
	local prev = Emu.context
	Emu.context = ctxOf[co] or prev
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(tostring(err) .. "\n" .. debug.traceback(co))
	end
	Emu.context = prev
end
Emu.resume = resume

local function spawnIn(ctx, fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	ctxOf[co] = ctx or Emu.context
	resume(co, ...)
	return co
end
Emu.spawnIn = spawnIn

local task = {}
function task.spawn(fn, ...)
	return spawnIn(Emu.context, fn, ...)
end
function task.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	ctxOf[co] = Emu.context
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	ctxOf[co] = Emu.context
	table.insert(sleeping, { co = co, at = Emu.time + (t or 0), args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	if not co or not ctxOf[co] then
		error("task.wait called outside a script thread", 2)
	end
	local start = Emu.time
	table.insert(sleeping, { co = co, at = Emu.time + math.max(t or 0, 1 / 60), args = nil })
	coroutine.yield()
	return Emu.time - start
end
function task.cancel(co)
	for i = #sleeping, 1, -1 do
		if sleeping[i].co == co then
			table.remove(sleeping, i)
		end
	end
end
function task.synchronize() end
function task.desynchronize() end
Emu.task = task

local function runScheduler()
	-- deferred first (they were queued this frame), then sleepers that are due
	for _ = 1, 10 do
		if #deferred == 0 then
			break
		end
		local list = deferred
		deferred = {}
		for _, d in list do
			resume(d.co, table.unpack(d.args, 1, d.args.n))
		end
	end
	local due = {}
	for i = #sleeping, 1, -1 do
		if sleeping[i].at <= Emu.time + 1e-9 then
			table.insert(due, 1, sleeping[i])
			table.remove(sleeping, i)
		end
	end
	for _, s in due do
		if s.args then
			resume(s.co, table.unpack(s.args, 1, s.args.n))
		else
			resume(s.co)
		end
	end
end

------------------------------------------------------------------------ signals
local SignalMT = { __type = "RBXScriptSignal" }
SignalMT.__index = SignalMT
local ConnMT = { __type = "RBXScriptConnection" }
ConnMT.__index = ConnMT
function ConnMT:Disconnect()
	self.Connected = false
	local list = self._signal._handlers
	for i = #list, 1, -1 do
		if list[i] == self then
			table.remove(list, i)
		end
	end
end
local function newSignal(name)
	return setmetatable({ _handlers = {}, _waiting = {}, _name = name }, SignalMT)
end
Emu.newSignal = newSignal
function SignalMT:Connect(fn)
	if type(fn) ~= "function" then
		error("Connect expects a function", 2)
	end
	local c = setmetatable({ _signal = self, _fn = fn, Connected = true, _ctx = Emu.context }, ConnMT)
	table.insert(self._handlers, c)
	return c
end
function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function SignalMT:Wait()
	local co = coroutine.running()
	table.insert(self._waiting, co)
	return coroutine.yield()
end
-- Fire only handlers registered from `ctx` (nil = all).
function SignalMT:Fire(...)
	self:FireCtx(nil, ...)
end
function SignalMT:FireCtx(ctx, ...)
	local list = table.clone(self._handlers)
	for _, c in list do
		if c.Connected and (ctx == nil or c._ctx == ctx) then
			spawnIn(c._ctx, c._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, co in waiting do
		resume(co, ...)
	end
end

------------------------------------------------------------------------ instances
local Instance = {}
local InstanceMT = { __type = "Instance" }
local Methods = {} -- [className] = { [name] = fn }
local Getters = {} -- [className] = { [prop] = fn(self) }
local Setters = {} -- [className] = { [prop] = fn(self, v) }
local Defaults = {}
Emu.Methods, Emu.Getters, Emu.Setters, Emu.Defaults = Methods, Getters, Setters, Defaults
local allInstances = setmetatable({}, { __mode = "k" })

local function classInfo(cls)
	return API.classes[cls]
end

local function chain(cls)
	local list = {}
	while cls and cls ~= "" do
		table.insert(list, cls)
		local info = API.classes[cls]
		cls = info and info.s
	end
	return list
end

local memberCache = {}
local function lookupMember(cls, key)
	local cache = memberCache[cls]
	if not cache then
		cache = {}
		memberCache[cls] = cache
	end
	local hit = cache[key]
	if hit ~= nil then
		return hit
	end
	local result = false
	for _, c in chain(cls) do
		local info = API.classes[c]
		if info then
			if info.p[key] then
				result = { kind = "prop", type = info.p[key], owner = c, readonly = table.find(info.ro, key) ~= nil, deprecated = table.find(info.d, key) ~= nil }
				break
			elseif table.find(info.f, key) then
				result = { kind = "func", owner = c, deprecated = table.find(info.d, key) ~= nil }
				break
			elseif table.find(info.e, key) then
				result = { kind = "event", owner = c, deprecated = table.find(info.d, key) ~= nil }
				break
			end
		end
	end
	cache[key] = result
	return result
end
Emu.lookupMember = lookupMember

local function isA(cls, name)
	for _, c in chain(cls) do
		if c == name then
			return true
		end
	end
	return false
end

local function findImpl(tbl, cls, key)
	for _, c in chain(cls) do
		local m = tbl[c]
		if m and m[key] ~= nil then
			return m[key]
		end
	end
	return nil
end

local DEFAULT_BY_TYPE = {
	["p:bool"] = false,
	["p:float"] = 0,
	["p:double"] = 0,
	["p:int"] = 0,
	["p:int64"] = 0,
	["p:string"] = "",
	["d:Content"] = "",
	["p:ContentId"] = "",
}

local function defaultFor(self, key, typ)
	local cls = rawget(self, "_class")
	local d = findImpl(Defaults, cls, key)
	if d ~= nil then
		if type(d) == "function" then
			return d(self)
		end
		return d
	end
	if DEFAULT_BY_TYPE[typ] ~= nil then
		return DEFAULT_BY_TYPE[typ]
	end
	local cat, name = string.match(typ, "^(%a):(.+)$")
	if cat == "e" then
		local et = enumType(name)
		if et then
			return et:GetEnumItems()[1]
		end
	elseif cat == "d" then
		if name == "Vector3" then
			return Vector3.new(0, 0, 0)
		elseif name == "CFrame" then
			return CFrame.new()
		elseif name == "Color3" then
			return Color3.new(0.64, 0.64, 0.65)
		elseif name == "Vector2" then
			return DT.Vector2.new(0, 0)
		elseif name == "UDim2" then
			return DT.UDim2.new(0, 0, 0, 0)
		elseif name == "UDim" then
			return DT.UDim.new(0, 0)
		elseif name == "NumberSequence" then
			return DT.NumberSequence.new(0)
		elseif name == "ColorSequence" then
			return DT.ColorSequence.new(Color3.new(1, 1, 1))
		elseif name == "NumberRange" then
			return DT.NumberRange.new(0)
		end
	end
	return nil
end

local NUMERIC = { ["p:float"] = true, ["p:double"] = true, ["p:int"] = true, ["p:int64"] = true }
local function checkValue(self, key, typ, v)
	local cls = rawget(self, "_class")
	local function bad(expect)
		error(string.format("Unable to assign property %s. %s expected, got %s (%s.%s)", key, expect, emuTypeof(v), cls, key), 4)
	end
	if NUMERIC[typ] then
		if type(v) ~= "number" then
			bad("number")
		end
		if v ~= v then
			bad("non-NaN number")
		end
	elseif typ == "p:bool" then
		if type(v) ~= "boolean" then
			bad("bool")
		end
	elseif typ == "p:string" then
		if type(v) ~= "string" and type(v) ~= "number" then
			bad("string")
		end
	else
		local cat, name = string.match(typ, "^(%a):(.+)$")
		if cat == "e" then
			if emuTypeof(v) == "EnumItem" then
				if rawget(v, "EnumType").Name ~= name then
					bad("Enum." .. name)
				end
			elseif type(v) == "number" or type(v) == "string" then
				local et = enumType(name)
				local found = nil
				for _, it in rawget(et, "_items") do
					if it.Name == v or it.Value == v then
						found = it
					end
				end
				if not found then
					bad("Enum." .. name)
				end
				return found
			else
				bad("Enum." .. name)
			end
		elseif cat == "d" then
			local simple = { Vector3 = true, CFrame = true, Color3 = true, Vector2 = true, UDim2 = true, UDim = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Font = true, Rect = true }
			if simple[name] and emuTypeof(v) ~= name then
				if not (name == "Font" and v == nil) then
					bad(name)
				end
			end
			if name == "PhysicalProperties" and v ~= nil and emuTypeof(v) ~= "PhysicalProperties" then
				bad("PhysicalProperties")
			end
			if name == "Vector3" and (v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z) then
				bad("finite Vector3")
			end
		elseif cat == "c" then
			if v ~= nil then
				if emuTypeof(v) ~= "Instance" then
					bad(name)
				end
				if not isA(rawget(v, "_class"), name) then
					bad(name)
				end
			end
		end
	end
	return v
end

local function getSignal(self, name)
	local sigs = rawget(self, "_signals")
	local s = sigs[name]
	if not s then
		s = newSignal(name)
		sigs[name] = s
	end
	return s
end
Emu.getSignal = getSignal

local function childNamed(self, name)
	for _, c in rawget(self, "_children") do
		if rawget(c, "_name") == name then
			return c
		end
	end
	return nil
end

InstanceMT.__index = function(self, key)
	local cls = rawget(self, "_class")
	if key == "Name" then
		return rawget(self, "_name")
	elseif key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "ClassName" then
		return cls
	end
	local m = lookupMember(cls, key)
	if m then
		if m.deprecated then
			warnOnce(cls .. "." .. key, "deprecated member used: " .. cls .. "." .. key)
		end
		if m.kind == "func" then
			local impl = findImpl(Methods, cls, key)
			if impl then
				return impl
			end
			return function()
				report("emulator: method " .. cls .. ":" .. key .. " is not implemented in the emulator")
			end
		elseif m.kind == "event" then
			return getSignal(self, key)
		else
			local g = findImpl(Getters, cls, key)
			if g then
				return g(self)
			end
			local props = rawget(self, "_props")
			local v = props[key]
			if v == nil then
				v = defaultFor(self, key, m.type)
				props[key] = v
			end
			return v
		end
	end
	local child = childNamed(self, key)
	if child then
		return child
	end
	error(tostring(key) .. " is not a valid member of " .. cls .. ' "' .. rawget(self, "_name") .. '"', 2)
end

local function fireChanged(self, key)
	local sigs = rawget(self, "_propSignals")
	if sigs and sigs[key] then
		sigs[key]:Fire()
	end
	local ch = rawget(self, "_signals").Changed
	if ch then
		ch:Fire(key)
	end
end

local function ancestors(inst)
	local list = {}
	local p = rawget(inst, "_parent")
	while p do
		table.insert(list, p)
		p = rawget(p, "_parent")
	end
	return list
end

local function setParent(self, parent)
	if rawget(self, "_destroyed") then
		error("The Parent property of " .. rawget(self, "_name") .. " is locked, current parent: NULL, new parent " .. (parent and rawget(parent, "_name") or "nil"), 3)
	end
	if parent ~= nil and emuTypeof(parent) ~= "Instance" then
		error("Parent must be an Instance", 3)
	end
	local old = rawget(self, "_parent")
	if old == parent then
		return
	end
	local p = parent
	while p do
		if p == self then
			error("Attempt to set parent of " .. rawget(self, "_name") .. " to itself or a descendant", 3)
		end
		p = rawget(p, "_parent")
	end
	if old then
		local list = rawget(old, "_children")
		local i = table.find(list, self)
		if i then
			table.remove(list, i)
		end
		getSignal(old, "ChildRemoved"):Fire(self)
		for _, a in { old, table.unpack(ancestors(old)) } do
			local s = rawget(a, "_signals").DescendantRemoving
			if s then
				s:Fire(self)
			end
		end
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_children"), self)
		getSignal(parent, "ChildAdded"):Fire(self)
		local function fireDesc(inst)
			for _, a in { parent, table.unpack(ancestors(parent)) } do
				local s = rawget(a, "_signals").DescendantAdded
				if s then
					s:Fire(inst)
				end
			end
		end
		fireDesc(self)
		for _, d in self:GetDescendants() do
			fireDesc(d)
		end
	end
	local s = rawget(self, "_signals").AncestryChanged
	if s then
		s:Fire(self, parent)
	end
	if Emu.onParentChanged then
		Emu.onParentChanged(self, old, parent)
	end
end

InstanceMT.__newindex = function(self, key, value)
	local cls = rawget(self, "_class")
	if key == "Parent" then
		setParent(self, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" then
			error("Name must be a string", 2)
		end
		rawset(self, "_name", value)
		fireChanged(self, "Name")
		return
	end
	local m = lookupMember(cls, key)
	if not m or m.kind ~= "prop" then
		error(tostring(key) .. " is not a valid member of " .. cls .. ' "' .. rawget(self, "_name") .. '"', 2)
	end
	if m.readonly and not Emu.internalWrite then
		error("Unable to assign property " .. key .. ". Property is read only (" .. cls .. ")", 2)
	end
	if m.deprecated then
		warnOnce(cls .. "." .. key, "deprecated member used: " .. cls .. "." .. key)
	end
	value = checkValue(self, key, m.type, value)
	local s = findImpl(Setters, cls, key)
	if s then
		s(self, value)
	else
		rawget(self, "_props")[key] = value
	end
	fireChanged(self, key)
end

InstanceMT.__tostring = function(self)
	return rawget(self, "_name")
end

local function rawNew(cls)
	local inst = setmetatable({
		_class = cls,
		_name = cls,
		_props = {},
		_children = {},
		_parent = nil,
		_attrs = {},
		_signals = {},
		_propSignals = nil,
		_destroyed = false,
	}, InstanceMT)
	allInstances[inst] = true
	return inst
end
Emu.rawNew = rawNew

function Instance.new(cls, parent)
	local info = classInfo(cls)
	if not info then
		error("Unable to create an Instance of type \"" .. tostring(cls) .. "\"", 2)
	end
	if info.nc then
		error("Unable to create an Instance of type \"" .. cls .. "\" (not creatable)", 2)
	end
	local inst = rawNew(cls)
	if parent then
		inst.Parent = parent
	end
	return inst
end
Emu.Instance = Instance

local function isInstance(v)
	return emuTypeof(v) == "Instance"
end
Emu.isInstance = isInstance

------------------------------------------------------------------------ Instance methods
local I = {}
Methods.Instance = I

function I:GetChildren()
	return table.clone(rawget(self, "_children"))
end
function I:GetDescendants()
	local out = {}
	local function walk(inst)
		for _, c in rawget(inst, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function I:FindFirstChild(name, recursive)
	if recursive then
		for _, d in self:GetDescendants() do
			if rawget(d, "_name") == name then
				return d
			end
		end
		return nil
	end
	return childNamed(self, name)
end
function I:FindFirstChildOfClass(cls)
	for _, c in rawget(self, "_children") do
		if rawget(c, "_class") == cls then
			return c
		end
	end
	return nil
end
function I:FindFirstChildWhichIsA(cls, recursive)
	local list = if recursive then self:GetDescendants() else rawget(self, "_children")
	for _, c in list do
		if isA(rawget(c, "_class"), cls) then
			return c
		end
	end
	return nil
end
function I:FindFirstAncestor(name)
	for _, a in ancestors(self) do
		if rawget(a, "_name") == name then
			return a
		end
	end
	return nil
end
function I:FindFirstAncestorOfClass(cls)
	for _, a in ancestors(self) do
		if rawget(a, "_class") == cls then
			return a
		end
	end
	return nil
end
function I:FindFirstAncestorWhichIsA(cls)
	for _, a in ancestors(self) do
		if isA(rawget(a, "_class"), cls) then
			return a
		end
	end
	return nil
end
function I:WaitForChild(name, timeout)
	local c = childNamed(self, name)
	if c then
		return c
	end
	local co = coroutine.running()
	if not co or not ctxOf[co] then
		error("WaitForChild yielded outside a script thread", 2)
	end
	local start = Emu.time
	local warnedInfinite = false
	while true do
		task.wait()
		c = childNamed(self, name)
		if c then
			return c
		end
		local waited = Emu.time - start
		if timeout and waited >= timeout then
			return nil
		end
		if not timeout and waited > 5 and not warnedInfinite then
			warnedInfinite = true
			report("Infinite yield possible on '" .. self:GetFullName() .. ":WaitForChild(\"" .. name .. "\")'")
		end
	end
end
function I:IsA(cls)
	return isA(rawget(self, "_class"), cls)
end
function I:IsDescendantOf(other)
	return table.find(ancestors(self), other) ~= nil
end
function I:IsAncestorOf(other)
	return table.find(ancestors(other), self) ~= nil
end
function I:GetFullName()
	local parts = { rawget(self, "_name") }
	for _, a in ancestors(self) do
		if rawget(a, "_class") ~= "DataModel" then
			table.insert(parts, 1, rawget(a, "_name"))
		end
	end
	return table.concat(parts, ".")
end
function I:ClearAllChildren()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
end
function I:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	for _, c in self:GetChildren() do
		c:Destroy()
	end
	if rawget(self, "_parent") then
		setParent(self, nil)
	end
	rawset(self, "_destroyed", true)
	local s = rawget(self, "_signals").Destroying
	if s then
		s:Fire()
	end
	for _, sig in rawget(self, "_signals") do
		sig._handlers = {}
	end
end
function I:GetAttribute(name)
	return rawget(self, "_attrs")[name]
end
function I:GetAttributes()
	return table.clone(rawget(self, "_attrs"))
end
local ATTR_TYPES = { number = true, string = true, boolean = true, Vector3 = true, Vector2 = true, Color3 = true, CFrame = true, UDim = true, UDim2 = true, NumberRange = true, NumberSequence = true, ColorSequence = true, Rect = true, Font = true, EnumItem = true, BrickColor = true }
function I:SetAttribute(name, value)
	if type(name) ~= "string" then
		error("SetAttribute: name must be a string", 2)
	end
	if value ~= nil and not ATTR_TYPES[emuTypeof(value)] then
		error("SetAttribute: " .. emuTypeof(value) .. " is not a supported attribute type (" .. name .. ")", 2)
	end
	if type(value) == "number" and value ~= value then
		report("SetAttribute: NaN written to attribute " .. name .. " on " .. self:GetFullName())
	end
	local attrs = rawget(self, "_attrs")
	if attrs[name] == value then
		return
	end
	attrs[name] = value
	local sigs = rawget(self, "_attrSignals")
	if sigs and sigs[name] then
		sigs[name]:Fire()
	end
	local s = rawget(self, "_signals").AttributeChanged
	if s then
		s:Fire(name)
	end
end
function I:GetAttributeChangedSignal(name)
	local sigs = rawget(self, "_attrSignals")
	if not sigs then
		sigs = {}
		rawset(self, "_attrSignals", sigs)
	end
	if not sigs[name] then
		sigs[name] = newSignal("Attr" .. name)
	end
	return sigs[name]
end
function I:GetPropertyChangedSignal(name)
	local m = lookupMember(rawget(self, "_class"), name)
	if not (m and m.kind == "prop") and name ~= "Parent" and name ~= "Name" then
		error(name .. " is not a valid property name.", 2)
	end
	local sigs = rawget(self, "_propSignals")
	if not sigs then
		sigs = {}
		rawset(self, "_propSignals", sigs)
	end
	if not sigs[name] then
		sigs[name] = newSignal("Prop" .. name)
	end
	return sigs[name]
end

-- Clone with internal references remapped.
function I:Clone()
	if self.Archivable == false then
		return nil
	end
	local map = {}
	local function copy(inst)
		local c = rawNew(rawget(inst, "_class"))
		rawset(c, "_name", rawget(inst, "_name"))
		for k, v in rawget(inst, "_props") do
			rawget(c, "_props")[k] = v
		end
		for k, v in rawget(inst, "_attrs") do
			rawget(c, "_attrs")[k] = v
		end
		rawset(c, "_source", rawget(inst, "_source"))
		map[inst] = c
		for _, child in rawget(inst, "_children") do
			if child.Archivable ~= false then
				local cc = copy(child)
				rawset(cc, "_parent", c)
				table.insert(rawget(c, "_children"), cc)
			end
		end
		return c
	end
	local root = copy(self)
	for orig, c in map do
		local props = rawget(c, "_props")
		for k, v in props do
			if isInstance(v) and map[v] then
				props[k] = map[v]
			end
		end
		_ = orig
	end
	return root
end

------------------------------------------------------------------------ parts, models, joints
local PV = {}
Methods.PVInstance = PV
local BP = {}
Methods.BasePart = BP
Getters.BasePart = {
	Position = function(self)
		return self.CFrame.Position
	end,
	Orientation = function(self)
		local x, y, z = self.CFrame:ToEulerAnglesYXZ()
		return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	end,
	AssemblyRootPart = function(self)
		return Emu.assemblyRoot(self)
	end,
	Mass = function(self)
		local s = self.Size
		return s.X * s.Y * s.Z * 0.7
	end,
	AssemblyMass = function(self)
		local s = self.Size
		return s.X * s.Y * s.Z * 0.7
	end,
}
Setters.BasePart = {
	Position = function(self, v)
		local cf = self.CFrame
		rawget(self, "_props").CFrame = cf.Rotation + v
	end,
	Size = function(self, v)
		if v.X < 0 or v.Y < 0 or v.Z < 0 then
			error("Size must be positive", 3)
		end
		rawget(self, "_props").Size = Vector3.new(math.max(v.X, 0.001), math.max(v.Y, 0.001), math.max(v.Z, 0.001))
	end,
}
Defaults.BasePart = {
	Size = function()
		return Vector3.new(4, 1, 2)
	end,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	Archivable = true,
	CollisionGroup = "Default",
	CFrame = function()
		return CFrame.new()
	end,
	AssemblyLinearVelocity = function()
		return Vector3.new(0, 0, 0)
	end,
	AssemblyAngularVelocity = function()
		return Vector3.new(0, 0, 0)
	end,
	LocalTransparencyModifier = 0,
}
Defaults.Instance = { Archivable = true }
function BP:SetNetworkOwner(p)
	if Emu.context ~= "server" then
		error("SetNetworkOwner can only be called from the server", 2)
	end
	if rawget(self, "_props").Anchored then
		error("Network Ownership API cannot be called on Anchored parts", 2)
	end
	if not self:IsDescendantOf(Emu.workspace) then
		error("Can only call Network Ownership API on a part that is descendant of Workspace", 2)
	end
	_ = p
end
function BP:SetNetworkOwnershipAuto() end
function BP:GetNetworkOwner()
	return nil
end
function BP:ApplyImpulse(v)
	self.AssemblyLinearVelocity += v / math.max(self.AssemblyMass, 1)
end
function BP:GetMass()
	return self.Mass
end
function BP:GetConnectedParts()
	return {}
end

local function modelParts(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

function PV:GetPivot()
	if self:IsA("BasePart") then
		return self.CFrame
	end
	local pp = self.PrimaryPart
	if pp then
		return pp.CFrame
	end
	local parts = modelParts(self)
	if parts[1] then
		return parts[1].CFrame
	end
	return CFrame.new()
end
function PV:PivotTo(cf)
	if typeof(cf) ~= "CFrame" then
		error("PivotTo expects a CFrame", 2)
	end
	if self:IsA("BasePart") then
		self.CFrame = cf
		return
	end
	local pivot = self:GetPivot()
	local delta = cf * pivot:Inverse()
	for _, p in modelParts(self) do
		rawget(p, "_props").CFrame = delta * p.CFrame
	end
end
Methods.Model = {
	ScaleTo = function(self, s)
		if type(s) ~= "number" or s <= 0 then
			error("ScaleTo expects a positive number", 2)
		end
		rawset(self, "_scale", s)
	end,
	GetScale = function(self)
		return rawget(self, "_scale") or 1
	end,
	GetBoundingBox = function(self)
		return self:GetPivot(), Vector3.new(4, 4, 4)
	end,
	GetExtentsSize = function()
		return Vector3.new(4, 4, 4)
	end,
	SetPrimaryPartCFrame = function(self, cf)
		self:PivotTo(cf)
	end,
	GetPrimaryPartCFrame = function(self)
		return self:GetPivot()
	end,
}

Getters.Attachment = {
	WorldPosition = function(self)
		local p = rawget(self, "_parent")
		local cf = self.CFrame
		if p and p:IsA("BasePart") then
			return (p.CFrame * cf).Position
		end
		return cf.Position
	end,
	WorldCFrame = function(self)
		local p = rawget(self, "_parent")
		if p and p:IsA("BasePart") then
			return p.CFrame * self.CFrame
		end
		return self.CFrame
	end,
	Position = function(self)
		return self.CFrame.Position
	end,
	Axis = function(self)
		return self.CFrame.RightVector
	end,
	SecondaryAxis = function(self)
		return self.CFrame.UpVector
	end,
}
Setters.Attachment = {
	Position = function(self, v)
		rawget(self, "_props").CFrame = self.CFrame.Rotation + v
	end,
}

------------------------------------------------------------------------ services
local services = {}
Emu.services = services

local function makeService(cls, name)
	local s = rawNew(cls)
	rawset(s, "_name", name or cls)
	services[cls] = s
	return s
end

function Emu.init(apiPath, shimPath)
	API = loadchunk(readfile(apiPath), "api")()
	Shim = loadchunk(readfile(shimPath), "shim")()
	Emu.Shim = Shim
	-- datatypes from the shim (with __type tags for typeof)
	Vector3, CFrame, Color3 = Shim.Vector3, Shim.CFrame, Shim.Color3
	Shim.tag()
	Emu.DT = DT

	local game = rawNew("DataModel")
	rawset(game, "_name", "Game")
	Emu.game = game
	for _, cls in { "Workspace", "Players", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "StarterPack", "Lighting", "SoundService", "RunService", "UserInputService", "ContextActionService", "PhysicsService", "Debris", "TweenService", "DataStoreService", "HttpService", "CollectionService", "GuiService", "TextService", "MarketplaceService", "ProximityPromptService", "Teams", "Chat", "TextChatService", "BadgeService" } do
		local s = makeService(cls)
		rawset(s, "_parent", game)
		table.insert(rawget(game, "_children"), s)
	end
	Emu.workspace = services.Workspace
	local spsc = rawNew("StarterPlayerScripts")
	rawset(spsc, "_name", "StarterPlayerScripts")
	spsc.Parent = services.StarterPlayer
	local scsc = rawNew("StarterCharacterScripts")
	rawset(scsc, "_name", "StarterCharacterScripts")
	scsc.Parent = services.StarterPlayer
	local cam = rawNew("Camera")
	rawset(cam, "_name", "Camera")
	cam.Parent = services.Workspace
	rawget(services.Workspace, "_props").CurrentCamera = cam
	local terrain = rawNew("Terrain")
	rawset(terrain, "_name", "Terrain")
	terrain.Parent = services.Workspace
	return game
end

-- game:GetService / workspace / service methods
Methods.DataModel = {
	GetService = function(self, name)
		local s = services[name]
		if not s then
			error("emulator: service " .. tostring(name) .. " not available", 2)
		end
		return s
	end,
	FindService = function(self, name)
		return services[name]
	end,
	IsLoaded = function()
		return true
	end,
	BindToClose = function() end,
}
Methods.ServiceProvider = Methods.DataModel

Methods.Workspace = {
	GetServerTimeNow = function()
		return Emu.time + 1000
	end,
	Raycast = function(self, origin, dir)
		-- only the arena floor (y = 0 disc of radius 60)
		if dir.Y >= 0 then
			return nil
		end
		local t = -origin.Y / dir.Y
		if t < 0 or t > 1 then
			return nil
		end
		local p = origin + dir * t
		if Vector3.new(p.X, 0, p.Z).Magnitude > 60 then
			return nil
		end
		return { Position = p, Normal = Vector3.new(0, 1, 0), Instance = nil, Distance = (p - origin).Magnitude, Material = Emu.Enum.Material.Slate }
	end,
	GetPartBoundsInRadius = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
	BulkMoveTo = function(self, parts, cframes)
		for i, p in parts do
			p.CFrame = cframes[i]
		end
	end,
}
Defaults.Workspace = { Gravity = 196.2 }

Methods.RunService = {
	IsStudio = function()
		return true
	end,
	IsServer = function()
		return Emu.context == "server"
	end,
	IsClient = function()
		return Emu.context == "client"
	end,
	IsRunning = function()
		return true
	end,
	IsRunMode = function()
		return false
	end,
	BindToRenderStep = function(self, name, priority, fn)
		if Emu.context ~= "client" then
			error("BindToRenderStep can only be called from the client", 2)
		end
		Emu.renderSteps[name] = { priority = priority, fn = fn }
	end,
	UnbindFromRenderStep = function(self, name)
		Emu.renderSteps[name] = nil
	end,
}
Emu.renderSteps = {}

-- Players
Methods.Players = {
	GetPlayers = function(self)
		local list = {}
		for _, c in rawget(self, "_children") do
			if rawget(c, "_class") == "Player" then
				table.insert(list, c)
			end
		end
		return list
	end,
	GetPlayerFromCharacter = function(self, char)
		for _, p in self:GetPlayers() do
			if rawget(p, "_props").Character == char then
				return p
			end
		end
		return nil
	end,
	GetPlayerByUserId = function(self, id)
		for _, p in self:GetPlayers() do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end,
}
Getters.Players = {
	LocalPlayer = function(self)
		if Emu.context == "client" then
			return Emu.localPlayer
		end
		return nil
	end,
}
Defaults.Players = { CharacterAutoLoads = true, MaxPlayers = 8 }

local function loadCharacter(player)
	if Emu.context ~= "server" then
		error("LoadCharacter can only be called by the server", 3)
	end
	local old = rawget(player, "_props").Character
	if old then
		getSignal(player, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	local sp = services.StarterPlayer
	local template = sp:FindFirstChild("StarterCharacter")
	if not template then
		error("emulator: no StarterCharacter", 3)
	end
	local char = template:Clone()
	rawset(char, "_name", rawget(player, "_name"))
	local scs = sp:FindFirstChildOfClass("StarterCharacterScripts")
	for _, s in scs:GetChildren() do
		s:Clone().Parent = char
	end
	char:PivotTo(CFrame.new(0, 3.1, 0))
	Emu.internalWrite = true
	rawget(player, "_props").Character = char
	Emu.internalWrite = false
	char.Parent = services.Workspace
	getSignal(player, "CharacterAdded"):Fire(char)
end
Methods.Player = {
	LoadCharacter = function(self)
		loadCharacter(self)
	end,
	LoadCharacterAsync = function(self)
		loadCharacter(self)
	end,
	Kick = function(self, msg)
		report("player kicked: " .. tostring(msg))
	end,
	GetMouse = function()
		return rawNew("PlayerMouse")
	end,
	GetNetworkPing = function()
		return 0.05
	end,
}

function Emu.addPlayer(name, userId)
	local p = rawNew("Player")
	rawset(p, "_name", name)
	Emu.internalWrite = true
	p.UserId = userId or 1
	p.DisplayName = name
	Emu.internalWrite = false
	local pg = rawNew("PlayerGui")
	rawset(pg, "_name", "PlayerGui")
	pg.Parent = p
	local ps = rawNew("PlayerScripts")
	rawset(ps, "_name", "PlayerScripts")
	ps.Parent = p
	local bp = rawNew("Backpack")
	rawset(bp, "_name", "Backpack")
	bp.Parent = p
	Emu.localPlayer = p
	p.Parent = services.Players
	getSignal(services.Players, "PlayerAdded"):Fire(p)
	return p
end

-- Remote events: loopback with one frame of latency and serialization checks
local function serialize(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "function" or t == "thread" then
		error("remote argument cannot be a " .. t, 4)
	end
	if t == "number" and v ~= v then
		error("remote argument is NaN", 4)
	end
	if t == "table" and emuTypeof(v) == "table" then
		if depth > 20 then
			error("remote table too deep", 4)
		end
		local out = {}
		local hasArray, hasHash = #v > 0, false
		for k, val in v do
			if type(k) ~= "number" then
				hasHash = true
				if type(k) ~= "string" then
					error("remote table key must be string or number", 4)
				end
			end
			out[k] = serialize(val, depth + 1)
		end
		if hasArray and hasHash then
			error("remote table mixes array and dictionary keys", 4)
		end
		return out
	end
	return v
end
local function packArgs(...)
	local n = select("#", ...)
	local out = { n = n }
	for i = 1, n do
		out[i] = serialize((select(i, ...)))
	end
	return out
end
local pendingRemotes = {}
Methods.RemoteEvent = {
	FireServer = function(self, ...)
		if Emu.context ~= "client" then
			error("FireServer can only be called from the client", 2)
		end
		local args = packArgs(...)
		local player = Emu.localPlayer
		table.insert(pendingRemotes, function()
			getSignal(self, "OnServerEvent"):FireCtx("server", player, table.unpack(args, 1, args.n))
		end)
	end,
	FireClient = function(self, player, ...)
		if Emu.context ~= "server" then
			error("FireClient can only be called from the server", 2)
		end
		if not isInstance(player) or not player:IsA("Player") then
			error("FireClient: first argument must be a Player", 2)
		end
		local args = packArgs(...)
		table.insert(pendingRemotes, function()
			getSignal(self, "OnClientEvent"):FireCtx("client", table.unpack(args, 1, args.n))
		end)
	end,
	FireAllClients = function(self, ...)
		if Emu.context ~= "server" then
			error("FireAllClients can only be called from the server", 2)
		end
		local args = packArgs(...)
		table.insert(pendingRemotes, function()
			getSignal(self, "OnClientEvent"):FireCtx("client", table.unpack(args, 1, args.n))
		end)
	end,
}
Methods.UnreliableRemoteEvent = Methods.RemoteEvent
Methods.BindableEvent = {
	Fire = function(self, ...)
		getSignal(self, "Event"):Fire(...)
	end,
}
Methods.RemoteFunction = {
	InvokeServer = function(self, ...)
		local cb = rawget(self, "_onServerInvoke")
		if not cb then
			error("emulator: RemoteFunction has no OnServerInvoke", 2)
		end
		local args = packArgs(...)
		local prev = Emu.context
		Emu.context = "server"
		local results = table.pack(cb(Emu.localPlayer, table.unpack(args, 1, args.n)))
		Emu.context = prev
		local outv = packArgs(table.unpack(results, 1, results.n))
		return table.unpack(outv, 1, outv.n)
	end,
}

-- input
Emu.mouse = DT.Vector2.new(640, 360)
Methods.UserInputService = {
	GetMouseLocation = function()
		return Emu.mouse
	end,
	IsKeyDown = function()
		return false
	end,
	GetLastInputType = function()
		return Emu.Enum.UserInputType.MouseMovement
	end,
	GetKeysPressed = function()
		return {}
	end,
}
Defaults.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }
Emu.actions = {}
Methods.ContextActionService = {
	BindAction = function(self, name, fn, touch, ...)
		Emu.actions[name] = fn
	end,
	BindActionAtPriority = function(self, name, fn, touch, priority, ...)
		if type(priority) ~= "number" then
			error("BindActionAtPriority: priority must be a number", 2)
		end
		Emu.actions[name] = fn
	end,
	UnbindAction = function(self, name)
		Emu.actions[name] = nil
	end,
	SetTitle = function(self, name, title)
		if type(title) ~= "string" then
			error("SetTitle expects a string", 2)
		end
	end,
	SetPosition = function(self, name, pos)
		if emuTypeof(pos) ~= "UDim2" then
			error("SetPosition expects a UDim2", 2)
		end
	end,
	SetImage = function() end,
	SetDescription = function() end,
	GetButton = function()
		return nil
	end,
}
function Emu.pressAction(name)
	local fn = Emu.actions[name]
	if not fn then
		report("emulator: action " .. name .. " is not bound")
		return
	end
	local input = { UserInputType = Emu.Enum.UserInputType.Keyboard, KeyCode = Emu.Enum.KeyCode.Space, Position = Vector3.new(0, 0, 0) }
	spawnIn("client", function()
		local r = fn(name, Emu.Enum.UserInputState.Begin, input)
		if r ~= nil and emuTypeof(r) ~= "EnumItem" then
			report("action handler returned a non-enum result")
		end
		fn(name, Emu.Enum.UserInputState.End, input)
	end)
end
function Emu.pressKey(keyName)
	local input = { UserInputType = Emu.Enum.UserInputType.Keyboard, KeyCode = Emu.Enum.KeyCode[keyName], Position = Vector3.new(0, 0, 0) }
	getSignal(services.UserInputService, "InputBegan"):FireCtx("client", input, false)
	getSignal(services.UserInputService, "InputEnded"):FireCtx("client", input, false)
end

-- camera
Defaults.Camera = {
	FieldOfView = 70,
	CFrame = function()
		return CFrame.new(0, 20, 20)
	end,
}
Getters.Camera = {
	ViewportSize = function()
		return DT.Vector2.new(1280, 720)
	end,
	Focus = function(self)
		return self.CFrame
	end,
}
local function camBasis(cam)
	local cf = cam.CFrame
	return cf.Position, cf.RightVector, cf.UpVector, cf.LookVector
end
Methods.Camera = {
	ViewportPointToRay = function(self, x, y)
		local o, r, u, l = camBasis(self)
		local w, h = 1280, 720
		local tanY = math.tan(math.rad(self.FieldOfView) / 2)
		local nx = (x / w) * 2 - 1
		local ny = 1 - (y / h) * 2
		local d = (l + r * (nx * tanY * w / h) + u * (ny * tanY)).Unit
		return DT.Ray.new(o, d)
	end,
	ScreenPointToRay = function(self, x, y)
		return self:ViewportPointToRay(x, y + 58)
	end,
	WorldToViewportPoint = function(self, p)
		local o, r, u, l = camBasis(self)
		local d = p - o
		local z = d:Dot(l)
		local tanY = math.tan(math.rad(self.FieldOfView) / 2)
		local w, h = 1280, 720
		local nx = d:Dot(r) / (z * tanY * w / h)
		local ny = d:Dot(u) / (z * tanY)
		local sx = (nx + 1) / 2 * w
		local sy = (1 - ny) / 2 * h
		return Vector3.new(sx, sy, z), z > 0 and math.abs(nx) <= 1 and math.abs(ny) <= 1
	end,
}
Methods.Camera.WorldToScreenPoint = Methods.Camera.WorldToViewportPoint

-- misc services
Methods.PhysicsService = {
	RegisterCollisionGroup = function(self, name)
		Emu.groups = Emu.groups or {}
		Emu.groups[name] = true
	end,
	IsCollisionGroupRegistered = function(self, name)
		return Emu.groups ~= nil and Emu.groups[name] == true or name == "Default"
	end,
	CollisionGroupSetCollidable = function(self, a, b, v)
		if not (Emu.groups and Emu.groups[a] or a == "Default") or not (Emu.groups and Emu.groups[b] or b == "Default") then
			error("CollisionGroupSetCollidable: group not registered (" .. a .. ", " .. b .. ")", 2)
		end
		if type(v) ~= "boolean" then
			error("CollisionGroupSetCollidable expects a boolean", 2)
		end
	end,
	CollisionGroupsAreCollidable = function()
		return true
	end,
}
Setters.BasePart.CollisionGroup = function(self, v)
	if v ~= "Default" and not (Emu.groups and Emu.groups[v]) then
		report("CollisionGroup '" .. tostring(v) .. "' is not registered (" .. self:GetFullName() .. ")")
	end
	rawget(self, "_props").CollisionGroup = v
end
Methods.Debris = {
	AddItem = function(self, item, t)
		task.delay(t or 10, function()
			item:Destroy()
		end)
	end,
}
Methods.StarterGui = {
	SetCoreGuiEnabled = function(self, t, v)
		if emuTypeof(t) ~= "EnumItem" then
			error("SetCoreGuiEnabled expects a CoreGuiType", 2)
		end
	end,
	SetCore = function() end,
	GetCore = function()
		return nil
	end,
}
Methods.SoundService = {
	PlayLocalSound = function() end,
}
Methods.Sound = {
	Play = function(self)
		rawget(self, "_props").IsPlaying = true
		task.delay(0.5, function()
			getSignal(self, "Ended"):Fire(self.SoundId)
		end)
	end,
	Stop = function(self)
		rawget(self, "_props").IsPlaying = false
	end,
	Pause = function() end,
	Resume = function() end,
}
Defaults.Sound = { Volume = 0.5, PlaybackSpeed = 1 }
Methods.ParticleEmitter = {
	Emit = function(self, n)
		if type(n) ~= "number" then
			error("Emit expects a number", 2)
		end
	end,
	Clear = function() end,
}
Defaults.ParticleEmitter = { Enabled = true, Rate = 5, LightEmission = 0 }
Methods.TweenService = {
	Create = function(self, inst, info, goals)
		if not isInstance(inst) or emuTypeof(info) ~= "TweenInfo" or type(goals) ~= "table" then
			error("TweenService:Create bad arguments", 2)
		end
		for k in goals do
			local m = lookupMember(rawget(inst, "_class"), k)
			if not m or m.kind ~= "prop" then
				error("TweenService:Create: " .. k .. " is not a property of " .. rawget(inst, "_class"), 2)
			end
		end
		local tw = rawNew("Tween")
		rawset(tw, "_inst", inst)
		rawset(tw, "_goals", goals)
		rawset(tw, "_time", info.Time)
		return tw
	end,
	GetValue = function(self, a)
		return a
	end,
}
Methods.Tween = {
	Play = function(self)
		local inst, goals = rawget(self, "_inst"), rawget(self, "_goals")
		task.delay(rawget(self, "_time"), function()
			for k, v in goals do
				inst[k] = v
			end
			getSignal(self, "Completed"):Fire(Emu.Enum.PlaybackState.Completed)
		end)
	end,
	Cancel = function() end,
	Pause = function() end,
}
Methods.Humanoid = {
	SetStateEnabled = function(self, st, on)
		if emuTypeof(st) ~= "EnumItem" or type(on) ~= "boolean" then
			error("SetStateEnabled bad arguments", 2)
		end
	end,
	ChangeState = function() end,
	GetState = function()
		return Emu.Enum.HumanoidStateType.Running
	end,
	Move = function(self, dir)
		Emu.internalWrite = true
		self.MoveDirection = dir
		Emu.internalWrite = false
	end,
	MoveTo = function() end,
	TakeDamage = function(self, d)
		self.Health -= d
	end,
	GetPlayingAnimationTracks = function()
		return {}
	end,
	LoadAnimation = function()
		error("emulator: LoadAnimation not supported", 2)
	end,
}
Defaults.Humanoid = { WalkSpeed = 16, MaxHealth = 100, Health = 100, HipHeight = 2, JumpPower = 50, AutoRotate = true, RequiresNeck = true, BreakJointsOnDeath = true }
Defaults.GuiObject = {
	Visible = true,
	BackgroundTransparency = 0,
	Size = DT.UDim2.new(0, 100, 0, 100),
	BackgroundColor3 = function()
		return Color3.new(1, 1, 1)
	end,
}
Defaults.GuiButton = { AutoButtonColor = true }
Defaults.LayerCollector = { Enabled = true, ResetOnSpawn = true }
Defaults.TextLabel = { TextSize = 14, TextTransparency = 0 }
Defaults.TextButton = { TextSize = 14, TextTransparency = 0 }
Defaults.Trail = { Enabled = true, Lifetime = 2 }
Defaults.Highlight = { Enabled = true, FillTransparency = 0.5, OutlineTransparency = 0 }
Defaults.Light = { Enabled = true, Brightness = 1 }
Defaults.Constraint = { Enabled = true }
Defaults.ProximityPrompt = { Enabled = true, MaxActivationDistance = 10, HoldDuration = 0, ActionText = "Interact" }
Defaults.UIStroke = { Thickness = 1, Enabled = true }
Defaults.UIGradient = { Enabled = true }
Defaults.BillboardGui = { Enabled = true }
Methods.GuiObject = {
	TweenSize = function()
		return true
	end,
	TweenPosition = function()
		return true
	end,
	TweenSizeAndPosition = function()
		return true
	end,
}
Getters.GuiBase2d = {
	AbsoluteSize = function()
		return DT.Vector2.new(100, 30)
	end,
	AbsolutePosition = function()
		return DT.Vector2.new(0, 0)
	end,
}
Methods.CollectionService = {
	AddTag = function(self, inst, tag)
		local tags = rawget(inst, "_tags") or {}
		tags[tag] = true
		rawset(inst, "_tags", tags)
	end,
	RemoveTag = function(self, inst, tag)
		local tags = rawget(inst, "_tags")
		if tags then
			tags[tag] = nil
		end
	end,
	HasTag = function(self, inst, tag)
		local tags = rawget(inst, "_tags")
		return tags ~= nil and tags[tag] == true
	end,
	GetTagged = function(self, tag)
		local out = {}
		for inst in allInstances do
			local tags = rawget(inst, "_tags")
			if tags and tags[tag] and not rawget(inst, "_destroyed") then
				table.insert(out, inst)
			end
		end
		return out
	end,
}
Methods.Instance.AddTag = function(self, tag)
	Methods.CollectionService.AddTag(nil, self, tag)
end
Methods.Instance.HasTag = function(self, tag)
	return Methods.CollectionService.HasTag(nil, self, tag)
end
Methods.Instance.RemoveTag = function(self, tag)
	Methods.CollectionService.RemoveTag(nil, self, tag)
end

-- DataStores (in-memory, survives the emulator session)
Emu.dataStores = {}
Emu.dataStoreFail = false
local function dsCheck()
	if Emu.context ~= "server" then
		error("DataStoreService can only be used from the server", 3)
	end
	if Emu.dataStoreFail then
		error("emulated DataStore failure (Studio API access disabled)", 3)
	end
	task.wait(0.05)
end
Methods.DataStoreService = {
	GetDataStore = function(self, name, scope)
		local key = name .. "/" .. (scope or "global")
		if not Emu.dataStores[key] then
			local ds = rawNew("DataStore")
			rawset(ds, "_name", name)
			rawset(ds, "_data", {})
			Emu.dataStores[key] = ds
		end
		return Emu.dataStores[key]
	end,
	GetOrderedDataStore = function(self, name)
		return Methods.DataStoreService.GetDataStore(self, "ordered:" .. name)
	end,
}
local function deep(v)
	if type(v) == "table" then
		local o = {}
		for k, x in v do
			o[k] = deep(x)
		end
		return o
	end
	return v
end
Methods.GlobalDataStore = {
	GetAsync = function(self, key)
		dsCheck()
		return deep(rawget(self, "_data")[key])
	end,
	SetAsync = function(self, key, value)
		dsCheck()
		rawget(self, "_data")[key] = deep(serialize(value))
	end,
	UpdateAsync = function(self, key, fn)
		dsCheck()
		local cur = deep(rawget(self, "_data")[key])
		local new = fn(cur)
		if new ~= nil then
			rawget(self, "_data")[key] = deep(serialize(new))
		end
		return deep(new)
	end,
	RemoveAsync = function(self, key)
		dsCheck()
		local cur = rawget(self, "_data")[key]
		rawget(self, "_data")[key] = nil
		return cur
	end,
	IncrementAsync = function(self, key, d)
		dsCheck()
		local cur = (rawget(self, "_data")[key] or 0) + (d or 1)
		rawget(self, "_data")[key] = cur
		return cur
	end,
}

------------------------------------------------------------------------ scripts
local moduleCache = { server = {}, client = {} }

local function makeEnv(scriptInst)
	local env
	env = setmetatable({
		script = scriptInst,
		game = Emu.game,
		workspace = Emu.workspace,
		Workspace = Emu.workspace,
		Instance = Instance,
		Enum = Emu.Enum,
		task = task,
		typeof = emuTypeof,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		Vector2 = DT.Vector2,
		UDim = DT.UDim,
		UDim2 = DT.UDim2,
		NumberSequence = DT.NumberSequence,
		NumberSequenceKeypoint = DT.NumberSequenceKeypoint,
		ColorSequence = DT.ColorSequence,
		ColorSequenceKeypoint = DT.ColorSequenceKeypoint,
		NumberRange = DT.NumberRange,
		PhysicalProperties = DT.PhysicalProperties,
		Font = DT.Font,
		TweenInfo = DT.TweenInfo,
		Ray = DT.Ray,
		Rect = DT.Rect,
		RaycastParams = DT.RaycastParams,
		OverlapParams = DT.OverlapParams,
		Random = DT.Random,
		tick = function()
			return Emu.time
		end,
		time = function()
			return Emu.time
		end,
		elapsedTime = function()
			return Emu.time
		end,
		wait = function(t)
			warnOnce("wait", "deprecated global wait() used")
			return task.wait(t)
		end,
		spawn = function(f)
			warnOnce("spawn", "deprecated global spawn() used")
			task.defer(f)
		end,
		delay = function(t, f)
			warnOnce("delay", "deprecated global delay() used")
			task.delay(t, f)
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			print("[warn] " .. table.concat(parts, " "))
		end,
		print = function(...)
			if Emu.quiet then
				return
			end
			print(...)
		end,
		require = function(m)
			return Emu.require(m)
		end,
		shared = {},
		os = setmetatable({
			clock = function()
				return Emu.time
			end,
			time = function()
				return math.floor(1700000000 + Emu.time)
			end,
		}, { __index = os }),
	}, { __index = _G })
	return env
end

function Emu.require(m)
	if not isInstance(m) or rawget(m, "_class") ~= "ModuleScript" then
		error("require: expected a ModuleScript, got " .. emuTypeof(m), 3)
	end
	local cache = moduleCache[Emu.context]
	local hit = cache[m]
	if hit then
		if hit.loading then
			error("require: cyclic dependency on " .. m:GetFullName(), 3)
		end
		return hit.value
	end
	cache[m] = { loading = true }
	local src = readfile(rawget(m, "_source"))
	local fn = loadchunk(src, m:GetFullName())
	setfenv(fn, makeEnv(m))
	local value = fn()
	if value == nil then
		error("Module code did not return exactly one value: " .. m:GetFullName(), 3)
	end
	cache[m] = { value = value }
	return value
end

function Emu.runScript(scriptInst, ctx)
	spawnIn(ctx, function()
		local src = readfile(rawget(scriptInst, "_source"))
		local fn = loadchunk(src, scriptInst:GetFullName())
		setfenv(fn, makeEnv(scriptInst))
		fn()
	end)
end

-- Build a Script/LocalScript/ModuleScript tree from a directory listing { name = path or {children} }.
function Emu.scriptInstance(cls, name, source)
	local s = rawNew(cls)
	rawset(s, "_name", name)
	rawset(s, "_source", source)
	return s
end

------------------------------------------------------------------------ physics (kinematic)
local function jointsIn(root)
	local list = {}
	for _, d in root:GetDescendants() do
		local c = rawget(d, "_class")
		if c == "Motor6D" or c == "Weld" or c == "WeldConstraint" then
			table.insert(list, d)
		end
	end
	return list
end

function Emu.assemblyRoot(part)
	return part
end

local function updateJoints(model)
	local joints = jointsIn(model)
	for _ = 1, 4 do
		for _, j in joints do
			local props = rawget(j, "_props")
			local p0, p1 = props.Part0, props.Part1
			if p0 and p1 and rawget(j, "_class") ~= "WeldConstraint" then
				local c0 = props.C0 or CFrame.new()
				local c1 = props.C1 or CFrame.new()
				local t = props.Transform or CFrame.new()
				rawget(p1, "_props").CFrame = (rawget(p0, "_props").CFrame or CFrame.new()) * c0 * t * c1:Inverse()
			end
		end
	end
end

local function findConstraint(root, cls)
	for _, d in root:GetDescendants() do
		if rawget(d, "_class") == cls and rawget(d, "_props").Enabled ~= false then
			local att = rawget(d, "_props").Attachment0
			if att and rawget(att, "_parent") == root then
				return d
			end
		end
	end
	return nil
end

function Emu.physicsStep(dt)
	local ws = Emu.workspace
	local g = ws.Gravity
	local models = {}
	for _, d in ws:GetDescendants() do
		if rawget(d, "_class") == "Model" and rawget(d, "_props").PrimaryPart then
			table.insert(models, d)
		end
	end
	for _, model in models do
		local root = rawget(model, "_props").PrimaryPart
		local rp = rawget(root, "_props")
		if not rp.Anchored and root:IsDescendantOf(ws) then
			local cf = rp.CFrame or CFrame.new()
			local vel = rp.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
			local hum = model:FindFirstChildOfClass("Humanoid")
			local lv = findConstraint(root, "LinearVelocity")
			local vx, vz = 0, 0
			if lv then
				local pv = rawget(lv, "_props").PlaneVelocity or DT.Vector2.new(0, 0)
				vx, vz = pv.X, pv.Y
			elseif hum then
				local md = rawget(hum, "_props").MoveDirection or Vector3.new(0, 0, 0)
				local ws_ = rawget(hum, "_props").WalkSpeed or 16
				vx, vz = md.X * ws_, md.Z * ws_
			else
				vx, vz = vel.X, vel.Z
			end
			local size = rp.Size or Vector3.new(2, 2, 1)
			local rest = size.Y / 2
			if hum then
				rest = (rawget(hum, "_props").HipHeight or 2) + size.Y / 2
			end
			local pos = cf.Position
			local onArena = Vector3.new(pos.X, 0, pos.Z).Magnitude <= 60
			local vy = vel.Y
			if onArena and pos.Y <= rest + 0.01 and vy <= 0 then
				vy = 0
			else
				vy -= g * dt
			end
			local np = pos + Vector3.new(vx, vy, vz) * dt
			if onArena and np.Y < rest and pos.Y >= rest - 0.5 then
				np = Vector3.new(np.X, rest, np.Z)
				vy = 0
			end
			if hum then
				local flat = Vector3.new(np.X, 0, np.Z)
				if flat.Magnitude > 59 then
					flat = flat.Unit * 59
					np = Vector3.new(flat.X, np.Y, flat.Z)
				end
			end
			local rot = cf.Rotation
			local ao = findConstraint(root, "AlignOrientation")
			if ao then
				rot = (rawget(ao, "_props").CFrame or CFrame.new()).Rotation
			end
			rp.CFrame = rot + np
			rp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
			updateJoints(model)
		end
	end
end

------------------------------------------------------------------------ frame
function Emu.step(dt)
	Emu.time += dt
	Emu.frame += 1
	local rs = services.RunService
	-- client render step
	local steps = {}
	for name, s in Emu.renderSteps do
		table.insert(steps, { name = name, priority = s.priority, fn = s.fn })
	end
	table.sort(steps, function(a, b)
		return a.priority < b.priority
	end)
	for _, s in steps do
		spawnIn("client", s.fn, dt)
	end
	getSignal(rs, "PreRender"):Fire(dt)
	getSignal(rs, "RenderStepped"):Fire(dt)
	getSignal(rs, "PreAnimation"):Fire(dt)
	getSignal(rs, "PreSimulation"):Fire(dt)
	getSignal(rs, "Stepped"):Fire(Emu.time, dt)
	Emu.physicsStep(dt)
	getSignal(rs, "PostSimulation"):Fire(dt)
	getSignal(rs, "Heartbeat"):Fire(dt)
	local remotes = pendingRemotes
	pendingRemotes = {}
	for _, fn in remotes do
		fn()
	end
	runScheduler()
end

return Emu
