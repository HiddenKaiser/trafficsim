--[[
> TrafficController.lua
	>> Car.lua*
	>> Lane.lua
	>> Metrics.lua

> TrafficController.rbxm
> README.md
--]]

--// Initialized in Car.intialize
local TrafficController;
local CONSTANTS;
local assert;

--// Functions

local function lerp(a, b, d)
	return a + (b - a) * d;
end


--// Class

export type CarEvent = {
	Started: number,
	Duration: number
}

export type SpeedEvent = {
	dir: number,
	accel: number,
	triggered: number
}

export type CarObject = {
	mile: number, -- how far the car is along the road
	lane: any,
	speed: number, -- current speed of the car
	predictedSpeed: number, -- predicted speed before acceleration is applied
	
	speedQueue: {SpeedEvent},
	events: {CarEvent}, -- keeps list of ticks
	
	ahead: CarObject?,
	behind: CarObject?,
	
	part: BasePart?
}


local Car = {};
Car.__index = Car;


-- Main Constructor
function Car.new(mile: number, lane: any, speed: number?, part: BasePart?) : CarObject
	
	if not TrafficController then
		error("Must initialize Car", 2); -- error on the stack that called it
	end
	
	local self : any = {
		mile = mile;
		lane = lane;
		speed = speed or CONSTANTS.TargetSpeed;
		predictedSpeed = speed or CONSTANTS.TargetSpeed;
		
		speedQueue = {};
		events = {};
		
		-- Will be handled by traffic controller
		ahead = nil;
		behind = nil;
		
		part = part;
	}
	
	setmetatable(self, Car);
	
	if CONSTANTS.Visualize and not self.part then
		self.part = self:GeneratePart();
		self:UpdateColors();
	end
	
	return self;
end


--// Distance

-- get rid of redundancy and save some processing power
function Car:GetRoadLength()
	if not self.roadLength then
		self.roadLength = (self.lane.miles * CONSTANTS.CarLength);
	end
	
	return self.roadLength;
end

-- Simply get the distance to the passed car
function Car:DistanceTo(Other: CarObject) : number
	
	-- if the car is on the other side, calculate distance based on that.
	if Other.mile < self.mile then
		return math.abs(Other.mile + (self:GetRoadLength() - self.mile));
	end
	
	return math.abs( Other.mile - self.mile);
end

-- How far off the current car is from the target following distance on the passed car
function Car:GetTargetOffset(Other: CarObject) : number
	if Other.mile < self.mile then
		return Other.mile + self:GetRoadLength() - CONSTANTS.FollowingDistance - self.mile;
	end
	
	return Other.mile - CONSTANTS.FollowingDistance - self.mile;
end


--// Speed

-- Applies acceleration by the distance parameter which is a value from -1 to 1
function Car:Accelerate_Real(dir: number, deltaTime: number)
	self.speed += (CONSTANTS.Acceleration * deltaTime) * dir;
	self.predictedSpeed = self.speed;
end

-- Account for human reaction time, implements a custom task scheduler
function Car:Accelerate(dir: number, deltaTime: number?)
	local appliedSpeed = (CONSTANTS.Acceleration * deltaTime) * dir;
	
	self.predictedSpeed += appliedSpeed;
	table.insert(self.speedQueue, {
		dir = dir,
		accel = appliedSpeed,
		triggered = tick()
	});
end

-- Apply queued speed based on human reaction time
-- Table Structure: {Longest Elapsed t -> Shortest Elapsed t}
function Car:UpdateSpeedQueue(TICK: number, deltaTime: number)
	
	for i,q in pairs(self.speedQueue) do
		local q = self.speedQueue[i];
		
		local elapsed = (TICK - q.triggered);
		if elapsed >= CONSTANTS.ReactionTime then
			self.speed += q.accel;
			table.remove(self.speedQueue, i);
		else
			-- any event that comes after this will be less than the elapsed time, so break;
			break;
		end
	end
	
end

-- Set absolute speed of car instantly
function Car:SetSpeed(speed: number)
	self.speed = speed;
	self.predictedSpeed = speed;
end


--// Events

-- Checks if the event is still active, and remove it if it isnt.
function Car:IsEventActive(name: string, TICK: number?): boolean
	
	if not self.events[name] then
		return false;
	end
	
	local Event: CarEvent? = self.events[name];
	
	if Event then
		if ((TICK or tick()) - Event.Started) <= Event.Duration then
			return true;
		else
			self.events[name] = nil;
		end
	end
	
	return false;
end

-- Adds to an event's duration if it exists, or creates it if it doesn't
function Car:TriggerEvent(name: string, duration: number): CarEvent
	local Event: CarEvent = self.events[name];
	
	if Event then
		Event.Duration += duration;
	else
		Event = {
			Started = tick(),
			Duration = duration
		}
		
		self.events[name] = Event;
	end
	
	return Event;
end

-- check if the events are active and activate their effects
function Car:EventsUpdate(TICK: number, deltaTime: number) : boolean
	
	if self:IsEventActive("SlowDown", TICK) then
		if self.predictedSpeed > CONSTANTS.TargetSpeed-20 then
			self:Accelerate(-0.5, deltaTime);
		end
		self.speed = math.clamp(self.speed, 1, CONSTANTS.TargetSpeed)
		return false;
	end

	if self:IsEventActive("StopEvent", TICK) then
		self:Accelerate(-0.5, deltaTime);
		self.speed = math.clamp(self.speed, 0, CONSTANTS.TargetSpeed);
		return false;
	end
	
	return true;
end



--// Main update loop

function Car:Update(deltaTime: number)
	
	local TICK = tick();
	
	self:UpdateSpeedQueue(TICK, deltaTime);
	
	local speedChangeEnabled: boolean = self:EventsUpdate(TICK, deltaTime);
	local ahead : CarObject? = self.ahead;
	
	if speedChangeEnabled then
	
		-- match the speed of the car ahead
		if ahead then
			local difference = self:GetTargetOffset(ahead);
			
			if difference > 10 then
				self:Accelerate(1, deltaTime);
			else
				self:Accelerate(-1.75, deltaTime);
			end
			
			local dist = self:DistanceTo(ahead);
			
			if dist <= 175 and self.speed >= ahead.speed+10 then
				self:Accelerate_Real(-3.5, deltaTime);
			elseif self.predictedSpeed < CONSTANTS.TargetSpeed then
				self:Accelerate(0.5, deltaTime);
			end
			
		else
			if self.predictedSpeed < CONSTANTS.TargetSpeed then
				self:Accelerate(1, deltaTime);
			end
		end
		
	end
	
	-- // Move forward by speed
	self.speed = math.clamp(self.speed, 1, CONSTANTS.SpeedLimit); -- limit speed
	local moveDist = (self.speed * deltaTime); -- set new mile
	
	local crashPos = ahead and (ahead.mile-CONSTANTS.CarLength-1);
	
	if 
		ahead
		and ahead ~= self.lane.carObjects[#self.lane.carObjects] -- make sure the car ahead isn't loooped around before crashing  
		and (self.mile + moveDist) > crashPos -- check if the car has crashed into the one in front
	then
		-- If the car is about to crash, try to shift lanes. If it cannot shift lanes, then it crashes.
		if not self.lane:AttemptLaneChange(self) then
			self:SetSpeed(1);
		end
	else
		self.mile += moveDist;
	end
	
	
	if CONSTANTS.Visualize then
		self:VisualizeMile();
	end
	
end

function Car:ToWorldPos() : Vector3
	return Vector3.new(self.lane.laneIndex * 10, 2, self.mile - self.lane.laneCenter);
end

function Car:VisualizeMile(dontLerp: boolean?)
	local lastCFrame = self.part.CFrame;
	local pos = self:ToWorldPos();
	
	self.part.CFrame = CFrame.new(
		Vector3.new(
			lerp(lastCFrame.Position.X,pos.x,0.025),
			pos.y,
			pos.z
		)
	);
end

-- change color based on what lane the car is in
function Car:UpdateColors()
	if not self.part then return end;
	
	if self.lane.laneIndex % 2 == 0 then
		self.part.BrickColor = BrickColor.new("Sea green");
	else
		self.part.BrickColor = BrickColor.new("Cyan");
	end
end

-- generate the physical car object
function Car:GeneratePart() : BasePart
	local part: BasePart = Instance.new("Part");
	
	part.Anchored = true;
	part.CanCollide = false;
	part.Size = Vector3.new(5, 3, CONSTANTS.CarLength);
	part.BrickColor = BrickColor.new("Cyan");
	part.CastShadow = false;
	part.Name = "Car"
	
	part.Parent = workspace.CarContainer;
	
	return part;
end


-- setup variables from master
function Car.intialize(TrafficControl)
	TrafficController = TrafficControl;
	CONSTANTS = TrafficControl.CONSTANTS;
	assert = TrafficControl.assert;
end


return Car;
