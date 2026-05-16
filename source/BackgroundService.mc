import Toybox.Activity;
import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;

(:background)
class BackgroundService extends Toybox.System.ServiceDelegate {

    private const GPS_NAME as String = "GPS Location";

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

    private var pending as Number = 2;
    private var gpsResult as Array? = null;
    private var samfordResult as Array? = null;

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        fetchWeather(homeLat(), homeLon(), method(:onSamfordData));

        var stored = Storage.getValue("gps_coords") as Array<Double>?;
        if (stored != null) {
            fetchWeather(stored[0], stored[1], method(:onGpsData));
        } else {
            pending = 1;
            gpsResult = null;
        }
    }

    private function fetchWeather(lat as Float or Double, lon as Float or Double, callback as Method) as Void {
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude"        => lat.format("%.4f"),
                "longitude"       => lon.format("%.4f"),
                "current"         => "temperature_2m,apparent_temperature,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation",
                "wind_speed_unit" => "kmh"
            },
            { :method => Communications.HTTP_REQUEST_METHOD_GET },
            callback
        );
    }

    function onGpsData(responseCode as Number, data as Dictionary?) as Void {
        gpsResult = parseWeather(responseCode, data, GPS_NAME);
        pending--;
        if (pending == 0) {
            Background.exit([ gpsResult, samfordResult ]);
        }
    }

    function onSamfordData(responseCode as Number, data as Dictionary?) as Void {
        samfordResult = parseWeather(responseCode, data, homeName());
        pending--;
        if (pending == 0) {
            Background.exit([ gpsResult, samfordResult ]);
        }
    }

    // Returns [temp, feelsLike, windSpeed, windGust, windDeg, locationName] or null on error
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
}
