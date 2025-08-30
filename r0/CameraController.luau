--!strict

local RunService = game:GetService("RunService")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ContextActionService = game:GetService("ContextActionService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local UserInputService = game:GetService("UserInputService")

local Limiter = require(script.Parent:WaitForChild("Limiter"))
local Spring = require(script.Parent:WaitForChild("Spring"))
local TransformExtrapolator = require(script.Parent:WaitForChild("TransformExtrapolator"))

--- ### CameraController.luau
---
--- camera controller
local CameraController = {
	--- camera object: \
	--- `CameraMode` and `CameraType` \
	--- are read-from internally \
	--- and written-to externally
	Camera = workspace.CurrentCamera;

	--- internal cameramode \
	--- this overwrites `CameraController.Camera.CameraMode`
	CameraMode = Enum.CameraMode.Classic;
	--- internal lockfirstperson \
	--- this overwrites `CameraController.Camera.CameraType` \
	--- \
	--- this should be either custom or scriptable \
	--- as all other cameratypes behaviors are best handled externally
	CameraType = Enum.CameraType.Custom;
	
	--- shiftlock value \
	--- original value: `Vector3.new(1.75, 0, 0)`
	CameraOffset = Vector3.new(0, 0, 0);

	--- camera distance limiter
	Limiter = require(script.Parent:WaitForChild("Limiter"));
	--- camera distance limiter extrapolator
	Extrapolator = TransformExtrapolator.create();
	--- camera distance limiter focus rotation
	FocusRotation = CFrame.new(
		0, 0, 0,
		-1, 0, 0,
		0, 1, 0,
		0, 0, -1
	);

	--- initial camera angle
	InitialCameraAngle = CFrame.fromOrientation(math.rad(-15), 0, 0);
	--- reset camera angle on next step
	ResetCameraAngle = true;

	--- input priority
	InputPriority = Enum.ContextActionPriority.Medium.Value;
	--- render priority
	RenderPriority = Enum.RenderPriority.Camera.Value;

	--- arrow key camera pan speed in radians/sec \
	--- ROTATION_SPEED_KEYS
	ArrowKeySpeed = math.rad(120);
	--- gamepad pan speed in radians/sec \
	--- ROTATION_SPEED_GAMEPAD
	GamepadSpeed = Vector2.new(1, 0.77) * math.rad(7);

	--- mouse pan speed in radians/sec
	--- ROTATION_SPEED_MOUSE
	MouseSpeed = Vector2.new(1, 0.77)*math.rad(0.5);
	--- pointer pan speed in radians/sec
	--- ROTATION_SPEED_POINTERACTION
	PointerSpeed = Vector2.new(1, 0.77)*math.rad(7);
	--- touch pan speed in radians/sec
	--- ROTATION_SPEED_TOUCH
	TouchSpeed = Vector2.new(1, 0.66)*math.rad(1);

	--- (scaled studs/wheel click)
	--- ZOOM_SPEED_MOUSE
	MouseZoomSpeed = 1;
	--- (studs/s)
	--- ZOOM_SPEED_KEYS
	KeyZoomSpeed = 0.1;
	--- (scaled studs/DIP %)
	--- ZOOM_SPEED_TOUCH
	TouchZoomSpeed = 0.04;

	--- "...Adjust the touch sensitivity so that sensitivity is reduced when swiping up \
	--- 25% sensitivity at 90°" \
	--- MIN_TOUCH_SENSITIVITY_FRACTION
	TouchSensitivityFraction = 0.25;

	--- gamepad pan deadzone
	GamepadDeadzone = 0.1;

	--- pan inputs as a single table \
	--- constructing a vector2 is expensive !! \
	--- `[1,  2]` gamepad x, y \
	--- `[3,  4]` keyboard arrow l, r \
	--- `[5,  6]` mouse delta x, y \
	--- `[7,  8]` pointer pan delta x, y \
	--- `[9, 10]` touch pan delta x, y
	PanInputs = table.create(10, 0);
	--- `[1]` keyboard i
	--- `[2]` keyboard o
	--- `[3]` mouse wheel (pointeraction)
	--- `[4]` mouse pinch (pointeraction)
	--- `[5]` touch pinch
	ZoomInputs = table.create(5, 0);

	GamepadZoomKeyCode = Enum.KeyCode.ButtonR3;
	GamepadZoomSteps = 3;
	CurrentGamepadZoomStep = 2;

	--- `Enum.UserInputType -> is pan-held` readwrite table
	PanInputMap = {
		[Enum.UserInputType.MouseButton2] = false;
		[Enum.UserInputType.Touch] = false;
	};

	--- boolean describing whether a pan input is being held
	HoldPan = false;

	--- internally-written time elapsed since last step
	LastStep = 0;

	--- default distance away from subject
	DefaultZoomDistance = 12.5;
	--- current zoom distance from subject
	CurrentZoomDistance = 0;

	--- zoom spring frequency
	ZoomSpringFrequency = 4.5;
	--- zoom spring acceleration
	ZoomSpringAcceleration = 0.0375;

	--- internal camera spring
	ZoomSpring = Spring.create(0, 0, 0, 0);

	--- zoom sensitivity curve
	ZoomSensitivityCurve = 0.5;
	--- min zoom when in first person
	FirstPersonDistanceMinZoom = 0.5;
	--- if zoom < this value, snaps to first-person
	FirstPersonDistanceSnap = 1;
	--- internally-set boolean describing whether camera is in first person
	InFirstPerson = false;

	--- "...Note: DotProduct check in CoordinateFrame::lookAt() prevents using values within about \
	--- 8.11 degrees of the +/- Y axis, that's why these limits are currently 80 degrees" \
	--- \
	--- camera min pitch
	CameraMinPitch = math.rad(-80);
	--- camera max pitch
	CameraMaxPitch = math.rad(80);

	--- camera min zoom distance \
	--- written to @ lowermost block
	CameraMinZoomDistance = 0;
	--- camera max zoom distance \
	--- written to @ lowermost block
	CameraMaxZoomDistance = 0;
}

--- advances cameracontroller by `dt`
function CameraController.step(dt: number)
	local now = os.clock()
	local realtime = now - CameraController.LastStep

	local camera = CameraController.Camera

	--- early exit if scriptable
	if CameraController.CameraType == Enum.CameraType.Scriptable then
		CameraController.reset()
		return
	end

	local cameracframe = camera.CFrame
	local camerasubject = camera.CameraSubject

	--- resolve camera subject cframe
	local camerasubjectcframe = CFrame.identity
	if camerasubject and camerasubject:IsA("BasePart") then
		camerasubjectcframe = camerasubject:GetPivot()
	end

	--- resolve camera reset angle
	local cameralookvector = cameracframe.LookVector
	if CameraController.ResetCameraAngle then
		if camerasubject and camerasubject:IsA("BasePart") then
			cameralookvector = (camerasubject:GetPivot() * CameraController.InitialCameraAngle).LookVector
		else
			cameralookvector = CameraController.InitialCameraAngle.LookVector
		end

		CameraController.ResetCameraAngle = false
	end

	--- resolve zoom
	local zoominput = CameraController.getzoominput()
	CameraController.stepzoom(zoominput)

	--- resolve spring
	local zoomspring = CameraController.ZoomSpring
	zoomspring.goal = CameraController.CurrentZoomDistance

	--- poppercam here to set maxvalue
	
	local zoomdistance = Spring.step(zoomspring, realtime)

	--- resolve rotations
	local rotateinput = CameraController.getrotationinput(realtime)
	local camerafocusposition = camerasubjectcframe.Position
	local newlookvector = CameraController.rotatelookvector(cameralookvector, rotateinput)

	--- resolve camera cframes
	local realcframe = CFrame.lookAlong(camerafocusposition - (zoomdistance * newlookvector), newlookvector)
	local realfocus = CFrame.lookAlong(camerafocusposition, newlookvector)
	
	--- apply camera offset (shiftlock) if not first person
	local cameraoffset = CameraController.CameraOffset
	if CameraController.CurrentZoomDistance <= CameraController.FirstPersonDistanceMinZoom then
		cameraoffset = Vector3.zero
	end
	if cameraoffset ~= Vector3.zero then
		local relativeoffset = cameraoffset.X * realcframe.RightVector + cameraoffset.Y * realcframe.UpVector + cameraoffset.Z * realcframe.LookVector

		realcframe += relativeoffset
		realfocus += relativeoffset
	end

	--- resolve zoom limit
	local limitedcframe do
		local limitedzoom = CameraController.CameraMaxZoomDistance

		local minpossiblezoom = CameraController.FirstPersonDistanceMinZoom
		local maxpossiblezoom = math.max(CameraController.CameraMaxZoomDistance, zoomdistance)

		if zoomspring.goal > 1 then
			local extrapolator = CameraController.Extrapolator
			local rotatedfocus = CFrame.lookAlong(realfocus.Position, -realcframe.LookVector) * CameraController.FocusRotation

			local extrapolationresult = TransformExtrapolator.step(extrapolator, realtime, rotatedfocus)
			limitedzoom = Limiter.cast(realfocus * CFrame.new(0, 0, minpossiblezoom), maxpossiblezoom - minpossiblezoom, extrapolationresult) + minpossiblezoom
			
			limitedcframe = rotatedfocus * CFrame.new(0, 0, limitedzoom)
		end

		zoomspring.mindistance = minpossiblezoom
		zoomspring.maxdistance = math.min(CameraController.CameraMaxZoomDistance, limitedzoom)

		limitedcframe = realcframe
	end

	--- finalize camera cframe
	realcframe = limitedcframe

	--- apply camera cframes
	camera.CFrame = realcframe
	camera.Focus = realfocus

	--- reset delta-based inputs
	CameraController.resetinputs()

	CameraController.LastStep = now
end

function CameraController.gamepadzoomstep(delta: number)
	local maxsteps = CameraController.GamepadZoomSteps
	local currentstep = (CameraController.CurrentGamepadZoomStep + delta) % maxsteps
	if currentstep < 1 then
		currentstep = maxsteps
	end

	CameraController.CurrentGamepadZoomStep = currentstep
	CameraController.CurrentZoomDistance = math.map(currentstep, 1, maxsteps, CameraController.CameraMinZoomDistance, CameraController.CameraMaxZoomDistance)
end

--- advances internal currentzoomdistance by zoominput
function CameraController.stepzoom(zoominput: number)
	local zoom = CameraController.CurrentZoomDistance

	if math.abs(zoominput) > 0 then
		local newzoom

		if zoominput > 0 then
			newzoom = zoom + zoominput*(1 + zoom*CameraController.ZoomSensitivityCurve)
			newzoom = math.max(newzoom, CameraController.FirstPersonDistanceSnap)
		else
			newzoom = (zoom + zoominput)/(1 - zoominput*CameraController.ZoomSensitivityCurve)
			newzoom = math.max(newzoom, CameraController.FirstPersonDistanceMinZoom)
		end

		if newzoom < CameraController.FirstPersonDistanceSnap then
			newzoom = CameraController.FirstPersonDistanceMinZoom
		end

		--- CameraController.resolvecurrentzoomdistance(newzoom) \
		--- "...by default, camera modules will respect LockFirstPerson and override the CurrentZoomDistance with 0 \
		--- regardless of what Player.CameraMinZoomDistance is set to, so that first person can be made \
		--- available by the developer without needing to allow players to mousewheel dolly into first person. \
		--- Some modules will override this function to remove or change first-person capability."
		if CameraController.CameraMode == Enum.CameraMode.LockFirstPerson then
			CameraController.CurrentZoomDistance = CameraController.FirstPersonDistanceMinZoom
			if not CameraController.InFirstPerson then
				CameraController.InFirstPerson = true
			end
		else
			local clampedsubjectdistance = math.clamp(newzoom, CameraController.CameraMinZoomDistance, CameraController.CameraMaxZoomDistance)
			if clampedsubjectdistance < CameraController.FirstPersonDistanceSnap then
				CameraController.CurrentZoomDistance = CameraController.FirstPersonDistanceMinZoom
				if not CameraController.InFirstPerson then
					CameraController.InFirstPerson = true
				end
			else
				CameraController.CurrentZoomDistance = clampedsubjectdistance
				if CameraController.InFirstPerson then
					CameraController.InFirstPerson = false
				end
			end
		end
	end

	return CameraController.CurrentZoomDistance
end

--- returns lookvector rotated by input rotation
function CameraController.rotatelookvector(lookvector: Vector3, rotation: Vector2)
	local pitchangle = math.asin(lookvector.Y)
	local ry = math.clamp(rotation.Y, -CameraController.CameraMaxPitch + pitchangle, -CameraController.CameraMinPitch + pitchangle)
	local constrainedrotateinput = Vector2.new(rotation.X, ry)
	local cframe = CFrame.Angles(0, -constrainedrotateinput.X, 0) * CFrame.lookAlong(Vector3.zero, lookvector) * CFrame.Angles(-constrainedrotateinput.Y, 0, 0)

	return cframe.LookVector
end

--- resets all camera inputs
function CameraController.reset()
	table.move(table.create(#CameraController.PanInputs, 0), 1, #CameraController.PanInputs, 1, CameraController.PanInputs)
	table.move(table.create(#CameraController.ZoomInputs, 0), 1, #CameraController.ZoomInputs, 1, CameraController.ZoomInputs)
end

--- resets delta-based inputs \
--- interally-called at the end of cameracontroller step
function CameraController.resetinputs()
	--- preserve non-delta inputs, stored in first 4 (gamepad pan, keyboard pan)
	local len = #CameraController.PanInputs - 4
	table.move(table.create(len, 0), 1, len, 5, CameraController.PanInputs)
	table.move(table.create(#CameraController.ZoomInputs, 0), 1, #CameraController.ZoomInputs, 1, CameraController.ZoomInputs)
end

--- "...adjusts the touch sensitivity delta so that sensitivity is reduced when swiping up \
--- or down, but stays the same when swiping towards the middle of the screen"
function CameraController.resolvetouchpitchsensitivity(delta: Vector2): Vector2
	local camera = CameraController.Camera

	if not camera then
		return delta
	end
	
	--- get the camera pitch in world space
	local pitch = camera.CFrame:ToEulerAnglesYXZ()
	
	if delta.Y*pitch >= 0 then
		--- do not reduce sensitivity when pitching towards the horizon
		return delta
	end
	
	--- set up a line to fit: \
	--- 1 = f(0) \
	--- 0 = f(±pi/2)
	local curveY = 1 - (2*math.abs(pitch)/math.pi)^0.75

	--- remap curveY from [0, 1] -> [MIN_TOUCH_SENSITIVITY_FRACTION, 1]
	local sensitivity = math.map(curveY, 0, 1, CameraController.TouchSensitivityFraction, 1)

	return Vector2.new(1, sensitivity)*delta
end

function CameraController.mapsignedvaluetodeadzone(value: number, deadzone: number)
	local abs = math.abs(value)
	if abs > deadzone then
		return math.map(abs, deadzone, 1, 0, 1) * math.sign(value)
	else
		return 0
	end
end

--- returns rotation input as a sum of all device inputs
function CameraController.getrotationinput(dt: number, disablekeyboardrotation: boolean?)
	--- `[1,  2]` gamepad x, y \
	--- `[3,  4]` keyboard arrow l, r \
	--- `[5,  6]` mouse delta x, y \
	--- `[7,  8]` pointer pan delta x, y \
	--- `[9, 10]` touch pan delta x, y
	local paninputs = CameraController.PanInputs

	local gamepaddeadzone = CameraController.GamepadDeadzone
	local gamepadx = CameraController.mapsignedvaluetodeadzone(paninputs[1], gamepaddeadzone)
	local gamepady = CameraController.mapsignedvaluetodeadzone(paninputs[2], gamepaddeadzone)

	local gamepadrotationvector = CameraController.GamepadSpeed * Vector2.new(gamepadx, gamepady) * UserGameSettings.GamepadCameraSensitivity
	local keyboardrotationvector = CameraController.ArrowKeySpeed * Vector2.new(paninputs[3] + paninputs[4], 0) * dt
	local mousemovevector = CameraController.MouseSpeed * Vector2.new(paninputs[5], paninputs[6])
	local pointerpanvector = CameraController.PointerSpeed * Vector2.new(paninputs[7], paninputs[8])
	local touchpanvector = CameraController.TouchSpeed * Vector2.new(paninputs[9], paninputs[10]) --- CameraController.resolvetouchpitchsensitivity(Vector2.new(paninputs[9], paninputs[10]))

	local camerayinvertvector = Vector2.new(1, UserGameSettings:GetCameraYInvertValue())

	if disablekeyboardrotation then
		keyboardrotationvector *= Vector2.zero
	end

	return (
		keyboardrotationvector
		+ gamepadrotationvector
		+ mousemovevector
		+ pointerpanvector
		+ touchpanvector
	) * camerayinvertvector
end

--- returns zoom input as a sum of all device inputs
function CameraController.getzoominput()
	local zoom = CameraController.ZoomInputs
	local keyboardzoom = CameraController.KeyZoomSpeed * (zoom[1] + zoom[2])
	local mousezoom = CameraController.MouseZoomSpeed * (-zoom[3] + zoom[4])
	local touchzoom = CameraController.TouchZoomSpeed * (-zoom[5])

	return keyboardzoom + mousezoom + touchzoom
end

function CameraController.touchguithumbstickframe(): Frame?
	local playergui = LocalPlayer:FindFirstChildOfClass("PlayerGui")::PlayerGui?
	local touchgui = playergui and playergui:FindFirstChild("r0TouchGui")::ScreenGui?
	local thumbstickframe = touchgui and touchgui:FindFirstChild("ThumbstickFrame")::Frame?

	return thumbstickframe
end

function CameraController.ispointinbounds(point: Vector2, topleft: Vector2, bottomright: Vector2)
	local cx, cy = point.X, point.Y

	return 
		cx >= topleft.X and
		cy >= topleft.Y and
		cx <= bottomright.X and
		cy <= bottomright.Y
end

function CameraController.filterpoints(array: {Vector2}, topleft, bottomright)
	for i = #array, 1, -1 do
		local vec = array[i]
		if CameraController.ispointinbounds(vec, topleft, bottomright) then
			table.remove(array, i)
		end
	end
end

if RunService:IsClient() then
	--- internal functions

	--- `[1,  2]` gamepad x, y \
	--- `[3,  4]` keyboard arrow l, r \
	--- `[5,  6]` mouse delta x, y \
	--- `[7,  8]` pointer pan delta x, y \
	--- `[9, 10]` touch pan delta x, y
	local paninputs = CameraController.PanInputs

	--- interally-called by contextaction "r0CameraThumbstick"
	local function thumbstick(action: string, state: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
		if inputobject.KeyCode == Enum.KeyCode.Thumbstick2 then
			local position = inputobject.Position
			
			paninputs[1] = position.X
			paninputs[2] = -position.Y
		end

		return Enum.ContextActionResult.Pass
	end

	--- interally-called by userinputservice.inputbegan
	local function mousemovement(inputobject: InputObject)
		local delta = inputobject.Delta
		paninputs[5] = delta.X
		paninputs[6] = delta.Y
	end

	--- interally-called by contextaction "r0CameraKeypress"
	local function keypress(action: string, state: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
		local keycode = inputobject.KeyCode
		local value = state == Enum.UserInputState.Begin and 1 or 0
		if keycode == Enum.KeyCode.I then
			CameraController.ZoomInputs[1] = value
		elseif keycode == Enum.KeyCode.O then
			CameraController.ZoomInputs[2] = value
		elseif keycode == Enum.KeyCode.Left then
			paninputs[3] = value
		elseif keycode == Enum.KeyCode.Right then
			paninputs[4] = -value
		end

		return
	end

	--- interally-called by userinputservice.pointeraction
	local function pointeraction(wheel: number, pan: Vector2, pinch: number, sunkinput: boolean)
		if sunkinput then return end

		CameraController.ZoomInputs[3] = wheel
		CameraController.ZoomInputs[4] = -pinch
		paninputs[7] = pan.X
		paninputs[8] = pan.Y
	end

	local lasttranslation = Vector2.zero

	local function resettouchpan()
		lasttranslation = Vector2.zero
		CameraController.PanInputs[9] = 0
		CameraController.PanInputs[10] = 0
	end

	--- interally-called by userinputservice.touchpan
	local ispanvalid = false
	local function touchpan(touchpositions: {Vector2}, totaltranslation: Vector2, velocity: Vector2, state: Enum.UserInputState, sunkinput: boolean)
		if state ~= Enum.UserInputState.Change then
			if state == Enum.UserInputState.Begin then
				--- pan is only valid if initial touch was not within bounds of the touchgui thumbstick
				local thumbstickframe = CameraController.touchguithumbstickframe()
				if thumbstickframe then
					local apos, asize = thumbstickframe.AbsolutePosition, thumbstickframe.AbsoluteSize
					CameraController.filterpoints(touchpositions, apos, apos + asize)
				end

				ispanvalid = #touchpositions > 0
			else
				ispanvalid = false
			end

			resettouchpan()

			return
		end

		if #touchpositions == 1 and ispanvalid then
			local delta = totaltranslation - lasttranslation
			lasttranslation = totaltranslation
			paninputs[9] += delta.X
			paninputs[10] += delta.Y

			CameraController.PanInputMap[Enum.UserInputType.Touch] = true
		else
			resettouchpan()
			CameraController.PanInputMap[Enum.UserInputType.Touch] = false
		end
	end

	--- interally-called by userinputservice.touchpinch
	local function touchpinch(touchpositions: {Vector2}, scale: number, velocity: number, state: Enum.UserInputState, sunkinput: boolean)
		if state ~= Enum.UserInputState.Change then return end

		local thumbstickframe = CameraController.touchguithumbstickframe()
		if thumbstickframe then
			local apos, asize = thumbstickframe.AbsolutePosition, thumbstickframe.AbsoluteSize
			CameraController.filterpoints(touchpositions, apos, apos + asize)
		end

		if #touchpositions == 2 then
			CameraController.ZoomInputs[5] = scale
		end
	end

	--- interally-called by userinputservice.inputbegan
	local function inputbegan(inputobject: InputObject, sunkinput: boolean)
		if inputobject.UserInputType == Enum.UserInputType.MouseButton2 and not sunkinput then
			CameraController.PanInputMap[Enum.UserInputType.MouseButton2] = true
			CameraController.HoldPan = true
		end
		if inputobject.KeyCode == CameraController.GamepadZoomKeyCode and not sunkinput then
			CameraController.gamepadzoomstep(1)
		end
	end

	--- interally-called by userinputservice.inputchanged
	local function inputchanged(inputobject: InputObject, sunkinput: boolean)
		if inputobject.UserInputType == Enum.UserInputType.MouseMovement then
			mousemovement(inputobject)
		end
	end

	--- interally-called by userinputservice.inputended
	local function inputended(inputobject: InputObject, sunkinput: boolean)
		if inputobject.UserInputType == Enum.UserInputType.MouseButton2 then
			CameraController.PanInputMap[Enum.UserInputType.MouseButton2] = false
			CameraController.HoldPan = false
		elseif inputobject.UserInputType == Enum.UserInputType.Touch then
			resettouchpan()
		end
	end

	do
		--- write player zoom to camera zoom
		CameraController.CameraMinZoomDistance = LocalPlayer.CameraMinZoomDistance
		CameraController.CameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance

		--- write defaults to distance
		local mindistance = CameraController.CameraMinZoomDistance
		local maxdistance = CameraController.CameraMaxZoomDistance
		local defaultzoomdistance = math.clamp(CameraController.DefaultZoomDistance, mindistance, maxdistance)
		CameraController.CurrentZoomDistance = defaultzoomdistance

		--- write defaults to spring
		local s = CameraController.ZoomSpring
		s.distance = defaultzoomdistance
		s.frequency = CameraController.ZoomSpringFrequency
		s.goal = defaultzoomdistance
		s.mindistance = mindistance
		s.maxdistance = maxdistance
	end

	--- thumbstick
	ContextActionService:BindActionAtPriority(
		"r0CameraThumbstick",
		thumbstick,
		false,
		CameraController.InputPriority,
		Enum.KeyCode.Thumbstick2
	)
	--- keyboard
	ContextActionService:BindActionAtPriority(
		"r0CameraKeypress",
		keypress,
		false,
		CameraController.InputPriority,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.I,
		Enum.KeyCode.O
	)
	--- pointer
	UserInputService.PointerAction:Connect(pointeraction)
	--- touch pan, pinch
	UserInputService.TouchPan:Connect(touchpan)
	UserInputService.TouchPinch:Connect(touchpinch)
	--- mouse/inputbeganchangedended
	UserInputService.InputBegan:Connect(inputbegan)
	UserInputService.InputChanged:Connect(inputchanged)
	UserInputService.InputEnded:Connect(inputended)

	--- camera step
	RunService:BindToRenderStep("r0Camera", CameraController.RenderPriority, CameraController.step)

	--- updates zoom distance and spring wrt min/maxzoomdistance
	local function zoomdistancemodified()
		local mindistance = CameraController.CameraMinZoomDistance
		local maxdistance = CameraController.CameraMaxZoomDistance
		local currentzoomdistance = math.clamp(CameraController.CurrentZoomDistance, mindistance, maxdistance)
		
		CameraController.CurrentZoomDistance = currentzoomdistance

		local s = CameraController.ZoomSpring
		s.distance = currentzoomdistance
		s.mindistance = mindistance
		s.maxdistance = maxdistance

		Spring.step(s, 1/60)
	end

	--- min/max zoom distance change
	LocalPlayer:GetPropertyChangedSignal("CameraMinZoomDistance"):Connect(function()
		CameraController.CameraMinZoomDistance = LocalPlayer.CameraMinZoomDistance
		zoomdistancemodified()
	end)
	LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(function()
		CameraController.CameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance
		zoomdistancemodified()
	end)
end

return CameraController