local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local log = require "log"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration

local driver_info = capabilities["buildbook37604.driverInformation"]

local DRIVER_NAME = "C.P TempSensor 0.1C"
local DRIVER_VERSION = "v1.4.0"
local DRIVER_AUTHOR = "치즈가루"

local function allowed_number(value, fallback, allowed)
  value = tonumber(value) or fallback
  return allowed[value] and value or fallback
end

local function get_temperature_change(device)
  return allowed_number(device.preferences.temperatureReportDelta, 10,
    { [10] = true, [20] = true, [30] = true, [50] = true, [100] = true })
end

local function get_temperature_min_interval(device)
  return allowed_number(device.preferences.temperatureReportMin, 1,
    { [1] = true, [2] = true, [5] = true, [10] = true })
end

local function get_temperature_max_interval(device)
  return allowed_number(device.preferences.temperatureReportMax, 10,
    { [10] = true, [30] = true, [60] = true, [300] = true, [600] = true })
end

local function get_humidity_change(device)
  return allowed_number(device.preferences.humidityReportDelta, 50,
    { [50] = true, [100] = true, [200] = true, [300] = true, [500] = true })
end

local function get_humidity_min_interval(device)
  return allowed_number(device.preferences.humidityReportMin, 1,
    { [1] = true, [2] = true, [5] = true, [10] = true })
end

local function get_humidity_max_interval(device)
  return allowed_number(device.preferences.humidityReportMax, 60,
    { [10] = true, [30] = true, [60] = true, [300] = true, [600] = true,
      [900] = true, [1800] = true, [3600] = true })
end

local function get_temperature_precision(device)
  local values = { p01 = 0.1, p05 = 0.5, p10 = 1.0 }
  return values[tostring(device.preferences.temperaturePrecision or "p01")] or 0.1
end

local function get_humidity_precision(device)
  return allowed_number(device.preferences.humidityPrecision, 1,
    { [1] = true, [2] = true, [5] = true })
end

local function round_to_step(value, step)
  return math.floor((value / step) + 0.5) * step
end

local function event_metadata(device)
  if device.preferences.saveHistory == false then
    return {
      state_change = false,
      visibility = { displayed = false, non_archivable = true, ephemeral = true }
    }
  end

  return {
    state_change = true,
    visibility = { displayed = true, non_archivable = false, ephemeral = false }
  }
end

local function info_metadata()
  return {
    state_change = false,
    visibility = { displayed = false, non_archivable = true, ephemeral = true }
  }
end

local function emit_driver_information(device)
  if driver_info == nil then return end
  if driver_info.author ~= nil then
    device:emit_event(driver_info.author(DRIVER_AUTHOR, info_metadata()))
  end
  if driver_info.driverVersion ~= nil then
    device:emit_event(driver_info.driverVersion(DRIVER_VERSION, info_metadata()))
  end
end

local function send_reads(device)
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function configure_reporting(driver, device, reason)
  local temp_min = get_temperature_min_interval(device)
  local temp_max = get_temperature_max_interval(device)
  local temp_change = get_temperature_change(device)
  local humidity_min = get_humidity_min_interval(device)
  local humidity_max = get_humidity_max_interval(device)
  local humidity_change = get_humidity_change(device)

  if temp_min > temp_max then temp_min = temp_max end
  if humidity_min > humidity_max then humidity_min = humidity_max end

  if driver and driver.environment_info and driver.environment_info.hub_zigbee_eui then
    device:send(device_management.build_bind_request(
      device, TemperatureMeasurement.ID, driver.environment_info.hub_zigbee_eui))
    device:send(device_management.build_bind_request(
      device, RelativeHumidity.ID, driver.environment_info.hub_zigbee_eui))
  end

  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device, temp_min, temp_max, data_types.Int16(temp_change)))

  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(
    device, humidity_min, humidity_max, data_types.Uint16(humidity_change)))

  device:set_field("pending_reporting_config", false, { persist = false })
  log.info(string.format(
    "Reporting configured (%s): temp min=%ds max=%ds change=%.2fC, humidity min=%ds max=%ds change=%.2f%%",
    tostring(reason or "unknown"), temp_min, temp_max, temp_change / 100,
    humidity_min, humidity_max, humidity_change / 100))
  send_reads(device)
end

local function request_config_when_awake(driver, device, source)
  if device:get_field("pending_reporting_config") ~= true then return end
  device:set_field("pending_reporting_config", false, { persist = false })
  device.thread:call_with_delay(1, function()
    configure_reporting(driver, device, "device-awake:" .. tostring(source))
  end)
end

local function added_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  emit_driver_information(device)
end

local function init_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  emit_driver_information(device)
end

local function do_configure_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  configure_reporting(driver, device, "doConfigure")
  emit_driver_information(device)
end

local function info_changed_handler(driver, device, event, args)
  local old = {}
  if args and args.old_st_store and args.old_st_store.preferences then
    old = args.old_st_store.preferences
  end

  local reporting_changed =
    old.temperatureReportDelta ~= device.preferences.temperatureReportDelta or
    old.temperatureReportMin ~= device.preferences.temperatureReportMin or
    old.temperatureReportMax ~= device.preferences.temperatureReportMax or
    old.humidityReportDelta ~= device.preferences.humidityReportDelta or
    old.humidityReportMin ~= device.preferences.humidityReportMin or
    old.humidityReportMax ~= device.preferences.humidityReportMax

  if reporting_changed then
    device:set_field("pending_reporting_config", true, { persist = false })
    configure_reporting(driver, device, "preference-change")
  elseif old.tempOffset ~= device.preferences.tempOffset or
         old.humidityOffset ~= device.preferences.humidityOffset or
         old.temperaturePrecision ~= device.preferences.temperaturePrecision or
         old.humidityPrecision ~= device.preferences.humidityPrecision or
         old.saveHistory ~= device.preferences.saveHistory then
    send_reads(device)
  end

  emit_driver_information(device)
end

local function refresh_handler(driver, device, command)
  send_reads(device)
  emit_driver_information(device)
end

local function temperature_handler(driver, device, value, zb_rx)
  request_config_when_awake(driver, device, "temperature-report")

  local offset = tonumber(device.preferences.tempOffset) or 0
  local measured = value.value / 100.0
  local emitted = round_to_step(measured + offset, get_temperature_precision(device))

  device:emit_event(capabilities.temperatureMeasurement.temperature({
    value = emitted,
    unit = "C"
  }, event_metadata(device)))
end

local function humidity_handler(driver, device, value, zb_rx)
  request_config_when_awake(driver, device, "humidity-report")

  local offset = tonumber(device.preferences.humidityOffset) or 0
  local measured = value.value / 100.0
  local corrected = math.max(0, math.min(100, measured + offset))
  local emitted = round_to_step(corrected, get_humidity_precision(device))
  emitted = math.max(0, math.min(100, math.floor(emitted + 0.5)))

  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(
    emitted,
    event_metadata(device)
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
  capabilities.battery,
  capabilities.firmwareUpdate
})

local driver = ZigbeeDriver(DRIVER_NAME, driver_template)
driver:run()
