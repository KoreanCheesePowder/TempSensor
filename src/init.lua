local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local log = require "log"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration

local driver_info = capabilities["buildbook37604.driverInformation"]

local DRIVER_NAME = "C.P TempSensor 0.1C"
local DRIVER_VERSION = "v1.0.8"
local DRIVER_AUTHOR = "치즈가루"

local TEMP_MIN_INTERVAL = 1
local TEMP_MAX_INTERVAL = 300
local HUMIDITY_MIN_INTERVAL = 10

local function get_temperature_change(device)
  local value = tonumber(device.preferences.temperatureReportDelta) or 10
  local allowed = { [10] = true, [20] = true, [30] = true, [50] = true, [100] = true }
  if allowed[value] then return value end
  return 10
end


local function get_humidity_change(device)
  local value = tonumber(device.preferences.humidityReportDelta) or 100
  local allowed = { [50] = true, [100] = true, [200] = true, [300] = true, [500] = true }
  if allowed[value] then return value end
  return 100
end

local function get_humidity_max_interval(device)
  local value = tonumber(device.preferences.humidityReportMax) or 300
  local allowed = { [60] = true, [300] = true, [600] = true, [900] = true, [1800] = true, [3600] = true }
  if allowed[value] then return value end
  return 300
end

local function emit_driver_information(device)
  if driver_info == nil then return end
  if driver_info.author ~= nil then
    device:emit_event(driver_info.author(DRIVER_AUTHOR))
  end
  if driver_info.driverVersion ~= nil then
    device:emit_event(driver_info.driverVersion(DRIVER_VERSION))
  end
end

local function send_reads(device)
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function configure_reporting(device)
  local temp_change = get_temperature_change(device)
  local humidity_change = get_humidity_change(device)
  local humidity_max_interval = get_humidity_max_interval(device)

  log.info(string.format(
    "%s %s by %s | Configure reporting: temperature min=%ds max=%ds change=%.2fC, humidity min=%ds max=%ds change=%.2f%%",
    DRIVER_NAME, DRIVER_VERSION, DRIVER_AUTHOR,
    TEMP_MIN_INTERVAL, TEMP_MAX_INTERVAL, temp_change / 100,
    HUMIDITY_MIN_INTERVAL, humidity_max_interval, humidity_change / 100
  ))

  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device,
    TEMP_MIN_INTERVAL,
    TEMP_MAX_INTERVAL,
    data_types.Int16(temp_change)
  ))

  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(
    device,
    HUMIDITY_MIN_INTERVAL,
    humidity_max_interval,
    data_types.Uint16(humidity_change)
  ))

  send_reads(device)
end

local function added_handler(driver, device)
  emit_driver_information(device)
end

local function init_handler(driver, device)
  emit_driver_information(device)
end

local function do_configure_handler(driver, device)
  configure_reporting(device)
  emit_driver_information(device)
end

local function info_changed_handler(driver, device, event, args)
  local old_preferences = {}
  if args ~= nil and args.old_st_store ~= nil and args.old_st_store.preferences ~= nil then
    old_preferences = args.old_st_store.preferences
  end

  if old_preferences.temperatureReportDelta ~= device.preferences.temperatureReportDelta or
     old_preferences.humidityReportDelta ~= device.preferences.humidityReportDelta or
     old_preferences.humidityReportMax ~= device.preferences.humidityReportMax then
    configure_reporting(device)
  elseif old_preferences.tempOffset ~= device.preferences.tempOffset or
         old_preferences.humidityOffset ~= device.preferences.humidityOffset then
    send_reads(device)
  end

  emit_driver_information(device)
end

local function refresh_handler(driver, device, command)
  send_reads(device)
  emit_driver_information(device)
end

local function temperature_handler(driver, device, value, zb_rx)
  local offset = tonumber(device.preferences.tempOffset) or 0
  local measured = value.value / 100.0
  local corrected = measured + offset

  log.info(string.format(
    "Temperature raw=%d measured=%.2fC offset=%.2fC emitted=%.2fC",
    value.value, measured, offset, corrected
  ))

  device:emit_event(capabilities.temperatureMeasurement.temperature({
    value = corrected,
    unit = "C"
  }))
end

local function humidity_handler(driver, device, value, zb_rx)
  local offset = tonumber(device.preferences.humidityOffset) or 0
  local measured = value.value / 100.0
  local corrected = math.max(0, math.min(100, measured + offset))

  log.info(string.format(
    "Humidity raw=%d measured=%.2f%% offset=%.2f%% emitted=%.0f%%",
    value.value, measured, offset, corrected
  ))

  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(
    math.floor(corrected + 0.5)
  ))
end

local driver_template = {
  health_check = false,
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    capabilities.firmwareUpdate,
    capabilities.refresh,
    driver_info
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
    doConfigure = do_configure_handler,
    infoChanged = info_changed_handler
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_handler
      },
      [RelativeHumidity.ID] = {
        [RelativeHumidity.attributes.MeasuredValue.ID] = humidity_handler
      }
    }
  }
}

defaults.register_for_default_handlers(driver_template, {
  capabilities.battery
})

ZigbeeDriver(DRIVER_NAME, driver_template):run()
