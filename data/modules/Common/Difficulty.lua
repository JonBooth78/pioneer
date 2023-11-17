local Game = package.core["Game"]
local Event = require 'Event'
local utils = require 'utils'
local Engine = require 'Engine'

---@type boolean
local LOG_DIFFICULTY = false

--- send a log message, from the pirates module
--- enables us to quickly turn the debugging on/off
---@param message string
local function logDifficulty( message )
	if LOG_DIFFICULTY then	logWarning( "Difficulty: " .. message ) end
end


local Difficulty = {}


-- --- applies a quadratic curve to the difficulty incoming
-- function Difficulty.map_for_difficulty( d, t )
--     local one_minus_t = (1-t)
--     return one_minus_t*one_minus_t*(1-d) + t*t*d
-- end

function Difficulty.multiplier_for_difficulty_window( d, cut_in, cut_out )
    local range = cut_out-cut_in
    d = d - cut_in;
    d = d / range
	d = math.clamp( d, 0, 1 )
    return d
end

--- Generate a random value, on a normal distribution for a difficulty
--- the distribution has a std of 0.15 and centered around the difficulty
--- score for the category multiplied by the modifier.
--- Then a cut in/out range is applied, such that any value generated
--- less than cut_in maps to zero and any value generated more than 
--- cut_out maps to one.
---@param category string 		The difficulty category to look up
---@param modifier number|nil	A modifier to apply (e.g. system lawlessness), defaults to 0.5 
---@param cut_in number|nil		Any value generated less than this get shifted and clamped to zero, defaults to 0
---@param cut_out number|nil	Any value generated more than this gets shifted and clamped to one, defaults to 1
function Difficulty:random_normal_for_category( category, modifier, cut_in, cut_out )
	if not cut_in then cut_in = 0 end
	if not cut_out then cut_out = 1 end
	if not modifier then modifier = 1 end

	local rng = Engine.rand:Normal( 0.0, 0.15 )

	rng = math.clamp( rng, -0.5, 0.5 ) -- prevent any statistical outliers that's about every 1/100
	logDifficulty( "Generated a normalized random number for " .. category .. " of " .. rng )

	local cat_val = self.category[category] 

	modifier = self.multiplier_for_difficulty_window( modifier, cut_in, cut_out )
	logDifficulty( "Applied window from " .. cut_in .. " to " .. cut_out .. " to modifier to give " .. modifier )

	rng = (rng + cat_val) * modifier

	logDifficulty( "Modified rng to " .. rng .. " with category at " .. cat_val .. " will be clamped [0,1]" )
	rng = math.clamp( rng, 0, 1)

	return rng
end

function Difficulty:yes_no_for_category( category, modifier, cut_in, cut_out )
	if not cut_in then cut_in = 0 end
	if not cut_out then cut_out = 1 end
	if not modifier then modifier = 1 end

	local d = self.category[category]

	local cut_off = (d * modifier)
	cut_off = self.multiplier_for_difficulty_window( cut_off, cut_in, cut_out )

	logDifficulty( "Calclated a yes_no cut off for category " .. category .. " with value " .. d .. " and modifer " .. modifier .. " cut in " .. cut_in .. " cut out " .. cut_out)

	if Engine.rand:Number(1) < cut_off then
		return true
	else
		return false
	end
end

Difficulty.category = {}

---@class Difficulty.DifficultyElement
---@field public descriptor table Read only table of description of this difficulty element
---@field private current_pc integer The current value
Difficulty.DifficultyElement = utils.class( "Difficulty.DifficultyElement" )

---@param default_percent integer what percentage is this by default?
function Difficulty.DifficultyElement:Constructor( default_percent, name, desc, tooltip )
	self.descriptor = utils.readOnly(
		{ default_pc = default_percent,
		  desc = desc,
		  tooltip = tooltip,
		  name = name
		}
	)
	self.current_pc = default_percent
end

---@type table<string, Difficulty.DifficultyElement>
Difficulty.category_elements =
{
	numPirates = Difficulty.DifficultyElement.New( 25, "numPirates", "Number of pirates", "Specifies how many pirates are likely to inhabit systems - also depends on the system security" ),
	pirateHostility = Difficulty.DifficultyElement.New( 25, "pirateHostility", "Pirate hostility", "Specifies how likely pirates are to attack, also depends on the cargo of the target ship" ),
	pirateEquipment = Difficulty.DifficultyElement.New( 25, "pirateEquipment", "Pirate equipment", "Specifies how well armed priates are likely to be" )
}

function Difficulty.DifficultyElement:GetPercent()
	return self.current_pc
end

---@type boolean
local defer_difficulty_refresh = false

---@param v integer The percentage to set to.
function Difficulty.DifficultyElement:SetPercent( v )
	v = math.clamp( v, 0, 100 )
	if v == self.current_pc then return end

	self.current_pc = v;

	if defer_difficulty_refresh then return end

	Engine.SetConfig( "difficulty", self.descriptor.name, "int", v )

	if Difficulty.player then
		Game.SetDifficulty( self.descriptor.name, v )
	end

	Difficulty.RefreshDifficulties()
end


function Difficulty.RefreshDifficulties()
	local t = {}
	for _, e in pairs( Difficulty.category_elements ) do
		t[e.descriptor.name] = e.current_pc/100.0
	end

	Difficulty.category = utils.readOnly(t);
end

function Difficulty.LoadDifficultiesFromConfig()
	defer_difficulty_refresh = true

	for _, e in pairs( Difficulty.category_elements ) do
		local val = Engine.GetConfig( "difficulty", e.descriptor.name, "int", e.descriptor.default_pc );
		e:SetPercent( val )
	end

	defer_difficulty_refresh = false
	Difficulty.RefreshDifficulties()
end

Difficulty.LoadDifficultiesFromConfig()


Event.Register('onGameStart', function()
	-- push all difficulty levels into the game
	-- so the c++ code can access them
	for _, d in pairs( Difficulty.category_elements ) do
		Game.SetDifficulty( d.descriptor.name, d.current_pc )
	end
end)

Event.Register('onGameEnd', function()
	Difficulty.LoadDifficultiesFromConfig()
end)

local function _serialize()

	local categories = {}
	for _, e in pairs( Difficulty.category_elements ) do
		categories[e.descriptor.name] = e.current_pc
	end

	return { version = 1, categories = categories }
end

local function _deserialize(data)
	---@type integer
	local version = data.version or 0

	if version > 0 then
		-- don't push these difficulty changes to the engine or game:
		defer_difficulty_refresh = true
		-- set percentages for all the ones saved:
		for category, value in pairs( data.categories ) do
			Difficulty.category_elements[category]:SetPercent(value)
		end
		defer_difficulty_refresh = false
	end
	-- now set them all to the game:
	for _, d in pairs (Difficulty.category_elements) do
		Game.SetDifficulty( d.descriptor.name, d.current_pc )
	end
end

require 'Serializer':Register('Difficulty', _serialize, _deserialize)

return Difficulty