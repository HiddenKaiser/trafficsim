--[[
> TrafficController.lua
	>> Car.lua
	>> Lane.lua*
	>> Metrics.lua

> TrafficController.rbxm
> README.md
--]]

--// Variables

local RunService = game:GetService("RunService");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Car = require( script.Parent:WaitForChild("Car") );
type CarObject = Car.CarObject;

local RNG: Random = Random.new();
local LaneAmount: number = 0;

-- to be initialized in Lane.initialize
local TrafficController;
local CONSTANTS;
local assert;

--// Helper Functions

-- Moves all values down by 1, will return to end if i-1 < 1
local function shiftDown(t: {any})
	local first = t[1];
	for i = 2, #t do
		t[i-1] = t[i];
	end
	t[#t] = first;
	return t;
end

-- Reverses a dictionary
local function reverseDictionary(original)
	local n = #original;
	local arr = table.create(n);
	for i,v in pairs(original) do
		arr[n-i+1] = v;
	end
	return arr;
end

-- Reverses an array
local function reverseArray(ori)
	local n = #ori;
	local arr = table.create(n);
	for j = 1, math.floor(n/2) do
		local k = n - j + 1;
		arr[j], arr[k] = ori[k], ori[j];
	end
	return arr;
end



--// Class

local Lane = {}
Lane.__index = Lane;

export type LaneObject = {
	miles: number,
	laneIndex: number,
	laneCenter: number?,
	
	carObjects: {CarObject}
}

function Lane.new(miles: number) : LaneObject
	
	if not TrafficController then
		error("Must initialize lane", 2); -- error on the stack that called it
	end
	
	LaneAmount += 1;
	
	local self : any = {
		miles = miles;
		laneIndex = LaneAmount;
		laneCenter = (miles * CONSTANTS.CarLength)/2;
		
		carObjects = {};
		
	}
	
	setmetatable(self, Lane);
	
	return self;
	
end


function Lane:GetCarAt(index: number): CarObject?
	if index < 1 or index > #self.carObjects then
		return nil;
	end
	return self.carObjects[index];
end

function Lane:GetPreviousCar(index: number): CarObject?
	return (index < #self.carObjects and self.carObjects[index+1]) or nil;
end


-- Adds a car to the lane. Used to shift lanes
function Lane:AddCar(newCar: CarObject) : boolean
	
	-- find closest car with a modified binary search
	local closestIndex = self:FindClosestCar(newCar.mile);
	local closest = self.carObjects[closestIndex];
	
	-- don't merge into another car
	if closest and math.abs(closest.mile - newCar.mile) < CONSTANTS.CarLength*3 then
		return false;
	end
	
	-- fit car into array, only 1-2 iterations.
	local index = closestIndex-1;
	
	for i = index, closestIndex do
		local c = self.carObjects[i];
		if c then
			if c.mile > newCar.mile then
				index = i;
			else
				break;
			end
		end
	end
	
	-- remove car from old lane
	if newCar.lane then
		newCar.lane:RemoveCar(newCar);
	end
	
	-- set car's lane to the current lane
	newCar.lane = self; 
	
	-- incoporate car into lane data
	local myIndex = index + 1;
	
	local ahead = self:GetCarAt(index); -- index == myIndex - 1
	local behind = self:GetCarAt(myIndex);
	
	if behind then
		behind.ahead = newCar;
	end
	
	newCar.ahead = ahead;
	
	table.insert(self.carObjects, myIndex, newCar);
	
	-- update colors based on lane #
	newCar:UpdateColors();
	
	-- successfully changed lane
	return true;
end

-- Removes car reference from lane
function Lane:RemoveCar(car: CarObject)
	local i = table.find(self.carObjects, car);
	if i then
		local behind = self:GetCarAt(i+1);
		local ahead = self:GetCarAt(i-1);
		
		table.remove(self.carObjects, i);
		
		if behind then 
			behind.ahead = ahead;
		end
	end
end

-- Arrange so that the cars in front will update first. Only used when the list is first populated.
function Lane:Rearrange()
	return table.sort(self.carObjects, function(a: CarObject, b: CarObject)
		return a.mile > b.mile;
	end)
end


-- Reverses the index given by the closest car binary search. (Binary search below)
function Lane:FindClosestCar(...): number?
	local i = self:FindClosestCar_Binary(...);
	return i and (#self.carObjects - i + 1);
end


-- Helper function for lane binary search
function Lane.getClosest(arr: {CarObject}, i1: number, i2: number, target: number): number
	if (target - arr[i1].mile) >= (arr[i2].mile - target) then
		return i2
	else
		return i1
	end
end

-- Perform binary search to find closest car. Index return needs to be reversed.
-- This allows performant searches with massive amounts of cars
-- O(log n) complexity
function Lane:FindClosestCar_Binary(target: number): number
	local arr = reverseDictionary(self.carObjects);
	local n = #arr;
	
	-- array is empty
	if n < 1 then
		return 1;
	end
	
	-- check edges
	if (target <= arr[1].mile) then
		return 1;
	end
	if (target >= arr[n].mile) then
		return n;
	end
	
	TrafficController.PerformanceMetrics.SearchAvg:Add(0, 1);

	-- Binary search
	local low, high, mid = 1, n, 0;

	while (low < high) do
		
		TrafficController.PerformanceMetrics.SearchAvg:Add(1, 0);
		
		mid = math.floor( (low + high) / 2 );

		if (arr[mid].mile == target) then
			return mid;
		end

		if (target < arr[mid].mile)  then
			if (mid > 1 and target > arr[mid - 1].mile) then
				return Lane.getClosest(
					arr,
					mid - 1,
					mid,
					target
				);
			end
			high = mid
		else
			if (mid < n and target < arr[mid + 1].mile) then
				return Lane.getClosest(
					arr,
					mid,
					mid + 1,
					target
				);
			end
			low = mid + 1
		end
	end

	-- last index left
	return mid;
end


-- Attempts to change lanes
function Lane:AttemptLaneChange(c: CarObject): boolean
	if not c:IsEventActive("LaneCooldown") then
		local validLanes = {};
		for i,lane2 in pairs(TrafficController.Lanes) do
			if lane2 ~= self and math.abs(lane2.laneIndex - self.laneIndex) <= 1 then
				table.insert(validLanes, lane2);
			end
		end

		while #validLanes > 0 do
			local i = math.random(1,#validLanes);
			local lane2 = validLanes[i];

			if lane2 and lane2:AddCar(c) then
				c:TriggerEvent("LaneCooldown", 3);
				return true;
			else
				table.remove(validLanes, i);
			end
		end
	end
	return false;
end


--// Main update loop

function Lane:Update(deltaTime: number)
	local carObjects = self.carObjects;
	local MAX_MILES = self.miles * CONSTANTS.CarLength;
	
	for i,c in pairs(carObjects) do
		
		c:Update(deltaTime);

		if c.mile >= MAX_MILES then
			
			shiftDown(carObjects);
			
			local cAhead = self:GetCarAt(#carObjects-1); -- 2nd to last car, last car is c
			c.ahead = cAhead; -- set ahead
			
			if cAhead then
				cAhead.behind = c;
			end
			
			c.mile = 0;
			c.behind = nil;
			
			TrafficController.PerformanceMetrics.CarThroughput:Add();
		end

		local slowRoll = RNG:NextInteger(1,17500);
		if slowRoll == 1 then
			c:TriggerEvent("SlowDown", 10);
		else
			local stopRoll = RNG:NextInteger(1,100000);
			if stopRoll == 1 and c.speed > 15 then
				c:TriggerEvent("StopEvent", 7);
			end
		end
		
		local laneChange = RNG:NextInteger(1,500);
		if laneChange == 1 then
			self:AttemptLaneChange(c);
		end
		
	end
	
	self.carObjects = carObjects;
end


function Lane:Model()
	local max = (self.miles * CONSTANTS.CarLength);

	local roadBeam = self:CreateBeam(Vector2.new(10 * self.laneIndex, 0), max, 9);
	roadBeam.Color = ColorSequence.new(Color3.new(0.227451, 0.227451, 0.227451));

	if self.laneIndex < #TrafficController.Lanes then
		local dashBeam = self:CreateBeam(Vector2.new(10 * self.laneIndex + 5, 0), max, 1);
		dashBeam.Color = ColorSequence.new(Color3.new(1, 1, 1));
	end
end

function Lane:Populate()

	if CONSTANTS.Visualize then
		self:Model();
	end

	for mile = 1, self.miles do
		local roll = RNG:NextInteger(1, 3);

		if roll == 1 and #self.carObjects < CONSTANTS.MaxCars then
			local c = Car.new(mile * CONSTANTS.CarLength, self);

			table.insert(self.carObjects, c);

			local previous = #self.carObjects > 1 and self.carObjects[#self.carObjects-1];
			if previous then
				previous.ahead = c;
				c.behind = previous;
			end
		end
	end

	self:Rearrange();

	self.carObjects[1]:SetSpeed(CONSTANTS.TargetSpeed);
end


function Lane:NewAttachment(pos)
	local part: BasePart = Instance.new("Part");

	part.Anchored = true;
	part.Size = Vector3.new(1,1,1);
	local a = Instance.new("Attachment", part);
	part.Transparency = 1;
	part.CFrame = CFrame.new(pos) * CFrame.Angles(0,0,math.rad(90));
	part.Name = "Lane"..self.laneIndex;

	part.Parent = workspace;

	return a;
end

function Lane:CreateBeam(pos, max, width)
	max /= 2;
	local a1 = self:NewAttachment(Vector3.new(pos.X, pos.Y, max));
	local a2 = self:NewAttachment(Vector3.new(pos.X, pos.Y, -max));

	local beam = Instance.new("Beam");
	beam.Attachment0 = a1;
	beam.Attachment1 = a2;
	beam.Width0 = width;
	beam.Width1 = width;
	beam.Transparency = NumberSequence.new(0,0);

	beam.Parent = a1.Parent;

	return beam;
end


-- setup variables from master
function Lane.intialize(TrafficControl)
	TrafficController = TrafficControl;
	CONSTANTS = TrafficControl.CONSTANTS;
	assert = TrafficControl.assert;
end



return Lane;
