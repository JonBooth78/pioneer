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

local possiblePirateLocalBodyOptions = function( player )
	local ports = Space.GetBodies(function (body)
--		return body.type == "STARPORT_SURFACE" || body.type == "STARPORT_ORBITAL"
		return body.superType == "STARPORT"
	end)

	local planets = Space.GetBodies(function (body)
--		return body.type == "PLANET_GAS_GIANT" or body.type == "PLANET_TERRESTRIAL" or body.type == "PLANET_TERRESTRIAL"
		return body.superType == "ROCKY_PLANET" or body.superType == "GAS_GIANT"
	end)

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

	logVerbose( "Spawning  " .. cluster_size .. " pirates near " .. local_body:GetLabel() .. "\n" )

	local shipdefs = utils.build_array(utils.filter(function (k,def) return def.tag == 'SHIP'
		and def.hyperdriveClass > 0 and def.roles.pirate end, pairs(ShipDef)))
	if #shipdefs == 0 then return end

	local first_pirate = nil;

	for p = 1, cluster_size, 1 do
		local shipdef = shipdefs[Engine.rand:Integer(1,#shipdefs)]
		local default_drive = Equipment.hyperspace['hyperdrive_'..tostring(shipdef.hyperdriveClass)]
		assert(default_drive)  -- never be nil.

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

--		local ship = Space.SpawnShip(shipdef.id, 8, 12)

		local ship = nil
		if first_pirate ~= nil then
			ship = Space.SpawnShipNear( shipdef.id, first_pirate, 5, 10 )			
		elseif local_body == player then
			ship = Space.SpawnShipNear( shipdef.id, local_body, 10, 50 )
			first_pirate = ship
		elseif local_body.superType == "STARPORT" then
			ship = Space.SpawnShipNear( shipdef.id, local_body, 100, 200 )
			first_pirate = ship
		else
			ship = Space.SpawnShipOrbit( shipdef.id, local_body, 400, 1000 )
			first_pirate = ship
		end

		local label = Ship.MakeRandomLabel()
		ship:SetLabel(label)
		ship:AddEquip(default_drive)
		ship:AddEquip(laserdef)

		if interested then
			if local_body == player then
				logVerbose( "  Pirate " .. label .. " spawned and interested in player\n" )
				ship:AIKill(Game.player)
			else
				logVerbose( "  Pirate " .. label .. " spawned and lurking\n" )
				ship:AIPirate(local_body)
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
		cluster_size =  math.min( cluster_size, max_pirates )
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
local onShipDestroyed = function (ship, body)
	logVerbose("Ship Destroyed - " .. ship:GetLabel() .. "\n" )
end

Event.Register("onShipDestroyed", onShipDestroyed)
--Event.Register("onAICompleted", onAICompleted)


Event.Register("onEnterSystem", onEnterSystem)
