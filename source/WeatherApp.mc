import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Entry point for the widget. Owns the background schedule and routes
// background results into persistent Storage for WeatherView to consume.
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

    // Receives [gpsWeather, homeWeather, gpsForecast, homeForecast] from BackgroundService
    // and persists each to Storage so WeatherView can display them on next draw.
    function onBackgroundData(data as Application.PersistableType) as Void {
        var result = data as Array;
        if (result == null || result.size() < 2) {
            return;
        }
        var gps         = result[0] as Array?;
        var home        = result[1] as Array?;
        var gpsFcast    = result.size() > 2 ? result[2] as Array? : null;
        var homeFcast   = result.size() > 3 ? result[3] as Array? : null;
        if (gps != null)      { Storage.setValue("gps_weather",   gps); }
        if (home != null)     { Storage.setValue("home_weather",  home); }
        if (gpsFcast != null) { Storage.setValue("gps_forecast",  gpsFcast); }
        if (homeFcast != null){ Storage.setValue("home_forecast", homeFcast); }
        WatchUi.requestUpdate();
    }

    // Re-schedule background and refresh the view when the user changes settings
    // in Garmin Connect (e.g. refresh rate or home location coordinates).
    // fetchAll() is called so the new coordinates are geocoded immediately —
    // a plain requestUpdate() only redraws and would leave the stale cached name.
    function onSettingsChanged() as Void {
        scheduleBackground();
        if (mainView != null) {
            mainView.fetchAll();
            WatchUi.requestUpdate();
        }
    }

    // Register a recurring background fetch at the user-configured interval.
    // deleteTemporalEvent must be called first — registering a second event
    // without deleting the previous one is a runtime error on device.
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
