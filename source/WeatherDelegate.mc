import Toybox.Lang;
import Toybox.WatchUi;

// Handles button input for the main weather view.
// SELECT toggles between GPS and home location (applies to both pages).
// UP/DOWN toggles between current conditions and forecast for the active location.
// MENU forces an immediate data refresh.
class WeatherDelegate extends WatchUi.BehaviorDelegate {

    private var view as WeatherView;

    function initialize(view as WeatherView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    // UP button or swipe up: toggle between current conditions and forecast
    function onNextPage() as Boolean {
        view.pageIndex = view.pageIndex == 0 ? 1 : 0;
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN button or swipe down: toggle between current conditions and forecast
    function onPreviousPage() as Boolean {
        view.pageIndex = view.pageIndex == 0 ? 1 : 0;
        WatchUi.requestUpdate();
        return true;
    }

    // SELECT: toggle between GPS location and home location (on either page)
    function onSelect() as Boolean {
        view.locationIndex = view.locationIndex == 0 ? 1 : 0;
        WatchUi.requestUpdate();
        return true;
    }

    // MENU button: force an immediate weather refresh for both locations
    function onMenu() as Boolean {
        view.fetchAll();
        return true;
    }
}
