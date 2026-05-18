import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Compact glance shown on the watch-face glance screen.
// Displays GPS location temperature and wind only — home location is omitted
// because glance space is too small to show both.
(:glance)
class WeatherGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        GlanceView.onUpdate(dc);
        var W = dc.getWidth();
        var H = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Read the last cached GPS weather written by WeatherView or BackgroundService.
        var gps = Storage.getValue("gps_weather") as Array?;
        if (gps != null && gps.size() >= 6) {
            var temp = Math.round(gps[0] as Float).toNumber();
            var name = gps[5] as String;

            // Location name — top line
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (H * 0.10).toNumber(), Graphics.FONT_TINY,
                name, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Temperature — large, left-aligned
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (H * 0.55).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                temp.format("%d") + "°C", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Rain + wind speed + compass, stacked right-aligned
            var speed = (gps[2] as Float).format("%.0f");
            var wdeg  = (gps[4] as Number or Float).toFloat();
            var rain  = gps.size() > 6 ? (gps[6] as Float).format("%.1f") + "mm" : "0.0mm";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W - 2, (H * 0.55).toNumber(), Graphics.FONT_TINY,
                rain + "\n" + speed + "km/h " + windDirName(wdeg),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // No cached data yet — show placeholder until first fetch completes
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W / 2, H / 2, Graphics.FONT_SMALL, "Weather",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
