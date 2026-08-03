local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local log = require "log"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration
local PollControl = clusters.PollControl

local driver_info = capabilities["buildbook37604.driverInformation"]

local DRIVER_NAME = "C.P TempSensor 0.1C"
local DRIVER_VERSION = "v1.6.0"
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

local function get_sensor_report_interval(device)
  return allowed_number(device.preferences.sensorReportInterval, 60,
    { [10] = true, [30] = true, [60] = true, [300] = true, [600] = true,
      [900] = true, [1800] = true, [3600] = true })
end

local function get_sleep_checkin_interval(device)
  return allowed_number(device.preferences.sleepCheckInInterval, 1740,
    { [1] = true, [5] = true, [10] = true, [30] = true, [60] = true,
      [300] = true, [600] = true, [1740] = true, [1800] = true })
end

local function get_short_poll_interval(device)
  return allowed_number(device.preferences.shortPollInterval, 4,
    { [1] = true, [2] = true, [4] = true, [8] = true })
end

local function get_fast_poll_timeout(device)
  return allowed_number(device.preferences.fastPollTimeout, 40,
    { [20] = true, [40] = true, [80] = true, [120] = true, [240] = true })
end

local function get_humidity_change(device)
  return allowed_number(device.preferences.humidityReportDelta, 50,
    { [50] = true, [100] = true, [200] = true, [300] = true, [500] = true })
end

local function get_humidity_min_interval(device)
  return allowed_number(device.preferences.humidityReportMin, 1,
    { [1] = true, [2] = true, [5] = true, [10] = true })
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


local function read_poll_control(device, reason)
  log.info(string.format(
    "Poll Control read-back requested (%s): %s",
    tostring(reason), tostring(device.label or device.id)))

  device:send(PollControl.attributes.CheckInInterval:read(device))
  device:send(PollControl.attributes.ShortPollInterval:read(device))
  device:send(PollControl.attributes.FastPollTimeout:read(device))
end

local function make_poll_control_attribute_handler(name)
  return function(driver, device, value, zb_rx)
    local raw = value and value.value or value
    local seconds = type(raw) == "number" and raw / 4 or "n/a"
    log.info(string.format(
      "Poll Control applied: %s raw=%s seconds=%s device=%s",
      tostring(name), tostring(raw), tostring(seconds),
      tostring(device.label or device.id)))
  end
end

local function apply_poll_control(device, reason)
  local checkin_seconds = get_sleep_checkin_interval(device)
  local checkin_quarter_seconds = checkin_seconds * 4
  local short_poll_quarter_seconds = get_short_poll_interval(device)
  local fast_poll_timeout_quarter_seconds = get_fast_poll_timeout(device)

  local writes = {
    { name = "CheckInInterval", attr_id = PollControl.attributes.CheckInInterval.ID,
      value = data_types.Uint32(checkin_quarter_seconds) },
    { name = "ShortPollInterval", attr_id = PollControl.attributes.ShortPollInterval.ID,
      value = data_types.Uint16(short_poll_quarter_seconds) },
    { name = "FastPollTimeout", attr_id = PollControl.attributes.FastPollTimeout.ID,
      value = data_types.Uint16(fast_poll_timeout_quarter_seconds) }
  }

  log.info(string.format(
    "Applying Poll Control (%s): checkIn=%ds shortPoll=%.2fs fastTimeout=%.2fs device=%s",
    tostring(reason), checkin_seconds, short_poll_quarter_seconds / 4,
    fast_poll_timeout_quarter_seconds / 4, tostring(device.label or device.id)))

  local all_sent = true
  for _, item in ipairs(writes) do
    local ok, err = pcall(function()
      local message = cluster_base.write_attribute(
        device,
        data_types.ClusterId(PollControl.ID),
        data_types.AttributeId(item.attr_id),
        item.value)
      device:send(message)
    end)

    if not ok then
      all_sent = false
      log.error(string.format(
        "Poll Control write failed: %s error=%s",
        item.name, tostring(err)))
    end
  end

  if all_sent then
    device:set_field("pending_poll_config", false, { persist = false })
    device.thread:call_with_delay(2, function()
      read_poll_control(device, "after-write")
    end)
  else
    device:set_field("pending_poll_config", true, { persist = false })
  end
end

local function request_poll_config_when_awake(device, source)
  if device:get_field("pending_poll_config") ~= true then return end
  apply_poll_control(device, "device-awake:" .. tostring(source))
end

local function send_reads(device)
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function configure_reporting(driver, device, reason)
  local temp_min = get_temperature_min_interval(device)
  local temp_max = get_sensor_report_interval(device)
  local temp_change = get_temperature_change(device)
  local humidity_min = get_humidity_min_interval(device)
  local humidity_max = get_sensor_report_interval(device)
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
  configure_reporting(driver, device, "device-awake:" .. tostring(source))
end

local function added_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  device:set_field("pending_poll_config", true, { persist = false })
  emit_driver_information(device)
end

local function init_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  device:set_field("pending_poll_config", true, { persist = false })
  emit_driver_information(device)
end

local function do_configure_handler(driver, device)
  device:set_field("pending_reporting_config", true, { persist = false })
  device:set_field("pending_poll_config", true, { persist = false })
  send_reads(device)
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
    old.humidityReportDelta ~= device.preferences.humidityReportDelta or
    old.humidityReportMin ~= device.preferences.humidityReportMin or
    old.sensorReportInterval ~= device.preferences.sensorReportInterval

  local poll_changed =
    old.sleepCheckInInterval ~= device.preferences.sleepCheckInInterval or
    old.shortPollInterval ~= device.preferences.shortPollInterval or
    old.fastPollTimeout ~= device.preferences.fastPollTimeout

  if reporting_changed then
    device:set_field("pending_reporting_config", true, { persist = false })
  end
  if poll_changed then
    device:set_field("pending_poll_config", true, { persist = false })
  end

  if reporting_changed or poll_changed then
    send_reads(device)
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
  request_poll_config_when_awake(device, "temperature-report")

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
  request_poll_config_when_awake(device, "humidity-report")

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
      },
      [PollControl.ID] = {
        [PollControl.attributes.CheckInInterval.ID] =
          make_poll_control_attribute_handler("CheckInInterval"),
        [PollControl.attributes.ShortPollInterval.ID] =
          make_poll_control_attribute_handler("ShortPollInterval"),
        [PollControl.attributes.FastPollTimeout.ID] =
          make_poll_control_attribute_handler("FastPollTimeout")
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
