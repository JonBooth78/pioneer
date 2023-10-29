-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

---@type WingmanManager
local wingman_manager = nil

local Ship = require 'Ship'
local utils = require 'utils'
local Event = require 'Event'
local ShipDefs = require 'ShipDef'

local ui = require 'pigui' -- for debug formatting of distances..

--- Do we make it easy for the player to kill wingmen.
--- Handy debug feature.
---@type boolean
local EASY_PLAYER_KILLS = false

local function logWingmen( message )
	logWarning( message )
end


---@class WingmanHandle
--- This allows us to make ships 'wingmen'
--- They will fly in formation with their leader (or attemtp to)
--- They will attack who their leader attacks and then return to formation
--- if a leader is killed, then one of the wingmen gets promoted to leader.
---
--- @field leader WingmanLeader			The leader of this wingman
--- @field wingman Ship					This wingman
--- @field formation_offset Vector3		Offset to fly in from leader
--- @field target Ship|nil				The ship currently being targeted
---@see WingmanManager
local WingmanHandle = utils.class( "wingman.handle" )

--- func desc
---@param leader WingmanLeader			The ship to follow
---@param wingman Ship					The following ship (wingman)
---@param formation_offset Vector3		The relative position to the leader to maintain
function WingmanHandle:Constructor( leader, wingman, formation_offset )
	self.leader = leader
	self.ship = wingman
	self.formation_offset = formation_offset
	-- stay in formation.
	self.ship:AIFormation( self.leader.ship, self.formation_offset )
end

---@class WingmanManager
--- Manages all the wingmen following leaders
---@see WingmanHandle
local WingmanManager = utils.class( "wingman.manager" )

---@class WingmanLeader
---@field ship 		Ship				The ship of the leader
---@field followers	WingmanHandle[]		Handles for all the followers
---@field target	Ship|nil			The target of this leader
local WingmanLeader = utils.class( "wingman.leader" )

function WingmanLeader:Constructor( ship )
	self.ship = ship
	self.followers = {}
end

---@type AIManager
function WingmanManager:Constructor( ai_manager )

    if WingmanManager.ai_manager then
        logError( "Attempt to create a wingman manager twice..." )
    end
    WingmanManager.ai_manager = ai_manager

	---Table indexing from the leader to array of all followers
	---@type table<Ship, WingmanLeader>
	self.leaders = {}

	---Table indexing from a target to the leader that is targetting it
	---@type table<Ship, WingmanLeader>
	self.leader_targets = {}

	---Table indexing from a ship to the handle for that follower
	---@type table<Ship, WingmanHandle>
	self.followers = {}

	---Table indexing from a target to a follower handle
	---@type table<Ship, WingmanHandle>
	self.follower_targets = {}

	Event.Register("onShipDestroyed", function( dead_ship, killer )
		logWingmen( "Ship Destroyed - " .. dead_ship:GetLabel() )

		local leader = self.leaders[dead_ship]
		self.leaders[dead_ship] = nil
		if leader then
			-- the destroyed ship was a leader...
			logWingmen( dead_ship:GetLabel() .. " was a wing leader" )

			if leader.target then
				self.leader_targets[leader.target] = nil
			end

			-- so we need to pick a new leader
			---@type WingmanHandle
			local new_leader = table.remove( leader.followers )
			self.followers[new_leader.ship] = nil

			if new_leader.target then
				self.follower_targets[new_leader.target] = nil
			end

			-- This can be extended for other AI Behaviours...
			-- The new leader can be asked to take over..
			-- Might need to register them with wingman and have a list
			-- this could be good....
			ai_manager:TakeOverBehaviour( dead_ship, new_leader.ship )
			
			if #leader.followers > 0 then

				logWingmen( new_leader.ship:GetLabel() .. " taking over as leader" )

				-- repurpose leader to become the new leader...
				leader.ship = new_leader.ship
				leader.target = new_leader.target

				if leader.target then
					self.leader_targets[leader.target] = leader
				end

				self.leaders[new_leader.ship] = leader
				
				for _, f in pairs(leader.followers) do
					f.leader = leader -- probably redundant, we reused this.
					if killer then 
						if not f.target then
							f.ship:AIKill( killer )
							f.target = killer
						end
					else
						f.ship:AIFormation( new_leader.ship, f.formation_offset )
					end
				end
			end
		end

		local follower = self.followers[dead_ship]
		if follower then
			logWingmen( follower.leader.ship:GetLabel() .. " lost follower " .. dead_ship:GetLabel() )
			-- The dead ship was a follower
			utils.remove_elem( follower.leader.followers, follower )
			if #follower.leader.followers == 0 then

				logWingmen( follower.leader.ship:GetLabel() .. " now has no followers" )

				-- no longer a leader as all followers are dead.
				-- so remove it as a wingman leader, no need to track
				if follower.leader.target then
					self.leader_targets[ follower.leader.target ] = nil
				end
				self.leaders[ follower.leader.ship ] = nil
			end
			self.followers[dead_ship] = nil
		end

		local leader_target = self.leader_targets[dead_ship]
		if leader_target then
			self.leader_targets[dead_ship] = nil
			leader_target.target = nil
		end

		-- now we've processed the dead ship from a leader/follower point of view
		-- pass on the notification (again this could be a set of AI behaviours that register)
		-- this ensures that the call to CopyBehaviour above happens before
		-- any chance of the other behavior to clean up the references to the dead ship
		-- and therefore forget the behaviour of it!
		ai_manager:OnShipDestroyed( dead_ship, killer )

		-- now. does the leader not have a target, if not, check if there is follower
		-- with a target and let the leader know if there is.
		if leader_target then
			if not leader_target.target then
				-- so the leader didn't pick up a new target above
				-- check if any of it's followers are engaged
				for _, f in pairs(leader_target.followers) do
					if f.target then
						ai_manager:NotifyAllyEngaged( leader, f.ship, f.target)
						if leader_target.target then
							break -- we picked one.
						end
					end
				end
			end
		end

		-- now we've done that, we can process the followers.
		local follower_target = self.follower_targets[dead_ship]
		if follower_target then
			follower_target.target = nil;
			self.follower_target[dead_ship] = nil

			if follower_target.leader.target then
				-- now attack whomsoever the leader is attacking...
				follower_target.target = follower_target.leader.targtet
				follower_target.ship:AIKill( follower_target.target )
				self.follower_target[follower_target.target] = follower_target
			end
		end

	end )

	Event.Register( "onShipHit", 
		---@param hit_ship Ship
		---@param aggressor Ship
		function( hit_ship, aggressor ) 
			if nil == aggressor then return end --TODO: how did this happen?
			if EASY_PLAYER_KILLS and aggressor:IsPlayer() then
				-- CHEAT for testing purposes only
				if hit_ship:GetHullPercent() > 0.1 then
					hit_ship:SetHullPercent( 0.1 )
				end
			end
			local h = self.followers[hit_ship]
			---@type WingmanLeader
			local leader = nil
			if h then 
				leader = h.leader
				if h.target ~= aggressor then
					h.target = aggressor
					h.ship:AIKill( aggressor )
					logWingmen( "Pirate wingman " .. h.ship:GetLabel() .. " attacking due to being hit" )
				end
			else
				leader = self.leaders[hit_ship]
			end
			if not leader then return end

			-- TODO: we could, again do with registering a series
			-- of behaviours if we end up with more than just ambush
			-- or we need some kind of 'stack' of behaviours
			-- so we can push a wingman into attacking and then they pop
			-- that behavior of the stack and go back to ambushing/following
			-- this might be smarter.
			if ai_manager:NotifyAllyEngaged( leader.ship, hit_ship, aggressor ) then
				for _, f in pairs( leader.followers ) do
					if not f.target then
						f.target = aggressor
						f.ship:AIKill( aggressor )
					end
				end			
			end
		end 
	)
end

--- func desc
---@param aggressor Ship	The ship that is starting the attack
---@param target Ship		The ship being attacked
function WingmanManager:NotifyAttackStarted( aggressor, target )
	local l = self.leaders[aggressor]
	if not l then return end

	l.target = target
	self.leader_targets[target] = l

	for _, f in pairs( l.followers ) do
		if not f.target then
			f.target = target
			local distance = ui.Format.Distance( f.ship:DistanceTo( target ) )
			logWingmen( "Pirate wingman " .. f.ship:GetLabel() .. " attacking as their leader is - they are " .. distance  )
			f.ship:AIKill( target )
			self.follower_targets[target] = f
		end
	end
end

--- Register a wingman and ships
---@param leader Ship
---@param wingman Ship
---@param formation_offset Vector3
function WingmanManager:RegisterWingman( leader, wingman, formation_offset )
	local leader_h = self.leaders[leader]
	if not leader_h then
		leader_h = WingmanLeader.New(leader)
		self.leaders[leader] = leader_h
	end

	---@type WingmanHandle
	local follower = WingmanHandle.New( leader_h, wingman, formation_offset )
	table.insert( leader_h.followers, 1, follower )

	self.followers[wingman] = follower
end

--- Order the ships given in the array in the order in which they need to be
--- registered such that the leader is first, then the next leader onwards
--- so that they will fly in nice formation.
---
--- example use (given an array of ships to order)
--- table.sort( ships, WingmanManager.WingComparison )
---
---@param a Ship first ship to compare
---@param b Ship second ship to compare
---@return boolean indicating ordering
function WingmanManager.WingComparison( a, b )

	local def_a = ShipDefs[a.shipId]
	local def_b = ShipDefs[b.shipId]

	local accel_a = def_a.linearThrust.FORWARD / a.totalMass
	local accel_b = def_b.linearThrust.FORWARD / b.totalMass

	return accel_a < accel_b
end


return WingmanManager