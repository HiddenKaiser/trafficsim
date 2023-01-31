--[[
> TrafficController.lua
	>> Car.lua
	>> Lane.lua
	>> Metrics.lua*

> TrafficController.rbxm
> README.md
--]]

local Metrics;


--// Counter
local Counter = {};
Counter.__index = Counter;

type Counter = number | Vector3;

function Counter.new(name: string?)
	local self = {
		name = name or "Counter";
		amount = 0;
	}

	setmetatable(self, Counter);

	return self;
end

function Counter:Add()
	self.amount += 1;
end

function Counter:GetAmount()
	return self.amount;
end

function Counter:Reset()
	self.amount = 0;
end

function Counter:Display()
	print((self.name..":"), self:GetAmount());
end



--// Average
local AverageCounter = {};
AverageCounter.__index = AverageCounter;

type AveragePossible = number | Vector3;

function AverageCounter.new(name: string?, doRound: boolean?, start: AveragePossible?)
	local self = {
		name = name or "Average";
		start = start;
		doRound = doRound;
		
		amount = start or 0;
		sum = 0;
	}
	
	setmetatable(self, AverageCounter);
	
	return self;
end

function AverageCounter:Add(v: AveragePossible, amount: number?)
	self.sum += v;
	self.amount += (amount or 1);
end

function AverageCounter:Reset()
	self.sum = 0;
	self.amount = 0;
end

function AverageCounter:ToAverage() : AveragePossible
	return self.sum / self.amount;
end

function AverageCounter:Display()
	if self.doRound then
		return print((self.name..":"), math.floor(self:ToAverage()*100)/100);
	else
		return print((self.name..":"), self:ToAverage());
	end
	
end



Metrics = {
	Counter = Counter;
	AverageCounter = AverageCounter;
}

return Metrics;
