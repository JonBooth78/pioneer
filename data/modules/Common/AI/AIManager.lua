-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local utils = require 'utils'

---@class BehaviorManager
---This class must be implemented for specific behaviours
---It allows them to work with the wingman system and
---have events called in the correct order.
local BehaviorManager = utils.class( "AI.behavior-manager" )

local AmbushManager = require 'modules.Common.AI.Ambush'
local WingmanManager = require 'modules.Common.AI.Wingmen'

--- Typically used when a leader of a wing is killed and then we
--- one follower will take over their base behavior (rather than following)
--- and if there are more followers, that one that took over becomes the new
--- leader
---@param source Ship	The ship to copy the behaviour from
---@param dest any		The ship to copy the behaviour to
---@return true boolean If the source ship was found and the copy completed.
function BehaviorManager:TakeOverBehaviour( source, dest ) 
    logError( "This needs to be implemented by the overriding class" )
    return false
end

--- Notification of when a ship is destroyed.
--- BehaviorManager does not iteslf subscribe to these events
--- as there is some explicit ordering needed to ensure wingmen work correclty
---@param dead_ship Ship
---@param killer Ship
function BehaviorManager:OnShipDestroyed( dead_ship, killer ) 
    logError( "This needs to be implemented by the overriding class" )
end

--- A notification for a leader following a set behavior that one of his wingmen/allies
--- has engaged in a fight.
---@param ship Ship     The leader of the wing (so the one that may be registered with a behavior)
---@param ally Ship     The ally what has engaged in battle
---@param target Ship   The target that the ally is now engaged with
function BehaviorManager:NotifyAllyEngaged( ship, ally, target ) 
    logError( "This needs to be implemented by the overriding class" )
end

---@class AIManager
---
---@field wingmen   WingmanManager
---@field ambush    AmbushManager
---@field behaviors BehaviorManager[]
local AIManager = utils.class( "AI.manager", BehaviorManager )

function AIManager:Constructor()
    self.wingmen = WingmanManager.New( self )
    self.ambush = AmbushManager.New( self )
    self.behaviors = { self.ambush }
end

--- Typically used when a leader of a wing is killed and then we
--- one follower will take over their base behavior (rather than following)
--- and if there are more followers, that one that took over becomes the new
--- leader
---@param source Ship	The ship to copy the behaviour from
---@param dest any		The ship to copy the behaviour to
---@return true boolean If the source ship was found and the copy completed.
function AIManager:TakeOverBehaviour( source, dest ) 
    for _, b  in pairs( self.behaviors ) do
        if b:TakeOverBehaviour( source, dest ) then
            return true
        end
    end
    return false
end

--- Notification of when a ship is destroyed.
--- as there is some explicit ordering needed to ensure wingmen work correclty
---@param dead_ship Ship
---@param killer Ship
function AIManager:OnShipDestroyed( dead_ship, killer ) 
    --- NOTE the wingman manager listens for this message and forwards it here for other behaviours
    --- to respond to
    for _, b  in pairs( self.behaviors ) do
        b:OnShipDestroyed( dead_ship, killer )
    end
end

--- A notification for a leader following a set behavior that one of his wingmen/allies
--- has engaged in a fight.
---@param ship Ship     The leader of the wing (so the one that may be registered with a behavior)
---@param ally Ship     The ally what has engaged in battle
---@param target Ship   The target that the ally is now engaged with
function AIManager:NotifyAllyEngaged( ship, ally, target ) 
    for _, b  in pairs( self.behaviors ) do
        b:NotifyAllyEngaged( ship, ally, target )
    end
end

---@type AIManager
local ai_manager = AIManager.New()

return ai_manager
