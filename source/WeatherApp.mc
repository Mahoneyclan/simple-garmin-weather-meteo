import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

(:glance, :background)
class WeatherApp extends Application.AppBase {

    private var mainView as WeatherView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        mainView = new WeatherView();
        scheduleBackground();
        return [ mainView, new WeatherDelegate(mainView) ];
    }

    function getGlanceView() as [ WatchUi.GlanceView ] or [ WatchUi.GlanceView, WatchUi.GlanceViewDelegate ] or Null {
        return [ new WeatherGlanceView() ];
    }

    function getServiceDelegate() as [ Toybox.System.ServiceDelegate ] {
        return [ new BackgroundService() ];
    }

    // Receives [gpsWeather, samfordWeather] arrays from BackgroundService
    function onBackgroundData(data as Application.PersistableType) as Void {
        var result = data as Array;
        if (result == null || result.size() < 2) {
            return;
        }
        var gps = result[0] as Array?;
        var samford = result[1] as Array?;
        if (gps != null) {
            Storage.setValue("gps_weather", gps);
        }
        if (samford != null) {
            Storage.setValue("samford_weather", samford);
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        scheduleBackground();
        if (mainView != null) {
            WatchUi.requestUpdate();
        }
    }

    private function scheduleBackground() as Void {
        Background.deleteTemporalEvent();
        var rate = Properties.getValue("refresh_rate") as Number?;
        if (rate == null) { rate = 30; }
        Background.registerForTemporalEvent(new Time.Duration(rate * 60));
    }
}

function getApp() as WeatherApp {
    return Application.getApp() as WeatherApp;
}
