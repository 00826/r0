--!strict

local RunService = game:GetService("RunService")

type ExtrapolateStepResult = typeof(require(script.Parent:WaitForChild("TransformExtrapolator")).step(...))

--- ### Limiter.luau
---
--- queries viewport against workspace
local Limiter = {
	--- camera object used by this module
	Camera = workspace.CurrentCamera;

	FieldOfViewConnection = nil :: RBXScriptConnection?;
	ViewportSizeConnection = nil :: RBXScriptConnection?;
	NearPlaneZConnection = nil :: RBXScriptConnection?;

	--- viewport projection x
	ProjectionX = 0;
	--- viewport projection y
	ProjectionY = 0;
	--- near plane z
	NearPlaneZ = -0.1;

	--- raycast limit when querying collision points
	QueryPointCastLimit = 64;
	--- offsets used to test for soft limits
	QuerySampleOffsets = {
		Vector2.new(0.4, 0.0),
		Vector2.new(-0.4, 0.0),
		Vector2.new(0.0, -0.4),
		Vector2.new(0.0, 0.4),
		Vector2.new(0.0, 0.2),
	};

	--- clip through baseparts with a transparency below this value
	TransparencyLimit = 0.25;

	--- whitelist raycast params
	WhitelistParams = RaycastParams.new();
	--- raycastparam whitelist
	Whitelist = table.create(16);

	--- whitelist raycast params
	BlacklistParams = RaycastParams.new();
	--- raycastparam blacklist
	Blacklist = table.create(16);
}

function Limiter.cast(focus: CFrame, targetdistance: number, extrapolatorresult: ExtrapolateStepResult)
	local realdistance = targetdistance

	local softlimit, hardlimit = Limiter.queryviewport(focus, targetdistance)
	if hardlimit < realdistance then
		realdistance = hardlimit
	end
	if softlimit < realdistance and Limiter.testpromotion(focus, targetdistance, extrapolatorresult) then
		realdistance = softlimit
	end

	return realdistance
end

function Limiter.getcollisionpoint(origin: Vector3, direction: Vector3)
	Limiter.BlacklistParams.FilterDescendantsInstances = Limiter.Blacklist
	repeat
		local result = workspace:Raycast(origin, direction, Limiter.BlacklistParams)

		if result then
			if result.Instance.CanCollide then
				return result.Position, true
			end
			Limiter.BlacklistParams:AddToFilter(result.Instance)
		end
	until not result

	return origin + direction, false
end

function Limiter.querypoint(origin: Vector3, unit: Vector3, dist: number, lastposition: Vector3?)
	debug.profilebegin("querypoint")

	local blacklistparams = Limiter.BlacklistParams
	local whitelistparams = Limiter.WhitelistParams

	local nearplanez = Limiter.NearPlaneZ

	dist += nearplanez
	local target = origin + unit*dist

	local softlimit = math.huge
	local hardlimit = math.huge
	local movingorigin = origin

	local piercecount = 0
	
	blacklistparams.FilterDescendantsInstances = Limiter.Blacklist
	repeat
		local entryresult = workspace:Raycast(movingorigin, target - movingorigin, blacklistparams)

		if not entryresult then
			break
		end

		piercecount += 1

		local entryinstance, entryposition = entryresult.Instance, entryresult.Position
		local lim = (entryposition - origin).Magnitude

		if piercecount >= Limiter.QueryPointCastLimit then
			hardlimit = lim
		elseif Limiter.canocclude(entryinstance) then
			whitelistparams.FilterDescendantsInstances = { entryinstance }

			local exitresult = workspace:Raycast(target, entryposition - target, whitelistparams)
			if exitresult then
				local promote = if lastposition then
					(workspace:Raycast(lastposition, target - lastposition, whitelistparams) or
						workspace:Raycast(target, lastposition - target, whitelistparams)) else false

				if promote then
					--- Ostensibly a soft limit, but the camera has passed through it in the last frame, so promote to a hard limit.
					hardlimit = lim
				elseif dist < softlimit then
					--- Trivial soft limit
					softlimit = lim
				end
			else
				--- Trivial hard limit
				hardlimit = lim
			end
		end

		blacklistparams:AddToFilter(entryinstance)
		movingorigin = entryposition - unit*1e-3
	until hardlimit < math.huge or not entryinstance

	debug.profileend()
	return softlimit - nearplanez, hardlimit - nearplanez
end

function Limiter.queryviewport(focus: CFrame, distance: number)
	debug.profilebegin("queryviewport")

	local focusposition = focus.Position
	local focusrightvector = focus.RightVector
	local focusupvector = focus.UpVector
	local focuslookvector = -focus.LookVector

	local projectionx = Limiter.ProjectionX
	local nearplanez = Limiter.NearPlaneZ
	
	local camera = Limiter.Camera
	local viewport = camera.ViewportSize

	local hardboxlimit = math.huge
	local softboxlimit = math.huge

	--- Center the viewport on the PoI, sweep points on the edge towards the target, and take the minimum limits
	for viewX = 0, 1 do
		local worldX = focusrightvector*((viewX - 0.5)*projectionx)

		for viewY = 0, 1 do
			local worldY = focusupvector*((viewY - 0.5)*projectionx)

			local origin = focusposition + nearplanez*(worldX + worldY)
			local lastPos = camera:ViewportPointToRay(
				viewport.X*viewX,
				viewport.Y*viewY
			).Origin

			local softPointLimit, hardPointLimit = Limiter.querypoint(origin, focuslookvector, distance, lastPos)

			if hardPointLimit < hardboxlimit then
				hardboxlimit = hardPointLimit
			end
			if softPointLimit < softboxlimit then
				softboxlimit = softPointLimit
			end
		end
	end
	debug.profileend()

	return softboxlimit, hardboxlimit
end

function Limiter.testpromotion(focus: CFrame, distance: number, extrapolatestepresult: ExtrapolateStepResult)
	debug.profilebegin("testpromotion")

	local focusposition = focus.Position
	local focusrightvector = focus.RightVector
	local focusupvector = focus.UpVector
	local focuslookvector = -focus.LookVector

	do
		--- Dead reckoning the camera rotation and focus
		debug.profilebegin("extrapolate")

		local SAMPLE_DT = 0.0625
		local SAMPLE_MAX_T = 1.25

		local translationvelocity = extrapolatestepresult.translationvelocity
		local rotationvelocity = extrapolatestepresult.rotationvelocity

		local maxDist = (Limiter.getcollisionpoint(focusposition, translationvelocity*SAMPLE_MAX_T) - focusposition).Magnitude
		--- Metric that decides how many samples to take
		local combinedSpeed = vector.magnitude(translationvelocity::any)

		for dt = 0, math.min(SAMPLE_MAX_T, vector.magnitude(rotationvelocity::any) + maxDist/combinedSpeed), SAMPLE_DT do
			local extrapolatedcframewrtdt = extrapolatestepresult.extrapolate(dt) --- Extrapolated CFrame at time dt

			if Limiter.querypoint(extrapolatedcframewrtdt.Position, -extrapolatedcframewrtdt.LookVector, distance) >= distance then
				return false
			end
		end

		debug.profileend()
	end

	do
		--- Test screen-space offsets from the focus for the presence of soft limits
		debug.profilebegin("testoffsets")

		for _, offset in ipairs(Limiter.QuerySampleOffsets) do
			local pos = Limiter.getcollisionpoint(focusposition, focusrightvector*offset.X + focusupvector*offset.Y)
			if Limiter.querypoint(pos, vector.normalize(focusposition::any + focuslookvector*distance - pos)::any, distance) == math.huge then
				return false
			end
		end

		debug.profileend()
	end

	debug.profileend()
	return true
end

function Limiter.setcamera(camera: Camera)
	Limiter.Camera = camera

	Limiter.projectionchanged(camera)

	if Limiter.FieldOfViewConnection then
		Limiter.FieldOfViewConnection:Disconnect()
		Limiter.FieldOfViewConnection = nil
	end
	Limiter.FieldOfViewConnection = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		Limiter.projectionchanged(camera)
	end)

	if Limiter.ViewportSizeConnection then
		Limiter.ViewportSizeConnection:Disconnect()
		Limiter.ViewportSizeConnection = nil
	end
	Limiter.ViewportSizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		Limiter.projectionchanged(camera)
	end)

	if Limiter.NearPlaneZConnection then
		Limiter.NearPlaneZConnection:Disconnect()
		Limiter.NearPlaneZConnection = nil
	end
	Limiter.FieldOfViewConnection = camera:GetPropertyChangedSignal("NearPlaneZ"):Connect(function()
		Limiter.NearPlaneZ = camera.NearPlaneZ
	end)
end

function Limiter.projectionchanged(camera: Camera)
	local fieldofviewradians = math.rad(camera.FieldOfView)
	local viewportsize = camera.ViewportSize
	local ar = viewportsize.X / viewportsize.Y

	local y = 2 * math.tan(fieldofviewradians * 0.5)
	local x = ar * y

	Limiter.ProjectionY = y
	Limiter.ProjectionX = x
end

function Limiter.gettotaltransparency(part: BasePart)
	return 1 - (1 - part.Transparency) * (1 - part.LocalTransparencyModifier)
end

function Limiter.canocclude(part: BasePart)
	-- Occluders must be:
	-- 1. Opaque
	-- 2. Interactable
	-- 3(x). Not in the same assembly as the subject

	return
		Limiter.gettotaltransparency(part) < Limiter.TransparencyLimit and
		part.CanCollide and
		--- subjectRoot ~= (part:GetRootPart() or part) and
		not part:IsA("TrussPart")
end

if RunService:IsClient() then
	local WhitelistParams = Limiter.WhitelistParams
	WhitelistParams.FilterType = Enum.RaycastFilterType.Include
	WhitelistParams.FilterDescendantsInstances = Limiter.Whitelist
	
	local BlacklistParams = Limiter.BlacklistParams
	BlacklistParams.FilterType = Enum.RaycastFilterType.Exclude
	BlacklistParams.FilterDescendantsInstances = Limiter.Blacklist

	Limiter.setcamera(Limiter.Camera)
end

return Limiter