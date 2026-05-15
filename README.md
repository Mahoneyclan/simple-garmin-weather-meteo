# Simple Garmin Weather (Open-Meteo)

A clean, minimal weather widget for Garmin Fenix watches. Displays live conditions for two locations — your current GPS position and a fixed home location (default: Samford Valley, QLD) — with a single button toggle between them.

![Widget screenshot](resources/drawables/launcher_icon.png)

## Features

- Temperature and feels-like temperature
- Wind speed, gust, and direction (arrow + compass label)
- Rainfall (mm, current hour)
- Two-location toggle (GPS ↔ Home)
- Background refresh on a configurable interval (15 / 30 / 60 min)
- Glance view showing current temperature and wind at a glance
- Offline cache — last known data shown instantly on launch
- No API key required — powered by [Open-Meteo](https://open-meteo.com) (free, no sign-up)

## Supported Devices

Fenix 5 Plus, 5S Plus, 5X Plus, Fenix 6 / 6S / 6X (all variants), Fenix 7 / 7S / 7X (all variants), Fenix 8 (43mm / 47mm / Solar)

## Navigation

| Button | Action |
|--------|--------|
| UP / DOWN | Toggle between GPS location and home location |
| SELECT | Toggle between GPS location and home location |
| MENU | Force refresh weather data |

## Settings

| Setting | Default | Options |
|---------|---------|---------|
| Background Refresh Interval | 30 min | 15 / 30 / 60 min |

Change settings via the **Garmin Connect app** on your phone → My Device → Apps & Widgets → Simple Garmin Weather.

## Home Location

The default home location is **Samford Valley, QLD, Australia** (-27.3705°S, 152.8691°E). To change it, edit the constants in `source/WeatherView.mc` and `source/BackgroundService.mc`:

```
private const SAMFORD_LAT as Float = -27.3705f;
private const SAMFORD_LON as Float = 152.8691f;
private const SAMFORD_NAME as String = "Samford Valley";
```

## Building

Requires the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (8.1+) and a developer key.

```bash
# Build for simulator
monkeyc -o bin/garminweatherwidget.prg -f monkey.jungle -y ~/.garmin_dev.der -d fenix6pro_sim -w

# Build for device
monkeyc -o bin/garminweatherwidget.prg -f monkey.jungle -y ~/.garmin_dev.der -d fenix6pro -w
```

Or use the [VS Code Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c).

## Data Source

Weather data provided by [Open-Meteo](https://open-meteo.com) — free, no API key required.

## License

MIT
