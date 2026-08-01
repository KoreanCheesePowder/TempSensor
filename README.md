# C.P TempSensor 0.1C v1.4.0

SmartThings Edge Driver for SONOFF Zigbee temperature and humidity sensors.

## Main features

- Temperature reporting down to 0.1 C
- Configurable temperature and humidity report-change thresholds
- Configurable minimum and maximum reporting intervals
- Temperature and humidity offset correction
- Configurable display precision
- Temperature and humidity shown together on the dashboard card
- SmartThings device-history compatible standard events
- Reporting configuration re-applied when a sleepy battery sensor wakes
- Battery and firmware-update capabilities retained

## Recommended responsive settings

- Temperature report change: 0.1 C
- Temperature minimum report interval: 1 second
- Temperature maximum report interval: 10 seconds
- Humidity report change: 0.5 %
- Humidity minimum report interval: 1 second
- Humidity maximum report interval: 1 minute

Aggressive reporting intervals can reduce battery life and increase Zigbee traffic.

## Installation

Run `SETUP-AND-INSTALL.cmd`, then select the channel and hub when prompted.
After installation, change the device driver in the SmartThings app.
