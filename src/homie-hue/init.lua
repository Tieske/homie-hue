--- Hue-to-Homie bridge.
--
-- This module instantiates a homie device acting as a bridge between the Philips
-- Hue API and Homie.
--
-- The module returns a single function that takes an options table. When called
-- it will construct a Homie device and add it to the Copas scheduler (without
-- running the scheduler).
-- @copyright Copyright (c) 2022-2022 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE`.
-- @usage
-- local copas = require "copas"
-- local hmh = require "homie-hue"
--
-- hmh {
--   millheat_access_key = "xxxxxxxx",
--   millheat_secret_token = "xxxxxxxx",
--   millheat_username = "xxxxxxxx",
--   millheat_password = "xxxxxxxx",
--   millheat_poll_interval = 15,            -- default: 15 seconds
--   homie_mqtt_uri = "http://mqtthost:123", -- format: "mqtt(s)://user:pass@hostname:port"
--   homie_domain = "homie",                 -- default: "homie"
--   homie_device_id = "millheat",           -- default: "millheat"
--   homie_device_name = "M2H bridge",       -- default: "Millheat-to-Homie bridge"
-- }
--
-- copas.loop()

local copas = require "copas"
local copas_timer = require "copas.timer"
local Device = require "homie.device"
local slugify = require("homie.utils").slugify
local log = require("logging").defaultLogger()
local json = require "cjson.safe"
local now = require("socket").gettime

local RETRIES = 3 -- retries for setting a new setpoint
local RETRY_DELAY = 1 -- in seconds, doubled after each try (as back-off mechanism)
local DEVICE_UPDATE_DELAY = 2 -- delay in seconds before recreating the Homie device after changes

local Homie_Hue = {}
Homie_Hue.__index = Homie_Hue

local event_handlers = {}

function event_handlers.status_initializing(self, event_data)
  -- nothing to do here.
end


function event_handlers.status_connecting(self, event_data)
  -- nothing to do here.
end


function event_handlers.status_open(self, event_data)
  -- nothing to do here.
end


function event_handlers.status_closed(self, event_data)
  -- nothing to do here.
end


function event_handlers.hue_add(self, event_data)
  self:update_device()
end


function event_handlers.hue_update(self, event_data)
  local hue = self.hue
  local current = event_data.current
  local received = event_data.received

  if current.type == "geofence_client" and current.name:match("^aiohue_") then
    -- this is a name by Home Assistant to fake a keep-alive, nothing to do
    return
  end

  if current.type ~= "light" and current.type ~= "grouped_light" then
    -- unsupported resource for now, nothing to do
    return
  end

  if current.type == "grouped_light" and current.owner.type == "bridge_home" then
    -- this is the entire home group, skip
    return
  end

  local node_name = self.id_name_map[current.id]
  if not node_name then
    log:error("no node-name found for resource id '" .. current.id .. "'")
    return
  end

  local node = self.homie.nodes[node_name]
  if not node_name then
    log:error("no node found for resource id '" .. current.id .. "', with name '"..node_name.."'")
    return
  end

  if (received.on or {}).on ~= nil then
    -- power state changed
    local ok, err = node.properties.power:set(received.on.on == true)
    if not ok then
      log:error("failed setting power state for '" .. self.id_name_map[current.id] .. "': "..tostring(err))
    end
    received.on = nil
  end

  if (received.dimming or {}).brightness ~= nil then
    -- brightness changed, only change if it is not 0 (when turned off)
    if received.dimming.brightness ~= 0 then
      local ok, err = node.properties.dimming:set(received.dimming.brightness)
      if not ok then
        log:error("failed setting brightness for '" .. self.id_name_map[current.id] .. "': "..tostring(err))
      end
    end
    received.dimming = nil
  end

  if received.color or received.color_temperature then
    log:warn("color change not implemented yet")
    return
  end

  if not next(received) then
    -- all changes handled, so exit
    return
  end

  -- some changes left, so it's a device change, update device
  print("changed: ", require("pl.pretty").write(received))
  self:update_device()
end


function event_handlers.hue_delete(self, event_data)
  self:update_device()
end



-- can be called if the device needs updating.
-- Will delay updates until DEVICE_UPDATE_DELAY seconds after last update
function Homie_Hue:update_device()
  if self.update_time then
    -- update is already scheduled
    self.update_time = now() + DEVICE_UPDATE_DELAY
    self.update_request_count = self.update_request_count + 1
    return
  end

  self.update_time = now() + DEVICE_UPDATE_DELAY
  self.update_request_count = 1
  copas_timer.new {
    name = "homie-hue device updater",
    recurring = false,
    delay = DEVICE_UPDATE_DELAY,
    callback = function()
      -- wait if we're not to execute yet...
      while now() < self.update_time do
        copas.pause(now() - self.update_time)
      end
      -- clear the flag, and update
      log:info("updating homie device (%d Hue changes)", self.update_request_count)
      self.update_time = nil
      self.update_request_count = nil
      self:new_device()
    end
  }
end



-- Creates a new homie device (replacing the old one if existing)
function Homie_Hue:new_device()
  if self.homie then
    -- a device exists, stop it
    self.homie:stop()
    self.homie = nil
  end

  -- create new device
  local newdevice = {
    uri = self.homie_mqtt_uri,
    domain = self.homie_domain,
    broker_state = nil, -- do not recover state from broker
    id = self.homie_device_id,
    homie = "4.0.0",
    extensions = "",
    name = self.homie_device_name,
    nodes = {}
  }

  -- map from id (key) to slugified name (value)
  local id_name_map = {}

  for _, resource_type in ipairs { "light", "grouped_light" } do

    for uuid, resource in pairs(self.hue.types[resource_type]) do

      local resource_id, resource_name, resource_typename, power, brightness

      if resource_type == "light" then
--for k,v in pairs(resource) do print(k," = ",v) end
-- local owner = resource.owner
-- resource.owner = nil
-- print("light: ", require("pl.pretty").write(resource))
-- resource.owner = owner
        resource_id = slugify(resource.owner.metadata.name)
        resource_name = resource.owner.metadata.name
        power = (resource.on.on == true)
        brightness = resource.dimming and resource.dimming.brightness or nil
        resource_typename = resource.owner.product_data.product_name .. " (" ..
                            resource.owner.product_data.manufacturer_name .. ")"

      elseif resource_type == "grouped_light" then
        if resource.owner.type == "bridge_home" then
          -- skip this one, it's the entire home group
          break
        end
        resource_id = slugify(resource.owner.metadata.name) -- room name
        resource_name = resource.owner.metadata.name -- room name
        power = (resource.on.on == true)
        brightness = resource.dimming and resource.dimming.brightness or nil
        resource_typename = resource.owner.type

      else
        error("unknown resource type: '%s'", resource_type)
      end

      -- track node name by id
      id_name_map[resource.id] = resource_id -- resource_id == slugified name

      -- add light
      if newdevice.nodes[resource_id] then
        log:warn("There are multiple lights/groups called '%s'", resource_id)
      end
      local node = {}
      newdevice.nodes[resource_id] = node
      node.name = resource_name
      node.type = resource_typename
      -- add on/off setting
      node.properties = {
        power = {
          name = "power",
          datatype = "boolean",
          settable = true,
          retained = true,
          default = power,
        },
      }
      if brightness then
        -- this is a dimmable light, so add additional property
        node.properties.dimming = {
          name = "dimming",
          datatype = "float",
          settable = true,
          retained = true,
          default = brightness,
          unit = "%",
          format = "0:100",
        }
      end
    end

  end

  self.id_name_map = id_name_map
  self.homie = Device.new(newdevice)
  self.homie:start()
end

return function(opts)
  local self = setmetatable(opts, Homie_Hue)
  -- Hue interface object
  self.hue = require("philips-hue").new {
    apikey = self.hue_key,
    address = self.hue_ip,
    sse_event_timout = self.hue_sse_event_timout,
    callback = function(hue_client, event_data)
      local event_key = tostring(event_data.type).."_"..tostring(event_data.event)
      return event_handlers[event_key](self, event_data)
    end,
  }

  self.hue:start()
end
