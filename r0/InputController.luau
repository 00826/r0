--!strict

local RunService = game:GetService("RunService")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

--- converts vector3 to udim2
@native
local function touchvectortoudim2(vec: Vector3)
	return UDim2.fromOffset(vec.X, vec.Y)
end

--- converts vector2 to vector3
@native
local function vector2tovector3(vec: Vector2)
	return Vector3.new(vec.X, vec.Y, 0)
end

--- returns whether `inputobject.position` is within bounds of box defined by `absoluteposition` and `absolutesize`
@native
local function isinputinbounds(absoluteposition: Vector2, absolutesize: Vector2, inputobject: InputObject)
	local bottomright = absoluteposition + absolutesize
	local inputposition = inputobject.Position
	local px, py = inputposition.X, inputposition.Y

	return px >= absoluteposition.X
		and py >= absoluteposition.Y
		and px <= bottomright.X
		and py <= bottomright.Y
end

--- ### InputController.luau
---
--- input controller
local InputController = {
	--- input vector
	Vector = Vector3.zero;

	--- interally-resolved preferred input based on recency
	PreferredInput = Enum.PreferredInput.KeyboardAndMouse;

	--- `Enum.UserInputType -> Enum.PreferredInput` conversion table \
	--- `Enum.UserInputType.TextInput` is omitted and should be accounted for externally
	InputTypesToPreferredInputs = {
		[Enum.UserInputType.None] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.Focus] = Enum.PreferredInput.KeyboardAndMouse;

		[Enum.UserInputType.MouseButton1] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.MouseButton2] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.MouseButton3] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.MouseWheel] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.MouseMovement] = Enum.PreferredInput.KeyboardAndMouse;
		[Enum.UserInputType.Keyboard] = Enum.PreferredInput.KeyboardAndMouse;
		
		[Enum.UserInputType.Touch] = Enum.PreferredInput.Touch;
		[Enum.UserInputType.Accelerometer] = Enum.PreferredInput.Touch;
		[Enum.UserInputType.Gyro] = Enum.PreferredInput.Touch;

		[Enum.UserInputType.Gamepad1] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad2] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad3] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad4] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad5] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad6] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad7] = Enum.PreferredInput.Gamepad;
		[Enum.UserInputType.Gamepad8] = Enum.PreferredInput.Gamepad;
	};

	--- `Enum.PreferredInput -> Enum.ContextActionPriority.___.Value` conversion table
	ActionPriorities = {
		[Enum.PreferredInput.Gamepad] = Enum.ContextActionPriority.Medium.Value;
		[Enum.PreferredInput.KeyboardAndMouse] = Enum.ContextActionPriority.Medium.Value;
		[Enum.PreferredInput.Touch] = Enum.ContextActionPriority.High.Value;
	};

	--- `inputvector = Vector3.new(t[1] + t[2], 0, t[3] + t[4])`
	KeyboardSigns = table.create(4, 0);
	--- `Enum.KeyCode -> { Offset: number; Sign: number; }` conversion table
	KeyboardMap = {
		[Enum.KeyCode.W] = { Offset = 1; Sign = -1; };
		[Enum.KeyCode.S] = { Offset = 2; Sign = 1; };
		[Enum.KeyCode.A] = { Offset = 3; Sign = -1; };
		[Enum.KeyCode.D] = { Offset = 4; Sign = 1; };

		[Enum.KeyCode.Up] = { Offset = 1; Sign = -1; };
		[Enum.KeyCode.Down] = { Offset = 2; Sign = 1; };
	};

	--- gamepad L3 deadzone
	GamepadDeadzone = 0.1;

	--- current touch inputobject
	TouchObject = nil :: InputObject?;
	--- touch thumbstick start position
	TouchStartPosition = Vector3.zero;
	--- touch thumbstick current position
	TouchCurrentPosition = Vector3.zero;
	--- touch thumbstick (L3) deadzone
	TouchDeadzone = 0.1;

	--- current touch gui \
	--- touchgui is always instantiated
	--- regardless of current input \
	--- for consistency
	TouchGui = nil :: ScreenGui?;

	--- `Enum.DisplaySize -> touch thumbstick ring size` conversion table
	ThumbstickRingMap = {
		[Enum.DisplaySize.Small] = UDim2.fromOffset(72, 72);
		[Enum.DisplaySize.Medium] = UDim2.fromOffset(96, 96);
		[Enum.DisplaySize.Large] = UDim2.fromOffset(128, 128);
	};
	--- `Enum.DisplaySize -> touch thumbstick circle size` conversion table
	ThumbstickCircleMap = {
		[Enum.DisplaySize.Small] = UDim2.fromOffset(36, 36);
		[Enum.DisplaySize.Medium] = UDim2.fromOffset(48, 48);
		[Enum.DisplaySize.Large] = UDim2.fromOffset(64, 64);
	};
	--- `Enum.DisplaySize -> touch thumbstickframe size` conversion table
	ThumbstickSizeMap = {
		[Enum.DisplaySize.Small] = UDim2.new(0.4, 0, 0.667, 0);
		[Enum.DisplaySize.Medium] = UDim2.new(0.4, 0, 0.667, 0);
		[Enum.DisplaySize.Large] = UDim2.new(0.4, 0, 0.667, 0);
	};
	--- `Enum.DisplaySize -> touch thumbstickframe position` conversion table
	ThumbstickPositionMap = {
		[Enum.DisplaySize.Small] = UDim2.new(0, 0, 0.333, 0);
		[Enum.DisplaySize.Medium] = UDim2.new(0, 0, 0.333, 0);
		[Enum.DisplaySize.Large] = UDim2.new(0, 0, 0.333, 0);
	};
	--- `Enum.PreferredInput -> touchgui visibility` conversion table
	TouchGuiVisibility = {
		[Enum.PreferredInput.Gamepad] = false;
		[Enum.PreferredInput.KeyboardAndMouse] = false;
		[Enum.PreferredInput.Touch] = true;
	};
}

function InputController.rebind(preferredinput: Enum.PreferredInput)
	ContextActionService:UnbindAction("r0Input")

	if preferredinput == Enum.PreferredInput.KeyboardAndMouse then
		local list = table.create(8)
		for k in InputController.KeyboardMap do
			table.insert(list, k)
		end

		ContextActionService:BindActionAtPriority("r0Input", InputController.keyboard, false, InputController.ActionPriorities[preferredinput], unpack(list))
	elseif preferredinput == Enum.PreferredInput.Gamepad then
		ContextActionService:BindActionAtPriority("r0Input", InputController.gamepad, false, InputController.ActionPriorities[preferredinput], Enum.KeyCode.Thumbstick1)
	elseif preferredinput == Enum.PreferredInput.Touch then
		ContextActionService:BindActionAtPriority("r0Input", InputController.touch, false, InputController.ActionPriorities[preferredinput], Enum.UserInputType.Touch)
	else
		warn("unaccounted preferredinput:", preferredinput.Name)
	end
end

--- internally-bound by `InputController.rebind(Enum.PreferredInput.KeyboardAndMouse)`
function InputController.keyboard(action: string, inputstate: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
	local entry = InputController.KeyboardMap[inputobject.KeyCode]
	if not entry then return end

	--[[{
		[1] = forward
		[2] = backward
		[3] = left
		[4] = right
	}]]
	local keysigns = InputController.KeyboardSigns
	keysigns[entry.Offset] = (inputstate == Enum.UserInputState.Begin) and entry.Sign or 0

	if inputstate == Enum.UserInputState.Cancel then
		InputController.Vector = Vector3.zero
	else
		InputController.Vector = Vector3.new(keysigns[3] + keysigns[4], 0, keysigns[1] + keysigns[2])
	end
	
	return Enum.ContextActionResult.Pass
end

--- internally-bound by `InputController.rebind(Enum.PreferredInput.Gamepad)`
function InputController.gamepad(action: string, inputstate: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
	if inputstate == Enum.UserInputState.Cancel then
		InputController.Vector = Vector3.zero
		return Enum.ContextActionResult.Sink
	end

	if inputobject.KeyCode ~= Enum.KeyCode.Thumbstick1 then return end

	local inputposition = inputobject.Position
	local distance = vector.magnitude(inputposition::any)
	if distance > InputController.GamepadDeadzone then
		local a = math.map(math.clamp(distance, 0, 1), InputController.GamepadDeadzone, 1, 0, 1)
		InputController.Vector = Vector3.new(inputposition.X * a, 0, -inputposition.Y * a)
	else
		InputController.Vector = Vector3.zero
	end

	return Enum.ContextActionResult.Sink
end

--- internally-bound by `InputController.rebind(Enum.PreferredInput.Touch)`
function InputController.touch(action: string, inputstate: Enum.UserInputState, inputobject: InputObject): Enum.ContextActionResult?
	local touchgui = InputController.TouchGui
	if not touchgui then return end

	local thumbstickframe = (touchgui::any).ThumbstickFrame::Frame
	local thumbstickframeapos = thumbstickframe.AbsolutePosition
	local thumbstickframeasize = thumbstickframe.AbsoluteSize

	local netinset = vector2tovector3(thumbstickframeapos - touchgui.AbsolutePosition)
	local inputposition = inputobject.Position - netinset

	local ring = (thumbstickframe::any).Ring::Frame
	local circle = (thumbstickframe::any).Circle::Frame

	if inputstate == Enum.UserInputState.Begin then
		if InputController.TouchObject then
			return Enum.ContextActionResult.Pass
		end

		if isinputinbounds(thumbstickframeapos, thumbstickframeasize, inputobject) then
			InputController.TouchObject = inputobject

			InputController.TouchCurrentPosition = inputposition
			InputController.TouchStartPosition = inputposition

			local inputudim2 = touchvectortoudim2(inputposition)
			ring.Position = inputudim2
			circle.Position = inputudim2
		else
			return Enum.ContextActionResult.Pass
		end
	elseif inputstate == Enum.UserInputState.Change then
		if InputController.TouchObject == inputobject then
			InputController.TouchCurrentPosition = inputposition

			local delta = InputController.TouchCurrentPosition - InputController.TouchStartPosition
			local direction = (vector.normalize(delta::any)::any)::Vector3
			local distance = vector.magnitude(delta::any)
			local radius = ring.AbsoluteSize.X * 0.5
			local innerradius = InputController.TouchDeadzone * radius
			if distance > radius then
				local dragpos = InputController.TouchStartPosition + (direction * (distance - radius))
				ring.Position = touchvectortoudim2(dragpos)
				InputController.TouchStartPosition = dragpos
			end

			if distance > innerradius then
				local a = math.map(math.clamp(distance, 0, radius), innerradius, radius, 0, 1)
				InputController.Vector = Vector3.new(direction.X * a, 0, direction.Y * a)
			else
				InputController.Vector = Vector3.zero
			end

			local inputudim2 = touchvectortoudim2(inputposition)
			circle.Position = inputudim2
			
			return Enum.ContextActionResult.Sink
		end

		return Enum.ContextActionResult.Pass
	elseif inputstate == Enum.UserInputState.End then
		if InputController.TouchObject == inputobject then
			InputController.TouchObject = nil
			InputController.Vector = Vector3.zero

			ring.Position = UDim2.fromScale(0.5, 0.5)
			circle.Position = UDim2.fromScale(0.5, 0.5)

			return Enum.ContextActionResult.Sink
		end

		return Enum.ContextActionResult.Pass
	elseif inputstate == Enum.UserInputState.Cancel then
		InputController.TouchObject = nil
		InputController.Vector = Vector3.zero

		ring.Position = UDim2.fromScale(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.5)
	end

	return
end

--- returns an empty touchgui
function InputController.createtouchgui(playergui: PlayerGui)
	--- base touchgui
	local touchgui = Instance.new("ScreenGui")
	touchgui.Name = "r0TouchGui"
	touchgui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
	touchgui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	touchgui.IgnoreGuiInset = false
	touchgui.ResetOnSpawn = false

	--- bottom-left thumbstick frame
	local thumbstickframe = Instance.new("Frame")
	thumbstickframe.Name = "ThumbstickFrame"
	thumbstickframe.AnchorPoint = Vector2.zero
	thumbstickframe.Size = InputController.ThumbstickSizeMap[Enum.DisplaySize.Medium]
	thumbstickframe.Position = InputController.ThumbstickPositionMap[Enum.DisplaySize.Medium]
	thumbstickframe.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	thumbstickframe.BackgroundTransparency = 1
	thumbstickframe.Parent = touchgui

	--- ring around circle
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.one * 0.5
	ring.Size = InputController.ThumbstickRingMap[Enum.DisplaySize.Medium]
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 0
	ring.Parent = thumbstickframe

	local ringstroke = Instance.new("UIStroke")
	ringstroke.Thickness = 2
	ringstroke.Transparency = 0.667
	ringstroke.Parent = ring

	local ringcorner = Instance.new("UICorner")
	ringcorner.CornerRadius = UDim.new(1, 0)
	ringcorner.Parent = ring

	--- circle
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.one * 0.5
	circle.Size = InputController.ThumbstickCircleMap[Enum.DisplaySize.Medium]
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	circle.BackgroundTransparency = 0.25
	circle.ZIndex = 1
	circle.Parent = thumbstickframe

	local circlestroke = Instance.new("UIStroke")
	circlestroke.Thickness = 2
	circlestroke.Transparency = 0.667
	circlestroke.Parent = circle

	local circlecorner = Instance.new("UICorner")
	circlecorner.CornerRadius = UDim.new(1, 0)
	circlecorner.Parent = circle
	
	touchgui.Parent = playergui

	return touchgui
end

--- returns internally-resolved `UserInputService.PreferredInput` signal based on recency
function InputController.preferredinputchanged()
	return script:GetAttributeChangedSignal("PreferredInput")
end

if RunService:IsClient() then
	do --- resolve touchgui
		local s, e = pcall(function()
			local playergui = LocalPlayer:WaitForChild("PlayerGui")
			local touchgui = InputController.createtouchgui(playergui)
			
			InputController.TouchGui = touchgui

			--- resize/repositions touchgui wrt displaysize enum
			local function adjust(touchgui: typeof(InputController.createtouchgui(playergui)), displaysize: Enum.DisplaySize)
				local thumbstickframe = (touchgui::any).ThumbstickFrame::Frame

				thumbstickframe.Size = InputController.ThumbstickSizeMap[displaysize]
				thumbstickframe.Position = InputController.ThumbstickPositionMap[displaysize]

				local ring = (thumbstickframe::any).Ring::Frame
				ring.Size = InputController.ThumbstickRingMap[displaysize]
				
				local circle = (thumbstickframe::any).Circle::Frame
				circle.Size = InputController.ThumbstickCircleMap[displaysize]
			end

			local function adjusttouchgui()
				adjust(touchgui, GuiService.ViewportDisplaySize)
			end

			adjusttouchgui()
			GuiService:GetPropertyChangedSignal("ViewportDisplaySize"):Connect(adjusttouchgui)

			touchgui.Enabled = InputController.TouchGuiVisibility[InputController.PreferredInput]
			InputController.preferredinputchanged():Connect(function()
				touchgui.Enabled = InputController.TouchGuiVisibility[InputController.PreferredInput]
			end)
		end)
		if not s then warn(e) end
	end
	do --- resolve internal preferred input
		local s, e = pcall(function()
			local function updatepreferredinput(userinputtype: Enum.UserInputType)
				local thispreferredinput = InputController.InputTypesToPreferredInputs[userinputtype]
				if thispreferredinput == nil then return end
				if InputController.PreferredInput ~= thispreferredinput then
					InputController.PreferredInput = thispreferredinput

					script:SetAttribute("PreferredInput", InputController.PreferredInput.Value)
				end
			end

			UserInputService.LastInputTypeChanged:Connect(updatepreferredinput)
			updatepreferredinput(UserInputService:GetLastInputType())
		end)
		if not s then warn(e) end
	end
end

return InputController