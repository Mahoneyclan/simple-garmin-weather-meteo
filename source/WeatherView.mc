import Toybox.Activity;
import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Full-screen weather view. Manages fetching, caching, and drawing for both
// the GPS location and the user-configured home location across three pages:
//   0 = GPS current conditions
//   1 = Home current conditions
//   2 = Forecast (GPS or Home, toggled by SELECT)
class WeatherView extends WatchUi.View {

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

    // Active page: 0=current conditions, 1=forecast
    var pageIndex as Number = 0;
    // Active location: 0=GPS, 1=home — applies to both pages
    var locationIndex as Number = 0;

    private var gpsData      as Array? = null;
    private var homeData     as Array? = null;
    private var gpsForecast  as Array? = null;
    private var homeForecast as Array? = null;
    // Guard flag: prevents firing a second one-shot GPS request while one is already pending.
    private var gpsRequested as Boolean = false;

    // Redraws the screen every 10 s while the widget is visible so elapsed
    // time and any background data arrival are reflected without user input.
    private var refreshTimer as Timer.Timer = new Timer.Timer();
    // Single-shot timer used to delay a retry after a network error.
    private var retryTimer   as Timer.Timer = new Timer.Timer();
    private var retryCount   as Number = 3;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        System.println("[WeatherView] onLayout: loading cached data");
        gpsData      = Storage.getValue("gps_weather")  as Array?;
        homeData     = Storage.getValue("home_weather")  as Array?;
        gpsForecast  = Storage.getValue("gps_forecast")  as Array?;
        homeForecast = Storage.getValue("home_forecast") as Array?;
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

    // Returns cached or live GPS coordinates. Tries four sources in order:
    //   1. Position API (live fix)
    //   2. Active activity location
    //   3. Garmin Weather observation position
    //   4. Last value saved to Storage
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

    // Fetch current conditions and forecast for both locations.
    // Retries up to 3 times on network error with a 5 s delay.
    function fetchAll() as Void {
        System.println("[WeatherView] fetchAll: starting requests");
        retryCount = 3;
        fetchHome();

        var coords = getGpsCoords();
        if (coords != null) {
            System.println("[WeatherView] fetchAll: GPS coords lat=" + coords[0] + " lon=" + coords[1]);
            fetchWeather(coords[0], coords[1], method(:onGpsResponse));
        } else if (!gpsRequested) {
            System.println("[WeatherView] fetchAll: requesting one-shot GPS location");
            gpsRequested = true;
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        } else {
            // Previous one-shot didn't resolve — reset so next refresh cycle tries again
            System.println("[WeatherView] fetchAll: resetting GPS request flag for next cycle");
            gpsRequested = false;
        }
    }

    // Fetch weather for the user-configured home location.
    private function fetchHome() as Void {
        fetchWeather(homeLat(), homeLon(), method(:onHomeResponse));
    }

    // Fire an Open-Meteo request with current conditions plus hourly/daily
    // forecast fields. past_days=1 gives yesterday for the history row;
    // forecast_days=4 covers today + 3 ahead (5 daily slots total).
    private function fetchWeather(lat, lon, callback as Method) as Void {
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
            gpsForecast = parseForecast(data, GPS_NAME, gpsData);
            Storage.setValue("gps_forecast", gpsForecast);
            WatchUi.requestUpdate();
        } else if (responseCode <= 0 && retryCount > 0) {
            System.println("[WeatherView] onGpsResponse: network error, retrying (retryCount=" + retryCount + ")");
            retryCount--;
            retryTimer.start(method(:fetchAll), 5000, false);
        } else {
            System.println("[WeatherView] onGpsResponse: failed. data=" + (data != null ? "present" : "null"));
        }
    }

    function onHomeResponse(responseCode as Number, data as Dictionary?) as Void {
        System.println("[WeatherView] onHomeResponse: responseCode=" + responseCode);
        if (responseCode == 200 && data != null) {
            homeData = parseWeather(data, homeName());
            Storage.setValue("home_weather", homeData);
            homeForecast = parseForecast(data, homeName(), homeData);
            Storage.setValue("home_forecast", homeForecast);
            WatchUi.requestUpdate();
        } else {
            System.println("[WeatherView] onHomeResponse: failed. data=" + (data != null ? "present" : "null"));
        }
    }

    // Returns [temp, feelsLike, windSpeed, windGust, windDeg, name, rain]
    // windSpeed and windGust are already in km/h from Open-Meteo (wind_speed_unit=kmh)
    private function parseWeather(data as Dictionary, name as String) as Array {
        var cur  = data["current"] as Dictionary;
        var gust = cur["wind_gusts_10m"];
        if (gust == null) { gust = cur["wind_speed_10m"]; } // gust not always reported
        var deg  = cur["wind_direction_10m"];
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

    // Returns a forecast array or null if data is missing.
    //
    // Structure:
    //   [0] name        String
    //   [1] hLabels     Array<String>[4]  hour labels: "Now", "+1h", "+2h", "+3h"
    //   [2] hTemps      Array<Number>[4]  hourly temps °C
    //   [3] hRain       Array<Number>[4]  hourly precipitation probability %
    //   [4] dNames      Array<String>[4]  day labels: "Today", "Mon", "Tue", "Wed"
    //   [5] dMaxT       Array<Number>[4]  daily max temp °C
    //   [6] dMinT       Array<Number>[4]  daily min temp °C
    //   [7] dWind       Array<Float>[4]   daily max wind km/h
    //   [8] dDir        Array<Number>[4]  daily dominant wind direction degrees
    //   [9] dRain       Array<Float>[4]   daily precipitation sum mm
    //
    // With no past_days, hourly[0] = today 00:00 local, so current hour = index currentHour.
    // Daily index 0=today, 1=tomorrow, 2=+2d, 3=+3d.
    private function parseForecast(data as Dictionary, name as String, current as Array?) as Array? {
        var hourly = data["hourly"] as Dictionary?;
        var daily  = data["daily"]  as Dictionary?;
        if (hourly == null || daily == null) { return null; }

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
            // "Now" temp comes from live current data so it matches the current-conditions page
            hTemps[i] = (i == 0 && current != null)
                ? Math.round(current[0] as Float).toNumber()
                : Math.round(hourlyTemps[idx] as Float).toNumber();
            hRain[i] = (hourlyRain[idx] != null) ? (hourlyRain[idx] as Number) : 0;
        }

        var dailyMax  = daily["temperature_2m_max"]          as Array;
        var dailyMin  = daily["temperature_2m_min"]          as Array;
        var dailyWind = daily["wind_speed_10m_max"]          as Array;
        var dailyDir  = daily["wind_direction_10m_dominant"] as Array;
        var dailyRain = daily["precipitation_sum"]           as Array;

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
                // i=1→tomorrow, formula: (todayDow + i - 1) % 7 → 0-indexed dow
                var dow = (todayDow + i - 1) % 7;
                dNames[i] = dayAbbr[dow];
            }
            dMaxT[i] = (dailyMax[i]  != null) ? Math.round(dailyMax[i]  as Float).toNumber() : 0;
            dMinT[i] = (dailyMin[i]  != null) ? Math.round(dailyMin[i]  as Float).toNumber() : 0;
            dWind[i] = (dailyWind[i] != null) ? (dailyWind[i] as Float)  : 0.0f;
            dDir[i]  = (dailyDir[i]  != null) ? (dailyDir[i]  as Number) : 0;
            dRain[i] = (dailyRain[i] != null) ? (dailyRain[i] as Float)  : 0.0f;
        }

        return [name, hLabels, hTemps, hRain, dNames, dMaxT, dMinT, dWind, dDir, dRain] as Array;
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

        if (pageIndex == 1) {
            drawForecastPage(dc, W, H);
        } else {
            var weather = locationIndex == 0 ? gpsData : homeData;
            if (weather == null) {
                if (locationIndex == 0 && getGpsCoords() == null) {
                    drawCentered(dc, W, H, "Waiting for\nGPS location...");
                } else {
                    drawCentered(dc, W, H, "Loading\nweather...");
                }
            } else {
                drawWeather(dc, W, H, weather);
            }
        }

        drawIndicator(dc, W, H);
    }

    // Layout: three equal 120° radial sectors from the centre.
    //   Top sector    (300°–60°)  : temperature + feels like
    //   Bottom-left   (180°–300°) : rain
    //   Bottom-right  (60°–180°)  : wind speed, gust, direction
    private function drawWeather(dc as Dc, W as Number, H as Number, w as Array) as Void {
        var temp  = Math.round(w[0] as Float).toNumber();
        var feels = Math.round(w[1] as Float).toNumber();
        var speed = (w[2] as Float);
        var gust  = (w[3] as Float);
        var wdeg  = (w[4] as Number or Float).toFloat();
        var name  = w[5] as String;
        var rain  = w.size() > 6 ? (w[6] as Float) : 0.0f;

        var cx = W / 2;
        var cy = H / 2;

        // ── Radial dividing lines ────────────────────────────────────
        // Three lines from centre at 60°, 180° (straight down), 300° from top.
        // R = 92% of half-width keeps lines clear of the bezel.
        var R  = (W * 0.46f).toNumber();
        var dx = (R * 0.866f).toNumber(); // R × sin(60°)
        var dy = (R * 0.500f).toNumber(); // R × cos(60°)
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy, cx + dx, cy - dy); // upper-right (60°)
        dc.drawLine(cx, cy, cx,      cy + R);  // straight down (180°)
        dc.drawLine(cx, cy, cx - dx, cy - dy); // upper-left (300°)

        // ── TOP SECTOR: Temperature ──────────────────────────────────
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (H * 0.10).toNumber(), Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // FONT_NUMBER_MEDIUM only supports digits; °C drawn separately as superscript
        var tempStr = temp.format("%d");
        var numW    = dc.getTextWidthInPixels(tempStr, Graphics.FONT_NUMBER_MEDIUM);
        var unitW   = dc.getTextWidthInPixels("°C", Graphics.FONT_SMALL);
        var numX    = (W - numW - unitW) / 2;
        var numY    = (H * 0.23).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(numX, numY, Graphics.FONT_NUMBER_MEDIUM,
            tempStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(numX + numW + 2, numY - (H * 0.05).toNumber(), Graphics.FONT_SMALL,
            "°C", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (H * 0.36).toNumber(), Graphics.FONT_XTINY,
            "Feels " + feels.format("%d") + "°C",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── BOTTOM-LEFT SECTOR: Rain ─────────────────────────────────
        // Sector centre at angle 240° from top, positioned at ~27% of width
        var rainX = (W * 0.27).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rainX, (H * 0.52).toNumber(), Graphics.FONT_TINY, "RAIN",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rainX, (H * 0.64).toNumber(), Graphics.FONT_SMALL,
            rain.format("%.1f") + " mm",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── BOTTOM-RIGHT SECTOR: Wind ────────────────────────────────
        // Sector centre at angle 120° from top, positioned at ~73% of width
        var windX = (W * 0.73).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(windX, (H * 0.52).toNumber(), Graphics.FONT_TINY, "WIND",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(windX, (H * 0.61).toNumber(), Graphics.FONT_SMALL,
            speed.format("%.0f") + " km/h",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(windX, (H * 0.70).toNumber(), Graphics.FONT_TINY,
            "gust " + gust.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Arrow + compass label centred together under the wind speed text (windX).
        var arrowSize  = (H * 0.07).toNumber();
        var arrowY     = (H * 0.82).toNumber();
        var half       = arrowSize / 2;
        var compassStr = windDirName(wdeg);
        var textW      = dc.getTextWidthInPixels(compassStr, Graphics.FONT_TINY);
        var totalW     = arrowSize + 4 + textW;
        var startX     = windX - totalW / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(windArrow((startX + half).toFloat(), arrowY.toFloat(),
                                  wdeg + 180.0f, arrowSize));
        dc.drawText(startX + arrowSize + 4, arrowY, Graphics.FONT_TINY,
            compassStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------
    // Forecast page
    // ---------------------------------------------------------------

    private function drawForecastPage(dc as Dc, W as Number, H as Number) as Void {
        var forecast = locationIndex == 0 ? gpsForecast : homeForecast;
        var current  = locationIndex == 0 ? gpsData     : homeData;

        if (forecast == null) {
            drawCentered(dc, W, H, "Loading\nforecast...");
            return;
        }

        var name    = forecast[0] as String;
        var hLabels = forecast[1] as Array;
        var hTemps  = forecast[2] as Array;
        var hRain   = forecast[3] as Array;
        var dNames  = forecast[4] as Array;
        var dMaxT   = forecast[5] as Array;
        var dMinT   = forecast[6] as Array;
        var dWind   = forecast[7] as Array;
        var dDir    = forecast[8] as Array;
        var dRain   = forecast[9] as Array;

        // Override "Now" temp with live current data if available
        var nowTemp = (current != null)
            ? Math.round(current[0] as Float).toNumber()
            : (hTemps[0] as Number);

        // 4px downward nudge so the title clears the top of the circular bezel.
        var yOff = 4;

        // --- Location name ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, (H * 0.07).toNumber() + yOff, Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Top separator ---
        // Narrowed to 22%-78%: at y=H*0.13 the circle half-width is only ~72px (centre±72).
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((W * 0.22).toNumber(), (H * 0.13).toNumber() + yOff,
                    (W * 0.78).toNumber(), (H * 0.13).toNumber() + yOff);

        // --- Hourly strip: 4 evenly-spaced columns (Now, +1h, +2h, +3h) ---
        // Columns at 20%, 40%, 60%, 80% — keeps content inside the circle at the top of the screen.
        var hourlyY0 = (H * 0.20).toNumber() + yOff; // hour labels
        var hourlyY1 = (H * 0.28).toNumber() + yOff; // temperatures
        var hourlyY2 = (H * 0.35).toNumber() + yOff; // rain probability

        for (var i = 0; i < 4; i++) {
            var cx = (W * (0.20 + i * 0.20)).toNumber();
            var temp = (i == 0) ? nowTemp : (hTemps[i] as Number);

            // Hour label — "Now" in white, others in gray
            dc.setColor((i == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, hourlyY0, Graphics.FONT_TINY,
                hLabels[i] as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Temperature
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, hourlyY1, Graphics.FONT_TINY,
                temp.format("%d") + "°",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Rain probability
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, hourlyY2, Graphics.FONT_XTINY,
                (hRain[i] as Number).format("%d") + "%",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Mid separator ---
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((W * 0.1).toNumber(), (H * 0.41).toNumber() + yOff,
                    (W * 0.9).toNumber(), (H * 0.41).toNumber() + yOff);

        // --- Daily rows: 4 rows (Today, +1d, +2d, +3d) ---
        // 4 columns: day | temp | wind | rain — redistributed to fit within circular bezel.
        var xDay  = (W * 0.14).toNumber();
        var xTemp = (W * 0.38).toNumber();
        var xWind = (W * 0.57).toNumber();
        var xRain = (W * 0.86).toNumber();
        var rowYs = new Array<Number>[4];
        rowYs[0] = (H * 0.47).toNumber() + yOff;
        rowYs[1] = (H * 0.57).toNumber() + yOff;
        rowYs[2] = (H * 0.67).toNumber() + yOff;
        rowYs[3] = (H * 0.77).toNumber() + yOff;

        for (var i = 0; i < 4; i++) {
            var y = rowYs[i] as Number;

            // Day name — "Today" in white, others in gray
            dc.setColor((i == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(xDay, y, Graphics.FONT_XTINY,
                dNames[i] as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Max/min temp
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xTemp, y, Graphics.FONT_XTINY,
                (dMaxT[i] as Number).format("%d") + "/" + (dMinT[i] as Number).format("%d") + "°",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Wind speed + compass direction
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xWind, y, Graphics.FONT_XTINY,
                (dWind[i] as Float).format("%.0f") + windDirName((dDir[i] as Number).toFloat()),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Daily rain sum
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xRain, y, Graphics.FONT_XTINY,
                (dRain[i] as Float).format("%.1f") + "mm",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ---------------------------------------------------------------
    // Indicator dots
    // ---------------------------------------------------------------

    // Two dots at the bottom: left=GPS location, right=home location.
    // The active location's dot is filled white; the inactive dot is outlined dark gray.
    private function drawIndicator(dc as Dc, W as Number, H as Number) as Void {
        var r   = (W * 0.027).toNumber();
        var cy  = (H * 0.93).toNumber();
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
    var half   = size / 2.0f;
    var coords = [
        [ 0.0f,          half],
        [ size * 0.07f, -half * 0.50f],
        [ size * 0.30f, -half * 0.30f],
        [ 0.0f,         -half],
        [-size * 0.30f, -half * 0.30f],
        [-size * 0.07f, -half * 0.50f]
    ];
    var result = new Array<Graphics.Point2D>[coords.size()];
    var rad    = Math.toRadians(angle);
    var cos    = Math.cos(rad);
    var sin    = Math.sin(rad);
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
    if (d < 22.5f)  { return "N";  }
    if (d < 67.5f)  { return "NE"; }
    if (d < 112.5f) { return "E";  }
    if (d < 157.5f) { return "SE"; }
    if (d < 202.5f) { return "S";  }
    if (d < 247.5f) { return "SW"; }
    if (d < 292.5f) { return "W";  }
    if (d < 337.5f) { return "NW"; }
    return "N";
}
