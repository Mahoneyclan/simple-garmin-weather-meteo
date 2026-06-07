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

    // UP button or swipe up: advance page 0→1→2→0
    function onNextPage() as Boolean {
        view.pageIndex = (view.pageIndex + 1) % 3;
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN button or swipe down: retreat page 0→2→1→0
    function onPreviousPage() as Boolean {
        view.pageIndex = (view.pageIndex + 2) % 3;
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
