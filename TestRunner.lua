-- Used to run the module
-- Will run on both client and server just fine
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local TrafficController = require( ReplicatedStorage:WaitForChild("TrafficController") );

TrafficController.initialize();
