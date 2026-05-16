# Privacy Policy — SimpleGlance Weather Widget

**Last updated: 16 May 2026**

## Overview

SimpleGlance Weather Widget ("the app") is a Connect IQ widget that displays weather conditions for your current GPS location and a fixed home location. This policy explains what data the app accesses and how it is used.

## Data Collected

### Location Data
The app accesses your device's GPS coordinates solely to fetch weather data for your current location. Coordinates are:
- Stored temporarily on the device (Garmin Application Storage) to allow weather fetching when GPS is unavailable
- Never transmitted to any server other than the weather API described below
- Never shared with third parties

### Weather Data
Weather data is retrieved from [Open-Meteo](https://open-meteo.com), a free and open-source weather API. The only information sent to Open-Meteo is your GPS latitude and longitude (rounded to 4 decimal places). Open-Meteo does not require account registration and does not track users. See [Open-Meteo's privacy policy](https://open-meteo.com/en/terms) for details.

## Data Not Collected

The app does **not** collect, store, or transmit:
- Personal identification information
- Device identifiers
- Usage analytics or telemetry
- Any data beyond GPS coordinates for weather requests

## Data Storage

Weather data and GPS coordinates are stored locally on your Garmin device using Garmin's Application Storage API. This data is used only to display weather information and cache results between refreshes. It is not accessible to or shared with any third party.

## Third-Party Services

| Service | Purpose | Privacy Policy |
|---------|---------|----------------|
| Open-Meteo | Weather data | https://open-meteo.com/en/terms |

## Contact

For questions about this privacy policy, open an issue at:
https://github.com/Mahoneyclan/simple-garmin-weather-meteo/issues
