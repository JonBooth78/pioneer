-- Copyright © 2008-2023 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

-- This file implements type information about C++ classes for Lua static analysis
-- TODO: this file is partially type-complete, please expand it as more types are added.

---@meta

---@class Engine
---
---@field rand Rand
---@field ticks number Number of milliseconds since Pioneer was started.
---@field time number Number of real-time seconds since Pioneer was started.
---@field frameTime number Length of the last frame in seconds.
---@field pigui unknown This is purposefully left untyped, type information is provided for the ui object
---@field version string

---@class Engine
local Engine = {}

-- TODO: add information about all Engine methods

--- Fetch a value from the ini config
---@param section? string The config section to fetch from
---@param key string The key to fetch
---@param type string One of int, float, string to determing the kind of value to get
---@param default integer|number|string The default value to return if the section/key is not stored
---@return integer|number|string The fetched value or default if it is not present
function Engine.GetConfig( section, key, type, default ) end

--- Set a value to the ini config
---@param section? string The config section to set to`
---@param key string The key to set
---@param type string One of int, float, string to determing the kind of value to get
---@param value integer|number|string The value to set
function Engine.SetConfig( section, key, type, value ) end

--- Start a transaction on the config, use if you're going to set multiple
--- values as then the config is only saved once you call EndConfigTransaction
--- rather than each time you set a new value
---@return integer An id for the transaction, used to close it.
function Engine.StartConfigTransaction() end

--- End a transaction; will flush and save any changes to disc made during the
--- the transaction
---@param id integer The transaction id returned from StartConfigTransaction
function Engine.EndConfigTransaction( id ) end

return Engine
