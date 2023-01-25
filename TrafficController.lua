--[[
> TrafficController.lua*
	>> Car.lua
	>> Lane.lua
	>> Metrics.lua

> TrafficController.rbxm
> README.md
--]]

--// Traffic Controller \\--

local TrafficController = {
	CONSTANTS = {
		ReactionTime = 375; -- in ms, 500 is the average human reaction time for traffic;
		
		TargetSpeed = 80; -- in studs a second, determines car speed
		SpeedLimit = 100; -- maximum speed
		Acceleration = 20; -- Acceleration studs/second^2
		
		CarLength = 10.0; -- how long the cars are in studs
		FollowingDistance = 1.25; -- distance from each edge of cars, equal to FollowingDistance * Car Length
		
		Miles = 375;
		MaxCars = 50;
		Lanes = 100;
		
		Visualize = true;
		CollectPerformanceData = true;
	},
	
	-- Error in the calling stack
	assert = function(condition, errorMsg)
		if not condition then
			return error(errorMsg, 3)
		end
	end,
	
	Lanes = {},
	PerformanceMetrics = {}
};


--// Services

local RunService = game:GetService("RunService");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Lane = require( script:WaitForChild("Lane") );
local Car = require( script:WaitForChild("Car") );
local Data = require( script:WaitForChild("Metrics") );

type LaneObject = Lane.LaneObject;
type CarObject = Car.CarObject;

--// Variables

local miles = TrafficController.CONSTANTS.Miles;
local cars : {CarObject?} = table.create(miles);
local tempObjs : {CarObject} = {};

local rng = Random.new();

 -- intialize dependencies
Car.intialize(TrafficController);
Lane.intialize(TrafficController);

--// Functions

function getCarAt(index: number): CarObject?
	if index < 1 or index > miles then
		return nil;
	end
	return cars[index];
end

function getPreviousCar(index: number): CarObject?
	local j = index-1;
	while j >= 1 do
		if cars[j] then
			return cars[j];
		end
		j -= 1;
	end
	return nil;
end

function shiftDown(t: {any})
	local first = t[1];
	for i = 2, #t do
		t[i-1] = t[i];
	end
	t[#t] = first;
	return t;
end


--// Initialization

function TrafficController.initialize()
	
	--// Constant Processing

	local CONSTANTS = TrafficController.CONSTANTS;
	
	CONSTANTS.ReactionTime /= 1000.0; -- convert ms to seconds

	CONSTANTS.FollowingDistance += 1; -- account for size of car
	CONSTANTS.FollowingDistance *= CONSTANTS.CarLength; -- compute absolute TargetDistance
	CONSTANTS.FollowingDistance += CONSTANTS.CarLength/2.0; -- compute TargetDistance so that distance is from the edges of each car
	
	
	--// Metrics Setup
	
	local metrics = TrafficController.PerformanceMetrics;
	
	metrics.SearchAvg = Data.AverageCounter.new("Binary Search Avg Iterations", true);
	metrics.UpdateLoop = Data.AverageCounter.new("Avg Lane Update Time (in seconds)");
	metrics.CarThroughput = Data.Counter.new("Car Throughput", true);
	metrics.AvgCars = Data.AverageCounter.new("Avg Cars Per Lane", true);
	
	
	--// Lane Setup
	
	local Lanes = TrafficController.Lanes;

	for i = 1,CONSTANTS.Lanes do
		table.insert(Lanes, Lane.new(CONSTANTS.Miles) )
	end

	for i,lane in pairs(Lanes) do
		lane:Populate();
	end
	
	local totalCars = 0;
	
	for i,lane in pairs(Lanes) do
		totalCars += #lane.carObjects;
	end
	
	warn("Simulating", totalCars, "Cars.");
	
	local lastMetric = CONSTANTS.CollectPerformanceData and tick();

	RunService.Heartbeat:Connect(function(deltaTime)
		
		if lastMetric and (tick() - lastMetric) >= 10 then
			lastMetric = tick();
			
			print("-----------------------------------------------------");
			warn("Simulating", totalCars, "Cars. Metrics showing data from the past 10 seconds.");
			for i,metric in pairs(metrics) do
				metric:Display();
				metric:Reset();
			end
			print("-----------------------------------------------------");
			
		end
		
		local begin = os.clock();
		
		for i,lane in pairs(Lanes) do
			lane:Update(deltaTime); -- update the lane, and all the cars in it
			
			metrics.AvgCars:Add(#lane.carObjects);
		end
		
		local elapsed = os.clock() - begin;
		
		metrics.UpdateLoop:Add(elapsed / #Lanes); -- Average to update each lane loop
	
	end)
end


return TrafficController;
