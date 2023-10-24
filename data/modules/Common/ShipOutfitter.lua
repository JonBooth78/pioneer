-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local Equipment = require 'Equipment'
local EquipType = require 'EquipType'

--- TODO: make this meta
---@class ShipDef
---@field id string
---@field name string The name ofthe ship type
---@field shipClass string
---@field manufacturer string
---@field cockpitName string
---@field tag string Based in <Constants.ShipTypeTag> One of "NONE", "SHIP", "STATIC_SHIP" or "MISSILE"
---@field angularThrust number The amount of angular thrust this ship can achieve. This is the value responsible for the rate that the ship can turn at.
---@field capacity integer The maximum space available for cargo and equipment, in tonnes
---@field hullMass integer  The total mass of the ship's hull, independent of any equipment or cargo inside it, in tonnes. This is the value used when calculating hyperjump ranges and hull damage.
---@field fuelTankMass integer
---@field basePrice number The base price of the ship. This typically receives some adjustment before being used as a buy or sell price (eg based on supply or demand)
---@field minCrew integer Minimum number of crew required to launch.
---@field maxCrew integer Maximum number of crew the ship can carry.
---@field hyperdriveClass integer An integer representing the power of the hyperdrive usually installed on those ships. If zero, it means the ship usually isn't equipped with one, although this does not necessarily mean one cannot be installed.
---@field effectiveExhaustVelocity number Ship thruster efficiency as the effective exhaust velocity in m/s. See http://en.wikipedia.org/wiki/Specific_impulse for an explanation of this value.
---@field thrusterFuelUse number
---@field frontCrossSec number
---@field sideCrossSec number
---@field topCrossSec number
---@field atmosphericPressureLimit number
---@field linearThrust table{ string: number } Table keyed on <Constants.ShipTypeThruster> ("REVERSE", "FORWARD", "UP", "DOWN", "LEFT", "RIGHT"), containing linear thrust of that thruster in newtons
---@field linAccelerationCap table{ string: number } Table keyed on <Constants.ShipTypeThruster> ("REVERSE", "FORWARD", "UP", "DOWN", "LEFT", "RIGHT"), containing containing acceleration cap of that thruster direction in m/s/s
---@field equipSlotCapacity  table{ string, integer } keyed on <Constants.EquipSlot>, containing maximum number of items that can be held in that slot (ignoring mass) "missile", "laser_rear", "cargo", "engine", "atmo_shield", "sensor", "scoop", "shield", "laser_front", "cabin"
---@field roles string[] one of "mercenary", "merchant", "pirate", "courier", 
local ShipDef = {}



---@type ShipDef[]
local ShipDefs = require 'ShipDef'
local Ship = require 'Ship'
local utils = require 'utils'
local Engine = require 'Engine'

---@class QuadraticBezierInterpolation
---
local QuadraticBezierInterpolation = utils.class( "QuadraticBezier")
function QuadraticBezierInterpolation:Constructor( x0, y0, x1, y1, x2, y2)
    -- first end
    self.x0 = x0
    self.y0 = y0
    -- control point
    self.x1 = x1
    self.y1 = y1
    -- second end
    self.x2 = x2
    self.y2 = y2

    self.ix0 = x0-x1
    self.iy0 = y0-y1
    self.ix1 = x2-x1
    self.iy1 = y2-y1
end

function QuadraticBezierInterpolation:GetForT( t )
    local tsq = t*t
    local one_minus_t_sq = (1-t)*(1-t)

    local x = self.x0 + one_minus_t_sq * self.ix0 + tsq * self.ix1
    local y = self.y0 + one_minus_t_sq * self.iy0 + tsq * self.iy1

    return x, y
end

local function map_for_difficulty( d, t )
      return (1-t)*(1-t)*(1-d) + t*t*d
end

---@class MocShip Is a moc of the ship interface that allow us
--- to add and build up data, so we can test the interface but also
--- calculate the value of various different random chance levels
--- as we can use that value to work out relative 'difficulty' If
--- desired.
local MocShip = utils.class( "ShipOutfitter.MocShip")

---@param label string Ship label
---@param shipdef ShipDef the ship definition
function MocShip:Constructor( label, shipdef )
--    self.shipdef = shipdef
    self.shipId = shipdef.id
    self.label = label
    --- @type table<string, EquipType.EquipType[]>
    self.slots = {}
end

---@param slot string The slot to get the equipment array for
---@return EquipType.EquipType[] Array of equipment installed in that slot
function MocShip:GetEquip(slot)
    return self.slots[slot]
end

---@return string
function MocShip:GetLabel()
    return self.label
end

---@param equip EquipType.EquipType
function MocShip:AddEquip( equip, count, slot )

    if not count then count = 1 end
    if not slot then slot = equip.slot end

    if self.slots[slot] then
        table.insert(self.slots[slot], equip)
    else
        self.slots[slot] = { equip }
    end
end

local ShipOutfitter = {}

-- local function dumpAllKeys( field )
--     local map = {}    
--     for _, def in pairs( ShipDefs ) do
--         for k, _ in pairs( def[field] ) do
--             map[k] = true
--         end
--     end

--     logWarning( "Dump of all " .. field )
--     for k, _ in pairs( map ) do
--         logWarning( "\t"..k )
--     end
--     logWarning( "End" )
-- end

-- local function dumpAllValues( field )
--     local map = {}    
--     for _, def in pairs( ShipDefs ) do
--         for _, v in pairs( def[field] ) do
--             map[v] = true 
--         end
--     end

--     logWarning( "Dump of all " .. field )
--     for k, _ in pairs( map ) do
--         logWarning( "\t"..k )
--     end
--     logWarning( "End" )
-- end

-- local dumped = false

--- Lookup table for different combination of tag and roles
---@type table{ string : ShipDef[] }
local role_defs = {}

---@return number from 0->1. The higher the number, the better the result
--- So this function can be modified from a linear chance to something else
--- to indicate difficulty
function ShipOutfitter.defaultGetChance()
    return Engine.rand:Number(1.0)
end

local dumped_all_ship_values = false

---@param tag string   The tag to filter by <Constants.ShipTypeTag> One of "NONE", "SHIP", "STATIC_SHIP" or "MISSILE"
---@param role string  The role that the ship is being picked for, can be "pirate", ...
---@return ShipDef|nil A randomized shipdef that meets the parameters passed in, or nil if nothing meets
function ShipOutfitter.PickShipDef(tag, role, getChance)    
    ---getChance is a function to return a number from 0->1. The higher the number, the better the result.
    if not getChance then
        getChance = ShipOutfitter.defaultGetChance
    end

    -- if not dumped then
    --     dumped = true
    --     dumpAllKeys( "roles" )
    --     dumpAllKeys( "equipSlotCapacity" )
    -- end

    local key = tag .. "-" .. role

    local shipdefs = role_defs[key]

    if not shipdefs then
        shipdefs = utils.build_array(utils.filter(function (k,def) return def.tag == tag
            and def.hyperdriveClass > 0 and def.roles[role] end, pairs(ShipDefs)))
        role_defs[key] = shipdefs
    end
	if #shipdefs == 0 then return nil end

    table.sort(shipdefs,function(a,b)
        return a.basePrice < b.basePrice
    end)

    if not  dumped_all_ship_values then
        dumped_all_ship_values = true
        for _, sd in pairs( shipdefs ) do
            logWarning( "Ship ".. sd.name .. " costs " .. sd.basePrice )
        end
    end

    local index = math.ceil(getChance()*#shipdefs*0.99999999999)
    ---@type ShipDef
    local shipdef = shipdefs[index]

    logWarning( "picked: " .. shipdef.name )
    return shipdef
end



---@class EquipmentTypeScheme A scheme (blueprint) for each equipment type that can be outfit.
---@field slot string               The slot this equipment blueprint is for
---@field chance number             How likely is this equipment to be present - anything greater than 1 is garunteed so long as there is space/funds, the larger the number the earlier it gets provisioned.
---@field repeatChance number       How much to modify the likelihood of the last pass of getting one to the next pass.
---@field totalWeight number|nil    The total weight of all the valid types
---@field types { "type": EquipType.EquipType, "weight": number )[]    The equipment in question and how likely, if this slot is chosen, for this equipment to be chosen - sorted in weakest first order.
local EquipmentTypeScheme = utils.class( "ShipOutfitter.EquipmentTypeScheme" )

function EquipmentTypeScheme:Constructor( specs )
    -- deep copy
    for k,v in pairs( specs ) do
        if k == 'types' then
            self.types = {}
            for _, t in pairs ( v ) do
                table.insert( self.types, { type=t.type, weight = t.weight })
            end
        else
            self[k] = v
        end
    end
end

function EquipmentTypeScheme:Prepare( mass_remaining )
    self.totalWeight = 0
    for _, e in pairs( self.types ) do
        if e.type.capabilities.mass <= mass_remaining  then
            self.totalWeight = self.totalWeight + e.weight;
        else
            e.weight = 0 -- can't be picked.
        end
    end
    if self.totalWeight == 0 then self.chance = 0 end
end

---@param   quality number From 0->1 indicating the quaility of the equipment to pick.
---@return  nil|EquipType.EquipType Either one was picked or not.
function EquipmentTypeScheme:Select( quality )
    if self.totalWeight == 0 then
        return nil 
    end
    quality = quality*self.totalWeight
    for _, e in pairs( self.types ) do
        if e.weight >= quality then
            self.chance = self.chance * self.repeatChance
            return e.type
        end
        quality = quality-e.weight
    end
    return nil
end

--see utils.normWeights etc.

---@class EquipmentScheme
---
--- This sceme defines a scheme or blueprint, if you like
--- for what equipment may be generated for a given ship.
---@field hyperdrive nil|number If nil, the default drive for the ship; if specified as a number the size of the drive, where zero is none and if n > 10 it is a military drive of n-10 size.
---@field equip EquipmentTypeScheme[]
---@field sorted boolean    Are the EquipmentTypeSchemes sorted
local EquipmentScheme = utils.class( "shipoutfitter.EquipmentScheme")

function EquipmentScheme:Constructor(type_scheme_specs)
    self.equip = {}
    for _,v in pairs( type_scheme_specs ) do
        table.insert(self.equip, EquipmentTypeScheme.New(v) )
    end
    self:Prepare()
end

function EquipmentScheme:Prepare()
    if not self.sorted then
        table.sort( self.equip, function( a, b )
            return a.chance > b.chance
        end );
        self.sorted = true
    end
    -- for _, slot in pairs( self.equip ) do
    --     slot:Prepare()
    -- end
end

---@param slot string The slot to return
---@return EquipmentTypeScheme|nil 
function EquipmentScheme:GetSlot( slot )
    for _, slot in pairs( self.equip ) do
        if slot.slot == slot then return slot end
    end
    return nil
end

---@param equip     EquipType.EquipType   The equipment type to make mandatory
---@param slot      string|nil            The slot to make it mandatory for, can be nil and then assumes the equipment can only be assigned to one slot
function EquipmentScheme:MakeEquipMandatory( equip, slot )
    if not slot then
        slot = equip.slot
    end
    local scheme = self:GetSlot( slot )

    if scheme.chance ~= 1 then
         scheme.chance = 1
         self.sorted = false
    end
    scheme.totalWeight = 1
    scheme.types = { type = equip, weight = 1 }
end

---@param slot string     The slot to make it mandatory, leaing the weights as per the blueprint
function EquipmentScheme:MakeSlotMandatory( slot )
    local scheme = self:GetSlot( slot )

    if scheme.chance ~= 1 then
         scheme.chance = 1
         self.sorted = false
    end
end

local AllSlots = {
    "missile", "atmo_shield", "ecm", "radar", "cabin", "shield", "laser_cooler", 
    "cargo_life_support", "autopilot", "target_scanner", "scoop", "hypercloud",
    "hull_autorepair", "hypercloud", "energy_booster", "thruster", "trade_computer",
    "sensor", "laser_front", "laser_rear", "engine"
}


local PirateEquipmentStats =
{
    {
        slot = "missile",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.missile_unguided, weight = 50 },
            { type = Equipment.misc.missile_guided, weight = 10 },
            { type = Equipment.misc.missile_smart, weight = 5 },
            { type = Equipment.misc.missile_naval, weight = 1 },            
        }
    },
    {
        slot = "atmo_shield",
        chance = 0.2,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.atmospheric_shielding , weight = 50 },
            { type = Equipment.misc.heavy_atmospheric_shielding , weight = 10 }
        }
    },
    {
        slot = "ecm",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.ecm_basic  , weight = 50 },
            { type = Equipment.misc.ecm_advanced  , weight = 10 }
        }
    },
    {
        slot = "radar",
        chance = 0.9,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.radar  , weight = 1 }
        }
    },
    {
        slot = "cabin",
        chance = 0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.cabin, weight = 50 },
            { type = Equipment.misc.cabin_occupied, weight = 10 }
        }
    },
    {
        slot = "shield",
        chance = 0.9,
        repeatChance = 0.5,
        types = {
            { type = Equipment.misc.shield_generator, weight = 1 }
        }
    },
    {
        slot = "laser_cooler",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.laser_cooling_booster, weight = 1 }
        }
    },
    {
        slot = "cargo_life_support",
        chance = 0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.cargo_life_support, weight = 1 }
        }
    },
    {
        slot = "autopilot",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.autopilot , weight = 1 }
        }
    },
    {
        slot = "target_scanner",
        chance = 0.75,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.target_scanner, weight = 50 },
            { type = Equipment.misc.advanced_target_scanner, weight = 10 }
        }
    },
    {
        slot = "scoop",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.fuel_scoop, weight = 50 },
            { type = Equipment.misc.cargo_scoop, weight = 50 },
            { type = Equipment.misc.multi_scoop, weight = 10 }
        }
    },
    {
        slot = "hypercloud",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.hypercloud_analyzer, weight = 1 }
        }
    },
    {
        slot = "energy_booster",
        chance = 0.5,
        repeatChance = 0.5,
        types = {
            { type = Equipment.misc.shield_energy_booster, weight = 1 }
        }
    },
    {
        slot = "hull_autorepair",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.hull_autorepair, weight = 1 }
        }
    },
    {
        slot = "thruster",
        chance = 1,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.thrusters_basic, weight = 50 },
            { type = Equipment.misc.thrusters_medium, weight = 50 },
            { type = Equipment.misc.thrusters_best, weight = 10 }
        }
    },
    {
        slot = "trade_computer",
        chance = 0.0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.trade_computer, weight = 10 }
        }
    },
    {
        slot = "sensor",
        chance = 0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.planetscanner, weight = 50 },
            { type = Equipment.misc.planetscanner_good, weight = 50 },
            { type = Equipment.misc.orbitscanner, weight = 50 },
            { type = Equipment.misc.orbitscanner_good, weight = 50 }
        }
    },
    {
        slot = "laser_front",
        chance = 1,
        repeatChance = 0,
        types = {
            { type = Equipment.laser.pulsecannon_1mw, weight = 100 },
            { type = Equipment.laser.pulsecannon_dual_1mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_2mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_rapid_2mw, weight = 50 },
            { type = Equipment.laser.beamlaser_1mw, weight = 40 },
            { type = Equipment.laser.beamlaser_dual_1mw, weight = 20 },
            { type = Equipment.laser.beamlaser_2mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_4mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_10mw, weight = 5 },
            { type = Equipment.laser.pulsecannon_20mw, weight = 2 },
            { type = Equipment.laser.miningcannon_5mw, weight = 0 },
            { type = Equipment.laser.miningcannon_17mw, weight = 0 },
            { type = Equipment.laser.small_plasma_accelerator, weight = 1 },
            { type = Equipment.laser.large_plasma_accelerator, weight = 0.5 }
        }
    },
    {
        slot = "laser_rear",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.laser.pulsecannon_1mw, weight = 100 },
            { type = Equipment.laser.pulsecannon_dual_1mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_2mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_rapid_2mw, weight = 50 },
            { type = Equipment.laser.beamlaser_1mw, weight = 40 },
            { type = Equipment.laser.beamlaser_dual_1mw, weight = 20 },
            { type = Equipment.laser.beamlaser_2mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_4mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_10mw, weight = 5 },
            { type = Equipment.laser.pulsecannon_20mw, weight = 2 },
            { type = Equipment.laser.miningcannon_5mw, weight = 0 },
            { type = Equipment.laser.miningcannon_17mw, weight = 0 },
            { type = Equipment.laser.small_plasma_accelerator, weight = 1 },
            { type = Equipment.laser.large_plasma_accelerator, weight = 0.5 }
        }
    },
 
}

local MercenaryEquipmentStats =
{
    {
        slot = "missile",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.missile_unguided, weight = 50 },
            { type = Equipment.misc.missile_guided, weight = 10 },
            { type = Equipment.misc.missile_smart, weight = 5 },
            { type = Equipment.misc.missile_naval, weight = 1 },            
        }
    },
    {
        slot = "atmo_shield",
        chance = 0.3,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.atmospheric_shielding , weight = 50 },
            { type = Equipment.misc.heavy_atmospheric_shielding , weight = 10 }
        }
    },
    {
        slot = "ecm",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.ecm_basic  , weight = 50 },
            { type = Equipment.misc.ecm_advanced  , weight = 10 }
        }
    },
    {
        slot = "radar",
        chance = 0.9,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.radar  , weight = 1 }
        }
    },
    {
        slot = "cabin",
        chance = 0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.cabin, weight = 50 },
            { type = Equipment.misc.cabin_occupied, weight = 10 }
        }
    },
    {
        slot = "shield",
        chance = 0.75,
        repeatChance = 0.75,
        types = {
            { type = Equipment.misc.shield_generator, weight = 1 }
        }
    },
    {
        slot = "laser_cooler",
        chance = 0.3,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.laser_cooling_booster, weight = 1 }
        }
    },
    {
        slot = "cargo_life_support",
        chance = 0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.cargo_life_support, weight = 1 }
        }
    },
    {
        slot = "autopilot",
        chance = 0.5,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.autopilot , weight = 1 }
        }
    },
    {
        slot = "target_scanner",
        chance = 0.75,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.target_scanner, weight = 50 },
            { type = Equipment.misc.advanced_target_scanner, weight = 10 }
        }
    },
    {
        slot = "scoop",
        chance = 0.2,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.fuel_scoop, weight = 50 },
            { type = Equipment.misc.cargo_scoop, weight = 50 },
            { type = Equipment.misc.multi_scoop, weight = 10 }
        }
    },
    {
        slot = "hypercloud",
        chance = 0.3,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.hypercloud_analyzer, weight = 1 }
        }
    },
    {
        slot = "energy_booster",
        chance = 0.25,
        repeatChance = 0.75,
        types = {
            { type = Equipment.misc.shield_energy_booster, weight = 1 }
        }
    },
    {
        slot = "hull_autorepair",
        chance = 0.3,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.hull_autorepair, weight = 1 }
        }
    },
    {
        slot = "thruster",
        chance = 0.6,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.thrusters_basic, weight = 50 },
            { type = Equipment.misc.thrusters_medium, weight = 50 },
            { type = Equipment.misc.thrusters_best, weight = 10 }
        }
    },
    {
        slot = "trade_computer",
        chance = 0.0,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.trade_computer, weight = 10 }
        }
    },
    {
        slot = "sensor",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.misc.planetscanner, weight = 50 },
            { type = Equipment.misc.planetscanner_good, weight = 50 },
            { type = Equipment.misc.orbitscanner, weight = 50 },
            { type = Equipment.misc.orbitscanner_good, weight = 50 }
        }
    },
    {
        slot = "laser_front",
        chance = 1,
        repeatChance = 0,
        types = {
            { type = Equipment.laser.pulsecannon_1mw, weight = 100 },
            { type = Equipment.laser.pulsecannon_dual_1mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_2mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_rapid_2mw, weight = 50 },
            { type = Equipment.laser.beamlaser_1mw, weight = 40 },
            { type = Equipment.laser.beamlaser_dual_1mw, weight = 20 },
            { type = Equipment.laser.beamlaser_2mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_4mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_10mw, weight = 5 },
            { type = Equipment.laser.pulsecannon_20mw, weight = 2 },
            { type = Equipment.laser.miningcannon_5mw, weight = 0 },
            { type = Equipment.laser.miningcannon_17mw, weight = 0 },
            { type = Equipment.laser.small_plasma_accelerator, weight = 1 },
            { type = Equipment.laser.large_plasma_accelerator, weight = 0.5 }
        }
    },
    {
        slot = "laser_rear",
        chance = 0.1,
        repeatChance = 0,
        types = {
            { type = Equipment.laser.pulsecannon_1mw, weight = 100 },
            { type = Equipment.laser.pulsecannon_dual_1mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_2mw, weight = 90 },
            { type = Equipment.laser.pulsecannon_rapid_2mw, weight = 50 },
            { type = Equipment.laser.beamlaser_1mw, weight = 40 },
            { type = Equipment.laser.beamlaser_dual_1mw, weight = 20 },
            { type = Equipment.laser.beamlaser_2mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_4mw, weight = 10 },
            { type = Equipment.laser.pulsecannon_10mw, weight = 5 },
            { type = Equipment.laser.pulsecannon_20mw, weight = 2 },
            { type = Equipment.laser.miningcannon_5mw, weight = 0 },
            { type = Equipment.laser.miningcannon_17mw, weight = 0 },
            { type = Equipment.laser.small_plasma_accelerator, weight = 1 },
            { type = Equipment.laser.large_plasma_accelerator, weight = 0.5 }
        }
    }, 
}


---@param role string  Name of the role
---@return EquipmentScheme
function ShipOutfitter.CreateDefaultSchemeForRole( role )
    if role == "pirate" then return EquipmentScheme.New(PirateEquipmentStats) end
    if role == "mercenary" then return EquipmentScheme.New(MercenaryEquipmentStats) end

    -- unknown
    return EquipmentScheme.New(MercenaryEquipmentStats)
end

---@param ship Ship The ship to outfit.  Assumed to be empty and newly spawned.
---@param shipdef ShipDef The definition used to spawn the Ship
---@param role string|EquipmentScheme The role the ship may be used for we are going to equip. One of "mercenary", "merchant", "pirate", "courier" or it might be a customized scheme.  Note this customized scheme will be consumed by this call
------@param budget number|nil The max amount of cash to spend on outfitting, if nil a random scaled value is generated, potentially modified by difficulty.  Note: this doesn't include the cost of the engine and mandatory items will always be fitted
function ShipOutfitter.EquipNewShip( shipdef, ship, role, getChance )
    
    logWarning( "Outfitting "..ship:GetLabel() )


    if not getChance then
        getChance = ShipOutfitter.defaultGetChance
    end

    ---@type EquipmentScheme
    local scheme;
    if role.Prepare then
        scheme = role
        scheme:Prepare()
    else
        scheme = ShipOutfitter.CreateDefaultSchemeForRole( role )
    end

    ---@type number
    local mass_remaining = shipdef.capacity;

    --- start with the hyperdrive
    if not scheme.hyperdrive then scheme.hyperdrive = shipdef.hyperdriveClass end
    if scheme.hyperdrive ~= 0 then

        ---@type EquipType.HyperdriveType
        local drive;
        if scheme.hyperdrive > 10 then
            drive = Equipment.hyperspace['hyperdrive_mil'..tostring(shipdef.hyperdriveClass-10)]
        else
            drive = Equipment.hyperspace['hyperdrive'..tostring(shipdef.hyperdriveClass)]            
        end        

        if drive then
            logWarning( "Added " .. drive:GetName() )
            mass_remaining = mass_remaining - drive.capabilities.mass
            ship:AddEquip(drive)
        end
    end

    local ts = nil
    local another_pass = true
    while another_pass do
        another_pass = false
        for _, type_scheme in pairs( scheme.equip ) do
            ts = type_scheme
            if type_scheme.chance <= 0 then                
                break 
            end

--            logVerbose( "Evaluating slot " .. type_scheme.slot )

            if type_scheme.chance >= 1 or type_scheme.chance > (1-getChance()) then
                type_scheme:Prepare( mass_remaining )
                local equip = type_scheme:Select( getChance() )
                if equip then
                    if not another_pass then 
                        if type_scheme.chance > 0 then
                            another_pass = true
                        end
                    end

                    mass_remaining = mass_remaining - equip.capabilities.mass
                    logWarning( "Added " .. equip:GetName() .. " tonnes remaining: " .. mass_remaining )
                    ship:AddEquip(equip,1,type_scheme.slot)
                end
            else
                type_scheme.chance = 0 -- missed it's chance
            end
        end
        if another_pass then
            logWarning( "Having another pass" )
            scheme.sorted = false
            scheme:Prepare()
        end
    end

end


function ShipOutfitter.CalculateEquipmentValue( ship )
    ---@type number
    local value = 0.0

    ---TODO add in the value of the hull?
	for _, name in ipairs(AllSlots) do
        local slot = ship:GetEquip(name)

        if slot then
            for _, equip in pairs(slot) do
                value = value + equip.price
            end
        end
    end

    return value
end

function ShipOutfitter.CalalculateTotalValue( ship )
    return ShipOutfitter.CalculateEquipmentValue( ship ) + ShipDefs[ship.shipId].basePrice
end

function ShipOutfitter.SampleShipValues( role, count )

    local values = {}

    while count > 0 do
        count = count -1

        local scheme = ShipOutfitter.CreateDefaultSchemeForRole( role )
        local sd = ShipOutfitter.PickShipDef( "SHIP", role )
        local ship = MocShip.New( Ship.MakeRandomLabel(), sd )

        ShipOutfitter.EquipNewShip( sd, ship, role, getChance )
        local value = ShipOutfitter.CalalculateTotalValue( ship )

        logWarning( "Total Ship Value: ".. value )
        table.insert( values, value )
    end

    logWarning( "Dumping all values:" )
    for _, v in pairs( values ) do
        logWarning( "\t"..v )
    end
end

---@param role string the role to calucalat the curve for
function ShipOutfitter.CalculateValueCurve( role )
    local sample_positions = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.9 }
    ---@type { pos: number, probability: number, value: number }[]
    local result = {}
    for _, sample_pos in pairs( sample_positions ) do
        ---@type number This will end up the probability of getting this ship or better.
        local probability = nil

        local scheme = ShipOutfitter.CreateDefaultSchemeForRole( role )

        local function getChance()
            if not probability then
                probability = (1-sample_pos)
            else
                probability = probability * (1-sample_pos)
            end
            return sample_pos
        end
        local sd = ShipOutfitter.PickShipDef( "SHIP", role, getChance )
        local ship = MocShip.New( "Value-Calc-"..role.."-"..sample_pos, sd )

        ShipOutfitter.EquipNewShip( sd, ship, role, getChance )

        local value = ShipOutfitter.CalalculateTotalValue( ship )

        logWarning( "calculated probability "..probability.." and value "..value)

        table.insert( result, { pos = sample_pos, probability = probability, value = value })
    end

    for _, v in pairs( result ) do
        logWarning( "curve for "..role.." at position "..v.pos.." has "..v.probability.." chance and "..v.value.." value" )
    end

    return result
end

return ShipOutfitter
