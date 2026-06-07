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

    // GPS name is reverse-geocoded at runtime; this is the cold-start fallback.
    private var gpsLocationName as String = "GPS Location";

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
    // Reverse-geocoded home name; seeded from cached data and refreshed each fetch.
    private var homeLocationName as String = "Home";

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
        // Seed names from last geocoded results so the first draw is never "GPS Location" / "Home".
        if (gpsData  != null && gpsData.size()  > 5 && gpsData[5]  != null) { gpsLocationName  = gpsData[5]  as String; }
        if (homeData != null && homeData.size() > 5 && homeData[5]  != null) { homeLocationName = homeData[5] as String; }
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
            fetchLocationName(coords[0], coords[1], method(:onGpsLocationName));
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

    // Fetch weather and reverse-geocoded name for the user-configured home location.
    private function fetchHome() as Void {
        var lat = homeLat();
        var lon = homeLon();
        fetchWeather(lat, lon, method(:onHomeResponse));
        fetchLocationName(lat, lon, method(:onLocationName));
    }

    private function fetchLocationName(lat as Float or Double, lon as Float or Double, callback as Method) as Void {
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
            callback
        );
    }

    // Extracts the most specific place name from a Nominatim reverse-geocoding response.
    private function parseLocationName(data as Dictionary) as String? {
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
        return name as String?;
    }

    function onLocationName(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null) {
            var name = parseLocationName(data);
            if (name != null) {
                homeLocationName = name;
                if (homeData != null && homeData.size() > 5) {
                    homeData[5] = homeLocationName;
                    Storage.setValue("home_weather", homeData);
                    if (homeForecast != null && homeForecast.size() > 0) {
                        homeForecast[0] = homeLocationName;
                        Storage.setValue("home_forecast", homeForecast);
                    }
                    WatchUi.requestUpdate();
                }
            }
        }
    }

    function onGpsLocationName(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null) {
            var name = parseLocationName(data);
            if (name != null) {
                gpsLocationName = name;
                if (gpsData != null && gpsData.size() > 5) {
                    gpsData[5] = gpsLocationName;
                    Storage.setValue("gps_weather", gpsData);
                    if (gpsForecast != null && gpsForecast.size() > 0) {
                        gpsForecast[0] = gpsLocationName;
                        Storage.setValue("gps_forecast", gpsForecast);
                    }
                    WatchUi.requestUpdate();
                }
            }
        }
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

    function onPosition(info as Position.Info) as Void {
        gpsRequested = false;
        if (info != null && info.position != null) {
            var pos = info.position.toDegrees();
            Storage.setValue("gps_coords", pos);
            fetchWeather(pos[0], pos[1], method(:onGpsResponse));
            fetchLocationName(pos[0], pos[1], method(:onGpsLocationName));
        }
        WatchUi.requestUpdate();
    }

    function onGpsResponse(responseCode as Number, data as Dictionary?) as Void {
        System.println("[WeatherView] onGpsResponse: responseCode=" + responseCode);
        if (responseCode == 200 && data != null) {
            gpsData = parseWeather(data, gpsLocationName);
            Storage.setValue("gps_weather", gpsData);
            gpsForecast = parseForecast(data, gpsLocationName, gpsData);
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
            homeData = parseWeather(data, homeLocationName);
            Storage.setValue("home_weather", homeData);
            homeForecast = parseForecast(data, homeLocationName, homeData);
            Storage.setValue("home_forecast", homeForecast);
            WatchUi.requestUpdate();
        } else {
            System.println("[WeatherView] onHomeResponse: failed. data=" + (data != null ? "present" : "null"));
        }
    }

    // Returns [temp, feelsLike, windSpeed, windGust, windDeg, name, rain, weatherCode, isDay]
    // windSpeed and windGust are already in km/h from Open-Meteo (wind_speed_unit=kmh)
    private function parseWeather(data as Dictionary, name as String) as Array {
        var cur  = data["current"] as Dictionary;
        var gust = cur["wind_gusts_10m"];
        if (gust == null) { gust = cur["wind_speed_10m"]; } // gust not always reported
        var deg  = cur["wind_direction_10m"];
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

    // Returns a forecast array or null if data is missing.
    //
    // Structure:
    //   [0]  name       String
    //   [1]  hLabels    Array<String>[4]   hour labels: "Now", "Xp", ...
    //   [2]  hTemps     Array<Number>[4]   hourly temps °C
    //   [3]  hRainProb  Array<Number>[4]   hourly precipitation probability %
    //   [4]  dNames     Array<String>[5]   day labels: "Today", "Mon", ...
    //   [5]  dMaxT      Array<Number>[5]   daily max temp °C
    //   [6]  dMinT      Array<Number>[5]   daily min temp °C
    //   [7]  dWind      Array<Float>[5]    daily max wind km/h
    //   [8]  dDir       Array<Number>[5]   daily dominant wind direction degrees
    //   [9]  dRain      Array<Float>[5]    daily precipitation sum mm
    //   [10] dCond      Array<Number>[5]   daily WMO weather code
    //   [11] hWcode     Array<Number>[4]   hourly WMO weather code
    //   [12] hPrecip    Array<Float>[4]    hourly precipitation mm
    //   [13] hWindSpd   Array<Float>[4]    hourly wind speed km/h
    //   [14] hWindDir   Array<Number>[4]   hourly wind direction degrees
    //
    // Daily index 0=today, 1=tomorrow, ..., 4=+4d (5 days total).
    private function parseForecast(data as Dictionary, name as String, current as Array?) as Array? {
        var hourly = data["hourly"] as Dictionary?;
        var daily  = data["daily"]  as Dictionary?;
        if (hourly == null || daily == null) { return null; }

        var info        = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentHour = info.hour as Number;
        var hourIdx     = currentHour;

        var hourlyTemps   = hourly["temperature_2m"]            as Array;
        var hourlyWcode   = hourly["weather_code"]              as Array?;
        var hourlyPrecip  = hourly["precipitation"]             as Array?;
        var hourlyWSpd    = hourly["wind_speed_10m"]            as Array?;
        var hourlyWDir    = hourly["wind_direction_10m"]        as Array?;

        var hLabels   = new Array<String>[4];
        var hTemps    = new Array<Number>[4];
        var hWcode    = new Array<Number>[4];
        var hPrecip   = new Array<Float>[4];
        var hWindSpd  = new Array<Float>[4];
        var hWindDir  = new Array<Number>[4];

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
            hTemps[i]    = (i == 0 && current != null)
                ? Math.round(current[0] as Float).toNumber()
                : Math.round(hourlyTemps[idx] as Float).toNumber();
            hWcode[i]    = (hourlyWcode  != null && hourlyWcode[idx]   != null) ? (hourlyWcode[idx]  as Number) : 0;
            hPrecip[i]   = (hourlyPrecip != null && hourlyPrecip[idx]  != null) ? (hourlyPrecip[idx] as Float)  : 0.0f;
            hWindSpd[i]  = (hourlyWSpd   != null && hourlyWSpd[idx]    != null) ? (hourlyWSpd[idx]   as Float)  : 0.0f;
            hWindDir[i]  = (hourlyWDir   != null && hourlyWDir[idx]    != null) ? (hourlyWDir[idx]   as Number) : 0;
        }

        var dailyMax  = daily["temperature_2m_max"]          as Array;
        var dailyMin  = daily["temperature_2m_min"]          as Array;
        var dailyWind = daily["wind_speed_10m_max"]          as Array;
        var dailyDir  = daily["wind_direction_10m_dominant"] as Array;
        var dailyRain = daily["precipitation_sum"]           as Array;
        var dailyCond = daily["weather_code"]                as Array?;

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

        return [name, hLabels, hTemps, null, dNames, dMaxT, dMinT, dWind, dDir, dRain,
                dCond, hWcode, hPrecip, hWindSpd, hWindDir] as Array;
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
            drawHourlyPage(dc, W, H);
        } else if (pageIndex == 2) {
            drawDailyPage(dc, W, H);
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

    // Layout: three sectors divided by clock-hand lines.
    //   Top semicircle  (9→12→3)  : location name, H, current temp, L, feels-like
    //   Bottom-right quadrant (3→6): wind speed, gust + direction
    //   Bottom-left  quadrant (6→9): rain amount + probability
    private function drawWeather(dc as Dc, W as Number, H as Number, w as Array) as Void {
        var temp  = Math.round(w[0] as Float).toNumber();
        var feels = Math.round(w[1] as Float).toNumber();
        var speed = (w[2] as Float);
        var gust  = (w[3] as Float);
        var wdeg  = (w[4] as Number or Float).toFloat();
        var name  = w[5] as String;
        var rain  = w.size() > 6 ? (w[6] as Float) : 0.0f;

        // Pull rain probability and today's H/L from the forecast cache.
        var forecast = locationIndex == 0 ? gpsForecast : homeForecast;
        var rainProb = 0;
        var highTemp = temp;
        var lowTemp  = temp;
        if (forecast != null) {
            var hRain = forecast[3] as Array?;
            if (hRain != null && hRain.size() > 0) { rainProb = hRain[0] as Number; }
            var dMaxT = forecast[5] as Array?;
            var dMinT = forecast[6] as Array?;
            if (dMaxT != null && dMaxT.size() > 0) { highTemp = dMaxT[0] as Number; }
            if (dMinT != null && dMinT.size() > 0) { lowTemp  = dMinT[0] as Number; }
        }

        var cx = W / 2;
        var cy = H / 2;

        // ── Radial dividing lines ────────────────────────────────────
        // Three lines at 2:30 (75°), 6:00 (180°), 9:30 (285°) clock positions.
        // Creates temp sector (9:30→2:30 through 12) and two lower sectors.
        // sin(75°)=0.966, cos(75°)=0.259; circR=30, R=92% half-width.
        var R    = (W * 0.46f).toNumber();
        var dx   = (R  * 0.966f).toNumber();
        var dy   = (R  * 0.259f).toNumber();
        var gapX = (30 * 0.966f).toNumber();
        var gapY = (30 * 0.259f).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx + gapX, cy - gapY, cx + dx,  cy - dy); // 2:30 (75°)
        dc.drawLine(cx,        cy + 30,   cx,        cy + R);  // 6:00 (180°)
        dc.drawLine(cx - gapX, cy - gapY, cx - dx,  cy - dy); // 9:30 (285°)

        // ── TOP SEMICIRCLE: Temperature ──────────────────────────────
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (H * 0.10).toNumber(), Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Current temp — FONT_NUMBER_MEDIUM digits-only; °C as superscript.
        // H: and L: are drawn flanking the temp block at the same baseline.
        var tempStr = temp.format("%d");
        var numW    = dc.getTextWidthInPixels(tempStr, Graphics.FONT_NUMBER_MEDIUM);
        var unitW   = dc.getTextWidthInPixels("°C", Graphics.FONT_SMALL);
        var numX    = (W - numW - unitW) / 2;
        var numY    = (H * 0.25).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(numX - 6, numY, Graphics.FONT_TINY,
            "H:" + highTemp.format("%d") + "°",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(numX + numW + unitW + 6, numY, Graphics.FONT_TINY,
            "L:" + lowTemp.format("%d") + "°",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(numX, numY, Graphics.FONT_NUMBER_MEDIUM,
            tempStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(numX + numW + 2, numY - (H * 0.05).toNumber(), Graphics.FONT_SMALL,
            "°C", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── CENTRE: Condition icon in a dark charcoal circle ─────────
        var wcode  = w.size() > 7 ? (w[7] as Number) : 0;
        var isDay  = w.size() > 8 ? (w[8] as Number) != 0 : true;
        var icon   = wmoIcon(wcode, isDay);
        var iW     = icon.getWidth();
        var iH     = icon.getHeight();
        var circR  = (iW > iH ? iW : iH) / 2 + 8;
        dc.setColor(0x1E1E1E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, circR);
        dc.setColor(0x484848, Graphics.COLOR_TRANSPARENT);
        // Arc from 2:30 to 9:30 through 6 — Garmin angles: 0°=right, CCW positive.
        // 2:30 clock (75° from top) = Garmin 15°; 9:30 clock (285°) = Garmin 165°.
        // CLOCKWISE from 15→0→270→165 sweeps through 6 o'clock (bottom).
        dc.drawArc(cx, cy, circR, Graphics.ARC_CLOCKWISE, 15, 165);
        dc.drawBitmap(cx - iW / 2, cy - iH / 2, icon);

        // Drawn after the circle so it renders on top — sits just above the icon.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (H * 0.37).toNumber(), Graphics.FONT_XTINY,
            "Feels " + feels.format("%d") + "°C",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── BOTTOM-LEFT QUADRANT (6→9): Rain ─────────────────────────
        // Centre of quadrant is at roughly (W*0.25, H*0.73).
        var rainX = (W * 0.25).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText((W * 0.06).toNumber(), (H * 0.58).toNumber() - 5, Graphics.FONT_TINY, "RAIN",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rainX, (H * 0.68).toNumber(), Graphics.FONT_SMALL,
            rain.format("%.1f") + " mm",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rainX, (H * 0.77).toNumber(), Graphics.FONT_XTINY,
            "prob " + rainProb.format("%d") + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── BOTTOM-RIGHT QUADRANT (3→6): Wind ────────────────────────
        // Centre of quadrant is at roughly (W*0.75, H*0.73).
        var windX = (W * 0.75).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText((W * 0.94).toNumber(), (H * 0.58).toNumber() - 5, Graphics.FONT_TINY, "WIND",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(windX, (H * 0.68).toNumber(), Graphics.FONT_SMALL,
            speed.format("%.0f") + " km/h",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(windX, (H * 0.77).toNumber(), Graphics.FONT_XTINY,
            "gust " + gust.format("%.0f") + "  " + windDirName(wdeg),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------
    // Screen 2 — Hourly forecast (4 columns: Now +1h +2h +3h)
    // ---------------------------------------------------------------

    private function drawHourlyPage(dc as Dc, W as Number, H as Number) as Void {
        var forecast = locationIndex == 0 ? gpsForecast : homeForecast;
        if (forecast == null) { drawCentered(dc, W, H, "Loading\nforecast..."); return; }

        var name     = forecast[0]  as String;
        var hLabels  = forecast[1]  as Array;
        var hTemps   = forecast[2]  as Array;
        var hWcode   = forecast.size() > 11 ? forecast[11] as Array? : null;
        var hPrecip   = forecast.size() > 12 ? forecast[12] as Array? : null;
        var hWindSpd  = forecast.size() > 13 ? forecast[13] as Array? : null;
        var hWindDir  = forecast.size() > 14 ? forecast[14] as Array? : null;

        var yOff = 4;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, (H * 0.07).toNumber() + yOff, Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((W * 0.22).toNumber(), (H * 0.13).toNumber() + yOff,
                    (W * 0.78).toNumber(), (H * 0.13).toNumber() + yOff);

        // 4 columns pulled inward to clear the circular bezel at the bottom rows
        var colX = new Array<Number>[4];
        colX[0] = (W * 0.18).toNumber();
        colX[1] = (W * 0.38).toNumber();
        colX[2] = (W * 0.62).toNumber();
        colX[3] = (W * 0.82).toNumber();

        var yLabel = (H * 0.16).toNumber() + yOff;
        var yIcon  = (H * 0.27).toNumber() + yOff;
        var yTemp  = (H * 0.40).toNumber() + yOff;
        var yPrec  = (H * 0.52).toNumber() + yOff;
        var yWind  = (H * 0.63).toNumber() + yOff;
        var yDir   = (H * 0.74).toNumber() + yOff;

        for (var i = 0; i < 4; i++) {
            var cx = colX[i] as Number;

            // Hour label
            dc.setColor((i == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yLabel, Graphics.FONT_TINY,
                hLabels[i] as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Condition icon — use current hour's is_day for "Now", daytime for rest
            var wcode  = (hWcode != null) ? (hWcode[i] as Number) : 0;
            var isDay  = true;
            var rowIcon = wmoIconSm(wcode, isDay);
            dc.drawBitmap(cx - rowIcon.getWidth() / 2, yIcon - rowIcon.getHeight() / 2, rowIcon);

            // Temperature
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yTemp, Graphics.FONT_TINY,
                (hTemps[i] as Number).format("%d") + "°",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Precipitation mm
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            var precip = (hPrecip != null) ? (hPrecip[i] as Float) : 0.0f;
            dc.drawText(cx, yPrec, Graphics.FONT_XTINY,
                precip.format("%.1f") + "mm",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Wind speed then direction on separate lines
            var wspd = (hWindSpd != null) ? (hWindSpd[i] as Float) : 0.0f;
            var wdir = (hWindDir != null) ? (hWindDir[i] as Number).toFloat() : 0.0f;
            dc.drawText(cx, yWind, Graphics.FONT_XTINY,
                wspd.format("%.0f") + "km",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, yDir, Graphics.FONT_XTINY,
                windDirName(wdir),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ---------------------------------------------------------------
    // Screen 3 — Daily forecast (5 days, centred vertically)
    // ---------------------------------------------------------------

    private function drawDailyPage(dc as Dc, W as Number, H as Number) as Void {
        var forecast = locationIndex == 0 ? gpsForecast : homeForecast;
        if (forecast == null) { drawCentered(dc, W, H, "Loading\nforecast..."); return; }

        var name   = forecast[0]  as String;
        var dNames = forecast[4]  as Array;
        var dMaxT  = forecast[5]  as Array;
        var dMinT  = forecast[6]  as Array;
        var dRain  = forecast[9]  as Array;
        var dCond  = forecast.size() > 10 ? forecast[10] as Array? : null;

        var yOff = 4;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(W / 2, (H * 0.07).toNumber() + yOff, Graphics.FONT_TINY,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((W * 0.22).toNumber(), (H * 0.13).toNumber() + yOff,
                    (W * 0.78).toNumber(), (H * 0.13).toNumber() + yOff);

        // 5 rows evenly spaced from H*0.20 to H*0.88, centred on screen
        var xDay  = (W * 0.10).toNumber();
        var xIcon = (W * 0.36).toNumber();
        var xTemp = (W * 0.62).toNumber() - 5;
        var xRain = (W * 0.88).toNumber();
        var rowYs = new Array<Number>[5];
        rowYs[0] = (H * 0.20).toNumber() + yOff;
        rowYs[1] = (H * 0.34).toNumber() + yOff;
        rowYs[2] = (H * 0.48).toNumber() + yOff;
        rowYs[3] = (H * 0.62).toNumber() + yOff;
        rowYs[4] = (H * 0.76).toNumber() + yOff;

        for (var i = 0; i < 5; i++) {
            var y = rowYs[i] as Number;

            dc.setColor((i == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(xDay, y, Graphics.FONT_XTINY,
                dNames[i] as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            if (dCond != null) {
                var rowIcon = wmoIconSm(dCond[i] as Number, true);
                dc.drawBitmap(xIcon - rowIcon.getWidth() / 2, y - rowIcon.getHeight() / 2, rowIcon);
            }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xTemp, y, Graphics.FONT_XTINY,
                (dMaxT[i] as Number).format("%d") + "/" + (dMinT[i] as Number).format("%d") + "°",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

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
