--!strict

--- ### r0client.luau
---
--- r0 local script

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local r0 = require(Shared:WaitForChild("r0"))
local CameraController = r0.CameraController
local InputController = r0.InputController

assert(CameraController and InputController, "this script should be a localscript")

--[[local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local PlayerModule = PlayerScripts:WaitForChild("PlayerModule")
local ControlModule = require(PlayerModule:WaitForChild("ControlModule"))::any]]

local Camera = workspace.CurrentCamera

r0.Container = workspace:WaitForChild("Entities")
r0.CollisionGroup = "Entities"

local r0input = r0.Input
local r0output = r0.Output

do --- r0 input table
	--- raycastparams
	local raycastparams = r0input.RaycastParams
	raycastparams.FilterType = Enum.RaycastFilterType.Exclude
	raycastparams.IgnoreWater = true
	raycastparams.FilterDescendantsInstances = table.create(1, r0.Container)

	--- locomotion
	r0input.Speed = 24
	r0input.JumpPower = 50
	r0input.FloatPower = 400
	r0input.RotationResponsiveness = 30
	
	--- floorcast config
	r0input.FloorcastExtend = 2/8
	r0input.RadiusExtend = -1/8

	--- fly config
	r0input.Flying = false
	r0input.FlyingRotateX = false
end

do --- interpolation settings
	r0.applybreakpoints({
		{ Distance = 200; Interpolate = true; Cycle = 1; };
		{ Distance = 400; Interpolate = false; Cycle = 2; };
		{ Distance = 800; Interpolate = false; Cycle = 4; };
		{ Distance = math.huge; Interpolate = false; Cycle = 4; };
	})
end

local keycodesigns = {
	[Enum.KeyCode.Space] = 1;
	[Enum.KeyCode.ButtonA] = 1;
	[Enum.KeyCode.LeftControl] = -1;
	[Enum.KeyCode.RightControl] = -1;
	[Enum.KeyCode.ButtonL3] = -1;
}

local shiftlockstate = false
local shiftlockkeys = {
	Enum.KeyCode.LeftShift;
	Enum.KeyCode.RightShift;
	Enum.KeyCode.ButtonY;
}

local lastjump = 0
local flywindow = 2/8

local function flight(state: boolean?)
	if state == nil then
		state = not r0input.Flying
	end
	r0input.Flying = state::boolean
end

local function inputbegan(inputobject: InputObject, sunkinput: boolean)
	if sunkinput then return end

	local sign = keycodesigns[inputobject.KeyCode]
	if sign then
		r0input.Vertical = sign

		if sign == 1 then
			local now = os.clock()
			if now - lastjump < flywindow then
				lastjump = 0
				flight()
			end

			lastjump = now
		end
		return
	end

	if table.find(shiftlockkeys, inputobject.KeyCode) then
		shiftlockstate = not shiftlockstate

		if shiftlockstate == true then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			if InputController.PreferredInput == Enum.PreferredInput.Gamepad then
				CameraController.CameraOffset = Vector3.zero
			else
				CameraController.CameraOffset = Vector3.new(1.75, 0, 0)
			end
			r0input.RotationType = Enum.RotationType.CameraRelative
			UserInputService.MouseIcon = "rbxasset://textures/MouseLockedCursor.png"
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			CameraController.CameraOffset = Vector3.zero
			r0input.RotationType = Enum.RotationType.MovementRelative
			UserInputService.MouseIcon = ""
		end
		return
	end
end

UserInputService.InputBegan:Connect(inputbegan)

local function inputended(inputobject: InputObject, sunkinput: boolean)
	--- if sunkinput then return end

	local sign = keycodesigns[inputobject.KeyCode]
	if sign and r0input.Vertical == sign then
		r0input.Vertical = 0
	end
end

UserInputService.InputEnded:Connect(inputended)

local function preferredinputchanged()
	local pi = InputController.PreferredInput
	InputController.rebind(pi)
end

preferredinputchanged()
InputController.preferredinputchanged():Connect(preferredinputchanged)

local function step(dt: number)
	debug.profilebegin("r0step")

	r0input.InputVector = InputController.Vector
	r0input.CameraCFrame = Camera.CFrame

	if r0input.Vertical == -1 then
		r0input.FrictionModifier = 1/24
	else
		r0input.FrictionModifier = 1
	end

	if r0input.Flying then
		r0input.SpeedModifier = 2
	else
		r0input.SpeedModifier = 1
	end

	local character = LocalPlayer.Character
	if not character then return end
	
	r0.step(character, dt)
	r0.pack(r0output.CFrame, r0output.Locomotion, r0input.Vertical, r0.Replication.Local)
	
	if r0input.Flying == true and r0output.Floor ~= nil then
		flight(false)
	end

	debug.profileend()
end

RunService:BindToRenderStep("r0step", Enum.RenderPriority.Character.Value + 1, step)

local replicationidoffset = r0.replicationidoffset()
local frame = 0
local cache = r0.Replication.Cache

do --- force guarantee local replication
	local r = buffer.create(r0.replicationresyncoffset())
	buffer.writef64(r, replicationidoffset, LocalPlayer.UserId)

	table.insert(cache, r)
end

local function replicate(dt: number)
	debug.profilebegin("r0replicate")
	frame += 1

	local zerocycle = frame % r0.Interpolation.MaxCycle == 0
	local i = 1 - (r0.Interpolation.Base ^ dt) --- resolve framerate-independent interpolant

	local replicationfocus = Vector3.zero
	if LocalPlayer.Character then
		replicationfocus = LocalPlayer.Character:GetPivot().Position
	end

	for _, replication in cache do
		local userid = buffer.readf64(replication, replicationidoffset)
		local player = Players:GetPlayerByUserId(userid)
		if player then
			local islocal = player == LocalPlayer
			local character = player.Character::r0.Character
			if not character then
				--- create empty character
				character = r0.create()
				character.Name = player.Name
				character.Parent = r0.Container
				player.Character = character

				local sphere = character.Sphere
				local rootpart = character.RootPart

				--- localcharacter case
				if islocal then
					rootpart.Anchored = false
					Camera.CameraSubject = character:WaitForChild("Head")
					Camera.CameraType = Enum.CameraType.Custom
				else
					rootpart.Anchored = true
				end

				sphere.Transparency = 0.5
				rootpart.Transparency = 0.5
			end

			if islocal then --- if not islocal but keeping this notation for readability
				continue
			else
				local cframe, locomotionstate, vertical = r0.unpack(replication)
				local distancefromfocus = vector.magnitude(cframe.Position::any - replicationfocus::any)
				local breakpoint = r0.interpolationbreakpoint(distancefromfocus)

				if frame % breakpoint.Cycle == 0 then
					if breakpoint.Interpolate then
						local pivot = character:GetPivot()
						local distancefromtarget = vector.magnitude(cframe.Position::any - pivot.Position::any)
						if distancefromtarget > 1000 then
							character:PivotTo(cframe)
						else
							character:PivotTo(pivot:Lerp(cframe, i))
						end
					else
						character:PivotTo(cframe)
					end
				end
			end
		else
			print("erm... guysh?", userid)
			continue
		end
	end
	
	if zerocycle then
		frame = 0
	end

	debug.profileend()
end

RunService:BindToRenderStep("r0replicate", Enum.RenderPriority.Character.Value + 2, replicate)

return true