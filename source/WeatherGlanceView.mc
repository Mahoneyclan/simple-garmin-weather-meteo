import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Glance strip: two columns separated by a vertical divider.
// Left  = Home location   Right = GPS location
// Each column shows a condition-coloured dot + temperature.
// No bitmap loading — dc.drawBitmap() is not available in glance context.
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

        var home = Storage.getValue("home_weather") as Array?;
        var gps  = Storage.getValue("gps_weather")  as Array?;

        // Vertical centre divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(W / 2, 0, W / 2, H);

        drawColumn(dc, W, H, home, W / 4);      // left: Home
        drawColumn(dc, W, H, gps,  W * 3 / 4);  // right: GPS
    }

    private function drawColumn(dc as Dc, W as Number, H as Number,
                                data as Array?, cx as Number) as Void {
        if (data == null || data.size() < 8) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, H / 2, Graphics.FONT_XTINY, "--",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var wcode = data[7] as Number;
        var temp  = Math.round(data[0] as Float).toNumber();
        var name  = data[5] as String;

        // Location name — centred, upper third
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (H * 0.22).toNumber(), Graphics.FONT_XTINY, name,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Condition dot — colour encodes weather category
        var dotR = H / 5;
        dc.setColor(conditionColor(wcode), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - dotR - 3, (H * 0.65).toNumber(), dotR);

        // Temperature
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 3, (H * 0.65).toNumber(), Graphics.FONT_SMALL,
            temp.format("%d") + "°",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Returns a colour representing the weather category for the given WMO code.
    private function conditionColor(code as Number) as Number {
        if (code <= 1)                          { return 0xFFCC00; }  // clear — yellow
        if (code <= 3)                          { return 0xAAAAAA; }  // cloudy — grey
        if (code <= 48)                         { return 0x888888; }  // fog — dark grey
        if (code <= 67)                         { return 0x4488FF; }  // rain/drizzle — blue
        if (code <= 77)                         { return 0xCCEEFF; }  // snow — light blue
        if (code <= 82)                         { return 0x2266CC; }  // showers — deep blue
        if (code <= 86)                         { return 0xCCEEFF; }  // snow showers — light blue
        return 0x9933CC;                                              // thunder — purple
    }
}
