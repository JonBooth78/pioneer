-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local Engine     = require 'Engine'
local Event      = require 'Event'
local Space      = require 'Space'
local Timer      = require 'Timer'
local utils      = require 'utils'
local Game       = require 'Game'

---@class Modules.Common.ProximityTest
local ProximityTest = {}

---@type table<Body, table<string, Modules.Common.ProximityTest.Context>>
local activeTests = utils.automagic()

-- ─── Context ─────────────────────────────────────────────────────────────────

local onBodyEnter = function(ctx, enter) end
local onBodyLeave = function(ctx, leave) end

-- List of bodies currently in proximity is stored with weak keys, so deleted
-- bodies are quietly cleaned up during a GC cycle
local bodyListMt = {
	__mode = "k"
}

---@class Modules.Common.ProximityTest.Context
---@field New fun(body, dist, interval, type): self
---@field body Body
---@field dist number
local Context = utils.class 'Modules.Common.ProximityTest.Context'

function Context:Constructor(key, body, dist, type)
	self.bodies = setmetatable({}, bodyListMt)
	self.key = key
	self.body = body
	self.dist = dist
	self.filter = type
	self.iter = 0

	self.onBodyEnter = onBodyEnter
	self.onBodyLeave = onBodyLeave
end

function Context:Cancel()
	activeTests[self.body][self.key] = nil
	self.iter = nil
end

---@param fn fun(ctx: Modules.Common.ProximityTest.Context, enter: Body)
function Context:SetBodyEnter(fn)
	self.onBodyEnter = fn
	return self
end

---@param fn fun(ctx: Modules.Common.ProximityTest.Context, leave: Body)
function Context:SetBodyLeave(fn)
	self.onBodyLeave = fn
	return self
end

-- ─── Proximity Test ──────────────────────────────────────────────────────────

-- Class: ProximityTest
--
-- This class provides a helper utility to allow using Space.GetBodiesNear() in
-- an efficient manner, providing an event-based API when bodies enter or leave
-- a user-specified relevancy range of the reference body.

local function makeTestKey(dist, interval, type)
	return string.format("%d:%d:%s", dist, interval, type or "Body")
end

-- Function: GetTest
--
-- Retrieves the Context object for an active proximity test currently queued
--
-- Parameters:
--
--   body - the reference body object of the proximity test
--   key  - the key value retrieved from the Context returned by RegisterTest
--
-- Returns:
--
--   context - the proximity test context object for the registered test
--
function ProximityTest:GetTest(body, key)
	return activeTests[body][key]
end

-- Function: RegisterTest
--
-- Register a new periodic proximity test relative to the given body
--
-- Parameters:
--
--   body     - the reference body to perform testing for
--   dist     - the distance (in meters) of the proximity test to perform
--   interval - how often a proximity test should be performed in seconds.
--              Smaller values are more performance-hungry.
--   type     - optional body classname filter, see Space.GetBodiesNear
--   overlap  - if false, all bodies of type in the radius will generate
--                initial proximity events on the first proximity test
--
-- Returns:
--
--   context - the context object for the registered test
--
function ProximityTest:RegisterTest(body, dist, interval, type, overlap)
	local key = makeTestKey(dist, interval, type)
	if activeTests[body][key] then return activeTests[body][key] end

	local context = Context.New(key, body, dist, type)
	local cb = self:MakeCallback(context)

	activeTests[body][key] = context

	-- Queue the start of the timer at a random timestamp inside the first interval period
	-- This provides natural load balancing for large numbers of callbacks created on the same frame
	-- (e.g. at game start / hyperspace entry)
	Timer:CallAt(Game.time + Engine.rand:Number(interval), function()

		if overlap == false then
			cb()
		else
			-- Pre-fill the list of nearby bodies (avoid spurious onBodyEnter() callbacks when creating)
			for i, locBody in ipairs(Space.GetBodiesNear(body, dist, type)) do
				context.bodies[locBody] = context.iter
			end
		end

		Timer:CallEvery(interval, cb)
	end)

	return context
end

---@private
---@param context Modules.Common.ProximityTest.Context
function ProximityTest:MakeCallback(context)
	return function()
		-- Callback has been cancelled
		if not context.iter then
			return true
		end

		local newIter = (context.iter + 1) % 2
		context.iter = newIter

		for i, locBody in ipairs(Space.GetBodiesNear(context.body, context.dist, context.filter)) do
			if not context.bodies[locBody] then
				context.onBodyEnter(context, locBody)
			end

			context.bodies[locBody] = newIter
		end

		local remove = {}
		for locBody, ver in pairs(context.bodies) do
			if ver ~= newIter then
				context.onBodyLeave(context, locBody)
				table.insert(remove, locBody)
			end
		end

		for _, v in ipairs(remove) do
			context.bodies[v] = nil
		end
	end
end

Event.Register("onGameStart", function()
	activeTests = utils.automagic()
end)

Event.Register("onGameEnd", function()
	activeTests = utils.automagic()
end)

return ProximityTest
