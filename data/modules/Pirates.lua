-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local Engine = require 'Engine'
local Game = require 'Game'
local Space = require 'Space'
local Event = require 'Event'
local Equipment = require 'Equipment'
local ShipDef = require 'ShipDef'
local Ship = require 'Ship'
local utils = require 'utils'
local ProximityTest = require 'modules.Common.ProximityTest'
local ShipOutfitter = require 'modules.Common.ShipOutfitter'

local AIManager = require 'modules.Common.AI.AIManager'

local Difficulty = require 'modules.Common.Difficulty'


local ui = require 'pigui' -- for debug formatting of distances..

--- Do we label the pirates in a way that it's easy to see in the logging
--- and log all the messages in this file?
---@type boolean
local LOG_PIRATES = true


--- send a log message, from the pirates module
--- enables us to quickly turn the debugging on/off
---@param message string
local function logPirate( message )
	if LOG_PIRATES then	logWarning( "Pirate: " .. message ) end
end

---@type number
local pirate_num = 0

---@return string
local function MakePirateLabel()
	if LOG_PIRATES then
		pirate_num = pirate_num + 1
		return "PIRATE-" .. pirate_num	
	else
		return Ship.MakeRandomLabel()
	end
end

local function possiblePirateLocalBodyOptions( player )
	local ports = Space.GetBodies( "SpaceStation" )
	local planets = Space.GetBodies( "Planet" )
	

	-- the pirates could start near any of the suggested locations...
	local PORT_WEIGHT = 10
	local PLAYER_POS_WEIGHT = 5
	local PLANET_WEIGHT = 1

	local options = {}

	for j = 1, PLAYER_POS_WEIGHT, 1 do
		table.insert( options, player )
	end

	for i, port in ipairs(ports) do
		for j = 1, PORT_WEIGHT, 1 do
			table.insert( options, port )
		end
	end
	for i, planet in ipairs(planets) do
		for j = 1, PLANET_WEIGHT, 1 do
			table.insert( options, planet )
		end
	end

	return options

end


---@param ship Ship the ship to evaluate if we want to attack
---@return boolean if we should attack
local function pirate_attack_evaluation( ship )
	--- TODO: pirates could also attack merchants...
	if not ship:IsPlayer() then return false end

	-- pirates are looking for high value cargo:
	local cargo_value_ratio = ShipOutfitter.ShipsMostValuableCargo( ship ) / ShipOutfitter.most_valuable_commodity
	local pirateInterestedModifier = 0.5 + cargo_value_ratio
	local pirates_interested = Difficulty:yes_no_for_category( "pirateHostility", pirateInterestedModifier )

	if pirates_interested then
		logPirate( "Decided the pirates are not interested in attacking the player" )
	else
		logPirate( "Decided the pirates are intersested in attacking the player" )
	end

	return pirates_interested
end

AIManager.ambush:RegisterAttackEvaluationFunction( "pirate_attack_fn", pirate_attack_evaluation )

-- spawn a cluster of pirates
---@field local_body		Where to spawn nearby
---@field cluster_size		How many pirates to spawn
---@field player			The player
---@field interested		Are the pirates going to try and engage the player? (boolean)
local function spawnPirateCluster( local_body, cluster_size, player )

	logPirate( "Spawning  " .. cluster_size .. " pirates near " .. local_body:GetLabel() .. "\n" )

	---@type Ship
	local first_pirate = nil;

	--- type MocShip[]
	local cluster = {}

	for p = 1, cluster_size, 1 do
		local shipdef = ShipOutfitter.PickShipDef( "SHIP", "pirate" )

		local label = MakePirateLabel()

		local ship = ShipOutfitter.MocShip.New( label, shipdef )

		ShipOutfitter.EquipNewShip( shipdef, ship, "pirate" )

		table.insert( cluster, ship)
	end

	-- this sorting should hopefully ensure the wing can remain cohesive.
	table.sort( cluster, AIManager.wingmen.WingComparison )
	
	first_pirate = nil
	for _, blueprint in pairs( cluster ) do
		local label = blueprint:GetLabel()

		local ship = nil
		if first_pirate then
			ship = Space.SpawnShipNear( blueprint.shipdef.id, first_pirate, 0.5, 3 )
		elseif local_body == player then
			ship = Space.SpawnShipNear( blueprint.shipdef.id, local_body, 10, 50 )
		elseif local_body:isa( "SpaceStation" ) then

			if local_body.isGroundStation then
				---@type Body
				local planet = local_body.path:GetSystemBody().parent.body

				---@type number
				local planet_radius = planet:GetPhysicalRadius()

				logPirate( "  Pirate " .. label .. " near port " .. local_body.label .. " near planet " .. planet.label .. " planet radius " .. planet_radius )
				local_body = planet
				local min_alt = planet_radius + 80*1000 -- planet_radius * 1.2
				local max_alt = planet_radius + 200*1000 -- planet_radius * 3.5

				ship = Space.SpawnShipOrbit( blueprint.shipdef.id, local_body, min_alt, max_alt )

			else

				-- this will put them in orbit, near the space station...
				-- only problem is they don't know to return to near the space station
				-- just to in orbit at the same altitude(ish) as the space station
				-- TODO: fix?
				ship = Space.SpawnShipNear( blueprint.shipdef.id, local_body, 80, 150 )
				local_body = local_body.path:GetSystemBody().parent.body				
			end
		else
			---@type number
			local planet_radius = local_body:GetPhysicalRadius()

			local min_alt = planet_radius * 1.2
			local max_alt = planet_radius * 3.5
			ship = Space.SpawnShipOrbit( blueprint.shipdef.id, local_body, min_alt, max_alt )
		end

		ship:SetLabel(label)

		blueprint:EquipShip(ship)

		if first_pirate then
			logPirate( "  Pirate " .. label .. " spawned and following " .. first_pirate:GetLabel() .. " " .. ship.totalMass )
			---@type Vector3
			local offset = ship:GetPositionRelTo( first_pirate )
			AIManager.wingmen:RegisterWingman( first_pirate, ship, offset )
		else
			first_pirate = ship
			if local_body == player then
				-- too tempting to evaluate if we should attack, they're right there!
				-- so no need to check pirate_attack_evaluation
				logPirate( "  Pirate " .. label .. " spawned at player and attacking\n" )
				ship:AIKill(Game.player)
			else
				first_pirate = ship
				logPirate( "  Pirate " .. label .. " spawned and lurking " .. ship.totalMass )

				AIManager.ambush:RegisterShip( ship, local_body, "pirate_attack_fn" )
			end
		end
	end
end

local function onEnterSystem( player )
	if not player:IsPlayer() then return end

	local lawlessness = Game.system.lawlessness

	local start_body_options = possiblePirateLocalBodyOptions( player )

	local cluster_size_options = { 1, 1, 1, 1, 2, 2, 2, 3, 3 }

	local max_pirates = Difficulty:random_normal_for_category( "numPirates", lawlessness, 0.2, 1 ) * 8;
	
	logPirate( "Decided to spawn " .. max_pirates .. " with lawlessness " .. lawlessness )

	local max_prirate =  math.floor( max_pirates )

	while max_pirates > 0 do

		local cluster_size = cluster_size_options[Engine.rand:Integer(1,#cluster_size_options)]
		cluster_size = math.min( cluster_size, max_pirates )
		max_pirates = max_pirates-cluster_size

		local local_body = start_body_options[Engine.rand:Integer(1,#start_body_options)]

		spawnPirateCluster( local_body, cluster_size, player )

	end
end

Event.Register("onEnterSystem", onEnterSystem)
