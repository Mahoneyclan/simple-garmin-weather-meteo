import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

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

        var gps = Storage.getValue("gps_weather") as Array?;
        if (gps != null && gps.size() >= 6) {
            var temp = Math.round(gps[0] as Float).toNumber();
            var name = gps[5] as String;

            // Location name — top line
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (H * 0.10).toNumber(), Graphics.FONT_TINY,
                name, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Temperature — large
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (H * 0.55).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                temp.format("%d") + "°C", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Wind speed (already km/h from Open-Meteo) + direction
            var speed = (gps[2] as Float).format("%.0f");
            var wdeg  = (gps[4] as Number or Float).toFloat();
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W - 2, (H * 0.55).toNumber(), Graphics.FONT_TINY,
                speed + "km/h\n" + windDirName(wdeg),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(W / 2, H / 2, Graphics.FONT_SMALL, "Weather",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
