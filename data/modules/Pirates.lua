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

local AIManager = require 'modules.Common.AI.AIManager'

local ui = require 'pigui' -- for debug formatting of distances..

--- Do we label the pirates in a way that it's easy to see in the logging
--- and log all the messages in this file?
---@type boolean
local LOG_PIRATES = true


--- send a log message, from the pirates module
--- enables us to quickly turn the debugging on/off
---@param message string
local function logPirate( message )
	if LOG_PIRATES then	logWarning( message ) end
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

local possiblePirateLocalBodyOptions = function( player )
-- 	local ports = Space.GetBodies(function (body)
-- --		return body.type == "STARPORT_SURFACE" || body.type == "STARPORT_ORBITAL"
-- 		return body.superType == "STARPORT"
-- 	end)

-- 	local planets = Space.GetBodies(function (body)
-- --		return body.type == "PLANET_GAS_GIANT" or body.type == "PLANET_TERRESTRIAL" or body.type == "PLANET_TERRESTRIAL"
-- 		return body.superType == "ROCKY_PLANET" or body.superType == "GAS_GIANT"
-- 	end)

	local ports = Space.GetBodies( "SpaceStation" )
	local planets = Space.GetBodies( "Planet" )
	

	-- the pirates could start near any of the suggested locations...
	local PORT_WEIGHT = 10
	local PLAYER_POS_WEIGHT = 5
	local PLANET_WEIGHT = 1

	local options = {}

--	for j = 1, PLAYER_POS_WEIGHT, 1 do
--		table.insert( options, player )
--	end

	for i, port in ipairs(ports) do
		for j = 1, PORT_WEIGHT, 1 do
			table.insert( options, port )
		end
	end
--	for i, planet in ipairs(planets) do
--		for j = 1, PLANET_WEIGHT, 1 do
--			table.insert( options, planet )
--		end
--	end

	return options

end

-- spawn a cluster of pirates
---@field local_body		Where to spawn nearby
---@field cluster_size		How many pirates to spawn
---@field player			The player
---@field interested		Are the pirates going to try and engage the player? (boolean)

local spawnPirateCluster = function( local_body, cluster_size, player, interested )

	cluster_size = 4

	logPirate( "Spawning  " .. cluster_size .. " pirates near " .. local_body:GetLabel() .. "\n" )

	local shipdefs = utils.build_array(utils.filter(function (k,def) return def.tag == 'SHIP'
		and def.hyperdriveClass > 0 and def.roles.pirate end, pairs(ShipDef)))
	if #shipdefs == 0 then return end

	---@type Ship
	local first_pirate = nil;

	for p = 1, cluster_size, 1 do
		local shipdef = shipdefs[Engine.rand:Integer(1,#shipdefs)]
		local default_drive = Equipment.hyperspace['hyperdrive_'..tostring(shipdef.hyperdriveClass)]
		assert(default_drive)  -- never be nil.

--		local ship = Space.SpawnShip(shipdef.id, 8, 12)
		local label = MakePirateLabel()

		local ship = nil
		if first_pirate then
			ship = Space.SpawnShipNear( shipdef.id, first_pirate, 0.5, 3 )
		elseif local_body == player then
			ship = Space.SpawnShipNear( shipdef.id, local_body, 10, 50 )
		elseif local_body:isa( "SpaceStation" ) then

			if local_body.isGroundStation then
	--            ship = Space.SpawnShipNear( shipdef.id, local_body, 100, 200 )
				---@type Body
				local planet = local_body.path:GetSystemBody().parent.body

				---@type number
				local planet_radius = planet:GetPhysicalRadius()

	--            local planet_radius_km = planet.radius / 1000
				logPirate( "  Pirate " .. label .. " near port " .. local_body.label .. " near planet " .. planet.label .. " planet radius " .. planet_radius )
				local_body = planet
				local min_alt = planet_radius + 80*1000 -- planet_radius * 1.2
				local max_alt = planet_radius + 200*1000 -- planet_radius * 3.5

				ship = Space.SpawnShipOrbit( shipdef.id, local_body, min_alt, max_alt )

	--			ship = Space.SpawnShipOrbit( shipdef.id, local_body, planet_radius * 1.2, planet_radius * 3.5 )
	--            ship = Space.SpawnShipOrbit( shipdef.id, local_body, planet_radius_km + 80, planet_radius_km + 200 )
			else

				-- this will put them in orbit, near the space station...
				-- only problem is they don't know to return to near the space station
				-- just to in orbit at the same altitude(ish) as the space station
				-- TODO: fix?
				ship = Space.SpawnShipNear( shipdef.id, local_body, 80, 150 )
				local_body = local_body.path:GetSystemBody().parent.body				
			end
		else
			---@type number
			local planet_radius = local_body:GetPhysicalRadius()

--			local min_alt = planet_radius + 400*1000 -- planet_radius * 1.2
--			local max_alt = planet_radius + 1000*1000 -- planet_radius * 3.5
			local min_alt = planet_radius * 1.2
			local max_alt = planet_radius * 3.5
			ship = Space.SpawnShipOrbit( shipdef.id, local_body, min_alt, max_alt )
		end

		ship:SetLabel(label)

		-- select a laser. this is naive - it simply chooses at random from
		-- the set of lasers that will fit, but never more than one above the
		-- player's current weapon.
		-- XXX this should use external factors (eg lawlessness) and not be
		-- dependent on the player in any way
		local max_laser_size = shipdef.capacity - default_drive.capabilities.mass
		local laserdefs = utils.build_array(utils.filter(
			function (k,l) return l:IsValidSlot('laser_front') and l.capabilities.mass <= max_laser_size and l.l10n_key:find("PULSECANNON") end,
			pairs(Equipment.laser)
		))
		local laserdef = laserdefs[Engine.rand:Integer(1,#laserdefs)]

		ship:AddEquip(default_drive)
		ship:AddEquip(laserdef)		

		if first_pirate then
			logPirate( "  Pirate " .. label .. " spawned and following " .. first_pirate:GetLabel() )
			---@type Vector3
			local offset = ship:GetPositionRelTo( first_pirate )
			AIManager.wingmen:RegisterWingman( first_pirate, ship, offset )
		else
			first_pirate = ship
			if local_body == player then
				logPirate( "  Pirate " .. label .. " spawned at player and attacking\n" )
				ship:AIKill(Game.player)
			else
				first_pirate = ship
				logPirate( "  Pirate " .. label .. " spawned and lurking\n" )

				AIManager.ambush:RegisterShip( ship, local_body, function( ship )
					return ship:IsPlayer()
				end )
			end
		end
	end
end

local onEnterSystem = function (player)
	if not player:IsPlayer() then return end

	local lawlessness = Game.system.lawlessness

	-- XXX number should be some combination of population, lawlessness,
	-- proximity to shipping lanes, etc
--	local max_pirates = 6
--	while max_pirates > 0 and Engine.rand:Number(1) < lawlessness do

	start_body_options = possiblePirateLocalBodyOptions( player )

	-- TODO: trim this size based on lawlessness?
	cluster_size_options = { 1, 1, 1, 1, 2, 2, 3 }

	local max_pirates = 1 --Engine.rand:Number(8)
	while max_pirates > 0 do

		local cluster_size = cluster_size_options[Engine.rand:Integer(1,#cluster_size_options)]
		cluster_size = math.min( cluster_size, max_pirates )
		max_pirates = max_pirates-cluster_size

		-- pirates know how big cargo hold the ship model has
		local playerCargoCapacity = ShipDef[player.shipId].capacity

		-- Pirate attack probability proportional to how fully loaded cargo hold is.
--		local discount = 2 		-- discount on 2t for small ships.
--		local probabilityPirateIsInterested = math.floor(player.usedCargo - discount) / math.max(1,  playerCargoCapacity - discount)
		local probabilityPirateIsInterested = 1

		local pirates_interested = (Engine.rand:Number(1) <= probabilityPirateIsInterested)

		local local_body = start_body_options[Engine.rand:Integer(1,#start_body_options)]

		spawnPirateCluster( local_body, cluster_size, player, pirates_interested )

	end
end

Event.Register("onEnterSystem", onEnterSystem)