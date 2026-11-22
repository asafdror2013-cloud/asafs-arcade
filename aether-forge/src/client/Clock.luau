--!nonstrict
-- Clock: the client's game-feel time. Hitstop freezes local simulation (your swing, enemy poses);
-- slow-motion scales it. Everything that should feel the freeze advances by Clock.dt instead of the
-- real frame time. Defensive windows (parry, i-frames) use server time and are never slowed.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherForge").Config)

local Clock = {
	real = 0, -- real seconds since start
	sim = 0, -- simulated (scaled) seconds since start
	dt = 0, -- scaled delta of the current frame
	realDt = 0,
	hitstopUntil = 0,
	slowUntil = 0,
	slowStart = 0,
	slowScale = 1,
}

function Clock.hitstop(duration)
	Clock.hitstopUntil = math.max(Clock.hitstopUntil, Clock.real + duration)
end

function Clock.slowmo(scale, duration)
	Clock.slowScale = scale
	Clock.slowStart = Clock.real
	Clock.slowUntil = Clock.real + duration
end

function Clock.inHitstop()
	return Clock.real < Clock.hitstopUntil
end

function Clock.scale()
	local s = Config.Feel.DebugTimeScale or 1
	if Clock.real < Clock.hitstopUntil then
		return 0
	end
	if Clock.real < Clock.slowUntil then
		-- ease back to full speed over the last 40% of the slow-mo
		local total = Clock.slowUntil - Clock.slowStart
		local left = Clock.slowUntil - Clock.real
		local k = math.clamp(left / (total * 0.4), 0, 1)
		s *= Clock.slowScale + (1 - Clock.slowScale) * (1 - k)
	end
	return s
end

function Clock.step(realDt)
	Clock.realDt = realDt
	Clock.real += realDt
	Clock.dt = realDt * Clock.scale()
	Clock.sim += Clock.dt
	return Clock.dt
end

function Clock.server()
	return workspace:GetServerTimeNow()
end

return Clock
