#!/usr/bin/env lua

--- Main CLI application.
-- Reads configuration from environment variables and starts the Hue-to-Homie bridge.
-- Does not support any CLI parameters.
--
-- For configuring the log, use LuaLogging environment variable prefix `"HOMIE_LOG_"`, see
-- "logLevel" in the example below.
-- @script homiehue
-- @usage
-- # configure parameters as environment variables
-- export HUE_KEY="xxxxxxxx"
-- export HUE_IP="xxxxxxxx"                   # Only set if auto-detection fails
-- export HOMIE_MQTT_URI="mqtt://synology"    # format: "mqtt(s)://user:pass@hostname:port"
-- export HOMIE_DOMAIN="homie"                # default: "homie"
-- export HOMIE_DEVICE_ID="philips-hue"       # default: "philips-hue"
-- export HOMIE_DEVICE_NAME="H2H bridge"      # default: "Hue-to-Homie bridge"
-- export HOMIE_LOG_LOGLEVEL="info"           # default: "INFO"
--
-- # start the application
-- homiehue

local ll = require "logging"
local copas = require "copas"
require("logging.rsyslog").copas() -- ensure copas, if rsyslog is used
local logger = assert(require("logging.envconfig").set_default_logger("HOMIE_LOG"))


do -- set Copas errorhandler
  local lines = require("pl.stringx").lines

  copas.setErrorHandler(function(msg, co, skt)
    msg = copas.gettraceback(msg, co, skt)
    for line in lines(msg) do
      ll.defaultLogger():error(line)
    end
  end, true)
end


print("starting Hue-to-Homie bridge")
logger:info("starting Hue-to-Homie bridge")


local opts = {
  hue_key = assert(os.getenv("HUE_KEY"), "environment variable HUE_KEY not set"),
  hue_ip = os.getenv("HUE_IP"),
  homie_domain = os.getenv("HOMIE_DOMAIN") or "homie",
  homie_mqtt_uri = assert(os.getenv("HOMIE_MQTT_URI"), "environment variable HOMIE_MQTT_URI not set"),
  homie_device_id = os.getenv("HOMIE_DEVICE_ID") or "philips-hue",
  homie_device_name = os.getenv("HOMIE_DEVICE_NAME") or "Hue-to-Homie bridge",
}

logger:info("HUE_KEY: ********")
logger:info("HUE_IP: " .. (opts.hue_ip or "(auto-detect)"))
logger:info("HOMIE_DOMAIN: %s", opts.homie_domain)
logger:info("HOMIE_MQTT_URI: %s", opts.homie_mqtt_uri)
logger:info("HOMIE_DEVICE_ID: %s", opts.homie_device_id)
logger:info("HOMIE_DEVICE_NAME: %s", opts.homie_device_name)


copas(function()
  require("homie-hue")(opts)
end)

ll.defaultLogger():info("Hue-to-Homie bridge exited")
