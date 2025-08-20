--!strict

local RunService = game:GetService("RunService")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local UserInputService = game:GetService("UserInputService")

local ZoomController = require(script.Parent:WaitForChild("ZoomController"))

-- Note: DotProduct check in CoordinateFrame::lookAt() prevents using values within about
-- 8.11 degrees of the +/- Y axis, that's why these limits are currently 80 degrees
local MIN_Y = math.rad(-80)
local MAX_Y = math.rad(80)

local LastStep = 0

--- ### CameraController.luau
---
--- camera controller
local CameraController = {
	--- camera
	Camera = workspace.CurrentCamera;
	--- initial camera angle
	InitialCameraAngle = CFrame.fromOrientation(math.rad(-15), 0, 0);
	ResetCameraAngle = true;

	--- input priority
	InputPriority = Enum.ContextActionPriority.Medium.Value;
	--- render priority
	RenderPriority = Enum.RenderPriority.Camera.Value;

	--- length of time for a short mouse button tap to be registered \
	--- MB_TAP_LENGTH
	PanMouseMinTime = 0.3;
	--- arrow key camera pan speed \
	--- ROTATION_SPEED_KEYS
	ArrowKeyRadSec = math.rad(120);
	--- gamepad pan speed \
	--- ROTATION_SPEED_GAMEPAD
	GamepadRadSec = Vector2.new(1, 0.77) * math.rad(7);

	--- ROTATION_SPEED_MOUSE
	MouseRadSec = Vector2.new(1, 0.77)*math.rad(0.5);
	--- ROTATION_SPEED_POINTERACTION
	PointerRadSec = Vector2.new(1, 0.77)*math.rad(7);
	--- ROTATION_SPEED_TOUCH
	TouchRadSec = Vector2.new(1, 0.66)*math.rad(1);

	--- (scaled studs/wheel click)
	--- ZOOM_SPEED_MOUSE
	MouseZoomSpeed = 1;
	--- (studs/s)
	--- ZOOM_SPEED_KEYS
	KeyZoomSpeed = 0.1;
	--- (scaled studs/DIP %)
	--- ZOOM_SPEED_TOUCH
	TouchZoomSpeed = 0.04;

	--- "...Adjust the touch sensitivity so that sensitivity is reduced when swiping up" \
	--- 25% sensitivity at 90° \
	--- MIN_TOUCH_SENSITIVITY_FRACTION
	TouchSensitivityFraction = 0.25;

	--- gamepad pan deadzone
	GamepadDeadzone = 0.1;

	--- gamepad vector
	GamepadVector = table.create(2, 0);
	--- keyboard pan left/right
	KeyboardPan = table.create(2, 0);
	--- mouse delta
	MouseMove = table.create(2, 0);
	--- pointer pan
	PointerPan = table.create(2, 0);
	--- touch move
	TouchPan = table.create(2, 0);
	--- touch pinch

	--[[{
		[1] keyboard i
		[2] keyboard o
		[3] mouse wheel (pointeraction)
		[4] mouse pinch (pointeraction)
		[5] touch pinch
	}]]
	ZoomInputs = table.create(5, 0);

	--- `Enum.UserInputType -> is pan-held` readwrite table
	PanInputMap = {
		[Enum.UserInputType.MouseButton2] = false;
		[Enum.UserInputType.Touch] = false;
	};

	HoldPan = false;

	--- default distance away from subject
	DefaultZoomDistance = 12.5;
	--- current zoom distance from subject
	CurrentZoomDistance = math.clamp(12.5, LocalPlayer.CameraMinZoomDistance, LocalPlayer.CameraMaxZoomDistance);

	ZoomSensitivityCurve = 0.5;
	--- min zoom when in first person
	FirstPersonDistanceMinZoom = 0.5;
	--- if zoom < this value, snaps to first-person
	FirstPersonDistanceSnap = 1;
	--- internally-set boolean describing whether camera is in first person
	InFirstPerson = false;

	CameraMinZoomDistance = LocalPlayer.CameraMinZoomDistance;
	CameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance;
}

function CameraController.step(dt: number)
	local now = os.clock()
	local realtime = now - LastStep

	local camera = CameraController.Camera
	local cameracframe = camera.CFrame
	local camerasubject = camera.CameraSubject

	local camerasubjectcframe = CFrame.identity
	
	if camerasubject and camerasubject:IsA("BasePart") then
		camerasubjectcframe = camerasubject:GetPivot()
	end

	local cameralookvector = cameracframe.LookVector
	if CameraController.ResetCameraAngle then
		if camerasubject and camerasubject:IsA("BasePart") then
			cameralookvector = (camerasubject:GetPivot() * CameraController.InitialCameraAngle).LookVector
		else
			cameralookvector = CameraController.InitialCameraAngle.LookVector
		end

		CameraController.ResetCameraAngle = false
	end

	local rotateinput = CameraController.getrotationinput(realtime)

	CameraController.stepzoom()

	local camerafocusposition = camerasubjectcframe.Position
	local newlookvector = CameraController.calculatenewlookvectorfromarg(cameralookvector, rotateinput)

	camera.CFrame = CFrame.lookAlong(camerafocusposition - (CameraController.CurrentZoomDistance * newlookvector), newlookvector)
	camera.Focus = CFrame.new(camerasubjectcframe.Position)

	CameraController.resetinputs()

	LastStep = now
end

function CameraController.stepzoom()
	local zoom = CameraController.CurrentZoomDistance
	local zoomdelta = CameraController.getzoomdelta()

	if math.abs(zoomdelta) > 0 then
		local newzoom

		if zoomdelta > 0 then
			newzoom = zoom + zoomdelta*(1 + zoom*CameraController.ZoomSensitivityCurve)
			newzoom = math.max(newzoom, CameraController.FirstPersonDistanceSnap)
		else
			newzoom = (zoom + zoomdelta)/(1 - zoomdelta*CameraController.ZoomSensitivityCurve)
			newzoom = math.max(newzoom, CameraController.FirstPersonDistanceMinZoom)
		end

		if newzoom < CameraController.FirstPersonDistanceSnap then
			newzoom = CameraController.FirstPersonDistanceMinZoom
		end

		CameraController.setcameratosubjectdistance(newzoom)
	end

	return ZoomController.GetZoomRadius()
end

function CameraController.calculatenewlookvectorfromarg(lookvector: Vector3, rotateinput: Vector2)
	local pitchangle = math.asin(lookvector.Y)
	local ry = math.clamp(rotateinput.Y, -MAX_Y + pitchangle, -MIN_Y + pitchangle)
	local constrainedrotateinput = Vector2.new(rotateinput.X, ry)
	local cframe = CFrame.Angles(0, -constrainedrotateinput.X, 0) * CFrame.lookAlong(Vector3.zero, lookvector) * CFrame.Angles(-constrainedrotateinput.Y, 0, 0)

	return cframe.LookVector
end

function CameraController.setcameratosubjectdistance(desiredsubjectdistance: number)
	local lastsubjectdistance = CameraController.CurrentZoomDistance

	-- By default, camera modules will respect LockFirstPerson and override the CurrentZoomDistance with 0
	-- regardless of what Player.CameraMinZoomDistance is set to, so that first person can be made
	-- available by the developer without needing to allow players to mousewheel dolly into first person.
	-- Some modules will override this function to remove or change first-person capability.
	if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
		CameraController.CurrentZoomDistance = CameraController.FirstPersonDistanceMinZoom
		if not CameraController.InFirstPerson then
			CameraController.InFirstPerson = true
		end
	else
		local newSubjectDistance = math.clamp(desiredsubjectdistance, LocalPlayer.CameraMinZoomDistance, LocalPlayer.CameraMaxZoomDistance)
		if newSubjectDistance < CameraController.FirstPersonDistanceSnap then
			CameraController.CurrentZoomDistance = CameraController.FirstPersonDistanceMinZoom
			if not CameraController.InFirstPerson then
				CameraController.InFirstPerson = true
			end
		else
			CameraController.CurrentZoomDistance = newSubjectDistance
			if CameraController.InFirstPerson then
				CameraController.InFirstPerson = false
			end
		end
	end

	-- Pass target distance and zoom direction to the zoom controller
	ZoomController.SetZoomParameters(CameraController.CurrentZoomDistance, math.sign(desiredsubjectdistance - lastsubjectdistance))

	-- Returned only for convenience to the caller to know the outcome
	return CameraController.CurrentZoomDistance
end

function CameraController.refreshzoomdistance(value: number?)
	CameraController.CurrentZoomDistance = math.clamp(value or CameraController.CurrentZoomDistance, LocalPlayer.CameraMinZoomDistance, LocalPlayer.CameraMaxZoomDistance);
end

function CameraController.reset()
	table.move(table.create(#CameraController.GamepadVector, 0), 1, #CameraController.GamepadVector, 1, CameraController.GamepadVector)
	table.move(table.create(#CameraController.KeyboardPan, 0), 1, #CameraController.KeyboardPan, 1, CameraController.KeyboardPan)
	table.move(table.create(#CameraController.MouseMove, 0), 1, #CameraController.MouseMove, 1, CameraController.MouseMove)
	table.move(table.create(#CameraController.PointerPan, 0), 1, #CameraController.PointerPan, 1, CameraController.PointerPan)
	table.move(table.create(#CameraController.TouchPan, 0), 1, #CameraController.TouchPan, 1, CameraController.TouchPan)

	table.move(table.create(#CameraController.ZoomInputs, 0), 1, #CameraController.ZoomInputs, 1, CameraController.ZoomInputs)
end

function CameraController.resetinputs()
	table.move(table.create(#CameraController.MouseMove, 0), 1, #CameraController.MouseMove, 1, CameraController.MouseMove)
	table.move(table.create(#CameraController.PointerPan, 0), 1, #CameraController.PointerPan, 1, CameraController.PointerPan)
	table.move(table.create(#CameraController.TouchPan, 0), 1, #CameraController.TouchPan, 1, CameraController.TouchPan)
	
	table.move(table.create(#CameraController.ZoomInputs, 0), 1, #CameraController.ZoomInputs, 1, CameraController.ZoomInputs)
end

-- Adjust the touch sensitivity so that sensitivity is reduced when swiping up
-- or down, but stays the same when swiping towards the middle of the screen
function CameraController.adjusttouchpitchsensitivity(delta: Vector2): Vector2
	local camera = workspace.CurrentCamera

	if not camera then
		return delta
	end
	
	-- get the camera pitch in world space
	local pitch = camera.CFrame:ToEulerAnglesYXZ()
	
	if delta.Y*pitch >= 0 then
		-- do not reduce sensitivity when pitching towards the horizon
		return delta
	end
	
	-- set up a line to fit:
	-- 1 = f(0)
	-- 0 = f(±pi/2)
	local curveY = 1 - (2*math.abs(pitch)/math.pi)^0.75

	-- remap curveY from [0, 1] -> [MIN_TOUCH_SENSITIVITY_FRACTION, 1]
	-- local sensitivity = curveY*(1 - CameraController.TouchSensitivityFraction) + CameraController.TouchSensitivityFraction
	local sensitivity = math.map(curveY, 0, 1, CameraController.TouchSensitivityFraction, 1)

	return Vector2.new(1, sensitivity)*delta
end

function CameraController.getrotationinput(dt: number, disablekeyboardrotation: boolean?)
	local keyboardrotationvector = CameraController.ArrowKeyRadSec * dt * Vector2.new(CameraController.KeyboardPan[1], CameraController.KeyboardPan[2])
	local gamepadrotationvector = CameraController.GamepadRadSec * Vector2.new(CameraController.GamepadVector[1], CameraController.GamepadVector[2]) * UserGameSettings.GamepadCameraSensitivity
	local mousemovevector = CameraController.MouseRadSec * Vector2.new(CameraController.MouseMove[1], CameraController.MouseMove[2])
	local pointerpanvector = CameraController.PointerRadSec * Vector2.new(CameraController.PointerPan[1], CameraController.PointerPan[2])
	local touchpanvector = CameraController.TouchRadSec * CameraController.adjusttouchpitchsensitivity(Vector2.new(CameraController.TouchPan[1], CameraController.TouchPan[2]))

	if disablekeyboardrotation then
		keyboardrotationvector *= Vector2.zero
	end

	return Vector2.new(1, UserGameSettings:GetCameraYInvertValue())
		* (
			keyboardrotationvector
			+ gamepadrotationvector
			+ mousemovevector
			+ pointerpanvector
			+ touchpanvector
		)
end

function CameraController.getzoomdelta()
	local zoom = CameraController.ZoomInputs
	local keyboardzoom = CameraController.KeyZoomSpeed * (zoom[1] + zoom[2])
	local mousezoom = CameraController.MouseZoomSpeed * (-zoom[3] + zoom[4])
	local touchzoom = CameraController.TouchZoomSpeed * (-zoom[5])

	return keyboardzoom + mousezoom + touchzoom
end

function CameraController.thumbstick(action: string, state: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
	if inputobject.KeyCode == Enum.KeyCode.Thumbstick2 then
		local position = inputobject.Position
		local gamepadvector = CameraController.GamepadVector
		gamepadvector[1] = position.X
		gamepadvector[2] = -position.Y
	end

	return Enum.ContextActionResult.Pass
end

function CameraController.mousemovement(inputobject: InputObject)
	local delta = inputobject.Delta
	CameraController.MouseMove[1] = delta.X
	CameraController.MouseMove[2] = delta.Y
end

function CameraController.keypress(action: string, state: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
	local keycode = inputobject.KeyCode
	local value = state == Enum.UserInputState.Begin and 1 or 0
	if keycode == Enum.KeyCode.I then
		CameraController.ZoomInputs[1] = value
	elseif keycode == Enum.KeyCode.O then
		CameraController.ZoomInputs[2] = value
	elseif keycode == Enum.KeyCode.Left then
		CameraController.KeyboardPan[1] = value
	elseif keycode == Enum.KeyCode.Right then
		CameraController.KeyboardPan[2] = value
	end

	return
end

function CameraController.pointeraction(wheel: number, pan: Vector2, pinch: number, sunkinput: boolean)
	if sunkinput then return end

	CameraController.ZoomInputs[3] = wheel
	CameraController.ZoomInputs[4] = -pinch
	CameraController.TouchPan[1] = pan.X
	CameraController.TouchPan[2] = pan.Y
end

function CameraController.touchpan(touchpositions: {Vector2}, totaltranslation: Vector2, velocity: Vector2, state: Enum.UserInputState, sunkinput: boolean)
	if #touchpositions == 1 then
		CameraController.TouchPan[1] += velocity.X
		CameraController.TouchPan[2] += velocity.Y

		CameraController.PanInputMap[Enum.UserInputType.Touch] = true
	else
		CameraController.PanInputMap[Enum.UserInputType.Touch] = false
	end
end

function CameraController.touchpinch(touchpositions: {Vector2}, scale: number, velocity: number, state: Enum.UserInputState, sunkinput: boolean)
	if #touchpositions == 2 then
		CameraController.ZoomInputs[5] = scale
	end
end

function CameraController.inputbegan(inputobject: InputObject, sunkinput: boolean)
	if inputobject.UserInputType == Enum.UserInputType.MouseButton2 and not sunkinput then
		CameraController.PanInputMap[Enum.UserInputType.MouseButton2] = true
		CameraController.HoldPan = true
	end
end

function CameraController.inputchanged(inputobject: InputObject, sunkinput: boolean)
	if inputobject.UserInputType == Enum.UserInputType.MouseMovement then
		CameraController.mousemovement(inputobject)
	end
end

function CameraController.inputended(inputobject: InputObject, sunkinput: boolean)
	if inputobject.UserInputType == Enum.UserInputType.MouseButton2 then
		CameraController.PanInputMap[Enum.UserInputType.MouseButton2] = false
		CameraController.HoldPan = false
	end
end

if RunService:IsClient() then
	--- thumbstick
	ContextActionService:BindActionAtPriority(
		"r0CameraThumbstick",
		CameraController.thumbstick,
		false,
		CameraController.InputPriority,
		Enum.KeyCode.Thumbstick2
	)
	--- keyboard
	ContextActionService:BindActionAtPriority(
		"r0CameraKeypress",
		CameraController.keypress,
		false,
		CameraController.InputPriority,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.I,
		Enum.KeyCode.O
	)
	--- pointer
	UserInputService.PointerAction:Connect(CameraController.pointeraction)
	--- touch pan, pinch
	UserInputService.TouchPan:Connect(CameraController.touchpan)
	UserInputService.TouchPinch:Connect(CameraController.touchpinch)
	--- mouse/inputbeganchangedended
	UserInputService.InputBegan:Connect(CameraController.inputbegan)
	UserInputService.InputChanged:Connect(CameraController.inputchanged)
	UserInputService.InputEnded:Connect(CameraController.inputended)

	--- update
	RunService:BindToRenderStep("r0Camera", CameraController.RenderPriority, CameraController.step)

	LocalPlayer:GetPropertyChangedSignal("CameraMinZoomDistance"):Connect(function()
		CameraController.CameraMinZoomDistance = LocalPlayer.CameraMinZoomDistance
		CameraController.refreshzoomdistance()
	end)
	LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(function()
		CameraController.CameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance
		CameraController.refreshzoomdistance()
	end)
end

return CameraController