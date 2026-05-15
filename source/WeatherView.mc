import Toybox.Activity;
import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.Weather;
import Toybox.WatchUi;

class WeatherView extends WatchUi.View {

    private const SAMFORD_LAT as Float = -27.3705f;
    private const SAMFORD_LON as Float = 152.8691f;
    private const SAMFORD_NAME as String = "Samford Valley";
    private const GPS_NAME     as String = "GPS Location";

    // 0 = GPS location, 1 = Samford Valley
    var locationIndex as Number = 0;

    private var gpsData    as Array? = null;
    private var samfordData as Array? = null;
    private var gpsRequested as Boolean = false;

    private var refreshTimer as Timer.Timer = new Timer.Timer();
    private var retryTimer  as Timer.Timer = new Timer.Timer();
    private var retryCount  as Number = 3;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        System.println("[WeatherView] onLayout: loading cached data and calling fetchAll");
        gpsData     = Storage.getValue("gps_weather") as Array?;
        samfordData = Storage.getValue("samford_weather") as Array?;
        System.println("[WeatherView] onLayout: gpsData=" + (gpsData != null ? "cached" : "null") + " samfordData=" + (samfordData != null ? "cached" : "null"));
        fetchAll();
    }

    function onShow() as Void {
        refreshTimer.start(method(:onRefreshTimer), 10000, true);
    }

    function onHide() as Void {
        refreshTimer.stop();
        retryTimer.stop();
    }

    function onRefreshTimer() as Void {
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------
    // Location detection (4-tier fallback)
    // ---------------------------------------------------------------
    private function getGpsCoords() as Array<Double>? {
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var pos = info.position.toDegrees();
            if (pos[0] > -90.0 && pos[0] < 90.0) {
                Storage.setValue("gps_coords", pos);
                return pos;
            }
        }

        var act = Activity.getActivityInfo();
        if (act != null && act.currentLocation != null) {
            var pos = act.currentLocation.toDegrees();
            Storage.setValue("gps_coords", pos);
            return pos;
        }

        if (Toybox has :Weather) {
            var cond = Weather.getCurrentConditions();
            if (cond != null && cond.observationLocationPosition != null) {
                var pos = cond.observationLocationPosition.toDegrees();
                Storage.setValue("gps_coords", pos);
                return pos;
            }
        }

        return Storage.getValue("gps_coords") as Array<Double>?;
    }

    // ---------------------------------------------------------------
    // Fetching
    // ---------------------------------------------------------------
    function fetchAll() as Void {
        System.println("[WeatherView] fetchAll: starting requests");
        retryCount = 3;
        fetchSamford();

        var coords = getGpsCoords();
        if (coords != null) {
            System.println("[WeatherView] fetchAll: GPS coords available lat=" + coords[0] + " lon=" + coords[1]);
            fetchWeather(coords[0], coords[1], method(:onGpsResponse));
        } else if (!gpsRequested) {
            System.println("[WeatherView] fetchAll: no GPS coords, requesting one-shot location");
            gpsRequested = true;
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        } else {
            // Previous one-shot didn't resolve — reset so next refresh cycle tries again
            System.println("[WeatherView] fetchAll: resetting GPS request flag for next cycle");
            gpsRequested = false;
        }
    }

    private function fetchSamford() as Void {
        fetchWeather(SAMFORD_LAT, SAMFORD_LON, method(:onSamfordResponse));
    }

    private function fetchWeather(lat, lon, callback as Method) as Void {
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

    function onPosition(info as Position.Info) as Void {
        gpsRequested = false;
        if (info != null && info.position != null) {
            var pos = info.position.toDegrees();
            Storage.setValue("gps_coords", pos);
            fetchWeather(pos[0], pos[1], method(:onGpsResponse));
        }
        WatchUi.requestUpdate();
    }

    function onGpsResponse(responseCode as Number, data as Dictionary?) as Void {
        System.println("[WeatherView] onGpsResponse: responseCode=" + responseCode);
        if (responseCode == 200 && data != null) {
            gpsData = parseWeather(data, GPS_NAME);
            Storage.setValue("gps_weather", gpsData);
            System.println("[WeatherView] onGpsResponse: parsed OK temp=" + gpsData[0] + " wind=" + gpsData[2]);
            WatchUi.requestUpdate();
        } else if (responseCode <= 0 && retryCount > 0) {
            System.println("[WeatherView] onGpsResponse: network error, retrying (retryCount=" + retryCount + ")");
            retryCount--;
            retryTimer.start(method(:fetchAll), 5000, false);
        } else {
            System.println("[WeatherView] onGpsResponse: failed, no retry. data=" + (data != null ? "present" : "null"));
        }
    }

    function onSamfordResponse(responseCode as Number, data as Dictionary?) as Void {
        System.println("[WeatherView] onSamfordResponse: responseCode=" + responseCode);
        if (responseCode == 200 && data != null) {
            samfordData = parseWeather(data, SAMFORD_NAME);
            Storage.setValue("samford_weather", samfordData);
            System.println("[WeatherView] onSamfordResponse: parsed OK temp=" + samfordData[0] + " wind=" + samfordData[2]);
            WatchUi.requestUpdate();
        } else {
            System.println("[WeatherView] onSamfordResponse: failed. data=" + (data != null ? "present" : "null"));
        }
    }

    // Returns [temp, feelsLike, windSpeed, windGust, windDeg, name, rain]
    // windSpeed and windGust are already in km/h from Open-Meteo
    private function parseWeather(data as Dictionary, name as String) as Array {
        var cur = data["current"] as Dictionary;
        var gust = cur["wind_gusts_10m"];
        if (gust == null) { gust = cur["wind_speed_10m"]; }
        var deg = cur["wind_direction_10m"];
        if (deg == null) { deg = 0; }
        var rain = cur["precipitation"];
        if (rain == null) { rain = 0.0f; }
        return [
            cur["temperature_2m"],
            cur["apparent_temperature"],
            cur["wind_speed_10m"],
            gust,
            deg,
            name,
            rain
        ] as Array;
    }

    // ---------------------------------------------------------------
    // Drawing
    // ---------------------------------------------------------------
    function onUpdate(dc as Dc) as Void {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var W = dc.getWidth();
        var H = dc.getHeight();

        var weather = locationIndex == 0 ? gpsData : samfordData;

        if (weather == null) {
            if (locationIndex == 0 && getGpsCoords() == null) {
                drawCentered(dc, W, H, "Waiting for\nGPS location...");
            } else {
                drawCentered(dc, W, H, "Loading\nweather...");
            }
        } else {
            drawWeather(dc, W, H, weather);
        }

        drawIndicator(dc, W, H);
    }

    private function drawWeather(dc as Dc, W as Number, H as Number, w as Array) as Void {
        var temp   = Math.round(w[0] as Float).toNumber();
        var feels  = Math.round(w[1] as Float).toNumber();
        var speed  = (w[2] as Float);   // already km/h
        var gust   = (w[3] as Float);
        var wdeg   = (w[4] as Number or Float).toFloat();
        var name   = w[5] as String;
        var rain   = w.size() > 6 ? (w[6] as Float) : 0.0f;

        // Location name
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, (H * 0.08).toNumber(), Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Temperature — number in large font, "°C" in small font superscripted
        // FONT_NUMBER_MEDIUM only supports digits; °C must be drawn separately
        var tempStr = temp.format("%d");
        var numW = dc.getTextWidthInPixels(tempStr, Graphics.FONT_NUMBER_MEDIUM);
        var unitW = dc.getTextWidthInPixels("°C", Graphics.FONT_SMALL);
        var numX = (W - numW - unitW) / 2;
        var numY = (H * 0.32).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(numX, numY, Graphics.FONT_NUMBER_MEDIUM,
            tempStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(numX + numW + 2, numY - (H * 0.05).toNumber(), Graphics.FONT_SMALL,
            "°C", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Feels like
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, (H * 0.50).toNumber(), Graphics.FONT_SMALL,
            "Feels " + feels.format("%d") + "°C", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Separator
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((W * 0.2).toNumber(), (H * 0.58).toNumber(),
                    (W * 0.8).toNumber(), (H * 0.58).toNumber());

        // Wind (left column) | Rain (right column)
        var colL = (W * 0.32).toNumber();
        var colR = (W * 0.68).toNumber();

        // Column labels
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, (H * 0.63).toNumber(), Graphics.FONT_TINY, "WIND",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(colR, (H * 0.63).toNumber(), Graphics.FONT_TINY, "RAIN",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Values
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, (H * 0.71).toNumber(), Graphics.FONT_SMALL,
            speed.format("%.0f") + " km/h",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(colR, (H * 0.71).toNumber(), Graphics.FONT_SMALL,
            rain.format("%.1f") + " mm",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Gust sub-label
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, (H * 0.78).toNumber(), Graphics.FONT_TINY,
            "gust " + gust.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Wind direction arrow (under WIND column) + compass label (under RAIN column)
        var arrowSize = (H * 0.09).toNumber();
        var arrowCx   = colL.toFloat();
        var arrowCy   = (H * 0.86).toNumber().toFloat();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(windArrow(arrowCx, arrowCy, wdeg + 180.0f, arrowSize));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colR, (H * 0.86).toNumber(), Graphics.FONT_SMALL,
            windDirName(wdeg), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Indicator dots: left = GPS, right = Samford Valley
    private function drawIndicator(dc as Dc, W as Number, H as Number) as Void {
        var r  = (W * 0.027).toNumber();
        var cy = (H * 0.92).toNumber();
        var gap = r * 3;
        var cx0 = W / 2 - gap / 2;
        var cx1 = W / 2 + gap / 2;

        if (locationIndex == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx0, cy, r);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx1, cy, r);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx0, cy, r);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx1, cy, r);
        }
    }

    private function drawCentered(dc as Dc, W as Number, H as Number, text as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, H / 2, Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Draws a wind-vane arrow whose visual centre is at (cx, cy).
// angle = 0 points up; wind convention: pass (windDeg + 180) to show direction of travel.
function windArrow(cx as Float, cy as Float, angle as Float, size as Number) as Array<Graphics.Point2D> {
    var half = size / 2.0f;
    var coords = [
        [ 0.0f,   half],
        [ size * 0.07f,  -half * 0.50f],
        [ size * 0.30f,  -half * 0.30f],
        [ 0.0f,  -half],
        [-size * 0.30f,  -half * 0.30f],
        [-size * 0.07f,  -half * 0.50f]
    ];
    var result = new Array<Graphics.Point2D>[coords.size()];
    var rad = Math.toRadians(angle);
    var cos = Math.cos(rad);
    var sin = Math.sin(rad);
    for (var i = 0; i < coords.size(); i++) {
        var x = (coords[i][0] * cos) - (coords[i][1] * sin);
        var y = (coords[i][0] * sin) + (coords[i][1] * cos);
        result[i] = [(cx + x).toNumber(), (cy + y).toNumber()] as Graphics.Point2D;
    }
    return result;
}

(:glance)
function windDirName(deg as Float) as String {
    var d = (deg.toNumber() % 360).toFloat();
    if (d < 0.0f) { d += 360.0f; }
    if (d < 22.5f)  { return "N";   }
    if (d < 67.5f)  { return "NE";  }
    if (d < 112.5f) { return "E";   }
    if (d < 157.5f) { return "SE";  }
    if (d < 202.5f) { return "S";   }
    if (d < 247.5f) { return "SW";  }
    if (d < 292.5f) { return "W";   }
    if (d < 337.5f) { return "NW";  }
    return "N";
}
