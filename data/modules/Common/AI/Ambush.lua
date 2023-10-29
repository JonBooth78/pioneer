-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local Ship = require 'Ship'
local utils = require 'utils'
local ProximityTest = require 'modules.Common.ProximityTest'

--- send a log message, from the pirates module
--- enables us to quickly turn the debugging on/off
---@param message string
local function logAmbush( message )
	logWarning( message )
end


---@param body Body to get the type string for ( "Ship", "Planet", etc `)
local function GetType( body )
	local types = { "Ship", "Planet", "SpaceStation" }

	for _, t in pairs( types ) do
		if body:isa( t ) then return t end
	end
	return "Body"
end

---@class AmbushShipHandle
---@field manager AmbushManager
local AmbushShipHandle = utils.class( "ambush.shiphandle" )

--- func desc
---@param ship Ship  							The ship lying in ambush
---@param ambush_location Body					The location it will lie in ambush about, normally a planet
---@param attack_fn fun(ship: Ship): boolean	Function to call to evaluate each ship that comes in range to see if we should attack
---TODO attack_fn needs to be something that we can save...
function AmbushShipHandle:Constructor( ship, ambush_location, attack_fn )
	self.ship = ship

	if ambush_location:isa( "SpaceStation" ) then
		ambush_location = ambush_location:GetSystemBody().parent.body
	end

	self.ambush_location = ambush_location
	self.attack_fn = attack_fn
	self.altitude = ship:DistanceTo( ambush_location )

	self.hunting_context = ProximityTest:RegisterTest( ship, 100*1000*1000, 30, "Ship", false )

	self.hunting_context:SetBodyEnter( function( context, ship )
		if self.attack_fn( ship ) then
			logAmbush( "Pirate " .. self.ship:GetLabel() .. " attacking!" )
			self:StartAttack( ship )
		end
	end )

	self:ReturnToAmbush()
end

--- Start attackig the given ship
---@param ship Ship the ship to attack
function AmbushShipHandle:StartAttack( ship )

	logAmbush( self.ship:GetLabel() .. " is now attacking " .. ship:GetLabel() )
	self.ship:AIKill( ship )
	self.target = ship
	self.too_far_context:Cancel()
	self.too_near_context:Cancel()
	self.hunting_context:Cancel()
	self.too_far_context = nil
	self.too_near_context = nil
	self.hunting_context = nil

	-- keep any wingmen in formation, until we get a bit closer
	-- so they all attack at once
	self.wingman_attack_context = ProximityTest:RegisterTest( self.ship, 1000*80, 5, "Ship", true)
	self.wingman_attack_context:SetBodyEnter( function (context, ship )
		if ship == self.target then
			logAmbush( self.ship:GetLabel() .. " is now informing his wingment to attack " .. ship:GetLabel() )

			self.manager.ai_manager.wingmen:NotifyAttackStarted( self.ship, ship )
			context:Cancel()
		end
	end )
end

function AmbushShipHandle:ReturnToAmbush()
	if self.target then
		self.manager.handle_by_target[self.target] = nil
		self.target = nil
	end

	if self.wingman_attack_context then
		self.wingman_attack_context:Cancel()
		self.wingman_attack_context = nil
	end

	---@type number
	local relalt = self.altitude/self.ambush_location:GetPhysicalRadius();

	logAmbush( "Pirate " .. self.ship:GetLabel() .. " flying to ambush desired alt " .. self.altitude .. " gets relative altitude " .. relalt )

	self.ship:AIEnterOrbit( self.ambush_location, relalt )

	self.too_far_context = ProximityTest:RegisterTest( self.ship, self.altitude + 500, 30, GetType( self.ambush_location ), false )
	self.too_near_context = ProximityTest:RegisterTest( self.ship, self.altitude - 500, 30, GetType( self.ambush_location ), false )

	local function OutOfRangeAction( context, body )
		if body == self.ambush_location then self:ReturnToAmbush() end
	end
	self.too_far_context:SetBodyLeave( OutOfRangeAction );
	self.too_near_context:SetBodyEnter( OutOfRangeAction );
end

--- func desc
---@param killer Ship|nil	The ship that killed it
function AmbushShipHandle:OnShipDestroyed( killer )
	if self.too_far_context then self.too_far_context:Cancel() end
	if self.too_near_context then self.too_near_context:Cancel() end
	self.too_far_context = nil
	self.too_near_context = nil	
end

---@class AmbushManager
---
--- You can regsister ships with this manager and it will put them into an AI 
--- cycle where they lay in ambush, roughly where they start until targets
--- come into range and then will attack.
---
---@field handles AmbushShipHandle[] All the handles to ships being managed
local AmbushManager = utils.class( "ambush.manager" )

---@param ai_manager AIManager
function AmbushManager:Constructor( ai_manager )
    if AmbushShipHandle.manager then
        logError( "Attempt to create two ambush managers, only one should ever be required" )
    end
    AmbushShipHandle.manager = self

    self.ai_manager = ai_manager
	---@type table<Ship, AmbushShipHandle>
	self.handle_by_ship = {}
	---@type table<Ship, AmbushShipHandle>
	self.handle_by_target = {}
end

--- 
---@param leader Ship
---@param ally Ship
---@param aggressor Ship`
---@return boolean true if all followers should also engage the aggressor
function AmbushManager:NotifyAllyEngaged( leader, ally, aggressor )
	local h = self.handle_by_ship[leader]
	if h then
		if not h.target then
			h:StartAttack( aggressor )
			return true
		end
	end
	return false
end

--- func desc
---@param ship Ship 	Ship the AI completed for
---@param result string String indicating the reason
---
-- * NONE             - AI completed successfully
-- * GRAV_TOO_HIGH    - AI can not compensate for gravity
-- * REFUSED_PERM     - AI was refused docking permission
-- * ORBIT_IMPOSSIBLE - AI was asked to enter an impossible orbit (orbit is
-- *                    outside target's frame)
-- function AmbushManager:OnAICompleted( ship, result )
-- 	h = self.handle_by_ship[ship]
-- 	if h then
-- 		h:OnAICompleted( ship, result )
-- 	end
-- end

---@param dead_ship Ship	The ship just destroyed
---@param killer Ship|nil	The ship that killed it
function AmbushManager:OnShipDestroyed( dead_ship, killer )
--	logAmbush("Ship Destroyed - " .. dead_ship:GetLabel() )

	h = self.handle_by_target[dead_ship]
	if h then
		h:ReturnToAmbush()
	end

	h = self.handle_by_ship[dead_ship]
	if h then
		h:OnShipDestroyed( killer )
		self.handle_by_ship[dead_ship] = nil
	end
end

--- Register a ship.  This ship will then lie in wait at it's current distance orbiting the ambush location until such time
--- 				  as another ship comes into range that attack_fn returns true for.  Then this ship will attack that one
---					  before returning to lie in wait.
---
---@param ship Ship  							The ship lying in ambush
---@param ambush_location Body					The location it will lie in ambush about, normally a planet
---@param attack_fn fun(ship: Ship): boolean	Function to call to evaluate each ship that comes in range to see if we should attack
function AmbushManager:RegisterShip( ship, ambush_location, attack_fn )
	self.handle_by_ship[ship] = AmbushShipHandle.New( ship, ambush_location, attack_fn )
end

--- Make the dest ship assume the bahaviour of the source ship
--- The source ship now has no behavour..
--- Normally called when the source ship is killed and a wingman
--- assumes leadership and/or the behaviour iteslf rather than
--- following along.
---
---@param source Ship	The ship to copy the behaviour from
---@param dest any		The ship to copy the behaviour to
---@return true boolean If the source ship was found and the copy completed.
function AmbushManager:TakeOverBehaviour( source, dest )
	local h = self.handle_by_ship[source]
	if not h then return false end
	h.ship = dest
	self.handle_by_ship[source] = nil
	self.handle_by_ship[dest] = h
end

return AmbushManager
