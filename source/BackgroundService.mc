import Toybox.Activity;
import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Background service that runs on a temporal schedule to fetch fresh weather
// data without requiring the widget UI to be open. Results are passed back
// to WeatherApp.onBackgroundData() via Background.exit().
(:background)
class BackgroundService extends Toybox.System.ServiceDelegate {

    // Read the last GPS name geocoded by WeatherView; avoids an extra request in background context.
    private function gpsStoredName() as String {
        var w = Storage.getValue("gps_weather") as Array?;
        if (w != null && w.size() > 5 && w[5] != null) { return w[5] as String; }
        return "GPS Location";
    }

    // Properties are stored as strings in resources/properties.xml because
    // Connect IQ settings only support alphaNumeric input for decimal values.
    private function homeLat() as Float {
        var v = Application.Properties.getValue("home_lat");
        return (v != null) ? (v as String).toFloat() : -27.3705f;
    }
    private function homeLon() as Float {
        var v = Application.Properties.getValue("home_lon");
        return (v != null) ? (v as String).toFloat() : 152.8691f;
    }

    // Counts outstanding HTTP requests; Background.exit() is called once all reach 0.
    private var pending           as Number      = 2;
    private var gpsResult         as Array?      = null;
    private var homeResult        as Array?      = null;
    private var gpsForecast       as Array?      = null;
    private var homeForecast      as Array?      = null;
    // Deferred home parsing: need the geocoded name before we can call parseWeather.
    private var homeLocationName  as String      = "Home";
    private var homeRawCode       as Number      = 0;
    private var homeRawData       as Dictionary? = null;

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    // Triggered by the background temporal event. Fetches weather for both
    // the home location and (if GPS coords are cached) the GPS location.
    // Also reverse-geocodes the home coordinates via Nominatim so the user
    // only needs to enter lat/lon — the place name is filled in automatically.
    // If no cached GPS coords exist, exits with null for the GPS slot so
    // WeatherView keeps showing its last known GPS data.
    function onTemporalEvent() as Void {
        var lat = homeLat();
        var lon = homeLon();
        fetchWeather(lat, lon, method(:onHomeData));
        fetchLocationName(lat, lon);

        var stored = Storage.getValue("gps_coords") as Array<Double>?;
        if (stored != null) {
            pending = 3;  // home weather + geocoding + GPS weather
            fetchWeather(stored[0], stored[1], method(:onGpsData));
        } else {
            pending = 2;  // home weather + geocoding only
            gpsResult   = null;
            gpsForecast = null;
        }
    }

    // Reverse-geocodes lat/lon via Nominatim (OpenStreetMap). On success,
    // homeLocationName is updated before home weather data is parsed.
    private function fetchLocationName(lat as Float, lon as Float) as Void {
        Communications.makeWebRequest(
            "https://nominatim.openstreetmap.org/reverse",
            {
                "lat"    => lat.format("%.4f"),
                "lon"    => lon.format("%.4f"),
                "format" => "json",
                "zoom"   => "14"
            },
            {
                :method  => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "User-Agent" => "SimpleGlanceWeatherWidget/1.0" }
            },
            method(:onLocationName)
        );
    }

    // Parses the Nominatim reverse-geocoding response. Tries address fields in
    // order of specificity; falls back to the first segment of display_name.
    function onLocationName(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null) {
            var addr = data["address"] as Dictionary?;
            var name = null;
            if (addr != null) {
                name = addr["suburb"];
                if (name == null) { name = addr["town"]; }
                if (name == null) { name = addr["city"]; }
                if (name == null) { name = addr["village"]; }
                if (name == null) { name = addr["hamlet"]; }
            }
            if (name == null) {
                var display = data["display_name"] as String?;
                if (display != null) {
                    var comma = display.find(",") as Number?;
                    name = (comma != null) ? display.substring(0, comma) : display;
                }
            }
            if (name != null) { homeLocationName = name as String; }
        }
        checkDone();
    }

    // Fire an Open-Meteo request with current conditions plus hourly/daily
    // forecast fields. past_days=1 gives yesterday for the history row;
    // forecast_days=4 covers today + 3 ahead (5 daily slots total).
    private function fetchWeather(lat as Float or Double, lon as Float or Double, callback as Method) as Void {
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude"        => lat.format("%.4f"),
                "longitude"       => lon.format("%.4f"),
                "current"         => "temperature_2m,apparent_temperature,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation,weather_code,is_day",
                "hourly"          => "temperature_2m,precipitation_probability,weather_code,precipitation,wind_speed_10m,wind_direction_10m",
                "daily"           => "temperature_2m_max,temperature_2m_min,wind_speed_10m_max,wind_direction_10m_dominant,precipitation_sum,weather_code",
                "wind_speed_unit" => "kmh",
                "forecast_days"   => "5",
                "timezone"        => "auto"
            },
            { :method => Communications.HTTP_REQUEST_METHOD_GET },
            callback
        );
    }

    function onGpsData(responseCode as Number, data as Dictionary?) as Void {
        var name    = gpsStoredName();
        gpsResult   = parseWeather(responseCode, data, name);
        gpsForecast = parseForecast(responseCode, data, name);
        checkDone();
    }

    // Store raw home response; final parsing happens in checkDone() once the
    // geocoded name is also available (callbacks can arrive in any order).
    function onHomeData(responseCode as Number, data as Dictionary?) as Void {
        homeRawCode = responseCode;
        homeRawData = data;
        checkDone();
    }

    private function checkDone() as Void {
        pending--;
        if (pending == 0) {
            homeResult   = parseWeather(homeRawCode, homeRawData, homeLocationName);
            homeForecast = parseForecast(homeRawCode, homeRawData, homeLocationName);
            Background.exit([ gpsResult, homeResult, gpsForecast, homeForecast ]);
        }
    }

    // Returns [temp, feelsLike, windSpeed, windGust, windDeg, locationName, rain] or null on error.
    private function parseWeather(responseCode as Number, data as Dictionary?, name as String) as Array? {
        if (responseCode != 200 || data == null) {
            return null;
        }
        var cur = data["current"] as Dictionary;
        var gust = cur["wind_gusts_10m"];
        if (gust == null) { gust = cur["wind_speed_10m"]; }
        var deg = cur["wind_direction_10m"];
        if (deg == null) { deg = 0; }
        var rain  = cur["precipitation"];
        if (rain == null) { rain = 0.0f; }
        var wcode = cur["weather_code"];
        if (wcode == null) { wcode = 0; }
        var isDay = cur["is_day"];
        if (isDay == null) { isDay = 1; }
        return [
            cur["temperature_2m"],       // 0: °C
            cur["apparent_temperature"], // 1: °C
            cur["wind_speed_10m"],       // 2: km/h
            gust,                        // 3: km/h
            deg,                         // 4: degrees (0=N, 90=E, ...)
            name,                        // 5: location name
            rain,                        // 6: mm
            wcode,                       // 7: WMO weather code
            isDay                        // 8: 1=day, 0=night
        ] as Array;
    }

    // Returns forecast array [name, hLabels[4], hTemps[4], hRain[4], dNames[4], dMaxT[4], dMinT[4], dWind[4], dDir[4], dRain[4]].
    // Now + 3 hours ahead; Today + 4 days ahead. Returns null on HTTP error or missing fields.
    private function parseForecast(responseCode as Number, data as Dictionary?, name as String) as Array? {
        if (responseCode != 200 || data == null) { return null; }
        var hourly = data["hourly"] as Dictionary?;
        var daily  = data["daily"]  as Dictionary?;
        if (hourly == null || daily == null) { return null; }

        var info        = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentHour = info.hour as Number;
        var hourIdx     = currentHour;

        var hourlyTemps  = hourly["temperature_2m"]            as Array;
        var hourlyRainP  = hourly["precipitation_probability"] as Array;
        var hourlyWcode  = hourly["weather_code"]              as Array?;
        var hourlyPrecip = hourly["precipitation"]             as Array?;
        var hourlyWSpd   = hourly["wind_speed_10m"]            as Array?;
        var hourlyWDir   = hourly["wind_direction_10m"]        as Array?;

        var hLabels  = new Array<String>[4];
        var hTemps   = new Array<Number>[4];
        var hRainProb = new Array<Number>[4];
        var hWcode   = new Array<Number>[4];
        var hPrecip  = new Array<Float>[4];
        var hWindSpd = new Array<Float>[4];
        var hWindDir = new Array<Number>[4];

        for (var i = 0; i < 4; i++) {
            var idx = hourIdx + i;
            var hr  = (currentHour + i) % 24;
            if (i == 0) {
                hLabels[i] = "Now";
            } else {
                var h12 = hr % 12;
                if (h12 == 0) { h12 = 12; }
                hLabels[i] = h12.format("%d") + (hr < 12 ? "a" : "p");
            }
            hTemps[i]    = Math.round(hourlyTemps[idx] as Float).toNumber();
            hRainProb[i] = (hourlyRainP  != null && hourlyRainP[idx]  != null) ? (hourlyRainP[idx]  as Number) : 0;
            hWcode[i]    = (hourlyWcode  != null && hourlyWcode[idx]   != null) ? (hourlyWcode[idx]  as Number) : 0;
            hPrecip[i]   = (hourlyPrecip != null && hourlyPrecip[idx]  != null) ? (hourlyPrecip[idx] as Float)  : 0.0f;
            hWindSpd[i]  = (hourlyWSpd   != null && hourlyWSpd[idx]    != null) ? (hourlyWSpd[idx]   as Float)  : 0.0f;
            hWindDir[i]  = (hourlyWDir   != null && hourlyWDir[idx]    != null) ? (hourlyWDir[idx]   as Number) : 0;
        }

        var dailyMax  = daily["temperature_2m_max"]            as Array;
        var dailyMin  = daily["temperature_2m_min"]            as Array;
        var dailyWind = daily["wind_speed_10m_max"]            as Array;
        var dailyDir  = daily["wind_direction_10m_dominant"]   as Array;
        var dailyRain = daily["precipitation_sum"]             as Array;
        var dailyCond = daily["weather_code"]                  as Array?;

        var dNames = new Array<String>[5];
        var dMaxT  = new Array<Number>[5];
        var dMinT  = new Array<Number>[5];
        var dWind  = new Array<Float>[5];
        var dDir   = new Array<Number>[5];
        var dRain  = new Array<Float>[5];
        var dCond  = new Array<Number>[5];

        var todayDow = info.day_of_week as Number;
        var dayAbbr  = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

        for (var i = 0; i < 5; i++) {
            if (i == 0) { dNames[i] = "Today"; }
            else {
                var dow = (todayDow + i - 1) % 7;
                dNames[i] = dayAbbr[dow];
            }
            dMaxT[i] = (dailyMax[i]  != null) ? Math.round(dailyMax[i]  as Float).toNumber() : 0;
            dMinT[i] = (dailyMin[i]  != null) ? Math.round(dailyMin[i]  as Float).toNumber() : 0;
            dWind[i] = (dailyWind[i] != null) ? (dailyWind[i] as Float)  : 0.0f;
            dDir[i]  = (dailyDir[i]  != null) ? (dailyDir[i]  as Number) : 0;
            dRain[i] = (dailyRain[i] != null) ? (dailyRain[i] as Float)  : 0.0f;
            dCond[i] = (dailyCond != null && dailyCond[i] != null) ? (dailyCond[i] as Number) : 0;
        }

        return [name, hLabels, hTemps, hRainProb, dNames, dMaxT, dMinT, dWind, dDir, dRain,
                dCond, hWcode, hPrecip, hWindSpd, hWindDir] as Array;
    }
}
