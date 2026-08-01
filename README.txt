C.P TempSensor 0.1C v1.0.8
Author: CheesePowder / ????

INSTALL
1. Extract the ZIP file completely.
2. Double-click SETUP-AND-INSTALL.cmd.
3. Select the requested SmartThings channel or hub.
4. In SmartThings, open the temperature sensor and change its driver to C.P TempSensor 0.1C.

TEST
1. Open sensor Settings.
2. Set Temperature report change to 0.1 C.
3. Run: smartthings edge:drivers:logcat
4. Select C.P TempSensor 0.1C.
5. Check whether temperature reports arrive in 0.1 C increments.

NOTE
The driver requests a 0.1 C Zigbee reporting threshold. The SONOFF firmware may ignore the request and continue reporting only at 0.5 C changes.

Changes in v1.0.8:
- Removed the optional device profile categories section.
- SmartThings rejected guessed category names Temperature and Sensor.
- The profile now contains only capabilities, preferences, and metadata.

Fingerprint added: SONOFF / SNZB-02DR2

Changes in v1.0.8:
- Added an embedded Device Configuration.
- Dashboard summary now groups temperature and humidity into the same tile.
- Preserved temperature, humidity, battery, firmware, refresh, and driver information in Detail view.
- After installation, force-close SmartThings and clear the app cache if the old tile remains cached.

Changes in v1.0.8:
- Added Humidity report change: 0.5, 1, 2, 3, or 5 percent.
- Added Humidity maximum report interval: 1, 5, 10, 15, 30, or 60 minutes.
- Reconfigures Zigbee reporting when either humidity setting changes.
- Set health_check = false to remove the deprecated Monitored Attributes warning.
- Wake the battery sensor after saving settings so the new Zigbee configuration is received.
