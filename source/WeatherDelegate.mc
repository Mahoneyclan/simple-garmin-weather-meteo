import Toybox.Lang;
import Toybox.WatchUi;

class WeatherDelegate extends WatchUi.BehaviorDelegate {

    private var view as WeatherView;

    function initialize(view as WeatherView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    // Up/down button or swipe: toggle between GPS and Samford Valley
    function onNextPage() as Boolean {
        toggle();
        return true;
    }

    function onPreviousPage() as Boolean {
        toggle();
        return true;
    }

    // Select button also toggles
    function onSelect() as Boolean {
        toggle();
        return true;
    }

    // MENU button: force refresh
    function onMenu() as Boolean {
        view.fetchAll();
        return true;
    }

    private function toggle() as Void {
        view.locationIndex = view.locationIndex == 0 ? 1 : 0;
        WatchUi.requestUpdate();
    }
}
