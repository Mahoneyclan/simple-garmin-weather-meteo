# SimpleGlance Weather Widget (Open-Meteo)

![Widget on Fenix 6 Pro](image-generators/screenshot_samford_watch.png)

A clean, minimal weather widget for Garmin Fenix watches. Displays live conditions for two locations — your current GPS position and a configurable home location — with a single button toggle between them.

| GPS Location | Home Location |
|:---:|:---:|
| ![GPS view](image-generators/screenshot_gps.png) | ![Samford Valley view](image-generators/screenshot_samford.png) |

## Features

- Radial watch face layout — temperature (top), rain (bottom-left), wind (bottom-right)
- Temperature and feels-like temperature
- Wind speed, gust, direction arrow and compass label
- Rainfall (mm, current hour)
- Forecast page: Now + 3 hours ahead (temp, rain probability) and Today + 3 days ahead (max/min temp, wind, rain)
- Two-location toggle (GPS ↔ Home) with indicator dots showing active location
- Background refresh on a configurable interval (15 / 30 / 60 min)
- Glance view showing current temperature, rainfall and wind at a glance
- Offline cache — last known data shown instantly on launch
- No API key required — powered by [Open-Meteo](https://open-meteo.com) (free, no sign-up)

## Supported Devices

Fenix 6, Fenix 6 Pro, Fenix 6S, Fenix 6S Pro

## Navigation

| Button | Action |
|--------|--------|
| UP / DOWN | Toggle between current conditions and forecast |
| SELECT | Toggle between GPS location and home location |
| MENU | Force refresh weather data |

The two dots at the bottom of the screen indicate the active location: left dot = GPS, right dot = Home.

## Settings

| Setting | Default | Options |
|---------|---------|---------|
| Background Refresh Interval | 30 min | 15 / 30 / 60 min |
| Home Location Name | Samford Valley | Any text (max 32 chars) |
| Home Latitude | -27.3705 | Decimal degrees (e.g. -27.3705) |
| Home Longitude | 152.8691 | Decimal degrees (e.g. 152.8691) |

Change settings via the **Garmin Connect app** on your phone → My Device → Apps & Widgets → SimpleGlance Weather Widget.

## Architecture

**BackgroundService.mc** — Runs on a timer even when the widget is closed. Fetches weather from Open-Meteo for both GPS and home locations, parses responses into compact arrays, and passes them to `WeatherApp` via `Background.exit()`. Never draws anything.

**WeatherApp.mc** — App entry point and coordinator. Launches the initial view, schedules/re-schedules the background fetch timer, and receives data from `BackgroundService` — writing it into persistent `Storage` for `WeatherView` to consume. Re-schedules the timer and triggers a redraw when settings change.

**WeatherDelegate.mc** — Button handler. UP/DOWN toggles between the current-conditions and forecast pages. SELECT toggles between GPS and home location. MENU forces an immediate data refresh. No drawing or networking.

**WeatherGlanceView.mc** — The small preview shown in the watch glance loop. Reads `gps_weather` from `Storage` and renders a one-line summary: location name, temperature, rainfall, and wind. GPS location only — the glance surface is too small for both.

**WeatherView.mc** — The full-screen widget UI. Fetches live data (with GPS fallback chain and retry logic), parses API responses, caches to `Storage`, and draws both the current-conditions page (radial 3-sector layout) and the forecast page (hourly strip + daily rows). Owns the 10-second refresh timer.

## Building

Requires the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (8.1+) and a developer key.

```bash
# Build for simulator
monkeyc -o bin/simpleglanceweatherwidget.prg -f monkey.jungle -y ~/.garmin_dev.der -d fenix6pro_sim -w

# Build for device
monkeyc -o bin/simpleglanceweatherwidget.prg -f monkey.jungle -y ~/.garmin_dev.der -d fenix6pro -w
```

Or use the [VS Code Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c).

## Data Source

Weather data provided by [Open-Meteo](https://open-meteo.com) — free, no API key required.

## License

© 2026 Mahoneyclan. All rights reserved.
