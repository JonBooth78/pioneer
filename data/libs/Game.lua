local Game = package.core["Game"]
local Event = require 'Event'
local utils = require 'utils'
local Engine = require 'Engine'
--local Engine = package.core["Engine"]

-- Simple way to track the start date of the game until DateTime objects are exposed to lua
local gameStartTime = 0.0

Game.comms_log_lines = {}
Game.AddCommsLogLine = function(text, sender, priority)
	table.insert(Game.comms_log_lines, { text=text, time=Game.time, sender=sender, priority = priority or 'normal'})
	if type(priority) == "number" and priority > 0 then
		Game.SetTimeAcceleration("1x")
	end 
end

Game.GetCommsLines = function()
	return Game.comms_log_lines
end

-- Function: GetStartTime()
--
-- Returns the zero-offset time in seconds since Jan 1 3200 at which the
-- current game began.
--
-- > local seconds_since_start = Game.time - Game.GetStartTime()
--
function Game.GetStartTime()
	return gameStartTime
end

Game.difficulty = {}

---@class Game.DifficultyElement
---@field public descriptor table Read only table of description of this difficulty element
---@field private current_pc integer The current value
Game.DifficultyElement = utils.class( "Game.DifficultyElement" )

---@param default_percent integer what percentage is this by default?
function Game.DifficultyElement:Constructor( default_percent, name, desc, tooltip )
	self.descriptor = utils.readOnly(
		{ default_pc = default_percent,
		  desc = desc,
		  tooltip = tooltip,
		  name = name
		}
	)
	self.current_pc = default_percent
end

---@type table<string, Game.DifficultyElement>
Game.difficulty_elements =
{
	numPirates = Game.DifficultyElement.New( 25, "numPirates", "Number of pirates", "Specifies how many pirates are likely to inhabit systems - also depends on the system security" ),
	pirateEquipment = Game.DifficultyElement.New( 25, "pirateEquipment", "Pirate equipment", "Specifies how well armed priates are likely to be" )
}

function Game.DifficultyElement:GetPercent()
	return self.current_pc
end

---@type boolean
local defer_difficulty_refresh = false

---@param v integer The percentage to set to.
function Game.DifficultyElement:SetPercent( v )
	v = math.min( v, 100 )
	v = math.max( v, 0 )
	if v == self.current_pc then return end

	self.current_pc = v;

	if defer_difficulty_refresh then return end

	Engine.SetConfig( "difficulty", self.descriptor.name, "int", v )

	if Game.player then
		Game.SetDifficulty( self.descriptor.name, v )
	end

	Game.RefreshDifficulties()
end


function Game.RefreshDifficulties()
	local t = {}
	for _, e in pairs( Game.difficulty_elements ) do
		t[e.descriptor.name] = e.current_pc/100.0
	end

	Game.difficulty = utils.readOnly(t);
end

function Game.LoadDifficultiesFromConfig()
	defer_difficulty_refresh = true

	for _, e in pairs( Game.difficulty_elements ) do
		local val = Engine.GetConfig( "difficulty", e.descriptor.name, "int", e.descriptor.default_pc );
		e:SetPercent( val )
	end

	defer_difficulty_refresh = false
	Game.RefreshDifficulties()
end

Game.LoadDifficultiesFromConfig()

Event.Register('onGameStart', function()
	Game.comms_log_lines = {}
	gameStartTime = Game.time

	-- push all difficulty levels into the game
	-- so the c++ code can access them
	for _, d in pairs( Game.difficulty_elements ) do
		Game.SetDifficulty( d.descriptor.name, d.current_pc )
	end
end)

Event.Register('onGameEnd', function()
	gameStartTime = 0
	Game.LoadDifficultiesFromConfig()
end)

local function _serialize()

	local difficulties = {}
	for _, e in pairs( Game.difficulty_elements ) do
		difficulties[e.descriptor.name] = e.current_pc
	end

	return { startTime = gameStartTime, version = 1, difficulties = difficulties }
end

local function _deserialize(data)
	gameStartTime = data.startTime or 0

	---@type integer
	local version = data.version or 0
	if version > 0 then

		-- don't push these difficulty changes to the engine or game:
		defer_difficulty_refresh = true
		-- set percentages for all the ones saved:
		for category, value in pairs( data.difficulties ) do
			Game.difficulty_elements[category]:SetPercent(value)
		end
		defer_difficulty_refresh = false

		-- now set them all to the game:
		for _, d in pairs (Game.difficulty_elements) do
			Game.SetDifficulty( d.descriptor.name, d.current_pc )
		end

	end
end

require 'Serializer':Register('Game', _serialize, _deserialize)

return Game
