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

    private const GPS_NAME as String = "GPS Location";

    // Properties are stored as strings in resources/properties.xml because
    // Connect IQ settings only support alphaNumeric input for decimal values.
    private function homeName() as String {
        var v = Application.Properties.getValue("home_name");
        return (v != null) ? v as String : "Home";
    }
    private function homeLat() as Float {
        var v = Application.Properties.getValue("home_lat");
        return (v != null) ? (v as String).toFloat() : -27.3705f;
    }
    private function homeLon() as Float {
        var v = Application.Properties.getValue("home_lon");
        return (v != null) ? (v as String).toFloat() : 152.8691f;
    }

    // Counts outstanding HTTP requests; Background.exit() is called once both reach 0.
    private var pending          as Number = 2;
    private var gpsResult        as Array? = null;
    private var homeResult       as Array? = null;
    private var gpsForecast      as Array? = null;
    private var homeForecast     as Array? = null;

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    // Triggered by the background temporal event. Fetches weather for both
    // the home location and (if GPS coords are cached) the GPS location.
    // If no cached GPS coords exist, exits with null for the GPS slot so
    // WeatherView keeps showing its last known GPS data.
    function onTemporalEvent() as Void {
        fetchWeather(homeLat(), homeLon(), method(:onHomeData));

        var stored = Storage.getValue("gps_coords") as Array<Double>?;
        if (stored != null) {
            fetchWeather(stored[0], stored[1], method(:onGpsData));
        } else {
            pending = 1;
            gpsResult  = null;
            gpsForecast = null;
        }
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
                "current"         => "temperature_2m,apparent_temperature,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation",
                "hourly"          => "temperature_2m,precipitation_probability",
                "daily"           => "temperature_2m_max,temperature_2m_min,wind_speed_10m_max,wind_direction_10m_dominant,precipitation_sum",
                "wind_speed_unit" => "kmh",
                "forecast_days"   => "4",
                "timezone"        => "auto"
            },
            { :method => Communications.HTTP_REQUEST_METHOD_GET },
            callback
        );
    }

    function onGpsData(responseCode as Number, data as Dictionary?) as Void {
        gpsResult   = parseWeather(responseCode, data, GPS_NAME);
        gpsForecast = parseForecast(responseCode, data, GPS_NAME);
        pending--;
        if (pending == 0) {
            Background.exit([ gpsResult, homeResult, gpsForecast, homeForecast ]);
        }
    }

    function onHomeData(responseCode as Number, data as Dictionary?) as Void {
        homeResult   = parseWeather(responseCode, data, homeName());
        homeForecast = parseForecast(responseCode, data, homeName());
        pending--;
        if (pending == 0) {
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
        var rain = cur["precipitation"];
        if (rain == null) { rain = 0.0f; }
        return [
            cur["temperature_2m"],       // 0: °C
            cur["apparent_temperature"], // 1: °C
            cur["wind_speed_10m"],       // 2: km/h
            gust,                        // 3: km/h
            deg,                         // 4: degrees (0=N, 90=E, ...)
            name,                        // 5: location name
            rain                         // 6: mm
        ] as Array;
    }

    // Returns forecast array [name, hLabels[4], hTemps[4], hRain[4], dNames[4], dMaxT[4], dMinT[4], dWind[4], dDir[4], dRain[4]].
    // Now + 3 hours ahead; Today + 3 days ahead. Returns null on HTTP error or missing fields.
    private function parseForecast(responseCode as Number, data as Dictionary?, name as String) as Array? {
        if (responseCode != 200 || data == null) { return null; }
        var hourly = data["hourly"] as Dictionary?;
        var daily  = data["daily"]  as Dictionary?;
        if (hourly == null || daily == null) { return null; }

        // With no past_days, hourly[0] = today 00:00 local.
        // The current hour therefore sits at index currentHour.
        var info        = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentHour = info.hour as Number;
        var hourIdx     = currentHour;

        var hourlyTemps = hourly["temperature_2m"]           as Array;
        var hourlyRain  = hourly["precipitation_probability"] as Array;

        var hLabels = new Array<String>[4];
        var hTemps  = new Array<Number>[4];
        var hRain   = new Array<Number>[4];

        for (var i = 0; i < 4; i++) {
            var idx = hourIdx + i;
            var hr  = (currentHour + i) % 24;
            hLabels[i] = (i == 0) ? "Now" : hr.format("%02d");
            hTemps[i]  = Math.round(hourlyTemps[idx] as Float).toNumber();
            hRain[i]   = (hourlyRain[idx] != null) ? (hourlyRain[idx] as Number) : 0;
        }

        var dailyMax  = daily["temperature_2m_max"]            as Array;
        var dailyMin  = daily["temperature_2m_min"]            as Array;
        var dailyWind = daily["wind_speed_10m_max"]            as Array;
        var dailyDir  = daily["wind_direction_10m_dominant"]   as Array;
        var dailyRain = daily["precipitation_sum"]             as Array;

        var dNames = new Array<String>[4];
        var dMaxT  = new Array<Number>[4];
        var dMinT  = new Array<Number>[4];
        var dWind  = new Array<Float>[4];
        var dDir   = new Array<Number>[4];
        var dRain  = new Array<Float>[4];

        // day_of_week: 1=Sun, 2=Mon, ..., 7=Sat
        var todayDow = info.day_of_week as Number;
        var dayAbbr  = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]; // 0-indexed

        for (var i = 0; i < 4; i++) {
            if (i == 0) { dNames[i] = "Today"; }
            else {
                // i=1 → tomorrow, i=2 → +2d, i=3 → +3d
                var dow = (todayDow + i - 1) % 7; // 0-indexed into dayAbbr
                dNames[i] = dayAbbr[dow];
            }
            dMaxT[i] = (dailyMax[i]  != null) ? Math.round(dailyMax[i]  as Float).toNumber() : 0;
            dMinT[i] = (dailyMin[i]  != null) ? Math.round(dailyMin[i]  as Float).toNumber() : 0;
            dWind[i] = (dailyWind[i] != null) ? (dailyWind[i] as Float)  : 0.0f;
            dDir[i]  = (dailyDir[i]  != null) ? (dailyDir[i]  as Number) : 0;
            dRain[i] = (dailyRain[i] != null) ? (dailyRain[i] as Float)  : 0.0f;
        }

        // Structure: [name, hLabels, hTemps, hRain, dNames, dMaxT, dMinT, dWind, dDir, dRain]
        return [name, hLabels, hTemps, hRain, dNames, dMaxT, dMinT, dWind, dDir, dRain] as Array;
    }
}
