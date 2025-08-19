--!strict

local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local Players = game:GetService("Players")

local Remote = script:WaitForChild("Remote")

--- returns movevector from input vector `i` relative to `cframe`
@native
local function movevector(i: Vector3, cframe: CFrame)
	local cos, sin
	local _, _, _, R00, R01, R02, _, _, R12, _, _, R22 = cframe:GetComponents()
	if R12 < 1 and R12 > -1 then
		--- cos, sin = lookvector.x, lookvector.z
		cos = R22
		sin = R02
	else
		--- cos, sin = rightvector.x, upvector.x
		cos = R00
		sin = -R01*math.sign(R12)
	end

	local length = (cos*cos + sin*sin)^0.5
	return Vector3.new(cos*i.X + sin*i.Z, 0, cos*i.Z - sin*i.X) / length
end

--- returns xyz movevector from input vector `i` and vertical input `v` relative to `cframe`
@native
function movevectorxyz(i: Vector3, v: number, cframe: CFrame)
	local vec = cframe.Rotation:VectorToWorldSpace(i) + (Vector3.yAxis * v)
	if vec == Vector3.zero then
		return Vector3.zero
	end

	return (vector.normalize(vec::any)::any)::Vector3 --- this is insane
end

--- returns `v.Unit`, or, if `NaN`, `Vector3.zero`
@native
local function unit_or_zero(v: Vector3)
	if v.Magnitude > 0 then
		return v.Unit
	else
		return Vector3.zero
	end
end

--- returns `v` projected onto `w`
@native
local function project(v: Vector3, w: Vector3)
	w = unit_or_zero(w)
	return v:Dot(w) * w
end

--- returns `v` rejected from `w`
@native
local function reject(v: Vector3, w: Vector3)
	return v - project(v, w)
end

--- writes signed 24-bit integer to buffer
@native
local function writei24(b: buffer, offset: number, value: number)
	local bitoffset = offset * 8
	local sign = math.sign(value) < 0 and 1 or 0
	if sign == 1 then
		value += 1
	end
	
	buffer.writebits(b, bitoffset, 23, math.abs(value))
	buffer.writebits(b, bitoffset + 23, 1, sign)
end

--- reads signed 24-bit integer from buffer
@native
local function readi24(b: buffer, offset: number)
	local bitoffset = offset * 8
	local value = buffer.readbits(b, bitoffset, 23)
	local sign = buffer.readbits(b, bitoffset + 23, 1)
	
	if sign == 1 then
		value *= -1
		value -= 1
	end
	
	return value
end

export type Character = typeof(script.StarterCharacter)

--- ### r0.luau
---
--- zero-limb humanoidless character controller
local r0 = {
	CameraController = require(script:WaitForChild("CameraController"));
	InputController = require(script:WaitForChild("InputController"));

	Input = {
		--- empty raycastparams
		RaycastParams = RaycastParams.new();

		--- empty inputvector
		--- `ControlScript:GetMoveVector()`
		InputVector = Vector3.zero;
		--- signed number
		Vertical = 0;

		--- empty camera cframe
		CameraCFrame = CFrame.identity;

		--- character rotation type
		RotationType = Enum.RotationType.MovementRelative;
		--- forced character rotation
		RotationForce = nil :: Vector3?;
		--- alignorientation.responsiveness
		RotationResponsiveness = 30;

		--- is in flying state
		Flying = false;
		--- if flying, rotate x axis?
		FlyingRotateX = true;

		--- extend floorcast length by this many studs
		FloorcastExtend = 0;
		--- extend floorcast radius by this many studs
		RadiusExtend = 0;

		--- truespeed = speed * speedmodifier
		Speed = 16;
		SpeedModifier = 1;

		--- truejumppower = jumppower * jumpmodifier
		JumpPower = 50;
		JumpModifier = 1;

		--- truefloatpower = floatpower * floatmodifier
		FloatPower = 0;
		FloatModifier = 1;

		--- linearvelocity.
		Friction = Vector3.one * 3000;
		FrictionModifier = 1;
	};
	Output = {
		--- floor, if found, of character stepped by `r0.step()`
		Floor = nil :: RaycastResult?;
		--- cframe of character stepped by `r0.step()`
		CFrame = CFrame.identity;
		--- locomotion state
		Locomotion = 0;
	};
	LocomotionStates = {
		"Idle";
		"Walk";
		"Fall";
		"Fly";
	};
	Replication = {
		Local = buffer.create(12);
		Cache = table.create(1 + Players.MaxPlayers) :: {buffer};

		ReadWritePrecision = 50;

		ClientSendRate = 1/45;
		ServerSendRate = 1/15;

		UnreliableByteLimit = 1000;
	};
	Interpolation = {
		Base = 10e-11;
		MaxCycle = 1;
		Breakpoints = table.create(8);
	};

	--- r0 character container instance
	Container = workspace;
	--- r0 character collision group
	CollisionGroup = "Default";

	SphereMeshId = "rbxassetid://122701517143775"; --- me when rojo :/
	SphereCollisionFidelity = Enum.CollisionFidelity.Hull --- me when rojo pt 2 :/
}

--- creates new character
function r0.create()
	local character = script.StarterCharacter:Clone()
	for _, thing in character:GetDescendants() do
		if thing:IsA("BasePart") then
			thing.CollisionGroup = r0.CollisionGroup
		end
	end
	
	return character
end

--- re-signs an unsigned number read from 2 bits
@native
function r0.resign(unsigned: number)
	if unsigned > 1 then
		return -1
	end

	return unsigned
end

--- un-signs an signed number to write into 2 bits
@native
function r0.unsign(signed: number)
	local sign = math.sign(signed)
	if sign < 0 then
		return 2
	end

	return sign
end

--- returns interpolation breakpoint wrt distance
function r0.interpolationbreakpoint(distance: number)
	for i, b in ipairs(r0.Interpolation.Breakpoints) do
		if distance < b.Distance then
			return b
		end
	end

	return { Distance = math.huge, Interpolate = false, Cycle = 1 }
end

--- applies interpolation breakpoints \
--- auto-sorts `b` by distance, ascending
function r0.applybreakpoints(b: { {Distance: number, Interpolate: boolean, Cycle: number} })
	table.sort(b, function(j, k)
		return j.Distance < k.Distance
	end)

	table.clear(r0.Interpolation.Breakpoints)
	table.move(b, 1, #b, 1, r0.Interpolation.Breakpoints)

	local maxcycle = 1
	for _, breakpoint in ipairs(b) do
		local cycle = breakpoint.Cycle
		if maxcycle < cycle then
			maxcycle = cycle
		end
	end

	r0.Interpolation.MaxCycle = maxcycle
end

--- packs cframe, locomotion state, and signed vertical input into 12-wide replication
function r0.pack(cframe: CFrame, locomotionstate: number, vertical: number, r: buffer?)
	if not r then
		r = buffer.create(12)
	end
	assert(r)

	local position = cframe.Position * r0.Replication.ReadWritePrecision
	writei24(r, 0, position.X)
	writei24(r, 3, position.Y)
	writei24(r, 6, position.Z)

	local rx, ry = cframe:ToOrientation()
	buffer.writeu8(r, 9, math.map(rx, -math.pi, math.pi, 0, 255))
	buffer.writeu8(r, 10, math.map(ry, -math.pi, math.pi, 0, 255))

	local bitoffset = 11 * 8
	buffer.writebits(r, bitoffset + 0, 6, locomotionstate)
	buffer.writebits(r, bitoffset + 6, 2, r0.unsign(vertical))

	return r
end

--- unpacks cframe, locomotion state, and signed vertical input from 12-wide replication
function r0.unpack(r: buffer)
	local position = Vector3.new(
		readi24(r, 0),
		readi24(r, 3),
		readi24(r, 6)
	) / r0.Replication.ReadWritePrecision

	local rx = math.map(buffer.readu8(r, 9), 0, 255, -math.pi, math.pi)
	local ry = math.map(buffer.readu8(r, 10), 0, 255, -math.pi, math.pi)
	
	local bitoffset = 11 * 8
	local locomotionstate = buffer.readbits(r, bitoffset + 0, 6)
	local vertical = r0.resign(buffer.readbits(r, bitoffset + 6, 2))

	return CFrame.new(position) * CFrame.fromOrientation(rx, ry, 0), locomotionstate, vertical
end

--- returns floor of character
function r0.floorcast(character: Character, radius: number, heightextend: number?)
	local rootpart = character.RootPart

	local topattachment = rootpart.TopAttachment
	local bottomattachment = rootpart.BottomAttachment

	local upvector = topattachment.WorldCFrame.UpVector
	local topposition = topattachment.WorldCFrame.Position
	local bottomposition = bottomattachment.WorldCFrame.Position

	--- radius crunch
	topposition -= upvector * radius
	bottomposition += upvector * radius

	local height = vector.magnitude(topposition - bottomposition)
	height += heightextend or 1/8

	return workspace:Spherecast(topposition, radius, -upvector * height, r0.Input.RaycastParams)
end

--- advances character by `dt`
function r0.step(character: Character, dt: number)
	local input = r0.Input
	local output = r0.Output

	local sphere = character.Sphere
	local rootpart = character.RootPart

	local cframe = rootpart.CFrame

	local alignorientation = rootpart.AlignOrientation
	local linearvelocity = rootpart.LinearVelocity

	local floor = r0.floorcast(character, (sphere.Size.X * 0.5) + input.RadiusExtend, input.FloorcastExtend)

	local isflying = input.Flying

	--- jump
	if input.Vertical == 1 then
		local lv = rootpart.AssemblyLinearVelocity
		if floor then
			rootpart.AssemblyLinearVelocity = Vector3.new(lv.X, input.JumpPower * input.JumpModifier, lv.Z)
		else
			rootpart:ApplyImpulse(Vector3.yAxis * input.FloatPower * input.FloatModifier * dt)
		end
	end
	
	--- true input vector
	local truevector = Vector3.zero
	if isflying then
		truevector = movevectorxyz(input.InputVector, input.Vertical, input.CameraCFrame)
	else
		truevector = movevector(input.InputVector, input.CameraCFrame)
	end
	local len = vector.magnitude(truevector::any)::any
	local ismoving = len > 0
	if ismoving then
		truevector = vector.normalize(truevector::any)::any
	end

	--- update alignorientation
	if ismoving then
		alignorientation.CFrame = CFrame.lookAlong(Vector3.zero, truevector)
	else
		if isflying then
			alignorientation.CFrame = CFrame.lookAlong(Vector3.zero, cframe.LookVector)
		else
			alignorientation.CFrame = CFrame.lookAlong(Vector3.zero, reject(cframe.LookVector, Vector3.yAxis))
		end
	end
	alignorientation.Responsiveness = input.RotationResponsiveness

	--- resolve rotation type
	local rx, ry = 0, 0
	if input.RotationForce ~= nil then
		local cf = CFrame.lookAlong(Vector3.zero, input.RotationForce)
		rx, ry = cf:ToOrientation()
	else
		if input.RotationType == Enum.RotationType.CameraRelative then
			rx, ry = input.CameraCFrame:ToOrientation()
		elseif input.RotationType == Enum.RotationType.MovementRelative then
			rx, ry = cframe:ToOrientation()
		end
	end

	--- force align along axes, resolves camera jitter for some reason likely some conflict with movers
	if isflying then
		if input.FlyingRotateX == false then
			rx = 0
		end

		if ismoving then
			local tx, ty = CFrame.lookAlong(Vector3.zero, truevector):ToOrientation()
			if input.FlyingRotateX == false then
				tx = 0
			end

			if vector.magnitude((truevector*Vector3.new(1, 0, 1))::any) > 10e-4 then
				alignorientation.CFrame = CFrame.fromOrientation(tx, ty, 0)
			else
				alignorientation.CFrame = CFrame.fromOrientation(rx, ry, 0)
			end
		end

		rootpart.CFrame = CFrame.new(cframe.Position) * CFrame.fromOrientation(rx, ry, 0)
	else
		rootpart.CFrame = CFrame.new(cframe.Position) * CFrame.fromOrientation(0, ry, 0)
	end

	--- move
	local velocity = truevector * input.Speed * input.SpeedModifier * math.clamp(len, 0, 1)
	if isflying then
		linearvelocity.MaxAxesForce = input.Friction
	else
		linearvelocity.MaxAxesForce = input.Friction * Vector3.new(1, 0, 1) * input.FrictionModifier
	end
	linearvelocity.VectorVelocity = velocity

	--- resolve locomotion
	local locomotion = nil
	if isflying then
		locomotion = table.find(r0.LocomotionStates, "Fly")
	else
		if floor == nil then
			locomotion = table.find(r0.LocomotionStates, "Fall")
		else
			if ismoving then
				locomotion = table.find(r0.LocomotionStates, "Walk")
			else
				locomotion = table.find(r0.LocomotionStates, "Idle")
			end
		end
	end

	--- update output
	output.CFrame = rootpart.CFrame
	output.Floor = floor
	output.Locomotion = locomotion or 0
end

local replicationlen = buffer.len(r0.pack(CFrame.identity, 0, 0))
local idoffset = replicationlen + 0
local resyncoffset = replicationlen + 8

--- returns replication id byte offset \
--- for external use
function r0.replicationidoffset()
	return idoffset
end

--- returns replication resync byte offset \
--- for external use
function r0.replicationresyncoffset()
	return resyncoffset
end

--- clears userid from replication cache
function r0.clear(userid: number)
	local cache = r0.Replication.Cache
	for i = #cache, 1, -1 do
		local b = cache[i]
		if buffer.readf64(b, idoffset) == userid then
			table.remove(cache, i)
		end
	end
end

if IsServer then
	local cache = r0.Replication.Cache

	local truebudget = r0.Replication.UnreliableByteLimit - (9 + 2) --- unreliable remote limit - (9 bytes overhead, 2 bytes data type)
	local maxentries = truebudget // (replicationlen + 8) --- [replicationlen bytes replication pack, 8 bytes userid]

	local recent = os.clock() - r0.Replication.ServerSendRate
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - recent
		if dt > r0.Replication.ServerSendRate then
			recent = now - (dt - r0.Replication.ServerSendRate)

			--- advance all buffers by deltatime
			--- then sort by latest resync time
			--- so that resyncing is an eventuality
			for _, replication in cache do
				local resynctime = buffer.readf64(replication, resyncoffset)
				buffer.writef64(replication, resyncoffset, resynctime + dt)
			end

			table.sort(cache, function(a, b)
				return buffer.readf64(a, resyncoffset) > buffer.readf64(b, resyncoffset)
			end)
			
			--- create big buffer to send over network
			local cachelen = #cache
			local bigbuffer = buffer.create(resyncoffset * math.min(cachelen, maxentries))
			for i = cachelen, 1, -1 do
				local replication = cache[i]
				if replication then
					local offset = (i - 1) * resyncoffset
					buffer.copy(bigbuffer, offset, replication, 0, resyncoffset)

					table.remove(cache, i)
				end
			end

			--- only send if worth sending over
			if buffer.len(bigbuffer) > 0 then
				Remote:FireAllClients(bigbuffer)
			end
		end
	end)

	Remote.OnServerEvent:Connect(function(player: Player, challenge: buffer)
		assert(type(challenge) == "buffer", "r0 replication buffer type mismatch")
		assert(buffer.len(challenge) == replicationlen, "r0 replication buffer len mismatch")

		--- if preexisting replication, copy to preexisting
		local userid = player.UserId
		local preexisting = false
		for _, replication in cache do
			if buffer.readf64(replication, idoffset) == userid then
				buffer.copy(replication, 0, challenge, 0, replicationlen) --- copy replication portion
				preexisting = true

				break
			end
		end

		--- if no preexisting replication, insert new replication
		if not preexisting then
			local replication = buffer.create(replicationlen + 16) --- [replicationlen bytes replication pack, 8 bytes userid, 8 bytes resynctime]
			buffer.copy(replication, 0, challenge, 0, replicationlen) --- copy replication + userid portion
			buffer.writef64(replication, idoffset, userid)
			--- buffer.writef64(replication, resyncoffset, 0)

			table.insert(cache, replication)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		r0.clear(player.UserId)
	end)
else
	local cache = r0.Replication.Cache

	local recent = os.clock() - r0.Replication.ClientSendRate
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - recent
		if dt > r0.Replication.ClientSendRate then
			recent = now - (dt - r0.Replication.ClientSendRate)

			Remote:FireServer(r0.Replication.Local)
		end
	end)

	@native
	local function resync(bigbuffer: buffer)
		local len = buffer.len(bigbuffer)
		for i = 1, len, resyncoffset do
			local offset = (i - 1)
			local challenge = buffer.create(resyncoffset)
			buffer.copy(challenge, 0, bigbuffer, offset, resyncoffset)
			
			--- if preexisting replication, copy to preexisting
			local userid = buffer.readf64(challenge, idoffset)
			local preexisting = false
			for _, replication in cache do
				if buffer.readf64(replication, idoffset) == userid then
					buffer.copy(replication, 0, challenge, 0)
					preexisting = true

					break
				end
			end

			--- if no preexisting replication, insert new replication
			if not preexisting then
				table.insert(cache, challenge)
			end
		end
	end

	Remote.OnClientEvent:Connect(resync)

	Players.PlayerRemoving:Connect(function(player: Player)
		r0.clear(player.UserId)
	end)
end

return r0